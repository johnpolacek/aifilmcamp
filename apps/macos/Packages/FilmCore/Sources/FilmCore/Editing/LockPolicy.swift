import Foundation
import GRDB

/// Which fields a subject kind may be locked on, and the **one** place `locks` is read
/// (PHASE1_DESIGN §3.7).
///
/// `LockField` is only the vocabulary; this is the policy. Every operation asks here
/// rather than writing its own `SELECT … FROM locks`, so "any lock blocks a merge but a
/// field lock on the target does not" is one rule with one implementation.
public enum LockPolicy {

    /// The fields §3.7 enumerates for a subject kind. Anything else is
    /// `.invalidLockField(subjectKind:field:)`.
    ///
    /// The empty set is the answer for the kinds `locks.subject_kind`'s `CHECK` does not
    /// admit (`appearance`, `synopsis`, `script`) — a scene synopsis is locked as the
    /// **scene**'s `synopsis` field, which is why `synopsis` is not lockable in itself.
    public static func fields(for kind: SubjectKind) -> Set<LockField> {
        switch kind {
        case .entity: [.name, .description, .kind, .isRelevant, .whole]
        case .scene: [.synopsis, .whole]
        case .alias, .state, .event, .relationship: [.whole]
        // PHASE2_DESIGN §7.5: `requirement` is the **only** kind the rebuilt
        // `locks.subject_kind` CHECK admits from Phase 2, and its fields are exactly these.
        // `tier` and `type_id` are immutable columns no operation edits, so they need no
        // lock-field vocabulary.
        case .requirement: [.name, .reason, .necessity, .whole]
        case .appearance, .synopsis, .script: []
        // Not lockable: a scene link, a basis citation, a dependency, an asset, a version,
        // a template entry, and (PHASE3_DESIGN §7.4) a prompt or prompt citation are
        // pinned through their requirement, or are settings. The freeze rule for prompts
        // runs through `requireRequirementUnlocked` instead.
        case .requirementScene, .basis, .dependency, .asset, .version, .templateEntry,
             .prompt, .promptReference: []
        }
    }

    /// PHASE3_DESIGN §7.4's named wrapper over the shipped whole-lock idiom.
    ///
    /// The new subject kinds are deliberately not lockable, so a subject-keyed check on a
    /// prompt row would see nothing — the requirement's own `whole` lock is what freezes
    /// its slot. Every §7.2 prompt operation calls this before mutating; Plan 014 wires it
    /// into each operation.
    static func requireRequirementUnlocked(
        requirementID: UUID,
        in db: Database
    ) throws {
        try checkUnlocked(
            subject: SubjectRef(kind: .requirement, id: requirementID),
            field: .whole,
            in: db
        )
    }

    /// Throws `.invalidLockField` unless §3.7 admits that pair.
    static func validate(subject: SubjectRef, field: LockField) throws {
        guard fields(for: subject.kind).contains(field) else {
            throw ProjectStoreError.invalidLockField(subjectKind: subject.kind, field: field)
        }
    }

    // MARK: - Reading locks

    /// The lock that stands in the way of changing `field` of `subject`, if any.
    ///
    /// A whole-record lock blocks every field; a field lock blocks its own field. `.whole`
    /// as the requested field means "the record itself" — a delete or a reject — which
    /// §3.7 puts under the whole-record lock alone: a `description` lock pins the
    /// description, not the row's existence.
    ///
    /// The rule that reads *any* lock is a different one, and belongs to merge and split
    /// (`anyLock` / `checkFree`): "Any lock on a subject — whole or field — blocks `merge`
    /// of that subject as a source and `split` of a locked alias, for both actors."
    ///
    /// `ORDER BY field` puts `*` first: `"*"` sorts below every field name, so the
    /// whole-record lock is the one reported when both exist.
    static func blocking(subject: SubjectRef, field: LockField, in db: Database) throws -> LockField? {
        guard let raw = try String.fetchOne(
            db,
            sql: """
                SELECT field FROM locks
                WHERE subject_kind = ? AND subject_id = ? AND field IN (?, ?) ORDER BY field LIMIT 1
                """,
            arguments: [
                subject.kind.rawValue, subject.id.uuidString,
                LockField.whole.rawValue, field.rawValue,
            ]
        ) else { return nil }
        return LockField(rawValue: raw) ?? .whole
    }

