import Foundation

/// The deterministic display-name rule (PHASE1_DESIGN §3.4).
///
/// `entities.name` is a display name; parser-created entities get the title-cased form
/// of a cue or heading location text while the raw text stays an alias. Roman numerals,
/// apostrophes, hyphens, `Mc`/`Mac`, and authored interior capitals are preserved.
/// Uppercasing and lowercasing are locale-independent (`uppercased()`/`lowercased()`),
/// so `McKAY` normalizes to `McKay` on every host.
public enum DisplayCase: Sendable {
    /// Characters that split a whitespace token into parts; the delimiter is kept.
    private static let delimiters: Set<Character> = ["-", "'", ".", "/"]
    private static let romanLetters: Set<Character> = ["I", "V", "X", "L"]

    /// Roman numerals of length ≤ 4 built only from `I V X L` — i.e. 1...89 rendered in
    /// strict form. Membership *is* the "strict roman-numeral pattern" of rule 2:
    /// `II`, `XIV`, `LIV`, and `XL` qualify; `IIII` does not (it is not strict), so it
    /// falls through to rule 5 and becomes `Iiii`.
    private static let romanNumerals: Set<String> = {
        var numerals: Set<String> = []
        let table: [(Int, String)] = [(50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        for value in 1...89 {
            var remaining = value
            var text = ""
            for (amount, symbol) in table {
                while remaining >= amount {
                    text += symbol
                    remaining -= amount
                }
            }
            if text.count <= 4, text.allSatisfy({ romanLetters.contains($0) }) {
                numerals.insert(text)
            }
        }
        return numerals
    }()

    /// Returns the display form of `raw`.
    ///
    /// Whitespace runs collapse to one space and the result is trimmed; each whitespace
    /// token splits on `-`, `'`, `.`, `/` keeping the delimiters; each part takes the
    /// first matching rule of §3.4.
    public static func titleCased(_ raw: String) -> String {
        let tokens = raw.split(whereSeparator: { $0.isWhitespace })
        return tokens.map { titleCaseToken(String($0)) }.joined(separator: " ")
    }

    // MARK: - Pieces

    private static func titleCaseToken(_ token: String) -> String {
        var result = ""
        var part = ""
        var previousDelimiter: Character?

        func flush() {
            result += cased(part, afterApostrophe: previousDelimiter == "'")
            part = ""
        }

        for character in token {
            if delimiters.contains(character) {
                flush()
                result.append(character)
                previousDelimiter = character
            } else {
                part.append(character)
            }
        }
        flush()
        return result
    }

    /// Applies §3.4's numbered rules to one part.
    ///
    /// The apostrophe rule **overrides** them for the part directly after a `'`:
    /// a single letter is lowercased (`SARAH'S` → `Sarah's`), anything longer is
    /// title-cased outright (`O'BRIEN` → `O'Brien`, `O'brien` → `O'Brien`).
    private static func cased(_ part: String, afterApostrophe: Bool) -> String {
        if part.isEmpty { return part }
        if afterApostrophe {
            if part.count == 1, part.first?.isCased == true { return part.lowercased() }
            if part.contains(where: { $0.isCased }) { return firstUpperRestLower(part) }
            return part
        }
        // (1) no cased letter → unchanged (`#2`, `&`).
        if !part.contains(where: { $0.isCased }) { return part }
        // (2) all-uppercase, length ≤ 4, only `I V X L`, strict roman → unchanged.
        if part.count <= 4, part.allSatisfy({ romanLetters.contains($0) }), romanNumerals.contains(part) {
            return part
        }
        // (3) `MC`/`Mc` or `MAC`/`Mac` prefix with ≥ 3 letters → `Mc`/`Mac` + remainder.
        if let scottish = scottishPrefixed(part) { return scottish }
        // (4) a lowercase letter at index ≥ 1 → unchanged, preserving `DeVries`.
        if part.dropFirst().contains(where: { $0.isLowercase }) { return part }
        // (5) otherwise first letter uppercased, rest lowercased.
        return firstUpperRestLower(part)
    }

    private static func scottishPrefixed(_ part: String) -> String? {
        guard part.count >= 3 else { return nil }
        for (token, replacement) in [("MAC", "Mac"), ("MC", "Mc")] {
            guard part.prefix(token.count).uppercased() == token else { continue }
            let remainder = String(part.dropFirst(token.count))
            return replacement + cased(remainder, afterApostrophe: false)
        }
        return nil
    }

    /// Uppercases the first cased character and lowercases every other one.
    private static func firstUpperRestLower(_ part: String) -> String {
        var result = ""
        var seenCased = false
        for character in part {
            if !seenCased, character.isCased {
                seenCased = true
                result += String(character).uppercased()
            } else {
                result += String(character).lowercased()
            }
        }
        return result
    }
}
