import Foundation
import GRDB

/// The review verdicts of PHASE1_DESIGN §3.6: `acceptFact` / `unacceptFact`, and the
/// `rejectSubject` / `unrejectSubject` primitives behind the tombstoning removes (§6).
///
/// All four write **only** review columns — `review_state`, `reviewed_at`, and the row's
/// `updated_at`. `source`, `created_source`, and `job_id` are never touched, which is what
/// keeps "the model found this and a person vouched for it" distinguishable from "a person
/// added this" (§7.2's `origin`).
///
/// The file is a Plan 005 addition beside the target layout's operation files: accept and
/// reject are not entity-, scene-, or continuity-shaped — they address any subject kind
/// that carries a review state, `synopsis` included.
enum ReviewOperations {

    /// Validated AI output is immediately usable. `accepted` here means active, not that a
    /// person reviewed it; `reviewed_at` deliberately remains NULL. The extraction and
    /// manifest appliers call the run-scoped form inside their commit transactions, while
    /// migration v8 uses the all-project form to retire legacy review queues.
    static func activateValidatedAIOutput(jobID: UUID, in db: Database) throws {
        try activateProposedFacts(where: "job_id = ?", arguments: [jobID.uuidString], in: db)
        try db.execute(
            sql: """
                UPDATE scenes SET synopsis_review_state = 'accepted'
                WHERE synopsis_review_state = 'proposed' AND synopsis_job_id = ?
                """,
            arguments: [jobID.uuidString]
        )
    }

    static func activateAllProposedFacts(in db: Database) throws {
        try activateProposedFacts(where: "1 = 1", arguments: [], in: db)
        try db.execute(
            sql: """
                UPDATE scenes SET synopsis_review_state = 'accepted'
                WHERE synopsis_review_state = 'proposed'
                """
        )
    }

    private static func activateProposedFacts(
        where predicate: String,
        arguments: StatementArguments,
        in db: Database
    ) throws {
        for table in [
            "entities", "entity_aliases", "scene_entities", "entity_states",
            "continuity_events", "entity_relationships", "asset_requirements",
            "asset_requirement_scenes", "asset_dependencies",
        ] {
            try db.execute(
                sql: """
                    UPDATE \(table) SET review_state = 'accepted'
                    WHERE review_state = 'proposed' AND \(predicate)
                    """,
                arguments: arguments
            )
        }
    }

    /// Where one subject's review columns live. A scene synopsis is a **column set** on
    /// `scenes` rather than a row of its own (§4.3), so the column names travel with the
    /// target instead of being assumed.
    struct Target {
        let ref: SubjectRef
        let table: String
        let reviewState: String
        let reviewedAt: String
        let updatedAt: String
        let createdSource: String
    }

    /// The kinds that carry **no** reviewable PROV surface (§7.5).
    ///
    /// The three reviewable Phase 2 kinds — `requirement`, `requirementScene`, and
    /// `dependency` — are deliberately absent: they carry the standard PROV block and are
    /// reviewed through the ordinary `review_state` / `reviewed_at` columns of their own
    /// tables, which `RowSnapshotStore.table(for:)` already names.
    static let unreviewableKinds: Set<SubjectKind> = [
        .scene, .script, .basis, .templateEntry, .asset, .version,
        // PHASE3_DESIGN §7.4: a prompt is output, not a reviewable fact (§4.3's inert
        // review_state), and its citations are immutable history like basis rows.
        .prompt, .promptReference,
    ]