    /// `.locked(subject:field:)` when anything blocks that change — the guard both actors
    /// pass through (§3.7: the human path clears it with an explicit `unlock`).
    static func checkUnlocked(subject: SubjectRef, field: LockField, in db: Database) throws {
        if let blocking = try blocking(subject: subject, field: field, in: db) {
            throw ProjectStoreError.locked(subject: subject, field: blocking)
        }
    }

    /// `true` when the **whole record** is locked.
    ///
    /// The one rule that asks this rather than `blocking(…)`: a merge adds an alias to its
    /// target, which a whole-record lock on the target refuses while a field lock on it
    /// does not (§3.5).
    static func hasWholeLock(subject: SubjectRef, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM locks WHERE subject_kind = ? AND subject_id = ? AND field = ?
                )
                """,
            arguments: [subject.kind.rawValue, subject.id.uuidString, LockField.whole.rawValue]
        ) ?? false
    }

    /// Any lock over the subject, whole or field — the merge-and-split rule (§3.7).
    static func anyLock(subject: SubjectRef, in db: Database) throws -> LockField? {
        guard let raw = try String.fetchOne(
            db,
            sql: """
                SELECT field FROM locks
                WHERE subject_kind = ? AND subject_id = ? ORDER BY field LIMIT 1
                """,
            arguments: [subject.kind.rawValue, subject.id.uuidString]
        ) else { return nil }
        return LockField(rawValue: raw) ?? .whole
    }

    /// `.locked` when **any** lock sits on the subject: merge of that subject as a source,
    /// and split of a locked alias, are refused by a field lock as surely as by `*`.
    static func checkFree(subject: SubjectRef, in db: Database) throws {
        if let field = try anyLock(subject: subject, in: db) {
            throw ProjectStoreError.locked(subject: subject, field: field)
        }
    }

    /// `true` when that exact lock row is there.
    static func exists(subject: SubjectRef, field: LockField, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM locks
                    WHERE subject_kind = ? AND subject_id = ? AND field = ?
                )
                """,
            arguments: [subject.kind.rawValue, subject.id.uuidString, field.rawValue]
        ) ?? false
    }

    /// The first lock over an entity or one of its aliases — the merge-source rule of
    /// §3.5, which refuses for **both** actors.
    static func firstLock(
        entity: UUID,
        aliases: [UUID],
        in db: Database
    ) throws -> (subject: SubjectRef, field: LockField)? {
        let entityRef = SubjectRef(kind: .entity, id: entity)
        if let field = try anyLock(subject: entityRef, in: db) { return (entityRef, field) }
        guard !aliases.isEmpty else { return nil }
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT subject_id, field FROM locks
                WHERE subject_kind = 'alias' AND subject_id IN \(EntityOperations.inClause(aliases))
                ORDER BY subject_id, field
                """,
            arguments: StatementArguments(aliases.map(\.uuidString))
        ) else { return nil }
        let ref = SubjectRef(kind: .alias, id: try UUID.required(row["subject_id"]))
        return (ref, LockField(rawValue: row["field"] as String? ?? LockField.whole.rawValue) ?? .whole)
    }
}

// MARK: - lock / unlock (§3.7)

/// The two operations that write `locks`.
///
/// Locking is an **operator** affordance: an `.ai` run that could lock or unlock would
/// defeat the very rule locks exist to enforce, so both are human-only, exactly as
/// `splitEntity` is (§3.5, §8.5 — no apply rule locks anything).
enum LockOperations {

    static func lock(
        subject: SubjectRef,
        field: LockField,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        try checkActor(actor, subject: subject)
        try LockPolicy.validate(subject: subject, field: field)
        try requireSubject(subject, in: db)

        // Undoing an `unlock` must bring the lock row back with its **original**
        // `locked_at`, never "now" (§3.8: an inverse restores timestamps).
        if let entry = mode.invertedEntry,
           let snapshot = lockSnapshot(in: entry, subject: subject, field: field) {
            try RowSnapshotStore.restore(snapshot, in: db)
            return MutationEffect(
                inverse: .unlock(subject: subject, field: field),
                affected: [subject]
            )
        }

        guard try !LockPolicy.exists(subject: subject, field: field, in: db) else {
            // Already locked: nothing to do, and nothing to undo.
            return MutationEffect(inverse: .batch([]), affected: [subject])
        }
        try db.execute(
            sql: """
                INSERT INTO locks (subject_kind, subject_id, field, locked_at) VALUES (?, ?, ?, ?)
                """,
            arguments: [
                subject.kind.rawValue, subject.id.uuidString, field.rawValue,
                UTCDate.string(from: Date()),
            ]
        )
        return MutationEffect(inverse: .unlock(subject: subject, field: field), affected: [subject])
    }

    static func unlock(
        subject: SubjectRef,
        field: LockField,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        try checkActor(actor, subject: subject)
        try LockPolicy.validate(subject: subject, field: field)

        guard let snapshot = try lockRow(subject: subject, field: field, in: db) else {
            // Not locked: nothing to do, and nothing to undo.
            return MutationEffect(inverse: .batch([]), affected: [subject])
        }
        try db.execute(
            sql: "DELETE FROM locks WHERE subject_kind = ? AND subject_id = ? AND field = ?",
            arguments: [subject.kind.rawValue, subject.id.uuidString, field.rawValue]
        )
        return MutationEffect(
            inverse: .lock(subject: subject, field: field),
            affected: [subject],
            snapshots: [snapshot]
        )
    }

    // MARK: - Preconditions (§3.8)

    static func precheckLock(subject: SubjectRef, field: LockField, in db: Database) throws {
        try requireRestorableSubject(subject, in: db)
    }

    static func precheckUnlock(subject: SubjectRef, field: LockField, in db: Database) throws {
        try requireRestorableSubject(subject, in: db)
    }

    // MARK: - Helpers

    private static func checkActor(_ actor: MutationActor, subject: SubjectRef) throws {
        guard actor == .human else { throw ProjectStoreError.protectedFact(subject: subject) }
    }

    /// A lock row carries no foreign key (§4.3), so the subject has to be checked by hand
    /// or a lock could outlive the row it pins.
    private static func requireSubject(_ subject: SubjectRef, in db: Database) throws {
        guard let table = RowSnapshotStore.table(for: subject.kind) else {
            throw ProjectStoreError.invalidLockField(subjectKind: subject.kind, field: .whole)
        }
        guard try RowSnapshotStore.exists(table: table, id: subject.id, in: db) else {
            throw subject.kind == .scene
                ? ProjectStoreError.sceneNotFound
                : ProjectStoreError.entityNotFound
        }
    }

    private static func requireRestorableSubject(_ subject: SubjectRef, in db: Database) throws {
        guard let table = RowSnapshotStore.table(for: subject.kind),
              try RowSnapshotStore.exists(table: table, id: subject.id, in: db)
        else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That item is no longer in this project."
            )
        }
    }

    private static func lockRow(
        subject: SubjectRef,
        field: LockField,
        in db: Database
    ) throws -> RowSnapshot? {
        try Row
            .fetchOne(
                db,
                sql: """
                    SELECT * FROM locks
                    WHERE subject_kind = ? AND subject_id = ? AND field = ?
                    """,
                arguments: [subject.kind.rawValue, subject.id.uuidString, field.rawValue]
            )
            .map { RowSnapshot(table: "locks", row: $0) }
    }

    /// The snapshot an `unlock` entry took of exactly this lock row.
    private static func lockSnapshot(
        in entry: JournalEntry,
        subject: SubjectRef,
        field: LockField
    ) -> RowSnapshot? {
        entry.snapshots.first { snapshot in
            snapshot.table == "locks"
                && snapshot.columns["subject_kind"] == .string(subject.kind.rawValue)
                && snapshot.columns["subject_id"] == .string(subject.id.uuidString)
                && snapshot.columns["field"] == .string(field.rawValue)
        }
    }
}
