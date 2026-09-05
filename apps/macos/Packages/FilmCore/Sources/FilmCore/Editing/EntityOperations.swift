import Foundation
import GRDB

/// The scalar entity operations of PHASE1_DESIGN §6.
///
/// Plan 005 step 1 implements `renameEntity` alone — the one op that exercises every part
/// of the engine (a row overwritten, a row created, provenance stamped, an inverse that
/// must restore both). Steps 2–4 add the rest beside it.
enum EntityOperations {

    /// §6's rename: the previous name becomes an alias unless that normalized form is
    /// already on the entity (§3.5), and a human edit flips the row to
    /// `source = 'human'` / `review_state = 'accepted'` and stamps `reviewed_at` while
    /// leaving `created_source` and `job_id` exactly as inserted (§3.6).
    static func rename(
        id: UUID,
        to name: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            // Undo/redo of a rename: restore the entity row's snapshotted columns and put
            // the alias the rename created back, or take it away again (§3.8).
            //
            // The name is read **before** the restore: this operation's own inverse is the
            // redo, which must put back the name the restore is about to overwrite.
            guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
            let restored = try InverseApplication.restoreAffected(
                of: entry,
                kinds: [.entity, .alias],
                ownedBy: id,
                in: db
            )
            return MutationEffect(
                inverse: .renameEntity(id: id, kind: entity.kind, name: entity.name),
                affected: restored.affected,
                snapshots: restored.snapshots
            )
        }

        guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
        // §3.6/§3.7: the parser owns a parser entity's name, a locked name is read-only
        // until an explicit unlock, and AI may not rewrite a protected row.
        try ProtectionPolicy.checkEntityEdit(entity, field: .name, actor: actor, in: db)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.invalidName(reason: "A name cannot be empty.")
        }
        let normalized = EntityNormalization.normalize(trimmed)
        if let conflicting = try conflictingEntityID(
            projectID: entity.projectID, kind: entity.kind, normalized: normalized, excluding: id, in: db
        ) {
            throw ProjectStoreError.nameConflict(existingEntityID: conflicting)
        }

        let now = Date()
        let timestamp = UTCDate.string(from: now)
        var affected: Set<SubjectRef> = [SubjectRef(kind: .entity, id: id)]
        var snapshots: [RowSnapshot] = []
        if let snapshot = try RowSnapshotStore.capture(table: "entities", id: id, in: db) {
            snapshots.append(snapshot)
        }

        // §3.5: the previous surface form survives as an alias, so a later run maps it to
        // the renamed entity instead of creating a duplicate.
        if let aliasID = try insertPreviousNameAlias(entity: entity, actor: actor, now: now, in: db) {
            affected.insert(SubjectRef(kind: .alias, id: aliasID))
        }

        try db.execute(
            sql: """
                UPDATE entities
                SET name = ?, name_normalized = ?, source = ?, review_state = ?,
                    reviewed_at = COALESCE(?, reviewed_at), updated_at = ?
                WHERE id = ?
                """,
            arguments: [
                trimmed, normalized, actor.factSource.rawValue,
                actor == .human ? ReviewState.accepted.rawValue : entity.reviewState.rawValue,
                actor == .human ? timestamp : nil,
                timestamp, id.uuidString,
            ]
        )

        return MutationEffect(
            inverse: .renameEntity(id: id, kind: entity.kind, name: entity.name),
            affected: affected,
            snapshots: snapshots
        )
    }

    /// The rename inverse's own preconditions, re-checked **before any write** (§3.8).
    static func precheckRename(
        id: UUID,
        name: String,
        entry: JournalEntry,
        in db: Database
    ) throws {
        guard let entity = try fetch(id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That item is no longer in this project."
            )
        }
        let normalized = EntityNormalization.normalize(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if try conflictingEntityID(
            projectID: entity.projectID, kind: entity.kind, normalized: normalized, excluding: id, in: db
        ) != nil {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Another item of that kind is now named “\(name)”."
            )
        }
        try InverseApplication.precheckAffected(of: entry, kinds: [.entity, .alias], in: db)
    }

    // MARK: - Row access

    /// The columns a scalar entity operation needs, without decoding the whole domain row.
    struct EntityRow {
        let id: UUID
        let projectID: UUID
        let kind: EntityKind
        let name: String
        let nameNormalized: String
        let description: String
        let parentID: UUID?
        let isRelevant: Bool
        let source: FactSource
        let createdSource: FactSource
        let reviewState: ReviewState
        let jobID: UUID?

        var ref: SubjectRef { SubjectRef(kind: .entity, id: id) }
    }

    static func fetch(id: UUID, in db: Database) throws -> EntityRow? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM entities WHERE id = ?",
            arguments: [id.uuidString]
        ) else { return nil }
        guard let kind = EntityKind(rawValue: row["kind"]),
              let source = FactSource(rawValue: row["source"]),
              let createdSource = FactSource(rawValue: row["created_source"]),
              let reviewState = ReviewState(rawValue: row["review_state"])
        else { throw ProjectStoreError.invalidBundle }
        return EntityRow(
            id: try UUID.required(row["id"]),
            projectID: try UUID.required(row["project_id"]),
            kind: kind,
            name: row["name"],
            nameNormalized: row["name_normalized"],
            description: row["description"],
            parentID: try (row["parent_id"] as String?).map(UUID.required),
            isRelevant: (row["is_relevant"] as Int) != 0,
            source: source,
            createdSource: createdSource,
            reviewState: reviewState,
            jobID: try (row["job_id"] as String?).map(UUID.required)
        )
    }

    /// The entity of that kind already holding `normalized` as its name, if any.
    static func conflictingEntityID(
        projectID: UUID,
        kind: EntityKind,
        normalized: String,
        excluding id: UUID,
        in db: Database
    ) throws -> UUID? {
        guard let raw = try String.fetchOne(
            db,
            sql: """
                SELECT id FROM entities
                WHERE project_id = ? AND kind = ? AND name_normalized = ? AND id <> ?
                """,
            arguments: [projectID.uuidString, kind.rawValue, normalized, id.uuidString]
        ) else { return nil }
        return try UUID.required(raw)
    }

    /// Inserts the entity's current name as an alias, or returns `nil` when that
    /// normalized form is already on the entity (§3.5's conditional insert).
    private static func insertPreviousNameAlias(
        entity: EntityRow,
        actor: MutationActor,
        now: Date,
        in db: Database
    ) throws -> UUID? {
        let normalized = entity.nameNormalized
        if let row = try Row.fetchOne(
            db,
            sql: """
                SELECT id, entity_id FROM entity_aliases
                WHERE project_id = ? AND kind = ? AND normalized = ?
                """,
            arguments: [entity.projectID.uuidString, entity.kind.rawValue, normalized]
        ) {
            let owner = try UUID.required(row["entity_id"])
            // On the same entity the insert is skipped; on another entity the normalized
            // form is taken project-and-kind-wide (§3.5) and the UI offers Merge.
            guard owner == entity.id else {
                throw ProjectStoreError.aliasConflict(existingEntityID: owner)
            }
            return nil
        }

        let aliasID = UUID()
        let timestamp = UTCDate.string(from: now)
        // A `.human` insert is born accepted and reviewed; an `.ai` insert never is (§3.6).
        let isHuman = actor == .human
        try db.execute(
            sql: """
                INSERT INTO entity_aliases (
                    id, entity_id, project_id, kind, alias, normalized, alias_kind,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                aliasID.uuidString, entity.id.uuidString, entity.projectID.uuidString,
                entity.kind.rawValue, entity.name, normalized,
                (isHuman ? AliasKind.human : AliasKind.mention).rawValue,
                actor.factSource.rawValue,
                (isHuman ? ReviewState.accepted : ReviewState.proposed).rawValue,
                isHuman ? timestamp : nil,
                actor.jobID?.uuidString,
                actor.factSource.rawValue, timestamp, timestamp,
            ]
        )
        return aliasID
    }
}

// MARK: - Provenance (§3.6)

extension EntityOperations {
    /// The assignment every scalar edit of a fact row shares.
    ///
    /// A human edit converts the row to `source = 'human'` / `review_state = 'accepted'`
    /// and stamps `reviewed_at`; an `.ai` edit leaves the verdict where it was and
    /// **never** writes `reviewed_at`. `created_source` and `job_id` are never in the list:
    /// they answer "who found this", and a later edit may not overwrite that (§7.2).
    static let provenanceAssignment = """
        source = ?, review_state = ?, reviewed_at = COALESCE(?, reviewed_at), updated_at = ?
        """

    static func provenanceArguments(
        actor: MutationActor,
        current: ReviewState,
        timestamp: String
    ) -> StatementArguments {
        [
            actor.factSource.rawValue,
            actor == .human ? ReviewState.accepted.rawValue : current.rawValue,
            actor == .human ? timestamp : nil,
            timestamp,
        ]
    }

    /// Restores the rows an entry touched and hands back the operation that would apply it
    /// again — the shape every scalar entity op's `.inverting` branch shares (§3.8).
    ///
    /// The current row is read **before** the restore: this operation's own inverse is the
    /// redo, which must put back the values the restore is about to overwrite.
    static func invertScalar(
        id: UUID,
        entry: JournalEntry,
        kinds: Set<SubjectKind>,
        redo: (EntityRow) -> EditOperation,
        in db: Database
    ) throws -> MutationEffect {
        guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
        let restored = try InverseApplication.restoreAffected(
            of: entry, kinds: kinds, ownedBy: id, in: db
        )
        return MutationEffect(
            inverse: redo(entity),
            affected: restored.affected,
            snapshots: restored.snapshots
        )
    }
}

// MARK: - createEntity (§6)

extension EntityOperations {
    /// §6's create. The id travels in the operation so a redo restores the row it first
    /// created, and a name that resolves to a **rejected** tombstone is refused rather
    /// than resurrected (§3.6, §8.5 rule 2).
    static func create(
        id: UUID,
        kind: EntityKind,
        name: String,
        description: String,
        actor: MutationActor,
        mode: MutationMode = .apply,
        in db: Database
    ) throws -> MutationEffect {
        let projectID = try projectID(in: db)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.invalidName(reason: "A name cannot be empty.")
        }
        let normalized = EntityNormalization.normalize(trimmed)

        // The tombstone wins over the name conflict: a rejected row *is* a row of that
        // name, `UNIQUE(project_id, kind, name_normalized)` would refuse the insert either
        // way, and `.rejected` says why. The **alias** branch is narrower: it is §8.5's
        // rule for a run's proposals, so a person who types a name a rejected entity
        // merely lists as an alias is creating a new entity, not resurrecting the old one.
        if let tombstone = try rejectedTombstone(
            projectID: projectID,
            kind: kind,
            normalized: normalized,
            matchingAliases: actor != .human,
            in: db
        ) {
            throw ProjectStoreError.rejected(subject: SubjectRef(kind: .entity, id: tombstone))
        }
        if let conflicting = try conflictingEntityID(
            projectID: projectID, kind: kind, normalized: normalized, excluding: id, in: db
        ) {
            throw ProjectStoreError.nameConflict(existingEntityID: conflicting)
        }

        let timestamp = UTCDate.string(from: Date())
        let isHuman = actor == .human
        try db.execute(
            sql: """
                INSERT INTO entities (
                    id, project_id, kind, name, name_normalized, description, parent_id,
                    is_relevant, source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, NULL, 1, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString, projectID.uuidString, kind.rawValue, trimmed, normalized,
                description,
                actor.factSource.rawValue,
                (isHuman ? ReviewState.accepted : ReviewState.proposed).rawValue,
                isHuman ? timestamp : nil,
                actor.jobID?.uuidString,
                // Every insert sets `created_source = source` (§3.6).
                actor.factSource.rawValue, timestamp, timestamp,
            ]
        )
        return MutationEffect(
            inverse: .deleteEntity(id: id, kind: kind),
            affected: [SubjectRef(kind: .entity, id: id)]
        )
    }

    /// The `rejected` row a normalized name — or, for a non-human actor, a normalized
    /// alias — of that kind resolves to (§3.6, §8.5 rule 2).
    static func rejectedTombstone(
        projectID: UUID,
        kind: EntityKind,
        normalized: String,
        matchingAliases: Bool,
        in db: Database
    ) throws -> UUID? {
        if let raw = try String.fetchOne(
            db,
            sql: """
                SELECT id FROM entities
                WHERE project_id = ? AND kind = ? AND name_normalized = ?
                  AND review_state = 'rejected'
                """,
            arguments: [projectID.uuidString, kind.rawValue, normalized]
        ) {
            return try UUID.required(raw)
        }
        guard matchingAliases else { return nil }
        if let raw = try String.fetchOne(
            db,
            sql: """
                SELECT entities.id FROM entity_aliases
                JOIN entities ON entities.id = entity_aliases.entity_id
                WHERE entity_aliases.project_id = ? AND entity_aliases.kind = ?
                  AND entity_aliases.normalized = ? AND entities.review_state = 'rejected'
                """,
            arguments: [projectID.uuidString, kind.rawValue, normalized]
        ) {
            return try UUID.required(raw)
        }
        return nil
    }

    /// The one project row's id (§4.3: a bundle holds exactly one).
    static func projectID(in db: Database) throws -> UUID {
        guard let raw = try String.fetchOne(db, sql: "SELECT id FROM projects LIMIT 1") else {
            throw ProjectStoreError.missingProject
        }
        return try UUID.required(raw)
    }
}

