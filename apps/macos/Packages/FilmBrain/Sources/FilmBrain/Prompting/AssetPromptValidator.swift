import FilmCore
import Foundation

/// Why an asset-prompt result was rejected (PHASE3_DESIGN §8.3).
///
/// **Film-Camp-authored** (§3.5, §13.7): the vendored `seedance_lint.py` is not adopted —
/// its `--specs` default holds no image model and its scene-completeness warnings misfire
/// on grey-background reference sheets. These codes are the image-prompt semantic layer.
public enum AssetPromptSemanticCode: String, Equatable, Sendable {
    case wrongSchemaVersion = "wrong_schema_version"
    case emptyPromptBody = "empty_prompt_body"
    case oversizedPromptBody = "oversized_prompt_body"
    case controlCharacters = "control_characters"
    /// A supplied designator (`@Image k`, k = 1…N) absent from the body: every reference
    /// must carry its explicit role statement, the vendored skill's canonical failure
    /// being the vague bulk statement.
    case missingReferenceDesignator = "missing_reference_designator"
    /// The body names a designator beyond N.
    case unknownReferenceDesignator = "unknown_reference_designator"
    case missingTargetModel = "missing_target_model"
    /// A Face Closeup is an identity reference, not a scene performance. Its prompt must
    /// explicitly keep the face emotionally neutral regardless of source-story context.
    case missingNeutralFacialExpression = "missing_neutral_facial_expression"
    /// The body states a numeric age. Deliberately **numeric-only** (§8.3): the vendored
    /// trigger words ("young", "little", …) are context-dependent and a mechanical word
    /// ban would refuse legitimate wardrobe and set prose; the instructions carry the full
    /// rule, this lint catches the unambiguous violations.
    case ageWritten = "age_written"
}

/// Every §8.3 semantic rule, checked against the §8.2 input the run was launched from
/// (PHASE3_DESIGN §8.3; Plan 016 contract B). Versioned like its Phase 1/2 peers.
///
/// What is deliberately **not** here: collisions with rows already in the project. Those
/// are apply's business (§8.4) — the step-0 digest guard, not this validator.
public struct AssetPromptValidator: Sendable {
    public static let version = 1

    private let structural = StructuredResultValidator()
    /// The supplied designators, densely numbered over the rendered references (§3.3).
    private let designatorCount: Int
    private let requiresNeutralFacialExpression: Bool

    /// The body cap, in UTF-8 bytes — the same limit `createPrompt` enforces on storage.
    static let maxBodyBytes = 32 * 1024

    /// The three numeric age patterns, case-insensitive (§8.3): "12 years old" /
    /// "a 12-year-old"; "age 34", "age: 34", "Aged 34"; "34 y.o." / "34 yo".
    static let agePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"\b\d{1,3}[-\s]year[s]?[-\s]old\b"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"\bage[d]?\s*[:=]?\s*\d{1,3}\b"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"\b\d{1,3}\s*y\.?o\.?\b"#, options: [.caseInsensitive]),
    ]

    static let designatorPattern = try! NSRegularExpression(pattern: #"@Image\s*(\d+)"#)

    public init(input: AssetPromptInput) {
        self.designatorCount = input.references.count
        self.requiresNeutralFacialExpression = input.requirement.entityKind == .character
            && input.requirement.templateCode == "face_closeup"
    }

    public func validate(resultFileAt url: URL) throws -> AssetPromptResult {
        let data = try structural.validatedData(resultFileAt: url, schemaURL: AssetPromptSchema.url)
        return try validate(data: data)
    }

    public func validate(data: Data) throws -> AssetPromptResult {
        try structural.validate(data: data, schemaURL: AssetPromptSchema.url)
        let result = try JSONDecoder().decode(AssetPromptResult.self, from: data)
        guard result.schemaVersion == AssetPromptSchema.version else {
            throw Self.reject(.wrongSchemaVersion)
        }
        let prompt = result.prompt
        // empty_prompt_body
        guard !prompt.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Self.reject(.emptyPromptBody)
        }
        // oversized_prompt_body
        guard prompt.body.utf8.count <= Self.maxBodyBytes else {
            throw Self.reject(.oversizedPromptBody)
        }
        // control_characters — newline and tab ride along; every other scalar under
        // 0x20 refuses, extraction's predicate and spelling.
        for value in [prompt.body, prompt.targetModel, prompt.guidance]
        where value.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\t" }) {
            throw Self.reject(.controlCharacters)
        }
        // missing_target_model — opaque to the app (§3.5), but never empty.
        guard !prompt.targetModel.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Self.reject(.missingTargetModel)
        }
        try Self.validateDesignators(
            in: prompt.body, suppliedCount: designatorCount
        )
        try Self.validateAge(prompt.body)
        if requiresNeutralFacialExpression {
            try Self.validateNeutralFacialExpression(prompt.body)
        }
        return result
    }

    // MARK: - Designators (§8.3)

    private static func validateDesignators(in body: String, suppliedCount count: Int) throws {
        guard count > 0 else {
            // No references supplied: naming any designator is unknown by construction,
            // and none can be missing.
            if firstDesignatorNumber(in: body) != nil {
                throw reject(.unknownReferenceDesignator)
            }
            return
        }
        var seen = Set<Int>()
        let range = NSRange(body.startIndex..., in: body)
        designatorPattern.enumerateMatches(in: body, range: range) { match, _, _ in
            guard let match, let matchRange = Range(match.range(at: 1), in: body) else { return }
            seen.insert(Int(body[matchRange]) ?? 0)
        }
        // missing_reference_designator: every k in 1…N appears at least once.
        if Set(1...count).subtracting(seen) != [] {
            throw reject(.missingReferenceDesignator)
        }
        // unknown_reference_designator: nothing outside 1…N.
        if !seen.isSubset(of: 1...count) {
            throw reject(.unknownReferenceDesignator)
        }
    }

    private static func firstDesignatorNumber(in body: String) -> Int? {
        guard let match = designatorPattern.firstMatch(
            in: body, range: NSRange(body.startIndex..., in: body)
        ), let range = Range(match.range(at: 1), in: body) else { return nil }
        return Int(body[range])
    }

    // MARK: - The age lint (§8.3)

    private static func validateAge(_ body: String) throws {
        let range = NSRange(body.startIndex..., in: body)
        for pattern in agePatterns where pattern.firstMatch(in: body, range: range) != nil {
            throw reject(.ageWritten)
        }
    }

    private static func validateNeutralFacialExpression(_ body: String) throws {
        guard body.range(
            of: #"\bneutral\s+facial\s+expression\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil else {
            throw reject(.missingNeutralFacialExpression)
        }
    }

    private static func reject(_ code: AssetPromptSemanticCode) -> StructuredValidationFailure {
        StructuredResultValidator.semanticViolation(code.rawValue)
    }
}
