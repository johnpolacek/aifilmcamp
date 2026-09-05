import Foundation
import GRDB

// PHASE3_DESIGN §7.2's six prompt operations (Plan 014 contract B), in the house shape:
// `MutationEffect`-returning statics that open no transaction (§7.1) — the caller's
// transaction is the one that counts, and the reentrancy test's `Editing/*.swift` glob
// covers this file automatically (§3.8).
//
// Shared discipline, per §7.4: every operation resolves its requirement and calls
// `LockPolicy.requireRequirementUnlocked` before mutating — the new subject kinds are
// deliberately not lockable, so a subject-keyed check would see nothing — and **the
// requirement joins each operation's affected set**.
//
// `AssetStatusRecompute` stays the only writer of `assets.status`; the ops run it at the
// end and fold `Applied.affected` into their own.

enum PromptOperations {

    // MARK: - Body validation (§7.2)

    /// Non-empty, ≤ 32 KB UTF-8, control-character-free other than newline and tab —
    /// create and edit share one rule (§8.3's semantic validator spells the same limits
    /// for AI output; these are the storage-side guards).
    static func validateBody(_ body: String) throws {
        guard !body.isEmpty else {
            throw ProjectStoreError.assetOperationRefused(reason: "A prompt cannot be empty.")
        }
        guard body.utf8.count <= 32 * 1024 else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "A prompt cannot be larger than 32 KB."
            )
        }
        let forbidden = body.unicodeScalars.contains { scalar in
            scalar.value < 0x20 && scalar != "\n" && scalar != "\t"
        }
        guard !forbidden else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "A prompt cannot contain control characters."
            )
        }
    }

    // MARK: - Preconditions (§5.8's two separate checks; §7.4's lock guard)

    /// Accepted is its own check with its own refusal (§13.10): review first, then work.
    static func requireAccepted(_ requirement: RequirementRow, in db: Database) throws {
        guard requirement.reviewState == .accepted else {
            throw ProjectStoreError.promptRequiresAcceptedRequirement
        }
    }

    static func requireActive(requirementID: UUID, in db: Database) throws {
        guard try AssetOperations.isActive(requirementID: requirementID, in: db) else {
            throw ProjectStoreError.requirementInactive(requirementID: requirementID)
        }
    }

    /// The unsatisfied active dependencies' names, for the blocked refusal's first entry.
    static func generationBlockers(
        requirementID: UUID, in db: Database
    ) throws -> [String] {
        try db.execute(sql: "PRAGMA foreign_keys = ON")
        let graph = try ProjectRepository.manifestGraph(in: db)
        return graph.unsatisfiedDependencies(of: requirementID).compactMap { targetID in
            graph.requirements[targetID].map(\.name)
        }
    }

    // MARK: - Row helpers

    struct RequirementRow {
        let id: UUID
        let projectID: UUID
        let reviewState: ReviewState
        var ref: SubjectRef { SubjectRef(kind: .requirement, id: id) }
    }

    static func requireRequirement(id: UUID, in db: Database) throws -> RequirementRow {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT id, project_id, review_state FROM asset_requirements WHERE id = ?",
            arguments: [id.uuidString]
        ) else { throw ProjectStoreError.requirementNotFound }
        guard let reviewState = ReviewState(rawValue: row["review_state"]) else {
            throw ProjectStoreError.invalidBundle
        }
        return RequirementRow(
            id: try UUID.required(row["id"]),
            projectID: try UUID.required(row["project_id"]),
            reviewState: reviewState
        )
    }

    struct PromptRow {
        let id: UUID
        let projectID: UUID
        let requirementID: UUID
        let promptNumber: Int
        var ref: SubjectRef { SubjectRef(kind: .prompt, id: id) }
    }

    static func requirePrompt(id: UUID, in db: Database) throws -> PromptRow {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT id, project_id, requirement_id, prompt_number FROM asset_prompts WHERE id = ?",
            arguments: [id.uuidString]
        ) else { throw ProjectStoreError.promptNotFound }
        return PromptRow(
            id: try UUID.required(row["id"]),
            projectID: try UUID.required(row["project_id"]),
            requirementID: try UUID.required(row["requirement_id"]),
            promptNumber: row["prompt_number"]
        )
    }

    /// §7.2's pinned walk: max + 1, in-transaction. Gaps are legal after deletes; deleting
    /// the newest frees its number for the next create.
    static func nextPromptNumber(requirementID: UUID, in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(prompt_number), 0) + 1 FROM asset_prompts WHERE requirement_id = ?",
            arguments: [requirementID.uuidString]
        ) ?? 1
    }

    /// The current prompt is the highest number (§3.2) — the only row a body edit may touch.
    static func requireCurrentPrompt(id: UUID, in db: Database) throws -> PromptRow {
        let prompt = try requirePrompt(id: id, in: db)
        let currentID = try String.fetchOne(
            db,
            sql: """
                SELECT id FROM asset_prompts WHERE requirement_id = ?
                ORDER BY prompt_number DESC LIMIT 1
                """,
            arguments: [prompt.requirementID.uuidString]
        )
        guard currentID == id.uuidString else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "Only the current prompt can be edited; earlier prompts are history."
            )
        }
        return prompt
    }

    /// The asset row behind a requirement, when one exists.
    static func assetID(ofRequirement requirementID: UUID, in db: Database) throws -> UUID? {
        try AssetOperations.asset(ofRequirement: requirementID, in: db)?.id
    }

    // MARK: - createPrompt (§7.2)

    static func createPrompt(
        id: UUID,
        requirementID: UUID,
        body: String,
        targetModel: String,
        restoring: [RowSnapshot],
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        try validateBody(body)
        if !restoring.isEmpty {
            // Redo: byte-identical, the recompute's status included (the createAsset shape).
            try RowGraph.restore(restoring, in: db)
            return MutationEffect(
                inverse: .deletePrompt(promptID: id),
                affected: [
                    SubjectRef(kind: .prompt, id: id),
                    SubjectRef(kind: .requirement, id: requirementID),
                ],
                snapshots: []
            )
        }

        let requirement = try requireRequirement(id: requirementID, in: db)
        try RequirementOperations.requireHuman(actor, subject: requirement.ref)
        try requireAccepted(requirement, in: db)
        try requireActive(requirementID: requirementID, in: db)
        try LockPolicy.requireRequirementUnlocked(requirementID: requirementID, in: db)

        // §7.2: the digest hashes inputs, not the body — computed in-transaction.
        let snapshot = try AssetPromptInputBuilder.snapshot(requirementID: requirementID, in: db)
        let number = try nextPromptNumber(requirementID: requirementID, in: db)
        let timestamp = UTCDate.string(from: Date())
        var arguments: StatementArguments = [
            id.uuidString, requirement.projectID.uuidString, requirementID.uuidString,
            number, body, targetModel, "", "", "", "",
            snapshot.digest, AssetPromptInputBuilder.schemaVersion,
        ]
        arguments += RequirementOperations.insertProvenance(actor, timestamp: timestamp)
        try db.execute(
            sql: """
                INSERT INTO asset_prompts (
                    id, project_id, requirement_id, prompt_number, body,
                    target_model, guidance, skill_id, skill_entry_path,
                    skill_entry_sha256, input_digest, input_format_version,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: arguments
        )
        let applied = try AssetOperations.recompute(requirementID: requirementID, in: db)
        return MutationEffect(
            inverse: .deletePrompt(promptID: id),
            affected: Set([
                SubjectRef(kind: .prompt, id: id),
                SubjectRef(kind: .requirement, id: requirementID),
            ]).union(applied.affected),
            snapshots: []
        )
    }

    // MARK: - attachGeneratedPrompt (§3.7, §8.4 step 2)

    /// The engine-internal apply op. Fixed `ai` provenance on its own inserts — never the
    /// shared `insertProvenance`, which births `.ai` rows `proposed`, while a prompt is
    /// output, not a reviewable fact (born `accepted`, inert PROV). Citations are derived
    /// here from §3.3's shared ordering over the rendered references — ordering,
    /// numbering, and capture live in the operation, never the applier (Plan 014).
    static func attachGeneratedPrompt(
        promptID: UUID,
        assetID: UUID,
        requirementID: UUID,
        body: String,
        targetModel: String,
        guidance: String,
        inputDigest: String,
        inputFormatVersion: Int,
        skillIdentity: AssetPromptSkillIdentity,
        actor: MutationActor,
        mode: MutationMode = .apply,
        in db: Database
    ) throws -> MutationEffect {
        try validateBody(body)
        // Redo of a generate (§13.11): the undo entry's snapshots restore byte-identically,
        // never through the gesture guards — the `createPrompt(restoring:)` pattern.
        if let invertedEntry = mode.invertedEntry {
            try RowGraph.restore(invertedEntry.snapshots, in: db)
            let payload = Self.payload(
                requirementID: requirementID, snapshots: invertedEntry.snapshots
            )
            var affected: Set<SubjectRef> = [
                SubjectRef(kind: .prompt, id: promptID),
                SubjectRef(kind: .requirement, id: requirementID),
            ]
            affected.formUnion(RowGraph.subjects(of: invertedEntry.snapshots))
            return MutationEffect(
                inverse: .removeAttachedPrompt(payload: payload),
                affected: affected,
                snapshots: []
            )
        }
        guard case .ai = actor else {
            // The human paths compose the shipped human-only ops; this case is the AI
            // actor's alone (§3.7).
            throw ProjectStoreError.protectedFact(subject: SubjectRef(kind: .requirement, id: requirementID))
        }
        let requirement = try requireRequirement(id: requirementID, in: db)
        try requireAccepted(requirement, in: db)
        try requireActive(requirementID: requirementID, in: db)
        try LockPolicy.requireRequirementUnlocked(requirementID: requirementID, in: db)
        // §8.4 step 1: blockage is digest-covered except through this gate's own read;
        // the refusal names the first entry of `generationBlockedBy` (§5.8).
        let blockers = try generationBlockers(requirementID: requirementID, in: db)
        if let first = blockers.first {
            throw ProjectStoreError.promptRequirementBlocked(dependencyName: first)
        }

        let existingAsset = try AssetOperations.asset(ofRequirement: requirementID, in: db)
        let composedAsset = existingAsset == nil
        let resolvedAssetID = existingAsset?.id ?? assetID
        if composedAsset {
            // §6.1's anchor: the first prompt composes the asset row itself, with fixed
            // `ai` provenance — the shipped `createAsset` is human-only and is not on
            // this path (§3.7).
            let timestamp = UTCDate.string(from: Date())
            try db.execute(
                sql: """
                    INSERT INTO assets (
                        id, project_id, requirement_id, status, is_stale, stale_since,
                        stale_reason, rejected_explicitly, notes,
                        source, confidence, review_state, reviewed_at, job_id,
                        created_source, created_at, updated_at
                    ) VALUES (?, ?, ?, 'needed', 0, NULL, NULL, 0, '',
                              'ai', NULL, 'accepted', NULL, ?, 'ai', ?, ?)
                    """,
                arguments: [
                    resolvedAssetID.uuidString, requirement.projectID.uuidString,
                    requirementID.uuidString,
                    actor.jobID?.uuidString, timestamp, timestamp,
                ]
            )
        }

        let number = try nextPromptNumber(requirementID: requirementID, in: db)
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO asset_prompts (
                    id, project_id, requirement_id, prompt_number, body,
                    target_model, guidance, skill_id, skill_entry_path,
                    skill_entry_sha256, input_digest, input_format_version,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                          'ai', NULL, 'accepted', NULL, ?, 'ai', ?, ?)
                """,
            arguments: [
                promptID.uuidString, requirement.projectID.uuidString, requirementID.uuidString,
                number, body, targetModel, guidance,
                skillIdentity.id, skillIdentity.entryPath, skillIdentity.entrySHA256,
                inputDigest, inputFormatVersion,
                actor.jobID?.uuidString, timestamp, timestamp,
            ]
        )

        // Citations: §3.3's rendered references — the satisfied subset, densely numbered,
        // capturing sha256 and display name at build time. Derived from the same shared
        // function the reads and builder use; the recorded values are immutable history.
        let graph = try ProjectRepository.manifestGraph(in: db)
        guard let requirementRow = graph.requirements[requirementID] else {
            throw ProjectStoreError.requirementNotFound
        }
        let planned = try AssetPromptInputBuilder.plannedDependencies(
            of: requirementRow, graph: graph, in: db
        )
        var citationRows: [RowSnapshot] = []
        for dependency in planned {
            guard dependency.isSatisfied, let designator = dependency.designator,
                  let approved = dependency.approvedVersion
            else { continue }
            let citationID = UUID()
            try db.execute(
                sql: """
                    INSERT INTO asset_prompt_references (
                        id, prompt_id, position, requirement_id, version_id,
                        class, role, exclusion, fidelity, sha256, display_name,
                        source, job_id, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                              'ai', ?, ?)
                    """,
                arguments: [
                    citationID.uuidString, promptID.uuidString, designator,
                    dependency.requirementID.uuidString, approved.versionID.uuidString,
                    dependency.class.rawValue, dependency.attributes.role,
                    dependency.attributes.exclusion, dependency.attributes.fidelity.rawValue,
                    approved.sha256,
                    "\(dependency.entityName) — \(dependency.requirementName)",
                    actor.jobID?.uuidString, timestamp,
                ]
            )
            if let snapshot = try RowSnapshotStore.capture(
                table: "asset_prompt_references", id: citationID, in: db
            ) {
                citationRows.append(snapshot)
            }
        }

        let applied = try AssetOperations.recompute(requirementID: requirementID, in: db)
        let payload = GeneratedPromptPayload(
            requirementID: requirementID,
            assetRow: composedAsset
                ? try RowSnapshotStore.capture(table: "assets", id: resolvedAssetID, in: db)
                : nil,
            promptRow: try RowSnapshotStore.capture(table: "asset_prompts", id: promptID, in: db)
                ?? RowSnapshot(table: "asset_prompts", columns: [:]),
            citationRows: citationRows
        )
        var affected: Set<SubjectRef> = [
            SubjectRef(kind: .prompt, id: promptID),
            SubjectRef(kind: .requirement, id: requirementID),
        ]
        affected.formUnion(citationRows.compactMap { snapshot -> SubjectRef? in
            guard case let .string(raw)? = snapshot.columns["id"], let id = UUID(uuidString: raw)
            else { return nil }
            return SubjectRef(kind: .promptReference, id: id)
        })
        if composedAsset { affected.insert(SubjectRef(kind: .asset, id: resolvedAssetID)) }
        affected.formUnion(applied.affected)
        return MutationEffect(
            inverse: .removeAttachedPrompt(payload: payload),
            affected: affected,
            snapshots: []
        )
    }

    /// Rebuilds a `GeneratedPromptPayload` from captured row snapshots — the redo path's
    /// inverse needs the same shape the apply recorded.
    private static func payload(
        requirementID: UUID, snapshots: [RowSnapshot]
    ) -> GeneratedPromptPayload {
        GeneratedPromptPayload(
            requirementID: requirementID,
            assetRow: snapshots.first { $0.table == "assets" },
            promptRow: snapshots.first { $0.table == "asset_prompts" }
                ?? RowSnapshot(table: "asset_prompts", columns: [:]),
            citationRows: snapshots.filter { $0.table == "asset_prompt_references" }
        )
    }

    /// `attachGeneratedPrompt`'s inverse: remove its inserts **together**, citations
    /// first, then the prompt, then the composed asset row; redo restores byte-identically.
    static func removeAttachedPrompt(
        payload: GeneratedPromptPayload, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        func deleteInserted() throws {
            for snapshot in payload.citationRows.reversed() {
                if case let .string(raw)? = snapshot.columns["id"],
                   let id = UUID(uuidString: raw) {
                    try RowSnapshotStore.delete(table: "asset_prompt_references", id: id, in: db)
                }
            }
            if case let .string(raw)? = payload.promptRow.columns["id"],
               let id = UUID(uuidString: raw) {
                try RowSnapshotStore.delete(table: "asset_prompts", id: id, in: db)
            }
            if let assetSnapshot = payload.assetRow,
               case let .string(raw)? = assetSnapshot.columns["id"],
               let id = UUID(uuidString: raw) {
                try RowSnapshotStore.delete(table: "assets", id: id, in: db)
            }
        }

        if case .inverting = mode {
            try deleteInserted()
        } else {
            // Redo: restore exactly what was inserted.
            try RowGraph.restore(payload.snapshots, in: db)
        }
        var affected: Set<SubjectRef> = [
            SubjectRef(kind: .requirement, id: payload.requirementID),
        ]
        affected.formUnion(RowGraph.subjects(of: payload.snapshots))
        let promptRow = payload.promptRow
        let promptID = Self.uuid(of: promptRow) ?? UUID()
        let assetID = payload.assetRow.flatMap { Self.uuid(of: $0) } ?? UUID()
        let body = Self.string(promptRow, "body") ?? ""
        let targetModel = Self.string(promptRow, "target_model") ?? ""
        let guidance = Self.string(promptRow, "guidance") ?? ""
        let digest = Self.string(promptRow, "input_digest") ?? ""
        let formatVersion = Self.int(promptRow, "input_format_version") ?? 1
        let skillIdentity = AssetPromptSkillIdentity(
            id: Self.string(promptRow, "skill_id") ?? "",
            entryPath: Self.string(promptRow, "skill_entry_path") ?? "",
            entrySHA256: Self.string(promptRow, "skill_entry_sha256") ?? ""
        )
        return MutationEffect(
            inverse: .attachGeneratedPrompt(
                promptID: promptID,
                assetID: assetID,
                requirementID: payload.requirementID,
                body: body,
                targetModel: targetModel,
                guidance: guidance,
                inputDigest: digest,
                inputFormatVersion: formatVersion,
                skillIdentity: skillIdentity
            ),
            affected: affected,
            snapshots: payload.snapshots
        )
    }


    // MARK: - Snapshot column helpers (JSONValue has no member accessors by design)

    private static func string(_ snapshot: RowSnapshot, _ column: String) -> String? {
        if case let .string(value)? = snapshot.columns[column] { return value }
        return nil
    }

    private static func int(_ snapshot: RowSnapshot, _ column: String) -> Int? {
        if case let .int(value)? = snapshot.columns[column] { return value }
        return nil
    }

    private static func id(_ snapshot: RowSnapshot) -> UUID? {
        guard let raw = string(snapshot, "id") else { return nil }
        return UUID(uuidString: raw)
    }

    private static func uuid(of snapshot: RowSnapshot) -> UUID? { id(snapshot) }


    // MARK: - setPromptBody (§7.2)

    static func setPromptBody(
        promptID: UUID, body: String, actor: MutationActor, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        try validateBody(body)
        let prompt = try requireCurrentPrompt(id: promptID, in: db)

        if let entry = mode.invertedEntry {
            // Undo/redo of a body edit: the row comes back from the entry's snapshot
            // byte-identically — updated_at included — never via a second UPDATE (§3.8).
            guard let current = try RowSnapshotStore.capture(
                table: "asset_prompts", id: promptID, in: db
            ) else {
                throw ProjectStoreError.promptNotFound
            }
            try RowGraph.restore(entry.snapshots.filter { $0.table == "asset_prompts" }, in: db)
            let restoredBody = Self.string(current, "body") ?? ""
            return MutationEffect(
                inverse: .setPromptBody(promptID: promptID, body: restoredBody),
                affected: [
                    SubjectRef(kind: .prompt, id: promptID),
                    SubjectRef(kind: .requirement, id: prompt.requirementID),
                ],
                snapshots: [current]
            )
        }

        try RequirementOperations.requireHuman(actor, subject: prompt.ref)
        try LockPolicy.requireRequirementUnlocked(requirementID: prompt.requirementID, in: db)

        var collector = SnapshotCollector()
        try collector.capture(table: "asset_prompts", id: promptID, in: db)
        let priorBody = try String.fetchOne(
            db, sql: "SELECT body FROM asset_prompts WHERE id = ?", arguments: [promptID.uuidString]
        ) ?? ""
        try db.execute(
            sql: """
                UPDATE asset_prompts
                SET body = ?, source = 'human', updated_at = ?
                WHERE id = ?
                """,
            arguments: [body, UTCDate.string(from: Date()), promptID.uuidString]
        )
        // `input_digest` untouched: it hashes inputs, not the body (§3.4).
        return MutationEffect(
            inverse: .setPromptBody(promptID: promptID, body: priorBody),
            affected: [
                SubjectRef(kind: .prompt, id: promptID),
                SubjectRef(kind: .requirement, id: prompt.requirementID),
            ],
            snapshots: collector.snapshots
        )
    }

    // MARK: - deletePrompt / restoreDeletedPrompt (§7.2, §4.3)

    @discardableResult
    static func deletePrompt(
        promptID: UUID, actor: MutationActor, in db: Database
    ) throws -> MutationEffect {
        let prompt = try requirePrompt(id: promptID, in: db)
        try RequirementOperations.requireHuman(actor, subject: prompt.ref)
        try LockPolicy.requireRequirementUnlocked(requirementID: prompt.requirementID, in: db)

        var collector = SnapshotCollector()
        try collector.capture(table: "asset_prompts", id: promptID, in: db)
        collector.add(contentsOf: try RowSnapshotStore.captureAll(
            table: "asset_prompt_references", where: "prompt_id = ?",
            arguments: [promptID.uuidString], in: db
        ))
        // The anchor's row as it was before this delete's recompute rewrote its status,
        // so the undo restores byte-identically rather than recomputing (§3.8).
        if let assetID = try assetID(ofRequirement: prompt.requirementID, in: db) {
            try collector.capture(table: "assets", id: assetID, in: db)
        }
        // §4.3's symmetric rule: the citing versions may live under another requirement's
        // asset after a combine, so they are captured wherever they live.
        let citingVersions = try RowSnapshotStore.captureAll(
            table: "asset_versions", where: "prompt_id = ?",
            arguments: [promptID.uuidString], in: db
        )
        collector.add(contentsOf: citingVersions)

        // Null the lineage stamps explicitly before the row goes: SET NULL would do it
        // silently, and §4.3 forbids relying on that alone. The captured rows above are
        // the restore record — whether this apply deletes a long-lived prompt or, running
        // as `createPrompt`'s op-level inverse, the row that create just made.
        try db.execute(
            sql: "UPDATE asset_versions SET prompt_id = NULL WHERE prompt_id = ?",
            arguments: [promptID.uuidString]
        )
        try db.execute(sql: "DELETE FROM asset_prompts WHERE id = ?",
                       arguments: [promptID.uuidString])

        let applied = try AssetOperations.recompute(requirementID: prompt.requirementID, in: db)
        let payload = DeletedPromptPayload(
            requirementID: prompt.requirementID,
            assetRow: collector.snapshots.first { $0.table == "assets" },
            promptRow: collector.snapshots.first { $0.table == "asset_prompts" }
                ?? RowSnapshot(table: "asset_prompts", columns: [:]),
            citationRows: collector.snapshots.filter { $0.table == "asset_prompt_references" },
            citingVersionRows: citingVersions
        )
        var affected: Set<SubjectRef> = [
            SubjectRef(kind: .prompt, id: promptID),
            SubjectRef(kind: .requirement, id: prompt.requirementID),
        ]
        affected.formUnion(RowGraph.subjects(of: citingVersions))
        affected.formUnion(applied.affected)
        return MutationEffect(
            inverse: .restoreDeletedPrompt(payload: payload),
            affected: affected,
            snapshots: collector.snapshots
        )
    }

    static func restoreDeletedPrompt(
        payload: DeletedPromptPayload, in db: Database
    ) throws -> MutationEffect {
        try RowGraph.restore(payload.snapshots, in: db)
        var affected: Set<SubjectRef> = [
            SubjectRef(kind: .requirement, id: payload.requirementID),
        ]
        affected.formUnion(RowGraph.subjects(of: payload.snapshots))
        let promptID = Self.uuid(of: payload.promptRow) ?? UUID()
        return MutationEffect(
            inverse: .deletePrompt(promptID: promptID),
            affected: affected,
            snapshots: []
        )
    }

    // MARK: - markAssetInProgress / clearAssetInProgress (§7.2, §14.7)

    static func markAssetInProgress(
        requirementID: UUID, actor: MutationActor, in db: Database
    ) throws -> MutationEffect {
        let requirement = try requireRequirement(id: requirementID, in: db)
        try RequirementOperations.requireHuman(actor, subject: requirement.ref)
        try requireAccepted(requirement, in: db)
        try requireActive(requirementID: requirementID, in: db)
        try LockPolicy.requireRequirementUnlocked(requirementID: requirementID, in: db)

        guard let asset = try AssetOperations.asset(ofRequirement: requirementID, in: db) else {
            throw ProjectStoreError.assetNotFound
        }
        let assetID = asset.id
        // §5.5/§6.1: once media has arrived, the slot is in review, not in generation.
        let versionCount = try AssetOperations.versionCount(assetID: assetID, in: db)
        guard versionCount == 0 else {
            throw ProjectStoreError.inProgressRequiresNoVersions
        }

        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: assetID, in: db)
        try db.execute(
            sql: "UPDATE assets SET in_progress_since = ?, updated_at = ? WHERE id = ?",
            arguments: [UTCDate.string(from: Date()), UTCDate.string(from: Date()),
                        assetID.uuidString]
        )
        let applied = try AssetOperations.recompute(requirementID: requirementID, in: db)
        return MutationEffect(
            inverse: .clearAssetInProgress(assetID: assetID),
            affected: Set([
                SubjectRef(kind: .asset, id: assetID),
                SubjectRef(kind: .requirement, id: requirementID),
            ]).union(applied.affected),
            snapshots: collector.snapshots
        )
    }

    static func clearAssetInProgress(
        assetID: UUID, actor: MutationActor, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        let asset = try AssetOperations.requireAsset(id: assetID, in: db)
        try RequirementOperations.requireHuman(actor, subject: asset.ref)
        try LockPolicy.requireRequirementUnlocked(requirementID: asset.requirementID, in: db)

        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: assetID, in: db)
        let prior = try String.fetchOne(
            db, sql: "SELECT in_progress_since FROM assets WHERE id = ?",
            arguments: [assetID.uuidString]
        )
        let priorDate = try prior.map(UTCDate.date(from:))
        try db.execute(
            sql: "UPDATE assets SET in_progress_since = NULL, updated_at = ? WHERE id = ?",
            arguments: [UTCDate.string(from: Date()), assetID.uuidString]
        )
        let applied = try AssetOperations.recompute(requirementID: asset.requirementID, in: db)
        return MutationEffect(
            // Payload-driven prior-timestamp restore, never a re-stamp (§7.1).
            inverse: .restoreAssetInProgress(assetID: assetID, timestamp: priorDate),
            affected: Set([
                SubjectRef(kind: .asset, id: assetID),
                SubjectRef(kind: .requirement, id: asset.requirementID),
            ]).union(applied.affected),
            snapshots: collector.snapshots
        )
    }

    static func restoreAssetInProgress(
        assetID: UUID, timestamp: Date?, in db: Database
    ) throws -> MutationEffect {
        let asset = try AssetOperations.requireAsset(id: assetID, in: db)
        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: assetID, in: db)
        if let timestamp {
            try db.execute(
                sql: "UPDATE assets SET in_progress_since = ? WHERE id = ?",
                arguments: [UTCDate.string(from: timestamp), assetID.uuidString]
            )
        } else {
            try db.execute(
                sql: "UPDATE assets SET in_progress_since = NULL WHERE id = ?",
                arguments: [assetID.uuidString]
            )
        }
        return MutationEffect(
            inverse: .clearAssetInProgress(assetID: assetID),
            affected: [
                SubjectRef(kind: .asset, id: assetID),
                SubjectRef(kind: .requirement, id: asset.requirementID),
            ],
            snapshots: collector.snapshots
        )
    }
}

extension PromptOperations {
    /// The inverse precondition (§3.8): the row an inverse needs is still where it was.
    static func precheckPrompt(id: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "asset_prompts", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That prompt is no longer in this project."
            )
        }
    }
}
