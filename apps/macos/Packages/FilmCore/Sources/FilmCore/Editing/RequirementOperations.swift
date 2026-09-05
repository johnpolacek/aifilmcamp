import Foundation
import GRDB

/// The requirement half of PHASE2_DESIGN §7.2's operation table.
///
/// Shaped exactly like Plan 005's `EntityOperations`: `MutationEffect`-returning static
/// funcs plus `precheck*` helpers, and **no transaction opened** — the reentrancy test globs
/// `Editing/*.swift`, so this file is covered automatically (§7.1).
///
/// No operation here creates an `assets` row. The asset-touching halves —
/// `rejectRequirement`, `unrejectRequirement`, and `setRequirementNecessity` recomputing an
/// existing asset to and from `deprecated`, and `combineRequirements` merging assets — go
/// through `AssetStatusRecompute` over rows that already exist; Plan 011 owns creating them.
enum RequirementOperations {

    // MARK: - Row access

    /// The columns a requirement operation needs, without decoding the whole domain row.
    struct RequirementRow {
        let id: UUID
        let projectID: UUID
        let entityID: UUID
        let tier: AssetRequirementTier
        let typeID: UUID?
        let name: String
        let nameNormalized: String
        let reason: String
        let necessity: RequirementNecessity
        let source: FactSource
        let createdSource: FactSource
        let reviewState: ReviewState
        let createdAt: String

        var ref: SubjectRef { SubjectRef(kind: .requirement, id: id) }
    }

