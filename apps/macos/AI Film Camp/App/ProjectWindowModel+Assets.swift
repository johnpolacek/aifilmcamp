import FilmCore
import Foundation

/// The fill-and-approve surface's state and commands on the **window model**
/// (PHASE2_DESIGN §4.1, §6.1–§6.4, §7.3 — Plan 011 contract C).
///
/// Same rule as the Manifest extension next door: every predicate, every refusal, and
/// every path lives here rather than in a view. A view offers a control, reads a value,
/// and calls a method; it never constructs an `EditOperation`, never opens a file, and
/// never decides whether a version may be deleted.
///
/// Two shapes are specific to media:
///
/// * **Containment on every path.** Preview, hash verification, and Reveal in Finder all
///   open the file through `BundleContainment` (§4.1's "every read that opens the file"),
///   so a symlinked `assets/` component or a symlinked leaf refuses the operation with
///   FilmCore's own error surfaced verbatim instead of being followed out of the bundle.
/// * **Confirmation before destruction.** `deleteVersion` and `deleteAsset` are the only
///   two gestures that destroy media, and both are non-invertible (§7.3), so each is armed
///   as a pending value and performed only on confirm — the Phase 1 delete-confirmation
///   shape, reused.
@MainActor
extension ProjectWindowModel {

    // MARK: - Containment (§4.1)

    /// The descriptor-relative door for every media path this window opens. FilmCore keeps
    /// its own copy internal; the app builds one over the same bundle root.
    var mediaContainment: BundleContainment { BundleContainment(rootURL: bundleURL) }

    // MARK: - §6.4's Missing scope

    /// The requirement ids `missingAssets()` reports, for the scope filter and the list's
    /// blocked badge.
    var missingRequirementIDs: Set<UUID> { Set(missingAssets.map(\.requirementID)) }

    /// The rows the Manifest list shows: what the review filter read, narrowed to §6.4's
    /// Missing set when the scope asks for it.
    var scopedRequirementSummaries: [RequirementSummary] {
        switch manifestScope {
        case .all: return requirementSummaries
        case .missing:
            let missing = missingRequirementIDs
            return requirementSummaries.filter { missing.contains($0.id) }
        }
    }

    /// The scope is a filter over rows the read layer already produced, not a second query
    /// — `missingAssets()` and `requirementSummaries()` are read on the same beat, so no
    /// refresh is needed to switch between them.
    func setManifestScope(_ scope: ManifestScopeFilter) {
        guard scope != manifestScope else { return }
        manifestScope = scope
        renamingRequirementID = nil
    }

    /// Whether a requirement is one of §6.4's Missing rows — the badge the Missing scope
    /// shows beside each row's blocked state.
    func isMissing(_ requirementID: UUID) -> Bool {
        missingRequirementIDs.contains(requirementID)
    }

    // MARK: - Import (§4.1, §7.3)

    /// Whether the inspected requirement can take media at all: `importAssetVersion` is
    /// refused while the requirement is inactive (§6.3), and saying so up front beats
    /// surfacing the refusal after an open panel.
    var canImportIntoSelectedRequirement: Bool {
        guard !isClosed, let detail = requirementDetail else { return false }
        return detail.isActive
    }

    /// Add Image…: the injected chooser, then the one import path.
    func chooseAndImportAssetVersion(requirementID: UUID) async {
        guard !isClosed, let url = await imageChooser() else { return }
        await importAssetVersion(requirementID: requirementID, from: url)
    }

    /// The single media-import code path — the inspector's button and its drop target both
    /// land here (contract C), exactly as the three screenplay entry points share one.
    ///
    /// The whole group is one journal entry (§7.3: the implicit accept, `createAsset`, and
    /// the version insert), so it is one undo step and `runEdit` needs no special case.
    func importAssetVersion(requirementID: UUID, from url: URL) async {
        await runEdit {
            try await self.session.importAssetVersion(
                requirementID: requirementID, from: url, actor: .human
            ).entry
        }
    }

