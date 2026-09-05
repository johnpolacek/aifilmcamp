import Foundation

/// What one extraction run asked FilmCore to change, and what it did (PHASE1_DESIGN §8.5).
///
/// `jobs.apply_report` holds exactly this value: before apply with `settings` filled and
/// every counter zero, after apply with the counters the run produced. It is a **FilmCore**
/// type because FilmCore may not import FilmBrain (§3.1), and it is declared here in Plan
/// 005 — rather than in Plan 007, which populates it — so `EditOperation` can carry the
/// `.applyExtractionRun` summary row that selective revert must skip (§3.8).
public struct ApplyReport: Codable, Equatable, Hashable, Sendable {
    /// Rows created or updated from the run's proposals.
    public var applied: Int
    /// `ai/proposed` rows this run replaced or removed as stale (§8.5 rule 4a).
    public var replaced: Int
    public var mergesApplied: Int
    /// Advisory merges the run proposed and the operator has not acted on.
    public var mergesSuggested: Int
    public var skippedLocked: Int
    public var skippedProtected: Int
    public var skippedParserOwned: Int
    /// Proposals that resolved to a `rejected` tombstone (§3.6).
    public var skippedRejected: Int
    /// Alias inserts skipped because the normalized form belongs to a third entity (§3.5).
    public var aliasConflicts: Int
    public var unanchoredEvidence: Int
    public var chunksFailed: Int
    /// Scene ordinals no completed chunk covered, ascending.
    public var uncoveredSceneOrdinals: [Int]
    public var durationMs: Int
    /// The settings captured at run start (§8.4); a preference edited mid-run does not apply.
    public var settings: ExtractionSettings

    public init(
        applied: Int = 0,
        replaced: Int = 0,
        mergesApplied: Int = 0,
        mergesSuggested: Int = 0,
        skippedLocked: Int = 0,
        skippedProtected: Int = 0,
        skippedParserOwned: Int = 0,
        skippedRejected: Int = 0,
        aliasConflicts: Int = 0,
        unanchoredEvidence: Int = 0,
        chunksFailed: Int = 0,
        uncoveredSceneOrdinals: [Int] = [],
        durationMs: Int = 0,
        settings: ExtractionSettings = ExtractionSettings()
    ) {
        self.applied = applied
        self.replaced = replaced
        self.mergesApplied = mergesApplied
        self.mergesSuggested = mergesSuggested
        self.skippedLocked = skippedLocked
        self.skippedProtected = skippedProtected
        self.skippedParserOwned = skippedParserOwned
        self.skippedRejected = skippedRejected
        self.aliasConflicts = aliasConflicts
        self.unanchoredEvidence = unanchoredEvidence
        self.chunksFailed = chunksFailed
        self.uncoveredSceneOrdinals = uncoveredSceneOrdinals
        self.durationMs = durationMs
        self.settings = settings
    }
}

/// The extraction knobs a run captures at start (§8.4).
///
/// Model ids and reasoning efforts are runtime values typed by the operator — FilmCore
/// never hard-codes a catalog and never validates them, so both are plain strings and
/// `nil` means "the account's Codex default".
public struct ExtractionSettings: Codable, Equatable, Hashable, Sendable {
    public var chunkModel: String?
    public var chunkEffort: String?
    public var reconcileModel: String?
    public var reconcileEffort: String?
    /// The chunk size budget, in characters of screenplay text (§8.2).
    public var chunkBudget: Int
    /// Bounded fan-out after the warm-up chunk (§8.4).
    public var concurrency: Int

    public init(
        chunkModel: String? = nil,
        chunkEffort: String? = nil,
        reconcileModel: String? = nil,
        reconcileEffort: String? = nil,
        chunkBudget: Int = 0,
        concurrency: Int = 0
    ) {
        self.chunkModel = chunkModel
        self.chunkEffort = chunkEffort
        self.reconcileModel = reconcileModel
        self.reconcileEffort = reconcileEffort
        self.chunkBudget = chunkBudget
        self.concurrency = concurrency
    }
}