    static func fetch(id: UUID, in db: Database) throws -> RequirementRow? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM asset_requirements WHERE id = ?", arguments: [id.uuidString]
        ) else { return nil }
        return try decode(row)
    }

    static func require(id: UUID, in db: Database) throws -> RequirementRow {
        guard let row = try fetch(id: id, in: db) else {
            throw ProjectStoreError.requirementNotFound
        }
        return row
    }

    static func decode(_ row: Row) throws -> RequirementRow {
        guard let tier = AssetRequirementTier(rawValue: row["tier"]),
              let necessity = RequirementNecessity(rawValue: row["necessity"]),
              let source = FactSource(rawValue: row["source"]),
              let createdSource = FactSource(rawValue: row["created_source"]),
              let reviewState = ReviewState(rawValue: row["review_state"])
        else { throw ProjectStoreError.invalidBundle }
        return RequirementRow(
            id: try UUID.required(row["id"]),
            projectID: try UUID.required(row["project_id"]),
            entityID: try UUID.required(row["entity_id"]),
            tier: tier,
            typeID: try (row["type_id"] as String?).map(UUID.required),
            name: row["name"],
            nameNormalized: row["name_normalized"],
            reason: row["reason"],
            necessity: necessity,
            source: source,
            createdSource: createdSource,
            reviewState: reviewState,
            createdAt: row["created_at"]
        )
    }

    /// The requirement of that entity already holding `normalized`, if any —
    /// `UNIQUE(entity_id, name_normalized)`, which spans **both** tiers (§4.3).
    static func conflictingRequirementID(
        entityID: UUID,
        normalized: String,
        excluding id: UUID,
        in db: Database
    ) throws -> UUID? {
        guard let raw = try String.fetchOne(
            db,
            sql: """
                SELECT id FROM asset_requirements
                WHERE entity_id = ? AND name_normalized = ? AND id <> ?
                """,
            arguments: [entityID.uuidString, normalized, id.uuidString]
        ) else { return nil }
        return try UUID.required(raw)
    }

    /// The row already filling `(entity_id, type_id)` — a **tombstoned** one included, which
    /// is what makes Build respect a rejected canonical slot rather than resurrect it (§5.2).
    static func canonicalSlotHolder(
        entityID: UUID,
        typeID: UUID,
        in db: Database
    ) throws -> UUID? {
        guard let raw = try String.fetchOne(
            db,
            sql: "SELECT id FROM asset_requirements WHERE entity_id = ? AND type_id = ?",
            arguments: [entityID.uuidString, typeID.uuidString]
        ) else { return nil }
        return try UUID.required(raw)
    }

    /// `true` when an `assets` row fills this requirement (§7.2's delete refusal).
    static func hasAsset(requirementID: UUID, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM assets WHERE requirement_id = ?)",
            arguments: [requirementID.uuidString]
        ) ?? false
    }

    // MARK: - Shared guards and provenance

    /// §7.1's human-only discipline, for the operations the AI actor may never perform:
    /// template edits, `manifest_inclusion`, and `necessity`.
    static func requireHuman(_ actor: MutationActor, subject: SubjectRef) throws {
        guard actor == .human else { throw ProjectStoreError.protectedFact(subject: subject) }
    }

    /// The PROV values a `.human` / `.ai` insert into a v4 fact table is born with (§3.7).
    static func insertProvenance(_ actor: MutationActor, timestamp: String) -> StatementArguments {
        let isHuman = actor == .human
        return [
            actor.factSource.rawValue,
            (isHuman ? ReviewState.accepted : ReviewState.proposed).rawValue,
            isHuman ? timestamp : nil,
            actor.jobID?.uuidString,
            actor.factSource.rawValue, timestamp, timestamp,
        ]
    }

    /// The `.inverting` half every scalar requirement op shares.
    ///
    /// Deliberately **not** `InverseApplication.restoreAffected(ownedBy:)`: an `assets` row
    /// carries no `entity_id`, so the owner filter would skip exactly the row the recompute
    /// touched. Restoring the requirement row plus the asset row that names it is both
    /// precise and batch-safe — a group's snapshots cover every child, and each child here
    /// restores only its own two rows.
    static func invertScalar(
        id: UUID,
        entry: JournalEntry,
        redo: (RequirementRow) -> EditOperation,
        in db: Database
    ) throws -> MutationEffect {
        let current = try require(id: id, in: db)
        var affected: Set<SubjectRef> = [current.ref]
        var priors: [RowSnapshot] = []
        if let snapshot = try RowSnapshotStore.capture(table: "asset_requirements", id: id, in: db) {
            priors.append(snapshot)
        }
        var restorable: [RowSnapshot] = []
        if let snapshot = entry.snapshot(table: "asset_requirements", id: id) {
            restorable.append(snapshot)
        }
        // The asset the entry's recompute rewrote, if there was one.
        for snapshot in entry.snapshots
        where snapshot.table == "assets"
            && snapshot.columns["requirement_id"] == .string(id.uuidString) {
            guard case let .string(rawID)? = snapshot.columns["id"],
                  let assetID = UUID(uuidString: rawID)
            else { continue }
            affected.insert(SubjectRef(kind: .asset, id: assetID))
            if let current = try RowSnapshotStore.capture(table: "assets", id: assetID, in: db) {
                priors.append(current)
            }
            restorable.append(snapshot)
        }
        guard !restorable.isEmpty else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has anything to restore."
            )
        }
        try RowGraph.restore(restorable, in: db)
        return MutationEffect(inverse: redo(current), affected: affected, snapshots: priors)
    }

    // MARK: - createRequirement / createCanonicalRequirement (§7.2, §5.2)

    /// §7.2's create. The id travels in the operation so a redo restores the row it first
    /// made.
    ///
    /// The eligibility rule is §3.3's **pool** and nothing more: the 2+ rule, §3.4's prop
    /// exception, and `manifest_inclusion` bound Build and the inference run, never a
    /// deliberate add — a person may create a prop requirement, or one on a `'never'`
    /// entity, directly.
    static func create(
        id: UUID,
        entityID: UUID,
        tier: AssetRequirementTier,
        typeID: UUID?,
        name: String,
        reason: String,
        outfitSourceVersionID: UUID? = nil,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        guard let entity = try EntityOperations.fetch(id: entityID, in: db) else {
            throw ProjectStoreError.entityNotFound
        }
        // §3.3's pool: rejected tombstones and marked-irrelevant entities earn nothing.
        guard entity.reviewState != .rejected, entity.isRelevant else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "That item is rejected or marked irrelevant, so it cannot take a new requirement."
            )
        }
        try validateTierPairing(tier: tier, typeID: typeID, entity: entity, in: db)
        // §7.1's write surface: the `.ai` actor "may create variant requirements … and
        // canonical-tier **prop** requirements (§3.4)" — and nothing else. A canonical row
        // on any other kind belongs to the template rule, whose rows are `parser`-sourced
        // and engine-internal (`createCanonicalRequirement`); an AI-proposed prop
        // requirement is canonical-tier but `ai`-sourced, and follows the ordinary
        // lifecycle. The rule lives here rather than in the wrapper so Plan 012's apply
        // reaches it through the same door.
        if actor != .human, tier == .canonical, entity.kind != .prop {
            throw ProjectStoreError.protectedFact(subject: SubjectRef(kind: .requirement, id: id))
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.invalidName(reason: "A name cannot be empty.")
        }
        let normalized = EntityNormalization.normalize(trimmed)
        if let conflicting = try conflictingRequirementID(
            entityID: entityID, normalized: normalized, excluding: id, in: db
        ) {
            throw ProjectStoreError.requirementNameConflict(existingRequirementID: conflicting)
        }
        if let typeID, let holder = try canonicalSlotHolder(entityID: entityID, typeID: typeID, in: db) {
            throw ProjectStoreError.requirementNameConflict(existingRequirementID: holder)
        }

        let timestamp = UTCDate.string(from: Date())
        try insertRequirement(
            id: id,
            projectID: entity.projectID,
            entityID: entityID,
            tier: tier,
            typeID: typeID,
            name: trimmed,
            normalized: normalized,
            reason: reason,
            necessity: .required,
            provenance: insertProvenance(actor, timestamp: timestamp),
            in: db
        )

        if let outfitSourceVersionID {
            guard actor == .human, tier == .variant, entity.kind == .character,
                  try Bool.fetchOne(db, sql: """
                    SELECT EXISTS(SELECT 1 FROM asset_versions v
                    JOIN assets a ON a.id = v.asset_id
                    JOIN asset_requirements r ON r.id = a.requirement_id
                    LEFT JOIN asset_requirement_types t ON t.id = r.type_id
                    WHERE v.id = ? AND v.status = 'approved' AND r.entity_id = ?
                      AND (t.code = 'full_body' OR r.outfit_source_version_id IS NOT NULL))
                    """, arguments: [outfitSourceVersionID.uuidString, entityID.uuidString]) == true
            else { throw ProjectStoreError.requirementOperationRefused(
                reason: "Choose a current character body image to create an outfit."
            ) }
            try db.execute(sql: "UPDATE asset_requirements SET outfit_source_version_id = ? WHERE id = ?",
                           arguments: [outfitSourceVersionID.uuidString, id.uuidString])
        }

        var affected: Set<SubjectRef> = [SubjectRef(kind: .requirement, id: id)]
        // §3.5: a new variant depends on each of its entity's existing active canonicals,
        // skipping any pair a rejected dependency tombstone covers.
        if tier == .variant {
            for canonicalID in try seedTargets(entityID: entityID, tier: .canonical, in: db) {
                if outfitSourceVersionID != nil {
                    let code = try String.fetchOne(db, sql: """
                        SELECT t.code FROM asset_requirements r
                        JOIN asset_requirement_types t ON t.id = r.type_id WHERE r.id = ?
                        """, arguments: [canonicalID.uuidString])
                    guard code == "face_closeup" else { continue }
                }
                guard try !dependencyExists(from: id, to: canonicalID, in: db) else { continue }
                let dependencyID = UUID()
                try insertDependency(
                    id: dependencyID,
                    requirementID: id,
                    dependsOnID: canonicalID,
                    provenance: insertProvenance(actor, timestamp: timestamp),
                    in: db
                )
                affected.insert(SubjectRef(kind: .dependency, id: dependencyID))
            }
        }
        return MutationEffect(inverse: .deleteRequirement(id: id), affected: affected)
    }

    /// §5.2's engine-internal creation, with **fixed `parser` provenance** so it is the
    /// operation — not a caller — that decides where a canonical row came from.
    ///
    /// It also writes §3.5's **mirror** dependency rows: each existing active variant of the
    /// entity gains a dependency on the new canonical, so a late-enabled template entry
    /// still participates in staleness. Seeding them here rather than as sibling children
    /// keeps their `parser` provenance fixed by the same operation, and makes them travel
    /// with the row on delete/restore through `ON DELETE CASCADE` and the delete's capture.
    static func createCanonical(
        id: UUID,
        entityID: UUID,
        typeID: UUID,
        name: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        // §7.1: the AI "never creates … `parser`-sourced canonical requirements". The row's
        // provenance is fixed by this operation, so the actor gate belongs here too —
        // `refreshCanonicalRequirements` is a public door that takes an actor, and without
        // this guard an `.ai` Build would mint parser rows.
        if case .refreshingCanonicalRequirements = mode {
            // The extraction run owns this deterministic post-processing edit so Revert
            // can undo it. The operation below still fixes row provenance to `parser`.
        } else {
            try requireHuman(actor, subject: SubjectRef(kind: .requirement, id: id))
        }
        guard let entity = try EntityOperations.fetch(id: entityID, in: db) else {
            throw ProjectStoreError.entityNotFound
        }
        try validateTierPairing(tier: .canonical, typeID: typeID, entity: entity, in: db)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.invalidName(reason: "A name cannot be empty.")
        }
        let normalized = EntityNormalization.normalize(trimmed)
        if let conflicting = try conflictingRequirementID(
            entityID: entityID, normalized: normalized, excluding: id, in: db
        ) {
            throw ProjectStoreError.requirementNameConflict(existingRequirementID: conflicting)
        }
        if let holder = try canonicalSlotHolder(entityID: entityID, typeID: typeID, in: db) {
            throw ProjectStoreError.requirementNameConflict(existingRequirementID: holder)
        }

        let timestamp = UTCDate.string(from: Date())
        // `parser` reads as "deterministic app pipeline" from Phase 2 on (§3.7), and such a
        // row is born `accepted` under a human gesture, exactly as `importScreenplay`'s are.
        let provenance: StatementArguments = [
            FactSource.parser.rawValue, ReviewState.accepted.rawValue, nil, nil,
            FactSource.parser.rawValue, timestamp, timestamp,
        ]
        try insertRequirement(
            id: id,
            projectID: entity.projectID,
            entityID: entityID,
            tier: .canonical,
            typeID: typeID,
            name: trimmed,
            normalized: normalized,
            reason: "",
            necessity: .required,
            provenance: provenance,
            in: db
        )

        var affected: Set<SubjectRef> = [SubjectRef(kind: .requirement, id: id)]
        for variantID in try seedTargets(entityID: entityID, tier: .variant, in: db) {
            if let variant = try Row.fetchOne(db, sql: "SELECT * FROM asset_requirements WHERE id = ?",
                                             arguments: [variantID.uuidString]),
               variant.hasColumn("outfit_source_version_id"),
               variant["outfit_source_version_id"] as String? != nil {
                let code = try String.fetchOne(db, sql: "SELECT code FROM asset_requirement_types WHERE id = ?",
                                               arguments: [typeID.uuidString])
                guard code == "face_closeup" else { continue }
            }
            guard try !dependencyExists(from: variantID, to: id, in: db) else { continue }
            let dependencyID = UUID()
            try insertDependency(
                id: dependencyID,
                requirementID: variantID,
                dependsOnID: id,
                provenance: provenance,
                in: db
            )
            affected.insert(SubjectRef(kind: .dependency, id: dependencyID))
        }
        affected.formUnion(
            try seedCharacterIdentityBundleDependency(
                entityID: entityID, provenance: provenance, in: db
            )
        )
        return MutationEffect(inverse: .deleteRequirement(id: id), affected: affected)
    }

    /// Plan 029's canonical bundle edge. This runs after either canonical is created, so
    /// it converges whether Face Closeup or Full Body filled the entity's template first.
    /// `dependencyExists` includes rejected rows, preserving a deliberate tombstone.
    private static func seedCharacterIdentityBundleDependency(
        entityID: UUID,
        provenance: StatementArguments,
        in db: Database
    ) throws -> Set<SubjectRef> {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT body.id AS body_id, face.id AS face_id
                FROM asset_requirements body
                JOIN asset_requirement_types body_type ON body_type.id = body.type_id
                JOIN asset_requirements face ON face.entity_id = body.entity_id
                JOIN asset_requirement_types face_type ON face_type.id = face.type_id
                WHERE body.entity_id = ?
                  AND body_type.entity_kind = 'character'
                  AND body_type.code = 'full_body'
                  AND face_type.entity_kind = 'character'
                  AND face_type.code = 'face_closeup'
                  AND body.review_state <> 'rejected'
                  AND body.necessity <> 'not_needed'
                  AND face.review_state <> 'rejected'
                  AND face.necessity <> 'not_needed'
                LIMIT 1
                """,
            arguments: [entityID.uuidString]
        ) else { return [] }

        let bodyID = try UUID.required(row["body_id"])
        let faceID = try UUID.required(row["face_id"])
        guard try !dependencyExists(from: bodyID, to: faceID, in: db) else { return [] }

        let dependencyID = UUID()
        try insertDependency(
            id: dependencyID,
            requirementID: bodyID,
            dependsOnID: faceID,
            provenance: provenance,
            in: db
        )
        return [SubjectRef(kind: .dependency, id: dependencyID)]
    }

    /// §4.3's `CHECK ((tier = 'canonical') = (type_id IS NOT NULL))` plus the Swift half:
    /// the template row must belong to the same project and match the entity's kind.
    private static func validateTierPairing(
        tier: AssetRequirementTier,
        typeID: UUID?,
        entity: EntityOperations.EntityRow,
        in db: Database
    ) throws {
        switch (tier, typeID) {
        case (.canonical, .none):
            throw ProjectStoreError.requirementOperationRefused(
                reason: "A canonical requirement has to name a template entry."
            )
        case (.variant, .some):
            throw ProjectStoreError.requirementOperationRefused(
                reason: "A variant requirement does not belong to a template entry."
            )
        case (.variant, .none):
            return
        case let (.canonical, .some(typeID)):
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM asset_requirement_types WHERE id = ?",
                arguments: [typeID.uuidString]
            ) else {
                throw ProjectStoreError.invalidTemplateEntry(
                    reason: "That template entry is not in this project."
                )
            }
            guard try UUID.required(row["project_id"]) == entity.projectID,
                  EntityKind(rawValue: row["entity_kind"]) == entity.kind
            else {
                throw ProjectStoreError.invalidTemplateEntry(
                    reason: "That template entry belongs to a different kind of item."
                )
            }
        }
    }

    static func insertRequirement(
        id: UUID,
        projectID: UUID,
        entityID: UUID,
        tier: AssetRequirementTier,
        typeID: UUID?,
        name: String,
        normalized: String,
        reason: String,
        necessity: RequirementNecessity,
        provenance: StatementArguments,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO asset_requirements (
                    id, project_id, entity_id, tier, type_id, name, name_normalized,
                    reason, necessity, source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString, projectID.uuidString, entityID.uuidString, tier.rawValue,
                typeID?.uuidString, name, normalized, reason, necessity.rawValue,
            ] + provenance
        )
    }

    static func insertDependency(
        id: UUID,
        requirementID: UUID,
        dependsOnID: UUID,
        provenance: StatementArguments,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO asset_dependencies (
                    id, requirement_id, depends_on_requirement_id,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [id.uuidString, requirementID.uuidString, dependsOnID.uuidString] + provenance
        )
    }

    /// The other-tier requirements of one entity that §3.5's seeding points at: active rows
    /// only, in a stable order.
    static func seedTargets(
        entityID: UUID,
        tier: AssetRequirementTier,
        in db: Database
    ) throws -> [UUID] {
        try String
            .fetchAll(
                db,
                sql: """
                    SELECT id FROM asset_requirements
                    WHERE entity_id = ? AND tier = ?
                      AND review_state <> 'rejected' AND necessity <> 'not_needed'
                    ORDER BY id
                    """,
                arguments: [entityID.uuidString, tier.rawValue]
            )
            .map { try UUID.required($0) }
    }

    /// `true` when a dependency row for that pair exists **in any state** — a rejected
    /// tombstone included, which is exactly what makes a deliberate removal stick across
    /// refreshes and inference (§3.5).
    static func dependencyExists(from: UUID, to: UUID, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM asset_dependencies
                    WHERE requirement_id = ? AND depends_on_requirement_id = ?
                )
                """,
            arguments: [from.uuidString, to.uuidString]
        ) ?? false
    }
}

// MARK: - deleteRequirement / restoreRequirement (§7.2, §4.3's deleted-row policy)

