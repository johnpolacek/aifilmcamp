import Foundation
import GRDB

/// PHASE3_DESIGN §6.1's **one** recompute rule, as a pure function over rows — the
/// amended seven-rule form (§13.1's owner delta, accepted 2026-08-22):
///
/// > ```text
/// > recompute(asset):
/// >   1. requirement rejected or necessity = not_needed   → deprecated
/// >   2. an approved version exists                       → approved
/// >   3. explicit rejection standing                      → rejected
/// >   4. at least one version row                         → needs_review
/// >   5. in_progress_since is set                         → in_progress   [NEW]
/// >   6. any prompt row exists for the requirement        → prompt_ready  [NEW]
/// >   7. otherwise                                        → needed
/// > ```
///
/// Rules 1–4 are byte-identical to Phase 2's five-rule form; the two new rows slot
/// strictly below them. Still the **only** writer of `assets.status`, still a pure
/// function of stored rows — the derived prompt staleness (§3.4) is deliberately not an
/// input — and still run at the end of every asset/version/prompt operation, agreed-with
/// by construction on the inverse path.
///
/// The function is deliberately **ahead of its operations** (the Plan 010/011 seam):
/// Plan 014's operations drive it for real; Plans 015/016 surface it and must not
/// redefine it.
///
/// Rule 1 is requirement-level only. Entity-level inactivity (§6.4) is a read-time concern:
/// it removes the requirement from the active set and badges it, but never rewrites a stored
/// asset status, which is why §7.4's entity tombstoning touches no requirement rows.
///
/// `rejectedExplicitly` (§6.1 rule 3) is **untouched by deprecation**, so a rejected slot
/// that is retired and later restored comes back `rejected` rather than quietly reopened —
/// and un-rejecting a requirement that is still `not_needed` leaves its asset `deprecated`,
/// because rule 1 checks **both** causes.
public enum AssetStatusRecompute {

    /// Everything §6.1's seven rules need about one asset and the requirement it fills.
    public struct Inputs: Equatable, Hashable, Sendable {
        /// The requirement's PROV `review_state`.
        public let requirementReviewState: ReviewState
        /// The requirement's `necessity`.
        public let requirementNecessity: RequirementNecessity
        /// `true` when one of the asset's version rows is `approved` (§4.3's partial unique
        /// index gives at most one).
        public let hasApprovedVersion: Bool
        /// `assets.rejected_explicitly` — rule 3's standing explicit rejection.
        public let rejectedExplicitly: Bool
        /// How many `asset_versions` rows the asset owns.
        public let versionCount: Int
        /// `assets.in_progress_since` — rule 5's marker (§6.1); `nil` until
        /// `markAssetInProgress` sets it.
        public let inProgressSince: Date?
        /// How many `asset_prompts` rows name this requirement (current and history alike).
        public let promptCount: Int

        public init(
            requirementReviewState: ReviewState,
            requirementNecessity: RequirementNecessity,
            hasApprovedVersion: Bool,
            rejectedExplicitly: Bool,
            versionCount: Int,
            inProgressSince: Date?,
            promptCount: Int
        ) {
            self.requirementReviewState = requirementReviewState
            self.requirementNecessity = requirementNecessity
            self.hasApprovedVersion = hasApprovedVersion
            self.rejectedExplicitly = rejectedExplicitly
            self.versionCount = versionCount
            self.inProgressSince = inProgressSince
            self.promptCount = promptCount
        }

    }

    /// §6.1's seven rules, in order. The **only** function that decides an `assets.status`.
    public static func status(for inputs: Inputs) -> AssetStatus {
        // 1. Both causes of requirement-level inactivity, checked together.
        if inputs.requirementReviewState == .rejected || inputs.requirementNecessity == .notNeeded {
            return .deprecated
        }
        // 2. An approved version is the canonical reference (§6.1's invariant).
        if inputs.hasApprovedVersion { return .approved }
        // 3. The filmmaker rejected the slot's media as a whole.
        if inputs.rejectedExplicitly { return .rejected }
        // 4. Media awaiting a verdict — any version row outranks both new states.
        if inputs.versionCount > 0 { return .needsReview }
        // 5. A marker without versions: generation underway. Legal without a prompt (the
        //    filmmaker may be generating from something outside the app).
        if inputs.inProgressSince != nil { return .inProgress }
        // 6. Prompts exist, media does not.
        if inputs.promptCount > 0 { return .promptReady }
        // 7. An asset row with nothing behind it.
        return .needed
    }

