import FilmBrain
import Foundation
import Observation

@MainActor
@Observable
final class ImageGeneratorSettingsModel {
    @ObservationIgnored private let credentialStore: any ImageProviderCredentialStore
    private(set) var isConfigured = false
    private(set) var status: ImageGeneratorStatus?
    private(set) var message: String?
    private(set) var isWorking = false

    init(credentialStore: any ImageProviderCredentialStore = ImageProviderKeychain.shared) {
        self.credentialStore = credentialStore
    }

    func refresh(provider: ImageProviderDescriptor) async {
        message = nil
        isConfigured = await credentialStore.isConfigured(providerID: provider.id)
        status = await LocalImageGenerator(
            provider: provider,
            helperURL: ImageGeneratorPreferences.helperURL(),
            credentialSource: credentialStore
        ).status()
    }

    func save(_ value: String, provider: ImageProviderDescriptor) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        message = nil
        do {
            try await credentialStore.set(value, providerID: provider.id)
            await refresh(provider: provider)
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func remove(provider: ImageProviderDescriptor) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        message = nil
        do {
            try await credentialStore.remove(providerID: provider.id)
            await refresh(provider: provider)
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}
