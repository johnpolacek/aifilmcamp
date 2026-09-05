import FilmCore
import SwiftUI

/// The state editor of §4.3 and §6: a category, a description, and the scene span the
/// state holds over.
///
/// `start_scene_id` is required and `end_scene_id` is optional — a `nil` end means the
/// state is still active at the end of the script. Both scenes must belong to the current
/// script and start must not come after end; those are FilmCore's checks and its refusals
/// are surfaced verbatim.
struct StateEditorSheet: View {
    @Bindable var model: ProjectWindowModel
    /// The entity the state belongs to. A state cannot exist without one, which is why
    /// this sheet is raised from an entity rather than from the Continuity list.
    let entityID: UUID
    /// `nil` adds; otherwise the row being edited in place.
    let existing: EntityState?

    @State private var category: StateCategory = .wardrobe
    @State private var description = ""
    @State private var startSceneID: UUID?
    @State private var endSceneID: UUID?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "Add State" : "Edit State")
                .font(.headline)
                .accessibilityIdentifier("stateEditorTitle")

            Text(model.entityNames[entityID] ?? "Entity")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Category", selection: $category) {
                ForEach(StateCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .accessibilityIdentifier("stateCategoryPicker")
            .accessibilityLabel("State category")

            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(2 ... 5)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("stateDescriptionField")
                .accessibilityLabel("State description")

            Picker("From scene", selection: $startSceneID) {
                ForEach(model.scenes) { scene in
                    Text(sceneTitle(scene)).tag(UUID?.some(scene.id))
                }
            }
            .accessibilityIdentifier("stateStartScenePicker")
            .accessibilityLabel("First scene")

            Picker("Until scene", selection: $endSceneID) {
                Text("End of script").tag(UUID?.none)
                ForEach(model.scenes) { scene in
                    Text(sceneTitle(scene)).tag(UUID?.some(scene.id))
                }
            }
            .accessibilityIdentifier("stateEndScenePicker")
            .accessibilityLabel("Last scene")

            HStack {
                Spacer()
                Button("Cancel") { model.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelStateButton")
                    .accessibilityLabel("Cancel state")
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveStateButton")
                    .accessibilityLabel("Save state")
            }
        }
        .padding(16)
        .frame(minWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stateEditorSheet")
        .accessibilityLabel(existing == nil ? "Add state" : "Edit state")
        .onAppear {
            if let existing {
                category = existing.category
                description = existing.description
                startSceneID = existing.startSceneID
                endSceneID = existing.endSceneID
            } else {
                startSceneID = startSceneID ?? model.scenes.first?.id
            }
        }
    }

    private var canSave: Bool {
        !isSaving
            && startSceneID != nil
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sceneTitle(_ scene: FilmCore.Scene) -> String {
        "\(scene.ordinal). \(scene.heading)"
    }

    private func save() {
        guard let startSceneID, canSave else { return }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        Task {
            if let existing {
                await model.editState(
                    id: existing.id,
                    category: category,
                    description: text,
                    startSceneID: startSceneID,
                    endSceneID: endSceneID
                )
            } else {
                await model.addState(
                    entityID: entityID,
                    category: category,
                    description: text,
                    startSceneID: startSceneID,
                    endSceneID: endSceneID
                )
            }
            isSaving = false
            guard model.error == nil else { return }
            model.presentedSheet = nil
        }
    }
}
