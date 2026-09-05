import FilmCore
import SwiftUI

/// The relationship editor of §4.3: a directed edge from this entity to another, with a
/// kind and a description.
///
/// `entity_relationships` is unique per `(from, to, kind)`, and a self-relationship is not
/// a relationship — both are FilmCore's to refuse, and its wording is what the operator
/// reads.
struct RelationshipEditorSheet: View {
    @Bindable var model: ProjectWindowModel
    let fromEntityID: UUID

    @State private var toEntityID: UUID?
    @State private var kind: RelationshipKind = .family
    @State private var description = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Relationship")
                .font(.headline)
                .accessibilityIdentifier("relationshipEditorTitle")

            Text(model.entityNames[fromEntityID] ?? "Entity")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Related to", selection: $toEntityID) {
                Text("Choose an entity").tag(UUID?.none)
                ForEach(candidates, id: \.id) { candidate in
                    Text(candidate.name).tag(UUID?.some(candidate.id))
                }
            }
            .accessibilityIdentifier("relationshipTargetPicker")
            .accessibilityLabel("Related entity")

            Picker("Kind", selection: $kind) {
                ForEach(RelationshipKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .accessibilityIdentifier("relationshipKindPicker")
            .accessibilityLabel("Relationship kind")

            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(2 ... 5)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("relationshipDescriptionField")
                .accessibilityLabel("Relationship description")

            HStack {
                Spacer()
                Button("Cancel") { model.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelRelationshipButton")
                    .accessibilityLabel("Cancel relationship")
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(toEntityID == nil || isSaving)
                    .accessibilityIdentifier("saveRelationshipButton")
                    .accessibilityLabel("Save relationship")
            }
        }
        .padding(16)
        .frame(minWidth: 460)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("relationshipEditorSheet")
        .accessibilityLabel("Add relationship")
    }

    private var candidates: [EntitySummary] {
        EntityKind.allCases
            .flatMap { model.entitySummaries[$0] ?? [] }
            .filter { $0.id != fromEntityID }
    }

    private func save() {
        guard let toEntityID else { return }
        isSaving = true
        Task {
            await model.addRelationship(
                fromEntityID: fromEntityID,
                toEntityID: toEntityID,
                kind: kind,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            isSaving = false
            guard model.error == nil else { return }
            model.presentedSheet = nil
        }
    }
}