extension RequirementOperations {
    /// §7.2's hard delete: `human`-created or already-rejected rows only, and **refused
    /// while an asset row exists**. Everything else tombstones instead — the engine routes,
    /// exactly as entity delete does.
    static func delete(
        id: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let requirement = try require(id: id, in: db)
        let createdHere = ContinuityOperations.createdByInvertedEntry(
            mode, table: "asset_requirements", id: id
        )
        if case .apply = mode {
            try ProtectionPolicy.checkFactEdit(
                ref: requirement.ref, source: requirement.source,
                reviewState: requirement.reviewState, actor: actor, in: db
            )
            guard requirement.source == .human || requirement.reviewState == .rejected else {
                return try rejectRow(requirement, actor: actor, mode: mode, in: db)
            }
        }
        // §7.2: the FK is `ON DELETE RESTRICT`; the Swift precheck turns what would be a raw
        // constraint failure into "delete the asset first".
        guard try !hasAsset(requirementID: id, in: db) else {
            throw ProjectStoreError.requirementHasAsset(requirementID: id)
        }
        if !createdHere, case .inverting = mode,
           !(requirement.source == .human || requirement.reviewState == .rejected) {
            // Undoing a create of an `ai`/`parser` row is still a delete (§3.8 outranks
            // §3.6 for the row an entry created); anything else routes to the tombstone.
            return try rejectRow(requirement, actor: actor, mode: mode, in: db)
        }

        let graph = try captureGraph(of: requirement, in: db)
        try RowSnapshotStore.deleteLocks(subject: requirement.ref, in: db)
        // `ON DELETE CASCADE` takes the scene links, basis rows, and dependency rows in
        // both directions.
        try RowSnapshotStore.delete(table: "asset_requirements", id: id, in: db)
        return MutationEffect(
            inverse: .restoreRequirement(graph: graph.snapshots),
            affected: graph.affected,
            snapshots: graph.snapshots
        )
    }

    /// `deleteRequirement`'s inverse: the whole graph back by original id.
    static func restore(graph: [RowSnapshot], in db: Database) throws -> MutationEffect {
        var missing: UUID?
        var first: UUID?
        for snapshot in graph where snapshot.table == "asset_requirements" {
            guard case let .string(raw)? = snapshot.columns["id"], let id = UUID(uuidString: raw)
            else { continue }
            if first == nil { first = id }
            if try !RowSnapshotStore.isPresent(snapshot, in: db) { missing = id }
        }
        guard let restored = missing ?? first else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has anything to restore."
            )
        }
        try RowGraph.restore(graph, in: db)
        return MutationEffect(
            inverse: .deleteRequirement(id: restored),
            affected: RowGraph.subjects(of: graph),
            snapshots: []
        )
    }

    struct RequirementGraphCapture {
        var snapshots: [RowSnapshot] = []
        var affected: Set<SubjectRef> = []
    }

    /// Everything a requirement delete must snapshot: the row, its scene links, its basis
    /// rows, its dependency rows in **both** directions, and its lock rows (§4.3).
    static func captureGraph(
        of requirement: RequirementRow,
        in db: Database
    ) throws -> RequirementGraphCapture {
        var capture = RequirementGraphCapture()
        var collector = SnapshotCollector()
        let id = requirement.id
        capture.affected.insert(requirement.ref)
        try collector.capture(table: "asset_requirements", id: id, in: db)

        func dependents(
            _ table: String,
            kind: SubjectKind,
            sql: String,
            arguments: StatementArguments
        ) throws {
            for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
                collector.add(table: table, row: row)
                capture.affected.insert(SubjectRef(kind: kind, id: try UUID.required(row["id"])))
            }
        }

        try dependents(
            "asset_requirement_scenes", kind: .requirementScene,
            sql: "SELECT * FROM asset_requirement_scenes WHERE requirement_id = ? ORDER BY id",
            arguments: [id.uuidString]
        )
        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM scene_reference_exclusions WHERE requirement_id = ? ORDER BY id",
            arguments: [id.uuidString]
        ) {
            collector.add(table: "scene_reference_exclusions", row: row)
        }
        try dependents(
            "asset_requirement_basis", kind: .basis,
            sql: "SELECT * FROM asset_requirement_basis WHERE requirement_id = ? ORDER BY id",
            arguments: [id.uuidString]
        )
        try dependents(
            "asset_dependencies", kind: .dependency,
            sql: """
                SELECT * FROM asset_dependencies
                WHERE requirement_id = ? OR depends_on_requirement_id = ? ORDER BY id
                """,
            arguments: [id.uuidString, id.uuidString]
        )

        // PHASE3_DESIGN §7.3 / §4.3's symmetric rule (Plan 014): the prompt graph rides
        // with the row, every version stamped by its prompts is captured wherever it now
        // lives (a combine may have moved it under another requirement's asset), and every
        // **other** prompt's citation naming this requirement goes too — the cascade would
        // SET NULL those columns silently.
        try dependents(
            "asset_prompts", kind: .prompt,
            sql: "SELECT * FROM asset_prompts WHERE requirement_id = ? ORDER BY id",
            arguments: [id.uuidString]
        )
        let promptIDs = collector.snapshots
            .filter { $0.table == "asset_prompts" }
            .compactMap { snapshot -> UUID? in
                guard case let .string(raw)? = snapshot.columns["id"] else { return nil }
                return UUID(uuidString: raw)
            }
        if !promptIDs.isEmpty {
            try dependents(
                "asset_versions", kind: .version,
                sql: """
                    SELECT asset_versions.* FROM asset_versions
                    JOIN asset_prompts ON asset_prompts.id = asset_versions.prompt_id
                    WHERE asset_prompts.requirement_id = ? ORDER BY asset_versions.id
                    """,
                arguments: [id.uuidString]
            )
        }
        try dependents(
            "asset_prompt_references", kind: .promptReference,
            sql: """
                SELECT DISTINCT asset_prompt_references.* FROM asset_prompt_references
                JOIN asset_prompts ON asset_prompts.id = asset_prompt_references.prompt_id
                WHERE asset_prompts.requirement_id = ?
                   OR asset_prompt_references.requirement_id = ?
                ORDER BY asset_prompt_references.id
                """,
            arguments: [id.uuidString, id.uuidString]
        )
        try collector.captureLocks(subject: requirement.ref, in: db)
        capture.snapshots = collector.snapshots
        return capture
    }
}

// MARK: - The tombstone and the recompute (§7.2, §6.3)