    /// Whether a dropped file is one the importer will even look at — the same five types
    /// the open panel offers, from FilmCore's own list. Content still decides at import:
    /// this only keeps an obviously wrong drop from opening a transaction.
    static func acceptsDroppedImage(_ url: URL) -> Bool {
        ImageFormat.acceptedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - The version verdicts (§7.3)

    func approveVersion(assetID: UUID, versionID: UUID) async {
        await runEdit {
            try await self.session.approveVersion(
                assetID: assetID, versionID: versionID, actor: .human
            )
        }
    }

    func rejectVersion(versionID: UUID) async {
        await runEdit { try await self.session.rejectVersion(versionID: versionID, actor: .human) }
    }

    /// §6.3's asymmetry, stated where the button is: the *user gesture* always lands on
    /// `needs_review`. Only the inverse restores a snapshotted prior status.
    func unrejectVersion(versionID: UUID) async {
        await runEdit { try await self.session.unrejectVersion(versionID: versionID, actor: .human) }
    }

    // MARK: - The slot verdicts (§7.3)

    /// `rejectAsset`'s precondition is "no approved version" (§7.3); the control is offered
    /// only when it holds, so the operator never meets a refusal they could see coming.
    var canRejectSelectedAsset: Bool {
        guard let detail = requirementDetail, let asset = detail.asset else { return false }
        return !asset.rejectedExplicitly && !detail.versions.contains { $0.status == .approved }
    }

    var canUnrejectSelectedAsset: Bool {
        requirementDetail?.asset?.rejectedExplicitly == true
    }

    func rejectAsset(assetID: UUID) async {
        await runEdit { try await self.session.rejectAsset(assetID: assetID, actor: .human) }
    }

    func unrejectAsset(assetID: UUID) async {
        await runEdit { try await self.session.unrejectAsset(assetID: assetID, actor: .human) }
    }

    /// §3.5's explicit **Mark Current**. FilmCore refuses it on an asset that is not stale,
    /// so the control is offered only while the flag stands.
    func markAssetCurrent(assetID: UUID) async {
        await runEdit { try await self.session.clearAssetStale(assetID: assetID, actor: .human) }
    }

    func setAssetNotes(id: UUID, text: String) async {
        await runEdit { try await self.session.setAssetNotes(id: id, text: text, actor: .human) }
    }

    func setVersionNotes(id: UUID, text: String) async {
        await runEdit { try await self.session.setVersionNotes(id: id, text: text, actor: .human) }
    }

    // MARK: - The two destructive gestures (§7.3, §4.1)

    /// Delete is offered on a **rejected** version only; FilmCore refuses any other, and
    /// the button says so by not being there.
    func canDeleteVersion(_ version: AssetVersion) -> Bool { version.status == .rejected }

    /// Arms the version-deletion confirmation. A version that is not rejected arms nothing
    /// at all — FilmCore would refuse it, and the inspector does not offer the control.
    func confirmVersionDeletion(_ version: AssetVersion) {
        guard canDeleteVersion(version) else { return }
        pendingMediaDeletion = PendingMediaDeletion(
            target: .version(id: version.id, number: version.versionNumber),
            requirementName: requirementDetail?.requirement.name ?? ""
        )
    }

    /// Arms the whole-slot deletion (§7.3's `deleteAsset`).
    func confirmAssetDeletion() {
        guard let detail = requirementDetail, let asset = detail.asset else { return }
        pendingMediaDeletion = PendingMediaDeletion(
            target: .asset(id: asset.id, versionCount: detail.versions.count),
            requirementName: detail.requirement.name
        )
    }

    /// Takes the armed value rather than reading it back, for the reason
    /// `performDeletion(_:)` documents: a `confirmationDialog` clears its binding as it
    /// dismisses, which can land before the button's own action.
    ///
    /// Both branches are non-invertible, so `didApply` clears the undo stack on its own —
    /// the entry FilmCore returns carries no inverse.
    func performMediaDeletion(_ pending: PendingMediaDeletion) async {
        pendingMediaDeletion = nil
        switch pending.target {
        case let .version(id, _):
            await runEdit { try await self.session.deleteVersion(versionID: id, actor: .human) }
        case let .asset(id, _):
            await runEdit { try await self.session.deleteAsset(assetID: id, actor: .human) }
        }
    }

    func confirmPendingMediaDeletion() async {
        guard let pending = pendingMediaDeletion else { return }
        await performMediaDeletion(pending)
    }

    func cancelPendingMediaDeletion() { pendingMediaDeletion = nil }

    // MARK: - Reveal in Finder, through containment (§4.1)

    /// Reveal opens the file, so it pays §4.1's rule like every other read: the leaf is
    /// walked descriptor-relative first, and a symlinked component or leaf refuses with
    /// `BundleContainmentError`'s own wording rather than pointing Finder outside the
    /// bundle. Only then is the path resolved for `NSWorkspace`.
    func revealVersionInFinder(_ version: AssetVersion) async {
        guard !isClosed else { return }
        do {
            let kind = try mediaContainment.entryKind(at: version.relativePath)
            guard kind == .file else {
                throw BundleContainmentError.missingComponent(
                    path: version.relativePath.rawValue,
                    component: version.relativePath.rawValue
                )
            }
            let url = try await session.resolve(version.relativePath)
            finderRevealer(url)
        } catch {
            self.error = .project(error)
        }
    }

    // MARK: - Clear Orphaned Media (§4.1)

    /// Lists the orphans and arms the confirmation. An empty sweep reports "nothing to
    /// remove" through the same summary the real one uses, rather than a silent no-op.
    func beginOrphanSweep() async {
        guard !isClosed else { return }
        do {
            let paths = try await session.orphanedMedia()
            if paths.isEmpty {
                presentedOrphanSummary = CacheSummaryPresentation(
                    summary: ClearedCacheSummary(bytesFreed: 0, filesRemoved: 0)
                )
                return
            }
            pendingOrphanSweep = PendingOrphanSweep(paths: paths)
        } catch {
            self.error = .project(error)
        }
    }

    /// The confirm action. It journals nothing and touches no row (§4.1), so there is no
    /// entry to register and no undo step — but a pending **redo** of an undone import
    /// whose file this removed will now refuse cleanly, which is the walk §7.3 pins.
    func performOrphanSweep(_ pending: PendingOrphanSweep) async {
        pendingOrphanSweep = nil
        do {
            let summary = try await session.clearOrphanedMedia(confirming: pending.paths)
            presentedOrphanSummary = CacheSummaryPresentation(summary: summary)
            await refresh()
        } catch {
            self.error = .project(error)
        }
    }

    func confirmPendingOrphanSweep() async {
        guard let pending = pendingOrphanSweep else { return }
        await performOrphanSweep(pending)
    }

    func cancelPendingOrphanSweep() { pendingOrphanSweep = nil }
}

/// The Manifest list's scope beside §8.6's review filters (PHASE2_DESIGN §6.4).
///
/// It is deliberately a **second** control rather than a fifth review case: review state
/// and "is this slot still missing media" are the two orthogonal axes of §6.1, and folding
/// them into one row of buttons would suggest they exclude each other.
enum ManifestScopeFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Every row the review filter admits.
    case all
    /// §6.4's Missing: active, `required`, and the asset is absent or not Approved.
    case missing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Everything"
        case .missing: "Missing"
        }
    }
}

extension ProjectWindowModel {
    /// Plan 015's Empty Slot action (§14.2): the shipped destructive path — rows in the
    /// transaction, files after commit, both behind the workshop confirm whose copy says
    /// "Prompts are kept." The operation spares prompt rows by contract (Plan 014).
    func performDestructiveAssetDeletion(assetID: UUID) async {
        guard let detail = requirementDetail else { return }
        await performMediaDeletion(PendingMediaDeletion(
            target: .asset(id: assetID, versionCount: detail.versions.count),
            requirementName: detail.requirement.name
        ))
    }
}
