import Foundation
import GRDB

// PHASE5_DESIGN §8.4's engine-internal scene-prompt attach (Plan 021 contract C) —
// `PromptOperations.attachGeneratedPrompt`'s shape at scene scale. The AI actor's entire
// §3.9 write surface: one `scene_prompts` row, its immutable citation rows, nothing else.
//
// Citations are derived **in the operation** from §3.2's plan over the same state the
// applier's step-0 digest was computed against — ordering, numbering, and capture live
// here, never the applier (the Plan 014 rule, repeated). Fixed `ai` provenance on its own
// inserts — never the shared `insertProvenance`, which births `.ai` rows `proposed`,
// while a prompt is output, not a reviewable fact (born `accepted`, inert PROV).
extension ScenePromptOperations {

    // MARK: - attachGeneratedScenePrompt (§7.1, §8.4 step 2)

    static func attachGeneratedScenePrompt(
        promptID: UUID,
        sceneID: UUID,
        body: String,
        guidance: String,
        durationSeconds: Int?,
        aspectRatio: String,
        resolution: String,
        inputDigest: String,
        inputFormatVersion: Int,
        skillIdentity: AssetPromptSkillIdentity,
        actor: MutationActor,
        mode: MutationMode = .apply,
        in db: Database
    ) throws -> MutationEffect {
        try validateBody(body)
        // Redo of a generate: the undo entry's snapshots restore byte-identically, never
        // through the gesture guards — the `attachGeneratedPrompt(restoring:)` pattern.
        if let invertedEntry = mode.invertedEntry {
            try RowGraph.restore(invertedEntry.snapshots, in: db)
            try consumeCreativeDirection(sceneID: sceneID, in: db)
            let payload = GeneratedScenePromptPayload(
                sceneID: sceneID,
                promptRow: invertedEntry.snapshots.first { $0.table == "scene_prompts" }
                    ?? RowSnapshot(table: "scene_prompts", columns: [:]),
                citationRows: invertedEntry.snapshots.filter { $0.table == "scene_prompt_references" }
            )
            var affected: Set<SubjectRef> = [
                SubjectRef(kind: .prompt, id: promptID),
                SubjectRef(kind: .scene, id: sceneID),
            ]
            affected.formUnion(RowGraph.subjects(of: invertedEntry.snapshots))
            return MutationEffect(
                inverse: .removeAttachedScenePrompt(payload: payload),
                affected: affected,
                snapshots: []
            )
        }
        guard case .ai = actor else {
            // The human paths compose the shipped human-only ops; this case is the AI
            // actor's alone (§7.1).
            throw ProjectStoreError.protectedFact(subject: SubjectRef(kind: .scene, id: sceneID))
        }

        // §8.4 step 1: the cheap preconditions outside the digest — the scene still
        // counted, the persisted active profile still cataloged. Everything else the
        // pre-flight gated on (Asset Ready, plan membership, reference bytes) is
        // digest-covered: the step-0 guard has already proven the input unchanged.
        let graph = try ProjectRepository.readinessGraph(in: db)
        guard graph.scenes.contains(where: { $0.id == sceneID }) else {
            throw ProjectStoreError.sceneNotFound
        }
        let readiness = ProjectRepository.deriveReadiness(graph)
        if let readyRow = readiness.scenes.first(where: { $0.sceneID == sceneID }),
           readyRow.isExcluded {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "Excluded scenes are not prepared for generation."
            )
        }
        let profileID = try String.fetchOne(
            db, sql: "SELECT generation_target_profile FROM projects"
        ) ?? TargetProfileCatalog.defaultProfileID
        guard let profile = TargetProfileCatalog.profile(id: profileID) else {
            throw ProjectStoreError.generationTargetProfileMissing(id: profileID)
        }
        guard profile.accepts(
            durationSeconds: durationSeconds, aspectRatio: aspectRatio, resolution: resolution
        ) else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "\(profile.displayName) does not accept those generation settings."
            )
        }

        let projectRaw = try String.fetchOne(db, sql: "SELECT id FROM projects")
        guard let projectID = projectRaw.flatMap(UUID.init(uuidString:)) else {
            throw ProjectStoreError.missingProject
        }

        let number = try nextScenePromptNumber(
            sceneID: sceneID, profileID: profile.id, in: db
        )
        let timestamp = UTCDate.string(from: Date())
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
                          'ai', NULL, 'accepted', NULL, ?, 'ai', ?, ?)
                """,
            arguments: [
                promptID.uuidString, projectID.uuidString, sceneID.uuidString,
                profile.id, number, body, guidance,
                durationSeconds as Int?, aspectRatio, resolution,
                skillIdentity.id, skillIdentity.entryPath, skillIdentity.entrySHA256,
                inputDigest, inputFormatVersion,
                actor.jobID?.uuidString, timestamp, timestamp,
            ]
        )

        // Citations from §3.2's plan — the satisfied subset, densely designated,
        // capturing sha256 and display name at build time. Derived from the one shared
        // derivation the reads and builder use; the recorded values are immutable history.
        let plan = try ProjectRepository.sceneReferencePlan(
            sceneID: sceneID, graph: graph, in: db
        )
        var citationRows: [RowSnapshot] = []
        var citationRefs: Set<SubjectRef> = []
        for planned in plan {
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
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ai', ?, ?)
                    """,
                arguments: [
                    citationID.uuidString, promptID.uuidString, designator,
                    planned.requirementID.uuidString, approved.versionID.uuidString,
                    planned.class.rawValue, planned.attributes.role,
                    planned.attributes.exclusion, planned.attributes.fidelity.rawValue,
                    approved.sha256, "\(planned.entityName) — \(planned.requirementName)",
                    actor.jobID?.uuidString, timestamp,
                ]
            )
            if let snapshot = try RowSnapshotStore.capture(
                table: "scene_prompt_references", id: citationID, in: db
            ) {
                citationRows.append(snapshot)
            }
            citationRefs.insert(SubjectRef(kind: .promptReference, id: citationID))
        }

        let payload = GeneratedScenePromptPayload(
            sceneID: sceneID,
            promptRow: try RowSnapshotStore.capture(table: "scene_prompts", id: promptID, in: db)
                ?? RowSnapshot(table: "scene_prompts", columns: [:]),
            citationRows: citationRows
        )
        var affected: Set<SubjectRef> = [
            SubjectRef(kind: .prompt, id: promptID),
            SubjectRef(kind: .scene, id: sceneID),
        ]
        affected.formUnion(citationRefs)
        try consumeCreativeDirection(sceneID: sceneID, in: db)
        return MutationEffect(
            inverse: .removeAttachedScenePrompt(payload: payload),
            affected: affected,
            snapshots: []
        )
    }

    // MARK: - removeAttachedScenePrompt (the inverse)

    /// `attachGeneratedScenePrompt`'s inverse: remove its inserts **together**, citations
    /// first, then the prompt row; redo restores byte-identically.
    static func removeAttachedScenePrompt(
        payload: GeneratedScenePromptPayload, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        func deleteInserted() throws {
            for snapshot in payload.citationRows.reversed() {
                if case let .string(raw)? = snapshot.columns["id"],
                   let id = UUID(uuidString: raw) {
                    try RowSnapshotStore.delete(table: "scene_prompt_references", id: id, in: db)
                }
            }
            if case let .string(raw)? = payload.promptRow.columns["id"],
               let id = UUID(uuidString: raw) {
                try RowSnapshotStore.delete(table: "scene_prompts", id: id, in: db)
            }
        }

        if case .inverting = mode {
            try deleteInserted()
        } else {
            // Redo: restore exactly what was inserted.
            try RowGraph.restore(payload.snapshots, in: db)
        }
        var affected: Set<SubjectRef> = [
            SubjectRef(kind: .scene, id: payload.sceneID),
        ]
        affected.formUnion(RowGraph.subjects(of: payload.snapshots))
        let promptRow = payload.promptRow
        let promptID = Self.uuid(of: promptRow) ?? UUID()
        return MutationEffect(
            inverse: .attachGeneratedScenePrompt(
                promptID: promptID,
                sceneID: payload.sceneID,
                body: Self.string(promptRow, "body") ?? "",
                guidance: Self.string(promptRow, "guidance") ?? "",
                durationSeconds: Self.int(promptRow, "duration_seconds"),
                aspectRatio: Self.string(promptRow, "aspect_ratio") ?? "",
                resolution: Self.string(promptRow, "resolution") ?? "",
                inputDigest: Self.string(promptRow, "input_digest") ?? "",
                inputFormatVersion: Self.int(promptRow, "input_format_version") ?? 1,
                skillIdentity: AssetPromptSkillIdentity(
                    id: Self.string(promptRow, "skill_id") ?? "",
                    entryPath: Self.string(promptRow, "skill_entry_path") ?? "",
                    entrySHA256: Self.string(promptRow, "skill_entry_sha256") ?? ""
                )
            ),
            affected: affected,
            snapshots: payload.snapshots
        )
    }

    // MARK: - Snapshot column helpers

    private static func string(_ snapshot: RowSnapshot, _ column: String) -> String? {
        if case let .string(value)? = snapshot.columns[column] { return value }
        return nil
    }

    /// Direction is a one-run instruction, not durable scene canon. Keeping the clear
    /// inside the attach transaction means a validation, commit, or failure-hook error
    /// rolls it back for retry. Undo removes the generated result but does not resurrect
    /// an instruction that was already consumed successfully.
    private static func consumeCreativeDirection(sceneID: UUID, in db: Database) throws {
        try db.execute(
            sql: "UPDATE scenes SET prompt_direction = '' WHERE id = ?",
            arguments: [sceneID.uuidString]
        )
    }

    private static func int(_ snapshot: RowSnapshot, _ column: String) -> Int? {
        if case let .int(value)? = snapshot.columns[column] { return value }
        return nil
    }

    private static func uuid(of snapshot: RowSnapshot) -> UUID? {
        guard let raw = string(snapshot, "id") else { return nil }
        return UUID(uuidString: raw)
    }
}
