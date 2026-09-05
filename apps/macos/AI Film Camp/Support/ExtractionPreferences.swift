import FilmCore
import Foundation

enum ExtractionPreferences {
    static let chunkModelKey = "com.aifilmcamp.extraction.chunkModel"
    static let chunkEffortKey = "com.aifilmcamp.extraction.chunkEffort"
    static let reconcileModelKey = "com.aifilmcamp.extraction.reconcileModel"
    static let reconcileEffortKey = "com.aifilmcamp.extraction.reconcileEffort"

    static func settings(
        defaults: UserDefaults = .standard,
        chunkBudget: Int = 32_000,
        concurrency: Int = 0
    ) -> ExtractionSettings {
        ExtractionSettings(
            chunkModel: value(for: chunkModelKey, defaults: defaults),
            chunkEffort: value(for: chunkEffortKey, defaults: defaults),
            reconcileModel: value(for: reconcileModelKey, defaults: defaults),
            reconcileEffort: value(for: reconcileEffortKey, defaults: defaults),
            chunkBudget: chunkBudget,
            concurrency: concurrency
        )
    }

    private static func value(for key: String, defaults: UserDefaults) -> String? {
        let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
