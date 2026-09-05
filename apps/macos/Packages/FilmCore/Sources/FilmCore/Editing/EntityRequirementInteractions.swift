import Foundation
import GRDB

/// PHASE2_DESIGN §7.4 — what the Phase 1 entity operations owe the requirement graph.
///
/// The Phase 1 operations enumerate their child tables explicitly, so every v4 table they
/// would otherwise strand or destroy is handled here, once, and called from
/// `EntityOperations` and `MergeSplitOperations`. Like every other file under `Editing/`
/// it opens **no transaction**.
enum EntityRequirementInteractions {

    // MARK: - Basis sweeps (§4.3's deleted-row policy, §7.4's last bullet)

    /// Basis rows citing a fact that is about to go away — snapshotted into `collector` and
    /// removed in the same transaction.
    ///
    /// `asset_requirement_basis.subject_id` is polymorphic and carries no foreign key
    /// (§4.3), so nothing else would take these rows: not the direct deletes
    /// (`removeState` / `removeEvent` / `removeSceneEntity`) and not the **cascade** paths
    /// (an entity delete taking its states, events, and appearances with it).
    @discardableResult
    static func sweepBasis(
        citing refs: [SubjectRef],
        into collector: inout SnapshotCollector,
        in db: Database
    ) throws -> Set<SubjectRef> {
        let found = try collectBasis(citing: refs, into: &collector, in: db)
        for ref in found { try RowSnapshotStore.delete(table: "asset_requirement_basis", id: ref.id, in: db) }
        return found
    }

