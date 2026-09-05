import Foundation

/// Heading decomposition (PHASE1_DESIGN §5.2).
///
/// Best-effort and purely structural: everything is stored, nothing is inferred.
/// Prefix matching is **case-insensitive** because §7.1 requires a lowercase heading
/// (`int. kitchen - day`) to parse exactly like its uppercase twin.
public enum HeadingParser: Sendable {
    /// The known time-of-day tokens (§5.2), compared case-insensitively.
    ///
    /// Comparison uppercases the trimmed trailing segment before lookup, so lowercase
    /// headings match; the stored `timeOfDay` is always the segment *as authored*.
    public static let timeOfDayTokens: Set<String> = [
        "DAY",
        "NIGHT",
        "DAWN",
        "DUSK",
        "MORNING",
        "AFTERNOON",
        "EVENING",
        "LATER",
        "CONTINUOUS",
        "SAME",
        "MOMENTS LATER",
        "SUNSET",
        "SUNRISE",
        "MAGIC HOUR",
    ]

    /// Heading prefixes, longest first so `INT./EXT.` never matches as bare `INT.`.
    ///
    /// Each token must be followed by `.` or whitespace (§5.1); a following `.` is
    /// consumed as part of the prefix.
    private static let prefixes: [(token: String, intExt: IntExt)] = [
        ("INT./EXT", .intExt),
        ("INT/EXT", .intExt),
        ("I/E", .intExt),
        ("INT", .int),
        ("EXT", .ext),
        // `EST.` is exterior (§5.1).
        ("EST", .ext),
    ]

    private static let timeSeparators = [" - ", " \u{2013} ", " \u{2014} "]

    /// Decomposes one heading line — forced (`.`) or prefixed, with or without a
    /// trailing `#12A#` scene number — into its stored parts.
    public static func parse(_ headingLine: String) -> ParsedHeading {
        var line = headingLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // A forced heading is one leading `.` not followed by another `.`; the dot is
        // dropped from `heading`. Whether the forced text also carries a prefix is what
        // decides `intExt`, so no separate "forced" flag is needed past this point.
        if line.hasPrefix("."), !line.hasPrefix("..") {
            line = String(line.dropFirst())
        }

        let (withoutNumber, sceneNumber) = splitSceneNumber(line)
        let heading = withoutNumber.trimmingCharacters(in: .whitespaces)

        // A forced heading is `.unknown` unless its text after the dot starts with a
        // prefix — which `splitPrefix` decides for forced and unforced lines alike.
        let (intExt, remainder) = splitPrefix(heading)
        let (locationText, timeOfDay) = splitTimeOfDay(remainder)
        let isOmitted = locationText.uppercased() == "OMITTED"

        return ParsedHeading(
            heading: heading,
            intExt: intExt,
            locationText: locationText,
            timeOfDay: timeOfDay,
            sceneNumber: sceneNumber,
            isOmitted: isOmitted
        )
    }

    // MARK: - Pieces

    /// Splits a trailing `#…#` scene number off the line. The number is the content
    /// between the final `#` and the nearest preceding `#`; it may not contain `#` and
    /// may not be empty.
    private static func splitSceneNumber(_ line: String) -> (String, String?) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("#"), trimmed.count >= 3 else { return (trimmed, nil) }
        let body = trimmed.dropLast()
        guard let openIndex = body.lastIndex(of: "#") else { return (trimmed, nil) }
        let number = String(body[body.index(after: openIndex)...])
        guard !number.isEmpty else { return (trimmed, nil) }
        let head = String(body[body.startIndex..<openIndex])
        return (head.trimmingCharacters(in: .whitespaces), number)
    }

    /// Matches a case-insensitive heading prefix and returns the rest of the heading.
    private static func splitPrefix(_ heading: String) -> (IntExt, String) {
        for prefix in prefixes {
            guard heading.count > prefix.token.count,
                  heading.prefix(prefix.token.count).uppercased() == prefix.token
            else { continue }
            let afterToken = heading.index(heading.startIndex, offsetBy: prefix.token.count)
            let next = heading[afterToken]
            let rest: Substring
            if next == "." {
                rest = heading[heading.index(after: afterToken)...]
            } else if next.isWhitespace {
                rest = heading[afterToken...]
            } else {
                continue
            }
            return (prefix.intExt, rest.trimmingCharacters(in: .whitespaces))
        }
        // No prefix: forced headings and `UNTITLED`-style lines keep the whole text.
        return (.unknown, heading.trimmingCharacters(in: .whitespaces))
    }

    /// Splits the last ` - ` / ` – ` / ` — ` segment off when it names a time of day.
    private static func splitTimeOfDay(_ remainder: String) -> (locationText: String, timeOfDay: String) {
        guard let separator = lastSeparatorRange(in: remainder) else {
            return (remainder, "")
        }
        let tail = remainder[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        guard isTimeOfDay(tail) else { return (remainder, "") }
        let head = String(remainder[remainder.startIndex..<separator.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        // `timeOfDay` stores the full segment as authored, e.g. `NIGHT (LATER)`.
        return (head, tail)
    }

    private static func lastSeparatorRange(in text: String) -> Range<String.Index>? {
        var best: Range<String.Index>?
        for separator in timeSeparators {
            if let found = text.range(of: separator, options: .backwards) {
                if let current = best {
                    if found.lowerBound > current.lowerBound { best = found }
                } else {
                    best = found
                }
            }
        }
        return best
    }

    /// A segment is a time of day when it — or the text left after peeling ONE trailing
    /// parenthesized group — matches a token, compared uppercased.
    private static func isTimeOfDay(_ segment: String) -> Bool {
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        if timeOfDayTokens.contains(trimmed.uppercased()) { return true }
        guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "(") else { return false }
        let head = String(trimmed[trimmed.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        return timeOfDayTokens.contains(head.uppercased())
    }
}
