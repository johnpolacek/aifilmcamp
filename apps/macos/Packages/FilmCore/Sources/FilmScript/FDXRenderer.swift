import Foundation

/// Deterministic FDX → Fountain rendering (PHASE1_DESIGN §5.4).
///
/// The whole point of this file is that FDX never gets its own scene rules: the
/// paragraph list becomes Fountain text and `FountainParser.parse(_:format: .fdx)` does
/// the segmentation, so both formats obey one scene contract. Same paragraphs in →
/// byte-identical text out, always; nothing here reads the clock, the environment, a
/// dictionary's iteration order, or any global state.
///
/// ## Blank-line rule
///
/// §5.4 says "one blank line between paragraphs", and Fountain says a character cue is
/// only a cue when the line *after* it is non-blank. Both are honored by separating
/// **logical blocks** — not paragraphs — with exactly one blank line:
///
/// - A `Character` paragraph opens a **dialogue run**. Every immediately following
///   `Parenthetical` or `Dialogue` paragraph joins that run and is separated from the
///   previous line by a single `\n` — no blank line, so the cue is followed by a
///   non-blank line and the block parses as dialogue.
/// - The run ends at the first paragraph that is neither `Parenthetical` nor `Dialogue`
///   (a second `Character` inside a dual-dialogue block ends it too, which is exactly
///   what Fountain needs to see before a `^` cue).
/// - Every other paragraph boundary gets exactly one blank line (`\n\n`).
///
/// A `Parenthetical` or `Dialogue` paragraph with no open run is its own block; it
/// renders as action, which is the honest reading of an orphaned FDX paragraph.
///
/// ## Forcing markers
///
/// Forced `.`/`@`/`> ` markers are emitted **only when the text would not otherwise
/// parse as that element in the position it is rendered into** — the renderer already
/// guarantees the blank-line context, so the only questions left are the line's own
/// shape and, for a cue, whether a dialogue run actually follows it. A `Character`
/// paragraph with nothing to say after it therefore gets `@`: without it the line would
/// parse as action.
public enum FDXRenderer: Sendable {
    /// The synthetic `FDXParagraph.type` `FDXReader` tags `TitlePage/Content` paragraphs
    /// with. It is not an FDX type — `TitlePage` paragraphs carry no semantic type at
    /// all (§5.4) — it is how the reader keeps one ordered paragraph list while the
    /// renderer still routes the title page out of `sourceText`.
    static let titlePageType = "__FDXTitlePage"

    /// Renders the paragraph list into Fountain text, its warnings, and the title-page lines.
    public nonisolated static func render(
        _ paragraphs: [FDXParagraph]
    ) -> (text: String, warnings: [ParseWarning], titlePageLines: [String]) {
        var titlePageLines: [String] = []
        var body: [FDXParagraph] = []
        for paragraph in paragraphs {
            if paragraph.type == titlePageType {
                // "Non-empty lines, in order" (§5.4): a `TitlePage` is positional free
                // text and mostly spacer paragraphs, so blank lines carry nothing.
                for line in paragraph.text.components(separatedBy: "\n")
                where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    titlePageLines.append(line)
                }
                continue
            }
            // Empty paragraphs are dropped from the body (§5.4). Filtering here — before
            // any separator is chosen — is what keeps a spacer paragraph between a cue
            // and its dialogue from breaking the run.
            guard !paragraph.text.isEmpty else { continue }
            body.append(paragraph)
        }

        var text = ""
        var warnings: [ParseWarning] = []
        var inDialogueRun = false

