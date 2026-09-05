import FilmCore
import Foundation

/// The checked-in output contract of the scene-prompt job (PHASE5_DESIGN §8.3).
public enum ScenePromptSchema: Sendable {
    public static let version = 2
    public static var url: URL {
        Bundle.module.url(forResource: "scene-prompt-v2.schema", withExtension: "json")!
    }
}

/// The validated §8.3 result, as the harness wrote it.
public struct ScenePromptResult: Codable, Equatable, Sendable {
    public struct Settings: Codable, Equatable, Sendable {
        public let durationSeconds: Int?
        public let aspectRatio: String
        public let resolution: String

        public init(durationSeconds: Int?, aspectRatio: String, resolution: String) {
            self.durationSeconds = durationSeconds
            self.aspectRatio = aspectRatio
            self.resolution = resolution
        }
    }

    public struct Card: Codable, Equatable, Sendable {
        public struct Reference: Codable, Equatable, Sendable {
            /// Dense local `@Image N` position.
            public let position: Int
            /// Designator in the scene input's approved-reference list.
            public let sourceDesignator: Int

            public init(position: Int, sourceDesignator: Int) {
                self.position = position
                self.sourceDesignator = sourceDesignator
            }
        }

        public let title: String
        /// The complete, paste-ready generation prompt for the scene.
        public let body: String
        /// Operator notes; may be empty.
        public let guidance: String

        public let settings: Settings
        public let references: [Reference]

        public init(
            title: String, body: String, guidance: String,
            settings: Settings, references: [Reference]
        ) {
            self.title = title
            self.body = body
            self.guidance = guidance
            self.settings = settings
            self.references = references
        }
    }

    public let schemaVersion: Int
    public let cards: [Card]

    public init(schemaVersion: Int, cards: [Card]) {
        self.schemaVersion = schemaVersion
        self.cards = cards
    }
}

/// The drafting child of one scene-prompt run (PHASE5_DESIGN §8.1 plus the 2026-08-31
/// quality amendment). Standard mode validates this task's silently self-reviewed result
/// as final. High Quality adds a second independent child that reviews and rewrites it
/// before the parent may commit. There is still one scene and one canonical transaction:
/// no chunking, no reconcile, no `ExtractionRun`, and no run-once gate.
///
/// Nothing here is task machinery: the job state machine, harness events, cancellation,
/// and failure mapping stay `StructuredJobRunner`'s, unchanged.
///
/// The instructions route through the selected descriptor, never a hardcoded tree
/// (§3.7's fifth-revision rule): the rendered header names the materialised entry — and,
/// only for the bundled default under `seedance_2_5`, pins that sub-skill and its
/// omni-reference template so the session stays off excluded siblings. An imported skill
/// is routed to its own entry and optional routing file with no assumption the
/// higgsfield tree exists; under a profile without Seedance pinning nothing but the
/// descriptor's own files are named, and the output is never labeled or validated as
/// Seedance-specific (`targetProfile` stays opaque to this type).
public struct GenerateScenePromptTask: StructuredTask {
    public typealias Output = ScenePromptResult
    public let taskName = Job.scenePromptTask
    public let schemaVersion = ScenePromptSchema.version
    public let schemaURL = ScenePromptSchema.url
    private let input: ScenePromptInput
    private let validator: ScenePromptValidator
    private let skillEntryPath: String
    private let skillRoutingPath: String?
    private let seedancePinning: (subSkillPath: String, omniTemplatePath: String)?

    /// - Parameters:
    ///   - input: the §8.2 snapshot this run was launched from. Every semantic rule of
    ///     §8.3 is checked against it, and §8.4 step 0 later proves it still holds by
    ///     rebuilding the same input inside the apply transaction.
    ///   - skillEntryPath: absolute path of the materialised entry file this run's
    ///     session reads (arm B: inside the run's workspace clone). Rendered into the
    ///     instructions only — never persisted, never digested.
    ///   - skillRoutingPath: absolute path of the skill's routing file, when the run
    ///     carries one.
    ///   - seedancePinning: the bundled-default-under-`seedance_2_5` posture — absolute
    ///     paths of the pinned Seedance 2.5 sub-skill entry and its omni-reference
    ///     template inside this run's own workspace clone. `nil` for every other
    ///     combination (§3.7's fifth revision).
    public init(
        input: ScenePromptInput,
        skillEntryPath: String,
        skillRoutingPath: String?,
        seedancePinning: (subSkillPath: String, omniTemplatePath: String)? = nil,
        enforcesQualityContract: Bool = false
    ) {
        self.input = input
        self.validator = ScenePromptValidator(
            input: input,
            enforcesQualityContract: enforcesQualityContract
        )
        self.skillEntryPath = skillEntryPath
        self.skillRoutingPath = skillRoutingPath
        self.seedancePinning = seedancePinning
    }

    public func prompt(for structuredInput: StructuredTaskInput) throws -> String {
        ScenePromptPrompt.render(
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

/// The scene-prompt instructions and the delimiter that wraps the §8.2 input
/// (PHASE5_DESIGN §8.1, §8.2).
///
/// Structurally `AssetPromptPrompt`: the checked-in instructions, one delimiter tag
/// around the untrusted payload, and **the wrapper outside the digest** — the runner
/// digests `input.text` (the plain rendered JSON), so `jobs.input_sha256` equals
/// `ScenePromptInputSnapshot.digest`, the one digest of §8.1/§3.4.
///
/// The file paths in the header are parameters — arm-B clones inside this run's own
/// workspace; nothing here resolves a bundle or cache location on its own.
public enum ScenePromptPrompt: Sendable {
    static let instructions: String = load("scene-prompt-v2")

    public static func render(
        payload: String,
        skillEntryPath: String,
        skillRoutingPath: String?,
        seedancePinning: (subSkillPath: String, omniTemplatePath: String)?
    ) -> String {
        skillHeader(
            skillEntryPath: skillEntryPath,
            skillRoutingPath: skillRoutingPath,
            seedancePinning: seedancePinning
        ) + "\n" + instructions
            + "\n\n<scene-prompt-input>\n" + payload + "\n</scene-prompt-input>\n"
    }

    static func skillHeader(
        skillEntryPath: String,
        skillRoutingPath: String?,
        seedancePinning: (subSkillPath: String, omniTemplatePath: String)?
    ) -> String {
        var header = "Skill entry: \(skillEntryPath)\n"
        if let pinning = seedancePinning {
            let skillRoot = URL(fileURLWithPath: skillEntryPath).deletingLastPathComponent()
            let promptSkill = skillRoot.appending(path: "skills/higgsfield-prompt/SKILL.md")
            let seedanceSkill = skillRoot.appending(path: "skills/higgsfield-seedance/SKILL.md")
            let constraints = skillRoot.appending(path: "skills/shared/negative-constraints.md")
            header += "Prompt-writing sub-skill: \(promptSkill.path)\n"
            header += "Seedance core sub-skill: \(seedanceSkill.path)\n"
            header += "Seedance 2.5 sub-skill: \(pinning.subSkillPath)\n"
            header += "Omni-reference template: \(pinning.omniTemplatePath)\n"
            header += "Shared negative constraints: \(constraints.path)\n"
        } else if let routing = skillRoutingPath {
            header += "Skill routing file: \(routing)\n"
        }
        return header
    }

    static func load(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Prompts")
            ?? Bundle.module.url(forResource: name, withExtension: "md")!
        return try! String(contentsOf: url, encoding: .utf8)
    }
}
