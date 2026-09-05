import FilmCore
import SwiftUI

/// §6's `setSceneEntity` / `removeSceneEntity` as a sheet: which entities appear in this
/// scene, and in which role.
///
/// Appearances upsert on `(scene_id, entity_id, role)`, so adding one that already exists
/// is not an error and not a duplicate — the same entity may legitimately hold two roles
/// in one scene, which is why the role travels with every row rather than being a property
/// of the pair.
struct SceneEntitiesEditor: View {
    @Bindable var model: ProjectWindowModel
    let detail: SceneDetail

    @State private var entityID: UUID?
    @State private var role: SceneEntityRole = .present

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entities in \(detail.scene.ordinal). \(detail.scene.heading)")
                .font(.headline)
                .accessibilityIdentifier("sceneEntitiesTitle")

            List {
                ForEach(detail.appearances) { appearance in
                    HStack(spacing: 6) {
                        Text(model.entityNames[appearance.entityID] ?? "Unknown")
                        Text(appearance.role.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button {
                            Task { await model.removeSceneEntity(id: appearance.id) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("removeSceneEntityButton")
                        .accessibilityLabel(
                            "Remove \(model.entityNames[appearance.entityID] ?? "entity") from this scene"
                        )
                    }
                }
            }
            .frame(minHeight: 160)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sceneEntitiesList")
            .accessibilityLabel("Entities in this scene")

            HStack(spacing: 6) {
                Picker("Entity", selection: $entityID) {
                    Text("Choose an entity").tag(UUID?.none)
                    ForEach(candidates, id: \.id) { candidate in
                        Text(candidate.name).tag(UUID?.some(candidate.id))
                    }
                }
                .accessibilityIdentifier("sceneEntityPicker")
                .accessibilityLabel("Entity to add")

                Picker("Role", selection: $role) {
                    ForEach(SceneEntityRole.allCases, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .accessibilityIdentifier("sceneEntityRolePicker")
                .accessibilityLabel("Role")

                Button("Add") { add() }
                    .disabled(entityID == nil)
                    .accessibilityIdentifier("addSceneEntityButton")
                    .accessibilityLabel("Add entity to scene")
            }

            HStack {
                Spacer()
                Button("Done") { model.presentedSheet = nil }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("sceneEntitiesDoneButton")
                    .accessibilityLabel("Done")
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 360)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sceneEntitiesSheet")
        .accessibilityLabel("Scene entities")
    }

    private var candidates: [EntitySummary] {
        EntityKind.allCases.flatMap { model.entitySummaries[$0] ?? [] }
    }

    private func add() {
        guard let entityID else { return }
        let role = role
        Task { await model.setSceneEntity(sceneID: detail.scene.id, entityID: entityID, role: role) }
    }
}