    static func target(for ref: SubjectRef) throws -> Target {
        if ref.kind == .synopsis {
            return Target(
                ref: ref,
                table: "scenes",
                reviewState: "synopsis_review_state",
                reviewedAt: "synopsis_reviewed_at",
                updatedAt: "synopsis_updated_at",
                createdSource: "synopsis_created_source"
            )
        }
        // `scene` and `script` carry no verdict of their own: a scene is reviewed through
        // its synopsis, and a script is not a fact.
        //
        // PHASE2_DESIGN §7.5's **explicit exclusions**: `basis`, `templateEntry`, `asset`,
        // and `version` all map a snapshot table, so without this guard an accept aimed at
        // one would reach `UPDATE … SET review_state` and fail as a raw SQL error. A basis
        // row is an immutable citation and a template row is settings — neither has a PROV
        // block at all — and PROV `review_state` on an asset or a version is inert (§3.7):
        // their lifecycle is `status`, so "reviewing" one is a call that must not exist.
        guard !Self.unreviewableKinds.contains(ref.kind),
              let table = RowSnapshotStore.table(for: ref.kind)
        else {
            throw ProjectStoreError.invalidFact(
                reason: "A \(ref.kind.rawValue) does not carry a review state."
            )
        }
        return Target(
            ref: ref,
            table: table,
            reviewState: "review_state",
            reviewedAt: "reviewed_at",
            updatedAt: "updated_at",
            createdSource: "created_source"
        )
    }

    // MARK: - acceptFact / unacceptFact (§3.6)

