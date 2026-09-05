import FilmBrain
import SwiftUI

struct ImageGeneratorSettingsView: View {
    @AppStorage(ImageGeneratorPreferences.providerIDKey) private var providerID =
        ImageProviderDescriptor.googleNanoBanana2.id
    @State private var model = ImageGeneratorSettingsModel()
    @State private var apiKey = ""
    @State private var showsRemoveConfirmation = false

    private var provider: ImageProviderDescriptor {
        ImageProviderCatalog.provider(id: providerID) ?? .googleNanoBanana2
    }

    var body: some View {
        Form {
            Section("Image provider") {
                Picker("Provider", selection: $providerID) {
                    ForEach(ImageProviderCatalog.builtIn) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                Text("Model: \(provider.modelID) · fixed 1K output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(provider.credentialLabel) {
                SecureField(model.isConfigured ? "Enter a replacement key" : "Enter API key", text: $apiKey)
                    .textContentType(.password)
                    .accessibilityIdentifier("imageGenerator.apiKey")
                HStack {
                    Button(model.isConfigured ? "Replace Key" : "Set Key") {
                        Task { await saveKey() }
                    }
                    .disabled(model.isWorking || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if model.isConfigured {
                        Button("Remove Key", role: .destructive) {
                            showsRemoveConfirmation = true
                        }
                        .disabled(model.isWorking)
                    }
                    Spacer()
                    Link("Get an API key", destination: provider.credentialHelpURL)
                }
                if model.isConfigured {
                    Label(provider.credentialStatusLabel, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("imageGenerator.keyConfigured")
                } else {
                    Label(
                        "Missing image generation API Key",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("imageGenerator.keyMissing")
                }
                Text("Keys are device-local and are never stored in project files or preferences. Film Camp does not display or copy a saved key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                if model.isWorking {
                    ProgressView()
                }
                if let message = model.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if let status = model.status {
                    Label(
                        statusMessage(status),
                        systemImage: statusIsReady(status) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(statusIsReady(status) ? Color.green : Color.orange)
                    .accessibilityIdentifier("imageGenerator.status")
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("imageGeneratorSettingsTab")
        .confirmationDialog(
            "Remove the \(provider.displayName) API key?",
            isPresented: $showsRemoveConfirmation
        ) {
            Button("Remove Key", role: .destructive) {
                Task { await removeKey() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Film Camp will no longer be able to generate with this provider until you set another key.")
        }
        .task(id: providerID) {
            apiKey = ""
            await model.refresh(provider: provider)
        }
    }

    private func saveKey() async {
        if await model.save(apiKey, provider: provider) {
            apiKey = ""
        }
    }

    private func removeKey() async {
        if await model.remove(provider: provider) {
            apiKey = ""
        }
    }

    private func statusIsReady(_ status: ImageGeneratorStatus) -> Bool {
        if case .ready = status { return true }
        return false
    }

    private func statusMessage(_ status: ImageGeneratorStatus) -> String {
        switch status {
        case .helperUnavailable:
            "The bundled image helper is unavailable. Reinstall Film Camp."
        case let .helperIncompatible(reason):
            reason
        case let .providerNotConfigured(name):
            "Missing image generation API Key for \(name)."
        case let .ready(context):
            "Ready to generate with \(context.provider.displayName)."
        }
    }
}
