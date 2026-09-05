import Foundation

/// `docs/OVERVIEW.md#asset-states`, stored on `assets.status` (PHASE2_DESIGN §6.1).
///
/// The full canonical set is admitted by the `CHECK` so Phase 3 needs no migration; Phase
/// 2 reaches five of the seven (`promptReady` and `inProgress` are Phase 3's). The status
/// is written **only** by §6.3's one recompute rule — never assigned ad hoc.
public enum AssetStatus: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    /// An asset row with zero version rows; also the *derived* display state of a
    /// requirement with no asset row at all.
    case needed
    /// Phase 3: a prompt was generated and nothing has been imported.
    case promptReady = "prompt_ready"
    /// Phase 3: a generation workflow is underway.
    case inProgress = "in_progress"
    /// At least one version, none approved, no standing explicit rejection.
    case needsReview = "needs_review"
    /// Exactly one approved version — the canonical reference (§6.1's invariant).
    case approved
    /// The filmmaker rejected the slot's media as a whole (`rejected_explicitly`).
    case rejected
    /// Retired because its requirement is rejected or `not_needed`; media is kept, and an
    /// approved version may still stand so restoring is lossless (§6.1).
    case deprecated
}

/// One `assets` row: the media slot of exactly one requirement (§4.3, §6.1).
///
/// Staleness is an orthogonal flag, not a state (§6.2): an Approved asset that is stale is
/// still Approved, badged with `staleReason`. `rejectedExplicitly` is §6.3 rule 3's
/// column — it survives deprecation, so a rejected slot that is retired and restored comes
/// back rejected rather than quietly reopened.
///
/// The PROV `reviewState` on an asset is **inert** (§3.7): assets are human-created, born
/// `accepted`, and their entire working lifecycle lives in `status`.
public struct Asset: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let requirementID: UUID
    public let status: AssetStatus
    public let isStale: Bool
    /// Non-nil exactly when `isStale` (§4.3's paired CHECKs).
    public let staleSince: Date?
    /// Non-nil exactly when `isStale`.
    public let staleReason: String?
    /// §6.3 rule 3's standing explicit rejection.
    public let rejectedExplicitly: Bool
    public let notes: String
    public let provenance: Provenance

    public init(
        id: UUID,
        projectID: UUID,
        requirementID: UUID,
        status: AssetStatus,
        isStale: Bool,
        staleSince: Date?,
        staleReason: String?,
        rejectedExplicitly: Bool,
        notes: String,
        provenance: Provenance
    ) {
        self.id = id
        self.projectID = projectID
        self.requirementID = requirementID
        self.status = status
        self.isStale = isStale
        self.staleSince = staleSince
        self.staleReason = staleReason
        self.rejectedExplicitly = rejectedExplicitly
        self.notes = notes
        self.provenance = provenance
    }
}