    /// §6's per-fact accept: `review_state = 'accepted'` plus the `reviewed_at` stamp that
    /// is the **only** signal an operator vouched for the row — and nothing else.
    static func accept(
        ref: SubjectRef,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let target = try target(for: ref)
        if let entry = mode.invertedEntry {
            return try invert(target: target, entry: entry, in: db) { state in
                .unacceptFact(ref, priorState: state)
            }
        }
        try requireHuman(actor, subject: ref)
        let (snapshot, state) = try read(target, in: db)
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                UPDATE \(target.table)
                SET \(target.reviewState) = ?, \(target.reviewedAt) = ?, \(target.updatedAt) = ?
                WHERE id = ?
                """,
            arguments: [ReviewState.accepted.rawValue, timestamp, timestamp, ref.id.uuidString]
        )
        return MutationEffect(
            inverse: .unacceptFact(ref, priorState: state),
            affected: [ref],
            snapshots: [snapshot]
        )
    }

    /// `acceptFact`'s inverse: the prior verdict back, and `reviewed_at` **cleared** —
    /// undoing an accept must leave it NULL again when it was NULL (§3.8).
    static func unaccept(
        ref: SubjectRef,
        priorState: ReviewState,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let target = try target(for: ref)
        if let entry = mode.invertedEntry {
            return try invert(target: target, entry: entry, in: db) { _ in .acceptFact(ref) }
        }
        try requireHuman(actor, subject: ref)
        let (snapshot, _) = try read(target, in: db)
        try db.execute(
            sql: """
                UPDATE \(target.table)
                SET \(target.reviewState) = ?, \(target.reviewedAt) = NULL, \(target.updatedAt) = ?
                WHERE id = ?
                """,
            arguments: [priorState.rawValue, UTCDate.string(from: Date()), ref.id.uuidString]
        )
        return MutationEffect(inverse: .acceptFact(ref), affected: [ref], snapshots: [snapshot])
    }

    // MARK: - rejectSubject / unrejectSubject (§6's tombstoning removes)

    /// The tombstone verdict on a state, event, relationship, alias, or appearance — the
    /// primitive `removeState` / `removeEvent` / `removeRelationship` use on rows they may
    /// not hard-delete (§6).
    ///
    /// Protection is the **caller's** check, not this one's: a remove has already asked
    /// `ProtectionPolicy` whether the row may go, and re-asking here would refuse the
    /// inverse of a change the project already contains.
    static func reject(
        ref: SubjectRef,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let target = try target(for: ref)
        if let entry = mode.invertedEntry {
            return try invert(target: target, entry: entry, in: db) { state in
                .unrejectSubject(ref, priorState: state)
            }
        }
        let (snapshot, state) = try read(target, in: db)
        try db.execute(
            sql: """
                UPDATE \(target.table)
                SET \(target.reviewState) = ?,
                    \(target.reviewedAt) = COALESCE(?, \(target.reviewedAt)),
                    \(target.updatedAt) = ?
                WHERE id = ?
                """,
            arguments: stamp(actor, state: .rejected, id: ref.id)
        )
        return MutationEffect(
            inverse: .unrejectSubject(ref, priorState: state),
            affected: [ref],
            snapshots: [snapshot]
        )
    }

    /// `rejectSubject`'s inverse: the verdict the tombstone replaced, or — with none
    /// carried — `accepted` for a row the parser created and `proposed` otherwise, so a
    /// parser row is never left `proposed` (§6).
    static func unreject(
        ref: SubjectRef,
        priorState: ReviewState?,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let target = try target(for: ref)
        if let entry = mode.invertedEntry {
            return try invert(target: target, entry: entry, in: db) { _ in .rejectSubject(ref) }
        }
        let (snapshot, _) = try read(target, in: db)
        let rawCreatedSource = try String.fetchOne(
            db,
            sql: "SELECT \(target.createdSource) FROM \(target.table) WHERE id = ?",
            arguments: [ref.id.uuidString]
        )
        let createdSource = FactSource(rawValue: rawCreatedSource ?? "")
        let restored = priorState ?? (createdSource == .parser ? .accepted : .proposed)
        try db.execute(
            sql: """
                UPDATE \(target.table)
                SET \(target.reviewState) = ?,
                    \(target.reviewedAt) = COALESCE(?, \(target.reviewedAt)),
                    \(target.updatedAt) = ?
                WHERE id = ?
                """,
            arguments: stamp(actor, state: restored, id: ref.id)
        )
        return MutationEffect(
            inverse: .rejectSubject(ref),
            affected: [ref],
            snapshots: [snapshot]
        )
    }

    // MARK: - The rows a review action addresses

    /// Accepting an entity accepts its alias **and appearance** rows: they are what Plan
    /// 006 exports as `aliases` / `appearsIn`, and they enter the answer key only when
    /// themselves reviewed (§3.5, §7.2).
    ///
    /// The result is deduplicated and ordered by `(kind, id)`, so the group's payload — and
    /// therefore its inverse — is reproducible.
    static func expand(refs: [SubjectRef], in db: Database) throws -> [SubjectRef] {
        var expanded: Set<SubjectRef> = []
        for ref in refs {
            expanded.insert(ref)
            switch ref.kind {
            case .entity:
                for id in try ids(
                    sql: "SELECT id FROM entity_aliases WHERE entity_id = ?", of: ref.id, in: db
                ) {
                    expanded.insert(SubjectRef(kind: .alias, id: id))
                }
                for id in try ids(
                    sql: "SELECT id FROM scene_entities WHERE entity_id = ?", of: ref.id, in: db
                ) {
                    expanded.insert(SubjectRef(kind: .appearance, id: id))
                }

            // PHASE2_DESIGN §7.2's review paragraph: accepting a requirement accepts its
            // still-`proposed` scene links and dependencies. **Basis rows are excluded** —
            // they are immutable citations with reduced provenance (§3.7), carry no
            // `review_state` column at all, and `target(for:)` refuses them outright.
            //
            // Only the edges the requirement **owns** (`requirement_id`) travel with it: a
            // mirror row seeded on another requirement is that requirement's dependency,
            // not this one's. Unlike the entity case above the rows are filtered to
            // `proposed`, exactly as §7.2 words it, so an accept never re-stamps
            // `reviewed_at` on a link a person already vouched for.
            case .requirement:
                for id in try ids(
                    sql: """
                        SELECT id FROM asset_requirement_scenes
                        WHERE requirement_id = ? AND review_state = 'proposed'
                        """,
                    of: ref.id, in: db
                ) {
                    expanded.insert(SubjectRef(kind: .requirementScene, id: id))
                }
                for id in try ids(
                    sql: """
                        SELECT id FROM asset_dependencies
                        WHERE requirement_id = ? AND review_state = 'proposed'
                        """,
                    of: ref.id, in: db
                ) {
                    expanded.insert(SubjectRef(kind: .dependency, id: id))
                }

            default:
                continue
            }
        }
        return expanded.sorted(by: order)
    }

    /// Every `proposed` fact row in the project, ordered by `(kind, id)` —
    /// `acceptAllProposed`'s payload (§6).
    ///
    /// `sequences` is deliberately absent: it carries PROV but no `SubjectKind`, and the
    /// parser writes its rows `accepted` (§5.3), so nothing there is ever proposed.
    static func proposedRefs(in db: Database) throws -> [SubjectRef] {
        var refs: [SubjectRef] = []
        let tables: [(String, SubjectKind)] = [
            ("entities", .entity),
            ("entity_aliases", .alias),
            ("scene_entities", .appearance),
            ("entity_states", .state),
            ("continuity_events", .event),
            ("entity_relationships", .relationship),
            // PHASE2_DESIGN §7.5: the three reviewable Phase 2 tables. `assets`,
            // `asset_versions`, `asset_requirement_basis`, and `asset_requirement_types`
            // are deliberately absent — the first two carry an **inert** PROV block whose
            // lifecycle is `status` (§3.7), and the last two carry no PROV at all.
            ("asset_requirements", .requirement),
            ("asset_requirement_scenes", .requirementScene),
            ("asset_dependencies", .dependency),
        ]
        for (table, kind) in tables {
            for raw in try String.fetchAll(
                db, sql: "SELECT id FROM \(table) WHERE review_state = 'proposed' ORDER BY id"
            ) {
                refs.append(SubjectRef(kind: kind, id: try UUID.required(raw)))
            }
        }
        for raw in try String.fetchAll(
            db, sql: "SELECT id FROM scenes WHERE synopsis_review_state = 'proposed' ORDER BY id"
        ) {
            refs.append(SubjectRef(kind: .synopsis, id: try UUID.required(raw)))
        }
        return refs.sorted(by: order)
    }

    // MARK: - Preconditions (§3.8)

    static func precheck(ref: SubjectRef, in db: Database) throws {
        let target = try target(for: ref)
        guard try RowSnapshotStore.exists(table: target.table, id: ref.id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Something that change reviewed is no longer in this project."
            )
        }
    }

    // MARK: - Helpers

    /// Accept is an operator verdict: `reviewed_at` "is set solely by
    /// `acceptFacts`/`acceptAllProposed` or by a human edit", and **an `.ai` mutation never
    /// writes `reviewed_at` on any row** (§3.6). An AI accept is therefore not a rule the
    /// policy softens — it is a call that must not exist.
    private static func requireHuman(_ actor: MutationActor, subject: SubjectRef) throws {
        guard actor == .human else { throw ProjectStoreError.protectedFact(subject: subject) }
    }

    /// The row's snapshot and its current verdict, read before the write so the inverse
    /// can restore both.
    private static func read(_ target: Target, in db: Database) throws -> (RowSnapshot, ReviewState) {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM \(target.table) WHERE id = ?", arguments: [target.ref.id.uuidString]
        ) else {
            throw target.ref.kind == .synopsis
                ? ProjectStoreError.sceneNotFound
                : ProjectStoreError.entityNotFound
        }
        let state = ReviewState(rawValue: row[target.reviewState] as String? ?? "") ?? .proposed
        return (RowSnapshot(table: target.table, row: row), state)
    }

    /// The `.inverting` half all four share: the row back exactly as the entry found it,
    /// and the operation that would apply the change again.
    private static func invert(
        target: Target,
        entry: JournalEntry,
        in db: Database,
        redo: (ReviewState) -> EditOperation
    ) throws -> MutationEffect {
        let (snapshot, state) = try read(target, in: db)
        guard let restored = entry.snapshot(table: target.table, id: target.ref.id) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has a review verdict to restore."
            )
        }
        try RowSnapshotStore.restore(restored, in: db)
        return MutationEffect(inverse: redo(state), affected: [target.ref], snapshots: [snapshot])
    }

    /// `reviewed_at` is stamped by a human verdict and left exactly where it was by an
    /// `.ai` one (§3.6).
    private static func stamp(_ actor: MutationActor, state: ReviewState, id: UUID) -> StatementArguments {
        let timestamp = UTCDate.string(from: Date())
        return [state.rawValue, actor == .human ? timestamp : nil, timestamp, id.uuidString]
    }

    private static func ids(sql: String, of owner: UUID, in db: Database) throws -> [UUID] {
        try String
            .fetchAll(db, sql: "\(sql) ORDER BY id", arguments: [owner.uuidString])
            .map { try UUID.required($0) }
    }

    static func order(_ lhs: SubjectRef, _ rhs: SubjectRef) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
