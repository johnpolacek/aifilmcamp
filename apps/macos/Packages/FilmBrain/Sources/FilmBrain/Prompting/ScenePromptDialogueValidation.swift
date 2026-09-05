import FilmCore
import Foundation

/// Final Seedance dialogue checks across the entire ordered card set. Timing ranges
/// have already passed ScenePromptValidator; prose feasibility remains an AI review.
enum ScenePromptDialogueValidation {
    private static let spokenLine = try! NSRegularExpression(
        pattern: #"^(.+?)\s+says\b[^{}]*:\s*\{([^{}\r\n]+)\}\s*$"#,
        options: [.caseInsensitive]
    )
    private static let unbracedSpeech = try! NSRegularExpression(
        pattern: #"^[^{}]+\bsays\b[^{}]*:\s*.+$"#,
        options: [.caseInsensitive]
    )
    private static let sectionHeading = try! NSRegularExpression(pattern: #"^\[[^\[\]]+\]$"#)
    private static let sentenceBoundary = try! NSRegularExpression(pattern: #"[.!?][ \t]+"#)
    private static let abbreviationEnding = try! NSRegularExpression(
        pattern: #"\b(?:Mr|Mrs|Ms|Mx|Dr|Prof|Sr|Jr|St|Capt|Cpt|Lt|Col|Gen|Sgt|Rev|[A-Z])\.$"#,
        options: [.caseInsensitive]
    )
    // Only delivery/source annotations, never arbitrary parentheticals or a
    // substring name match: "Alex (Sam)" must not pass as Alex.
    private static let speakerAnnotation = try! NSRegularExpression(
        pattern: #"\s*\(\s*(?:O\.?\s*S\.?|O\.?\s*C\.?|V\.?\s*O\.?|CONT['’]D|CONTINUED|OFF[- ]SCREEN|OFF[- ]CAMERA|ON[- ]SCREEN|VOICE[- ]?OVER|BROADCAST|RADIO|TV|PHONE|TELEPHONE|FILTERED)\s*\)\s*$"#,
        options: [.caseInsensitive]
    )

    private struct Occurrence {
        let dialogue: ScenePromptDialogueLine
        let card: Int
        let stage: Int
    }

    private struct Stage {
        let number: Int
        let duration: Double
        var spokenWords = 0
    }

    static func validate(
        _ result: ScenePromptResult,
        source: [ScenePromptDialogueLine]
    ) throws -> ScenePromptResult {
        var occurrences: [Occurrence] = []
        var cards: [ScenePromptResult.Card] = []
        let sourceSpeakers = Set(source.map(\.speaker))
        for (cardIndex, card) in result.cards.enumerated() {
            var stages: [Stage] = []
            var activeStage: Int?
            var bodyLines: [String] = []
            for rawLine in card.body.components(separatedBy: .newlines) {
                var line = rawLine.trimmingCharacters(in: .whitespaces)
                if activeStage != nil,
                   let separated = separateStagingProse(in: line, speakers: sourceSpeakers) {
                    bodyLines.append(separated.prose)
                    bodyLines.append(separated.speech)
                    line = separated.speech
                } else {
                    bodyLines.append(rawLine)
                }
                let range = NSRange(line.startIndex..., in: line)
                if let timing = ScenePromptValidator.stageTiming(in: line) {
                    stages.append(.init(number: timing.number, duration: timing.duration))
                    activeStage = stages.count - 1
                    continue
                }
                if sectionHeading.firstMatch(in: line, range: range) != nil {
                    activeStage = nil
                    continue
                }

                guard line.contains("{") || line.contains("}") else {
                    if unbracedSpeech.firstMatch(in: line, range: range) != nil {
                        throw reject(.invalidDialogueFormat)
                    }
                    continue
                }
                guard let match = spokenLine.firstMatch(in: line, range: range),
                      let speaker = capture(1, in: line, match: match),
                      let text = capture(2, in: line, match: match),
                      !normalized(text).isEmpty else {
                    throw reject(.invalidDialogueFormat)
                }
                guard let activeStage else { throw reject(.dialogueOutsideStage) }
                occurrences.append(.init(
                    dialogue: .init(speaker: normalized(speaker), text: normalized(text)),
                    card: cardIndex + 1,
                    stage: stages[activeStage].number
                ))
                stages[activeStage].spokenWords += text.split(whereSeparator: \.isWhitespace).count
            }

            // Advisory only: 3.5 words/second is intentionally more permissive than
            // the writer's ~2.4 planning baseline. It flags clear crowding without
            // pretending to predict acting, pauses, simultaneous motion, or reading.
            let warnings = stages.compactMap { stage -> String? in
                guard Double(stage.spokenWords) > stage.duration * 3.5 else { return nil }
                let seconds = stage.duration.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
                return "Pacing warning: Stage \(stage.number) allocates \(seconds) seconds "
                    + "to \(stage.spokenWords) spoken words and may be crowded. "
                    + "Review delivery or give this beat more time; this is an estimate."
            }
            let guidance = ([card.guidance] + warnings.filter { !card.guidance.contains($0) })
                .filter { !$0.isEmpty }.joined(separator: "\n")
            cards.append(.init(
                title: card.title, body: bodyLines.joined(separator: "\n"), guidance: guidance,
                settings: card.settings, references: card.references
            ))
        }

        // Compare occurrences, never a Set or a first matching phrase: a repeated
        // source line (even with a different speaker) must survive in the right place.
        guard occurrences.count == source.count else { throw reject(.dialogueSourceMismatch) }
        for (index, pair) in zip(occurrences, source).enumerated() {
            let (occurrence, expected) = pair
            let actual = occurrence.dialogue
            guard actual.text == normalized(expected.text) else {
                throw reject(.dialogueSourceMismatch)
            }
            guard speakerMatches(actual.speaker, expected: expected.speaker) else {
                let detail = "Card \(occurrence.card), Stage \(occurrence.stage), dialogue occurrence \(index + 1): "
                    + "expected speaker “\(diagnosticName(expected.speaker))”, "
                    + "but found “\(diagnosticName(actual.speaker))” before “says”. "
                    + "Use the canonical character name before “says” and put location or delivery "
                    + "directions after it. Off-screen and broadcast speakers may remain unseen. "
                    + "Generate again; no screenplay rewrite is needed to correct attribution."
                throw StructuredResultValidator.semanticViolation(
                    ScenePromptSemanticCode.missingDialogueSpeaker.rawValue + ": " + detail
                )
            }
        }
        return .init(schemaVersion: result.schemaVersion, cards: cards)
    }

    private static func normalized(_ text: String) -> String {
        // Line wrapping may change; words, punctuation, and capitalization may not.
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Repair only a missing newline after a complete staging sentence. The
    /// remaining attribution must exactly match a source speaker (plus allowed
    /// annotations). Never infer a speaker from a mention or replace a name with
    /// the expected speaker; the ordered source comparison still runs afterward.
    private static func separateStagingProse(
        in line: String,
        speakers: Set<String>
    ) -> (prose: String, speech: String)? {
        guard let match = spokenLine.firstMatch(
            in: line, range: NSRange(line.startIndex..., in: line)
        ), let attribution = capture(1, in: line, match: match),
           !speakers.contains(where: { speakerMatches(attribution, expected: $0) })
        else { return nil }

        for boundary in sentenceBoundary.matches(
            in: attribution, range: NSRange(attribution.startIndex..., in: attribution)
        ).reversed() {
            let offset = NSMaxRange(boundary.range)
            let split = String.Index(utf16Offset: offset, in: attribution)
            let prose = String(attribution[..<split]).trimmingCharacters(in: .whitespaces)
            // A title or initial is not a staging sentence: "Dr. Pundit" must
            // not become "Pundit" unless that full name is itself canonical.
            guard abbreviationEnding.firstMatch(
                in: prose, range: NSRange(prose.startIndex..., in: prose)
            ) == nil else { continue }
            let candidate = String(attribution[split...])
            guard speakers.contains(where: { speakerMatches(candidate, expected: $0) }) else {
                continue
            }
            let speechStart = String.Index(utf16Offset: offset, in: line)
            return (prose, String(line[speechStart...]))
        }
        return nil
    }

    private static func speakerMatches(_ actual: String, expected: String) -> Bool {
        let expected = normalized(expected)
        var candidate = normalized(actual)
        while true {
            // Check first so a canonical name containing parentheses is preserved.
            if candidate.caseInsensitiveCompare(expected) == .orderedSame { return true }
            guard let match = speakerAnnotation.firstMatch(
                in: candidate, range: NSRange(candidate.startIndex..., in: candidate)
            ), let range = Range(match.range, in: candidate) else { return false }
            candidate = normalized(String(candidate[..<range.lowerBound]))
        }
    }

    private static func diagnosticName(_ name: String) -> String {
        // Bound untrusted labels and exclude invisible controls from UI/log copy.
        let visible = name.unicodeScalars.filter {
            $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
        }
        let text = normalized(String(String.UnicodeScalarView(visible)))
        return String(text.prefix(100)) + (text.count > 100 ? "…" : "")
    }

    private static func capture(_ group: Int, in text: String, match: NSTextCheckingResult) -> String? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private static func reject(_ code: ScenePromptSemanticCode) -> StructuredValidationFailure {
        StructuredResultValidator.semanticViolation(code.rawValue)
    }
}
