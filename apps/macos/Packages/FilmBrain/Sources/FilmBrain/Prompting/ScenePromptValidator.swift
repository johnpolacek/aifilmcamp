import FilmCore
import Foundation

public enum ScenePromptSemanticCode: String, Equatable, Sendable {
    case wrongSchemaVersion = "wrong_schema_version"
    case emptyPromptSet = "empty_prompt_set"
    case tooManyCards = "too_many_cards"
    case emptyPromptBody = "empty_prompt_body"
    case oversizedPromptSet = "oversized_prompt_set"
    case controlCharacters = "control_characters"
    case referenceMappingGap = "reference_mapping_gap"
    case duplicateReferenceMapping = "duplicate_reference_mapping"
    case unknownReferenceSource = "unknown_reference_source"
    case missingReferenceDesignator = "missing_reference_designator"
    case unknownReferenceDesignator = "unknown_reference_designator"
    case bulkReferenceStatement = "bulk_reference_statement"
    case missingReferenceRole = "missing_reference_role"
    case missingReferenceFidelity = "missing_reference_fidelity"
    case missingReferenceExclusion = "missing_reference_exclusion"
    case ageWritten = "age_written"
    case invalidDuration = "invalid_duration"
    case invalidAspectRatio = "invalid_aspect_ratio"
    case invalidResolution = "invalid_resolution"
    case arbitraryCameraMeasurement = "arbitrary_camera_measurement"
    case formattedSoundCue = "formatted_sound_cue"
    case escapedAngleMarkup = "escaped_angle_markup"
    case qualityBoilerplate = "quality_boilerplate"
    case missingTimingPlan = "missing_timing_plan"
    case invalidTimingPlan = "invalid_timing_plan"
    case missingDialogueSpeaker = "missing_dialogue_speaker"
    case invalidDialogueFormat = "invalid_dialogue_format"
    case dialogueOutsideStage = "dialogue_outside_stage"
    case dialogueSourceMismatch = "dialogue_source_mismatch"
    case creativeDirectionNotApplied = "creative_direction_not_applied"
}

/// Version-two validation gives every card its own dense `@Image N` namespace.
public struct ScenePromptValidator: Sendable {
    public static let version = 5
    static let maximumCards = 32
    static let maximumCombinedBodyBytes = 64 * 1024

    private let structural = StructuredResultValidator()
    private let input: ScenePromptInput
    private let sourceDialogue: [ScenePromptDialogueLine]
    private let profile: TargetProfile?
    private let enforcesQualityContract: Bool

