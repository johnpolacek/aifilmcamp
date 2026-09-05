import FilmCore
import SwiftUI

/// §3.11's Scenes content list: a sortable `Table` of Ordinal, Scene #, Heading, INT/EXT,
/// Location, Time — plus PHASE4_DESIGN §5.2's **Readiness** column.
///
/// Search is scoped to this section and matches **heading + text**; the scene text comes
/// from the model's slices of `Script.sourceText`, so typing costs no query.
struct SceneTableView: View {
    @Bindable var model: ProjectWindowModel

    @State private var sortOrder = [KeyPathComparator(\SceneRow.ordinal)]

    var body: some View {
        if model.scenes.isEmpty {
            // Contract D's third import entry point. It applies the same extension
            // predicate as the open panel's delegate and lands on the same code path.
            ContentUnavailableView(
                ProjectSection.scenes.emptyStateText,
                systemImage: ProjectSection.scenes.systemImage
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: ProjectWindowModel.acceptsDroppedScreenplay) else {
                    return false
                }
                Task { await model.importScreenplay(from: url) }
                return true
            }
            .accessibilityIdentifier("sceneImportDropTarget")
            .accessibilityLabel("Import a screenplay")
        } else {
            VStack(spacing: 0) {
                readinessScopePicker
                Table(rows, selection: selectionBinding, sortOrder: $sortOrder) {
                    TableColumn("Ordinal", value: \.ordinal) { row in
                        Text("\(row.ordinal)").monospacedDigit()
                    }
                    .width(min: 60, ideal: 70)
                    TableColumn("Scene #", value: \.sceneNumber)
                        .width(min: 60, ideal: 80)
                    TableColumn("Heading", value: \.heading)
                    TableColumn("Readiness", value: \.readinessSortKey) { row in
                        Text(row.readinessText)
                            .monospacedDigit()
                        .foregroundStyle(readinessColor(row))
                        .help(row.readinessHelp)
                        .accessibilityIdentifier("sceneReadinessCell_\(row.ordinal)")
                        .accessibilityLabel("Readiness: \(row.readinessHelp)")
                    }
                    .width(min: 140, ideal: 180)
                    TableColumn("INT/EXT", value: \.intExt)
                        .width(min: 70, ideal: 90)
                    TableColumn("Location", value: \.location)
                    TableColumn("Time", value: \.time)
                        .width(min: 70, ideal: 100)
                }
                .accessibilityIdentifier("sceneTable")
                .accessibilityLabel("Scenes")
            }
        }
    }

    /// §5.3's drill-down target: the preset filter, clearable here. Like the Manifest
    /// list's scope control it narrows what the list shows.
    private var readinessScopePicker: some View {
        HStack(spacing: 6) {
            ForEach(SceneReadinessFilter.allCases) { filter in
                Button(filter.title) {
                    model.setSceneReadinessFilter(filter)
                }
                .buttonStyle(.link)
                .opacity(model.sceneReadinessFilter == filter ? 1 : 0.5)
                .accessibilityIdentifier("sceneReadinessScope_\(filter.rawValue)")
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sceneReadinessScopes")
    }

    private var rows: [SceneRow] {
        let query = model.searchText(in: .scenes).trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = model.sceneReadinessFilter
        let scenes = model.scenes.filter { scene in
            guard !query.isEmpty else { return true }
            if scene.heading.localizedCaseInsensitiveContains(query) { return true }
            return model.sceneTexts[scene.id]?.localizedCaseInsensitiveContains(query) ?? false
        }
        let filtered = scenes.filter { scene in
            guard filter != .all else { return true }
            guard let row = model.readinessRow(forSceneID: scene.id) else { return false }
            return filter.admits(row)
        }
        return filtered.map { SceneRow(scene: $0, readiness: model.readinessRow(forSceneID: $0.id)) }
            .sorted(using: sortOrder)
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { model.selection(in: .scenes) },
            set: { model.setSelection($0, in: .scenes) }
        )
    }

    private func readinessColor(_ row: SceneRow) -> Color {
        switch row.state {
        case .assetReady: .green
        case .blocked: .orange
        case .partial, nil: .primary
        }
    }
}

/// The table's row shape: every column is a non-optional `Comparable` so `KeyPathComparator`
/// can sort it.
struct SceneRow: Identifiable, Equatable {
    let id: UUID
    let ordinal: Int
    let sceneNumber: String
    let heading: String
    let intExt: String
    let location: String
    let time: String
    /// §5.2's readiness column: the state name with the `readyCount / requiredCount`
    /// figure ("Asset Ready · 7 / 7"), or the existing Omitted/Preamble label in place of
    /// a state on excluded rows (§3.4).
    let readinessText: String
    /// Blocked first — actionable work sorts to the top when the operator clicks it.
    let readinessSortKey: Int
    let state: SceneReadinessState?
    let isExcluded: Bool

    init(scene: FilmCore.Scene, readiness: SceneReadiness?) {
        id = scene.id
        ordinal = scene.ordinal
        sceneNumber = scene.sceneNumber ?? ""
        heading = scene.heading
        intExt = scene.intExt.displayName
        location = scene.locationText
        time = scene.timeOfDay

        if scene.isOmitted || scene.ordinal == 0 {
            readinessText = scene.isOmitted ? "Omitted" : "Preamble"
            readinessSortKey = -2
            state = nil
            isExcluded = true
            return
        }
        guard let readiness else {
            readinessText = ""
            readinessSortKey = -1
            state = nil
            isExcluded = false
            return
        }
        readinessText =
            "\(readiness.state.displayName) · \(readiness.readyCount) / \(readiness.requiredCount)"
        readinessSortKey = switch readiness.state {
        case .blocked: 0
        case .partial: 1
        case .assetReady: 2
        }
        state = readiness.state
        isExcluded = false
    }

    var readinessHelp: String {
        guard let state else {
            return isExcluded
                ? "This scene is not a generation target, so it holds no readiness state."
                : ""
        }
        let base = "\(state.displayName) · \(readinessText.components(separatedBy: "· ")[1])"
        return base
    }
}

extension SceneReadinessState {
    var displayName: String {
        switch self {
        case .assetReady: "Asset Ready"
        case .partial: "Partial"
        case .blocked: "Blocked"
        }
    }
}
