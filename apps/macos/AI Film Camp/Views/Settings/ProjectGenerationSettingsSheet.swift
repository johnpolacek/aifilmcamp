import FilmCore
import SwiftUI

/// Project-scoped generation settings. These are document data, so they live beside the
/// project workspace rather than in the app-wide Settings scene.
struct ProjectGenerationSettingsSheet: View {
    @Bindable var model: ProjectWindowModel
    @Environment(\.dismiss) private var dismiss
    @State private var styleBible = ""
    @State private var loadedStyleBible = false
    @State private var skillChooserPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Settings").font(.title2.bold())

            Form {
                Picker("Target Profile", selection: profileBinding) {
                    ForEach(TargetProfileCatalog.all, id: \.id) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .accessibilityIdentifier("projectSettings.targetProfile")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Style Bible")
                    TextField("Shared visual direction for every scene", text: $styleBible, axis: .vertical)
                        .lineLimit(4 ... 10)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("projectSettings.styleBible")
                    HStack {
                        Spacer()
                        Button("Save Style Bible") {
                            let value = styleBible
                            Task { await model.setWorkspaceStyleBible(value) }
                        }
                        .accessibilityIdentifier("projectSettings.saveStyleBible")
                    }
                }

                LabeledContent("Prompt Skill") {
                    HStack(spacing: 8) {
                        Text(model.selectedSkillRow?.displayName ?? "Bundled Default")
                            .foregroundStyle(.secondary)
                        Button("Choose…") { skillChooserPresented = true }
                            .accessibilityIdentifier("projectSettings.skillChooser")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("projectSettings.done")
            }
        }
        .padding(20)
        .frame(width: 560, height: 500)
        .accessibilityIdentifier("projectSettingsSheet")
        .task {
            await model.loadWorkspaceSettings()
            guard loadedStyleBible == false else { return }
            loadedStyleBible = true
            styleBible = model.workspaceStyleBible
        }
        .sheet(isPresented: $skillChooserPresented) {
            SkillChooserSheet(model: model)
        }
    }

    private var profileBinding: Binding<String> {
        Binding(
            get: {
                model.scenePackageDetail?.activeProfile.id
                    ?? model.scenePackages.first?.activeProfileID
                    ?? TargetProfileCatalog.seedance2_5.id
            },
            set: { profileID in Task { await model.setGenerationTargetProfile(profileID) } }
        )
    }
}
