import Foundation
import GRDB

/// Writes and reads `edit_journal` and its `edit_journal_affected` rows (PHASE1_DESIGN §3.8).
///
/// One entry is one `edit_journal` row plus one `edit_journal_affected` row per subject
/// in the entry's read-write set. Nothing else writes those tables, and nothing else
/// turns them back into a `JournalEntry`.
enum JournalStore {
    /// Appends one entry and returns it with the `seq` SQLite assigned.
    ///
    /// `invertsSeq` is the entry this one undoes (§3.8's cancellation rule); `childInverses`
    /// is non-empty only for a group entry, where the payload holds every child inverse
    /// **in order** even though the entry's own `inverse` applies them in reverse.
    @discardableResult
    static func append(
        op: EditOperation,
        effect: MutationEffect,
        actor: MutationActor,
        jobID: UUID?,
        invertsSeq: Int64? = nil,
        childInverses: [EditOperation] = [],
        at now: Date,
        in db: Database
    ) throws -> JournalEntry {
        let payload = JournalPayload(
            inverse: effect.inverse,
            snapshots: effect.snapshots,
            childInverses: childInverses
        )
        let payloadJSON = String(
            decoding: try JournalCoding.encoder.encode(payload),
            as: UTF8.self
        )
        let opJSON = String(decoding: try JournalCoding.encoder.encode(op), as: UTF8.self)
        // `at` is the timestamp as the column stores it — millisecond precision — so the
        // entry this returns is `==` the entry a later read decodes.
        let stamp = UTCDate.string(from: now)
        let at = try UTCDate.date(from: stamp)

        try db.execute(
            sql: """
                INSERT INTO edit_journal (at, actor, job_id, inverts_seq, op, payload)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                stamp, actor.storageValue, jobID?.uuidString,
                invertsSeq, opJSON, payloadJSON,
            ]
        )
        let seq = db.lastInsertedRowID

        for subject in effect.affected.sorted(by: subjectOrder) {
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO edit_journal_affected (seq, subject_kind, subject_id)
                    VALUES (?, ?, ?)
                    """,
                arguments: [seq, subject.kind.rawValue, subject.id.uuidString]
            )
        }

        return JournalEntry(
            seq: seq,
            at: at,
            actor: actor,
            jobID: jobID,
            invertsSeq: invertsSeq,
            op: op,
            inverse: effect.inverse,
            affected: effect.affected,
            snapshots: effect.snapshots
        )
    }

    // MARK: - Reading

    /// One entry by its `seq`, or `nil` when it is not in the journal.
    static func entry(seq: Int64, in db: Database) throws -> JournalEntry? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM edit_journal WHERE seq = ?",
            arguments: [seq]
        ) else { return nil }
        return try decode(row, in: db)
    }

    /// The newest `limit` entries, most recent first — `ProjectReading.journal(limit:)`.
    static func newest(limit: Int, in db: Database) throws -> [JournalEntry] {
        try Row
            .fetchAll(
                db,
                sql: "SELECT * FROM edit_journal ORDER BY seq DESC LIMIT ?",
                arguments: [max(0, limit)]
            )
            .map { try decode($0, in: db) }
    }

    /// One run's entries, newest first — the order selective revert walks (§3.8).
    static func entries(jobID: UUID, in db: Database) throws -> [JournalEntry] {
        try Row
            .fetchAll(
                db,
                sql: "SELECT * FROM edit_journal WHERE job_id = ? ORDER BY seq DESC",
                arguments: [jobID.uuidString]
            )
            .map { try decode($0, in: db) }
    }

    /// The child inverses a group entry recorded, in the order they were applied.
    static func childInverses(seq: Int64, in db: Database) throws -> [EditOperation] {
        guard let json = try String.fetchOne(
            db,
            sql: "SELECT payload FROM edit_journal WHERE seq = ?",
            arguments: [seq]
        ) else { return [] }
        return try JournalCoding.decoder
            .decode(JournalPayload.self, from: Data(json.utf8))
            .childInverses
    }

    /// The subjects one entry touched.
    static func affected(seq: Int64, in db: Database) throws -> Set<SubjectRef> {
        var affected: Set<SubjectRef> = []
        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM edit_journal_affected WHERE seq = ?",
            arguments: [seq]
        ) {
            guard let kind = SubjectKind(rawValue: row["subject_kind"]) else {
                throw ProjectStoreError.invalidBundle
            }
            affected.insert(SubjectRef(kind: kind, id: try UUID.required(row["subject_id"])))
        }
        return affected
    }

    /// `(seq, actor, inverts_seq)` for every entry, newest first — everything the liveness
    /// and conflict walks of §3.8 need before they touch `edit_journal_affected`.
    static func ledger(in db: Database) throws -> [JournalLedgerRow] {
        try Row
            .fetchAll(db, sql: "SELECT seq, actor, inverts_seq FROM edit_journal ORDER BY seq DESC")
            .map { row in
                JournalLedgerRow(
                    seq: row["seq"],
                    isHuman: (row["actor"] as String) == "human",
                    invertsSeq: row["inverts_seq"]
                )
            }
    }

    private static func decode(_ row: Row, in db: Database) throws -> JournalEntry {
        let seq: Int64 = row["seq"]
        let jobID = try (row["job_id"] as String?).map(UUID.required)
        let actor: MutationActor
        switch row["actor"] as String {
        case "human": actor = .human
        case "ai":
            guard let jobID else { throw ProjectStoreError.invalidBundle }
            actor = .ai(jobID: jobID)
        default: throw ProjectStoreError.invalidBundle
        }
        let op = try JournalCoding.decoder.decode(
            EditOperation.self,
            from: Data((row["op"] as String).utf8)
        )
        let payload = try JournalCoding.decoder.decode(
            JournalPayload.self,
            from: Data((row["payload"] as String).utf8)
        )
        return JournalEntry(
            seq: seq,
            at: try UTCDate.date(from: row["at"]),
            actor: actor,
            jobID: jobID,
            invertsSeq: row["inverts_seq"],
            op: op,
            inverse: payload.inverse,
            affected: try affected(seq: seq, in: db),
            snapshots: payload.snapshots
        )
    }

    /// A stable insert order, so a journal write is reproducible row for row.
    private static func subjectOrder(_ lhs: SubjectRef, _ rhs: SubjectRef) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// The three journal columns liveness and conflict detection read (§3.8).
struct JournalLedgerRow: Equatable, Sendable {
    let seq: Int64
    let isHuman: Bool
    let invertsSeq: Int64?
}
