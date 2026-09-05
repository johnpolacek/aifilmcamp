import FilmBrain
import Foundation

/// App-wide provider selection. Provider credentials live exclusively in Keychain.
enum ImageGeneratorPreferences {
    static let providerIDKey = "com.aifilmcamp.imageGenerator.providerID"
    private static let legacyPresetIDKey = "com.aifilmcamp.imageGenerator.presetID"
    private static let legacyExecutableOverrideKey =
        "com.aifilmcamp.imageGenerator.executableOverride"

    static func provider(defaults: UserDefaults = .standard) -> ImageProviderDescriptor {
        let selected: String
        if let stored = defaults.string(forKey: providerIDKey) {
            selected = stored
        } else {
            selected = ImageProviderDescriptor.googleNanoBanana2.id
            defaults.set(selected, forKey: providerIDKey)
            defaults.removeObject(forKey: legacyPresetIDKey)
            defaults.removeObject(forKey: legacyExecutableOverrideKey)
        }
        return ImageProviderCatalog.provider(id: selected) ?? .googleNanoBanana2
    }

    static func helperURL(bundle: Bundle = .main) -> URL {
        bundle.bundleURL
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Helpers", directoryHint: .isDirectory)
            .appending(path: "filmcamp-image-helper")
    }
}
