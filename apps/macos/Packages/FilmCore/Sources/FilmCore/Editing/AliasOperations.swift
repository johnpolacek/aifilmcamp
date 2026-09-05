import Foundation
import GRDB

/// `addAlias` and `removeAlias` (PHASE1_DESIGN §3.5, §6).
///
/// A normalized alias is unique **per project and kind**, so an alias insert is always
/// conditional: already on this entity → skipped; on another entity of the same kind →
/// `.aliasConflict(existingEntityID:)`, which is where the UI offers Merge.
enum AliasOperations {
    /// The columns an alias operation needs, provenance included: §3.5 makes AI aliases
    /// append-only and §3.6 makes a parser cue or heading alias parser-owned, so every
    /// removal has to know where the row came from.
    struct AliasRow {
        let id: UUID
        let entityID: UUID
        let projectID: UUID
        let kind: EntityKind
        let alias: String
        let normalized: String
        let aliasKind: AliasKind
        let source: FactSource
        let reviewState: ReviewState

        var ref: SubjectRef { SubjectRef(kind: .alias, id: id) }
    }

    static func fetch(id: UUID, in db: Database) throws -> AliasRow? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM entity_aliases WHERE id = ?", arguments: [id.uuidString]
        ) else { return nil }
        guard let kind = EntityKind(rawValue: row["kind"]),
              let aliasKind = AliasKind(rawValue: row["alias_kind"]),
              let source = FactSource(rawValue: row["source"]),
              let reviewState = ReviewState(rawValue: row["review_state"])
        else { throw ProjectStoreError.invalidBundle }
        return AliasRow(
            id: try UUID.required(row["id"]),
            entityID: try UUID.required(row["entity_id"]),
            projectID: try UUID.required(row["project_id"]),
            kind: kind,
            alias: row["alias"],
            normalized: row["normalized"],
            aliasKind: aliasKind,
            source: source,
            reviewState: reviewState
        )
    }

    /// The entity of that kind already holding this normalized surface form, if any.
    static func owner(
        projectID: UUID,
        kind: EntityKind,
        normalized: String,
        in db: Database
    ) throws -> (aliasID: UUID, entityID: UUID)? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT id, entity_id FROM entity_aliases
                WHERE project_id = ? AND kind = ? AND normalized = ?
                """,
            arguments: [projectID.uuidString, kind.rawValue, normalized]
        ) else { return nil }
        return (try UUID.required(row["id"]), try UUID.required(row["entity_id"]))
    }

    /// The alias ids of one entity, in a stable order.
    static func aliasIDs(of entityID: UUID, in db: Database) throws -> [UUID] {
        try String
            .fetchAll(
                db,
                sql: "SELECT id FROM entity_aliases WHERE entity_id = ? ORDER BY id",
                arguments: [entityID.uuidString]
            )
            .map { try UUID.required($0) }
    }

    // MARK: - addAlias

    /// §6's `addAlias`, and — when `restoring` carries a payload — `removeAlias`'s inverse,
    /// which puts the alias row and everything that pointed at it back by original id.
    static func add(
        entityID: UUID,
        alias: String,
        aliasID: UUID?,
        restoring: [RowSnapshot],
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        if !restoring.isEmpty {
            try RowGraph.restore(restoring, in: db)
            guard let aliasID = restoredAliasID(in: restoring) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "That change no longer has an alias to restore."
                )
            }
            return MutationEffect(
                inverse: .removeAlias(aliasID: aliasID),
                affected: RowGraph.subjects(of: restoring)
            )
        }

        guard let entity = try EntityOperations.fetch(id: entityID, in: db) else {
            throw ProjectStoreError.entityNotFound
        }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.invalidName(reason: "An alias cannot be empty.")
        }
        // §3.5/§3.7: an alias addition is refused only by a whole-record lock on the
        // entity — for `.ai` because aliases are append-only rather than forbidden, and
        // for a person because a pinned record is read-only until they unlock it.
        try ProtectionPolicy.checkAliasAddition(toEntity: entity.ref, actor: actor, in: db)
        let normalized = EntityNormalization.normalize(trimmed)
        if let existing = try owner(
            projectID: entity.projectID, kind: entity.kind, normalized: normalized, in: db
        ) {
            guard existing.entityID == entityID else {
                throw ProjectStoreError.aliasConflict(existingEntityID: existing.entityID)
            }
            // §3.5's conditional insert: the same normalized form on the same entity is
            // already the row this would add, so the operation changes nothing.
            return MutationEffect(inverse: .batch([]))
        }

        let id = aliasID ?? UUID()
        try insert(
            id: id,
            entityID: entityID,
            projectID: entity.projectID,
            kind: entity.kind,
            alias: trimmed,
            normalized: normalized,
            aliasKind: actor == .human ? .human : .mention,
            actor: actor,
            timestamp: UTCDate.string(from: Date()),
            in: db
        )
        return MutationEffect(
            inverse: .removeAlias(aliasID: id),
            affected: [SubjectRef(kind: .alias, id: id)]
        )
    }

    /// The one alias insert (§3.6): `created_source = source`, a `.human` insert born
    /// `accepted` with `reviewed_at` set, an `.ai` insert `proposed` and never reviewed.
    static func insert(
        id: UUID,
        entityID: UUID,
        projectID: UUID,
        kind: EntityKind,
        alias: String,
        normalized: String,
        aliasKind: AliasKind,
        actor: MutationActor,
        timestamp: String,
        in db: Database
    ) throws {
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
                id.uuidString, entityID.uuidString, projectID.uuidString, kind.rawValue,
                alias, normalized, aliasKind.rawValue,
                actor.factSource.rawValue,
                (isHuman ? ReviewState.accepted : ReviewState.proposed).rawValue,
                isHuman ? timestamp : nil,
                actor.jobID?.uuidString,
                actor.factSource.rawValue, timestamp, timestamp,
            ]
        )
    }

    // MARK: - removeAlias

    /// §6's `removeAlias`. The alias row's dependents — appearances and evidence that
    /// recorded it in `matched_alias_id`, evidence whose subject *is* the alias, and any
    /// lock over it — are snapshotted so the inverse restores the whole neighbourhood.
    static func remove(
        aliasID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        guard let alias = try fetch(id: aliasID, in: db) else {
            throw ProjectStoreError.entityNotFound
        }
        // §3.5: for `.ai` aliases are append-only, whatever the entity's review state; an
        // alias lock pins the surface form to its entity for both actors (§3.7).
        try ProtectionPolicy.checkAliasRemoval(alias, actor: actor, in: db)
        var collector = SnapshotCollector()
        var affected: Set<SubjectRef> = [alias.ref]
        try collector.capture(table: "entity_aliases", id: aliasID, in: db)

        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM scene_entities WHERE matched_alias_id = ? ORDER BY id",
            arguments: [aliasID.uuidString]
        ) {
            collector.add(table: "scene_entities", row: row)
            affected.insert(SubjectRef(kind: .appearance, id: try UUID.required(row["id"])))
        }
        // `evidence.subject_id` is polymorphic and carries no foreign key, so evidence
        // *about* the alias has to be taken by hand or it is left orphaned.
        var orphaned: [UUID] = []
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM evidence
                WHERE matched_alias_id = ? OR (subject_kind = 'alias' AND subject_id = ?)
                ORDER BY id
                """,
            arguments: [aliasID.uuidString, aliasID.uuidString]
        ) {
            collector.add(table: "evidence", row: row)
            if (row["subject_kind"] as String) == SubjectKind.alias.rawValue {
                orphaned.append(try UUID.required(row["id"]))
            }
        }
        try collector.captureLocks(subject: alias.ref, in: db)

        for id in orphaned { try RowSnapshotStore.delete(table: "evidence", id: id, in: db) }
        try RowSnapshotStore.deleteLocks(subject: alias.ref, in: db)
        try RowSnapshotStore.delete(table: "entity_aliases", id: aliasID, in: db)

        return MutationEffect(
            inverse: .addAlias(
                entityID: alias.entityID,
                alias: alias.alias,
                aliasID: aliasID,
                restoring: collector.snapshots
            ),
            affected: affected,
            snapshots: collector.snapshots
        )
    }

    // MARK: - Preconditions (§3.8)

    static func precheckAdd(
        entityID: UUID,
        alias: String,
        aliasID: UUID?,
        restoring: [RowSnapshot],
        in db: Database
    ) throws {
        guard restoring.isEmpty else {
            try InverseApplication.precheckSnapshots(restoring, in: db)
            return
        }
        guard let entity = try EntityOperations.fetch(id: entityID, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That item is no longer in this project."
            )
        }
        let normalized = EntityNormalization.normalize(
            alias.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let existing = try owner(
            projectID: entity.projectID, kind: entity.kind, normalized: normalized, in: db
        ), existing.entityID != entityID {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "“\(alias)” now belongs to another item."
            )
        }
    }

    static func precheckRemove(aliasID: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "entity_aliases", id: aliasID, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change added is already gone."
            )
        }
    }

    private static func restoredAliasID(in snapshots: [RowSnapshot]) -> UUID? {
        for snapshot in snapshots where snapshot.table == "entity_aliases" {
            if case let .string(raw)? = snapshot.columns["id"] { return UUID(uuidString: raw) }
        }
        return nil
    }
}
