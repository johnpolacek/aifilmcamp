import Foundation
import GRDB

// PHASE5_DESIGN §7.1's scene-prompt and project-generation operations (Plan 019 contract
// A), in the house shape: `MutationEffect`-returning statics that open no transaction —
// the caller's transaction is the one that counts, and the reentrancy test's `Editing/`
// glob covers this file automatically.
//
// `createScenePrompt` is **the human counterpart of the AI attach** (§7.1): it enforces
// §8.1's pre-flight and then captures digest, format version, citations, and settings
// through **the one shared capture path**, `ScenePromptInputBuilder.snapshot(sceneID:in:)`
// — the same in-transaction rebuild §8.4 step 0 prescribes for the apply. There is no
// second capture path to fork.
//
// Scene prompts adopt the Phase 3 history model verbatim (§3.1): current = highest
// `prompt_number` per `(scene, target_profile)`, delete-the-newest as restore, body edit
// flips provenance `source` only. Nothing here recomputes asset status — scene prompts
// touch no asset row — and no subject is lockable at scene scope (§4.3).

enum ScenePromptOperations {

    // MARK: - Body validation (§7.1)

    /// Non-empty, ≤ 64 KB UTF-8 (§7.1's scene-scale cap — twice the asset table's), control
    /// character free other than newline and tab. Storage-side guard; §8.3's validator
    /// spells the same limits for AI output.
    static func validateBody(_ body: String) throws {
        guard !body.isEmpty else {
            throw ProjectStoreError.sceneOperationRefused(reason: "A prompt cannot be empty.")
        }
        guard body.utf8.count <= 64 * 1024 else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "A prompt cannot be larger than 64 KB."
            )
        }
        let forbidden = body.unicodeScalars.contains { scalar in
            scalar.value < 0x20 && scalar != "\n" && scalar != "\t"
        }
        guard !forbidden else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "A prompt cannot contain control characters."
            )
        }
    }

    // MARK: - The §8.1 pre-flight (shared by every writer; the run gate mirrors it)

    /// Everything the pre-flight gates on, resolved once: the readiness row (Asset Ready
    /// read from Plan 017's derivation — never re-derived here), the cataloged active
    /// profile, the reference plan, and the profile limit check.
    struct PreFlight {
        let sceneID: UUID
        let projectID: UUID
        let profile: TargetProfile
        let plan: [ScenePlannedReference]
    }

    static func preFlight(sceneID: UUID, in db: Database) throws -> PreFlight {
        // Counted scene first: it must exist and carry a package state at all (§3.3).
        let graph = try ProjectRepository.readinessGraph(in: db)
        guard graph.scenes.contains(where: { $0.id == sceneID }) else {
            throw ProjectStoreError.sceneNotFound
        }

        let projectRaw = try String.fetchOne(db, sql: "SELECT id FROM projects")
        guard let projectID = projectRaw.flatMap(UUID.init(uuidString:)) else {
            throw ProjectStoreError.missingProject
        }

        // The persisted active profile P (§3.5); an id the catalog no longer carries
        // refuses naming it — never a crash.
        let profileID = try String.fetchOne(
            db, sql: "SELECT generation_target_profile FROM projects"
        ) ?? TargetProfileCatalog.defaultProfileID
        guard let profile = TargetProfileCatalog.profile(id: profileID) else {
            throw ProjectStoreError.generationTargetProfileMissing(id: profileID)
        }

        // Asset Ready from Plan 017's derivation over this same load (§3.3's rule).
        let readiness = ProjectRepository.deriveReadiness(graph)
        guard let readyRow = readiness.scenes.first(where: { $0.sceneID == sceneID }) else {
            throw ProjectStoreError.sceneNotFound
        }
        guard !readyRow.isExcluded else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "Excluded scenes are not prepared for generation."
            )
        }
        guard readyRow.state == .assetReady else {
            throw ProjectStoreError.scenePromptRequiresAssetReady
        }

        // §3.2's budget refuses, never truncates.
        let plan = try ProjectRepository.sceneReferencePlan(
            sceneID: sceneID, graph: graph, in: db
        )
        let satisfied = plan.count(where: \.isSatisfied)
        guard satisfied <= profile.imageReferenceLimit else {
            throw ProjectStoreError.sceneReferencesExceedProfileLimit(
                count: satisfied, limit: profile.imageReferenceLimit
            )
        }

        return PreFlight(
            sceneID: sceneID, projectID: projectID, profile: profile, plan: plan
        )
    }

    // MARK: - Row helpers

    struct ScenePromptRow {
        let id: UUID
        let sceneID: UUID
        let targetProfile: String
        let promptNumber: Int
        var ref: SubjectRef { SubjectRef(kind: .prompt, id: id) }
    }

    static func requireScenePrompt(id: UUID, in db: Database) throws -> ScenePromptRow {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT id, scene_id, target_profile, prompt_number
                FROM scene_prompts WHERE id = ?
                """,
            arguments: [id.uuidString]
        ) else { throw ProjectStoreError.promptNotFound }
        return ScenePromptRow(
            id: try UUID.required(row["id"]),
            sceneID: try UUID.required(row["scene_id"]),
            targetProfile: row["target_profile"],
            promptNumber: row["prompt_number"]
        )
    }

    /// The pinned walk at scene scope: max + 1 for the `(scene, profile)` pair,
    /// in-transaction. Gaps are legal after deletes.
    static func nextScenePromptNumber(
        sceneID: UUID, profileID: String, in db: Database
    ) throws -> Int {
        try Int.fetchOne(
            db,
            sql: """
                SELECT COALESCE(MAX(prompt_number), 0) + 1 FROM scene_prompts
                WHERE scene_id = ? AND target_profile = ?
                """,
            arguments: [sceneID.uuidString, profileID]
        ) ?? 1
    }

    /// Only the highest-numbered row of its `(scene, profile)` pair may be body-edited.
    static func requireCurrentScenePrompt(id: UUID, in db: Database) throws -> ScenePromptRow {
        let prompt = try requireScenePrompt(id: id, in: db)
        let currentID = try String.fetchOne(
            db,
            sql: """
                SELECT id FROM scene_prompts
                WHERE scene_id = ? AND target_profile = ?
                ORDER BY prompt_number DESC LIMIT 1
                """,
            arguments: [prompt.sceneID.uuidString, prompt.targetProfile]
        )
        guard currentID == id.uuidString else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "Only the current prompt can be edited; earlier prompts are history."
            )
        }
        return prompt
    }

    // MARK: - createScenePrompt (§7.1)

    static func createScenePrompt(
        id: UUID,
        sceneID: UUID,
        body: String,
        guidance: String,
        durationSeconds: Int?,
        aspectRatio: String,
        resolution: String,
        restoring: [RowSnapshot],
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        try validateBody(body)
        if !restoring.isEmpty {
            // Redo: byte-identical, the `createPrompt(restoring:)` shape.
            try RowGraph.restore(restoring, in: db)
            return MutationEffect(
                inverse: .deleteScenePrompt(promptID: id),
                affected: [
                    SubjectRef(kind: .prompt, id: id),
                    SubjectRef(kind: .scene, id: sceneID),
                ],
                snapshots: []
            )
        }

        try RequirementOperations.requireHuman(actor, subject: SubjectRef(kind: .scene, id: sceneID))
        let flight = try preFlight(sceneID: sceneID, in: db)

        // Profile-validated settings (§4.3); unconstrained profiles admit anything.
        guard flight.profile.accepts(
            durationSeconds: durationSeconds, aspectRatio: aspectRatio, resolution: resolution
        ) else {
            throw ProjectStoreError.sceneOperationRefused(
                reason:
                    "\(flight.profile.displayName) does not accept those generation settings."
            )
        }

        // §8.1's budget pre-flight over the exact text being captured.
        let snapshot = try ScenePromptInputBuilder.snapshot(sceneID: sceneID, in: db)
        try ScenePromptInputBudget.check(text: snapshot.text)

        let number = try nextScenePromptNumber(
            sceneID: sceneID, profileID: flight.profile.id, in: db
        )
        let timestamp = UTCDate.string(from: Date())
        var arguments: StatementArguments = [
            id.uuidString, flight.projectID.uuidString, sceneID.uuidString,
            flight.profile.id, number, body, guidance,
            durationSeconds as Int?, aspectRatio, resolution,
            "", "", "",
            snapshot.digest, ScenePromptInputBuilder.schemaVersion,
        ]
        arguments += RequirementOperations.insertProvenance(actor, timestamp: timestamp)
        try db.execute(
            sql: """
                INSERT INTO scene_prompts (
                    id, project_id, scene_id, target_profile, prompt_number,
                    body, guidance, duration_seconds, aspect_ratio, resolution,
                    skill_id, skill_entry_path, skill_entry_sha256,
                    input_digest, input_format_version,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                          ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: arguments
        )

        // Citations from the plan the digest was computed over — the same satisfied subset,
        // densely designated, that §8.4 step 2 records for an AI attach. Immutable history.
        var citationRefs: Set<SubjectRef> = []
        for planned in flight.plan {
            guard planned.isSatisfied, let designator = planned.designator,
                  let approved = planned.approvedVersion
            else { continue }
            let citationID = UUID()
            try db.execute(
                sql: """
                    INSERT INTO scene_prompt_references (
                        id, prompt_id, position, requirement_id, version_id,
                        class, role, exclusion, fidelity, sha256, display_name,
                        source, job_id, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'human', NULL, ?)
                    """,
                arguments: [
                    citationID.uuidString, id.uuidString, designator,
                    planned.requirementID.uuidString, approved.versionID.uuidString,
                    planned.class.rawValue, planned.attributes.role,
                    planned.attributes.exclusion, planned.attributes.fidelity.rawValue,
                    approved.sha256, "\(planned.entityName) — \(planned.requirementName)",
                    timestamp,
                ]
            )
            citationRefs.insert(SubjectRef(kind: .promptReference, id: citationID))
        }

        return MutationEffect(
            inverse: .deleteScenePrompt(promptID: id),
            affected: Set([
                SubjectRef(kind: .prompt, id: id),
                SubjectRef(kind: .scene, id: sceneID),
            ]).union(citationRefs),
            snapshots: []
        )
    }

    // MARK: - setScenePromptBody (§7.1)

    static func setScenePromptBody(
        promptID: UUID, body: String, actor: MutationActor, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        try validateBody(body)
        let prompt = try requireCurrentScenePrompt(id: promptID, in: db)

        if let entry = mode.invertedEntry {
            // Undo/redo restores the row byte-identically — updated_at included (§3.8).
            guard let current = try RowSnapshotStore.capture(
                table: "scene_prompts", id: promptID, in: db
            ) else {
                throw ProjectStoreError.promptNotFound
            }
            try RowGraph.restore(entry.snapshots.filter { $0.table == "scene_prompts" }, in: db)
            let restoredBody = Self.string(current, "body") ?? ""
            return MutationEffect(
                inverse: .setScenePromptBody(promptID: promptID, body: restoredBody),
                affected: [
                    SubjectRef(kind: .prompt, id: promptID),
                    SubjectRef(kind: .scene, id: prompt.sceneID),
                ],
                snapshots: [current]
            )
        }

        try RequirementOperations.requireHuman(actor, subject: prompt.ref)

        var collector = SnapshotCollector()
        try collector.capture(table: "scene_prompts", id: promptID, in: db)
        let priorBody = try String.fetchOne(
            db, sql: "SELECT body FROM scene_prompts WHERE id = ?", arguments: [promptID.uuidString]
        ) ?? ""
        try db.execute(
            sql: """
                UPDATE scene_prompts
                SET body = ?, source = 'human', updated_at = ?
                WHERE id = ?
                """,
            arguments: [body, UTCDate.string(from: Date()), promptID.uuidString]
        )
        // Citations and `input_digest` untouched: they record what the prompt was written
        // against, not what it currently says (§7.1).
        return MutationEffect(
            inverse: .setScenePromptBody(promptID: promptID, body: priorBody),
            affected: [
                SubjectRef(kind: .prompt, id: promptID),
                SubjectRef(kind: .scene, id: prompt.sceneID),
            ],
            snapshots: collector.snapshots
        )
    }

    // MARK: - deleteScenePrompt / restoreDeletedScenePrompt (§7.1)

    @discardableResult
    static func deleteScenePrompt(
        promptID: UUID, actor: MutationActor, in db: Database
    ) throws -> MutationEffect {
        // Schema v9's compatibility view exposes the first card as the legacy prompt id.
        // Delete through the canonical graph operation so a still-supported singular
        // call cannot cascade a multi-card set and restore only its first card on undo.
        if try db.tableExists("scene_prompt_sets"),
           try ProjectRepository.scenePromptSet(id: promptID, in: db) != nil {
            return try ScenePromptSetOperations.deleteSet(
                setID: promptID, actor: actor, requireCurrent: false, in: db
            )
        }

        let prompt = try requireScenePrompt(id: promptID, in: db)
        try RequirementOperations.requireHuman(actor, subject: prompt.ref)

        var collector = SnapshotCollector()
        try collector.capture(table: "scene_prompts", id: promptID, in: db)
        let citations = try RowSnapshotStore.captureAll(
            table: "scene_prompt_references", where: "prompt_id = ?",
            arguments: [promptID.uuidString], in: db
        )
        collector.add(contentsOf: citations)
        try db.execute(sql: "DELETE FROM scene_prompts WHERE id = ?", arguments: [promptID.uuidString])

        let payload = DeletedScenePromptPayload(
            sceneID: prompt.sceneID,
            promptRow: collector.snapshots.first { $0.table == "scene_prompts" }
                ?? RowSnapshot(table: "scene_prompts", columns: [:]),
            citationRows: citations
        )
        return MutationEffect(
            inverse: .restoreDeletedScenePrompt(payload: payload),
            affected: [
                SubjectRef(kind: .prompt, id: promptID),
                SubjectRef(kind: .scene, id: prompt.sceneID),
            ],
            snapshots: collector.snapshots
        )
    }

    static func restoreDeletedScenePrompt(
        payload: DeletedScenePromptPayload, in db: Database
    ) throws -> MutationEffect {
        try RowGraph.restore(payload.snapshots, in: db)
        let promptID = Self.string(payload.promptRow, "id").flatMap(UUID.init(uuidString:)) ?? UUID()
        return MutationEffect(
            inverse: .deleteScenePrompt(promptID: promptID),
            affected: [
                SubjectRef(kind: .prompt, id: promptID),
                SubjectRef(kind: .scene, id: payload.sceneID),
            ],
            snapshots: []
        )
    }

    // MARK: - setStyleBible (§3.6, §14.5)

    static func setStyleBible(
        text: String, actor: MutationActor, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        try RequirementOperations.requireHuman(actor, subject: SubjectRef(kind: .script, id: UUID()))
        let projectRaw = try String.fetchOne(db, sql: "SELECT id FROM projects")
        guard let projectID = projectRaw.flatMap(UUID.init(uuidString:)) else {
            throw ProjectStoreError.missingProject
        }
        var collector = SnapshotCollector()
        try collector.capture(table: "projects", id: projectID, in: db)
        let prior = try String.fetchOne(db, sql: "SELECT style_bible FROM projects") ?? ""
        try db.execute(
            sql: "UPDATE projects SET style_bible = ?, updated_at = ? WHERE id = ?",
            arguments: [text, UTCDate.string(from: Date()), projectID.uuidString]
        )
        // Digest input: every scene prompt in the project reads stale after this (§6.2).
        // No stored flag is written anywhere — staleness stays derived (§3.4).
        return MutationEffect(
            inverse: .setStyleBible(text: prior),
            affected: [SubjectRef(kind: .script, id: projectID)],
            snapshots: collector.snapshots
        )
    }

    // MARK: - setGenerationTargetProfile (§3.3, §14.2)

    static func setGenerationTargetProfile(
        profileID: String, actor: MutationActor, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        try RequirementOperations.requireHuman(actor, subject: SubjectRef(kind: .script, id: UUID()))
        guard TargetProfileCatalog.profile(id: profileID) != nil else {
            throw ProjectStoreError.generationTargetProfileMissing(id: profileID)
        }
        let projectRaw = try String.fetchOne(db, sql: "SELECT id FROM projects")
        guard let projectID = projectRaw.flatMap(UUID.init(uuidString:)) else {
            throw ProjectStoreError.missingProject
        }
        var collector = SnapshotCollector()
        try collector.capture(table: "projects", id: projectID, in: db)
        let prior = try String.fetchOne(
            db, sql: "SELECT generation_target_profile FROM projects"
        ) ?? TargetProfileCatalog.defaultProfileID
        try db.execute(
            sql: "UPDATE projects SET generation_target_profile = ?, updated_at = ? WHERE id = ?",
            arguments: [profileID, UTCDate.string(from: Date()), projectID.uuidString]
        )
        // Stales nothing (§6.2): each prompt row was rendered and digested against its own
        // profile; only which history the headline consults changes (§3.3).
        return MutationEffect(
            inverse: .setGenerationTargetProfile(profileID: prior),
            affected: [SubjectRef(kind: .script, id: projectID)],
            snapshots: collector.snapshots
        )
    }

    // MARK: - Snapshot column helpers (JSONValue has no member accessors by design)

    private static func string(_ snapshot: RowSnapshot, _ column: String) -> String? {
        if case let .string(value)? = snapshot.columns[column] { return value }
        return nil
    }
}

extension ScenePromptOperations {
    /// The inverse precondition (§3.8): the row an inverse needs is still where it was.
    static func precheckScenePrompt(id: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "scene_prompts", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That prompt is no longer in this project."
            )
        }
    }
}
