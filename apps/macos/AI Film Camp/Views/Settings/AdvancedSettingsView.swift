import SwiftUI

struct AdvancedSettingsView: View {
    @AppStorage(ExtractionPreferences.chunkModelKey) private var chunkModel = ""
    @AppStorage(ExtractionPreferences.chunkEffortKey) private var chunkEffort = ""
    @AppStorage(ExtractionPreferences.reconcileModelKey) private var reconcileModel = ""
    @AppStorage(ExtractionPreferences.reconcileEffortKey) private var reconcileEffort = ""

    var body: some View {
        Form {
            Section("Chunk extraction") {
                TextField("Model", text: $chunkModel, prompt: Text("Codex default"))
                TextField("Reasoning effort", text: $chunkEffort, prompt: Text("Codex default"))
            }
            Section("Entity reconciliation") {
                TextField("Model", text: $reconcileModel, prompt: Text("Codex default"))
                TextField("Reasoning effort", text: $reconcileEffort, prompt: Text("Codex default"))
            }
            Text("Values are captured when a run starts. Leave a field empty to use your Codex account default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("advancedSettingsTab")
    }
}