extension RequirementOperations {
    /// §7.2's `rejectRequirement`: the tombstone, plus §6.3's recompute of any existing
    /// asset to `deprecated` in the same group.
    static func reject(
        id: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, redo: { row in
                .unrejectRequirement(id: id, priorState: row.reviewState)
            }, in: db)
        }
        let requirement = try require(id: id, in: db)
        try ProtectionPolicy.checkFactEdit(
            ref: requirement.ref, source: requirement.source,
            reviewState: requirement.reviewState, actor: actor, in: db
        )
        return try rejectRow(requirement, actor: actor, mode: mode, in: db)
    }

    /// The write half of `reject`, shared with `delete`'s tombstone routing.
    private static func rejectRow(
        _ requirement: RequirementRow,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        var collector = SnapshotCollector()
        try collector.capture(table: "asset_requirements", id: requirement.id, in: db)
        try setReviewState(.rejected, of: requirement.id, actor: actor, in: db)
        let applied = try AssetStatusRecompute.recompute(
            requirementID: requirement.id,
            reviewState: .rejected,
            necessity: requirement.necessity,
            in: db
        )
        collector.add(contentsOf: applied.snapshots)
        return MutationEffect(
            inverse: .unrejectRequirement(id: requirement.id, priorState: requirement.reviewState),
            affected: Set([requirement.ref]).union(applied.affected),
            snapshots: collector.snapshots
        )
    }

    /// §7.2's `unrejectRequirement`. The recompute checks **both** of §6.3 rule 1's causes,
    /// so un-rejecting a requirement that is still `not_needed` leaves its asset
    /// `deprecated` — and `rejected_explicitly`, which deprecation never touched, decides
    /// rule 3 when the slot does come back.
    static func unreject(
        id: UUID,
        priorState: ReviewState?,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, redo: { _ in
                .rejectRequirement(id: id)
            }, in: db)
        }
        let requirement = try require(id: id, in: db)
        try ProtectionPolicy.checkFactEdit(
            ref: requirement.ref, source: requirement.source,
            reviewState: requirement.reviewState, actor: actor, in: db
        )
        let restored = priorState ?? (requirement.createdSource == .parser ? .accepted : .proposed)

        var collector = SnapshotCollector()
        try collector.capture(table: "asset_requirements", id: id, in: db)
        try setReviewState(restored, of: id, actor: actor, in: db)
        let applied = try AssetStatusRecompute.recompute(
            requirementID: id,
            reviewState: restored,
            necessity: requirement.necessity,
            in: db
        )
        collector.add(contentsOf: applied.snapshots)
        return MutationEffect(
            inverse: .rejectRequirement(id: id),
            affected: Set([requirement.ref]).union(applied.affected),
            snapshots: collector.snapshots
        )
    }

    static func setReviewState(
        _ state: ReviewState,
        of id: UUID,
        actor: MutationActor,
        in db: Database
    ) throws {
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                UPDATE asset_requirements
                SET review_state = ?, reviewed_at = COALESCE(?, reviewed_at), updated_at = ?
                WHERE id = ?
                """,
            arguments: [
                state.rawValue, actor == .human ? timestamp : nil, timestamp, id.uuidString,
            ]
        )
    }
}

// MARK: - Scalar field edits (§7.2)

extension RequirementOperations {
    /// §7.2's rename: re-checks `UNIQUE(entity_id, name_normalized)` and rewrites
    /// `name_normalized` through `EntityNormalization`.
    static func rename(
        id: UUID,
        to name: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, redo: { row in
                .renameRequirement(id: id, name: row.name)
            }, in: db)
        }
        let requirement = try require(id: id, in: db)
        // A `parser`-sourced canonical row's `name` is parser-owned (§3.7): AI may never
        // rename one, and a name lock stops either actor.
        try ProtectionPolicy.checkFactEdit(
            ref: requirement.ref, source: requirement.source,
            reviewState: requirement.reviewState, field: .name, actor: actor, in: db
        )
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.invalidName(reason: "A name cannot be empty.")
        }
        let normalized = EntityNormalization.normalize(trimmed)
        if let conflicting = try conflictingRequirementID(
            entityID: requirement.entityID, normalized: normalized, excluding: id, in: db
        ) {
            throw ProjectStoreError.requirementNameConflict(existingRequirementID: conflicting)
        }
        return try updateColumns(
            requirement,
            assignments: "name = ?, name_normalized = ?",
            values: [trimmed, normalized],
            actor: actor,
            inverse: .renameRequirement(id: id, name: requirement.name),
            in: db
        )
    }

    static func setReason(
        id: UUID,
        text: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, redo: { row in
                .setRequirementReason(id: id, text: row.reason)
            }, in: db)
        }
        let requirement = try require(id: id, in: db)
        try ProtectionPolicy.checkFactEdit(
            ref: requirement.ref, source: requirement.source,
            reviewState: requirement.reviewState, field: .reason, actor: actor, in: db
        )
        return try updateColumns(
            requirement,
            assignments: "reason = ?",
            values: [text],
            actor: actor,
            inverse: .setRequirementReason(id: id, text: requirement.reason),
            in: db
        )
    }

    /// §7.2's necessity edit — human-only (§7.1: the AI actor never touches necessity) —
    /// with §6.3's recompute of any existing asset in the same group.
    static func setNecessity(
        id: UUID,
        necessity: RequirementNecessity,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertScalar(id: id, entry: entry, redo: { row in
                .setRequirementNecessity(id: id, necessity: row.necessity)
            }, in: db)
        }
        let requirement = try require(id: id, in: db)
        try requireHuman(actor, subject: requirement.ref)
        try ProtectionPolicy.checkFactEdit(
            ref: requirement.ref, source: requirement.source,
            reviewState: requirement.reviewState, field: .necessity, actor: actor, in: db
        )
        var effect = try updateColumns(
            requirement,
            assignments: "necessity = ?",
            values: [necessity.rawValue],
            actor: actor,
            inverse: .setRequirementNecessity(id: id, necessity: requirement.necessity),
            in: db
        )
        let applied = try AssetStatusRecompute.recompute(
            requirementID: id,
            // A human edit lands the row `accepted` (§3.6), which the recompute must see.
            reviewState: actor == .human ? .accepted : requirement.reviewState,
            necessity: necessity,
            in: db
        )
        effect.affected.formUnion(applied.affected)
        effect.snapshots.append(contentsOf: applied.snapshots)
        return effect
    }

    /// The write shape every scalar requirement edit shares: snapshot, assign, stamp PROV.
    private static func updateColumns(
        _ requirement: RequirementRow,
        assignments: String,
        values: StatementArguments,
        actor: MutationActor,
        inverse: EditOperation,
        in db: Database
    ) throws -> MutationEffect {
        var snapshots: [RowSnapshot] = []
        if let snapshot = try RowSnapshotStore.capture(
            table: "asset_requirements", id: requirement.id, in: db
        ) {
            snapshots.append(snapshot)
        }
        var arguments = values
        arguments += EntityOperations.provenanceArguments(
            actor: actor,
            current: requirement.reviewState,
            timestamp: UTCDate.string(from: Date())
        )
        arguments += [requirement.id.uuidString]
        try db.execute(
            sql: """
                UPDATE asset_requirements
                SET \(assignments), \(EntityOperations.provenanceAssignment)
                WHERE id = ?
                """,
            arguments: arguments
        )
        return MutationEffect(inverse: inverse, affected: [requirement.ref], snapshots: snapshots)
    }

    /// §3.3's override (§7.2: human-only). The prior value is the inverse.
    static func setManifestInclusion(
        entityID: UUID,
        inclusion: ManifestInclusion,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .entity, id: entityID)
        if let entry = mode.invertedEntry {
            // The value is read **before** the restore: this operation's own inverse is the
            // redo, which must put back what the restore is about to overwrite.
            let current = try currentInclusion(of: entityID, in: db)
            let restored = try InverseApplication.restoreAffected(
                of: entry, kinds: [.entity], ownedBy: entityID, in: db
            )
            return MutationEffect(
                inverse: .setManifestInclusion(entityID: entityID, inclusion: current),
                affected: restored.affected,
                snapshots: restored.snapshots
            )
        }
        guard let entity = try EntityOperations.fetch(id: entityID, in: db) else {
            throw ProjectStoreError.entityNotFound
        }
        try requireHuman(actor, subject: ref)
        try LockPolicy.checkUnlocked(subject: ref, field: .whole, in: db)
        let prior = try currentInclusion(of: entityID, in: db)
        var snapshots: [RowSnapshot] = []
        if let snapshot = try RowSnapshotStore.capture(table: "entities", id: entityID, in: db) {
            snapshots.append(snapshot)
        }
        var arguments: StatementArguments = [inclusion.rawValue]
        arguments += EntityOperations.provenanceArguments(
            actor: actor, current: entity.reviewState, timestamp: UTCDate.string(from: Date())
        )
        arguments += [entityID.uuidString]
        try db.execute(
            sql: """
                UPDATE entities SET manifest_inclusion = ?,
                    \(EntityOperations.provenanceAssignment)
                WHERE id = ?
                """,
            arguments: arguments
        )
        return MutationEffect(
            inverse: .setManifestInclusion(entityID: entityID, inclusion: prior),
            affected: [ref],
            snapshots: snapshots
        )
    }

    static func currentInclusion(of entityID: UUID, in db: Database) throws -> ManifestInclusion {
        let raw = try String.fetchOne(
            db, sql: "SELECT manifest_inclusion FROM entities WHERE id = ?",
            arguments: [entityID.uuidString]
        )
        return ManifestInclusion(rawValue: raw ?? "") ?? .automatic
    }
}

// MARK: - Scene links (§7.2)

extension RequirementOperations {
    /// §7.2's `addRequirementScene`: **variant tier only**, and a human add whose
    /// `(requirement_id, scene_id)` matches a tombstoned row **un-rejects that row** —
    /// one journal entry, inverse = reject — instead of raw-failing the UNIQUE key.
    static func addScene(
        requirementID: UUID,
        sceneID: UUID,
        linkID: UUID?,
        restoring: [RowSnapshot],
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if !restoring.isEmpty {
            try RowGraph.restore(restoring, in: db)
            guard let id = rowID(of: "asset_requirement_scenes", in: restoring) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "That change no longer has a scene link to restore."
                )
            }
            return MutationEffect(
                inverse: .removeRequirementScene(linkID: id),
                affected: RowGraph.subjects(of: restoring)
            )
        }

        let requirement = try require(id: requirementID, in: db)
        guard requirement.tier == .variant else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "A canonical requirement's scenes come from the screenplay, so they cannot be edited."
            )
        }
        try SceneOperations.requireScene(sceneID, in: db)
        try LockPolicy.checkUnlocked(subject: requirement.ref, field: .whole, in: db)

        if let existing = try Row.fetchOne(
            db,
            sql: """
                SELECT * FROM asset_requirement_scenes
                WHERE requirement_id = ? AND scene_id = ?
                """,
            arguments: [requirementID.uuidString, sceneID.uuidString]
        ) {
            let existingID = try UUID.required(existing["id"])
            let ref = SubjectRef(kind: .requirementScene, id: existingID)
            guard ReviewState(rawValue: existing["review_state"] as String? ?? "") == .rejected else {
                throw ProjectStoreError.requirementOperationRefused(
                    reason: "That scene is already listed for this requirement."
                )
            }
            // §7.2's tombstone un-rejection: one entry, and `rejectSubject` undoes it.
            return try ReviewOperations.unreject(
                ref: ref,
                priorState: actor == .human ? .accepted : nil,
                actor: actor,
                mode: mode,
                in: db
            )
        }

        let id = linkID ?? UUID()
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO asset_requirement_scenes (
                    id, requirement_id, scene_id, source, confidence, review_state,
                    reviewed_at, job_id, created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [id.uuidString, requirementID.uuidString, sceneID.uuidString]
                + insertProvenance(actor, timestamp: timestamp)
        )
        return MutationEffect(
            inverse: .removeRequirementScene(linkID: id),
            affected: [SubjectRef(kind: .requirementScene, id: id)]
        )
    }

    /// §7.2's `removeRequirementScene`: an `ai`/`parser` row **tombstones** (Phase 1 §3.6);
    /// a `human` row, or one already rejected, is hard-deleted with its snapshot.
    static func removeScene(
        linkID: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .requirementScene, id: linkID)
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM asset_requirement_scenes WHERE id = ?",
            arguments: [linkID.uuidString]
        ) else { throw ProjectStoreError.requirementNotFound }
        let source = ContinuityOperations.source(of: row)
        let state = ContinuityOperations.reviewState(of: row)
        let requirementID = try UUID.required(row["requirement_id"])
        try LockPolicy.checkUnlocked(
            subject: SubjectRef(kind: .requirement, id: requirementID), field: .whole, in: db
        )
        try ProtectionPolicy.checkFactEdit(
            ref: ref, source: source, reviewState: state, actor: actor, in: db
        )
        guard ContinuityOperations.isHardDeletable(source: source, reviewState: state)
            || ContinuityOperations.createdByInvertedEntry(
                mode, table: "asset_requirement_scenes", id: linkID
            )
        else {
            return try ReviewOperations.reject(ref: ref, actor: actor, mode: mode, in: db)
        }
        let snapshot = RowSnapshot(table: "asset_requirement_scenes", row: row)
        try RowSnapshotStore.delete(table: "asset_requirement_scenes", id: linkID, in: db)
        return MutationEffect(
            inverse: .addRequirementScene(
                requirementID: requirementID,
                sceneID: try UUID.required(row["scene_id"]),
                linkID: linkID,
                restoring: [snapshot]
            ),
            affected: [ref],
            snapshots: [snapshot]
        )
    }

    static func rowID(of table: String, in snapshots: [RowSnapshot]) -> UUID? {
        for snapshot in snapshots where snapshot.table == table {
            guard case let .string(raw)? = snapshot.columns["id"] else { continue }
            return UUID(uuidString: raw)
        }
        return nil
    }
}

// MARK: - Scene-specific reference exclusions (v13)

extension RequirementOperations {
    static func excludeReferenceFromScene(
        sceneID: UUID,
        requirementID: UUID,
        exclusionID: UUID?,
        restoring: [RowSnapshot],
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        if restoring.isEmpty == false {
            try RowGraph.restore(restoring, in: db)
            guard let id = rowID(of: "scene_reference_exclusions", in: restoring) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "That change no longer has a scene reference to restore."
                )
            }
            return MutationEffect(
                inverse: .includeReferenceInScene(exclusionID: id),
                affected: [
                    SubjectRef(kind: .scene, id: sceneID),
                    SubjectRef(kind: .requirement, id: requirementID),
                ]
            )
        }

        let requirement = try require(id: requirementID, in: db)
        try requireHuman(actor, subject: requirement.ref)
        try SceneOperations.requireScene(sceneID, in: db)
        try LockPolicy.checkUnlocked(subject: requirement.ref, field: .whole, in: db)

        let isSceneReference = try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1
                    FROM asset_requirements requirement
                    WHERE requirement.id = ?
                      AND (
                        (requirement.tier = 'canonical' AND EXISTS(
                            SELECT 1 FROM scene_entities appearance
                            WHERE appearance.entity_id = requirement.entity_id
                              AND appearance.scene_id = ?
                              AND appearance.role IN (\(ManifestQualification.visibleRoleSQLList))
                              AND appearance.review_state <> 'rejected'
                        ))
                        OR (requirement.tier = 'variant' AND EXISTS(
                            SELECT 1 FROM asset_requirement_scenes link
                            WHERE link.requirement_id = requirement.id
                              AND link.scene_id = ?
                              AND link.review_state <> 'rejected'
                        ))
                      )
                )
                """,
            arguments: [requirementID.uuidString, sceneID.uuidString, sceneID.uuidString]
        ) ?? false
        guard isSceneReference else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "Only a reference linked to this scene can be removed here."
            )
        }

        let id = exclusionID ?? UUID()
        let alreadyExcluded = try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM scene_reference_exclusions
                    WHERE scene_id = ? AND requirement_id = ?
                )
                """,
            arguments: [sceneID.uuidString, requirementID.uuidString]
        ) ?? false
        guard alreadyExcluded == false else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "That reference has already been removed from this scene."
            )
        }
        try db.execute(
            sql: """
                INSERT INTO scene_reference_exclusions (
                    id, scene_id, requirement_id, created_at
                ) VALUES (?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString,
                sceneID.uuidString,
                requirementID.uuidString,
                UTCDate.string(from: Date()),
            ]
        )
        return MutationEffect(
            inverse: .includeReferenceInScene(exclusionID: id),
            affected: [
                SubjectRef(kind: .scene, id: sceneID),
                SubjectRef(kind: .requirement, id: requirementID),
            ]
        )
    }

    static func includeReferenceInScene(
        exclusionID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM scene_reference_exclusions WHERE id = ?",
            arguments: [exclusionID.uuidString]
        ) else { throw ProjectStoreError.requirementNotFound }
        let sceneID = try UUID.required(row["scene_id"])
        let requirementID = try UUID.required(row["requirement_id"])
        let requirement = try require(id: requirementID, in: db)
        try requireHuman(actor, subject: requirement.ref)
        try LockPolicy.checkUnlocked(subject: requirement.ref, field: .whole, in: db)
        let snapshot = RowSnapshot(table: "scene_reference_exclusions", row: row)
        try RowSnapshotStore.delete(
            table: "scene_reference_exclusions", id: exclusionID, in: db
        )
        return MutationEffect(
            inverse: .excludeReferenceFromScene(
                sceneID: sceneID,
                requirementID: requirementID,
                exclusionID: exclusionID,
                restoring: [snapshot]
            ),
            affected: [
                SubjectRef(kind: .scene, id: sceneID),
                SubjectRef(kind: .requirement, id: requirementID),
            ],
            snapshots: [snapshot]
        )
    }
}

