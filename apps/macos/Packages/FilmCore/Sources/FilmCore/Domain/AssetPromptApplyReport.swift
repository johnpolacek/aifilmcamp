import Foundation

/// The generation-settings knobs one prompt run captured at start (PHASE3_DESIGN §8.1,
/// §4.4) — the `ManifestSettings` shape with the skill identity added, so the recorded
/// run is reproducible against what it actually ran with.
///
/// Model ids and reasoning efforts are runtime values typed by the operator — FilmCore
/// never hard-codes a catalog and never validates them; `nil` means "the account's Codex
/// default". The skill identity is descriptor-relative provenance (§3.5), `''` for a run
/// that had none, retained for decoding older rows.
public struct AssetPromptSettings: Codable, Equatable, Hashable, Sendable {
    public var model: String?
    public var effort: String?
    /// The §8.1 pre-flight budget in UTF-16 code units of the rendered input.
    public var inputBudgetUTF16: Int
    public var skillID: String
    public var skillEntryPath: String
    public var skillEntrySHA256: String

    public init(
        model: String? = nil,
        effort: String? = nil,
        inputBudgetUTF16: Int = 0,
        skillID: String = "",
        skillEntryPath: String = "",
        skillEntrySHA256: String = ""
    ) {
        self.model = model
        self.effort = effort
        self.inputBudgetUTF16 = inputBudgetUTF16
        self.skillID = skillID
        self.skillEntryPath = skillEntryPath
        self.skillEntrySHA256 = skillEntrySHA256
    }
}

/// What one asset-prompt run's apply did (PHASE3_DESIGN §8.5).
///
/// It shares one nullable JSON column with `ApplyReport` and `ManifestApplyReport` —
/// `jobs.apply_report` — and is written inside the prompt apply transaction. `Job`
/// `.assetPromptReport` gates on the task, so run history cannot cross-decode one report
/// type as another.
///
/// **The three types stay key-disjoint** (§4.4's rule extended), and §8.5's field names
/// overlap the older reports' (`durationMs`, `settings`). Disjointness is therefore made
/// structural rather than accidental, exactly as `ManifestApplyReport` did: every stored
/// key carries the `assetPrompt` prefix.
public struct AssetPromptApplyReport: Codable, Equatable, Hashable, Sendable {
    /// The requirement the prompt was generated for.
    public var requirementID: UUID
    /// The prompt row the apply inserted.
    public var promptID: UUID
    /// Its assigned number — the current prompt after the apply (§3.2).
    public var promptNumber: Int
    /// Citation rows the apply wrote (§3.3's rendered references).
    public var referenceCount: Int
    /// The skill's routing choice as returned (§8.3), opaque to the app.
    public var targetModel: String
    public var durationMs: Int
    /// The settings captured at run start (§8.1); a preference edited mid-run does not apply.
    public var settings: AssetPromptSettings

    /// The stored-key prefix that keeps this type key-disjoint from its two siblings in
    /// the shared column.
    static let keyPrefix = "assetPrompt"

    enum CodingKeys: String, CodingKey {
        case requirementID = "assetPromptRequirementID"
        case promptID = "assetPromptPromptID"
        case promptNumber = "assetPromptPromptNumber"
        case referenceCount = "assetPromptReferenceCount"
        case targetModel = "assetPromptTargetModel"
        case durationMs = "assetPromptDurationMs"
        case settings = "assetPromptSettings"
    }

    public init(
        requirementID: UUID,
        promptID: UUID,
        promptNumber: Int,
        referenceCount: Int,
        targetModel: String,
        durationMs: Int = 0,
        settings: AssetPromptSettings = AssetPromptSettings()
    ) {
        self.requirementID = requirementID
        self.promptID = promptID
        self.promptNumber = promptNumber
        self.referenceCount = referenceCount
        self.targetModel = targetModel
        self.durationMs = durationMs
        self.settings = settings
    }
}
