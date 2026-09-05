import Foundation
import GRDB

/// States, continuity events, and relationships (PHASE1_DESIGN §4.3, §6).
///
/// The three tables share one shape: an `add` that can also **restore** a hard-deleted row
/// by its original id, an `edit` whose inverse restores the snapshotted row, and a
/// `remove` that tombstones what it may not delete (§6).
enum ContinuityOperations {

    /// `removeState` / `removeEvent` / `removeRelationship` hard-delete a `human` row and
    /// tombstone everything else — the same rule `deleteEntity` follows, for the same
    /// reason: the tombstone is what stops a later run resurrecting the row (§3.6).
    static func isHardDeletable(source: FactSource, reviewState: ReviewState) -> Bool {
        source == .human || reviewState == .rejected
    }

    /// `true` when the remove is the **inverse** of the entry that created this row.
    ///
    /// §3.6's tombstone is a rule about a person taking out a row the project already had;
    /// §3.8's inverse rule — "delete every row the entry created", the one
    /// `InverseApplication.restoreAffected` follows — outranks it here. Without this, undo
    /// of an `.ai(jobID)` `addState` (and selective revert of the run that made it) would
    /// leave a `rejected` row behind instead of the state the project was in, and
    /// `ReviewOperations` would refuse the inverse outright: the entry that created the row
    /// snapshotted nothing, so there is no verdict to restore.
    ///
    /// An entry that **snapshotted** the row overwrote or removed one that already existed,
    /// so the tombstone rule still applies to it.
    static func createdByInvertedEntry(_ mode: MutationMode, table: String, id: UUID) -> Bool {
        guard let entry = mode.invertedEntry else { return false }
        return entry.snapshot(table: table, id: id) == nil
    }

    // MARK: - Shared row access

