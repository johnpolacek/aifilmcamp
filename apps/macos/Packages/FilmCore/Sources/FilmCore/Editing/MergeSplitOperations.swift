import Foundation
import GRDB

/// Which of two colliding rows survives a merge (PHASE1_DESIGN §3.5).
///
/// Most protected wins — `human` (3) > `ai` + `accepted` (2) > `parser` (1) >
/// `ai` + `proposed` (0) — ties by earliest `created_at`, then by `id`, so the choice is
/// total and reproducible rather than "whichever row SQLite handed back first".
enum ProtectionRank {
    static func rank(source: FactSource, reviewState: ReviewState) -> Int {
        switch source {
        case .human: 3
        case .ai: reviewState == .accepted ? 2 : 0
        case .parser: 1
        }
    }

    static func rank(of row: Row) -> Int {
        guard let source = FactSource(rawValue: row["source"] as String? ?? ""),
              let state = ReviewState(rawValue: row["review_state"] as String? ?? "")
        else { return 0 }
        return rank(source: source, reviewState: state)
    }

    /// The colliding rows ordered survivor-first.
    static func survivorFirst(_ rows: [Row]) -> [Row] {
        rows.sorted { lhs, rhs in
            let lhsRank = rank(of: lhs), rhsRank = rank(of: rhs)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            let lhsCreated = lhs["created_at"] as String? ?? ""
            let rhsCreated = rhs["created_at"] as String? ?? ""
            if lhsCreated != rhsCreated { return lhsCreated < rhsCreated }
            return (lhs["id"] as String? ?? "") < (rhs["id"] as String? ?? "")
        }
    }
}

/// `mergeEntities`, `splitEntity`, and their payload-driven inverses (§3.5, §3.8).
enum MergeSplitOperations {

    // MARK: - mergeEntities (§3.5)

