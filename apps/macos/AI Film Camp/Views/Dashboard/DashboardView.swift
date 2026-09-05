import FilmCore
import SwiftUI

/// PHASE4_DESIGN §5.3's Dashboard section (Plan 017 contract C): panels 1–3 in order —
/// scenes, Top Unblockers, assets — every figure from the one readiness snapshot, every
/// list row a deep link, and blockers before totals (the OVERVIEW Stage 12 instruction).
///
/// Panel 4 (Suggestions) is Plan 018's and does not render here — hidden-not-broken.
/// The Generation Packages block (PHASE5_DESIGN §6.1, Plan 020) now renders beneath the
/// assets panel — Phase 4 left it deliberately absent ("wait for Phase 5 rather than
/// rendering empty") — fed by the same one-read beat as the Generation section (§3.3).
struct DashboardView: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        if model.scenes.isEmpty {
            ContentUnavailableView(
                ProjectSection.dashboard.emptyStateText,
                systemImage: ProjectSection.dashboard.systemImage
            )
        } else if let snapshot = model.readinessSnapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    scenesPanel(snapshot)
                    unblockersPanel(snapshot)
                    assetsPanel(snapshot)
                    generationPackagesPanel()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: ProjectSection.dashboard.systemImage)
        }
    }

    // MARK: - Panel 1: Scenes

    @ViewBuilder
    private func scenesPanel(_ snapshot: ReadinessSnapshot) -> some View {
        let summary = snapshot.summary
        VStack(alignment: .leading, spacing: 8) {
            Text("Scenes").font(.headline)
            HStack(spacing: 12) {
                stateButton("Asset Ready", summary.assetReady, .assetReady)
                stateButton("Partial", summary.partial, .partial)
                stateButton("Blocked", summary.blocked, .blocked)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dashboardSceneCounts")

            // The excluded figure rendered small beside the three pinned states (§3.4):
            // omitted scenes and the preamble are listed, never counted.
            Text("\(summary.excluded) omitted")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dashboardExcludedCounts")

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Clicking a state filters the Scenes section with that readiness filter preset.
    private func stateButton(_ name: String, _ count: Int, _ state: SceneReadinessState) -> some View {
        Button {
            Task { await model.showScenesFiltered(by: state) }
        } label: {
            Text("\(name) · \(count)")
        }
        .buttonStyle(.link)
        .accessibilityIdentifier("dashboardSceneState_\(state.rawValue)")
        .accessibilityLabel("\(count) scenes \(name)")
    }

    // MARK: - Panel 2: Top Unblockers

    @ViewBuilder
    private func unblockersPanel(_ snapshot: ReadinessSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Unblockers").font(.headline)

            if snapshot.impacts.isEmpty {
                Text("Nothing is missing yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // The head of §3.5's ranking; the full ranking is one disclosure away.
            ForEach(Array(snapshot.impacts.prefix(5).enumerated()), id: \.element.id) {
                index, impact in
                topUnblockerRow(impact, rank: index + 1)
            }

            if snapshot.impacts.count > 5 {
                DisclosureGroup("All \(snapshot.impacts.count) missing assets") {
                    ForEach(Array(snapshot.impacts.dropFirst(5).enumerated()), id: \.element.id) {
                        index, impact in
                        topUnblockerRow(impact, rank: index + 6)
                    }
                }
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(DashboardCopy.boundPerAsset)
                Text(DashboardCopy.boundAdvancesNotCompletes)
                Text(DashboardCopy.boundSoleUnsatisfied)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("topUnblockerHelpText")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("topUnblockersPanel")
    }

    private func topUnblockerRow(_ impact: UnblockerImpact, rank: Int) -> some View {
        Button {
            Task { await model.reveal(.requirement(id: impact.requirementID)) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(impact.entityName) — \(impact.requirementName)")
                    .foregroundStyle(.primary)
                Text(
                    "advances \(impact.unfinishedSceneCount) unfinished scene"
                        + "\(impact.unfinishedSceneCount == 1 ? "" : "s")"
                        + " · unblocks \(impact.unblocksRequirementCount) other asset"
                        + "\(impact.unblocksRequirementCount == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("topUnblockerRow_\(rank)")
        .accessibilityLabel(
            "Top blocker \(rank): \(impact.entityName) — \(impact.requirementName), "
                + "advances \(impact.unfinishedSceneCount) unfinished scenes, "
                + "unblocks \(impact.unblocksRequirementCount) other assets"
        )
    }

    // MARK: - Panel 3: Assets

    @ViewBuilder
    private func assetsPanel(_ snapshot: ReadinessSnapshot) -> some View {
        let counts = model.manifestSummary?.overall
        VStack(alignment: .leading, spacing: 8) {
            Text("Assets").font(.headline)

            // The roadmap's "214 / 247 ready" line, defined on the surface: approved
            // active requirements over all active requirements (§13.12).
            Text("\(snapshot.summary.requirementsApproved) / \(snapshot.summary.requirementsTotal) ready")
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .accessibilityIdentifier("dashboardAssetCounts")

            Text(DashboardCopy.assetsDefinition)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let counts {
                HStack(spacing: 12) {
                    bucket("Missing", counts.missing)
                    bucket("Blocked", counts.blocked)
                    bucket("Stale", counts.stale)
                    bucket("Optional", counts.optional)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("dashboardAssetBuckets")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bucket(_ name: String, _ count: Int) -> some View {
        Text("\(name) \(count)")
            .font(.caption)
            .monospacedDigit()
    }

    // MARK: - Generation Packages (PHASE5_DESIGN §6.1, Plan 020)

    /// The three package counts under the active profile, from the same
    /// `scenePackages()` read the Generation section's list consumes — byte-consistent
    /// figures by construction (§3.3). Clicking a state opens the Generation section.
    @ViewBuilder
    private func generationPackagesPanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generation Packages").font(.headline)

            Text(model.generationCountsLine)
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .accessibilityIdentifier("dashboardGenerationCounts")
                .accessibilityLabel("Generation packages: \(model.generationCountsLine)")

            HStack(spacing: 12) {
                generationStateButton(
                    "Generation Ready", model.generationCounts.ready, .generationReady
                )
                generationStateButton("Stale", model.generationCounts.stale, .stale)
                generationStateButton(
                    "Needs Preparation", model.generationCounts.needsPreparation,
                    .needsPreparation
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dashboardGenerationBuckets")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("generationPackagesPanel")
    }

    private func generationStateButton(_ name: String, _ count: Int, _ state: ScenePackageState)
        -> some View
    {
        Button {
            Task { await model.showGenerationFiltered(by: state) }
        } label: {
            Text("\(name) · \(count)")
        }
        .buttonStyle(.link)
        .accessibilityIdentifier("dashboardGenerationState_\(state.rawValue)")
        .accessibilityLabel("\(count) scenes \(name)")
    }
}
