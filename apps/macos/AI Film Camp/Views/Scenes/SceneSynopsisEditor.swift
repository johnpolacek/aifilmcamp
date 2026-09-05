import FilmCore
import SwiftUI

/// The scene synopsis, editable (§3.11 as revised) through `setSynopsis` — the one write
/// that touches a scene's synopsis PROV columns and nothing else in the row.
///
/// The synopsis is a lockable field in its own right (`scene` / `synopsis`, §3.7), so it
/// renders read-only with an Unlock control once pinned.
struct SceneSynopsisEditor: View {
    @Bindable var model: ProjectWindowModel
    let scene: FilmCore.Scene

    @State private var draft = ""
    @State private var editedSceneID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Synopsis").font(.headline)
                Spacer(minLength: 8)
                LockButton(model: model, subject: subject, field: .synopsis, name: "Synopsis")
            }

            if isLocked {
                Text(scene.synopsis.isEmpty ? "No synopsis yet." : scene.synopsis)
                    .foregroundStyle(scene.synopsis.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sceneSynopsisText")
                    .accessibilityLabel("Synopsis, locked: \(scene.synopsis.isEmpty ? "none" : scene.synopsis)")
            } else {
                TextField("No synopsis yet.", text: $draft, axis: .vertical)
                    .lineLimit(2 ... 8)
                    .textFieldStyle(.roundedBorder)
                    .tracksTextEditing(model)
                    .accessibilityIdentifier("sceneSynopsisField")
                    .accessibilityLabel("Synopsis")
                HStack {
                    Spacer()
                    Button("Save Synopsis") { save() }
                        .disabled(draft == scene.synopsis)
                        .accessibilityIdentifier("saveSynopsisButton")
                        .accessibilityLabel("Save synopsis")
                }
            }
        }
        // Adopting on the scene id rather than on every change is what lets the operator
        // keep typing while `changes()` refreshes the model underneath them.
        .task(id: scene.id) {
            if editedSceneID != scene.id {
                editedSceneID = scene.id
                draft = scene.synopsis
            }
        }
        // The store is the document (§3.11): a synopsis that changed there — this
        // editor's own save, an undo, another window — is what the field shows next.
        .onChange(of: scene.synopsis) { _, stored in draft = stored }
    }

    private var subject: SubjectRef { SubjectRef(kind: .scene, id: scene.id) }

    private var isLocked: Bool { model.isLocked(subject, field: .synopsis) }

    private func save() {
        let text = draft
        Task { await model.setSynopsis(sceneID: scene.id, text: text) }
    }
}