    /// The convenience overload, spelled as the seven facts rather than the struct.
    public static func status(
        requirementReviewState: ReviewState,
        requirementNecessity: RequirementNecessity,
        hasApprovedVersion: Bool,
        rejectedExplicitly: Bool,
        versionCount: Int,
        inProgressSince: Date?,
        promptCount: Int
    ) -> AssetStatus {
        status(
            for: Inputs(
                requirementReviewState: requirementReviewState,
                requirementNecessity: requirementNecessity,
                hasApprovedVersion: hasApprovedVersion,
                rejectedExplicitly: rejectedExplicitly,
                versionCount: versionCount,
                inProgressSince: inProgressSince,
                promptCount: promptCount
            )
        )
    }
}

// MARK: - Applying the rule to a stored row

extension AssetStatusRecompute {
    /// What one recompute did, for the operation folding it into its effect.
    struct Applied {
        /// The asset row exactly as it was **before** the recompute, or `nil` when the
        /// requirement has no asset row (the ordinary Phase 2a case).
        var snapshot: RowSnapshot?
        var assetID: UUID?
        var status: AssetStatus?

        var affected: Set<SubjectRef> {
            guard let assetID else { return [] }
            return [SubjectRef(kind: .asset, id: assetID)]
        }

        var snapshots: [RowSnapshot] { snapshot.map { [$0] } ?? [] }
    }

    /// Recomputes the asset of one requirement, writing `status` and nothing else.
    ///
    /// No transaction is opened (§7.1): the caller's is the one that counts. A requirement
    /// with no asset row is the no-op case — Plan 010's operations never create one.
    static func recompute(
        requirementID: UUID,
        reviewState: ReviewState,
        necessity: RequirementNecessity,
        in db: Database
    ) throws -> Applied {
        guard let assetRow = try Row.fetchOne(
            db,
            sql: "SELECT * FROM assets WHERE requirement_id = ?",
            arguments: [requirementID.uuidString]
        ) else { return Applied() }

        let assetID = try UUID.required(assetRow["id"])
        let versionCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM asset_versions WHERE asset_id = ?",
            arguments: [assetID.uuidString]
        ) ?? 0
        let hasApproved = try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM asset_versions WHERE asset_id = ? AND status = 'approved'
                )
                """,
            arguments: [assetID.uuidString]
        ) ?? false
        // §6.1's two new inputs, both stored rows only — never the derived staleness.
        var marker: Date?
        if let raw = assetRow["in_progress_since"] as String? {
            marker = try UTCDate.date(from: raw)
        }
        let promptCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM asset_prompts WHERE requirement_id = ?",
            arguments: [requirementID.uuidString]
        ) ?? 0

        let status = status(
            requirementReviewState: reviewState,
            requirementNecessity: necessity,
            hasApprovedVersion: hasApproved,
            rejectedExplicitly: (assetRow["rejected_explicitly"] as Int) != 0,
            versionCount: versionCount,
            inProgressSince: marker,
            promptCount: promptCount
        )
        let snapshot = RowSnapshot(table: "assets", row: assetRow)
        // `rejected_explicitly` is deliberately not written here: deprecation preserves it
        // (§6.3), and only §7.3's asset operations set or clear it.
        try db.execute(
            sql: "UPDATE assets SET status = ?, updated_at = ? WHERE id = ?",
            arguments: [status.rawValue, UTCDate.string(from: Date()), assetID.uuidString]
        )
        return Applied(snapshot: snapshot, assetID: assetID, status: status)
    }
}
