import Foundation

public struct Scene: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let scriptID: UUID
    /// Parser-assigned and contiguous from 1; ordinal 0 is the preamble ("Before first scene").
    public let ordinal: Int
    public let sequenceID: UUID?
    public let heading: String
    public let intExt: SceneIntExt
    /// The heading minus its prefix and time-of-day segment; may be `""`.
    public let locationText: String
    public let timeOfDay: String
    /// The author's `#12A#`; never used for ordering.
    public let sceneNumber: String?
    /// The scene's span in `Script.sourceText`.
    public let range: UTF16Range
    public let isOmitted: Bool
    public let synopsis: String
    // The synopsis field's own provenance (§4.3) — the scene row itself is parser-owned.
    public let synopsisSource: FactSource?
    public let synopsisCreatedSource: FactSource?
    public let synopsisConfidence: Double?
    public let synopsisReviewState: ReviewState?
    public let synopsisReviewedAt: Date?
    public let synopsisJobID: UUID?
    public let synopsisUpdatedAt: Date?

    public init(
        id: UUID,
        scriptID: UUID,
        ordinal: Int,
        sequenceID: UUID?,
        heading: String,
        intExt: SceneIntExt,
        locationText: String,
        timeOfDay: String,
        sceneNumber: String?,
        range: UTF16Range,
        isOmitted: Bool,
        synopsis: String,
        synopsisSource: FactSource? = nil,
        synopsisCreatedSource: FactSource? = nil,
        synopsisConfidence: Double? = nil,
        synopsisReviewState: ReviewState? = nil,
        synopsisReviewedAt: Date? = nil,
        synopsisJobID: UUID? = nil,
        synopsisUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.scriptID = scriptID
        self.ordinal = ordinal
        self.sequenceID = sequenceID
        self.heading = heading
        self.intExt = intExt
        self.locationText = locationText
        self.timeOfDay = timeOfDay
        self.sceneNumber = sceneNumber
        self.range = range
        self.isOmitted = isOmitted
        self.synopsis = synopsis
        self.synopsisSource = synopsisSource
        self.synopsisCreatedSource = synopsisCreatedSource
        self.synopsisConfidence = synopsisConfidence
        self.synopsisReviewState = synopsisReviewState
        self.synopsisReviewedAt = synopsisReviewedAt
        self.synopsisJobID = synopsisJobID
        self.synopsisUpdatedAt = synopsisUpdatedAt
    }
}

/// FilmCore's interior/exterior classification, so reading a scene never requires
/// importing the parser (§3.1). Raw values match `scenes.int_ext`.
public enum SceneIntExt: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case int
    case ext
    case intExt = "int_ext"
    case unknown
}
