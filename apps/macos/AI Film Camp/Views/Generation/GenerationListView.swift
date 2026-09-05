import FilmCore
import SwiftUI

/// PHASE5_DESIGN §5.3/§5.1's Generation section (Plan 020 contract A): scenes in ordinal
/// order with §3.3's package-state badges, the state filter, the counts line naming the
/// active profile, and the excluded scenes under their existing labels with no package
/// state. Presentation only — every figure is `model.scenePackages`, never re-derived.
struct GenerationListView: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if model.scenePackages.isEmpty && excludedScenes.isEmpty {
                    ContentUnavailableView(
                        ProjectSection.generation.emptyStateText,
                        systemImage: ProjectSection.generation.systemImage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
        }
    }

    private var excludedScenes: [SceneReadiness] {
        guard let snapshot = model.readinessSnapshot else { return [] }
        return snapshot.scenes.filter(\.isExcluded)
    }

    // MARK: - Header: the counts line naming P, and the filter

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(GenerationPackageFilter.allCases) { filter in
                    filterButton(filter)
                }
                Spacer(minLength: 0)
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Text(model.generationCountsLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("generationSummaryText")
                .accessibilityLabel("Generation counts: \(model.generationCountsLine)")
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("generationHeader")
        .accessibilityLabel("Generation summary")
    }

    private func filterButton(_ filter: GenerationPackageFilter) -> some View {
        let isActive = model.generationFilter == filter
        return Button {
            model.setGenerationFilter(filter)
        } label: {
            Text(filter.title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.25) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("generationFilter_\(filter.rawValue)")
        .accessibilityLabel("Show \(filter.title.lowercased()) scenes")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - List

    private var list: some View {
        List(selection: selectionBinding) {
            ForEach(model.filteredScenePackages) { summary in
                row(summary).tag(summary.sceneID)
            }
            // Excluded scenes render under their existing labels with no package state
            // (§3.3) — listed, never counted.
            if !excludedScenes.isEmpty {
                Section("Excluded") {
                    ForEach(excludedScenes) { scene in
                        HStack(spacing: 8) {
                            Text("\(scene.ordinal). \(scene.heading)")
                                .foregroundStyle(.secondary)
                            Text(scene.isOmitted ? "Omitted" : "Before first scene")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("generation.scene.excluded.\(scene.ordinal)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("generation.sceneList")
        .accessibilityLabel("Generation scene list")
    }

    /// One package row: ordinal + heading, the package-state badge, and the scene's
    /// Asset Ready state beside it — **two visibly distinct labels** everywhere both
    /// appear (§3.3; no collapsed badge).
    private func row(_ summary: ScenePackageSummary) -> some View {
        HStack(spacing: 8) {
            Text("\(summary.ordinal). \(summary.heading)")
            Spacer(minLength: 8)
            // The Asset Ready axis — Plan 017's derived state, its own label.
            Text(assetReadyLabel(summary.assetReadyState))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("generation.assetReadyBadge.\(summary.ordinal)")
                .accessibilityLabel("Asset Ready state: \(assetReadyLabel(summary.assetReadyState))")
            // The package axis — this phase's derived state, its own badge.
            Text(packageStateLabel(summary.packageState))
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .accessibilityIdentifier("generation.packageStateBadge.\(summary.ordinal)")
                .accessibilityLabel("Package state: \(packageStateLabel(summary.packageState))")
            Text("\(summary.satisfiedCount)/\(summary.plannedCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel(
                    "\(summary.satisfiedCount) of \(summary.plannedCount) references approved"
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("generation.scene.\(summary.ordinal)")
    }

    private func assetReadyLabel(_ state: SceneReadinessState) -> String {
        switch state {
        case .assetReady: "Asset Ready"
        case .partial: "Partial"
        case .blocked: "Blocked"
        }
    }

    private func packageStateLabel(_ state: ScenePackageState) -> String {
        switch state {
        case .needsPreparation: "Needs Preparation"
        case .generationReady: "Generation Ready"
        case .stale: "Stale"
        }
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { model.selection(in: .generation) },
            set: { model.setSelection($0, in: .generation) }
        )
    }
}