        for (position, paragraph) in body.enumerated() {
            let kind = Kind(type: paragraph.type)
            let continuesRun = inDialogueRun && (kind == .parenthetical || kind == .dialogue)

            if position > 0 {
                text += continuesRun ? "\n" : "\n\n"
            }
            let blockStart = text.utf16.count

            let followedByDialogue: Bool = {
                guard position + 1 < body.count else { return false }
                let next = Kind(type: body[position + 1].type)
                return next == .parenthetical || next == .dialogue
            }()
            text += line(for: paragraph, kind: kind, followedByDialogue: followedByDialogue)

            if kind == .unsupported {
                warnings.append(
                    ParseWarning(
                        code: .unsupportedParagraphType,
                        message: "Unsupported FDX paragraph type \"\(paragraph.type)\"; rendered as action.",
                        range: UTF16Range(start: blockStart, end: text.utf16.count)
                    )
                )
            }

            switch kind {
            case .character: inDialogueRun = true
            case .parenthetical, .dialogue: inDialogueRun = continuesRun
            default: inDialogueRun = false
            }
        }

        return (text, warnings, titlePageLines)
    }

    // MARK: - Paragraph types (§5.4)

    /// What a `Paragraph@Type` renders as. Lookup is case-insensitive, which is also how
    /// `End of Act` and `End Of Act` — both observed in the wild — become one entry.
    enum Kind: Equatable {
        case sceneHeading
        case action
        case character
        case parenthetical
        case dialogue
        case transition
        case lyric
        case section
        case note
        /// Rendered as action, plus an `unsupportedParagraphType` warning; never dropped.
        case unsupported

        init(type: String) {
            switch type.lowercased() {
            case "scene heading": self = .sceneHeading
            case "action", "shot", "general", "cast list",
                 "end of act", "act info", "show/ep. title": self = .action
            case "character": self = .character
            case "parenthetical": self = .parenthetical
            case "dialogue": self = .dialogue
            case "transition": self = .transition
            case "lyrics": self = .lyric
            case "sequence", "new act", "cold opening": self = .section
            case "summary", "note",
                 "outline 1", "outline 2", "outline 3", "outline 4", "outline body": self = .note
            default: self = .unsupported
            }
        }
    }

    // MARK: - One paragraph

    private static func line(for paragraph: FDXParagraph, kind: Kind, followedByDialogue: Bool) -> String {
        let text = paragraph.text
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        switch kind {
        case .sceneHeading:
            var out = needsForcedHeadingDot(trimmed) ? "." + text : text
            if let number = paragraph.number, !number.isEmpty {
                out += " #\(number)#"
            }
            return out

        case .character:
            // `@` whenever the line would not parse as a cue where it lands: either its
            // own shape disqualifies it, or nothing follows it to be dialogue.
            let parsesAsCue = FountainLineClassifier.isCueCandidate(trimmed) && followedByDialogue
            let marker = parsesAsCue ? "" : "@"
            return marker + text + (paragraph.isDualSecond ? " ^" : "")

        case .parenthetical:
            // A parenthetical only reads as one when it is wrapped; FDX stores some
            // templates' parentheticals without the parentheses.
            return FountainLineClassifier.isParenthetical(trimmed) ? text : "(" + text + ")"

        case .transition:
            return FountainLineClassifier.isTransitionCandidate(trimmed) ? text : "> " + text

        case .lyric:
            return trimmed.hasPrefix("~") ? text : "~" + text

        case .section:
            return trimmed.hasPrefix("#") ? text : "# " + text

        case .note:
            // `]]` inside the note would terminate it early and leak the rest into the
            // scene text, so it is deterministically spaced apart. Nothing else is
            // escaped: Fountain notes have no escape syntax.
            return "[[" + text.replacingOccurrences(of: "]]", with: "] ]") + "]]"

        case .action, .dialogue, .unsupported:
            return text
        }
    }

    /// A forced `.` is needed unless the line already parses as a heading — either by a
    /// `INT.`/`EXT.`/… prefix or because it is already forced with a single leading dot.
    private static func needsForcedHeadingDot(_ trimmed: String) -> Bool {
        if FountainLineClassifier.isPrefixedHeading(trimmed) { return false }
        if trimmed.hasPrefix("."), !trimmed.hasPrefix("..") { return false }
        return true
    }
}
