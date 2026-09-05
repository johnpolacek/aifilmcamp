import Foundation

/// The validated asset-prompt output as FilmCore sees it (PHASE3_DESIGN §8.4; Plan 016
/// contract B) — the `ExtractionProposal`/`ManifestProposal` pattern: the throwing init is
/// the last gate, re-checking the storage-side limits so an unvalidated value can never
/// reach the applier even through a programming error.
public struct AssetPromptProposal: Equatable, Sendable {
    public let requirementID: UUID
    public let body: String
    public let targetModel: String
    public let guidance: String
    /// The settings captured at run start (§8.1); recorded on the report.
    public let settings: AssetPromptSettings

    public init(
        requirementID: UUID,
        body: String,
        targetModel: String,
        guidance: String,
        settings: AssetPromptSettings
    ) throws {
        // The same rules §8.3's semantic validator enforced on the result and §7.2's
        // storage guard enforces on every prompt row — non-empty, ≤ 32 KB UTF-8,
        // control-character-free other than newline and tab.
        guard !body.isEmpty else {
            throw ProjectStoreError.assetOperationRefused(reason: "A prompt cannot be empty.")
        }
        guard body.utf8.count <= 32 * 1024 else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "A prompt cannot be larger than 32 KB."
            )
        }
        guard !body.unicodeScalars.contains(where: {
            $0.value < 0x20 && $0 != "\n" && $0 != "\t"
        }) else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "A prompt cannot contain control characters."
            )
        }
        self.requirementID = requirementID
        self.body = body
        self.targetModel = targetModel
        self.guidance = guidance
        self.settings = settings
    }
}

/// What one prompt apply produced (§8.4 step 4): the report and **the journal entry** —
/// returned to the workshop so it routes the entry through `didApply` and ⌘Z reads
/// "Undo Generate Prompt" (§13.11's stated deviation: the apply is invertible, and the
/// undo stack survives generation).
public struct AssetPromptApplyOutcome: Sendable {
    public let report: AssetPromptApplyReport
    public let entry: JournalEntry

    public init(report: AssetPromptApplyReport, entry: JournalEntry) {
        self.report = report
        self.entry = entry
    }
}
