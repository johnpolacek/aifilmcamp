import Foundation

/// Line-level Fountain syntax recognition (PHASE1_DESIGN §5.1).
///
/// Deliberately **internal**: the public contract of `FilmScript` is the list in Plan
/// 002 "Contracts (normative)", and the classifier is an implementation detail of
/// `FountainParser`. Every function here works on a *trimmed effective line* — the line
/// text with `[[ ]]` notes and `/* */` boneyard spans already excised (§5.1: excision
/// happens before classification) and surrounding whitespace removed.
///
/// The functions come in two families:
///
/// - `marker(in:)` recognizes the **forced / marker** syntaxes, which need no
///   surrounding blank lines and therefore also terminate an action or dialogue run.
/// - `isPrefixedHeading`, `isTransitionCandidate`, `isCueCandidate` recognize the
///   **context-sensitive** syntaxes; the caller supplies the blank-line context.
enum FountainLineClassifier {
    /// A syntax recognizable from the line alone.
    enum Marker: Equatable {
        /// `#` section: `depth` is the count of leading `#`, `title` the trimmed rest.
        case section(depth: Int, title: String)
        /// A line of three or more `=` (§5.1).
        case pageBreak(text: String)
        /// A line starting with a single `=` (§5.1); `text` is the rest, trimmed.
        case synopsis(text: String)
        /// One leading `.` not followed by another.
        case forcedHeading
        /// `> text <`; `text` is the interior, trimmed.
        case centered(text: String)
        /// `> text` without a trailing `<`; `text` is the rest, trimmed.
        case forcedTransition(text: String)
        /// `~lyric`; `text` is the rest, trimmed.
        case lyric(text: String)
        /// `@CUE` with a non-empty normalized name.
        case forcedCue
    }

    /// Heading prefixes (§5.1), longest first so `INT./EXT.` never matches as `INT.`.
    /// Mirrors `HeadingParser`'s table; the trailing `.` is matched separately because
    /// a prefix may be followed by either `.` or whitespace.
    static let headingPrefixes = ["INT./EXT", "INT/EXT", "I/E", "INT", "EXT", "EST"]

    // MARK: - Marker syntaxes

    static func marker(in trimmed: String) -> Marker? {
        guard let first = trimmed.first else { return nil }
        switch first {
        case "#":
            let depth = trimmed.prefix(while: { $0 == "#" }).count
            let title = String(trimmed.dropFirst(depth)).trimmingCharacters(in: .whitespaces)
            return .section(depth: depth, title: title)
        case "=":
            if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "=" }) {
                return .pageBreak(text: trimmed)
            }
            return .synopsis(text: String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        case ".":
            // `..` is not a forced heading; it falls through to action.
            guard !trimmed.hasPrefix("..") else { return nil }
            return .forcedHeading
        case ">":
            if trimmed.count >= 2, trimmed.hasSuffix("<") {
                let inner = trimmed.dropFirst().dropLast()
                return .centered(text: inner.trimmingCharacters(in: .whitespaces))
            }
            return .forcedTransition(text: String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        case "~":
            return .lyric(text: String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        case "@":
            // `@` with nothing that survives normalization (`@`, `@ ^`) names nobody, so
            // it is not a cue at all; returning `nil` lets it fall through to action.
            return CueNormalizer.normalize(trimmed).name.isEmpty ? nil : .forcedCue
        default:
            return nil
        }
    }

    // MARK: - Context-sensitive syntaxes

    /// A heading recognized by its prefix (§5.1). The caller must additionally require
    /// that the line is the first body line or is preceded by a blank line.
    static func isPrefixedHeading(_ trimmed: String) -> Bool {
        for token in headingPrefixes {
            guard trimmed.count > token.count,
                  trimmed.prefix(token.count).uppercased() == token
            else { continue }
            let next = trimmed[trimmed.index(trimmed.startIndex, offsetBy: token.count)]
            if next == "." || next.isWhitespace { return true }
        }
        return false
    }

    /// An unforced transition: an all-caps line ending in `TO:` (§5.1). The caller must
    /// additionally require a blank line before and a blank line (or end of text) after.
    static func isTransitionCandidate(_ trimmed: String) -> Bool {
        guard trimmed.hasSuffix("TO:") else { return false }
        guard trimmed.contains(where: { $0.isLetter }) else { return false }
        return !trimmed.contains(where: { $0.isLowercase })
    }

    /// An unforced character cue (§5.1). The caller must additionally require a blank
    /// line before, a non-blank line after, and that the line is neither a heading nor
    /// a transition (both are tested first by `FountainParser`).
    ///
    /// Rejected: a line ending in `:` (so `FADE IN:` followed by action is never a
    /// cue), a line with no letter at all (pure punctuation or digits), and any line
    /// carrying a lowercase letter outside trailing parenthesized extensions — except
    /// the interior of a **leading** `Mc`/`Mac` (`McKAY`, `MacLEOD`; `O'BRIEN` has no
    /// lowercase at all). The exception is anchored at the start of the cue exactly as
    /// §5.1 words it, so `DR. McKAY` is not a cue.
    static func isCueCandidate(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty, !trimmed.hasSuffix(":") else { return false }

        var body = trimmed
        if body.hasSuffix("^") {
            body = String(body.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        var core = body
        while core.hasSuffix(")"), let open = matchingOpenParenIndex(in: core) {
            core = String(core[core.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        }
        guard core.contains(where: { $0.isLetter }) else { return false }

        var rest = Substring(core)
        for prefix in ["Mac", "Mc"] where rest.hasPrefix(prefix) {
            rest = rest.dropFirst(prefix.count)
            break
        }
        return !rest.contains(where: { $0.isLowercase })
    }

    /// A parenthetical: a dialogue-block line that opens with `(` and closes with `)`.
    static func isParenthetical(_ trimmed: String) -> Bool {
        trimmed.count >= 2 && trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
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
}
