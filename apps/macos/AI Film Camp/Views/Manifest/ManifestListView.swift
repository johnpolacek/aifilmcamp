import FilmCore
import SwiftUI

/// The **Manifest** section (PHASE2_DESIGN §5.1–§5.3, §6.1, §6.4, §8.6): every requirement
/// row grouped by entity, the §6.4 counts, the review filters, and the **Build Asset
/// Manifest** action.
///
/// Presentation only. Every action routes through `ProjectWindowModel+Manifest.swift`,
/// which is where the filters, the predicates, and §7.2's operations live — no view here
/// decides what a selection admits.
struct ManifestListView: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if model.requirementGroups.isEmpty, model.entitiesMissingCanonicalSet.isEmpty,
                   model.manifestInclusionSuggestions.isEmpty
                {
                    ContentUnavailableView(
                        emptyStateText,
                        systemImage: ProjectSection.manifest.systemImage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
        }
    }

    // MARK: - Header: §6.4's counts, §8.6's filters, §5.2's Build, §5.3's badges

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RequirementReviewFilters(model: model)
                ManifestScopeFilters(model: model)
                Button("Build Asset Manifest") {
                    Task { await model.buildAssetManifest() }
                }
                .disabled(!model.canBuildAssetManifest)
                .accessibilityIdentifier("buildManifestButton")
                .accessibilityLabel("Build Asset Manifest")
                // §8's one-time inference pass, beside the deterministic Build it
                // complements. Both stay: Build is idempotent and repeatable, inference
                // runs once (§3.6).
                Button(model.inferManifestButtonTitle) {
                    Task { await model.prepareManifestRun() }
                }
                .disabled(!model.canInferManifest)
                .accessibilityIdentifier("inferManifestButton")
                .accessibilityLabel(model.inferManifestButtonTitle)
                .padding(.trailing, 8)
            }

            // The run's own line while it runs, and §3.6's refusal copy when the action is
            // unavailable — verbatim from the FilmCore error the store would throw.
            if let progress = model.manifestProgress, model.activeManifestRun != nil {
                Text(progress.message)
                    .font(.caption)
                    .accessibilityIdentifier("manifestRunProgressText")
                    .accessibilityLabel(progress.message)
                    .padding(.horizontal, 8)
            } else if let refusal = model.manifestRunRefusalMessage {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manifestRunRefusalText")
                    .accessibilityLabel(refusal)
                    .padding(.horizontal, 8)
            }

            Text(model.manifestCountsLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("manifestSummaryText")
                .accessibilityLabel("Manifest counts: \(model.manifestCountsLine)")
                .padding(.horizontal, 8)

            if let message = model.lastBuildMessage {
                Text(message)
                    .font(.caption)
                    .accessibilityIdentifier("manifestBuildResultText")
                    .accessibilityLabel(message)
                    .padding(.horizontal, 8)
            }

            // §5.3: a canonical slot Build could not create because of a §5.2 name
            // collision is badged, naming both rows, and the remedy is rename **or
            // delete** — a rejected row keeps its normalized name.
            ForEach(Array(model.buildCollisionBadges.enumerated()), id: \.offset) { _, badge in
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manifestCollisionBadge")
                    .accessibilityLabel(badge)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manifestHeader")
        .accessibilityLabel("Manifest summary")
    }

    private var emptyStateText: String {
        // §6.4's Missing is a question with a good answer when it is empty, so it gets its
        // own sentence rather than "No all requirements."
        if model.manifestScope == .missing {
            return "Nothing is missing: every required slot has an approved reference image."
        }
        return model.requirementReviewFilter == .all
            ? ProjectSection.manifest.emptyStateText
            : "No \(model.requirementReviewFilter.title.lowercased()) requirements."
    }

    // MARK: - List

    private var list: some View {
        List(selection: selectionBinding) {
            // §3.4/§8.5's inclusion suggestions: **advisory**, never auto-applied. They live
            // in the run's persisted report, so they survive reopen, and one click performs
            // the human override through §7.2's operation.
            if !model.manifestInclusionSuggestions.isEmpty {
                Section("Suggested manifest inclusion") {
                    ForEach(model.manifestInclusionSuggestions) { suggestion in
                        suggestionRow(suggestion)
                    }
                }
            }
            // §5.3's "qualifies but has no canonical set — Build to add". These entities
            // have no requirement row to hang a badge on, so they lead the list.
            if !model.entitiesMissingCanonicalSet.isEmpty {
                Section("Qualifies — Build to add") {
                    ForEach(model.entitiesMissingCanonicalSet) { entity in
                        qualifyingRow(entity)
                    }
                }
            }
            ForEach(model.requirementGroups) { group in
                Section("\(group.entityName) · \(group.entityKind.displayName)") {
                    ForEach(group.requirements) { summary in
                        row(summary).tag(summary.id)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(ids: ids)
        }
        // `.contain` keeps the rows in the accessibility tree, as the entity list's does.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("requirementList")
        .accessibilityLabel("Manifest list")
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: ManifestSuggestionRow) -> some View {
        HStack(spacing: 8) {
            Text(suggestion.line)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manifestSuggestionText")
                .accessibilityLabel(suggestion.line)
            ManifestBadge(
                text: "advisory",
                label: "Advisory suggestion — nothing was changed",
                identifier: "manifestSuggestionBadge"
            )
            Spacer(minLength: 8)
            Button(suggestion.actionTitle) {
                Task { await model.applyManifestSuggestion(suggestion) }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("applyManifestSuggestionButton")
            .accessibilityLabel("\(suggestion.actionTitle) \(suggestion.entityName)")
        }
    }

    @ViewBuilder
    private func qualifyingRow(_ entity: QualifyingEntity) -> some View {
        HStack(spacing: 8) {
            Text(entity.name)
            ManifestBadge(
                text: "qualifies but has no canonical set — Build to add",
                label: "\(entity.name) qualifies but has no canonical set — Build to add",
                tint: .orange,
                identifier: "manifestQualifyingBadge"
            )
            Spacer(minLength: 8)
        }
    }

    /// One requirement row: tier, necessity, review state, lock, and the **asset display
    /// state** — Needed for a slot with no asset row (§6.1). The two axes are deliberately
    /// distinct: the review badge is the requirement's own lifecycle, the status badge is
    /// its media's.
    @ViewBuilder
    private func row(_ summary: RequirementSummary) -> some View {
        HStack(spacing: 8) {
            Text(summary.name)
            ManifestBadge(
                text: summary.tier.displayName,
                label: "Tier: \(summary.tier.displayName)"
            )
            Text(summary.necessity.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Necessity: \(summary.necessity.displayName)")
            if summary.reviewState != .accepted {
                ManifestBadge(
                    text: summary.reviewState.displayName,
                    label: "Review state: \(summary.reviewState.displayName)"
                )
            }
            ManifestBadge(
                text: summary.displayStatus.displayName,
                label: "Asset: \(summary.displayStatus.displayName)",
                tint: summary.displayStatus == .approved ? .green : .secondary
            )
            if summary.isStale {
                ManifestBadge(text: "Stale", label: "Stale", tint: .orange)
            }
            // §6.4: Blocked is a subset of Missing — a missing row whose dependency is
            // unsatisfied. The Missing scope is where it matters most, so the badge rides
            // on the row rather than on the scope control.
            if summary.isBlocked {
                ManifestBadge(
                    text: "Blocked",
                    label: "Blocked by an unsatisfied dependency",
                    tint: .orange,
                    identifier: "requirementBlockedRowBadge"
                )
            }
            ForEach(summary.drift.badges(sceneCount: summary.requiredBySceneCount), id: \.self) { badge in
                ManifestBadge(text: badge, label: badge, tint: .orange)
            }
            if summary.isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Locked")
            }
            Spacer(minLength: 8)
            Text("\(summary.requiredBySceneCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("Required by \(summary.requiredBySceneCount) scenes")
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The context menu (mirrored by the Entity menu)

    @ViewBuilder
    private func contextMenu(ids: Set<UUID>) -> some View {
        Button("Rename") { act(ids) { model.beginRequirementRename() } }
            .disabled(!model.canRenameRequirement)
        Divider()
        Button("Mark Required") {
            act(ids) { Task { await model.setSelectedRequirementNecessity(.required) } }
        }
        .disabled(!model.canSetRequirementNecessity)
        Button("Mark Optional") {
            act(ids) { Task { await model.setSelectedRequirementNecessity(.optional) } }
        }
        .disabled(!model.canSetRequirementNecessity)
        Button("Mark Not Needed") {
            act(ids) { Task { await model.setSelectedRequirementNecessity(.notNeeded) } }
        }
        .disabled(!model.canSetRequirementNecessity)
        Divider()
        Button("Combine…") { act(ids) { model.presentedSheet = .combineRequirements } }
            .disabled(!model.canCombineRequirementSelection)
        Button(model.isSelectedRequirementWholeLocked ? "Unlock" : "Lock") {
            act(ids) { Task { await model.toggleSelectedRequirementLock() } }
        }
        .disabled(!model.canToggleRequirementLock)
        Divider()
        Button("Accept") { act(ids) { Task { await model.acceptRequirementSelection() } } }
            .disabled(!model.canAcceptRequirementSelection)
        Button("Reject") {
            act(ids) {
                guard let id = model.selectedRequirementSummary?.id else { return }
                Task { await model.rejectRequirement(id: id) }
            }
        }
        .disabled(model.selectedRequirementSummary?.reviewState == .rejected
            || !model.canRejectRequirementSelection)
        Button("Delete") {
            act(ids) {
                guard let id = model.selectedRequirementSummary?.id else { return }
                Task { await model.deleteRequirement(id: id) }
            }
        }
        .disabled(model.selectedRequirementSummary == nil)
    }

    private func act(_ ids: Set<UUID>, _ body: () -> Void) {
        model.setSelection(ids, in: .manifest)
        body()
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            // The inspector's `.task(id:)` loads the detail for whatever this selects, the
            // same way the entity inspector does.
            get: { model.selection(in: .manifest) },
            set: { model.setSelection($0, in: .manifest) }
        )
    }
}

/// §6.4's Missing scope, beside the review filters and in the same grammar (Plan 011
/// contract C).
///
/// It is backed by `missingAssets()` — the read, not a predicate restated here — so the
/// rows this shows and the "N missing" in the counts line can never disagree.
struct ManifestScopeFilters: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ManifestScopeFilter.allCases) { scope in
                button(scope)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manifestScopeFilters")
        .accessibilityLabel("Manifest scope")
    }

    private func button(_ scope: ManifestScopeFilter) -> some View {
        let isActive = model.manifestScope == scope
        return Button {
            model.setManifestScope(scope)
        } label: {
            Text(scope.title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.25) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("manifestScope_\(scope.rawValue)")
        .accessibilityLabel("Show \(scope.title.lowercased())")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

/// Rejected requirements remain reachable for correction or restoration. Validated output
/// needs no Proposed / Accepted triage.
struct RequirementReviewFilters: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach([RequirementReviewFilter.all, .rejected]) { filter in
                button(filter)
            }
            Spacer(minLength: 0)
        }
        // The header row is shared with Build/Infer and can be squeezed into a narrow
        // list column; without this the capsules compress to slivers whose frames no
        // longer match their labels, and clicks on them land nowhere.
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("requirementReviewFilters")
        .accessibilityLabel("Requirement review filter")
    }

    private func button(_ filter: RequirementReviewFilter) -> some View {
        let isActive = model.requirementReviewFilter == filter
        return Button {
            Task { await model.setRequirementReviewFilter(filter) }
        } label: {
            Text(filter.title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.25) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("requirementFilter_\(filter.rawValue)")
        .accessibilityLabel("Show \(filter.title.lowercased()) requirements")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
