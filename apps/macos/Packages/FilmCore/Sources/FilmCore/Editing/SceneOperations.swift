import Foundation
import GRDB

/// The scene-shaped operations of PHASE1_DESIGN §6: `setSceneEntity`, `removeSceneEntity`,
/// `setSynopsis`, and the human-authored scene screenplay override.
///
/// A scene row itself is parser output and is never edited here — `setSynopsis` writes the
/// synopsis PROV column set and **nothing else** (§4.3).
enum SceneOperations {

    // MARK: - Scenes

    /// The one project's current script (§5.5). Every scene an edit names has to belong to
    /// it, or the edit is addressing a screenplay that has been replaced.
    static func currentScriptID(in db: Database) throws -> UUID? {
        guard let raw = try String.fetchOne(db, sql: "SELECT current_script_id FROM projects")
        else { return nil }
        return try UUID.required(raw)
    }

    /// The scene's ordinal, or `nil` when the scene is not in the current script.
    static func ordinal(ofScene id: UUID, in db: Database) throws -> Int? {
        guard let scriptID = try currentScriptID(in: db) else { return nil }
        return try Int.fetchOne(
            db,
            sql: "SELECT ordinal FROM scenes WHERE id = ? AND script_id = ?",
            arguments: [id.uuidString, scriptID.uuidString]
        )
    }

    static func requireScene(_ id: UUID, in db: Database) throws {
        guard try ordinal(ofScene: id, in: db) != nil else { throw ProjectStoreError.sceneNotFound }
    }

    // MARK: - setSceneText