// MARK: - deleteEntity and restoreEntity (§6, §3.8)

extension EntityOperations {
    /// §6's hard delete: allowed only on a `human` row or one that is already `rejected`.
    /// Everything else is a tombstone case, and the UI's Delete calls `rejectEntity`.
    ///
    /// The whole graph — aliases, appearances, states, events, relationships, evidence,
    /// child locations, and every lock row over any of them — is snapshotted first, so
    /// `restoreEntity` puts it all back with its **original ids**.
    static func delete(
        id: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
        // An inverse restores a state the project already had, so both rules below are
        // rules about *new* deletions only.
        if case .apply = mode {
            // Protection first: §3.6 answers an `.ai` delete of a parser entity with
            // `.parserOwned` and of a protected one with `.protectedFact`, and a lock on
            // the entity — whole or field — refuses the delete for either actor (§3.7).
            try ProtectionPolicy.checkEntityEdit(entity, field: .whole, actor: actor, in: db)
            guard entity.source == .human || entity.reviewState == .rejected else {
                throw ProjectStoreError.rejectInsteadOfDelete(entityID: id)
            }
        } else if mode.isReplacingAIProposal {
            guard entity.source == .ai, entity.reviewState == .proposed else {
                throw ProjectStoreError.protectedFact(subject: entity.ref)
            }
        }

        // PHASE2_DESIGN §7.4: refused while any of this entity's requirements has an asset.
        // The FK is `ON DELETE RESTRICT`, so the Swift precheck is what turns a raw
        // mid-cascade constraint failure into "delete this entity's assets first".
        try EntityRequirementInteractions.requireNoAssets(ofEntity: id, in: db)

        let graph = try captureGraph(of: entity, in: db)
        for evidenceID in graph.evidenceIDs {
            try RowSnapshotStore.delete(table: "evidence", id: evidenceID, in: db)
        }
        for basisID in graph.basisIDs {
            try RowSnapshotStore.delete(table: "asset_requirement_basis", id: basisID, in: db)
        }
        for subject in graph.lockSubjects {
            try RowSnapshotStore.deleteLocks(subject: subject, in: db)
        }
        // `ON DELETE CASCADE` takes the aliases, appearances, states, events, and
        // relationships; `ON DELETE SET NULL` clears the child locations' `parent_id`.
        try RowSnapshotStore.delete(table: "entities", id: id, in: db)

        return MutationEffect(
            inverse: .restoreEntity(graph: graph.snapshots),
            affected: graph.affected,
            snapshots: graph.snapshots
        )
    }

