import SwiftUI

struct AddScenesSheet: View {
  @Bindable var model: ProjectWindowModel
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var errorMessage: String?
  @State private var isWorking = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Add Scenes")
        .font(.title2.weight(.semibold))
      Text(
        "Paste the new scenes below, including each scene heading (for example, INT. HOUSE - DAY). They will be added at the end of your screenplay."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      TextEditor(text: $text)
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
        .frame(minHeight: 240)
        .disabled(isWorking)
        .accessibilityLabel("New scene screenplay text")
        .accessibilityIdentifier("addScenes.text")
        .onChange(of: text) { _, _ in
          errorMessage = nil
        }

      Text(
        "Existing scene work and the original imported file are preserved. Speaking characters and locations are linked automatically; other references can be added in Scene Data. This addition cannot be undone and clears undo history."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if let errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("addScenes.error")
      }

      HStack {
        if isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
          .disabled(isWorking)
          .accessibilityIdentifier("addScenes.cancel")
        Button("Add Scenes") { add() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(isWorking || text.isEmpty || !model.canAddScenes)
          .accessibilityIdentifier("addScenes.add")
      }
    }
    .padding(24)
    .frame(width: 720, height: 650)
    .interactiveDismissDisabled(isWorking)
  }

  private func add() {
    guard !isWorking else { return }
    isWorking = true
    errorMessage = nil
    Task {
      defer { isWorking = false }
      do {
        if try await model.appendScenes(text: text) {
          dismiss()
        } else {
          errorMessage = "Finish the current operation before adding scenes."
        }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
