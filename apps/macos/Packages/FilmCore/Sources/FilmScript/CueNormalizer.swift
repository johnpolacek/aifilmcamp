import Foundation

/// Character-cue normalization (PHASE1_DESIGN §5.1, §5.3).
///
/// `SARAH`, `SARAH (V.O.)`, `SARAH (CONT'D)`, `SARAH (V.O.) (CONT'D)`, `@Sarah`, and
/// `SARAH ^` all normalize to `SARAH`. It never merges different names: `SARAH` and
/// `SARAH MORGAN` stay distinct.
public enum CueNormalizer: Sendable {
    /// Apostrophe variants folded to `'` inside extensions, so `(CONT’D)` and
    /// `(CONT'D)` are the same extension.
    private static let apostrophes: Set<Character> = ["\u{2019}", "\u{2018}", "\u{02BC}"]
    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":"]

    /// Splits a raw cue line into its normalized name and its extensions.
    ///
    /// Extensions are uppercased, stripped of parentheses, with apostrophes folded, and
    /// kept in document (left-to-right) order.
    public static func normalize(_ raw: String) -> (name: String, extensions: [String]) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Forced-cue marker.
        if text.hasPrefix("@") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        // Dual-dialogue marker; `isDual` is recorded by the caller, not here.
        if text.hasSuffix("^") {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        var extensions: [String] = []
        while true {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix(")"), let open = matchingOpenParenIndex(in: trimmed) else {
                text = trimmed
                break
            }
            let inner = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
            // Peeling right-to-left, so prepend to keep document order.
            extensions.insert(normalizeExtension(String(inner)), at: 0)
            text = String(trimmed[trimmed.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        }

        var name = collapseWhitespace(text).uppercased()
        while let last = name.last, trailingPunctuation.contains(last) {
            name = String(name.dropLast())
        }
        name = name.trimmingCharacters(in: .whitespaces)
        return (name, extensions)
    }

    // MARK: - Pieces

    /// Index of the `(` that opens the final `)` of `text`, honoring nesting.
    private static func matchingOpenParenIndex(in text: String) -> String.Index? {
        var depth = 0
        var index = text.endIndex
        while index > text.startIndex {
            index = text.index(before: index)
            let character = text[index]
            if character == ")" {
                depth += 1
            } else if character == "(" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func normalizeExtension(_ raw: String) -> String {
        var result = ""
        for character in raw {
            if character == "(" || character == ")" { continue }
            result.append(apostrophes.contains(character) ? "'" : character)
        }
        return collapseWhitespace(result).uppercased()
    }

    private static func collapseWhitespace(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
