import Foundation

/// Source-text normalization (PHASE1_DESIGN §5.1).
///
/// Exactly two transformations, so offsets stay honest: a leading UTF-8 BOM is
/// stripped, and `\r\n` and lone `\r` become `\n`. Smart quotes, tabs, trailing
/// whitespace, and every other Unicode detail survive untouched. The function is
/// idempotent: `normalize(normalize(x)) == normalize(x)`.
public enum TextNormalization: Sendable {
    private static let byteOrderMark: Unicode.Scalar = "\u{FEFF}"
    private static let carriageReturn: Unicode.Scalar = "\r"
    private static let lineFeed: Unicode.Scalar = "\n"

    /// Returns `raw` with a leading BOM removed and all line endings folded to `\n`.
    ///
    /// Works over Unicode scalars rather than `Character`s so that a CRLF pair — which
    /// Swift renders as a single grapheme cluster — collapses to exactly one `\n`.
    public static func normalize(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(raw.unicodeScalars.count)

        var isFirst = true
        var previousWasCarriageReturn = false
        for scalar in raw.unicodeScalars {
            if isFirst {
                isFirst = false
                // Only a *leading* BOM is stripped; an interior U+FEFF is content.
                if scalar == byteOrderMark {
                    continue
                }
            }
            if scalar == carriageReturn {
                scalars.append(lineFeed)
                previousWasCarriageReturn = true
                continue
            }
            if scalar == lineFeed, previousWasCarriageReturn {
                // The `\n` half of a CRLF pair; the break was already emitted.
                previousWasCarriageReturn = false
                continue
            }
            previousWasCarriageReturn = false
            scalars.append(scalar)
        }
        return String(scalars)
    }
}
