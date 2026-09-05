import FilmCore
import SwiftUI

/// The continuity event editor of §3.11 and §4.3: what happens, in which scene, to which
/// entity — and the state it results in.
///
/// The entity is nullable on purpose: a scene-wide event belongs to no single entity
/// (§4.3). `resulting_state_id` must belong to the same entity, so the picker offers only
/// that entity's states and clears itself when the entity changes.
struct EventEditorSheet: View {
    @Bindable var model: ProjectWindowModel
    /// `nil` adds; otherwise the row being edited in place.
    let existing: ContinuityEvent?

    @State private var sceneID: UUID?
    @State private var entityID: UUID?
    @State private var description = ""
    @State private var resultingStateID: UUID?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "Add Continuity Event" : "Edit Continuity Event")
                .font(.headline)
                .accessibilityIdentifier("eventEditorTitle")

            Picker("Scene", selection: $sceneID) {
                ForEach(model.scenes) { scene in
                    Text("\(scene.ordinal). \(scene.heading)").tag(UUID?.some(scene.id))
                }
            }
            .accessibilityIdentifier("eventScenePicker")
            .accessibilityLabel("Scene")

            Picker("Entity", selection: $entityID) {
                Text("No entity").tag(UUID?.none)
                ForEach(entityChoices, id: \.id) { choice in
                    Text(choice.name).tag(UUID?.some(choice.id))
                }
            }
            .accessibilityIdentifier("eventEntityPicker")
            .accessibilityLabel("Entity")

            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(2 ... 5)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("eventDescriptionField")
                .accessibilityLabel("Event description")

            Picker("Resulting state", selection: $resultingStateID) {
                Text("No resulting state").tag(UUID?.none)
                ForEach(stateChoices) { state in
                    Text("\(state.category.displayName): \(state.description)")
                        .tag(UUID?.some(state.id))
                }
            }
            .disabled(entityID == nil)
            .accessibilityIdentifier("eventResultingStatePicker")
            .accessibilityLabel("Resulting state")

            HStack {
                Spacer()
                Button("Cancel") { model.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelEventButton")
                    .accessibilityLabel("Cancel event")
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveEventButton")
                    .accessibilityLabel("Save event")
            }
        }
        .padding(16)
        .frame(minWidth: 460)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("eventEditorSheet")
        .accessibilityLabel(existing == nil ? "Add continuity event" : "Edit continuity event")
        .onAppear {
            if let existing {
                sceneID = existing.sceneID
                entityID = existing.entityID
                description = existing.description
                resultingStateID = existing.resultingStateID
            } else {
                sceneID = sceneID ?? model.scenes.first?.id
            }
        }
        // §4.3: the resulting state must belong to the event's entity, so a change of
        // entity drops a selection that would no longer be valid.
        .onChange(of: entityID) { _, _ in
            if !stateChoices.contains(where: { $0.id == resultingStateID }) { resultingStateID = nil }
        }
        .task(id: model.refreshToken) { await model.loadContinuityStates() }
    }

    private var canSave: Bool {
        !isSaving
            && sceneID != nil
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Every entity the project holds, by kind then name — the same order the sidebar's
    /// sections walk.
    private var entityChoices: [EntitySummary] {
        EntityKind.allCases.flatMap { model.entitySummaries[$0] ?? [] }
    }

    private var stateChoices: [EntityState] {
        guard let entityID else { return [] }
        return model.continuityStates.filter { $0.entityID == entityID }
    }

    private func save() {
        guard let sceneID, canSave else { return }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        Task {
            if let existing {
                await model.editEvent(
                    id: existing.id,
                    sceneID: sceneID,
                    entityID: entityID,
                    description: text,
                    resultingStateID: resultingStateID
                )
            } else {
                await model.addEvent(
                    sceneID: sceneID,
                    entityID: entityID,
                    description: text,
                    resultingStateID: resultingStateID
                )
            }
            isSaving = false
            guard model.error == nil else { return }
            model.presentedSheet = nil
        }
    }
}
