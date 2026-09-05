import FilmCore
import SwiftUI

/// The **one** shared entity list of §3.11, used by all six entity sections: name, review
/// badge, lock icon, appearance count — plus this plan's review filter, `+`, and the
/// context menu that mirrors the Entity menu.
///
/// Multi-selection offers only the actions valid for the whole selection; the predicates
/// are `EntityCommands.swift`'s, shared with the menu rather than restated here.
struct EntityListView: View {
    @Bindable var model: ProjectWindowModel
    let section: ProjectSection

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if summaries.isEmpty, query.isEmpty {
                    ContentUnavailableView(emptyStateText, systemImage: section.systemImage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
        }
        // Aliases live only on `EntityDetail`, so the index is fetched once, the first
        // time a search actually needs it.
        .task(id: query) {
            guard !query.isEmpty else { return }
            await model.loadAliasIndex()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ReviewFilters(model: model)
            AddMissingEntityButton(model: model)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(.trailing, 8)
                .accessibilityIdentifier("createEntityButton")
                .accessibilityLabel("Add \(singularNoun.lowercased())")
        }
    }

    // MARK: - List

    private var list: some View {
        List(selection: selectionBinding) {
            ForEach(filtered) { summary in
                row(summary)
                    .tag(summary.id)
            }
        }
        // `forSelectionType:` is what makes a right-click on an unselected row select it
        // first, so the menu's items and the Entity menu's agree on what they act on.
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(ids: ids)
        } primaryAction: { ids in
            // Double-click renames, the same action Return performs.
            guard ids.count == 1 else { return }
            model.setSelection(ids, in: section)
            model.beginRename()
        }
        // `.contain` keeps the rows in the accessibility tree: naming the list without it
        // collapses the whole list into one element.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entityList")
        .accessibilityLabel("\(section.title) list")
    }

    @ViewBuilder
    private func row(_ summary: EntitySummary) -> some View {
        HStack(spacing: 8) {
            Text(summary.name)
            if summary.reviewState != .accepted {
                Text(summary.reviewState.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.18), in: Capsule())
                    .accessibilityLabel("Review state: \(summary.reviewState.displayName)")
            }
            if let band = summary.confidence.map(ConfidenceBand.init(confidence:)) {
                Text(band.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Confidence: \(band.rawValue)")
            }
            if summary.hasUnanchoredEvidence {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Unanchored evidence")
            }
            if summary.isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Locked")
            }
            Spacer(minLength: 8)
            Text("\(summary.appearanceCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("\(summary.appearanceCount) appearances")
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The context menu (mirrored by the Entity menu)

    @ViewBuilder
    private func contextMenu(ids: Set<UUID>) -> some View {
        Button("Rename") { act(ids) { model.beginRename() } }
            .disabled(!model.canRename)
        Divider()
        Button("Merge…") { act(ids) { model.presentedSheet = .merge } }
            .disabled(!model.canMergeSelection)
        Button("Split…") { act(ids) { model.presentedSheet = .split } }
            .disabled(!model.canSplitSelection)
        Button("Move into…") { act(ids) { model.presentedSheet = .moveInto } }
            .disabled(!model.canMoveSelectionIntoLocation)
        Divider()
        Button(model.isSelectionWholeLocked ? "Unlock" : "Lock") {
            act(ids) { Task { await model.toggleWholeRecordLock() } }
        }
        .disabled(!model.canToggleWholeRecordLock)
        Button("Mark Irrelevant") {
            act(ids) { Task { await model.setRelevance(ids: model.selectedEntityIDs, isRelevant: false) } }
        }
        .disabled(!model.canMarkSelectionIrrelevant)
        Divider()
        Button("Accept") { act(ids) { Task { await model.acceptSelection() } } }
            .disabled(!model.canAcceptSelection)
        Button("Delete") { act(ids) { model.confirmDeletion(of: model.selectedEntityIDs) } }
            .disabled(!model.canDeleteSelection)
    }

    /// Every context action runs against the rows the menu was raised over.
    private func act(_ ids: Set<UUID>, _ body: () -> Void) {
        model.setSelection(ids, in: section)
        body()
    }

    // MARK: - Creating

    /// The `+` of the empty state. The name is a placeholder the operator renames in
    /// place; it is disambiguated first because `name_normalized` is unique per kind and
    /// a second "New Character" would be refused rather than created.
    private var singularNoun: String { section.entityKind?.displayName ?? "Entity" }

    // MARK: - Data

    private var query: String { model.searchText(in: section) }

    private var summaries: [EntitySummary] {
        guard let kind = section.entityKind else { return [] }
        return model.entitySummaries[kind] ?? []
    }

    /// The empty state is §3.11's for the default list; a filter that hides everything
    /// says so instead, or the operator has no way to tell an empty project from an empty
    /// filter.
    private var emptyStateText: String {
        model.entityReviewFilter == .all
            ? section.emptyStateText
            : "No \(model.entityReviewFilter.title.lowercased()) \(section.title.lowercased())."
    }

    /// Entities match **name + aliases** (§3.11).
    private var filtered: [EntitySummary] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return summaries }
        return summaries.filter { summary in
            if summary.name.localizedCaseInsensitiveContains(query) { return true }
            return (model.aliasIndex[summary.id] ?? [])
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { model.selection(in: section) },
            set: { model.setSelection($0, in: section) }
        )
    }
}
