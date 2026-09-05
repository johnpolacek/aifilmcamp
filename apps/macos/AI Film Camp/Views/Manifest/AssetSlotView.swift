import AppKit
import FilmCore
import SwiftUI

/// The requirement inspector's **slot surface** (PHASE2_DESIGN §4.1, §6.1–§6.3, §7.3 —
/// Plan 011 contract C): import, the version list with its verdicts, the stale badge with
/// its reason and Mark Current, and the asset's display state.
///
/// Presentation only. Every action routes through `ProjectWindowModel+Assets.swift`; this
/// file opens no file, builds no path, and decides nothing a refusal could disagree with —
/// the previews go through `AssetPreviewLoader`, which is the one place §4.1's containment,
/// integrity, and capped-decode rules are honoured.
///
/// Phase 3's workshop window is built on this contract, not in it: there is no prompt, no
/// provider, and no generation control here.
struct AssetSlotView: View {
    @Bindable var model: ProjectWindowModel
    let detail: RequirementDetail

    @State private var notesDraft = ""
    @State private var loadedAssetID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            stale
            slotActions
            notes
            versionList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The second import entry point (contract C): the same code path as Add Image….
        .dropDestination(for: URL.self) { urls, _ in
            guard detail.isActive,
                  let url = urls.first(where: ProjectWindowModel.acceptsDroppedImage)
            else { return false }
            let id = detail.requirement.id
            Task { await model.importWorkshopResult(requirementID: id, from: url) }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assetSlot")
        .accessibilityLabel("Reference images")
        .task(id: detail.asset?.id) {
            guard loadedAssetID != detail.asset?.id else { return }
            loadedAssetID = detail.asset?.id
            notesDraft = detail.asset?.notes ?? ""
        }
        .onChange(of: detail.asset?.notes ?? "") { _, stored in notesDraft = stored }
    }

    // MARK: - Header: §6.1's display state and the import control

    private var header: some View {
        HStack(spacing: 6) {
            Text("Reference Images").font(.headline)
            // §6.1's media axis as a chip of its own, deliberately apart from the
            // requirement's review state.
            ManifestBadge(
                text: detail.displayStatus.displayName,
                label: "Asset state: \(detail.displayStatus.displayName)",
                tint: detail.displayStatus == .approved ? .green : .secondary,
                identifier: "assetStatusChip"
            )
            Spacer(minLength: 8)
            Button("Add Image…") {
                let id = detail.requirement.id
                Task { await model.chooseAndImportWorkshopResult(requirementID: id) }
            }
            .disabled(!detail.isActive)
            .accessibilityIdentifier("assetImportButton")
            .accessibilityLabel("Add a reference image to \(detail.requirement.name)")
        }
    }

    // MARK: - §6.2's stale flag, with §3.5's reason **verbatim**

