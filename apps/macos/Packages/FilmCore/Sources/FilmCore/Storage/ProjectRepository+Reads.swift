import Foundation
import GRDB

/// Every `ProjectReading` member over schema v2 (PHASE1_DESIGN §6).
///
/// The reads live beside the writes but in their own file: Plan 004 adds views over
/// them, and `ProjectSession` should stay a thin actor over this type.
extension ProjectRepository {
    // MARK: - Script-scoped reads

    /// The id of `projects.current_script_id`, or `nil` before the first import.
    private func currentScriptID(_ db: Database) throws -> UUID? {
        guard let raw = try String.fetchOne(db, sql: "SELECT current_script_id FROM projects") else {
            return nil
        }
        return try UUID.required(raw)
    }

    func scenes() throws -> [Scene] {
        try database.queue.read { db in
            guard let scriptID = try currentScriptID(db) else { return [] }
            return try Row
                .fetchAll(
                    db,
                    sql: "SELECT * FROM scenes WHERE script_id = ? ORDER BY ordinal",
                    arguments: [scriptID.uuidString]
                )
                .map(decodeScene)
        }
    }

    func sceneDetail(id: UUID) throws -> SceneDetail {
        try database.queue.read { db in
            guard let sceneRow = try Row.fetchOne(
                db,
                sql: "SELECT * FROM scenes WHERE id = ?",
                arguments: [id.uuidString]
            ) else { throw ProjectStoreError.sceneNotFound }
            let scene = try decodeScene(sceneRow)

            let appearanceRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT scene_entities.*, entities.name AS entity_name
                    FROM scene_entities
                    JOIN entities ON entities.id = scene_entities.entity_id
                    WHERE scene_entities.scene_id = ?
                    ORDER BY scene_entities.role, entities.name
                    """,
                arguments: [id.uuidString]
            )
            let appearances = try appearanceRows.map(decodeSceneEntity)

            var entitiesByID: [UUID: Entity] = [:]
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT entities.* FROM entities
                    JOIN scene_entities ON scene_entities.entity_id = entities.id
                    WHERE scene_entities.scene_id = ?
                    """,
                arguments: [id.uuidString]
            ) {
                let entity = try decodeEntity(row)
                entitiesByID[entity.id] = entity
            }
            var entitiesByRole: [SceneEntityRole: [Entity]] = [:]
            for appearance in appearances {
                guard let entity = entitiesByID[appearance.entityID] else { continue }
                entitiesByRole[appearance.role, default: []].append(entity)
            }

            // Active anywhere in this scene's ordinal span; an open-ended state runs to the end.
            let states = try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT entity_states.* FROM entity_states
                        JOIN scenes AS start_scene ON start_scene.id = entity_states.start_scene_id
                        LEFT JOIN scenes AS end_scene ON end_scene.id = entity_states.end_scene_id
                        WHERE start_scene.script_id = ?
                          AND start_scene.ordinal <= ?
                          AND (entity_states.end_scene_id IS NULL OR end_scene.ordinal >= ?)
                        ORDER BY entity_states.rowid
                        """,
                    arguments: [scene.scriptID.uuidString, scene.ordinal, scene.ordinal]
                )
                .map(decodeEntityState)

            // Every ownerless row belongs to the scene: synopsis evidence plus evidence
            // for a scene-wide continuity event. Entity-owned rows remain in exactly one
            // `EntityDetail.evidence`, so the two read shapes still partition the table.
            let evidence = try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT * FROM evidence
                        WHERE scene_id = ? AND owner_entity_id IS NULL
                        ORDER BY rowid
                        """,
                    arguments: [id.uuidString]
                )
                .map(decodeEvidence)

