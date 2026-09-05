import Foundation

/// One hand-written/generated card value. `referencePositions` are positions in the
/// scene input plan, ordered as the card's local `@Image 1...N` mapping.
public struct ScenePromptCardDraft: Codable, Equatable, Hashable, Sendable {
    public let title: String
    public let body: String
    public let guidance: String
    public let durationSeconds: Int?
    public let aspectRatio: String
    public let resolution: String
    public let referencePositions: [Int]

    public init(
        title: String = "", body: String, guidance: String = "",
        durationSeconds: Int? = nil, aspectRatio: String = "", resolution: String = "",
        referencePositions: [Int] = []
    ) {
        self.title = title
        self.body = body
        self.guidance = guidance
        self.durationSeconds = durationSeconds
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.referencePositions = referencePositions
    }
}

public struct ScenePromptSetProposal: Equatable, Sendable {
    public static let maximumCards = 32
    public static let maximumCombinedBodyBytes = 64 * 1024

    public let sceneID: UUID
    public let cards: [ScenePromptCardDraft]
    public let settings: ScenePromptSettings

    public init(
        sceneID: UUID, cards: [ScenePromptCardDraft], settings: ScenePromptSettings
    ) throws {
        guard (1...Self.maximumCards).contains(cards.count) else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "A prompt set must contain between 1 and 32 cards."
            )
        }
        guard cards.reduce(0, { $0 + $1.body.utf8.count }) <= Self.maximumCombinedBodyBytes else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "A prompt set cannot contain more than 64 KB of prompt text."
            )
        }
        for card in cards {
            try ScenePromptProposal.validateBody(card.body)
            guard Set(card.referencePositions).count == card.referencePositions.count,
                  card.referencePositions.allSatisfy({ $0 >= 1 }) else {
                throw ProjectStoreError.sceneOperationRefused(
                    reason: "A prompt card's reference mapping must be unique and positive."
                )
            }
        }
        self.sceneID = sceneID
        self.cards = cards
        self.settings = settings
    }
}

/// The validated scene-prompt output as FilmCore sees it (PHASE5_DESIGN §8.4) — the
/// `AssetPromptProposal` pattern: the throwing init is the last gate, re-checking the
/// storage-side limits so an unvalidated value can never reach the applier even through
/// a programming error. The same rules §8.3's semantic validator enforced on the result
/// and §7.1's storage guard enforces on every prompt row — non-empty, ≤ 64 KB UTF-8 at
/// scene scale (twice the asset cap), control-character-free other than newline and tab.
public struct ScenePromptProposal: Equatable, Sendable {
    public let sceneID: UUID
    public let body: String
    public let guidance: String
    public let durationSeconds: Int?
    public let aspectRatio: String
    public let resolution: String
    /// The settings captured at run start (§8.1); recorded on the report.
    public let settings: ScenePromptSettings

    public init(
        sceneID: UUID,
        body: String,
        guidance: String = "",
        durationSeconds: Int? = nil,
        aspectRatio: String = "",
        resolution: String = "",
        settings: ScenePromptSettings
    ) throws {
        try Self.validateBody(body)
        self.sceneID = sceneID
        self.body = body
        self.guidance = guidance
        self.durationSeconds = durationSeconds
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.settings = settings
    }

    static func validateBody(_ body: String) throws {
        guard !body.isEmpty else {
            throw ProjectStoreError.sceneOperationRefused(reason: "A prompt cannot be empty.")
        }
        guard body.utf8.count <= 64 * 1024 else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "A prompt cannot be larger than 64 KB."
            )
        }
        guard !body.unicodeScalars.contains(where: {
            $0.value < 0x20 && $0 != "\n" && $0 != "\t"
        }) else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "A prompt cannot contain control characters."
            )
        }
    }
}

public struct ScenePromptSetApplyOutcome: Sendable {
    public let report: ScenePromptApplyReport
    public let entry: JournalEntry
    public let set: ScenePromptSetDetail

    public init(report: ScenePromptApplyReport, entry: JournalEntry, set: ScenePromptSetDetail) {
        self.report = report
        self.entry = entry
        self.set = set
    }
}

/// What one scene-prompt apply produced (§8.4 step 4): the report and **the journal
/// entry** — returned to the Generation section so it routes the entry through `didApply`
/// and ⌘Z reads "Undo Generate Scene Prompt" (the §13.11 deviation, Phase 3's, repeated).
public struct ScenePromptApplyOutcome: Sendable {
    public let report: ScenePromptApplyReport
    public let entry: JournalEntry

    public init(report: ScenePromptApplyReport, entry: JournalEntry) {
        self.report = report
        self.entry = entry
    }
}
