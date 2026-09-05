import Foundation

/// One extracted PDF text line, on the reader → renderer path only (PHASE1_DESIGN §5.4a).
///
/// It plays exactly `FDXParagraph`'s role: `PDFReader` decides what a *line* is by asking
/// PDFKit, and `PDFRenderer` turns this list — and nothing else — into Fountain text.
/// That split keeps classification independent from PDFKit and rendering byte-deterministic.
///
/// ## The six stored properties are frozen (Plan 008 contract A)
///
/// - **Both axes are page-relative fractions, so a `PDFLine` carries no absolute unit.**
///   §5.4a normalizes the left edge so "Letter, A4, and scaled documents classify
///   identically"; the vertical axis is normalized for the same reason, which also
///   removes the need for a redundant per-line page height. The page-furniture predicate
///   then reads directly as `topFraction < 0.08 || bottomFraction > 0.92`.
/// - **`topFraction` grows downward** while PDF's own coordinates grow upward. §5.4a
///   writes the inter-line gap as `previous.minY - current.maxY`; in these top-down
///   fractions the identical quantity is `current.topFraction - previous.bottomFraction`.
///   This is a sign convention, not a change of rule: do not flip it, do not mix the two.
/// - A line's height is `bottomFraction - topFraction`; there is no stored height.
/// - `rightFraction` exists **only** for the dual-dialogue column check (§5.4a's "disjoint
///   horizontal ranges"). Nothing else reads it.
/// - `text` is trimmed at extraction (§5.4a: "record its trimmed text"), so the renderer
///   never re-trims and a leading-space difference cannot move a rendered offset.
///
/// `PDFLine` is deliberately **not** part of `ScreenplayDocument`: no `Double` of it ever
/// reaches persisted `ScreenplayDocument` output, exactly as no `FDXParagraph` does.
public struct PDFLine: Codable, Equatable, Sendable {
    /// The line's text, trimmed of leading and trailing whitespace.
    public let text: String
    /// 0-based page index in document order.
    public let pageIndex: Int
    /// `(bounds.minX - mediaBox.minX) / mediaBox.width`.
    public let leftFraction: Double
    /// `(bounds.maxX - mediaBox.minX) / mediaBox.width`.
    public let rightFraction: Double
    /// `(mediaBox.maxY - bounds.maxY) / mediaBox.height`; `0` at the top of the page.
    public let topFraction: Double
    /// `(mediaBox.maxY - bounds.minY) / mediaBox.height`; `1` at the bottom of the page.
    public let bottomFraction: Double

    public init(
        text: String,
        pageIndex: Int,
        leftFraction: Double,
        rightFraction: Double,
        topFraction: Double,
        bottomFraction: Double
    ) {
        self.text = text
        self.pageIndex = pageIndex
        self.leftFraction = leftFraction
        self.rightFraction = rightFraction
        self.topFraction = topFraction
        self.bottomFraction = bottomFraction
    }
}
