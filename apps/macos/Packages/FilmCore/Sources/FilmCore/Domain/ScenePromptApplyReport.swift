import Foundation

public enum ScenePromptQualityMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    /// One Codex request performs the draft, silent review, repair, and final output.
    case standard
    /// A second independent Codex request reviews and rewrites the first request's result.
    case highQuality

    public var requestCount: Int { self == .highQuality ? 2 : 1 }
}

/// The generation-settings knobs one scene-prompt run captured at start (PHASE5_DESIGN
/// §8.1, §4.4) — `AssetPromptSettings`' shape, mirrored per §4.4's naming contract.
///
/// Model ids and reasoning efforts are runtime values typed by the operator — FilmCore
/// never hard-codes a catalog and never validates them; `nil` means "the account's Codex
/// default". The skill identity is descriptor-relative provenance (§3.5's fourth rule),
/// never an absolute cache path.
public struct ScenePromptSettings: Codable, Equatable, Hashable, Sendable {
    public var model: String?
    public var effort: String?
    /// The §8.1 pre-flight budget in UTF-16 code units of the rendered input.
    public var inputBudgetUTF16: Int
    public var qualityMode: ScenePromptQualityMode
    public var skillID: String
    public var skillEntryPath: String
    public var skillEntrySHA256: String

    public init(
        model: String? = nil,
        effort: String? = nil,
        inputBudgetUTF16: Int = 0,
        qualityMode: ScenePromptQualityMode = .standard,
        skillID: String = "",
        skillEntryPath: String = "",
        skillEntrySHA256: String = ""
    ) {
        self.model = model
        self.effort = effort
        self.inputBudgetUTF16 = inputBudgetUTF16
        self.qualityMode = qualityMode
        self.skillID = skillID
        self.skillEntryPath = skillEntryPath
        self.skillEntrySHA256 = skillEntrySHA256
    }

    private enum CodingKeys: String, CodingKey {
        case model, effort, inputBudgetUTF16, qualityMode
        case skillID, skillEntryPath, skillEntrySHA256
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        effort = try container.decodeIfPresent(String.self, forKey: .effort)
        inputBudgetUTF16 = try container.decode(Int.self, forKey: .inputBudgetUTF16)
        // Runs written before the mode existed always used the independent second pass.
        qualityMode = try container.decodeIfPresent(
            ScenePromptQualityMode.self, forKey: .qualityMode
        ) ?? .highQuality
        skillID = try container.decode(String.self, forKey: .skillID)
        skillEntryPath = try container.decode(String.self, forKey: .skillEntryPath)
        skillEntrySHA256 = try container.decode(String.self, forKey: .skillEntrySHA256)
    }
}

/// What one scene-prompt run's apply did (PHASE5_DESIGN §8.5).
///
/// It shares one nullable JSON column with its four siblings — `jobs.apply_report` — and
/// §8.5's field names overlap the older reports', so disjointness is made structural
/// exactly as `ManifestApplyReport` and `AssetPromptApplyReport` were: every stored key
/// carries the `scenePrompt` prefix. `ReportTypeTests` asserts the five encoded key sets
/// stay pairwise disjoint.
public struct ScenePromptApplyReport: Codable, Equatable, Hashable, Sendable {
    /// The scene the prompt was generated for.
    public var sceneID: UUID
    /// The active profile P the run targeted (§3.3) — persisted on the prompt row.
    public var targetProfile: String
    /// The complete prompt-set result the apply inserted.
    public var setID: UUID
    /// Its assigned version number — the current set after the apply.
    public var setNumber: Int
    /// Ordered cards committed atomically.
    public var cardCount: Int
    /// Citation rows the apply wrote (§3.2's plan, captured at generation time).
    public var referenceCount: Int
    /// The one digest (§8.1): the builder snapshot's digest the run recorded at launch.
    public var inputDigest: String
    /// The rendered-input version stamped on the row (§4.3).
    public var formatVersion: Int
    /// The settings captured at run start, skill triple included (§8.5).
    public var settings: ScenePromptSettings
    public var durationMs: Int

    /// The stored-key prefix that keeps this type key-disjoint from its four siblings in
    /// the shared column.
    static let keyPrefix = "scenePrompt"

    enum CodingKeys: String, CodingKey {
        case sceneID = "scenePromptSceneID"
        case targetProfile = "scenePromptTargetProfile"
        case setID = "scenePromptSetID"
        case setNumber = "scenePromptSetNumber"
        case cardCount = "scenePromptCardCount"
        case referenceCount = "scenePromptReferenceCount"
        case inputDigest = "scenePromptInputDigest"
        case formatVersion = "scenePromptFormatVersion"
        case settings = "scenePromptSettings"
        case durationMs = "scenePromptDurationMs"
    }

    public init(
        sceneID: UUID,
        targetProfile: String,
        setID: UUID,
        setNumber: Int,
        cardCount: Int,
        referenceCount: Int,
        inputDigest: String,
        formatVersion: Int,
        settings: ScenePromptSettings = ScenePromptSettings(),
        durationMs: Int = 0
    ) {
        self.sceneID = sceneID
        self.targetProfile = targetProfile
        self.setID = setID
        self.setNumber = setNumber
        self.cardCount = cardCount
        self.referenceCount = referenceCount
        self.inputDigest = inputDigest
        self.formatVersion = formatVersion
        self.settings = settings
        self.durationMs = durationMs
    }

    /// Source-compatible aliases for callers compiled during the one-card transition.
    public var promptID: UUID { setID }
    public var promptNumber: Int { setNumber }

    public init(
        sceneID: UUID,
        targetProfile: String,
        promptID: UUID,
        promptNumber: Int,
        referenceCount: Int,
        inputDigest: String,
        formatVersion: Int,
        settings: ScenePromptSettings = ScenePromptSettings(),
        durationMs: Int = 0
    ) {
        self.init(
            sceneID: sceneID,
            targetProfile: targetProfile,
            setID: promptID,
            setNumber: promptNumber,
            cardCount: 1,
            referenceCount: referenceCount,
            inputDigest: inputDigest,
            formatVersion: formatVersion,
            settings: settings,
            durationMs: durationMs
        )
    }
}