            return SceneDetail(
                scene: scene,
                appearances: appearances,
                entitiesByRole: entitiesByRole,
                states: states,
                evidence: evidence
            )
        }
    }

    /// The human override when present, otherwise the scene's imported screenplay slice.
    func sceneText(id: UUID) throws -> String {
        try database.queue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT scenes.start_utf16 AS start_utf16, scenes.end_utf16 AS end_utf16,
                           scenes.screenplay_override AS screenplay_override,
                           scripts.source_text AS source_text
                    FROM scenes JOIN scripts ON scripts.id = scenes.script_id
                    WHERE scenes.id = ?
                    """,
                arguments: [id.uuidString]
            ) else { throw ProjectStoreError.sceneNotFound }
            if let override: String = row["screenplay_override"] { return override }
            let text: String = row["source_text"]
            let start: Int = row["start_utf16"]
            let end: Int = row["end_utf16"]
            return text.utf16Slice(start: start, end: end)
        }
    }

    func sceneReferenceExclusionID(
        sceneID: UUID,
        requirementID: UUID
    ) throws -> UUID? {
        try database.queue.read { db in
            guard let raw = try String.fetchOne(
                db,
                sql: """
                    SELECT id FROM scene_reference_exclusions
                    WHERE scene_id = ? AND requirement_id = ?
                    """,
                arguments: [sceneID.uuidString, requirementID.uuidString]
            ) else { return nil }
            return try UUID.required(raw)
        }
    }

    func sceneExclusions(id: UUID) throws -> [SceneExclusion] {
        try database.queue.read { db in
            try Row
                .fetchAll(
                    db,
                    sql: "SELECT * FROM scene_exclusions WHERE scene_id = ? ORDER BY start_utf16, end_utf16",
                    arguments: [id.uuidString]
                )
                .map(decodeSceneExclusion)
        }
    }

    func sequences() throws -> [ScriptSequence] {
        try database.queue.read { db in
            guard let scriptID = try currentScriptID(db) else { return [] }
            return try Row
                .fetchAll(
                    db,
                    sql: "SELECT * FROM sequences WHERE script_id = ? ORDER BY ordinal",
                    arguments: [scriptID.uuidString]
                )
                .map(decodeScriptSequence)
        }
    }

    /// Scene-ordinal order; rows whose `entity_id` is `NULL` are included.
    func continuityEvents() throws -> [ContinuityEvent] {
        try database.queue.read { db in
            try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT continuity_events.* FROM continuity_events
                        JOIN scenes ON scenes.id = continuity_events.scene_id
                        ORDER BY scenes.ordinal, continuity_events.rowid
                        """
                )
                .map(decodeContinuityEvent)
        }
    }

    // MARK: - Entities

    /// The shared `WHERE` of `entities` and `entitySummaries`.
    private func entityFilter(
        kind: EntityKind?,
        reviewState: ReviewState?,
        includeIrrelevant: Bool,
        includeRejected: Bool
    ) -> (sql: String, arguments: StatementArguments) {
        var clauses: [String] = []
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let kind {
            clauses.append("entities.kind = ?")
            arguments.append(kind.rawValue)
        }
        if let reviewState {
            clauses.append("entities.review_state = ?")
            arguments.append(reviewState.rawValue)
        }
        if !includeIrrelevant { clauses.append("entities.is_relevant = 1") }
        if !includeRejected { clauses.append("entities.review_state <> 'rejected'") }
        let sql = clauses.isEmpty ? "1" : clauses.joined(separator: " AND ")
        return (sql, StatementArguments(arguments))
    }

    func entities(
        kind: EntityKind?,
        reviewState: ReviewState?,
        includeIrrelevant: Bool,
        includeRejected: Bool
    ) throws -> [Entity] {
        let filter = entityFilter(
            kind: kind,
            reviewState: reviewState,
            includeIrrelevant: includeIrrelevant,
            includeRejected: includeRejected
        )
        return try database.queue.read { db in
            try Row
                .fetchAll(
                    db,
                    sql: "SELECT entities.* FROM entities WHERE \(filter.sql) ORDER BY entities.kind, entities.name",
                    arguments: filter.arguments
                )
                .map(decodeEntity)
        }
    }

    func entitySummaries(
        kind: EntityKind?,
        reviewState: ReviewState?,
        includeIrrelevant: Bool,
        includeRejected: Bool
    ) throws -> [EntitySummary] {
        let filter = entityFilter(
            kind: kind,
            reviewState: reviewState,
            includeIrrelevant: includeIrrelevant,
            includeRejected: includeRejected
        )
        return try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT entities.id AS id, entities.kind AS kind, entities.name AS name,
                           entities.review_state AS review_state,
                           entities.confidence AS confidence,
                           EXISTS (
                               SELECT 1 FROM evidence
                               WHERE evidence.owner_entity_id = entities.id
                                 AND evidence.anchored = 0
                           ) AS has_unanchored_evidence,
                           EXISTS (
                               SELECT 1 FROM locks
                               WHERE locks.subject_kind = 'entity' AND locks.subject_id = entities.id
                           ) AS is_locked,
                           (
                               SELECT COUNT(*) FROM scene_entities
                               WHERE scene_entities.entity_id = entities.id
                           ) AS appearance_count
                    FROM entities
                    WHERE \(filter.sql)
                    ORDER BY entities.kind, entities.name
                    """,
                arguments: filter.arguments
            ).map { row in
                guard let kind = EntityKind(rawValue: row["kind"]),
                      let reviewState = ReviewState(rawValue: row["review_state"])
                else { throw ProjectStoreError.invalidBundle }
                return EntitySummary(
                    id: try UUID.required(row["id"]),
                    kind: kind,
                    name: row["name"],
                    reviewState: reviewState,
                    confidence: row["confidence"],
                    hasUnanchoredEvidence: (row["has_unanchored_evidence"] as Int) != 0,
                    isLocked: (row["is_locked"] as Int) != 0,
                    appearanceCount: row["appearance_count"]
                )
            }
        }
    }

    func entityDetail(id: UUID) throws -> EntityDetail {
        try database.queue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM entities WHERE id = ?",
                arguments: [id.uuidString]
            ) else { throw ProjectStoreError.entityNotFound }
            let entity = try decodeEntity(row)
            let key = id.uuidString

            let aliases = try Row
                .fetchAll(
                    db,
                    sql: "SELECT * FROM entity_aliases WHERE entity_id = ? ORDER BY normalized",
                    arguments: [key]
                )
                .map(decodeEntityAlias)
            let appearances = try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT scene_entities.* FROM scene_entities
                        JOIN scenes ON scenes.id = scene_entities.scene_id
                        WHERE scene_entities.entity_id = ?
                        ORDER BY scenes.ordinal, scene_entities.role
                        """,
                    arguments: [key]
                )
                .map(decodeSceneEntity)
            let states = try Row
                .fetchAll(
                    db,
                    sql: "SELECT * FROM entity_states WHERE entity_id = ? ORDER BY rowid",
                    arguments: [key]
                )
                .map(decodeEntityState)
            let events = try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT continuity_events.* FROM continuity_events
                        JOIN scenes ON scenes.id = continuity_events.scene_id
                        WHERE continuity_events.entity_id = ?
                        ORDER BY scenes.ordinal, continuity_events.rowid
                        """,
                    arguments: [key]
                )
                .map(decodeContinuityEvent)
            let relationships = try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT * FROM entity_relationships
                        WHERE from_entity_id = ? OR to_entity_id = ?
                        ORDER BY rowid
                        """,
                    arguments: [key, key]
                )
                .map(decodeEntityRelationship)
            // Every row this entity owns — the complement of the synopsis rows in `SceneDetail`.
            let evidence = try Row
                .fetchAll(
                    db,
                    sql: "SELECT * FROM evidence WHERE owner_entity_id = ? ORDER BY rowid",
                    arguments: [key]
                )
                .map(decodeEvidence)
            let locks = try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT * FROM locks
                        WHERE subject_kind = 'entity' AND subject_id = ?
                        ORDER BY field
                        """,
                    arguments: [key]
                )
                .map(decodeLock)
            // PHASE2_DESIGN §4.4: the entity inspector shows its manifest slots, canonical
            // before variant. No rule is applied here — the derived flags belong to
            // `requirementSummaries` / `requirement(id:)`, which run them through
            // `ManifestQualification`.
            let requirements = try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT * FROM asset_requirements
                        WHERE entity_id = ?
                        ORDER BY CASE tier WHEN 'canonical' THEN 0 ELSE 1 END, name_normalized
                        """,
                    arguments: [key]
                )
                .map(decodeAssetRequirement)

            return EntityDetail(
                entity: entity,
                aliases: aliases,
                appearances: appearances,
                states: states,
                events: events,
                relationships: relationships,
                evidence: evidence,
                locks: locks,
                requirements: requirements
            )
        }
    }

    // MARK: - Locks, journal, review, runs

    func locks() throws -> [Lock] {
        try database.queue.read { db in
            try Row
                .fetchAll(db, sql: "SELECT * FROM locks ORDER BY subject_kind, subject_id, field")
                .map(decodeLock)
        }
    }

    /// The most recent `limit` entries, newest first.
    func journal(limit: Int) throws -> [JournalEntry] {
        try database.queue.read { db in try JournalStore.newest(limit: limit, in: db) }
    }

    /// Every fact row still awaiting a verdict, including scene synopses.
    func pendingReviewCount() throws -> Int {
        try database.queue.read { db in
            var total = 0
            let tables = [
                "sequences", "entities", "entity_aliases", "scene_entities",
                "entity_states", "continuity_events", "entity_relationships",
            ]
            for table in tables {
                total += try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE review_state = 'proposed'"
                ) ?? 0
            }
            total += try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM scenes WHERE synopsis_review_state = 'proposed'"
            ) ?? 0
            return total
        }
    }

    func extractionProtectionSummary() throws -> ExtractionProtectionSummary {
        try database.queue.read { db in
            let tables = [
                "sequences", "entities", "entity_aliases", "scene_entities",
                "entity_states", "continuity_events", "entity_relationships",
            ]
            var accepted = 0
            for table in tables {
                accepted += try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE review_state = 'accepted' AND reviewed_at IS NOT NULL"
                ) ?? 0
            }
            accepted += try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM scenes WHERE synopsis_review_state = 'accepted' AND synopsis_reviewed_at IS NOT NULL"
            ) ?? 0
            let locked = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM locks") ?? 0
            return ExtractionProtectionSummary(acceptedFacts: accepted, lockedFacts: locked)
        }
    }

    /// Parent jobs, oldest first, reporting the aggregate usage apply stored on the parent.
    func runs() throws -> [RunSummary] {
        try database.queue.read { db in
            let parents = try Row
                .fetchAll(db, sql: "SELECT * FROM jobs WHERE parent_job_id IS NULL ORDER BY rowid")
                .map(decodeJob)
            return try parents.enumerated().map { index, parent in
                let children = try Row
                    .fetchAll(
                        db,
                        sql: "SELECT * FROM jobs WHERE parent_job_id = ? ORDER BY rowid",
                        arguments: [parent.id.uuidString]
                    )
                    .map(decodeJob)
                return RunSummary(
                    job: parent,
                    runNumber: index + 1,
                    childCount: children.count,
                    // §8.5: apply writes the sum over this run's leaves onto the parent row in
                    // its single transaction, so re-summing children here would double-count it.
                    usage: parent.usage
                )
            }
        }
    }

    func disclosureAcknowledgedAt() throws -> Date? {
        try database.queue.read { db in
            guard let raw = try String.fetchOne(
                db,
                sql: "SELECT disclosure_acknowledged_at FROM projects"
            ) else { return nil }
            return try UTCDate.date(from: raw)
        }
    }
}

extension String {
    /// The `[start, end)` UTF-16 slice, clamped to this string's bounds.
    func utf16Slice(start: Int, end: Int) -> String {
        let units = Array(utf16)
        let lower = min(max(0, start), units.count)
        let upper = min(max(lower, end), units.count)
        return String(decoding: units[lower..<upper], as: UTF16.self)
    }
}
