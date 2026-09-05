import Foundation

/// A quote in the screenplay backing one fact (PHASE1_DESIGN §3.3, §4.3).
///
/// `anchored` and the two offsets move together: a row is anchored exactly when both
/// offsets are present, enforced by the table's `CHECK`.
public struct Evidence: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// One of `SubjectKind.evidenceable`.
    public let subjectKind: SubjectKind
    public let subjectID: UUID
    /// `nil` for synopsis evidence and entity-less continuity-event evidence; otherwise
    /// the entity that owns the row.
    public let ownerEntityID: UUID?
    public let sceneID: UUID
    /// The alias that produced this evidence, when one did (§3.5).
    public let matchedAliasID: UUID?
    /// `nil` when the quote could not be anchored in `Script.sourceText`.
    public let range: UTF16Range?
    public let quote: String
    public let source: FactSource
    public let jobID: UUID?
    public let createdAt: Date

    public var isAnchored: Bool { range != nil }

    public init(
        id: UUID,
        subjectKind: SubjectKind,
        subjectID: UUID,
        ownerEntityID: UUID?,
        sceneID: UUID,
        matchedAliasID: UUID?,
        range: UTF16Range?,
        quote: String,
        source: FactSource,
        jobID: UUID?,
        createdAt: Date
    ) {
        self.id = id
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.ownerEntityID = ownerEntityID
        self.sceneID = sceneID
        self.matchedAliasID = matchedAliasID
        self.range = range
        self.quote = quote
        self.source = source
        self.jobID = jobID
        self.createdAt = createdAt
    }
}
