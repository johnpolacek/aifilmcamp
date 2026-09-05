import Foundation

/// What one manifest-inference run asked FilmCore to change, and what it did
/// (PHASE2_DESIGN §8.5).
///
/// It shares one nullable JSON column with `ApplyReport` — `jobs.apply_report` — and is
/// written through the typed door `setManifestReport` (§7.5), which refuses any job whose
/// task is not `inferAssetManifest`. `Job.manifestReport` gates on the same task, so run
/// history can never cross-decode one report type as the other.
///
/// **The two types stay key-disjoint** (§4.4), and the property names of §8.5 overlap
/// `ApplyReport`'s (`skippedLocked`, `skippedProtected`, `skippedRejected`, `durationMs`,
/// `settings`). Disjointness is therefore made structural rather than accidental: every
/// stored key of this type carries the `manifest` prefix, so a new counter added later
/// cannot silently re-collide. `ReportTypeTests` asserts the disjointness programmatically
/// from the two encoded key sets.
public struct ManifestApplyReport: Codable, Equatable, Hashable, Sendable {
    /// Requirement, scene-link, basis, and dependency rows the run created.
    public var created: Int
    /// Proposals that matched a row already in the project.
    public var skippedExisting: Int
    /// Proposals that resolved to a `rejected` tombstone (§3.6, as extraction does).
    public var skippedRejected: Int
    /// Proposals aimed at a protected row — `human`, or `ai` + `accepted` (§3.6).
    public var skippedProtected: Int
    public var skippedLocked: Int
    /// Advisory `manifest_inclusion` suggestions, persisted in full so the advisory UI
    /// survives reopen (§3.4).
    public var suggestions: [ManifestInclusionSuggestion]
    public var durationMs: Int
    /// The settings captured at run start, so the recorded run is reproducible against the
    /// settings it actually ran with.
    public var settings: ManifestSettings

    public init(
        created: Int = 0,
        skippedExisting: Int = 0,
        skippedRejected: Int = 0,
        skippedProtected: Int = 0,
        skippedLocked: Int = 0,
        suggestions: [ManifestInclusionSuggestion] = [],
        durationMs: Int = 0,
        settings: ManifestSettings = ManifestSettings()
    ) {
        self.created = created
        self.skippedExisting = skippedExisting
        self.skippedRejected = skippedRejected
        self.skippedProtected = skippedProtected
        self.skippedLocked = skippedLocked
        self.suggestions = suggestions
        self.durationMs = durationMs
        self.settings = settings
    }

    /// The prefix every stored key carries, so key-disjointness with `ApplyReport` is a
    /// property of the type rather than of today's field list.
    static let keyPrefix = "manifest"

    enum CodingKeys: String, CodingKey {
        case created = "manifestCreated"
        case skippedExisting = "manifestSkippedExisting"
        case skippedRejected = "manifestSkippedRejected"
        case skippedProtected = "manifestSkippedProtected"
        case skippedLocked = "manifestSkippedLocked"
        case suggestions = "manifestSuggestions"
        case durationMs = "manifestDurationMs"
        case settings = "manifestSettings"
    }
}

/// The manifest-inference knobs a run captures at start (§8.1, §8.5).
///
/// Model ids and reasoning efforts are runtime values typed by the operator — FilmCore
/// never hard-codes a catalog and never validates them, so both are plain strings and
/// `nil` means "the account's Codex default", exactly as in `ExtractionSettings`.
public struct ManifestSettings: Codable, Equatable, Hashable, Sendable {
    public var model: String?
    public var effort: String?
    /// The §8.1 input budget, in UTF-16 code units of the built input.
    public var inputBudgetUTF16: Int

    public init(model: String? = nil, effort: String? = nil, inputBudgetUTF16: Int = 0) {
        self.model = model
        self.effort = effort
        self.inputBudgetUTF16 = inputBudgetUTF16
    }
}

/// One advisory suggestion that an entity's `manifest_inclusion` be changed (§3.4, §8.5).
///
/// Advisory only: the run never writes `manifest_inclusion` itself — the filmmaker acts on
/// the suggestion, or does not.
public struct ManifestInclusionSuggestion: Codable, Equatable, Hashable, Sendable {
    /// Which way the run suggests moving the entity's inclusion.
    public enum Direction: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
        /// Into the manifest — `'always'` (§3.4's prop exception).
        case promote
        /// Out of it — `'never'`.
        case suppress
    }

    public let entityID: UUID
    public let direction: Direction
    public let reason: String
    public let confidence: Double?

    public init(entityID: UUID, direction: Direction, reason: String, confidence: Double? = nil) {
        self.entityID = entityID
        self.direction = direction
        self.reason = reason
        self.confidence = confidence
    }
}
