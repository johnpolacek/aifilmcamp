import FilmCore
import SwiftUI

/// Plan 023's only primary navigation surface.
struct SceneWorkspaceRail: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        Group {
            if model.scenes.isEmpty {
                ContentUnavailableView(
                    "Import a screenplay to see its scenes.",
                    systemImage: "film"
                )
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first(where: ProjectWindowModel.acceptsDroppedScreenplay)
                    else { return false }
                    Task { await model.importScreenplay(from: url) }
                    return true
                }
                .accessibilityIdentifier("sceneImportDropTarget")
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(model.workspaceRows) { row in
                            Button {
                                Task { await model.selectWorkspaceScene(row.id) }
                            } label: {
                                SceneWorkspaceRailRow(
                                    ordinal: row.scene.ordinal,
                                    heading: row.scene.heading,
                                    status: row.status,
                                    isSelected: model.selectedWorkspaceSceneID == row.id
                                )
                            }
                            .id(row.id)
                            .buttonStyle(.plain)
                            .listRowBackground(
                                model.selectedWorkspaceSceneID == row.id
                                    ? CampAppearance.inset
                                    : Color.clear
                            )
                            .accessibilityIdentifier("sceneRail.scene.\(row.scene.ordinal)")
                            .accessibilityLabel(
                                "Scene \(row.scene.ordinal), \(row.scene.heading), \(row.status.rawValue)"
                            )
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(CampAppearance.surface)
                    .accessibilityIdentifier("sceneRail")
                    .accessibilityLabel("Scenes")
                    .onChange(of: model.selectedWorkspaceSceneID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                CampLogo()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text("AI FILM CAMP")
                    .font(CampAppearance.label())
                    .tracking(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(CampAppearance.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(CampAppearance.rule).frame(height: 1)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.script != nil {
                Button {
                    model.presentedSheet = .addScenes
                } label: {
                    Label("Add Scenes…", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .disabled(!model.canAddScenes)
                .padding(12)
                .background(CampAppearance.surface)
                .accessibilityIdentifier("addScenesButton")
                .accessibilityLabel("Add scenes at the end")
            }
        }
        .navigationTitle("Scenes")
        .searchable(text: $model.workspaceSearchText, prompt: "Search scenes")
    }
}
private struct SceneWorkspaceRailRow: View {
    let ordinal: Int
    let heading: String
    let status: SceneWorkspaceStatus
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(ordinal)")
                    .font(CampAppearance.label(12))
                    .foregroundStyle(isSelected ? CampAppearance.accent : Color.secondary)
                    .frame(minWidth: 22, alignment: .leading)
                Text(heading)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .lineLimit(2)
            }
            Label(status.rawValue, systemImage: status.systemImage)
                .font(.caption)
                .foregroundStyle(status == .ready ? .green : .secondary)
                .accessibilityIdentifier("sceneWorkflowStatus")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 7)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(CampAppearance.accent)
                    .frame(width: 2)
                    .offset(x: -8)
                    .accessibilityHidden(true)
            }
        }
    }
}
