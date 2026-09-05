import Foundation

/// A Fountain `#` section (PHASE1_DESIGN §5.2). Named `ScriptSequence` because
/// `Sequence` would shadow `Swift.Sequence`.
public struct ScriptSequence: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let scriptID: UUID
    /// Contiguous from 1 in document order across *all* depths.
    public let ordinal: Int
    /// Count of leading `#` characters.
    public let depth: Int
    public let title: String
    public let range: UTF16Range
    public let provenance: Provenance

    public init(
        id: UUID,
        scriptID: UUID,
        ordinal: Int,
        depth: Int,
        title: String,
        range: UTF16Range,
        provenance: Provenance
    ) {
        self.id = id
        self.scriptID = scriptID
        self.ordinal = ordinal
        self.depth = depth
        self.title = title
        self.range = range
        self.provenance = provenance
    }
}