    @ViewBuilder
    private var stale: some View {
        // The reason is the stored `stale_reason` string, rendered as it was written. The
        // UI never recomposes it: FilmCore names the dependency that moved, and a second
        // wording here would be a second source of truth.
        if let asset = detail.asset, asset.isStale {
            HStack(spacing: 6) {
                Text(asset.staleReason ?? "This reference is stale.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("assetStaleBadge")
                    .accessibilityLabel(asset.staleReason ?? "This reference is stale.")
                // Offered only while the flag stands: `clearAssetStale` refuses on an asset
                // that is not stale (§3.5), so an always-visible control would be a trap.
                Button("Mark Current") {
                    Task { await model.markAssetCurrent(assetID: asset.id) }
                }
                .accessibilityIdentifier("markAssetCurrentButton")
                .accessibilityLabel("Mark this reference current")
            }
        }
    }

    // MARK: - Slot-level verdicts (§7.3)

    @ViewBuilder
    private var slotActions: some View {
        if let asset = detail.asset {
            HStack(spacing: 8) {
                if model.canRejectSelectedAsset {
                    Button("Reject Slot") {
                        Task { await model.rejectAsset(assetID: asset.id) }
                    }
                    .accessibilityIdentifier("rejectAssetButton")
                    .accessibilityLabel("Reject the reference images for \(detail.requirement.name)")
                }
                if model.canUnrejectSelectedAsset {
                    Button("Un-reject Slot") {
                        Task { await model.unrejectAsset(assetID: asset.id) }
                    }
                    .accessibilityIdentifier("unrejectAssetButton")
                    .accessibilityLabel("Un-reject the reference images for \(detail.requirement.name)")
                }
                Button("Delete All Images…") { model.confirmAssetDeletion() }
                    .accessibilityIdentifier("deleteAssetButton")
                    .accessibilityLabel("Delete every reference image for \(detail.requirement.name)")
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Notes (§7.3's `setAssetNotes`)

    @ViewBuilder
    private var notes: some View {
        if let asset = detail.asset {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Notes on these references.", text: $notesDraft, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .textFieldStyle(.roundedBorder)
                    .tracksTextEditing(model)
                    .accessibilityIdentifier("assetNotesField")
                    .accessibilityLabel("Asset notes")
                HStack {
                    Spacer()
                    Button("Save Notes") {
                        let text = notesDraft
                        Task { await model.setAssetNotes(id: asset.id, text: text) }
                    }
                    .disabled(notesDraft == asset.notes)
                    .accessibilityIdentifier("saveAssetNotesButton")
                    .accessibilityLabel("Save asset notes")
                }
            }
        }
    }

    // MARK: - The versions

    @ViewBuilder
    private var versionList: some View {
        if detail.versions.isEmpty {
            Text("No reference images yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("assetVersionsEmptyText")
                .accessibilityLabel("No reference images yet")
        } else {
            ForEach(detail.versions) { version in
                AssetVersionRow(model: model, detail: detail, version: version)
            }
        }
    }
}

/// One version: its capped preview (or the damaged-asset warning), its status, and §7.3's
/// four verdicts over it.
struct AssetVersionRow: View {
    @Bindable var model: ProjectWindowModel
    let detail: RequirementDetail
    let version: AssetVersion

    @State private var preview = AssetPreviewLoader.Preview.empty

    private var title: String { "v\(version.versionNumber)" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) · \(version.status.displayName) · \(version.originalFileName)")
                    .font(.caption)
                    .accessibilityIdentifier("assetVersionRow")
                    .accessibilityLabel(
                        "Version \(version.versionNumber), \(version.status.displayName), "
                            + version.originalFileName
                    )
                if let damage = preview.damage {
                    Text(damage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("assetVersionDamagedBadge")
                        .accessibilityLabel("Version \(version.versionNumber) damaged: \(damage)")
                }
                actions
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        // Reloaded whenever the row's bytes could have changed under it: a new refresh
        // token means an operation landed, and the path identifies the file.
        .task(id: "\(version.relativePath.rawValue)#\(model.refreshToken)") {
            let containment = model.mediaContainment
            let version = version
            preview = await Task.detached(priority: .utility) {
                AssetPreviewLoader.load(containment: containment, version: version)
            }.value
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let data = preview.thumbnailPNG, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: preview.damage == nil ? "photo" : "exclamationmark.triangle")
                    .foregroundStyle(preview.damage == nil ? Color.secondary : Color.orange)
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityIdentifier("assetVersionThumbnail")
        .accessibilityLabel("Preview of version \(version.versionNumber)")
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if version.status != .approved, let asset = detail.asset {
                Button("Approve") {
                    Task { await model.approveVersion(assetID: asset.id, versionID: version.id) }
                }
                .accessibilityIdentifier("approveVersionButton")
                .accessibilityLabel("Approve version \(version.versionNumber)")
            }
            if version.status == .rejected {
                Button("Un-reject") {
                    Task { await model.unrejectVersion(versionID: version.id) }
                }
                .accessibilityIdentifier("unrejectVersionButton")
                .accessibilityLabel("Un-reject version \(version.versionNumber)")
            } else {
                Button("Reject") {
                    Task { await model.rejectVersion(versionID: version.id) }
                }
                .accessibilityIdentifier("rejectVersionButton")
                .accessibilityLabel("Reject version \(version.versionNumber)")
            }
            // §7.3: only a **rejected** version may be deleted, and the deletion is
            // non-invertible — so the control appears only where it is allowed and always
            // through the confirmation.
            if model.canDeleteVersion(version) {
                Button("Delete…") { model.confirmVersionDeletion(version) }
                    .accessibilityIdentifier("deleteVersionButton")
                    .accessibilityLabel("Delete version \(version.versionNumber)")
            }
            Button("Reveal in Finder") {
                Task { await model.revealVersionInFinder(version) }
            }
            .accessibilityIdentifier("revealVersionButton")
            .accessibilityLabel("Reveal version \(version.versionNumber) in Finder")
        }
    }
}

extension AssetVersionStatus {
    /// Three of §6.1's asset-state names, reused for versions — same words, so a version
    /// badge and an asset chip never describe the same verdict differently.
    var displayName: String {
        switch self {
        case .needsReview: "Needs Review"
        case .approved: "Approved"
        case .rejected: "Rejected"
        }
    }
}