    /// Merges one source into the target. More than one source is a `performGroup` of
    /// these, one child per source.
    static func merge(
        sourceID: UUID,
        into targetID: UUID,
        nameAliasID: UUID?,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        guard sourceID != targetID else {
            throw ProjectStoreError.mergeRefused(reason: "An item cannot be merged into itself.")
        }
        guard let source = try EntityOperations.fetch(id: sourceID, in: db),
              let target = try EntityOperations.fetch(id: targetID, in: db)
        else { throw ProjectStoreError.entityNotFound }
        guard source.kind == target.kind else {
            throw ProjectStoreError.mergeRefused(reason: "Only items of the same kind can be merged.")
        }

        // §3.7: any lock on the source or one of its aliases refuses the merge for both
        // actors, and so does a **whole-record** lock on the target, because the merge
        // adds an alias to it. A field lock on the target does not. §3.5's AI merge
        // exception lives in the same policy: parser↔parser and ai→parser are allowed,
        // while a **protected** source — one a human edited, or an AI proposal a human
        // accepted — is not.
        let sourceAliasIDs = try AliasOperations.aliasIDs(of: sourceID, in: db)
        try ProtectionPolicy.checkMergeSource(
            source, aliasIDs: sourceAliasIDs, actor: actor, in: db
        )
        try ProtectionPolicy.checkMergeTarget(target, actor: actor, in: db)

        // PHASE2_DESIGN §7.4: what the requirement half will do, decided before the first
        // write — its two refusals (a colliding pair where **both** members have media, and
        // a retarget that would close a dependency loop) are thrown from here.
        let requirementPlan = try EntityRequirementInteractions.planRequirementMerge(
            source: sourceID, target: targetID, in: db
        )

        let timestamp = UTCDate.string(from: Date())
        var collector = SnapshotCollector()
        var affected: Set<SubjectRef> = [source.ref, target.ref]
        var moved: [SubjectRef] = []
        var created: [SubjectRef] = []
        var skippedAliases: [String] = []
        try collector.capture(table: "entities", id: sourceID, in: db)

        /// Evidence about a row that is about to go away, moved onto the row that survived.
        func retargetEvidence(from loser: UUID, to survivor: UUID, kind: SubjectKind) throws {
            for row in try Row.fetchAll(
                db,
                sql: "SELECT * FROM evidence WHERE subject_kind = ? AND subject_id = ? ORDER BY id",
                arguments: [kind.rawValue, loser.uuidString]
            ) {
                collector.add(table: "evidence", row: row)
            }
            try db.execute(
                sql: """
                    UPDATE evidence SET subject_id = ?, owner_entity_id = ?
                    WHERE subject_kind = ? AND subject_id = ?
                    """,
                arguments: [
                    survivor.uuidString, targetID.uuidString, kind.rawValue, loser.uuidString,
                ]
            )
        }

        /// Evidence about a row that goes away with no survivor to inherit it.
        func dropEvidence(about ref: SubjectRef) throws {
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

        /// The losing half of a collision: snapshotted in full **with its lock rows**, then
        /// removed.
        func removeLoser(table: String, ref: SubjectRef) throws {
            try collector.captureLocks(subject: ref, in: db)
            try RowSnapshotStore.deleteLocks(subject: ref, in: db)
            try RowSnapshotStore.delete(table: table, id: ref.id, in: db)
        }

        // 1. Aliases move first: `entity_aliases(project_id, kind, normalized)` does not
        //    contain `entity_id`, so a move can never collide — and doing them first is
        //    what makes the source-name insert below find an already-moved surface form.
        for row in try Row.fetchAll(
            db, sql: "SELECT * FROM entity_aliases WHERE entity_id = ? ORDER BY id",
            arguments: [sourceID.uuidString]
        ) {
            let id = try UUID.required(row["id"])
            collector.add(table: "entity_aliases", row: row)
            let ref = SubjectRef(kind: .alias, id: id)
            affected.insert(ref)
            moved.append(ref)
            try db.execute(
                sql: "UPDATE entity_aliases SET entity_id = ?, kind = ?, updated_at = ? WHERE id = ?",
                arguments: [targetID.uuidString, target.kind.rawValue, timestamp, id.uuidString]
            )
        }

        // 2. Appearances: `scene_entities(scene_id, entity_id, role)` is the first of the
        //    two indexes that can collide.
        for row in try Row.fetchAll(
            db, sql: "SELECT * FROM scene_entities WHERE entity_id = ? ORDER BY id",
            arguments: [sourceID.uuidString]
        ) {
            let id = try UUID.required(row["id"])
            collector.add(table: "scene_entities", row: row)
            affected.insert(SubjectRef(kind: .appearance, id: id))
            let sceneID: String = row["scene_id"]
            let role: String = row["role"]
            guard let rival = try Row.fetchOne(
                db,
                sql: "SELECT * FROM scene_entities WHERE scene_id = ? AND entity_id = ? AND role = ?",
                arguments: [sceneID, targetID.uuidString, role]
            ) else {
                try db.execute(
                    sql: "UPDATE scene_entities SET entity_id = ?, updated_at = ? WHERE id = ?",
                    arguments: [targetID.uuidString, timestamp, id.uuidString]
                )
                moved.append(SubjectRef(kind: .appearance, id: id))
                continue
            }
            let rivalID = try UUID.required(rival["id"])
            collector.add(table: "scene_entities", row: rival)
            affected.insert(SubjectRef(kind: .appearance, id: rivalID))
            let ordered = ProtectionRank.survivorFirst([row, rival])
            let survivorID = try UUID.required(ordered[0]["id"])
            let loserID = try UUID.required(ordered[1]["id"])
            try retargetEvidence(from: loserID, to: survivorID, kind: .appearance)
            // PHASE2_DESIGN §7.4: a basis row citing the losing appearance is **re-pointed**
            // at the survivor rather than swept — the citation is still true — and dropped
            // only where the requirement already cites the survivor.
            affected.formUnion(
                try EntityRequirementInteractions.retargetBasis(
                    from: SubjectRef(kind: .appearance, id: loserID),
                    to: survivorID,
                    into: &collector,
                    in: db
                )
            )
            try removeLoser(table: "scene_entities", ref: SubjectRef(kind: .appearance, id: loserID))
            if survivorID == id {
                // The source's row won, so it takes the place the rival held.
                try db.execute(
                    sql: "UPDATE scene_entities SET entity_id = ?, updated_at = ? WHERE id = ?",
                    arguments: [targetID.uuidString, timestamp, id.uuidString]
                )
                moved.append(SubjectRef(kind: .appearance, id: id))
            }
        }

        // 3. Relationships, in both directions;
        //    `entity_relationships(from, to, kind)` is the second colliding index, and a
        //    relationship that becomes self-referential is dropped.
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM entity_relationships
                WHERE from_entity_id = ? OR to_entity_id = ? ORDER BY id
                """,
            arguments: [sourceID.uuidString, sourceID.uuidString]
        ) {
            let id = try UUID.required(row["id"])
            // A row already moved by an earlier iteration is no longer this row.
            guard let current = try Row.fetchOne(
                db, sql: "SELECT * FROM entity_relationships WHERE id = ?", arguments: [id.uuidString]
            ) else { continue }
            collector.add(table: "entity_relationships", row: current)
            let ref = SubjectRef(kind: .relationship, id: id)
            affected.insert(ref)
            let kind: String = current["kind"]
            let from = (current["from_entity_id"] as String) == sourceID.uuidString
                ? targetID.uuidString : (current["from_entity_id"] as String)
            let to = (current["to_entity_id"] as String) == sourceID.uuidString
                ? targetID.uuidString : (current["to_entity_id"] as String)

            if from == to {
                try dropEvidence(about: ref)
                try removeLoser(table: "entity_relationships", ref: ref)
                continue
            }
            if let rival = try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM entity_relationships
                    WHERE from_entity_id = ? AND to_entity_id = ? AND kind = ? AND id <> ?
                    """,
                arguments: [from, to, kind, id.uuidString]
            ) {
                let rivalID = try UUID.required(rival["id"])
                collector.add(table: "entity_relationships", row: rival)
                affected.insert(SubjectRef(kind: .relationship, id: rivalID))
                let ordered = ProtectionRank.survivorFirst([current, rival])
                let survivorID = try UUID.required(ordered[0]["id"])
                let loserID = try UUID.required(ordered[1]["id"])
                try retargetEvidence(from: loserID, to: survivorID, kind: .relationship)
                try removeLoser(
                    table: "entity_relationships", ref: SubjectRef(kind: .relationship, id: loserID)
                )
                guard survivorID == id else { continue }
            }
            try db.execute(
                sql: """
                    UPDATE entity_relationships
                    SET from_entity_id = ?, to_entity_id = ?, updated_at = ? WHERE id = ?
                    """,
                arguments: [from, to, timestamp, id.uuidString]
            )
            moved.append(ref)
        }