// MARK: - Dependencies and the cycle walk (§3.5, §7.2)

extension RequirementOperations {
    /// One edge of the dependency graph.
    struct DependencyEdge {
        let id: UUID
        let from: UUID
        let to: UUID
    }

    /// Every **active** dependency edge. Rejected tombstones are not edges: they are the
    /// record of a removal, and seeding respects them without the graph doing so.
    static func activeEdges(in db: Database) throws -> [DependencyEdge] {
        try Row
            .fetchAll(
                db,
                sql: """
                    SELECT id, requirement_id, depends_on_requirement_id FROM asset_dependencies
                    WHERE review_state <> 'rejected' ORDER BY id
                    """
            )
            .map { row in
                DependencyEdge(
                    id: try UUID.required(row["id"]),
                    from: try UUID.required(row["requirement_id"]),
                    to: try UUID.required(row["depends_on_requirement_id"])
                )
            }
    }

    /// §3.5's Swift walk over the **full prospective graph**: `true` when it contains a
    /// cycle. Self-edges are refused separately, before this ever runs.
    static func hasCycle(_ edges: [(from: UUID, to: UUID)]) -> Bool {
        var adjacency: [UUID: [UUID]] = [:]
        for edge in edges { adjacency[edge.from, default: []].append(edge.to) }
        var state: [UUID: Int] = [:]   // 1 = on the stack, 2 = finished

        func visit(_ node: UUID) -> Bool {
            switch state[node] {
            case 1: return true
            case 2: return false
            default: break
            }
            state[node] = 1
            for next in adjacency[node] ?? [] where visit(next) { return true }
            state[node] = 2
            return false
        }

        for node in adjacency.keys where visit(node) { return true }
        return false
    }

    /// §7.2's `addDependency`: the cycle and self-edge walk runs **before any write**, both
    /// endpoints must be non-rejected, and a human add matching a tombstoned pair un-rejects
    /// that row — after the cycle check.
    static func addDependency(
        requirementID: UUID,
        dependsOnID: UUID,
        dependencyID: UUID?,
        restoring: [RowSnapshot],
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if !restoring.isEmpty {
            try RowGraph.restore(restoring, in: db)
            guard let id = rowID(of: "asset_dependencies", in: restoring) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "That change no longer has a dependency to restore."
                )
            }
            return MutationEffect(
                inverse: .removeDependency(id: id),
                affected: RowGraph.subjects(of: restoring)
            )
        }

        guard requirementID != dependsOnID else {
            throw ProjectStoreError.invalidFact(
                reason: "A requirement cannot depend on itself."
            )
        }
        let requirement = try require(id: requirementID, in: db)
        let target = try require(id: dependsOnID, in: db)
        guard requirement.reviewState != .rejected, target.reviewState != .rejected else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "A rejected requirement cannot take part in a dependency."
            )
        }
        try LockPolicy.checkUnlocked(subject: requirement.ref, field: .whole, in: db)

        var edges = try activeEdges(in: db).map { (from: $0.from, to: $0.to) }
        edges.append((from: requirementID, to: dependsOnID))
        guard !hasCycle(edges) else {
            throw ProjectStoreError.invalidFact(
                reason: "That dependency would make the requirements depend on each other in a loop."
            )
        }

        if let existing = try Row.fetchOne(
            db,
            sql: """
                SELECT * FROM asset_dependencies
                WHERE requirement_id = ? AND depends_on_requirement_id = ?
                """,
            arguments: [requirementID.uuidString, dependsOnID.uuidString]
        ) {
            let existingID = try UUID.required(existing["id"])
            let ref = SubjectRef(kind: .dependency, id: existingID)
            guard ReviewState(rawValue: existing["review_state"] as String? ?? "") == .rejected else {
                throw ProjectStoreError.requirementOperationRefused(
                    reason: "That dependency already exists."
                )
            }
            return try ReviewOperations.unreject(
                ref: ref,
                priorState: actor == .human ? .accepted : nil,
                actor: actor,
                mode: mode,
                in: db
            )
        }

        let id = dependencyID ?? UUID()
        try insertDependency(
            id: id,
            requirementID: requirementID,
            dependsOnID: dependsOnID,
            provenance: insertProvenance(actor, timestamp: UTCDate.string(from: Date())),
            in: db
        )
        return MutationEffect(
            inverse: .removeDependency(id: id),
            affected: [SubjectRef(kind: .dependency, id: id)]
        )
    }

    /// §7.2's `removeDependency`: removal of an `ai`/`parser` row **tombstones** it, which
    /// is what §3.5's seeding respects across refreshes and inference.
    static func removeDependency(
        id: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .dependency, id: id)
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM asset_dependencies WHERE id = ?", arguments: [id.uuidString]
        ) else { throw ProjectStoreError.requirementNotFound }
        let source = ContinuityOperations.source(of: row)
        let state = ContinuityOperations.reviewState(of: row)
        let requirementID = try UUID.required(row["requirement_id"])
        try LockPolicy.checkUnlocked(
            subject: SubjectRef(kind: .requirement, id: requirementID), field: .whole, in: db
        )
        try ProtectionPolicy.checkFactEdit(
            ref: ref, source: source, reviewState: state, actor: actor, in: db
        )
        guard ContinuityOperations.isHardDeletable(source: source, reviewState: state)
            || ContinuityOperations.createdByInvertedEntry(
                mode, table: "asset_dependencies", id: id
            )
        else {
            return try ReviewOperations.reject(ref: ref, actor: actor, mode: mode, in: db)
        }
        let snapshot = RowSnapshot(table: "asset_dependencies", row: row)
        try RowSnapshotStore.delete(table: "asset_dependencies", id: id, in: db)
        return MutationEffect(
            inverse: .addDependency(
                requirementID: requirementID,
                dependsOnID: try UUID.required(row["depends_on_requirement_id"]),
                dependencyID: id,
                restoring: [snapshot]
            ),
            affected: [ref],
            snapshots: [snapshot]
        )
    }
}

// MARK: - Preconditions for the inverses (§3.8)

extension RequirementOperations {
    static func precheckRow(id: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "asset_requirements", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That requirement is no longer in this project."
            )
        }
    }

    static func precheckCreate(
        id: UUID,
        entityID: UUID,
        name: String,
        in db: Database
    ) throws {
        guard try !RowSnapshotStore.exists(table: "asset_requirements", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change removed is already back."
            )
        }
        let normalized = EntityNormalization.normalize(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if try conflictingRequirementID(
            entityID: entityID, normalized: normalized, excluding: id, in: db
        ) != nil {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Another requirement of that item is now named “\(name)”."
            )
        }
    }

    static func precheckRename(id: UUID, name: String, in db: Database) throws {
        let requirement = try fetch(id: id, in: db)
        guard let requirement else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That requirement is no longer in this project."
            )
        }
        let normalized = EntityNormalization.normalize(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if try conflictingRequirementID(
            entityID: requirement.entityID, normalized: normalized, excluding: id, in: db
        ) != nil {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Another requirement of that item is now named “\(name)”."
            )
        }
    }

    static func precheckChildRow(table: String, id: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: table, id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change touched is no longer in this project."
            )
        }
    }

    static func precheckAddChild(table: String, id: UUID?, restoring: [RowSnapshot], in db: Database) throws {
        guard restoring.isEmpty else {
            try InverseApplication.precheckSnapshots(restoring, in: db)
            return
        }
        guard let id, try RowSnapshotStore.exists(table: table, id: id, in: db) else { return }
        throw ProjectStoreError.inverseNoLongerApplicable(
            reason: "Something that change removed is already back."
        )
    }
}