    static func row(_ table: String, id: UUID, in db: Database) throws -> Row {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM \(table) WHERE id = ?", arguments: [id.uuidString]
        ) else { throw ProjectStoreError.entityNotFound }
        return row
    }

    static func source(of row: Row) -> FactSource {
        FactSource(rawValue: row["source"] as String? ?? "") ?? .ai
    }

    static func reviewState(of row: Row) -> ReviewState {
        ReviewState(rawValue: row["review_state"] as String? ?? "") ?? .proposed
    }

    /// The PROV values every `.human` / `.ai` insert into these tables is born with (§3.6).
    private static func insertProvenance(
        _ actor: MutationActor,
        timestamp: String
    ) -> StatementArguments {
        let isHuman = actor == .human
        return [
            actor.factSource.rawValue,
            (isHuman ? ReviewState.accepted : ReviewState.proposed).rawValue,
            isHuman ? timestamp : nil,
            actor.jobID?.uuidString,
            actor.factSource.rawValue, timestamp, timestamp,
        ]
    }

    // MARK: - Validation ("Scenes, states, events, relationships")

    /// A state's scenes: `start_scene_id` is required, both scenes belong to the current
    /// script, and `start.ordinal ≤ end.ordinal`.
    static func validateStateScenes(startSceneID: UUID, endSceneID: UUID?, in db: Database) throws {
        guard let start = try SceneOperations.ordinal(ofScene: startSceneID, in: db) else {
            throw ProjectStoreError.sceneNotFound
        }
        guard let endSceneID else { return }
        guard let end = try SceneOperations.ordinal(ofScene: endSceneID, in: db) else {
            throw ProjectStoreError.sceneNotFound
        }
        guard start <= end else {
            throw ProjectStoreError.invalidFact(
                reason: "A state cannot end in a scene before the one it starts in."
            )
        }
    }

    /// `ContinuityEvent.resulting_state_id` must belong to the same entity — and therefore
    /// to an entity at all, which is why an entity-less event may not carry one.
    static func validateResultingState(
        _ resultingStateID: UUID?,
        entityID: UUID?,
        in db: Database
    ) throws {
        guard let resultingStateID else { return }
        guard let entityID else {
            throw ProjectStoreError.invalidFact(
                reason: "An event that results in a state has to say whose state it is."
            )
        }
        guard let owner = try String.fetchOne(
            db, sql: "SELECT entity_id FROM entity_states WHERE id = ?",
            arguments: [resultingStateID.uuidString]
        ) else {
            throw ProjectStoreError.invalidFact(reason: "That state is not in this project.")
        }
        guard try UUID.required(owner) == entityID else {
            throw ProjectStoreError.invalidFact(
                reason: "An event can only result in a state of the same item."
            )
        }
    }

    /// `entity_relationships` is unique per `(from, to, kind)`, and nothing relates to
    /// itself.
    static func validateRelationship(
        from: UUID,
        to: UUID,
        kind: RelationshipKind,
        excluding id: UUID?,
        in db: Database
    ) throws {
        guard from != to else {
            throw ProjectStoreError.invalidFact(reason: "An item cannot relate to itself.")
        }
        for entityID in [from, to] where try EntityOperations.fetch(id: entityID, in: db) == nil {
            throw ProjectStoreError.entityNotFound
        }
        if try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM entity_relationships
                    WHERE from_entity_id = ? AND to_entity_id = ? AND kind = ? AND id <> ?
                )
                """,
            arguments: [from.uuidString, to.uuidString, kind.rawValue, (id ?? UUID()).uuidString]
        ) ?? false {
            throw ProjectStoreError.invalidFact(
                reason: "Those two already have a \(kind.rawValue) relationship."
            )
        }
    }

    static func requireEntity(_ id: UUID, in db: Database) throws {
        guard try EntityOperations.fetch(id: id, in: db) != nil else {
            throw ProjectStoreError.entityNotFound
        }
    }

    // MARK: - States

    /// §6's `addState`, and — when `restoring` carries a payload — `removeState`'s inverse
    /// for a hard-deleted row, which puts it back with its **original id** (§3.8).
    static func addState(
        id: UUID?,
        entityID: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID?,
        restoring: [RowSnapshot],
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        if let restored = try restore(restoring, table: "entity_states", kind: .state, in: db) {
            return restored
        }
        try requireEntity(entityID, in: db)
        try validateStateScenes(startSceneID: startSceneID, endSceneID: endSceneID, in: db)
        ProtectionPolicy.checkReferenceAddition(
            toEntity: SubjectRef(kind: .entity, id: entityID), actor: actor
        )

        let stateID = id ?? UUID()
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO entity_states (
                    id, entity_id, category, description, start_scene_id, end_scene_id,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                stateID.uuidString, entityID.uuidString, category.rawValue, description,
                startSceneID.uuidString, endSceneID?.uuidString,
            ] + insertProvenance(actor, timestamp: timestamp)
        )
        return MutationEffect(
            inverse: .removeState(id: stateID),
            affected: [SubjectRef(kind: .state, id: stateID)]
        )
    }

    static func editState(
        id: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID?,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .state, id: id)
        if let entry = mode.invertedEntry {
            return try invertEdit(entry: entry, ref: ref, table: "entity_states", in: db) { row in
                .editState(
                    id: id,
                    category: StateCategory(rawValue: row["category"]) ?? category,
                    description: row["description"],
                    startSceneID: try UUID.required(row["start_scene_id"]),
                    endSceneID: try (row["end_scene_id"] as String?).map(UUID.required)
                )
            }
        }
        let row = try row("entity_states", id: id, in: db)
        try ProtectionPolicy.checkFactEdit(
            ref: ref, source: source(of: row), reviewState: reviewState(of: row), actor: actor, in: db
        )
        try validateStateScenes(startSceneID: startSceneID, endSceneID: endSceneID, in: db)

        let snapshot = RowSnapshot(table: "entity_states", row: row)
        var arguments: StatementArguments = [
            category.rawValue, description, startSceneID.uuidString, endSceneID?.uuidString,
        ]
        arguments += EntityOperations.provenanceArguments(
            actor: actor, current: reviewState(of: row), timestamp: UTCDate.string(from: Date())
        )
        arguments += [id.uuidString]
        try db.execute(
            sql: """
                UPDATE entity_states
                SET category = ?, description = ?, start_scene_id = ?, end_scene_id = ?,
                    \(EntityOperations.provenanceAssignment)
                WHERE id = ?
                """,
            arguments: arguments
        )
        return MutationEffect(
            inverse: .editState(
                id: id,
                category: StateCategory(rawValue: row["category"]) ?? category,
                description: row["description"],
                startSceneID: try UUID.required(row["start_scene_id"]),
                endSceneID: try (row["end_scene_id"] as String?).map(UUID.required)
            ),
            affected: [ref],
            snapshots: [snapshot]
        )
    }

    static func removeState(
        id: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .state, id: id)
        let row = try row("entity_states", id: id, in: db)
        try ProtectionPolicy.checkFactEdit(
            ref: ref, source: source(of: row), reviewState: reviewState(of: row), actor: actor, in: db
        )
        guard isHardDeletable(source: source(of: row), reviewState: reviewState(of: row))
            || (mode.isReplacingAIProposal && source(of: row) == .ai && reviewState(of: row) == .proposed)
            || createdByInvertedEntry(mode, table: "entity_states", id: id)
        else {
            // §6: the tombstone, not a delete — `unrejectSubject` is therefore the inverse.
            return try ReviewOperations.reject(ref: ref, actor: actor, mode: mode, in: db)
        }
        var collector = SnapshotCollector()
        collector.add(table: "entity_states", row: row)
        // An event that resulted in this state loses the link (`ON DELETE SET NULL`), so
        // its row has to travel in the payload or the undo would not put the link back.
        for dependent in try Row.fetchAll(
            db, sql: "SELECT * FROM continuity_events WHERE resulting_state_id = ? ORDER BY id",
            arguments: [id.uuidString]
        ) {
            collector.add(table: "continuity_events", row: dependent)
        }
        try collector.captureLocks(subject: ref, in: db)
        try dropEvidence(about: ref, into: &collector, in: db)
        // PHASE2_DESIGN §7.4: basis rows citing this fact are swept in the same
        // transaction — they carry no foreign key, so nothing else would take them.
        try EntityRequirementInteractions.sweepBasis(citing: [ref], into: &collector, in: db)
        try RowSnapshotStore.deleteLocks(subject: ref, in: db)
        try RowSnapshotStore.delete(table: "entity_states", id: id, in: db)

        return MutationEffect(
            inverse: .addState(
                id: id,
                entityID: try UUID.required(row["entity_id"]),
                category: StateCategory(rawValue: row["category"]) ?? .other,
                description: row["description"],
                startSceneID: try UUID.required(row["start_scene_id"]),
                endSceneID: try (row["end_scene_id"] as String?).map(UUID.required),
                restoring: collector.snapshots
            ),
            affected: [ref],
            snapshots: collector.snapshots
        )
    }

    // MARK: - Events

    static func addEvent(
        id: UUID?,
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID?,
        restoring: [RowSnapshot],
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        if let restored = try restore(restoring, table: "continuity_events", kind: .event, in: db) {
            return restored
        }
        try SceneOperations.requireScene(sceneID, in: db)
        if let entityID { try requireEntity(entityID, in: db) }
        try validateResultingState(resultingStateID, entityID: entityID, in: db)
        if let entityID {
            ProtectionPolicy.checkReferenceAddition(
                toEntity: SubjectRef(kind: .entity, id: entityID), actor: actor
            )
        }

        let eventID = id ?? UUID()
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO continuity_events (
                    id, scene_id, entity_id, description, resulting_state_id,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                eventID.uuidString, sceneID.uuidString, entityID?.uuidString, description,
                resultingStateID?.uuidString,
            ] + insertProvenance(actor, timestamp: timestamp)
        )
        return MutationEffect(
            inverse: .removeEvent(id: eventID),
            affected: [SubjectRef(kind: .event, id: eventID)]
        )
    }

    static func editEvent(
        id: UUID,
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID?,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .event, id: id)
        if let entry = mode.invertedEntry {
            return try invertEdit(entry: entry, ref: ref, table: "continuity_events", in: db) { row in
                try priorEvent(id: id, row: row)
            }
        }
        let row = try row("continuity_events", id: id, in: db)
        try ProtectionPolicy.checkFactEdit(
            ref: ref, source: source(of: row), reviewState: reviewState(of: row), actor: actor, in: db
        )
        try SceneOperations.requireScene(sceneID, in: db)
        if let entityID { try requireEntity(entityID, in: db) }
        try validateResultingState(resultingStateID, entityID: entityID, in: db)

        let snapshot = RowSnapshot(table: "continuity_events", row: row)
        var arguments: StatementArguments = [
            sceneID.uuidString, entityID?.uuidString, description, resultingStateID?.uuidString,
        ]
        arguments += EntityOperations.provenanceArguments(
            actor: actor, current: reviewState(of: row), timestamp: UTCDate.string(from: Date())
        )
        arguments += [id.uuidString]
        try db.execute(
            sql: """
                UPDATE continuity_events
                SET scene_id = ?, entity_id = ?, description = ?, resulting_state_id = ?,
                    \(EntityOperations.provenanceAssignment)
                WHERE id = ?
                """,
            arguments: arguments
        )
        return MutationEffect(
            inverse: try priorEvent(id: id, row: row),
            affected: [ref],
            snapshots: [snapshot]
        )
    }

    static func removeEvent(
        id: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .event, id: id)
        let row = try row("continuity_events", id: id, in: db)
        try ProtectionPolicy.checkFactEdit(
            ref: ref, source: source(of: row), reviewState: reviewState(of: row), actor: actor, in: db
        )
        guard isHardDeletable(source: source(of: row), reviewState: reviewState(of: row))
            || (mode.isReplacingAIProposal && source(of: row) == .ai && reviewState(of: row) == .proposed)
            || createdByInvertedEntry(mode, table: "continuity_events", id: id)
        else {
            return try ReviewOperations.reject(ref: ref, actor: actor, mode: mode, in: db)
        }
        var collector = SnapshotCollector()
        collector.add(table: "continuity_events", row: row)
        try collector.captureLocks(subject: ref, in: db)
        try dropEvidence(about: ref, into: &collector, in: db)
        // PHASE2_DESIGN §7.4's basis sweep, as for a state.
        try EntityRequirementInteractions.sweepBasis(citing: [ref], into: &collector, in: db)
        try RowSnapshotStore.deleteLocks(subject: ref, in: db)
        try RowSnapshotStore.delete(table: "continuity_events", id: id, in: db)

        return MutationEffect(
            inverse: .addEvent(
                id: id,
                sceneID: try UUID.required(row["scene_id"]),
                entityID: try (row["entity_id"] as String?).map(UUID.required),
                description: row["description"],
                resultingStateID: try (row["resulting_state_id"] as String?).map(UUID.required),
                restoring: collector.snapshots
            ),
            affected: [ref],
            snapshots: collector.snapshots
        )
    }

    // MARK: - Relationships

    static func addRelationship(
        id: UUID?,
        fromEntityID: UUID,
        toEntityID: UUID,
        kind: RelationshipKind,
        description: String,
        restoring: [RowSnapshot],
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        if let restored = try restore(
            restoring, table: "entity_relationships", kind: .relationship, in: db
        ) {
            return restored
        }
        try validateRelationship(
            from: fromEntityID, to: toEntityID, kind: kind, excluding: id, in: db
        )
        ProtectionPolicy.checkReferenceAddition(
            toEntity: SubjectRef(kind: .entity, id: fromEntityID), actor: actor
        )

        let relationshipID = id ?? UUID()
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO entity_relationships (
                    id, from_entity_id, to_entity_id, kind, description,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                relationshipID.uuidString, fromEntityID.uuidString, toEntityID.uuidString,
                kind.rawValue, description,
            ] + insertProvenance(actor, timestamp: timestamp)
        )
        return MutationEffect(
            inverse: .removeRelationship(id: relationshipID),
            affected: [SubjectRef(kind: .relationship, id: relationshipID)]
        )
    }

    static func removeRelationship(
        id: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .relationship, id: id)
        let row = try row("entity_relationships", id: id, in: db)
        try ProtectionPolicy.checkFactEdit(
            ref: ref, source: source(of: row), reviewState: reviewState(of: row), actor: actor, in: db
        )
        guard isHardDeletable(source: source(of: row), reviewState: reviewState(of: row))
            || (mode.isReplacingAIProposal && source(of: row) == .ai && reviewState(of: row) == .proposed)
            || createdByInvertedEntry(mode, table: "entity_relationships", id: id)
        else {
            return try ReviewOperations.reject(ref: ref, actor: actor, mode: mode, in: db)
        }
        var collector = SnapshotCollector()
        collector.add(table: "entity_relationships", row: row)
        try collector.captureLocks(subject: ref, in: db)
        try dropEvidence(about: ref, into: &collector, in: db)
        try RowSnapshotStore.deleteLocks(subject: ref, in: db)
        try RowSnapshotStore.delete(table: "entity_relationships", id: id, in: db)

        return MutationEffect(
            inverse: .addRelationship(
                id: id,
                fromEntityID: try UUID.required(row["from_entity_id"]),
                toEntityID: try UUID.required(row["to_entity_id"]),
                kind: RelationshipKind(rawValue: row["kind"]) ?? .other,
                description: row["description"],
                restoring: collector.snapshots
            ),
            affected: [ref],
            snapshots: collector.snapshots
        )
    }

    // MARK: - Preconditions (§3.8)

    static func precheckAdd(
        id: UUID?,
        table: String,
        restoring: [RowSnapshot],
        in db: Database
    ) throws {
        guard restoring.isEmpty else {
            try InverseApplication.precheckSnapshots(restoring, in: db)
            return
        }
        guard let id, try !RowSnapshotStore.exists(table: table, id: id, in: db) else { return }
        throw ProjectStoreError.inverseNoLongerApplicable(
            reason: "Something that change removed is already back."
        )
    }

    static func precheckRow(table: String, id: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: table, id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change touched is no longer in this project."
            )
        }
    }

    // MARK: - Helpers

    /// The restore half of an `add`: the row and everything the removal took with it, back
    /// by original id.
    private static func restore(
        _ snapshots: [RowSnapshot],
        table: String,
        kind: SubjectKind,
        in db: Database
    ) throws -> MutationEffect? {
        guard !snapshots.isEmpty else { return nil }
        guard let id = snapshots.first(where: { $0.table == table }).flatMap(rowID) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has anything to restore."
            )
        }
        try RowGraph.restore(snapshots, in: db)
        let inverse: EditOperation = switch kind {
        case .state: .removeState(id: id)
        case .event: .removeEvent(id: id)
        default: .removeRelationship(id: id)
        }
        return MutationEffect(
            inverse: inverse,
            affected: RowGraph.subjects(of: snapshots).union([SubjectRef(kind: kind, id: id)])
        )
    }

    /// The `.inverting` half of an `edit`: the row back as the entry found it, plus the
    /// operation that would apply the edit again.
    private static func invertEdit(
        entry: JournalEntry,
        ref: SubjectRef,
        table: String,
        in db: Database,
        redo: (Row) throws -> EditOperation
    ) throws -> MutationEffect {
        let current = try row(table, id: ref.id, in: db)
        let snapshot = RowSnapshot(table: table, row: current)
        guard let restored = entry.snapshot(table: table, id: ref.id) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has anything to restore."
            )
        }
        try RowSnapshotStore.restore(restored, in: db)
        return MutationEffect(inverse: try redo(current), affected: [ref], snapshots: [snapshot])
    }

    /// Evidence about a row that is going away with no survivor to inherit it: snapshotted
    /// and removed, because `evidence.subject_id` carries no foreign key (§4.3).
    private static func dropEvidence(
        about ref: SubjectRef,
        into collector: inout SnapshotCollector,
        in db: Database
    ) throws {
        var ids: [UUID] = []
        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM evidence WHERE subject_kind = ? AND subject_id = ? ORDER BY id",
            arguments: [ref.kind.rawValue, ref.id.uuidString]
        ) {
            collector.add(table: "evidence", row: row)
            ids.append(try UUID.required(row["id"]))
        }
        for id in ids { try RowSnapshotStore.delete(table: "evidence", id: id, in: db) }
    }

    private static func priorEvent(id: UUID, row: Row) throws -> EditOperation {
        .editEvent(
            id: id,
            sceneID: try UUID.required(row["scene_id"]),
            entityID: try (row["entity_id"] as String?).map(UUID.required),
            description: row["description"],
            resultingStateID: try (row["resulting_state_id"] as String?).map(UUID.required)
        )
    }

    private static func rowID(_ snapshot: RowSnapshot) -> UUID? {
        guard case let .string(raw)? = snapshot.columns["id"] else { return nil }
        return UUID(uuidString: raw)
    }
}