        // 4. States and continuity events carry no uniqueness of their own.
        for (table, kind) in [("entity_states", SubjectKind.state), ("continuity_events", .event)] {
            for row in try Row.fetchAll(
                db, sql: "SELECT * FROM \(table) WHERE entity_id = ? ORDER BY id",
                arguments: [sourceID.uuidString]
            ) {
                let id = try UUID.required(row["id"])
                collector.add(table: table, row: row)
                let ref = SubjectRef(kind: kind, id: id)
                affected.insert(ref)
                moved.append(ref)
                try db.execute(
                    sql: "UPDATE \(table) SET entity_id = ?, updated_at = ? WHERE id = ?",
                    arguments: [targetID.uuidString, timestamp, id.uuidString]
                )
            }
        }

        // 5. Evidence: ownership, and the rows whose subject *is* the source entity.
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM evidence
                WHERE owner_entity_id = ? OR (subject_kind = 'entity' AND subject_id = ?)
                ORDER BY id
                """,
            arguments: [sourceID.uuidString, sourceID.uuidString]
        ) {
            collector.add(table: "evidence", row: row)
        }
        try db.execute(
            sql: "UPDATE evidence SET owner_entity_id = ? WHERE owner_entity_id = ?",
            arguments: [targetID.uuidString, sourceID.uuidString]
        )
        try db.execute(
            sql: """
                UPDATE evidence SET subject_id = ?
                WHERE subject_kind = 'entity' AND subject_id = ?
                """,
            arguments: [targetID.uuidString, sourceID.uuidString]
        )

        // 6. Child locations. A target that is itself a child of the source would become
        //    its own parent, so it loses the link instead (§3.5).
        for row in try Row.fetchAll(
            db, sql: "SELECT * FROM entities WHERE parent_id = ? ORDER BY id",
            arguments: [sourceID.uuidString]
        ) {
            let id = try UUID.required(row["id"])
            collector.add(table: "entities", row: row)
            let ref = SubjectRef(kind: .entity, id: id)
            affected.insert(ref)
            moved.append(ref)
            try db.execute(
                sql: "UPDATE entities SET parent_id = ?, updated_at = ? WHERE id = ?",
                arguments: [
                    id == targetID ? nil : targetID.uuidString, timestamp, id.uuidString,
                ]
            )
        }

        // 6b. PHASE2_DESIGN §7.4: B's requirements move to A. Collisions resolve by the
        //     plan computed above — liveness first, then protection — with the loser's
        //     asset re-pointed to the survivor when only it has one, and B's
        //     `manifest_inclusion` discarded with B (A's stands, and the column lives on
        //     the entity row this merge deletes).
        try EntityRequirementInteractions.applyRequirementMerge(
            requirementPlan,
            target: targetID,
            timestamp: timestamp,
            into: &collector,
            affected: &affected,
            moved: &moved,
            in: db
        )

        // 7. The source's name survives as an alias on the target — unless the target
        //    already holds that normalized form, or an unrelated third entity does, in
        //    which case the insert is skipped and **reported** rather than thrown (§3.5).
        if let existing = try AliasOperations.owner(
            projectID: source.projectID, kind: target.kind, normalized: source.nameNormalized, in: db
        ) {
            if existing.entityID != targetID { skippedAliases.append(source.name) }
        } else {
            // Pinned by the operation, so a redo of this merge brings the alias back with
            // the id it first had (§3.8).
            let aliasID = nameAliasID ?? UUID()
            try AliasOperations.insert(
                id: aliasID,
                entityID: targetID,
                projectID: source.projectID,
                kind: target.kind,
                alias: source.name,
                normalized: source.nameNormalized,
                aliasKind: actor == .human ? .human : .mention,
                actor: actor,
                timestamp: timestamp,
                in: db
            )
            let ref = SubjectRef(kind: .alias, id: aliasID)
            created.append(ref)
            affected.insert(ref)
        }

        // 8. The source row itself. Everything it owned has moved, so nothing cascades.
        try RowSnapshotStore.deleteLocks(subject: source.ref, in: db)
        try RowSnapshotStore.delete(table: "entities", id: sourceID, in: db)

        // 9. A redo puts back the lock rows the matching `unmerge` took away with the rows
        //    it deleted (§3.7).
        affected.formUnion(try restoreRemovedLocks(mode, in: db))

        return MutationEffect(
            inverse: .unmerge(
                target: targetID, created: created, moved: moved, snapshots: collector.snapshots
            ),
            affected: affected,
            snapshots: collector.snapshots,
            skippedAliases: skippedAliases
        )
    }

    /// Puts back every lock row the inverse being undone removed along with the rows it
    /// deleted, skipping any whose subject is not there to be locked.
    ///
    /// `unmerge` and `unsplit` snapshot those lock rows into their own journal payload
    /// (§3.7), and the redo re-runs the original operation — so this is the one place that
    /// payload can be replayed.
    static func restoreRemovedLocks(_ mode: MutationMode, in db: Database) throws -> Set<SubjectRef> {
        guard let entry = mode.invertedEntry else { return [] }
        var restorable: [RowSnapshot] = []
        var subjects: Set<SubjectRef> = []
        for snapshot in entry.snapshots where snapshot.table == "locks" {
            guard case let .string(rawKind)? = snapshot.columns["subject_kind"],
                  let kind = SubjectKind(rawValue: rawKind),
                  case let .string(rawID)? = snapshot.columns["subject_id"],
                  let id = UUID(uuidString: rawID),
                  let table = RowSnapshotStore.table(for: kind),
                  try RowSnapshotStore.exists(table: table, id: id, in: db)
            else { continue }
            restorable.append(snapshot)
            subjects.insert(SubjectRef(kind: kind, id: id))
        }
        try RowGraph.restore(restorable, in: db)
        return subjects
    }

    /// `mergeEntities`' inverse: the snapshots back by original id, the moved rows back
    /// with them, and **every row the merge created** — the source-name alias included —
    /// taken away again, so merge → undo is byte-identical (§3.5).
    static func unmerge(
        target targetID: UUID,
        created: [SubjectRef],
        moved: [SubjectRef],
        snapshots: [RowSnapshot],
        in db: Database
    ) throws -> MutationEffect {
        // The source is the one `entities` snapshot that is missing: a merge deletes
        // exactly one entity row and always snapshots it, while every other entity row it
        // touches — the target and the child locations — is still there. The target itself
        // comes from the payload, because a merge that created and moved nothing would
        // leave no row to read it off.
        let sourceID = try absentEntityID(in: snapshots, in: db)

        let removedLocks = try RowGraph.delete(created, in: db)
        try RowGraph.restore(snapshots, in: db)

        var affected = RowGraph.subjects(of: snapshots)
        affected.formUnion(created)
        affected.formUnion(moved)
        // The target is touched without being snapshotted — the merge added an alias to it
        // and this takes it away again — so it has to be named explicitly, exactly as the
        // merge names it (§3.8: `affected` lists every row the entry touched).
        affected.insert(SubjectRef(kind: .entity, id: targetID))
        let inverse: EditOperation? = if let sourceID {
            .mergeEntities(
                sourceIDs: [sourceID],
                into: targetID,
                nameAliasIDs: created.filter { $0.kind == .alias }.map(\.id)
            )
        } else {
            nil
        }
        return MutationEffect(inverse: inverse, affected: affected, snapshots: removedLocks)
    }

    /// The entity a snapshot list holds that is **not** in the database — the row the
    /// merge deleted.
    private static func absentEntityID(in snapshots: [RowSnapshot], in db: Database) throws -> UUID? {
        for snapshot in snapshots where snapshot.table == "entities" {
            guard case let .string(raw)? = snapshot.columns["id"], let id = UUID(uuidString: raw)
            else { continue }
            if try !RowSnapshotStore.isPresent(snapshot, in: db) { return id }
        }
        return nil
    }

    // MARK: - splitEntity (§3.5)

    /// §3.5's split. Human-only: design §8.5 never splits, so an `.ai` attempt is a
    /// protected-fact refusal rather than a merge in reverse.
    static func split(
        entityID: UUID,
        aliasIDs: [UUID],
        newName: String,
        newEntityID: UUID,
        newAliasID: UUID?,
        movedAppearanceIDs: [UUID],
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        guard actor == .human else {
            throw ProjectStoreError.protectedFact(subject: SubjectRef(kind: .entity, id: entityID))
        }
        guard let source = try EntityOperations.fetch(id: entityID, in: db) else {
            throw ProjectStoreError.entityNotFound
        }
        guard !aliasIDs.isEmpty else {
            throw ProjectStoreError.splitRefused(reason: "Choose at least one alias to split out.")
        }
        let ownAliasIDs = try AliasOperations.aliasIDs(of: entityID, in: db)
        let moving = Set(aliasIDs)
        guard moving.isSubset(of: Set(ownAliasIDs)) else {
            throw ProjectStoreError.splitRefused(
                reason: "Those aliases do not all belong to this item."
            )
        }
        guard ownAliasIDs.count > moving.count else {
            throw ProjectStoreError.splitRefused(
                reason: "At least one alias has to stay with the original."
            )
        }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.invalidName(reason: "A name cannot be empty.")
        }
        let normalized = EntityNormalization.normalize(trimmed)
        if let conflicting = try EntityOperations.conflictingEntityID(
            projectID: source.projectID, kind: source.kind, normalized: normalized,
            excluding: newEntityID, in: db
        ) {
            throw ProjectStoreError.nameConflict(existingEntityID: conflicting)
        }
        // §3.7: **any** lock on the source, or on any alias being split out, refuses the
        // split — for both actors.
        try LockPolicy.checkFree(subject: source.ref, in: db)
        for aliasID in aliasIDs {
            try LockPolicy.checkFree(subject: SubjectRef(kind: .alias, id: aliasID), in: db)
        }

        let timestamp = UTCDate.string(from: Date())
        var collector = SnapshotCollector()
        var affected: Set<SubjectRef> = [source.ref, SubjectRef(kind: .entity, id: newEntityID)]
        var moved: [SubjectRef] = []
        var created: [SubjectRef] = [SubjectRef(kind: .entity, id: newEntityID)]
        try collector.capture(table: "entities", id: entityID, in: db)

        // A `.human` insert is born accepted and reviewed (§3.6). `parent_id` is
        // deliberately NULL: §3.5 says nothing about inheriting the source's parent, and a
        // split-out location is a new place until the operator says otherwise.
        try db.execute(
            sql: """
                INSERT INTO entities (
                    id, project_id, kind, name, name_normalized, description, parent_id,
                    is_relevant, source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, '', NULL, 1, 'human', NULL, 'accepted', ?, NULL,
                          'human', ?, ?)
                """,
            arguments: [
                newEntityID.uuidString, source.projectID.uuidString, source.kind.rawValue,
                trimmed, normalized, timestamp, timestamp, timestamp,
            ]
        )

        let aliasList = aliasIDs.sorted { $0.uuidString < $1.uuidString }
        for aliasID in aliasList {
            try collector.capture(table: "entity_aliases", id: aliasID, in: db)
            let ref = SubjectRef(kind: .alias, id: aliasID)
            affected.insert(ref)
            moved.append(ref)
            try db.execute(
                sql: "UPDATE entity_aliases SET entity_id = ?, updated_at = ? WHERE id = ?",
                arguments: [newEntityID.uuidString, timestamp, aliasID.uuidString]
            )
        }

        // Appearances move by the alias that produced them (`matched_alias_id`) plus the
        // rows the split sheet listed — **never** by comparing an evidence quote against
        // an alias, which would effectively never match (§3.5). `movedAppearanceIDs` is
        // deliberately scoped by `entity_id = ?` and silently ignores anything outside the
        // source: the sheet only ever offers this entity's rows, and a split may not reach
        // into another entity's.
        var appearanceIDs: [UUID] = []
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM scene_entities
                WHERE entity_id = ?
                  AND (matched_alias_id IN \(EntityOperations.inClause(aliasList))
                       OR id IN \(EntityOperations.inClause(movedAppearanceIDs)))
                ORDER BY id
                """,
            arguments: [entityID.uuidString]
                + StatementArguments(aliasList.map(\.uuidString))
                + StatementArguments(movedAppearanceIDs.map(\.uuidString))
        ) {
            let id = try UUID.required(row["id"])
            collector.add(table: "scene_entities", row: row)
            let ref = SubjectRef(kind: .appearance, id: id)
            affected.insert(ref)
            moved.append(ref)
            appearanceIDs.append(id)
            try db.execute(
                sql: "UPDATE scene_entities SET entity_id = ?, updated_at = ? WHERE id = ?",
                arguments: [newEntityID.uuidString, timestamp, id.uuidString]
            )
        }

        var evidenceIDs: [UUID] = []
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM evidence
                WHERE owner_entity_id = ?
                  AND (matched_alias_id IN \(EntityOperations.inClause(aliasList))
                       OR (subject_kind = 'alias'
                           AND subject_id IN \(EntityOperations.inClause(aliasList)))
                       OR (subject_kind = 'appearance'
                           AND subject_id IN \(EntityOperations.inClause(appearanceIDs))))
                ORDER BY id
                """,
            arguments: [entityID.uuidString]
                + StatementArguments(aliasList.map(\.uuidString))
                + StatementArguments(aliasList.map(\.uuidString))
                + StatementArguments(appearanceIDs.map(\.uuidString))
        ) {
            collector.add(table: "evidence", row: row)
            evidenceIDs.append(try UUID.required(row["id"]))
        }
        for id in evidenceIDs {
            try db.execute(
                sql: "UPDATE evidence SET owner_entity_id = ? WHERE id = ?",
                arguments: [newEntityID.uuidString, id.uuidString]
            )
        }

        // The new entity's own name becomes an alias on it, unless that normalized form
        // already exists — which it does whenever the split was made from that alias.
        if try AliasOperations.owner(
            projectID: source.projectID, kind: source.kind, normalized: normalized, in: db
        ) == nil {
            // Pinned by the operation, like `newEntityID`, so a redo brings the alias back
            // with the id it first had (§3.8).
            let aliasID = newAliasID ?? UUID()
            try AliasOperations.insert(
                id: aliasID, entityID: newEntityID, projectID: source.projectID,
                kind: source.kind, alias: trimmed, normalized: normalized,
                aliasKind: .human, actor: actor, timestamp: timestamp, in: db
            )
            let ref = SubjectRef(kind: .alias, id: aliasID)
            created.append(ref)
            affected.insert(ref)
        }

        // A redo puts back the lock rows the matching `unsplit` removed (§3.7).
        affected.formUnion(try restoreRemovedLocks(mode, in: db))

        return MutationEffect(
            inverse: .unsplit(created: created, moved: moved, sourceSnapshot: collector.snapshots),
            affected: affected,
            snapshots: collector.snapshots
        )
    }

    /// `splitEntity`'s inverse — never a plain merge, which would leave the new entity's
    /// name as an alias on the source that did not exist before the split (§3.5).
    static func unsplit(
        created: [SubjectRef],
        moved: [SubjectRef],
        sourceSnapshot: [RowSnapshot],
        in db: Database
    ) throws -> MutationEffect {
        // The redo's payload is read while the split's rows are still where it put them.
        let newEntityRef = created.first { $0.kind == .entity }
        let newName = try newEntityRef.flatMap { ref in
            try String.fetchOne(
                db, sql: "SELECT name FROM entities WHERE id = ?", arguments: [ref.id.uuidString]
            )
        }
        let sourceID = sourceSnapshot
            .first { $0.table == "entities" }
            .flatMap { snapshot -> UUID? in
                guard case let .string(raw)? = snapshot.columns["id"] else { return nil }
                return UUID(uuidString: raw)
            }

        // The rows go back **before** the new entity goes away: deleting it first would
        // cascade the very rows this inverse means to return.
        try RowGraph.restore(sourceSnapshot, in: db)
        let removedLocks = try RowGraph.delete(created, in: db)

        var affected = RowGraph.subjects(of: sourceSnapshot)
        affected.formUnion(created)
        affected.formUnion(moved)

        let inverse: EditOperation? = if let sourceID, let newEntityRef, let newName {
            .splitEntity(
                entityID: sourceID,
                aliasIDs: moved.filter { $0.kind == .alias }.map(\.id),
                newName: newName,
                newEntityID: newEntityRef.id,
                newAliasID: created.first { $0.kind == .alias }?.id,
                movedAppearanceIDs: moved.filter { $0.kind == .appearance }.map(\.id)
            )
        } else {
            nil
        }
        return MutationEffect(inverse: inverse, affected: affected, snapshots: removedLocks)
    }

    // MARK: - Preconditions (§3.8)

    static func precheckMerge(sourceIDs: [UUID], into targetID: UUID, in db: Database) throws {
        for id in sourceIDs + [targetID] {
            guard try RowSnapshotStore.exists(table: "entities", id: id, in: db) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "One of the items that change touched is no longer in this project."
                )
            }
        }
    }

    static func precheckSplit(
        entityID: UUID,
        aliasIDs: [UUID],
        newName: String,
        newEntityID: UUID,
        in db: Database
    ) throws {
        guard try RowSnapshotStore.exists(table: "entities", id: entityID, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That item is no longer in this project."
            )
        }
        guard try !RowSnapshotStore.exists(table: "entities", id: newEntityID, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change removed is already back."
            )
        }
        for aliasID in aliasIDs {
            guard try RowSnapshotStore.exists(table: "entity_aliases", id: aliasID, in: db) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "One of the aliases that change moved is gone."
                )
            }
        }
    }

    /// `unmerge` and `unsplit` need the same two things: the rows they created still
    /// there to remove, and every snapshot still free to go back.
    static func precheckUndo(
        created: [SubjectRef],
        snapshots: [RowSnapshot],
        in db: Database
    ) throws {
        for ref in created {
            guard let table = RowSnapshotStore.table(for: ref.kind) else { continue }
            guard try RowSnapshotStore.exists(table: table, id: ref.id, in: db) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "Something that change added is already gone."
                )
            }
        }
        try InverseApplication.precheckSnapshots(snapshots, in: db)
    }
}