    /// `deleteEntity`'s inverse: the whole graph back by original id (§3.8's table).
    static func restore(graph: [RowSnapshot], in db: Database) throws -> MutationEffect {
        // Read the entity the graph is about **before** restoring: afterwards every row is
        // present and "the one that was missing" is no longer answerable.
        var subject: (id: UUID, kind: EntityKind)?
        var firstEntity: (id: UUID, kind: EntityKind)?
        for snapshot in graph where snapshot.table == "entities" {
            guard case let .string(rawID)? = snapshot.columns["id"],
                  let id = UUID(uuidString: rawID),
                  case let .string(rawKind)? = snapshot.columns["kind"],
                  let kind = EntityKind(rawValue: rawKind)
            else { continue }
            if firstEntity == nil { firstEntity = (id, kind) }
            if try !RowSnapshotStore.isPresent(snapshot, in: db) { subject = (id, kind) }
        }
        guard let restored = subject ?? firstEntity else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has anything to restore."
            )
        }

        try RowGraph.restore(graph, in: db)
        return MutationEffect(
            inverse: .deleteEntity(id: restored.id, kind: restored.kind),
            affected: RowGraph.subjects(of: graph),
            snapshots: []
        )
    }

    /// Everything a delete must snapshot before it runs.
    struct EntityGraphCapture {
        var snapshots: [RowSnapshot] = []
        var affected: Set<SubjectRef> = []
        /// Evidence rows the delete removes by hand: `evidence.subject_id` is polymorphic
        /// and carries no foreign key, so nothing else would take them.
        var evidenceIDs: [UUID] = []
        /// Basis rows the delete removes by hand: `asset_requirement_basis.subject_id` is
        /// polymorphic too, and the ones citing this entity's cascaded facts sit on other
        /// entities' requirements, which no cascade reaches (PHASE2_DESIGN §7.4, §4.3).
        var basisIDs: [UUID] = []
        /// The subjects whose lock rows go with them (§3.7).
        var lockSubjects: [SubjectRef] = []
    }

    static func captureGraph(of entity: EntityRow, in db: Database) throws -> EntityGraphCapture {
        var capture = EntityGraphCapture()
        var collector = SnapshotCollector()
        let id = entity.id
        capture.affected.insert(entity.ref)
        capture.lockSubjects.append(entity.ref)
        try collector.capture(table: "entities", id: id, in: db)

        func dependents(_ table: String, kind: SubjectKind, sql: String, arguments: StatementArguments) throws -> [UUID] {
            var ids: [UUID] = []
            for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
                let rowID = try UUID.required(row["id"])
                ids.append(rowID)
                collector.add(table: table, row: row)
                let ref = SubjectRef(kind: kind, id: rowID)
                capture.affected.insert(ref)
                capture.lockSubjects.append(ref)
            }
            return ids
        }

        let aliasIDs = try dependents(
            "entity_aliases", kind: .alias,
            sql: "SELECT * FROM entity_aliases WHERE entity_id = ? ORDER BY id",
            arguments: [id.uuidString]
        )
        let appearanceIDs = try dependents(
            "scene_entities", kind: .appearance,
            sql: "SELECT * FROM scene_entities WHERE entity_id = ? ORDER BY id",
            arguments: [id.uuidString]
        )
        let stateIDs = try dependents(
            "entity_states", kind: .state,
            sql: "SELECT * FROM entity_states WHERE entity_id = ? ORDER BY id",
            arguments: [id.uuidString]
        )
        let eventIDs = try dependents(
            "continuity_events", kind: .event,
            sql: "SELECT * FROM continuity_events WHERE entity_id = ? ORDER BY id",
            arguments: [id.uuidString]
        )
        let relationshipIDs = try dependents(
            "entity_relationships", kind: .relationship,
            sql: """
                SELECT * FROM entity_relationships
                WHERE from_entity_id = ? OR to_entity_id = ? ORDER BY id
                """,
            arguments: [id.uuidString, id.uuidString]
        )

        // Rows of **other** entities the delete changes without deleting: child locations
        // lose their parent, foreign events lose a `resulting_state_id`, and foreign
        // appearances and evidence lose a `matched_alias_id`.
        for row in try Row.fetchAll(
            db, sql: "SELECT * FROM entities WHERE parent_id = ? ORDER BY id",
            arguments: [id.uuidString]
        ) {
            collector.add(table: "entities", row: row)
            capture.affected.insert(SubjectRef(kind: .entity, id: try UUID.required(row["id"])))
        }
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM continuity_events
                WHERE resulting_state_id IN \(inClause(stateIDs)) AND entity_id IS NOT ?
                ORDER BY id
                """,
            arguments: StatementArguments(stateIDs.map(\.uuidString)) + [id.uuidString]
        ) {
            collector.add(table: "continuity_events", row: row)
            capture.affected.insert(SubjectRef(kind: .event, id: try UUID.required(row["id"])))
        }
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM scene_entities
                WHERE matched_alias_id IN \(inClause(aliasIDs)) AND entity_id <> ?
                ORDER BY id
                """,
            arguments: StatementArguments(aliasIDs.map(\.uuidString)) + [id.uuidString]
        ) {
            collector.add(table: "scene_entities", row: row)
            capture.affected.insert(SubjectRef(kind: .appearance, id: try UUID.required(row["id"])))
        }

        // Evidence the delete must take by hand, plus evidence that merely points at one
        // of the aliases and survives with `matched_alias_id` cleared.
        let owned = try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM evidence
                WHERE owner_entity_id = ?
                   OR (subject_kind = 'entity' AND subject_id = ?)
                   OR (subject_kind = 'alias' AND subject_id IN \(inClause(aliasIDs)))
                   OR (subject_kind = 'appearance' AND subject_id IN \(inClause(appearanceIDs)))
                   OR (subject_kind = 'state' AND subject_id IN \(inClause(stateIDs)))
                   OR (subject_kind = 'event' AND subject_id IN \(inClause(eventIDs)))
                   OR (subject_kind = 'relationship' AND subject_id IN \(inClause(relationshipIDs)))
                ORDER BY id
                """,
            arguments: [id.uuidString, id.uuidString]
                + StatementArguments(aliasIDs.map(\.uuidString))
                + StatementArguments(appearanceIDs.map(\.uuidString))
                + StatementArguments(stateIDs.map(\.uuidString))
                + StatementArguments(eventIDs.map(\.uuidString))
                + StatementArguments(relationshipIDs.map(\.uuidString))
        )
        for row in owned {
            collector.add(table: "evidence", row: row)
            capture.evidenceIDs.append(try UUID.required(row["id"]))
        }
        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM evidence WHERE matched_alias_id IN \(inClause(aliasIDs)) ORDER BY id",
            arguments: StatementArguments(aliasIDs.map(\.uuidString))
        ) {
            collector.add(table: "evidence", row: row)
        }

        // PHASE2_DESIGN §7.4's requirement half: the whole requirement graph the cascade
        // would take — requirements, scene links, basis rows, dependencies in both
        // directions, requirement locks — plus the basis rows citing the states, events,
        // and appearances this delete cascades away, which live on **other** entities'
        // requirements and are swept by hand in the same transaction (§4.3).
        let requirements = try EntityRequirementInteractions.captureRequirementGraph(
            ofEntity: id,
            facts: appearanceIDs.map { SubjectRef(kind: .appearance, id: $0) }
                + stateIDs.map { SubjectRef(kind: .state, id: $0) }
                + eventIDs.map { SubjectRef(kind: .event, id: $0) },
            into: &collector,
            in: db
        )
        capture.affected.formUnion(requirements.affected)
        capture.lockSubjects.append(contentsOf: requirements.lockSubjects)
        capture.basisIDs = requirements.sweptBasis

        for subject in capture.lockSubjects {
            try collector.captureLocks(subject: subject, in: db)
        }
        capture.snapshots = collector.snapshots
        return capture
    }

    /// `IN (?, ?, …)`, or a list nothing matches when there is nothing to match.
    static func inClause(_ ids: [UUID]) -> String {
        ids.isEmpty ? "(NULL)" : "(" + ids.map { _ in "?" }.joined(separator: ", ") + ")"
    }
}

// MARK: - Rejection (§3.6's tombstone)

extension EntityOperations {
    /// §6's reject: the verdict, not a delete. `source`, `created_source`, and `job_id`
    /// stay exactly as they were, aliases and dependent rows are retained — they are what
    /// stops a later run resurrecting the entity.
    static func reject(
        id: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, kinds: [.entity], redo: { entity in
                .unrejectEntity(id: id, kind: entity.kind, priorState: entity.reviewState)
            }, in: db)
        }
        guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
        // A rejection is the tombstone form of a delete, so it answers to the same rule:
        // the parser owns its rows, and a protected row is not the analysis's to retract.
        try ProtectionPolicy.checkEntityEdit(entity, field: .whole, actor: actor, in: db)
        let timestamp = UTCDate.string(from: Date())
        var snapshots: [RowSnapshot] = []
        if let snapshot = try RowSnapshotStore.capture(table: "entities", id: id, in: db) {
            snapshots.append(snapshot)
        }
        try db.execute(
            sql: """
                UPDATE entities
                SET review_state = 'rejected', reviewed_at = COALESCE(?, reviewed_at), updated_at = ?
                WHERE id = ?
                """,
            arguments: [actor == .human ? timestamp : nil, timestamp, id.uuidString]
        )
        return MutationEffect(
            inverse: .unrejectEntity(id: id, kind: entity.kind, priorState: entity.reviewState),
            affected: [entity.ref],
            snapshots: snapshots
        )
    }

    /// §6's unreject: `priorState` when the inverse carried one, the state the tombstone
    /// replaced when the journal still remembers it, else `accepted` for a row the parser
    /// created and `proposed` otherwise — a parser row is never left `proposed`.
    static func unreject(
        id: UUID,
        priorState: ReviewState?,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, kinds: [.entity], redo: { entity in
                .rejectEntity(id: id, kind: entity.kind)
            }, in: db)
        }
        guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
        try ProtectionPolicy.checkEntityEdit(entity, field: .whole, actor: actor, in: db)
        let restored = try priorState
            ?? rememberedState(of: id, in: db)
            ?? (entity.createdSource == .parser ? .accepted : .proposed)
        let timestamp = UTCDate.string(from: Date())
        var snapshots: [RowSnapshot] = []
        if let snapshot = try RowSnapshotStore.capture(table: "entities", id: id, in: db) {
            snapshots.append(snapshot)
        }
        try db.execute(
            sql: """
                UPDATE entities
                SET review_state = ?, reviewed_at = COALESCE(?, reviewed_at), updated_at = ?
                WHERE id = ?
                """,
            arguments: [
                restored.rawValue, actor == .human ? timestamp : nil, timestamp, id.uuidString,
            ]
        )
        return MutationEffect(
            inverse: .rejectEntity(id: id, kind: entity.kind),
            affected: [entity.ref],
            snapshots: snapshots
        )
    }

    /// The `review_state` the newest journalled rejection of this entity snapshotted.
    ///
    /// Scoped through `edit_journal_affected` to this entity's **own** entries and
    /// deliberately unbounded: a tombstone older than the last few hundred edits still has
    /// to remember what it replaced, and a limit would silently drop it to the fallback.
    /// A batch rejection journals one `.batch` row, so its children are searched too.
    static func rememberedState(of id: UUID, in db: Database) throws -> ReviewState? {
        let seqs = try Int64.fetchAll(
            db,
            sql: """
                SELECT seq FROM edit_journal_affected
                WHERE subject_kind = 'entity' AND subject_id = ? ORDER BY seq DESC
                """,
            arguments: [id.uuidString]
        )
        for seq in seqs {
            guard let entry = try JournalStore.entry(seq: seq, in: db), rejects(entry.op, id) else {
                continue
            }
            guard let snapshot = entry.snapshot(table: "entities", id: id),
                  case let .string(raw)? = snapshot.columns["review_state"],
                  let state = ReviewState(rawValue: raw)
            else { continue }
            return state
        }
        return nil
    }

    /// `true` when the operation — or, for a group, one of its children — rejected `id`.
    private static func rejects(_ op: EditOperation, _ id: UUID) -> Bool {
        switch op {
        case let .rejectEntity(rejected, _): rejected == id
        case let .batch(children): children.contains { rejects($0, id) }
        default: false
        }
    }
}

// MARK: - Scalar field edits (§6)

extension EntityOperations {
    static func setDescription(
        id: UUID,
        text: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, kinds: [.entity], redo: { entity in
                .setDescription(id: id, text: entity.description)
            }, in: db)
        }
        guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
        // §3.6's one AI-over-parser allowance: an **empty** parser description may be
        // filled, a written one may not be overwritten.
        try ProtectionPolicy.checkEntityEdit(entity, field: .description, actor: actor, in: db)
        let timestamp = UTCDate.string(from: Date())
        var snapshots: [RowSnapshot] = []
        if let snapshot = try RowSnapshotStore.capture(table: "entities", id: id, in: db) {
            snapshots.append(snapshot)
        }
        var arguments: StatementArguments = [text]
        arguments += provenanceArguments(actor: actor, current: entity.reviewState, timestamp: timestamp)
        arguments += [id.uuidString]
        try db.execute(
            sql: "UPDATE entities SET description = ?, \(provenanceAssignment) WHERE id = ?",
            arguments: arguments
        )
        return MutationEffect(
            inverse: .setDescription(id: id, text: entity.description),
            affected: [entity.ref],
            snapshots: snapshots
        )
    }

    static func setRelevance(
        id: UUID,
        isRelevant: Bool,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, kinds: [.entity], redo: { entity in
                .setRelevance(id: id, isRelevant: entity.isRelevant)
            }, in: db)
        }
        guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
        try ProtectionPolicy.checkEntityEdit(entity, field: .isRelevant, actor: actor, in: db)
        let timestamp = UTCDate.string(from: Date())
        var snapshots: [RowSnapshot] = []
        if let snapshot = try RowSnapshotStore.capture(table: "entities", id: id, in: db) {
            snapshots.append(snapshot)
        }
        var arguments: StatementArguments = [isRelevant ? 1 : 0]
        arguments += provenanceArguments(actor: actor, current: entity.reviewState, timestamp: timestamp)
        arguments += [id.uuidString]
        try db.execute(
            sql: "UPDATE entities SET is_relevant = ?, \(provenanceAssignment) WHERE id = ?",
            arguments: arguments
        )
        return MutationEffect(
            inverse: .setRelevance(id: id, isRelevant: entity.isRelevant),
            affected: [entity.ref],
            snapshots: snapshots
        )
    }

    /// §6's reclassify: the entity's aliases carry to the new kind with it, and
    /// `UNIQUE(project_id, kind, normalized)` is re-checked **there** (§3.5).
    static func reclassify(
        id: UUID,
        kind: EntityKind,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, kinds: [.entity, .alias], redo: { entity in
                .reclassify(id: id, kind: entity.kind)
            }, in: db)
        }
        guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
        try ProtectionPolicy.checkEntityEdit(entity, field: .kind, actor: actor, in: db)
        guard entity.kind != kind else {
            throw ProjectStoreError.invalidName(reason: "That item is already a \(kind.undoNoun.lowercased()).")
        }
        // PHASE2_DESIGN §7.4: refused while the entity has canonical requirement rows,
        // **tombstoned ones included** — a template type is kind-bound and a tombstone
        // keeps its `type_id`. Variant requirements carry across kinds unchanged.
        try EntityRequirementInteractions.requireNoCanonicalRequirements(ofEntity: id, in: db)
        // A location that contains other locations cannot stop being a location (§6).
        if entity.kind == .location, try hasChildren(id: id, in: db) {
            throw ProjectStoreError.invalidParent(
                reason: "This location contains other locations. Move them out before changing its kind."
            )
        }

        let aliasRows = try Row.fetchAll(
            db, sql: "SELECT * FROM entity_aliases WHERE entity_id = ? ORDER BY id",
            arguments: [id.uuidString]
        )
        for row in aliasRows {
            let normalized: String = row["normalized"]
            if let raw = try String.fetchOne(
                db,
                sql: """
                    SELECT entity_id FROM entity_aliases
                    WHERE project_id = ? AND kind = ? AND normalized = ? AND entity_id <> ?
                    """,
                arguments: [entity.projectID.uuidString, kind.rawValue, normalized, id.uuidString]
            ) {
                throw ProjectStoreError.aliasConflict(existingEntityID: try UUID.required(raw))
            }
        }
        if let conflicting = try conflictingEntityID(
            projectID: entity.projectID, kind: kind, normalized: entity.nameNormalized,
            excluding: id, in: db
        ) {
            throw ProjectStoreError.nameConflict(existingEntityID: conflicting)
        }

        let timestamp = UTCDate.string(from: Date())
        var collector = SnapshotCollector()
        var affected: Set<SubjectRef> = [entity.ref]
        try collector.capture(table: "entities", id: id, in: db)
        for row in aliasRows {
            collector.add(table: "entity_aliases", row: row)
            affected.insert(SubjectRef(kind: .alias, id: try UUID.required(row["id"])))
        }

        var arguments: StatementArguments = [kind.rawValue]
        arguments += provenanceArguments(actor: actor, current: entity.reviewState, timestamp: timestamp)
        arguments += [id.uuidString]
        try db.execute(
            sql: "UPDATE entities SET kind = ?, \(provenanceAssignment) WHERE id = ?",
            arguments: arguments
        )
        // `entity_aliases.kind` is a denormalized copy of the entity's kind, so it moves
        // mechanically — the alias's own provenance is not a human edit of that fact.
        try db.execute(
            sql: "UPDATE entity_aliases SET kind = ?, updated_at = ? WHERE entity_id = ?",
            arguments: [kind.rawValue, timestamp, id.uuidString]
        )

        return MutationEffect(
            inverse: .reclassify(id: id, kind: entity.kind),
            affected: affected,
            snapshots: collector.snapshots
        )
    }

    /// §6's "Move into…": locations only, no self-parent, no cycles.
    static func setLocationParent(
        id: UUID,
        parentID: UUID?,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, kinds: [.entity], redo: { entity in
                .setLocationParent(id: id, parentID: entity.parentID)
            }, in: db)
        }
        guard let entity = try fetch(id: id, in: db) else { throw ProjectStoreError.entityNotFound }
        try ProtectionPolicy.checkLocationParentEdit(entity, actor: actor, in: db)
        guard entity.kind == .location else {
            throw ProjectStoreError.invalidParent(reason: "Only locations can be moved into a location.")
        }
        if let parentID {
            guard parentID != id else {
                throw ProjectStoreError.invalidParent(reason: "A location cannot contain itself.")
            }
            guard let parent = try fetch(id: parentID, in: db), parent.kind == .location else {
                throw ProjectStoreError.invalidParent(reason: "A location can only be moved into another location.")
            }
            // Ancestor walk: the new parent may not already sit under this location.
            var cursor: UUID? = parent.parentID
            var seen: Set<UUID> = [parentID]
            while let next = cursor {
                guard next != id else {
                    throw ProjectStoreError.invalidParent(
                        reason: "That would put this location inside one of its own sub-locations."
                    )
                }
                guard seen.insert(next).inserted else { break }
                cursor = try fetch(id: next, in: db)?.parentID
            }
        }

        let timestamp = UTCDate.string(from: Date())
        var snapshots: [RowSnapshot] = []
        if let snapshot = try RowSnapshotStore.capture(table: "entities", id: id, in: db) {
            snapshots.append(snapshot)
        }
        var arguments: StatementArguments = [parentID?.uuidString]
        arguments += provenanceArguments(actor: actor, current: entity.reviewState, timestamp: timestamp)
        arguments += [id.uuidString]
        try db.execute(
            sql: "UPDATE entities SET parent_id = ?, \(provenanceAssignment) WHERE id = ?",
            arguments: arguments
        )
        return MutationEffect(
            inverse: .setLocationParent(id: id, parentID: entity.parentID),
            affected: [entity.ref],
            snapshots: snapshots
        )
    }

    static func hasChildren(id: UUID, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM entities WHERE parent_id = ?)",
            arguments: [id.uuidString]
        ) ?? false
    }
}

// MARK: - Preconditions for the inverses (§3.8)

extension EntityOperations {
    /// Every scalar entity inverse needs the same two things: the row still there, and the
    /// rows the entry touched still restorable.
    static func precheckScalar(id: UUID, entry: JournalEntry, kinds: Set<SubjectKind>, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "entities", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That item is no longer in this project."
            )
        }
        try InverseApplication.precheckAffected(of: entry, kinds: kinds, in: db)
    }

    static func precheckCreate(id: UUID, kind: EntityKind, name: String, in db: Database) throws {
        guard try !RowSnapshotStore.exists(table: "entities", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change removed is already back."
            )
        }
        let projectID = try projectID(in: db)
        let normalized = EntityNormalization.normalize(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if try conflictingEntityID(
            projectID: projectID, kind: kind, normalized: normalized, excluding: id, in: db
        ) != nil {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Another item of that kind is now named “\(name)”."
            )
        }
    }
}
