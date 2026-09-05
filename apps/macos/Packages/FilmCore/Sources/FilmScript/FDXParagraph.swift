import Foundation

/// One FDX `Paragraph`, on the reader → renderer path only (PHASE1_DESIGN §5.4).
///
/// It is deliberately flat: the SAX walk in `FDXReader` decides which XML paragraphs
/// are body paragraphs and what dual-dialogue position they hold, and `FDXRenderer`
/// then turns this list — and nothing else — into Fountain text. That split is what
/// makes rendering testable and byte-deterministic on its own.
public struct FDXParagraph: Codable, Equatable, Sendable {
    /// The `Paragraph@Type` attribute, defaulted to `Action` when absent (§5.4).
    public let type: String
    /// The concatenation of the paragraph's **direct** `Text` children, no separator,
    /// no trimming; embedded newlines and tabs are preserved.
    public let text: String
    /// `Paragraph@Number`, the author's scene number — never read from `SceneProperties`.
    public let number: String?
    /// `true` for the **second** `Character` cue inside a `DualDialogue` block, which
    /// renders with a trailing Fountain `^`.
    public let isDualSecond: Bool

    public init(type: String, text: String, number: String?, isDualSecond: Bool) {
        self.type = type
        self.text = text
        self.number = number
        self.isDualSecond = isDualSecond
    }
}