// MARK: - combineRequirements / uncombineRequirements (§7.2, fully specified there)

extension RequirementOperations {
    /// Which of two colliding requirement-child rows survives (§7.2, §7.4).
    ///
    /// **Liveness first** — an active row always survives over a `rejected` tombstone,
    /// whatever its source or review rank — then the Phase 1 protection order, then earliest
    /// `created_at`, then `id`. The protection ranking orders rows of equal liveness only.
    static func combineSurvivorFirst(_ rows: [Row]) -> [Row] {
        rows.sorted { lhs, rhs in
            let lhsLive = isLive(lhs), rhsLive = isLive(rhs)
            if lhsLive != rhsLive { return lhsLive }
            let lhsRank = ProtectionRank.rank(of: lhs), rhsRank = ProtectionRank.rank(of: rhs)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            let lhsCreated = lhs["created_at"] as String? ?? ""
            let rhsCreated = rhs["created_at"] as String? ?? ""
            if lhsCreated != rhsCreated { return lhsCreated < rhsCreated }
            return (lhs["id"] as String? ?? "") < (rhs["id"] as String? ?? "")
        }
    }

    static func isLive(_ row: Row) -> Bool {
        (row["review_state"] as String? ?? "") != ReviewState.rejected.rawValue
    }

    /// §7.2's `combineRequirements`, in the order the spec fixes: validate, walk the whole
    /// prospective dependency graph for cycles, move the graph, merge the assets, recompute
    /// once, tombstone the sources.
    ///
    /// Sources may belong to a **different entity** than the target: the combined
    /// requirement lives on the target's entity, and moved scene links reference scenes, so
    /// they carry over unchanged. A tombstoned source stays on its own entity.
    static func combine(
        sourceIDs: [UUID],
        into targetID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        // 1. Validation, all of it before the first write.
        var seen: Set<UUID> = []
        let sources = sourceIDs.filter { seen.insert($0).inserted }
        guard !sources.isEmpty else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "Choose at least one requirement to combine."
            )
        }
        guard !sources.contains(targetID) else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "The requirement you are combining into cannot also be a source."
            )
        }
        let target = try require(id: targetID, in: db)
        // Human-only, like `splitRequirement`. §7.1's write surface does not list combining
        // among the things the `.ai` actor may do, and combining edits — retargets and
        // drops — dependency rows the run did not create, which the same paragraph forbids
        // outright. §7.2 gates it only by the lock rule, so the actor gate is stated here.
        try requireHuman(actor, subject: target.ref)
        var sourceRows: [RequirementRow] = []
        for id in sources { sourceRows.append(try require(id: id, in: db)) }
        // **All participants must be variant-tier.** A canonical requirement's scene links
        // are derived, so a variant's stored links moved onto one would be stranded rows.
        for row in [target] + sourceRows where row.tier != .variant {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "Only variant requirements can be combined."
            )
        }
        // §7.5: any lock on any participant blocks the combine, for both actors.
        for row in [target] + sourceRows {
            try LockPolicy.checkFree(subject: row.ref, in: db)
        }

        // 2. The full prospective dependency graph, re-checked for cycles before any write.
        let sourceSet = Set(sources)
        func retarget(_ id: UUID) -> UUID { sourceSet.contains(id) ? targetID : id }
        var prospective: [(from: UUID, to: UUID)] = []
        var pairs: Set<String> = []
        for edge in try activeEdges(in: db) {
            let from = retarget(edge.from), to = retarget(edge.to)
            guard from != to else { continue }
            guard pairs.insert("\(from.uuidString)/\(to.uuidString)").inserted else { continue }
            prospective.append((from, to))
        }
        guard !hasCycle(prospective) else {
            throw ProjectStoreError.invalidFact(
                reason: "Combining those requirements would make them depend on each other in a loop."
            )
        }

        let timestamp = UTCDate.string(from: Date())
        var collector = SnapshotCollector()
        var affected: Set<SubjectRef> = [target.ref]
        var moved: [SubjectRef] = []
        var removed: [SubjectRef] = []

        func drop(table: String, ref: SubjectRef) throws {
            removed.append(ref)
            try RowSnapshotStore.delete(table: table, id: ref.id, in: db)
        }

        // 3. Scene links and 4. basis rows: the same move-or-collide shape over two uniques.
        for source in sourceRows {
            for row in try Row.fetchAll(
                db,
                sql: "SELECT * FROM asset_requirement_scenes WHERE requirement_id = ? ORDER BY id",
                arguments: [source.id.uuidString]
            ) {
                let id = try UUID.required(row["id"])
                let ref = SubjectRef(kind: .requirementScene, id: id)
                collector.add(table: "asset_requirement_scenes", row: row)
                affected.insert(ref)
                let sceneID: String = row["scene_id"]
                guard let rival = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT * FROM asset_requirement_scenes
                        WHERE requirement_id = ? AND scene_id = ?
                        """,
                    arguments: [targetID.uuidString, sceneID]
                ) else {
                    try db.execute(
                        sql: """
                            UPDATE asset_requirement_scenes
                            SET requirement_id = ?, updated_at = ? WHERE id = ?
                            """,
                        arguments: [targetID.uuidString, timestamp, id.uuidString]
                    )
                    moved.append(ref)
                    continue
                }
                let rivalID = try UUID.required(rival["id"])
                collector.add(table: "asset_requirement_scenes", row: rival)
                affected.insert(SubjectRef(kind: .requirementScene, id: rivalID))
                let ordered = combineSurvivorFirst([row, rival])
                let survivorID = try UUID.required(ordered[0]["id"])
                let loserID = try UUID.required(ordered[1]["id"])
                try drop(
                    table: "asset_requirement_scenes",
                    ref: SubjectRef(kind: .requirementScene, id: loserID)
                )
                if survivorID == id {
                    try db.execute(
                        sql: """
                            UPDATE asset_requirement_scenes
                            SET requirement_id = ?, updated_at = ? WHERE id = ?
                            """,
                        arguments: [targetID.uuidString, timestamp, id.uuidString]
                    )
                    moved.append(ref)
                }
            }

            for row in try Row.fetchAll(
                db,
                sql: "SELECT * FROM asset_requirement_basis WHERE requirement_id = ? ORDER BY id",
                arguments: [source.id.uuidString]
            ) {
                let id = try UUID.required(row["id"])
                let ref = SubjectRef(kind: .basis, id: id)
                collector.add(table: "asset_requirement_basis", row: row)
                affected.insert(ref)
                let subjectKind: String = row["subject_kind"]
                let subjectID: String = row["subject_id"]
                guard let rival = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT * FROM asset_requirement_basis
                        WHERE requirement_id = ? AND subject_kind = ? AND subject_id = ?
                        """,
                    arguments: [targetID.uuidString, subjectKind, subjectID]
                ) else {
                    try db.execute(
                        sql: "UPDATE asset_requirement_basis SET requirement_id = ? WHERE id = ?",
                        arguments: [targetID.uuidString, id.uuidString]
                    )
                    moved.append(ref)
                    continue
                }
                // A basis row is an immutable citation with reduced provenance (§3.7), so
                // "liveness" and the review rank do not apply: the target's existing
                // citation is kept and the duplicate is dropped, earliest `created_at`
                // first, then `id` — the tail of the same total order.
                let rivalID = try UUID.required(rival["id"])
                collector.add(table: "asset_requirement_basis", row: rival)
                affected.insert(SubjectRef(kind: .basis, id: rivalID))
                let mineCreated: String = row["created_at"]
                let rivalCreated: String = rival["created_at"]
                let mineWins = mineCreated != rivalCreated
                    ? mineCreated < rivalCreated
                    : id.uuidString < rivalID.uuidString
                if mineWins {
                    try drop(table: "asset_requirement_basis", ref: SubjectRef(kind: .basis, id: rivalID))
                    try db.execute(
                        sql: "UPDATE asset_requirement_basis SET requirement_id = ? WHERE id = ?",
                        arguments: [targetID.uuidString, id.uuidString]
                    )
                    moved.append(ref)
                } else {
                    try drop(table: "asset_requirement_basis", ref: ref)
                }
            }
        }

        // 5. Dependencies: retargeted, self-edges removed, duplicates dropped.
        for candidate in try Row.fetchAll(
            db,
            sql: """
                SELECT id FROM asset_dependencies
                WHERE requirement_id IN \(EntityOperations.inClause(sources))
                   OR depends_on_requirement_id IN \(EntityOperations.inClause(sources))
                ORDER BY id
                """,
            arguments: StatementArguments(sources.map(\.uuidString))
                + StatementArguments(sources.map(\.uuidString))
        ) {
            let id = try UUID.required(candidate["id"])
            // A row an earlier iteration already dropped is no longer this row.
            guard let row = try Row.fetchOne(
                db, sql: "SELECT * FROM asset_dependencies WHERE id = ?", arguments: [id.uuidString]
            ) else { continue }
            let ref = SubjectRef(kind: .dependency, id: id)
            collector.add(table: "asset_dependencies", row: row)
            affected.insert(ref)
            let from = retarget(try UUID.required(row["requirement_id"]))
            let to = retarget(try UUID.required(row["depends_on_requirement_id"]))
            guard from != to else {
                try drop(table: "asset_dependencies", ref: ref)
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
                let ordered = combineSurvivorFirst([row, rival])
                let survivorID = try UUID.required(ordered[0]["id"])
                let loserID = try UUID.required(ordered[1]["id"])
                try drop(table: "asset_dependencies", ref: SubjectRef(kind: .dependency, id: loserID))
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

        // 6. Assets merge, with §7.2's total survivor rule.
        var neutralizeVersionIDs: [UUID] = []
        let participantAssets = try assetRows(of: [targetID] + sources, in: db)
        if !participantAssets.isEmpty {
            let survivor = try surviving(assetRows: participantAssets, targetID: targetID, in: db)
            let survivorID = try UUID.required(survivor["id"])
            collector.add(table: "assets", row: survivor)
            affected.insert(SubjectRef(kind: .asset, id: survivorID))
            // The survivor's own approved version, snapshotted so the hand-ordered inverse
            // can demote it first and still put it back (§7.2, §7.3).
            for row in try Row.fetchAll(
                db,
                sql: "SELECT * FROM asset_versions WHERE asset_id = ? AND status = 'approved'",
                arguments: [survivorID.uuidString]
            ) {
                let versionID = try UUID.required(row["id"])
                collector.add(table: "asset_versions", row: row)
                affected.insert(SubjectRef(kind: .version, id: versionID))
                neutralizeVersionIDs.append(versionID)
            }

            var nextVersion = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(version_number), 0) FROM asset_versions WHERE asset_id = ?",
                arguments: [survivorID.uuidString]
            ) ?? 0
            // Losers in **source-requirement order**, then version-number order.
            for loser in participantAssets where try UUID.required(loser["id"]) != survivorID {
                let loserID = try UUID.required(loser["id"])
                for version in try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM asset_versions WHERE asset_id = ? ORDER BY version_number, id",
                    arguments: [loserID.uuidString]
                ) {
                    let versionID = try UUID.required(version["id"])
                    let ref = SubjectRef(kind: .version, id: versionID)
                    collector.add(table: "asset_versions", row: version)
                    affected.insert(ref)
                    moved.append(ref)
                    nextVersion += 1
                    // At most one approved version survives, and it is the survivor's own;
                    // files never move, so `relative_path` is untouched and a `v3.png`
                    // filename no longer implies `version_number = 3` (§4.1).
                    let status = (version["status"] as String? ?? "") == "approved"
                        ? AssetVersionStatus.needsReview.rawValue
                        : (version["status"] as String? ?? "")
                    try db.execute(
                        sql: """
                            UPDATE asset_versions
                            SET asset_id = ?, version_number = ?, status = ?, updated_at = ?
                            WHERE id = ?
                            """,
                        arguments: [
                            survivorID.uuidString, nextVersion, status, timestamp,
                            versionID.uuidString,
                        ]
                    )
                }
                collector.add(table: "assets", row: loser)
                // The loser's staleness flags and `rejected_explicitly` are discarded with
                // its row, snapshotted in the payload; the survivor keeps its own.
                try drop(table: "assets", ref: SubjectRef(kind: .asset, id: loserID))
            }

            if try UUID.required(survivor["requirement_id"]) != targetID {
                try db.execute(
                    sql: "UPDATE assets SET requirement_id = ?, updated_at = ? WHERE id = ?",
                    arguments: [targetID.uuidString, timestamp, survivorID.uuidString]
                )
                moved.append(SubjectRef(kind: .asset, id: survivorID))
            }

            // PHASE3_DESIGN §6.1's third exclusion leg: when the combine moves version
            // rows under the surviving asset, its `in_progress_since` is cleared — a
            // marked empty slot absorbing a filled one must not hide a marker under rule 4
            // and resurface it as `in_progress` after the last `deleteVersion`. The
            // survivor row was snapshotted above, so the hand-ordered inverse restores it.
            try db.execute(
                sql: "UPDATE assets SET in_progress_since = NULL WHERE id = ?",
                arguments: [survivorID.uuidString]
            )

            // 7. Status recomputed **once**, at the end (§6.3).
            let applied = try AssetStatusRecompute.recompute(
                requirementID: targetID,
                reviewState: target.reviewState,
                necessity: target.necessity,
                in: db
            )
            collector.add(contentsOf: applied.snapshots)
            affected.formUnion(applied.affected)
        }

        // 8. Sources are tombstoned, not deleted, with their emptied graphs snapshotted.
        for source in sourceRows {
            try collector.capture(table: "asset_requirements", id: source.id, in: db)
            try setReviewState(.rejected, of: source.id, actor: actor, in: db)
            affected.insert(source.ref)
        }

        let payload = RequirementCombinePayload(
            target: targetID,
            sourceIDs: sources,
            moved: moved,
            removed: removed,
            neutralizeVersionIDs: neutralizeVersionIDs,
            snapshots: collector.snapshots
        )
        return MutationEffect(
            inverse: .uncombineRequirements(payload: payload),
            affected: affected,
            snapshots: collector.snapshots
        )
    }

    /// The `assets` rows of these requirements, in the order the requirements were given —
    /// which is the target first, then source-requirement order (§7.2's renumbering order).
    private static func assetRows(of requirementIDs: [UUID], in db: Database) throws -> [Row] {
        var rows: [Row] = []
        for id in requirementIDs {
            if let row = try Row.fetchOne(
                db, sql: "SELECT * FROM assets WHERE requirement_id = ?", arguments: [id.uuidString]
            ) {
                rows.append(row)
            }
        }
        return rows
    }

    /// §7.2's total survivor rule: the target's own asset when it has one; otherwise the
    /// participant asset preferred by (holds an approved version) first, then earliest
    /// `created_at`, then `id`.
    private static func surviving(
        assetRows rows: [Row],
        targetID: UUID,
        in db: Database
    ) throws -> Row {
        for row in rows where try UUID.required(row["requirement_id"]) == targetID { return row }
        var best: (row: Row, approved: Bool, created: String, id: String)?
        for row in rows {
            let id = row["id"] as String? ?? ""
            let approved = try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM asset_versions WHERE asset_id = ? AND status = 'approved'
                    )
                    """,
                arguments: [id]
            ) ?? false
            let created = row["created_at"] as String? ?? ""
            guard let current = best else {
                best = (row, approved, created, id)
                continue
            }
            let wins: Bool = if approved != current.approved {
                approved
            } else if created != current.created {
                created < current.created
            } else {
                id < current.id
            }
            if wins { best = (row, approved, created, id) }
        }
        // `rows` is non-empty at every call site.
        return best!.row
    }

    /// `combineRequirements`' payload-driven, **hand-ordered** inverse (§7.2).
    static func uncombine(
        payload: RequirementCombinePayload,
        in db: Database
    ) throws -> MutationEffect {
        // Demote first: the partial unique index is enforced per statement and the snapshot
        // store's collision precheck cannot see a `WHERE status = 'approved'` predicate
        // (§7.3), so no approved row is ever restored while another still stands. Every id
        // here is snapshotted below, so the demotion is undone by the restore.
        for id in payload.neutralizeVersionIDs {
            try db.execute(
                sql: "UPDATE asset_versions SET status = ? WHERE id = ?",
                arguments: [AssetVersionStatus.needsReview.rawValue, id.uuidString]
            )
        }
        try RowGraph.restore(payload.snapshots, in: db)

        var affected = RowGraph.subjects(of: payload.snapshots)
        affected.formUnion(payload.moved)
        affected.formUnion(payload.removed)
        affected.insert(SubjectRef(kind: .requirement, id: payload.target))
        for id in payload.sourceIDs { affected.insert(SubjectRef(kind: .requirement, id: id)) }
        return MutationEffect(
            inverse: .combineRequirements(sourceIDs: payload.sourceIDs, into: payload.target),
            affected: affected,
            snapshots: []
        )
    }
}

// MARK: - splitRequirement / unsplitRequirement (§7.2)

extension RequirementOperations {
    /// §7.2's split. Human-only, exactly as `splitEntity` is: §8.4 never splits, so an
    /// `.ai` attempt is a protected-fact refusal rather than a combine in reverse.
    static func split(
        id: UUID,
        sceneIDs: [UUID],
        newName: String,
        newID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        let source = try require(id: id, in: db)
        try requireHuman(actor, subject: source.ref)
        guard source.tier == .variant else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "Only variant requirements can be split."
            )
        }
        // §7.5: a lock on the requirement blocks the split for both actors.
        try LockPolicy.checkFree(subject: source.ref, in: db)

        let linkRows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM asset_requirement_scenes WHERE requirement_id = ? ORDER BY id",
            arguments: [id.uuidString]
        )
        var storedScenes: [UUID] = []
        for row in linkRows { storedScenes.append(try UUID.required(row["scene_id"])) }
        let stored = Set(storedScenes)
        var uniqueMoving: Set<UUID> = []
        let movingList = sceneIDs.filter { uniqueMoving.insert($0).inserted }
        let moving = Set(movingList)
        // A **nonempty proper subset**: moving everything is a rename, not a split.
        guard !moving.isEmpty, moving.isSubset(of: stored), moving.count < stored.count else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "Choose some — but not all — of this requirement's scenes to split out."
            )
        }
        let remainder = stored.subtracting(moving)

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.invalidName(reason: "A name cannot be empty.")
        }
        let normalized = EntityNormalization.normalize(trimmed)
        if let conflicting = try conflictingRequirementID(
            entityID: source.entityID, normalized: normalized, excluding: newID, in: db
        ) {
            throw ProjectStoreError.requirementNameConflict(existingRequirementID: conflicting)
        }
        guard try !RowSnapshotStore.exists(table: "asset_requirements", id: newID, in: db) else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "That requirement id is already in this project."
            )
        }

        let timestamp = UTCDate.string(from: Date())
        var collector = SnapshotCollector()
        var affected: Set<SubjectRef> = [source.ref, SubjectRef(kind: .requirement, id: newID)]
        var moved: [SubjectRef] = []
        var created: [SubjectRef] = [SubjectRef(kind: .requirement, id: newID)]

        // The split-off requirement is born **empty**: the source keeps its asset (§7.2).
        try insertRequirement(
            id: newID,
            projectID: source.projectID,
            entityID: source.entityID,
            tier: .variant,
            typeID: nil,
            name: trimmed,
            normalized: normalized,
            reason: source.reason,
            necessity: source.necessity,
            provenance: insertProvenance(actor, timestamp: timestamp),
            in: db
        )

        for row in linkRows {
            let sceneID = try UUID.required(row["scene_id"])
            guard moving.contains(sceneID) else { continue }
            let linkID = try UUID.required(row["id"])
            let ref = SubjectRef(kind: .requirementScene, id: linkID)
            collector.add(table: "asset_requirement_scenes", row: row)
            affected.insert(ref)
            moved.append(ref)
            try db.execute(
                sql: """
                    UPDATE asset_requirement_scenes
                    SET requirement_id = ?, updated_at = ? WHERE id = ?
                    """,
                arguments: [newID.uuidString, timestamp, linkID.uuidString]
            )
        }

        // §7.2's pinned basis assignment, through the cited fact's **scene footprint**.
        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM asset_requirement_basis WHERE requirement_id = ? ORDER BY id",
            arguments: [id.uuidString]
        ) {
            let basisID = try UUID.required(row["id"])
            let ref = SubjectRef(kind: .basis, id: basisID)
            let footprint = try sceneFootprint(of: row, requirementScenes: stored, in: db)
            let inMoved = !footprint.isDisjoint(with: moving)
            let inRemainder = !footprint.isDisjoint(with: remainder)

            if inMoved, !inRemainder {
                collector.add(table: "asset_requirement_basis", row: row)
                affected.insert(ref)
                moved.append(ref)
                try db.execute(
                    sql: "UPDATE asset_requirement_basis SET requirement_id = ? WHERE id = ?",
                    arguments: [newID.uuidString, basisID.uuidString]
                )
            } else if inMoved, inRemainder {
                // Overlapping both: the row **stays** and a copy is created for the new
                // requirement — legal because basis uniqueness is per requirement, and
                // correct because a citation is not a resource that must live on one side.
                let copyID = UUID()
                try db.execute(
                    sql: """
                        INSERT INTO asset_requirement_basis (
                            id, requirement_id, subject_kind, subject_id, source, job_id, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        copyID.uuidString, newID.uuidString, row["subject_kind"] as String,
                        row["subject_id"] as String, row["source"] as String,
                        row["job_id"] as String?, timestamp,
                    ]
                )
                let copyRef = SubjectRef(kind: .basis, id: copyID)
                created.append(copyRef)
                affected.insert(copyRef)
                affected.insert(ref)
            }
            // Entirely in the remainder, or empty against both sets — an event outside every
            // linked scene, legitimately citing a variant it precedes — stays with the source.
        }

        // §3.5's deterministic seeding for the new variant, tombstones respected.
        for canonicalID in try seedTargets(entityID: source.entityID, tier: .canonical, in: db) {
            guard try !dependencyExists(from: newID, to: canonicalID, in: db) else { continue }
            let dependencyID = UUID()
            try insertDependency(
                id: dependencyID,
                requirementID: newID,
                dependsOnID: canonicalID,
                provenance: insertProvenance(actor, timestamp: timestamp),
                in: db
            )
            let ref = SubjectRef(kind: .dependency, id: dependencyID)
            created.append(ref)
            affected.insert(ref)
        }

        let payload = RequirementSplitPayload(
            sourceID: id,
            newID: newID,
            newName: trimmed,
            sceneIDs: movingList,
            created: created,
            moved: moved,
            snapshots: collector.snapshots
        )
        return MutationEffect(
            inverse: .unsplitRequirement(payload: payload),
            affected: affected,
            snapshots: collector.snapshots
        )
    }

    /// The scenes a basis row's cited fact covers (§7.2): an appearance's scene, an event's
    /// scene, and a state's scene **range intersected with the requirement's scenes**.
    static func sceneFootprint(
        of row: Row,
        requirementScenes: Set<UUID>,
        in db: Database
    ) throws -> Set<UUID> {
        let subjectID = try UUID.required(row["subject_id"])
        switch SubjectKind(rawValue: row["subject_kind"] as String? ?? "") {
        case .appearance:
            guard let raw = try String.fetchOne(
                db, sql: "SELECT scene_id FROM scene_entities WHERE id = ?",
                arguments: [subjectID.uuidString]
            ) else { return [] }
            return [try UUID.required(raw)]
        case .event:
            guard let raw = try String.fetchOne(
                db, sql: "SELECT scene_id FROM continuity_events WHERE id = ?",
                arguments: [subjectID.uuidString]
            ) else { return [] }
            return [try UUID.required(raw)]
        case .state:
            guard let stateRow = try Row.fetchOne(
                db, sql: "SELECT start_scene_id, end_scene_id FROM entity_states WHERE id = ?",
                arguments: [subjectID.uuidString]
            ) else { return [] }
            let startID = try UUID.required(stateRow["start_scene_id"])
            guard let start = try SceneOperations.ordinal(ofScene: startID, in: db) else { return [] }
            let endID = try (stateRow["end_scene_id"] as String?).map(UUID.required)
            let end = try endID.flatMap { try SceneOperations.ordinal(ofScene: $0, in: db) }
            var covered: Set<UUID> = []
            for sceneID in requirementScenes {
                guard let ordinal = try SceneOperations.ordinal(ofScene: sceneID, in: db) else { continue }
                guard ordinal >= start else { continue }
                if let end, ordinal > end { continue }
                covered.insert(sceneID)
            }
            return covered
        default:
            return []
        }
    }

    /// `splitRequirement`'s payload-driven inverse: every created row deleted, copies
    /// included, and every moved row back byte-identically. Nothing is guessed at undo time.
    static func unsplit(
        payload: RequirementSplitPayload,
        in db: Database
    ) throws -> MutationEffect {
        // The rows go back **before** the new requirement goes away: deleting it first
        // would cascade the very rows this inverse means to return.
        try RowGraph.restore(payload.snapshots, in: db)
        let removedLocks = try RowGraph.delete(payload.created, in: db)

        var affected = RowGraph.subjects(of: payload.snapshots)
        affected.formUnion(payload.created)
        affected.formUnion(payload.moved)
        affected.insert(SubjectRef(kind: .requirement, id: payload.sourceID))
        return MutationEffect(
            inverse: .splitRequirement(
                id: payload.sourceID,
                sceneIDs: payload.sceneIDs,
                newName: payload.newName,
                newID: payload.newID
            ),
            affected: affected,
            snapshots: removedLocks
        )
    }

    // MARK: - Preconditions (§3.8)

    static func precheckCombine(sourceIDs: [UUID], into targetID: UUID, in db: Database) throws {
        for id in sourceIDs + [targetID] {
            guard try RowSnapshotStore.exists(table: "asset_requirements", id: id, in: db) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "One of the requirements that change touched is no longer in this project."
                )
            }
        }
    }

    static func precheckSplit(payload: RequirementSplitPayload, in db: Database) throws {
        for ref in payload.created {
            guard let table = RowSnapshotStore.table(for: ref.kind) else { continue }
            guard try RowSnapshotStore.exists(table: table, id: ref.id, in: db) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "Something that change added is already gone."
                )
            }
        }
        try InverseApplication.precheckSnapshots(payload.snapshots, in: db)
    }

    static func precheckSplitApply(id: UUID, newID: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "asset_requirements", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That requirement is no longer in this project."
            )
        }
        guard try !RowSnapshotStore.exists(table: "asset_requirements", id: newID, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change removed is already back."
            )
        }
    }
}