    /// The snapshot half of `sweepBasis`, for a caller that deletes the rows itself —
    /// `deleteEntity` takes its whole capture list first and writes afterwards.
    static func collectBasis(
        citing refs: [SubjectRef],
        into collector: inout SnapshotCollector,
        in db: Database
    ) throws -> Set<SubjectRef> {
        var swept: Set<SubjectRef> = []
        for ref in refs {
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM asset_requirement_basis
                    WHERE subject_kind = ? AND subject_id = ? ORDER BY id
                    """,
                arguments: [ref.kind.rawValue, ref.id.uuidString]
            ) {
                let id = try UUID.required(row["id"])
                collector.add(table: "asset_requirement_basis", row: row)
                swept.insert(SubjectRef(kind: .basis, id: id))
            }
        }
        return swept
    }

    /// Basis rows citing a fact that lost a collision but has a survivor to inherit it —
    /// **re-pointed** rather than swept (§7.4: "sweep or re-point").
    ///
    /// `UNIQUE(requirement_id, subject_kind, subject_id)` means a requirement that already
    /// cites the survivor cannot cite it twice; that duplicate is snapshotted and dropped,
    /// exactly as a collision loser is everywhere else.
    @discardableResult
    static func retargetBasis(
        from loser: SubjectRef,
        to survivor: UUID,
        into collector: inout SnapshotCollector,
        in db: Database
    ) throws -> Set<SubjectRef> {
        var touched: Set<SubjectRef> = []
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM asset_requirement_basis
                WHERE subject_kind = ? AND subject_id = ? ORDER BY id
                """,
            arguments: [loser.kind.rawValue, loser.id.uuidString]
        ) {
            let id = try UUID.required(row["id"])
            let requirementID: String = row["requirement_id"]
            collector.add(table: "asset_requirement_basis", row: row)
            touched.insert(SubjectRef(kind: .basis, id: id))
            let duplicate = try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM asset_requirement_basis
                        WHERE requirement_id = ? AND subject_kind = ? AND subject_id = ?
                    )
                    """,
                arguments: [requirementID, loser.kind.rawValue, survivor.uuidString]
            ) ?? false
            if duplicate {
                try RowSnapshotStore.delete(table: "asset_requirement_basis", id: id, in: db)
            } else {
                try db.execute(
                    sql: "UPDATE asset_requirement_basis SET subject_id = ? WHERE id = ?",
                    arguments: [survivor.uuidString, id.uuidString]
                )
            }
        }
        return touched
    }

    // MARK: - deleteEntity (§7.4's first bullet)

    /// §7.4: a hard delete is refused while **any** of the entity's requirements has an
    /// asset. The FK is `ON DELETE RESTRICT`, so without this the failure would surface as
    /// a raw constraint error partway through the cascade.
    static func requireNoAssets(ofEntity entityID: UUID, in db: Database) throws {
        let holder = try String.fetchOne(
            db,
            sql: """
                SELECT assets.requirement_id FROM assets
                JOIN asset_requirements ON asset_requirements.id = assets.requirement_id
                WHERE asset_requirements.entity_id = ?
                ORDER BY assets.id LIMIT 1
                """,
            arguments: [entityID.uuidString]
        )
        guard holder == nil else { throw ProjectStoreError.entityHasAssets(entityID: entityID) }
    }

    /// The requirement half of `deleteEntity`'s capture list (§7.4).
    ///
    /// Everything `ON DELETE CASCADE` would take with the entity, so `restoreEntity` puts
    /// it back byte-identically: the requirements, their scene links, their basis rows,
    /// their dependency rows in **both** directions — including rows on *other* entities'
    /// requirements that depend on these — and the requirement lock rows.
    ///
    /// Returns the subjects touched and the basis rows the caller must delete by hand:
    /// citations of this entity's cascaded states, events, and appearances, which live on
    /// requirements the cascade does not reach.
    static func captureRequirementGraph(
        ofEntity entityID: UUID,
        facts: [SubjectRef],
        into collector: inout SnapshotCollector,
        in db: Database
    ) throws -> (affected: Set<SubjectRef>, lockSubjects: [SubjectRef], sweptBasis: [UUID]) {
        var affected: Set<SubjectRef> = []
        var lockSubjects: [SubjectRef] = []

        var requirementIDs: [UUID] = []
        for row in try Row.fetchAll(
            db, sql: "SELECT * FROM asset_requirements WHERE entity_id = ? ORDER BY id",
            arguments: [entityID.uuidString]
        ) {
            let id = try UUID.required(row["id"])
            requirementIDs.append(id)
            collector.add(table: "asset_requirements", row: row)
            let ref = SubjectRef(kind: .requirement, id: id)
            affected.insert(ref)
            lockSubjects.append(ref)
        }
        let list = EntityOperations.inClause(requirementIDs)
        let arguments = StatementArguments(requirementIDs.map(\.uuidString))

        for (table, kind, sql) in [
            (
                "asset_requirement_scenes", SubjectKind.requirementScene,
                "SELECT * FROM asset_requirement_scenes WHERE requirement_id IN \(list) ORDER BY id"
            ),
            (
                "asset_requirement_basis", SubjectKind.basis,
                "SELECT * FROM asset_requirement_basis WHERE requirement_id IN \(list) ORDER BY id"
            ),
        ] {
            for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
                collector.add(table: table, row: row)
                affected.insert(SubjectRef(kind: kind, id: try UUID.required(row["id"])))
            }
        }
        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM scene_reference_exclusions WHERE requirement_id IN \(list) ORDER BY id",
            arguments: arguments
        ) {
            collector.add(table: "scene_reference_exclusions", row: row)
        }
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM asset_dependencies
                WHERE requirement_id IN \(list) OR depends_on_requirement_id IN \(list)
                ORDER BY id
                """,
            arguments: arguments + arguments
        ) {
            collector.add(table: "asset_dependencies", row: row)
            affected.insert(SubjectRef(kind: .dependency, id: try UUID.required(row["id"])))
        }

