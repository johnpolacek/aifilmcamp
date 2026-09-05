import FilmCore
import Foundation

/// The checked-in output contract of the asset-prompt job (PHASE3_DESIGN §8.3).
public enum AssetPromptSchema: Sendable {
    public static let version = 1
    public static var url: URL {
        Bundle.module.url(forResource: "asset-prompt-v1.schema", withExtension: "json")!
    }
}

/// The validated §8.3 result, as the harness wrote it.
public struct AssetPromptResult: Codable, Equatable, Sendable {
    public struct Prompt: Codable, Equatable, Sendable {
        /// The complete, paste-ready generation prompt.
        public let body: String
        /// The skill's routing choice ('Nano Banana 2', …) — opaque to the app (§3.5).
        public let targetModel: String
        /// Generation-settings prose; may be empty.
        public let guidance: String

        public init(body: String, targetModel: String, guidance: String) {
            self.body = body
            self.targetModel = targetModel
            self.guidance = guidance
        }
    }

    public let schemaVersion: Int
    public let prompt: Prompt

    public init(schemaVersion: Int, prompt: Prompt) {
        self.schemaVersion = schemaVersion
        self.prompt = prompt
    }
}

/// The one asset-prompt task (PHASE3_DESIGN §8.1): **one requirement, one request, one
/// transaction** — the Phase 2 manifest shape at single-requirement scale. No chunking, no
/// reconcile, no `ExtractionRun`, and no run-once gate (§3.1): a prompt is derived,
/// disposable output that re-runs freely.
///
/// Nothing here is task machinery: the job state machine, harness events, cancellation,
/// and failure mapping stay `StructuredJobRunner`'s, unchanged.
public struct GenerateAssetPromptTask: StructuredTask {
    public typealias Output = AssetPromptResult
    public let taskName = Job.assetPromptTask
    public let schemaVersion = AssetPromptSchema.version
    public let schemaURL = AssetPromptSchema.url
    private let input: AssetPromptInput
    private let validator: AssetPromptValidator
    private let skillEntryPath: String
    private let skillRoutingPath: String?

    /// - Parameters:
    ///   - input: the §8.2 snapshot this run was launched from. Every semantic rule of
    ///     §8.3 is checked against it, and §8.4 step 0 later proves it still holds by
    ///     rebuilding the same input inside the apply transaction.
    ///   - skillEntryPath: absolute path of the materialised entry file this run's session
    ///     reads (arm B: inside the run's workspace, §3.5). Rendered into the instructions
    ///     only — never persisted, never digested.
    ///   - skillRoutingPath: absolute path of the routing table, when the descriptor
    ///     carries one.
    public init(
        input: AssetPromptInput,
        skillEntryPath: String,
        skillRoutingPath: String?
    ) {
        self.input = input
        self.validator = AssetPromptValidator(input: input)
        self.skillEntryPath = skillEntryPath
        self.skillRoutingPath = skillRoutingPath
    }

    public func prompt(for _: StructuredTaskInput) throws -> String {
        let creativeContext = try AssetPromptCreativeContext(input: input).render()
        return AssetPromptPrompt.render(
            payload: creativeContext,
            skillEntryPath: skillEntryPath,
            skillRoutingPath: skillRoutingPath
        )
    }

    public func validate(resultFileAt url: URL) throws -> AssetPromptResult {
        try validator.validate(resultFileAt: url)
    }
}

/// The deliberately narrow subset Codex sees while writing an image prompt. The complete
/// `AssetPromptInput` remains the job's persisted digest input and the apply-time drift
/// guard; screenplay-derived story context does not need to enter the creative request.
struct AssetPromptCreativeContext: Codable, Equatable, Sendable {
    struct Requirement: Codable, Equatable, Sendable {
        let tier: AssetRequirementTier
        let name: String
        let entityKind: EntityKind
        let templateCode: String
    }

    struct Entity: Codable, Equatable, Sendable {
        struct VisualState: Codable, Equatable, Sendable {
            let category: StateCategory
            let description: String
        }

        let name: String
        let aliases: [String]
        let description: String
        let visualStates: [VisualState]
    }

    struct Reference: Codable, Equatable, Sendable {
        let designator: String
        let `class`: ReferenceClass
        let description: String
        let role: String
        let fidelity: ReferenceFidelity
    }

    let schemaVersion: Int
    let requirement: Requirement
    let entity: Entity
    let references: [Reference]

    init(input: AssetPromptInput) {
        schemaVersion = 1
        requirement = Requirement(
            tier: input.requirement.tier,
            name: input.requirement.name,
            entityKind: input.requirement.entityKind,
            templateCode: input.requirement.templateCode
        )
        entity = Entity(
            name: input.entity.name,
            aliases: input.entity.aliases,
            description: input.entity.description,
            // Canonical prompts establish a stable baseline. Timeline states are useful
            // only when a variant asks for the visible state tied to its selected scenes.
            visualStates: input.requirement.tier == .variant
                ? input.entity.states.map {
                    Entity.VisualState(category: $0.category, description: $0.description)
                }
                : []
        )
        references = input.references.map {
            Reference(
                designator: $0.designator,
                class: $0.class,
                description: $0.description,
                role: $0.role,
                fidelity: $0.fidelity
            )
        }
    }

    func render() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