// MARK: - refreshCanonicalRequirements (§5.2's Build)

extension RequirementOperations {
    /// What one Build would do, decided **before** `performGroup` is invoked.
    ///
    /// The guard has to live here rather than inside the group: `performGroup` always
    /// journals when it runs, so an idempotent no-op Build must skip it entirely and return
    /// `entry: nil` (§5.2).
    struct ManifestBuildPlan {
        var children: [EditOperation] = []
        var collisions: [ManifestBuildResult.Collision] = []
    }

    /// §5.2, in order: every eligible entity (§3.3, props only under `'always'`), every
    /// **enabled** template entry for its kind, skip a filled `(entity_id, type_id)` slot —
    /// a tombstoned one included — and count a `UNIQUE(entity_id, name_normalized)` clash as
    /// a skip rather than a throw.
    static func buildPlan(in db: Database) throws -> ManifestBuildPlan {
        var plan = ManifestBuildPlan()

        // §3.3's visible-role scene count, its `IN (…)` list generated from
        // `ManifestQualification.visibleRoles` so the SQL cannot drift from the Swift set.
        var visibleSceneCounts: [UUID: Int] = [:]
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT entity_id, COUNT(DISTINCT scene_id) AS scene_count
                FROM scene_entities
                WHERE role IN (\(ManifestQualification.visibleRoleSQLList))
                  AND review_state <> 'rejected'
                GROUP BY entity_id
                """
        ) {
            visibleSceneCounts[try UUID.required(row["entity_id"])] = row["scene_count"]
        }

        struct TemplateEntry {
            let id: UUID
            let code: String
            let displayName: String
        }
        var entriesByKind: [EntityKind: [TemplateEntry]] = [:]
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM asset_requirement_types
                WHERE is_enabled = 1 ORDER BY entity_kind, sort_order, code
                """
        ) {
            guard let kind = EntityKind(rawValue: row["entity_kind"]) else { continue }
            entriesByKind[kind, default: []].append(
                TemplateEntry(
                    id: try UUID.required(row["id"]),
                    code: row["code"],
                    displayName: row["display_name"]
                )
            )
        }

