import Foundation

/// A pin on a subject or one of its fields (PHASE1_DESIGN §3.7).
///
/// `field` is one of an enumerated set per subject kind, never an arbitrary column;
/// `Lock.wholeRecord` (`"*"`) locks the whole row.
public struct Lock: Codable, Equatable, Hashable, Sendable {
    /// The `field` value that means "the whole record".
    public static let wholeRecord = "*"

    /// One of `SubjectKind.lockable`.
    public let subjectKind: SubjectKind
    public let subjectID: UUID
    public let field: String
    public let lockedAt: Date

    public var subject: SubjectRef { SubjectRef(kind: subjectKind, id: subjectID) }
    public var isWholeRecord: Bool { field == Self.wholeRecord }

    public init(subjectKind: SubjectKind, subjectID: UUID, field: String, lockedAt: Date) {
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.field = field
        self.lockedAt = lockedAt
    }
}