    static func setSceneText(
        sceneID: UUID,
        text: String?,
        in db: Database
    ) throws -> MutationEffect {
        try requireScene(sceneID, in: db)
        let normalized = text?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping
        if let normalized,
           normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProjectStoreError.invalidSceneText
        }
        let prior = try String.fetchOne(
            db,
            sql: "SELECT screenplay_override FROM scenes WHERE id = ?",
            arguments: [sceneID.uuidString]
        )
        guard prior != normalized else {
            return MutationEffect(inverse: .batch([]), affected: [])
        }
        try db.execute(
            sql: "UPDATE scenes SET screenplay_override = ? WHERE id = ?",
            arguments: [normalized, sceneID.uuidString]
        )
        return MutationEffect(
            inverse: .setSceneText(sceneID: sceneID, text: prior),
            affected: [SubjectRef(kind: .scene, id: sceneID)]
        )
    }

    // MARK: - setScenePromptDirection

    static func setScenePromptDirection(
        sceneID: UUID,
        text: String,
        in db: Database
    ) throws -> MutationEffect {
        try requireScene(sceneID, in: db)
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prior = try String.fetchOne(
            db,
            sql: "SELECT prompt_direction FROM scenes WHERE id = ?",
            arguments: [sceneID.uuidString]
        ) ?? ""
        guard prior != normalized else {
            return MutationEffect(inverse: .batch([]), affected: [])
        }
        try db.execute(
            sql: "UPDATE scenes SET prompt_direction = ? WHERE id = ?",
            arguments: [normalized, sceneID.uuidString]
        )
        return MutationEffect(
            inverse: .setScenePromptDirection(sceneID: sceneID, text: prior),
            affected: [SubjectRef(kind: .scene, id: sceneID)]
        )
    }

    // MARK: - setSceneEntity (§6)

    /// Upserts on `(scene_id, entity_id, role)`.
    ///
    /// A fresh row is inserted with `matched_alias_id` NULL: a hand-added appearance was
    /// produced by no alias, and §3.5's split lookup reads that column. An **existing**
    /// row keeps its `matched_alias_id` for exactly that reason — vouching for an
    /// appearance the parser found must not cut the alias link a later split needs.
    ///
    /// Locks never block adding an appearance that references an entity (§3.7), so a
    /// locked or protected entity still accepts one.
    static func setSceneEntity(
        sceneID: UUID,
        entityID: UUID,
        role: SceneEntityRole,
        appearanceID: UUID?,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            guard let appearanceID else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "That change no longer names the appearance it touched."
                )
            }
            let ref = SubjectRef(kind: .appearance, id: appearanceID)
            let inverted = try InverseApplication.invertRow(of: entry, ref: ref, in: db)
            guard inverted.restored else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "That change no longer has an appearance to restore."
                )
            }
            // The row was there before this inverse ran ⇒ the entry had only overwritten
            // it, so the redo is the same upsert; otherwise the entry had removed it and
            // the redo removes it again.
            let redo: EditOperation = inverted.snapshots.contains { $0.table == "scene_entities" }
                ? .setSceneEntity(
                    sceneID: sceneID, entityID: entityID, role: role, appearanceID: appearanceID
                )
                : .removeSceneEntity(appearanceID: appearanceID)
            return MutationEffect(inverse: redo, affected: [ref], snapshots: inverted.snapshots)
        }

        try requireScene(sceneID, in: db)
        guard try EntityOperations.fetch(id: entityID, in: db) != nil else {
            throw ProjectStoreError.entityNotFound
        }
        ProtectionPolicy.checkReferenceAddition(
            toEntity: SubjectRef(kind: .entity, id: entityID), actor: actor
        )

        let timestamp = UTCDate.string(from: Date())
        if let existing = try Row.fetchOne(
            db,
            sql: """
                SELECT * FROM scene_entities WHERE scene_id = ? AND entity_id = ? AND role = ?
                """,
            arguments: [sceneID.uuidString, entityID.uuidString, role.rawValue]
        ) {
            let id = try UUID.required(existing["id"])
            let ref = SubjectRef(kind: .appearance, id: id)
            // Re-stamping an existing appearance is an edit of that row, so it answers to
            // §3.6: the parser owns its `speaking`/`setting` rows, and an accepted or
            // human-owned appearance is not the analysis's to re-stamp.
            try ProtectionPolicy.checkFactEdit(
                ref: ref,
                source: FactSource(rawValue: existing["source"] as String? ?? "") ?? .parser,
                reviewState: ReviewState(rawValue: existing["review_state"] as String? ?? "") ?? .proposed,
                actor: actor,
                in: db
            )
            let snapshot = RowSnapshot(table: "scene_entities", row: existing)
            var arguments = EntityOperations.provenanceArguments(
                actor: actor,
                current: ReviewState(rawValue: existing["review_state"] as String? ?? "") ?? .proposed,
                timestamp: timestamp
            )
            arguments += [id.uuidString]
            try db.execute(
                sql: "UPDATE scene_entities SET \(EntityOperations.provenanceAssignment) WHERE id = ?",
                arguments: arguments
            )
            return MutationEffect(
                inverse: .setSceneEntity(
                    sceneID: sceneID, entityID: entityID, role: role, appearanceID: id
                ),
                affected: [ref],
                snapshots: [snapshot]
            )
        }

        let id = appearanceID ?? UUID()
        let isHuman = actor == .human
        try db.execute(
            sql: """
                INSERT INTO scene_entities (
                    id, scene_id, entity_id, role, matched_alias_id,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, NULL, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString, sceneID.uuidString, entityID.uuidString, role.rawValue,
                actor.factSource.rawValue,
                (isHuman ? ReviewState.accepted : ReviewState.proposed).rawValue,
                isHuman ? timestamp : nil,
                actor.jobID?.uuidString,
                actor.factSource.rawValue, timestamp, timestamp,
            ]
        )
        return MutationEffect(
            inverse: .removeSceneEntity(appearanceID: id),
            affected: [SubjectRef(kind: .appearance, id: id)]
        )
    }

    /// §6's `removeSceneEntity`: a hard delete, because §3.6's tombstone rule covers
    /// entities, states, events, and relationships — an appearance the operator takes out
    /// of a scene is simply gone, and the journal payload is what brings it back.
    ///
    /// Deliberately **not** mode-aware: a redo re-runs the real removal and re-snapshots
    /// what it takes, exactly as `removeAlias` does, so the evidence it carries away is
    /// captured every time rather than only the first.
    static func removeSceneEntity(
        appearanceID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM scene_entities WHERE id = ?", arguments: [appearanceID.uuidString]
        ) else { throw ProjectStoreError.entityNotFound }
        let ref = SubjectRef(kind: .appearance, id: appearanceID)
        try ProtectionPolicy.checkFactEdit(
            ref: ref,
            source: FactSource(rawValue: row["source"] as String? ?? "") ?? .parser,
            reviewState: ReviewState(rawValue: row["review_state"] as String? ?? "") ?? .proposed,
            actor: actor,
            in: db
        )

        var collector = SnapshotCollector()
        collector.add(table: "scene_entities", row: row)
        var evidenceIDs: [UUID] = []
        for evidence in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM evidence
                WHERE subject_kind = 'appearance' AND subject_id = ? ORDER BY id
                """,
            arguments: [appearanceID.uuidString]
        ) {
            collector.add(table: "evidence", row: evidence)
            evidenceIDs.append(try UUID.required(evidence["id"]))
        }
        for id in evidenceIDs { try RowSnapshotStore.delete(table: "evidence", id: id, in: db) }
        // PHASE2_DESIGN §7.4: basis rows citing this appearance are swept in the same
        // transaction, and travel back with it through the payload.
        try EntityRequirementInteractions.sweepBasis(citing: [ref], into: &collector, in: db)
        try RowSnapshotStore.delete(table: "scene_entities", id: appearanceID, in: db)

        return MutationEffect(
            inverse: .setSceneEntity(
                sceneID: try UUID.required(row["scene_id"]),
                entityID: try UUID.required(row["entity_id"]),
                role: SceneEntityRole(rawValue: row["role"]) ?? .present,
                appearanceID: appearanceID
            ),
            affected: [ref],
            snapshots: collector.snapshots
        )
    }

    // MARK: - setSynopsis (§4.3's synopsis PROV set)

    /// Writes `synopsis` and its seven PROV columns — and no other column of the scene.
    ///
    /// `synopsis_created_source` and `synopsis_job_id` answer "who found it" and are
    /// `COALESCE`d rather than assigned, so a later edit never overwrites them (§3.6).
    static func setSynopsis(
        sceneID: UUID,
        text: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .synopsis, id: sceneID)
        if let entry = mode.invertedEntry {
            guard let snapshot = entry.snapshot(table: "scenes", id: sceneID),
                  let current = try RowSnapshotStore.capture(table: "scenes", id: sceneID, in: db)
            else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "That scene is no longer in this project."
                )
            }
            let priorText: String = if case let .string(value)? = current.columns["synopsis"] {
                value
            } else {
                ""
            }
            try RowSnapshotStore.restore(snapshot, in: db)
            return MutationEffect(
                inverse: .setSynopsis(sceneID: sceneID, text: priorText),
                affected: [ref],
                snapshots: [current]
            )
        }

        try requireScene(sceneID, in: db)
        guard let snapshot = try RowSnapshotStore.capture(table: "scenes", id: sceneID, in: db) else {
            throw ProjectStoreError.sceneNotFound
        }
        let source = FactSource(
            rawValue: try String.fetchOne(
                db, sql: "SELECT synopsis_source FROM scenes WHERE id = ?",
                arguments: [sceneID.uuidString]
            ) ?? ""
        )
        let state = ReviewState(
            rawValue: try String.fetchOne(
                db, sql: "SELECT synopsis_review_state FROM scenes WHERE id = ?",
                arguments: [sceneID.uuidString]
            ) ?? ""
        )
        // §3.6/§3.7 for the synopsis field: a `synopsis` or whole-record lock on the
        // **scene** refuses for both actors, and `.ai` may not overwrite a synopsis a
        // person wrote or accepted.
        try ProtectionPolicy.checkSynopsisEdit(
            sceneID: sceneID, source: source, reviewState: state, actor: actor, in: db
        )

        let priorText: String = if case let .string(value)? = snapshot.columns["synopsis"] {
            value
        } else {
            ""
        }
        let timestamp = UTCDate.string(from: Date())
        let isHuman = actor == .human
        try db.execute(
            sql: """
                UPDATE scenes
                SET synopsis = ?,
                    synopsis_source = ?,
                    synopsis_created_source = COALESCE(synopsis_created_source, ?),
                    synopsis_review_state = ?,
                    synopsis_reviewed_at = COALESCE(?, synopsis_reviewed_at),
                    synopsis_job_id = COALESCE(synopsis_job_id, ?),
                    synopsis_updated_at = ?
                WHERE id = ?
                """,
            arguments: [
                text,
                actor.factSource.rawValue,
                actor.factSource.rawValue,
                (isHuman ? ReviewState.accepted : (state ?? .proposed)).rawValue,
                isHuman ? timestamp : nil,
                actor.jobID?.uuidString,
                timestamp,
                sceneID.uuidString,
            ]
        )
        return MutationEffect(
            inverse: .setSynopsis(sceneID: sceneID, text: priorText),
            affected: [ref],
            snapshots: [snapshot]
        )
    }

    // MARK: - Preconditions (§3.8)

    /// The `setSceneEntity` inverse restores a row by original id, so the row it names
    /// has to be either still there or free to come back — `(scene_id, entity_id, role)`
    /// is unique (§4.3).
    static func precheckSceneEntity(
        appearanceID: UUID?,
        entry: JournalEntry,
        in db: Database
    ) throws {
        guard let appearanceID else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer names the appearance it touched."
            )
        }
        guard let snapshot = entry.snapshot(table: "scene_entities", id: appearanceID) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has an appearance to restore."
            )
        }
        if try !RowSnapshotStore.isPresent(snapshot, in: db),
           try RowSnapshotStore.wouldCollide(snapshot, in: db) {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Restoring that change would collide with something added since."
            )
        }
    }

    static func precheckRemoveSceneEntity(appearanceID: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "scene_entities", id: appearanceID, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change added is already gone."
            )
        }
    }

    static func precheckSynopsis(sceneID: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "scenes", id: sceneID, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That scene is no longer in this project."
            )
        }
    }
}