        for row in try Row.fetchAll(db, sql: "SELECT * FROM entities ORDER BY id") {
            guard let kind = EntityKind(rawValue: row["kind"]),
                  let reviewState = ReviewState(rawValue: row["review_state"]),
                  let inclusion = ManifestInclusion(rawValue: row["manifest_inclusion"])
            else { continue }
            let entityID = try UUID.required(row["id"])
            let facts = ManifestQualification.EntityFacts(
                kind: kind,
                reviewState: reviewState,
                isRelevant: (row["is_relevant"] as Int) != 0,
                manifestInclusion: inclusion,
                visibleSceneCount: visibleSceneCounts[entityID] ?? 0
            )
            guard ManifestQualification.qualifies(facts) else { continue }

            for entry in entriesByKind[kind] ?? [] {
                if try canonicalSlotHolder(entityID: entityID, typeID: entry.id, in: db) != nil {
                    continue
                }
                let normalized = EntityNormalization.normalize(entry.displayName)
                // `excluding:` takes a requirement id; nothing is excluded here, so a
                // fresh id stands in for "no row of my own".
                if let existing = try conflictingRequirementID(
                    entityID: entityID, normalized: normalized, excluding: UUID(), in: db
                ) {
                    plan.collisions.append(
                        ManifestBuildResult.Collision(
                            entityID: entityID,
                            typeID: entry.id,
                            templateCode: entry.code,
                            templateDisplayName: entry.displayName,
                            existingRequirementID: existing
                        )
                    )
                    continue
                }
                plan.children.append(
                    .createCanonicalRequirement(
                        id: UUID(),
                        entityID: entityID,
                        typeID: entry.id,
                        name: entry.displayName
                    )
                )
            }
        }
        return plan
    }
}
