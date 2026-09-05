import Foundation

/// One recorded mutation (PHASE1_DESIGN §3.8).
///
/// `affected` lists **every** row the entry touched — the entity, its aliases,
/// appearances, evidence, states, events, relationships, and lock rows — because undo
/// and revert detect conflicts by comparing affected sets.
public struct JournalEntry: Codable, Equatable, Sendable, Identifiable {
    public let seq: Int64
    public let at: Date
    public let actor: MutationActor
    public let jobID: UUID?
    /// The `seq` this entry inverted, when it applied another entry's inverse (§3.8's
    /// cancellation rule). Written by nothing until Plan 005's `applyInverse`.
    public let invertsSeq: Int64?
    public let op: EditOperation
    /// The operation that undoes `op`, or `nil` when `op` is non-invertible.
    public let inverse: EditOperation?
    public let affected: Set<SubjectRef>
    /// Full row snapshots of anything the entry deleted or overwrote.
    public let snapshots: [RowSnapshot]

    public var id: Int64 { seq }

    public init(
        seq: Int64,
        at: Date,
        actor: MutationActor,
        jobID: UUID?,
        invertsSeq: Int64?,
        op: EditOperation,
        inverse: EditOperation?,
        affected: Set<SubjectRef>,
        snapshots: [RowSnapshot]
    ) {
        self.seq = seq
        self.at = at
        self.actor = actor
        self.jobID = jobID
        self.invertsSeq = invertsSeq
        self.op = op
        self.inverse = inverse
        self.affected = affected
        self.snapshots = snapshots
    }
}

/// What `edit_journal.payload` holds: everything about an entry that is not a column.
struct JournalPayload: Codable, Equatable, Sendable {
    var inverse: EditOperation?
    var snapshots: [RowSnapshot]
    /// Child inverses in order, for group entries (Plan 005).
    var childInverses: [EditOperation]

    init(inverse: EditOperation?, snapshots: [RowSnapshot], childInverses: [EditOperation] = []) {
        self.inverse = inverse
        self.snapshots = snapshots
        self.childInverses = childInverses
    }
}