        // PHASE3_DESIGN §7.3 / §4.3 (Plan 014): the requirements' prompt graphs cascade
        // with them; citing version stamps and foreign citations naming these
        // requirements are captured before the cascade nulls them. Hard delete is
        // refused while any requirement has an asset, so a prompt-bearing requirement
        // here carries no anchor — the transient §6.1 state — and the capture is what
        // keeps restoreEntity byte-identical.
        for row in try Row.fetchAll(
            db, sql: "SELECT * FROM asset_prompts WHERE requirement_id IN \(list) ORDER BY id",
            arguments: arguments
        ) {
            collector.add(table: "asset_prompts", row: row)
            affected.insert(SubjectRef(kind: .prompt, id: try UUID.required(row["id"])))
        }
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT asset_versions.* FROM asset_versions
                JOIN asset_prompts ON asset_prompts.id = asset_versions.prompt_id
                WHERE asset_prompts.requirement_id IN \(list) ORDER BY asset_versions.id
                """,
            arguments: arguments
        ) {
            collector.add(table: "asset_versions", row: row)
            affected.insert(SubjectRef(kind: .version, id: try UUID.required(row["id"])))
        }
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT DISTINCT asset_prompt_references.* FROM asset_prompt_references
                JOIN asset_prompts ON asset_prompts.id = asset_prompt_references.prompt_id
                WHERE asset_prompts.requirement_id IN \(list)
                   OR asset_prompt_references.requirement_id IN \(list)
                ORDER BY asset_prompt_references.id
                """,
            arguments: arguments + arguments
        ) {
            collector.add(table: "asset_prompt_references", row: row)
            affected.insert(SubjectRef(kind: .promptReference, id: try UUID.required(row["id"])))
        }

        // Citations of the facts the delete cascades away. Basis rows on this entity's own
        // requirements are snapshotted above and cascade with them; these are the ones on
        // **other** entities' requirements, which nothing would otherwise take.
        let swept = try collectBasis(citing: facts, into: &collector, in: db)
        affected.formUnion(swept)
        return (affected, lockSubjects, swept.map(\.id).sorted { $0.uuidString < $1.uuidString })
    }

    // MARK: - reclassify (§7.4's fourth bullet)

    /// §7.4: reclassify is refused while the entity has **canonical** requirement rows,
    /// tombstoned ones included — their template types are kind-bound and a tombstone keeps
    /// its `type_id`. Variant requirements carry across kinds unchanged.
    static func requireNoCanonicalRequirements(ofEntity entityID: UUID, in db: Database) throws {
        let holder = try String.fetchOne(
            db,
            sql: """
                SELECT id FROM asset_requirements
                WHERE entity_id = ? AND tier = 'canonical' ORDER BY id LIMIT 1
                """,
            arguments: [entityID.uuidString]
        )
        guard holder == nil else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: """
                    This item has canonical asset requirements, which belong to its kind. \
                    Delete them before changing its kind — rejecting one does not make the \
                    row absent.
                    """
            )
        }
    }

    // MARK: - mergeEntities (§7.4's second bullet)

    /// One `(entity_id, type_id)` or `(entity_id, name_normalized)` clash between a
    /// requirement of the source and one of the target.
    struct RequirementCollision {
        let sourceRequirementID: UUID
        let targetRequirementID: UUID
        let survivorID: UUID
        let loserID: UUID
    }

    /// What the requirement half of a merge will do, decided **before any write**: which
    /// rows collide, who survives, and whether the merge is refused outright.
    struct RequirementMergePlan {
        var movingIDs: [UUID] = []
        var collisions: [RequirementCollision] = []
        /// Loser → survivor, for the dependency retarget.
        var mapping: [UUID: UUID] = [:]
    }

    /// §7.4's collision rule, planned ahead of the writes so its refusals — the both-assets
    /// pair and a retarget that would close a dependency loop — are thrown before the first
    /// statement.
    static func planRequirementMerge(
        source sourceID: UUID,
        target targetID: UUID,
        in db: Database
    ) throws -> RequirementMergePlan {
        var plan = RequirementMergePlan()
        for row in try Row.fetchAll(
            db, sql: "SELECT * FROM asset_requirements WHERE entity_id = ? ORDER BY id",
            arguments: [sourceID.uuidString]
        ) {
            let id = try UUID.required(row["id"])
            guard let rival = try rivalRequirement(of: row, onEntity: targetID, in: db) else {
                plan.movingIDs.append(id)
                continue
            }
            let rivalID = try UUID.required(rival["id"])
            // **Unless both members of a colliding pair have assets, which refuses the
            // merge** — the remedy depends on the tier (§7.4).
            if try RequirementOperations.hasAsset(requirementID: id, in: db),
               try RequirementOperations.hasAsset(requirementID: rivalID, in: db) {
                throw ProjectStoreError.mergeRefused(reason: bothAssetsReason(row, rival))
            }
            // Liveness first, then the Phase 1 protection order — §7.2's ordering, shared.
            let ordered = RequirementOperations.combineSurvivorFirst([row, rival])
            let survivorID = try UUID.required(ordered[0]["id"])
            let loserID = try UUID.required(ordered[1]["id"])
            plan.collisions.append(
                RequirementCollision(
                    sourceRequirementID: id,
                    targetRequirementID: rivalID,
                    survivorID: survivorID,
                    loserID: loserID
                )
            )
            plan.mapping[loserID] = survivorID
            if survivorID == id { plan.movingIDs.append(id) }
        }

        // The prospective dependency graph, re-checked before any write (§7.4).
        var prospective: [(from: UUID, to: UUID)] = []
        var pairs: Set<String> = []
        for edge in try RequirementOperations.activeEdges(in: db) {
            let from = plan.mapping[edge.from] ?? edge.from
            let to = plan.mapping[edge.to] ?? edge.to
            guard from != to else { continue }
            guard pairs.insert("\(from.uuidString)/\(to.uuidString)").inserted else { continue }
            prospective.append((from, to))
        }
        guard !RequirementOperations.hasCycle(prospective) else {
            throw ProjectStoreError.mergeRefused(
                reason: "Merging those items would make their requirements depend on each other in a loop."
            )
        }
        return plan
    }

    /// The requirement of the target entity a source requirement would collide with, over
    /// **either** §4.3 unique.
    private static func rivalRequirement(
        of row: Row,
        onEntity targetID: UUID,
        in db: Database
    ) throws -> Row? {
        if let typeID = row["type_id"] as String?,
           let rival = try Row.fetchOne(
               db,
               sql: "SELECT * FROM asset_requirements WHERE entity_id = ? AND type_id = ?",
               arguments: [targetID.uuidString, typeID]
           ) {
            return rival
        }
        return try Row.fetchOne(
            db,
            sql: "SELECT * FROM asset_requirements WHERE entity_id = ? AND name_normalized = ?",
            arguments: [targetID.uuidString, row["name_normalized"] as String]
        )
    }

    /// §7.4's tier-dependent remedy wording.
    private static func bothAssetsReason(_ lhs: Row, _ rhs: Row) -> String {
        let names = "“\(lhs["name"] as String)” and “\(rhs["name"] as String)”"
        let isVariant = (lhs["tier"] as String? ?? "") == AssetRequirementTier.variant.rawValue
            && (rhs["tier"] as String? ?? "") == AssetRequirementTier.variant.rawValue
        return isVariant
            ? "\(names) both have media. Combine the pair first, then merge."
            : "\(names) both have media. Delete or reject one side's asset, then merge."
    }

    /// The write half of the plan: requirements moved to the target entity, collision
    /// losers snapshotted and dropped with a single-asset re-point, and dependency edges
    /// retargeted with self-edges and duplicates removed.
    ///
    /// Everything moved or dropped joins the caller's payload, so `unmerge` stays
    /// byte-identical.
    static func applyRequirementMerge(
        _ plan: RequirementMergePlan,
        target targetID: UUID,
        timestamp: String,
        into collector: inout SnapshotCollector,
        affected: inout Set<SubjectRef>,
        moved: inout [SubjectRef],
        in db: Database
    ) throws {
        // 1. Dependency edges that touch a dropped loser: retargeted onto its survivor
        //    **before** the loser goes away, because `ON DELETE CASCADE` would otherwise
        //    destroy the very edges §7.4 says to retarget. Self-edges are removed and
        //    duplicates dropped by the same survivor rule.
        try retargetDependencies(
            plan.mapping, timestamp: timestamp, into: &collector, affected: &affected,
            moved: &moved, in: db
        )

        // 2. Collision losers: snapshotted with their graphs and dropped.
        for collision in plan.collisions {
            let loser = SubjectRef(kind: .requirement, id: collision.loserID)
            affected.insert(loser)
            affected.insert(SubjectRef(kind: .requirement, id: collision.survivorID))
            try captureRequirementRow(collision.loserID, into: &collector, affected: &affected, in: db)
            try captureRequirementRow(
                collision.survivorID, into: &collector, affected: &affected, in: db
            )
            // "A losing requirement's asset (when only it has one) re-points to the
            // surviving requirement" — and it has to, or `ON DELETE RESTRICT` refuses the
            // drop. The plan already refused the pair where both had one.
            if let asset = try Row.fetchOne(
                db, sql: "SELECT * FROM assets WHERE requirement_id = ?",
                arguments: [collision.loserID.uuidString]
            ) {
                let assetID = try UUID.required(asset["id"])
                collector.add(table: "assets", row: asset)
                let ref = SubjectRef(kind: .asset, id: assetID)
                affected.insert(ref)
                moved.append(ref)
                try db.execute(
                    sql: "UPDATE assets SET requirement_id = ?, updated_at = ? WHERE id = ?",
                    arguments: [collision.survivorID.uuidString, timestamp, assetID.uuidString]
                )
            }
            // PHASE3_DESIGN §7.3 / §4.3: the loser's prompt graphs are captured and
            // dropped with it; the version rows stamped by those prompts — under the
            // re-pointed asset or wherever an earlier combine left them — are snapshotted
            // before the cascade SET NULLs their stamps. The moved requirements' prompts
            // all read stale immediately afterwards (the merge changed §8.2 inputs),
            // which is correct and asserted in PromptCaptureTests.
            let loserPrompts = try RowSnapshotStore.captureAll(
                table: "asset_prompts", where: "requirement_id = ?",
                arguments: [collision.loserID.uuidString], in: db
            )
            for snapshot in loserPrompts {
                collector.add(snapshot)
                if case let .string(raw)? = snapshot.columns["id"],
                   let promptID = UUID(uuidString: raw) {
                    affected.insert(SubjectRef(kind: .prompt, id: promptID))
                }
            }
            let loserPromptIDs = loserPrompts.compactMap { snapshot -> UUID? in
                guard case let .string(raw)? = snapshot.columns["id"] else { return nil }
                return UUID(uuidString: raw)
            }
            if !loserPromptIDs.isEmpty {
                for row in try Row.fetchAll(
                    db,
                    sql: """
                        SELECT asset_versions.* FROM asset_versions
                        JOIN asset_prompts ON asset_prompts.id = asset_versions.prompt_id
                        WHERE asset_prompts.requirement_id = ? ORDER BY asset_versions.id
                        """,
                    arguments: [collision.loserID.uuidString]
                ) {
                    let versionID = try UUID.required(row["id"])
                    collector.add(table: "asset_versions", row: row)
                    affected.insert(SubjectRef(kind: .version, id: versionID))
                }
                for row in try Row.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT asset_prompt_references.* FROM asset_prompt_references
                        JOIN asset_prompts ON asset_prompts.id = asset_prompt_references.prompt_id
                        WHERE asset_prompts.requirement_id = ?
                           OR asset_prompt_references.requirement_id = ?
                        ORDER BY asset_prompt_references.id
                        """,
                    arguments: StatementArguments([collision.loserID.uuidString])
                        + StatementArguments([collision.loserID.uuidString])
                ) {
                    let citationID = try UUID.required(row["id"])
                    collector.add(table: "asset_prompt_references", row: row)
                    affected.insert(SubjectRef(kind: .promptReference, id: citationID))
                }
            }

            try RowSnapshotStore.deleteLocks(subject: loser, in: db)
            // `ON DELETE CASCADE` takes the loser's scene links, basis rows, dependency
            // rows, prompts, and their citations — all snapshotted above.
            try RowSnapshotStore.delete(table: "asset_requirements", id: collision.loserID, in: db)
        }

        // 3. The rows that move to the target entity, survivors of a collision included.
        for id in plan.movingIDs {
            guard try RowSnapshotStore.exists(table: "asset_requirements", id: id, in: db) else {
                continue
            }
            try captureRequirementRow(id, into: &collector, affected: &affected, in: db)
            let ref = SubjectRef(kind: .requirement, id: id)
            affected.insert(ref)
            moved.append(ref)
            try db.execute(
                sql: "UPDATE asset_requirements SET entity_id = ?, updated_at = ? WHERE id = ?",
                arguments: [targetID.uuidString, timestamp, id.uuidString]
            )
        }

    }

    private static func retargetDependencies(
        _ mapping: [UUID: UUID],
        timestamp: String,
        into collector: inout SnapshotCollector,
        affected: inout Set<SubjectRef>,
        moved: inout [SubjectRef],
        in db: Database
    ) throws {
        guard !mapping.isEmpty else { return }
        for row in try Row.fetchAll(db, sql: "SELECT id FROM asset_dependencies ORDER BY id") {
            let id = try UUID.required(row["id"])
            guard let current = try Row.fetchOne(
                db, sql: "SELECT * FROM asset_dependencies WHERE id = ?", arguments: [id.uuidString]
            ) else { continue }
            let oldFrom = try UUID.required(current["requirement_id"])
            let oldTo = try UUID.required(current["depends_on_requirement_id"])
            let from = mapping[oldFrom] ?? oldFrom
            let to = mapping[oldTo] ?? oldTo
            guard from != oldFrom || to != oldTo else { continue }
            let ref = SubjectRef(kind: .dependency, id: id)
            collector.add(table: "asset_dependencies", row: current)
            affected.insert(ref)
            if from == to {
                try RowSnapshotStore.delete(table: "asset_dependencies", id: id, in: db)
                continue
            }
            if let rival = try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM asset_dependencies
                    WHERE requirement_id = ? AND depends_on_requirement_id = ? AND id <> ?
                    """,
                arguments: [from.uuidString, to.uuidString, id.uuidString]
            ) {
                let rivalID = try UUID.required(rival["id"])
                collector.add(table: "asset_dependencies", row: rival)
                affected.insert(SubjectRef(kind: .dependency, id: rivalID))
                let ordered = RequirementOperations.combineSurvivorFirst([current, rival])
                let survivorID = try UUID.required(ordered[0]["id"])
                let loserID = try UUID.required(ordered[1]["id"])
                try RowSnapshotStore.delete(table: "asset_dependencies", id: loserID, in: db)
                guard survivorID == id else { continue }
            }
            try db.execute(
                sql: """
                    UPDATE asset_dependencies
                    SET requirement_id = ?, depends_on_requirement_id = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [from.uuidString, to.uuidString, timestamp, id.uuidString]
            )
            moved.append(ref)
        }
    }

    /// One requirement row plus everything a cascade would take with it, snapshotted so the
    /// merge's payload can put it all back.
    private static func captureRequirementRow(
        _ id: UUID,
        into collector: inout SnapshotCollector,
        affected: inout Set<SubjectRef>,
        in db: Database
    ) throws {
        guard let requirement = try RequirementOperations.fetch(id: id, in: db) else { return }
        let capture = try RequirementOperations.captureGraph(of: requirement, in: db)
        collector.add(contentsOf: capture.snapshots)
        affected.formUnion(capture.affected)
    }
}
