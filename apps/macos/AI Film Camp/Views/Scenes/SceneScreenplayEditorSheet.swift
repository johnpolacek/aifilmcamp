import SwiftUI

/// Edits the scene-local screenplay override used by search and prompt generation. The
/// imported screenplay itself remains untouched.
struct SceneScreenplayEditorSheet: View {
    @Bindable var model: ProjectWindowModel
    let sceneID: UUID
    let initialText: String

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(model: ProjectWindowModel, sceneID: UUID, initialText: String) {
        self.model = model
        self.sceneID = sceneID
        self.initialText = initialText
        _text = State(initialValue: initialText)
    }

    private var canSave: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && text != initialText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Screenplay")
                .font(.title3.weight(.semibold))
            Text("This changes the screenplay text used for this scene and its generated prompts. The imported screenplay file is preserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .accessibilityIdentifier("sceneScreenplayEditor.text")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    Task {
                        if await model.setSceneText(sceneID: sceneID, text: text) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .accessibilityIdentifier("sceneScreenplayEditor.save")
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 520)
    }
}