    static let agePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"\b\d{1,3}[-\s]year[s]?[-\s]old\b"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"\bage[d]?\s*[:=]?\s*\d{1,3}\b"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"\b\d{1,3}\s*y\.?o\.?\b"#, options: [.caseInsensitive]),
    ]
    static let designatorPattern = try! NSRegularExpression(pattern: #"@Image\s*(\d+)"#)
    static let arbitraryCameraMeasurementPattern = try! NSRegularExpression(
        pattern: #"\b\d{1,3}\s*(?:°|degrees?)\s*(?:diagonal\s+)?(?:field\s+of\s+view|fov)\b"#,
        options: [.caseInsensitive]
    )
    static let formattedSoundCuePattern = try! NSRegularExpression(
        pattern: #"(?:\\)?<\s*([A-Z][A-Z0-9 .!?_-]{1,30})\s*>"#
    )
    static let totalDurationPattern = try! NSRegularExpression(
        pattern: #"(?im)^Total duration:[ \t]*([0-9]+(?:\.[0-9]+)?)[ \t]*seconds?\.[ \t]*$"#
    )
    static let stageTimingPattern = try! NSRegularExpression(
        pattern: #"(?im)^\[Stage[ \t]+([0-9]+)[ \t]*[—–-][ \t]*([0-9]+(?:\.[0-9]+)?)[ \t]*[—–-][ \t]*([0-9]+(?:\.[0-9]+)?)[ \t]+seconds?\][ \t]*$"#
    )
    private static let stageHeadingPattern = try! NSRegularExpression(
        pattern: #"(?i)^\[Stage\b"#
    )

    struct StageTiming {
        let number: Int
        let start: Double
        let end: Double
        var duration: Double { end - start }
    }

    /// Shared by continuity validation and dialogue pacing so fractional stages
    /// cannot be accepted by one check and silently skipped by the other.
    static func stageTiming(in line: String) -> StageTiming? {
        guard let match = stageTimingPattern.firstMatch(
            in: line, range: NSRange(line.startIndex..., in: line)
        ), let number = captureInt(1, match: match, text: line),
           let start = captureSeconds(2, match: match, text: line),
           let end = captureSeconds(3, match: match, text: line)
        else { return nil }
        return StageTiming(number: number, start: start, end: end)
    }
    static let forbiddenQualityBoilerplate = [
        "one action per stage",
        "sharp focus throughout",
        "the set contains only the referenced",
    ]
    static let qualityBoilerplateRepairs = [
        ("one action per stage", "one primary visible change in each timed beat"),
        ("sharp focus throughout", "keep the primary subject clearly legible"),
        ("the set contains only the referenced", "preserve the referenced"),
    ]
    static let genericFillerRepairs = [
        (
            "Dozens of analysts work tensely at their stations. Agents and analysts remain active amid overlapping voices throughout.",
            "Dozens of analysts and agents work tensely at separate stations throughout."
        ),
        (
            "is the only speaking face for the line; other visible faces keep lips at rest",
            "is the only clearly visible speaking face. Other featured faces keep lips at rest; subdued overlapping voices come from off-camera or indistinct background personnel"
        ),
        (
            "is the only speaking face; every other visible face listens or works with lips at rest",
            "is the only clearly visible speaking face; other featured faces keep lips at rest while indistinct background personnel continue working"
        ),
        (
            "Anatomically correct, all limbs visible and naturally positioned.",
            "Maintain anatomically coherent visible features, natural posture, and stable facial articulation."
        ),
        ("closes the mouth", "settles with lips closed"),
        ("It is daytime despite the absence of windows.", ""),
        ("Agents are FBI personnel working alongside the analysts.", ""),
        ("Populate the room only with", "Populate the room with"),
        ("maintaining distinct body separation and ", ""),
        ("motion smooth and fluid", "motion natural"),
        ("smooth and fluid human motion", "natural human motion"),
    ]

    public init(input: ScenePromptInput, enforcesQualityContract: Bool = false) {
        self.input = input
        self.sourceDialogue = ScenePromptDialogue.lines(in: input)
        self.profile = TargetProfileCatalog.profile(id: input.targetProfile.id)
        self.enforcesQualityContract = enforcesQualityContract
    }

    public func validate(resultFileAt url: URL) throws -> ScenePromptResult {
        let data = try structural.validatedData(resultFileAt: url, schemaURL: ScenePromptSchema.url)
        return try validate(data: data)
    }

    public func validate(data: Data) throws -> ScenePromptResult {
        try structural.validate(data: data, schemaURL: ScenePromptSchema.url)
        let decoded = try JSONDecoder().decode(ScenePromptResult.self, from: data)
        let result = enforcesQualityContract
            ? repairObjectiveQualityFormatting(in: decoded)
            : decoded
        guard result.schemaVersion == ScenePromptSchema.version else {
            throw Self.reject(.wrongSchemaVersion)
        }
        guard !result.cards.isEmpty else { throw Self.reject(.emptyPromptSet) }
        guard result.cards.count <= Self.maximumCards else { throw Self.reject(.tooManyCards) }
        guard result.cards.reduce(0, { $0 + $1.body.utf8.count }) <= Self.maximumCombinedBodyBytes else {
            throw Self.reject(.oversizedPromptSet)
        }
        for card in result.cards { try validate(card: card) }
        if enforcesQualityContract {
            try validateCreativeDirection(
                in: result.cards.map(\.body).joined(separator: "\n")
            )
        }
        if enforcesQualityContract, profile?.id == TargetProfileCatalog.seedance2_5.id {
            return try ScenePromptDialogueValidation.validate(result, source: sourceDialogue)
        }
        return result
    }

    /// Repairs narrow, unambiguous wording mistakes before the final quality contract
    /// runs. Unsupported numeric FOV phrases become an ordinary qualitative direction,
    /// sound effects wrapped like pseudo-tags (`<CLICK.>` or `\<CLICK.>`) are unwrapped,
    /// and known stock boilerplate becomes useful generation language. Other numeric
    /// prose and angle-bracket content remain untouched for normal validation.
    private func repairObjectiveQualityFormatting(
        in result: ScenePromptResult
    ) -> ScenePromptResult {
        ScenePromptResult(
            schemaVersion: result.schemaVersion,
            cards: result.cards.map { card in
                let cleanBody = card.body
                    .replacingOccurrences(of: "&#x20;", with: " ")
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: "\n")
                // Formatting repairs must never rewrite source dialogue. Even a
                // forbidden boilerplate phrase may legitimately be spoken in a script.
                let conciseBody = cleanBody.components(separatedBy: .newlines).map { line in
                    guard !line.contains("{"), !line.contains("}") else { return line }
                    let withoutMeasurement = Self.arbitraryCameraMeasurementPattern.stringByReplacingMatches(
                        in: line,
                        range: NSRange(line.startIndex..., in: line),
                        withTemplate: "natural field of view"
                    )
                    let body = Self.formattedSoundCuePattern.stringByReplacingMatches(
                        in: withoutMeasurement,
                        range: NSRange(withoutMeasurement.startIndex..., in: withoutMeasurement),
                        withTemplate: "$1"
                    )
                    return (Self.qualityBoilerplateRepairs + Self.genericFillerRepairs)
                        .reduce(body) { partial, repair in
                            partial.replacingOccurrences(
                                of: repair.0, with: repair.1, options: [.caseInsensitive]
                            )
                        }
                }.joined(separator: "\n")
                let goalSafeBody = repairUnsupportedDialogueSummary(in: conciseBody)
                let audioSafeBody = ensureMusicDirection(in: goalSafeBody)
                let identitySafeBody = repairCharacterIdentityPronouns(
                    in: audioSafeBody,
                    card: card
                )
                return .init(
                    title: card.title,
                    body: identitySafeBody,
                    guidance: card.guidance,
                    settings: card.settings,
                    references: card.references
                )
            }
        )
    }

    /// Dialogue content belongs verbatim in its timed stage. If a generated goal turns an
    /// otherwise unidentified pronoun into an unsupported occupant, suspect, pilot,
    /// driver, target, or owner, reduce that goal to the visible act of giving orders.
    /// Source-established labels remain untouched.
    private func repairUnsupportedDialogueSummary(in body: String) -> String {
        let authoritativeText = (
            [input.sceneText]
                + input.entities.map(\.description)
                + input.continuity.map(\.description)
        ).joined(separator: " ").lowercased()
        let unsupportedLabels = ["occupant", "suspect", "pilot", "driver", "target", "owner"]
            .filter { authoritativeText.contains($0) == false }
        guard unsupportedLabels.isEmpty == false else { return body }

        let speakers = Array(Set(screenplayDialogueAttributions().map(\.speaker)))
        guard speakers.count == 1, let speaker = speakers.first else { return body }

        var section = ""
        return body.components(separatedBy: .newlines).map { line in
            if line.hasPrefix("[") { section = line }
            guard section == "[Generation Goal]",
                  line.localizedCaseInsensitiveContains("primary event"),
                  line.range(of: #"\border(?:s|ed|ing)?\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  unsupportedLabels.contains(where: {
                      line.localizedCaseInsensitiveContains($0)
                  })
            else { return line }
            return "The central subject is \(speaker), and the primary event is \(speaker) giving orders."
        }.joined(separator: "\n")
    }

    /// When the screenplay does not call for music, make that absence explicit so the
    /// video model does not invent a score. A source mention of music remains authored
    /// territory and is never overwritten by this repair.
    private func ensureMusicDirection(in body: String) -> String {
        let musicPattern = try! NSRegularExpression(
            pattern: #"\b(?:music|song|score|singing|sings)\b"#,
            options: [.caseInsensitive]
        )
        let sourceRange = NSRange(input.sceneText.startIndex..., in: input.sceneText)
        guard musicPattern.firstMatch(in: input.sceneText, range: sourceRange) == nil else {
            return body
        }
        let noMusicPattern = try! NSRegularExpression(
            pattern: #"\b(?:no|without)\s+music\b"#,
            options: [.caseInsensitive]
        )
        let bodyRange = NSRange(body.startIndex..., in: body)
        guard noMusicPattern.firstMatch(in: body, range: bodyRange) == nil else {
            return body
        }

        var lines = body.components(separatedBy: .newlines)
        guard let audioIndex = lines.firstIndex(where: { $0 == "[Audio]" }) else {
            return body
        }
        let nextSection = lines.indices.first { index in
            index > audioIndex && lines[index].hasPrefix("[")
        } ?? lines.endIndex
        lines.insert("No music.", at: nextSection)
        return lines.joined(separator: "\n")
    }

    /// The prompt writer does not receive image pixels, so it may not infer a referenced
    /// character's gender from an approved portrait. For a card with one identity
    /// character, repair only possessives attached to visual-identity nouns. Explicit
    /// entity/continuity evidence selects `his` or `her`; absent evidence uses the
    /// character's name. Dialogue lines are left verbatim.
    private func repairCharacterIdentityPronouns(
        in body: String,
        card: ScenePromptResult.Card
    ) -> String {
        let mappedDesignators = Set(card.references.compactMap { reference -> String? in
            guard reference.sourceDesignator > 0,
                  reference.sourceDesignator <= input.references.count
            else { return nil }
            return input.references[reference.sourceDesignator - 1].designator
        })
        let identityEntities = input.entities.filter { entity in
            entity.materials.contains {
                $0.class == .identity && mappedDesignators.contains($0.designator)
            }
        }
        guard identityEntities.count == 1, let entity = identityEntities.first else {
            return body
        }

        let evidence = ([entity.description] + input.continuity.compactMap { entry in
            entry.entity.caseInsensitiveCompare(entity.name) == .orderedSame
                ? entry.description : nil
        }).joined(separator: " ")
        let hasFemaleEvidence = Self.containsGenderWord(
            in: evidence,
            pattern: #"\b(?:woman|female|she|her|hers)\b"#
        )
        let hasMaleEvidence = Self.containsGenderWord(
            in: evidence,
            pattern: #"\b(?:man|male|he|him|his)\b"#
        )
        let sourcePronouns: String
        let replacement: String
        if hasFemaleEvidence && !hasMaleEvidence {
            sourcePronouns = "his"
            replacement = "her $1"
        } else if hasMaleEvidence && !hasFemaleEvidence {
            sourcePronouns = "her"
            replacement = "his $1"
        } else {
            sourcePronouns = "his|her"
            replacement = NSRegularExpression.escapedTemplate(for: entity.name + "'s") + " $1"
        }
        let identityNouns = [
            "body proportions", "screen position", "face", "head", "hair", "hairstyle",
            "body", "build", "wardrobe", "identity", "clothing", "gaze", "eyes",
            "mouth", "lips", "jaw", "posture", "expression", "features", "appearance",
            "eyeline",
        ].joined(separator: "|")
        let pattern = try! NSRegularExpression(
            pattern: #"\b(?:"# + sourcePronouns + #")\s+((?:(?:fixed|steady|controlled|watchful)\s+)?(?:"#
                + identityNouns + #"))\b"#,
            options: [.caseInsensitive]
        )
        return body.components(separatedBy: .newlines).map { line in
            guard line.contains("{") == false else { return line }
            let range = NSRange(line.startIndex..., in: line)
            return pattern.stringByReplacingMatches(
                in: line,
                range: range,
                withTemplate: replacement
            )
        }.joined(separator: "\n")
    }

    private static func containsGenderWord(in text: String, pattern: String) -> Bool {
        let expression = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return expression.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ) != nil
    }

    private func validate(card: ScenePromptResult.Card) throws {
        guard !card.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Self.reject(.emptyPromptBody)
        }
        for value in [card.title, card.body, card.guidance,
                      card.settings.aspectRatio, card.settings.resolution]
        where value.unicodeScalars.contains(where: {
            $0.value < 0x20 && $0 != "\n" && $0 != "\t"
        }) {
            throw Self.reject(.controlCharacters)
        }

        let positions = card.references.map(\.position)
        let sources = card.references.map(\.sourceDesignator)
        guard Set(positions).count == positions.count, Set(sources).count == sources.count else {
            throw Self.reject(.duplicateReferenceMapping)
        }
        let expectedPositions = positions.isEmpty ? [] : Array(1...positions.count)
        guard positions == expectedPositions else {
            throw Self.reject(.referenceMappingGap)
        }
        guard sources.allSatisfy({ $0 >= 1 && $0 <= input.references.count }) else {
            throw Self.reject(.unknownReferenceSource)
        }

        try Self.validateDesignators(in: card.body, localCount: positions.count)
        if profile?.declaresReferenceGrammar == true {
            try Self.validateDeclarationLines(
                in: card.body,
                sources: sources.map { input.references[$0 - 1] }
            )
        }
        try Self.validateAge(card.body)
        try validate(settings: card.settings)
        if enforcesQualityContract {
            try validateQualityContract(card.body, settings: card.settings)
        }
    }

    private func validate(settings: ScenePromptResult.Settings) throws {
        guard let profile else { return }
        if let seconds = settings.durationSeconds,
           let range = profile.durationRange, !range.contains(seconds) {
            throw Self.reject(.invalidDuration)
        }
        if !profile.aspectRatios.isEmpty,
           !profile.aspectRatios.contains(settings.aspectRatio) {
            throw Self.reject(.invalidAspectRatio)
        }
        if !profile.resolutions.isEmpty,
           !profile.resolutions.contains(settings.resolution) {
            throw Self.reject(.invalidResolution)
        }
    }

    private static func validateDesignators(in body: String, localCount: Int) throws {
        let seen = designatorNumbers(in: body)
        guard localCount > 0 else {
            if !seen.isEmpty { throw reject(.unknownReferenceDesignator) }
            return
        }
        let expected = Set(1...localCount)
        if !expected.isSubset(of: seen) { throw reject(.missingReferenceDesignator) }
        if !seen.isSubset(of: expected) { throw reject(.unknownReferenceDesignator) }
    }

    static func validateDeclarationLines(
        in body: String, sources: [ScenePromptInputReference]
    ) throws {
        let lines = body.components(separatedBy: .newlines)
        for (offset, source) in sources.enumerated() {
            let position = offset + 1
            let solo = lines.filter { designatorNumbers(in: $0) == [position] }
            guard !solo.isEmpty else { throw reject(.bulkReferenceStatement) }
            guard solo.contains(where: { $0.localizedCaseInsensitiveContains(source.role) }) else {
                throw reject(.missingReferenceRole)
            }
            let expectedFidelity = source.fidelity.rawValue.replacingOccurrences(
                of: "_", with: "-"
            )
            guard solo.contains(where: { line in
                normalizedFidelityText(line).contains(expectedFidelity)
            }) else {
                throw reject(.missingReferenceFidelity)
            }
            guard source.exclusion.isEmpty || solo.contains(where: { line in
                line.range(of: "do not", options: .caseInsensitive) != nil
                    && line.localizedCaseInsensitiveContains(source.exclusion)
            }) else {
                throw reject(.missingReferenceExclusion)
            }
        }
    }

    /// The project payload stores enum-safe underscores while Seedance documents
    /// hyphenated terms. Accept either punctuation (and ordinary spaces) but still require
    /// the exact grade derived for this specific reference.
    private static func normalizedFidelityText(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func designatorNumbers(in text: String) -> Set<Int> {
        var values = Set<Int>()
        let range = NSRange(text.startIndex..., in: text)
        designatorPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let swiftRange = Range(match.range(at: 1), in: text) else { return }
            values.insert(Int(text[swiftRange]) ?? 0)
        }
        return values
    }

    private static func validateAge(_ body: String) throws {
        let range = NSRange(body.startIndex..., in: body)
        if agePatterns.contains(where: { $0.firstMatch(in: body, range: range) != nil }) {
            throw reject(.ageWritten)
        }
    }

    /// A High Quality draft may reach the independent reviewer with repairable prose.
    /// Standard output and the reviewer's final output cross these deterministic gates.
    /// They intentionally cover objective anti-patterns rather than subjective style.
    private func validateQualityContract(
        _ body: String,
        settings: ScenePromptResult.Settings
    ) throws {
        let direction = body.components(separatedBy: .newlines)
            .filter { !$0.contains("{") && !$0.contains("}") }.joined(separator: "\n")
        let range = NSRange(direction.startIndex..., in: direction)
        if Self.arbitraryCameraMeasurementPattern.firstMatch(in: direction, range: range) != nil {
            throw Self.reject(.arbitraryCameraMeasurement)
        }
        if Self.formattedSoundCuePattern.firstMatch(in: direction, range: range) != nil {
            throw Self.reject(.formattedSoundCue)
        }
        if direction.contains("\\<") {
            throw Self.reject(.escapedAngleMarkup)
        }
        if Self.forbiddenQualityBoilerplate.contains(where: {
            direction.localizedCaseInsensitiveContains($0)
        }) {
            throw Self.reject(.qualityBoilerplate)
        }
        if profile?.id == TargetProfileCatalog.seedance2_5.id {
            guard let duration = settings.durationSeconds else {
                throw Self.reject(.missingTimingPlan)
            }
            try Self.validateTimingPlan(in: body, durationSeconds: duration)
        }
    }

    /// Creative direction is filmmaker-authored authority over otherwise optional
    /// performance, blocking, eyeline, and camera choices. Keep this gate deliberately
    /// bounded to concrete, mechanically recognizable intent instead of pretending to
    /// understand arbitrary prose. The drafting/review prompts handle the full note;
    /// this check prevents the most consequential explicit requests from being silently
    /// replaced by contradictory stock staging.
    private func validateCreativeDirection(in body: String) throws {
        let direction = input.creativeDirection
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !direction.isEmpty else { return }

        let requestsOrbit = Self.containsAny(
            ["orbit", "orbital", "arc around", "camera arc", "circle around"],
            in: direction
        )
        let requestsPerformanceMotion = Self.containsAny(
            [
                "move around", "more movement", "more dynamic", "dynamic movement",
                "natural acting", "natural performance", "physical performance",
                "gesture", "gesturing",
            ],
            in: direction
        )
        let requestsEyelineTransition = Self.containsAny(
            ["address", "turn to", "look to", "look toward", "face the", "speaks to"],
            in: direction
        ) && Self.containsAny(
            ["then", "when", "while", "start", "begin", "initially", "first", "from"],
            in: direction
        )

        let prompt = body.lowercased()
        let entityNames = input.entities.map { $0.name.lowercased() }
        let subjectDirection = prompt.components(separatedBy: .newlines)
            .filter { line in entityNames.contains(where: { line.contains($0) }) }
            .joined(separator: "\n")
        if requestsOrbit {
            let realizesOrbit = Self.containsAny(
                ["orbit", "orbital", "arc around", "arcs around", "curved path", "circles around"],
                in: prompt
            )
            let contradictsOrbit = Self.containsAny(
                [
                    "stable axis", "single axis", "same axis", "straight approach",
                    "without changing axis", "one intentional axis",
                ],
                in: prompt
            )
            guard realizesOrbit, !contradictsOrbit else {
                throw Self.reject(.creativeDirectionNotApplied)
            }
        }

        if requestsEyelineTransition {
            let realizesTransition = Self.matchesAny(
                [
                    #"\b(?:turns?|turning|pivots?|pivoting|reorients?|reorienting)\b[^.\n]{0,120}\b(?:address|toward|to face|agents?|analysts?|room|team|personnel|people)\b"#,
                    #"\b(?:shifts?|moves?)\b[^.\n]{0,50}\b(?:gaze|eyeline|attention)\b[^.\n]{0,80}\b(?:agents?|analysts?|room|team|personnel|people)\b"#,
                    #"\b(?:looks?|faces?)\b[^.\n]{0,60}\bfrom\b[^.\n]{0,60}\bto(?:ward)?\b"#,
                ],
                in: subjectDirection
            )
            let contradictsTransition = Self.containsAny(
                [
                    "fixed screen eyeline", "maintaining the fixed screen eyeline",
                    "without shifting the gaze", "without shifting her gaze",
                    "without shifting his gaze", "without shifting their gaze",
                    "without looking away",
                ],
                in: subjectDirection
            ) || Self.matchesAny(
                [#"eyes? (?:remain|stay) locked[^.\n]{0,100}\b(?:speaks?|delivers?|orders?)\b"#],
                in: subjectDirection
            )
            guard realizesTransition, !contradictsTransition else {
                throw Self.reject(.creativeDirectionNotApplied)
            }
        }

        if requestsPerformanceMotion {
            let realizesMotion = Self.matchesAny(
                [
                    #"\b(?:shifts? (?:their |her |his )?weight|gestures?|turns?|pivots?|reorients?|steps?|crosses|paces?)\b"#,
                ],
                in: subjectDirection
            )
            guard realizesMotion else {
                throw Self.reject(.creativeDirectionNotApplied)
            }
        }
    }

    private static func containsAny(_ needles: [String], in text: String) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func matchesAny(_ patterns: [String], in text: String) -> Bool {
        patterns.contains { pattern in
            let expression = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            return expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
            ) != nil
        }
    }

    private static func validateTimingPlan(
        in body: String,
        durationSeconds: Int
    ) throws {
        let fullRange = NSRange(body.startIndex..., in: body)
        let totals = totalDurationPattern.matches(in: body, range: fullRange)
        guard let totalMatch = totals.first,
              let total = captureSeconds(1, match: totalMatch, text: body)
        else {
            throw reject(.missingTimingPlan)
        }
        guard totals.count == 1, total == Double(durationSeconds) else {
            throw reject(.invalidTimingPlan)
        }

        var expectedStage = 1
        var expectedStart = 0.0
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard stageHeadingPattern.firstMatch(
                in: line, range: NSRange(line.startIndex..., in: line)
            ) != nil else { continue }
            // Malformed stage headings must fail, not disappear from the timeline.
            guard let timing = stageTiming(in: line),
                  timing.number == expectedStage,
                  timing.start == expectedStart,
                  timing.end > timing.start,
                  timing.end <= total
            else {
                throw reject(.invalidTimingPlan)
            }
            expectedStage += 1
            // Compare parsed endpoints directly; do not sum or round durations.
            expectedStart = timing.end
        }
        guard expectedStage > 1 else { throw reject(.missingTimingPlan) }
        guard expectedStart == total else { throw reject(.invalidTimingPlan) }
    }

    private func screenplayDialogueAttributions() -> [(speaker: String, dialogue: String)] {
        sourceDialogue.map { (speaker: $0.speaker, dialogue: $0.text) }
    }

    private static func captureInt(
        _ index: Int,
        match: NSTextCheckingResult,
        text: String
    ) -> Int? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    private static func captureSeconds(
        _ index: Int,
        match: NSTextCheckingResult,
        text: String
    ) -> Double? {
        guard let range = Range(match.range(at: index), in: text),
              let seconds = Double(text[range]), seconds.isFinite
        else { return nil }
        return seconds
    }

    private static func reject(_ code: ScenePromptSemanticCode) -> StructuredValidationFailure {
        StructuredResultValidator.semanticViolation(code.rawValue)
    }
}
