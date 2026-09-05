import FilmCore
import Foundation

/// The second, independent scene-prompt pass. It receives canonical scene context and a
/// validated draft, then returns the same checked output shape after reviewing and
/// rewriting it. The draft is evidence, never authority; `ScenePromptValidator` checks
/// the refined result against the original canonical input again.
public struct RefineScenePromptTask: StructuredTask {
    public typealias Output = ScenePromptResult
    public let taskName = Job.scenePromptRefinementTask
    public let schemaVersion = ScenePromptSchema.version
    public let schemaURL = ScenePromptSchema.url

    private let validator: ScenePromptValidator
    private let skillEntryPath: String
    private let skillRoutingPath: String?
    private let seedancePinning: (subSkillPath: String, omniTemplatePath: String)?

    public init(
        authoritativeInput: ScenePromptInput,
        skillEntryPath: String,
        skillRoutingPath: String?,
        seedancePinning: (subSkillPath: String, omniTemplatePath: String)? = nil
    ) {
        validator = ScenePromptValidator(
            input: authoritativeInput,
            enforcesQualityContract: true
        )
        self.skillEntryPath = skillEntryPath
        self.skillRoutingPath = skillRoutingPath
        self.seedancePinning = seedancePinning
    }

    public func prompt(for structuredInput: StructuredTaskInput) throws -> String {
        ScenePromptRefinementPrompt.render(
            payload: structuredInput.text,
            skillEntryPath: skillEntryPath,
            skillRoutingPath: skillRoutingPath,
            seedancePinning: seedancePinning
        )
    }

    public func validate(resultFileAt url: URL) throws -> ScenePromptResult {
        try validator.validate(resultFileAt: url)
    }
}

/// Deterministic input to the review pass. The authoritative project input and the draft
/// are kept in separate fields so the reviewer cannot mistake generated prose for source
/// facts. Sorted-key encoding makes the child job's digest stable.
public struct ScenePromptRefinementInput: Codable, Equatable, Sendable {
    public let authoritativeInput: ScenePromptInput
    public let draft: ScenePromptResult

    public init(authoritativeInput: ScenePromptInput, draft: ScenePromptResult) {
        self.authoritativeInput = authoritativeInput
        self.draft = draft
    }

    public func rendered() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

enum ScenePromptRefinementPrompt {
    private static let instructions = ScenePromptPrompt.load("scene-prompt-refinement-v1")

    static func render(
        payload: String,
        skillEntryPath: String,
        skillRoutingPath: String?,
        seedancePinning: (subSkillPath: String, omniTemplatePath: String)?
    ) -> String {
        ScenePromptPrompt.skillHeader(
            skillEntryPath: skillEntryPath,
            skillRoutingPath: skillRoutingPath,
            seedancePinning: seedancePinning
        ) + "\n" + instructions
            + "\n\n<scene-prompt-refinement-input>\n" + payload
            + "\n</scene-prompt-refinement-input>\n"
    }
}
