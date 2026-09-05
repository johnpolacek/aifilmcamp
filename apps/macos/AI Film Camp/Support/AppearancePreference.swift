import AppKit
import Foundation

/// The app-wide appearance override (Settings ▸ General): follow the system, or force
/// light/dark for every window. **Defaults to dark** per product decision, so a fresh
/// install opens dark regardless of the Mac's own setting; choosing System hands the
/// decision back (`NSApp.appearance = nil`) and tracks appearance changes live.
///
/// The choice is a plain UserDefaults string, applied by setting `NSApp.appearance` —
/// one global handle every window inherits, so no view reads this type and no SwiftUI
/// `colorScheme` plumbing exists anywhere.
enum AppearancePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    static let defaultsKey = "com.aifilmcamp.appearance"

    /// The fresh-install default: dark.
    static var current: AppearancePreference {
        current(defaults: .standard)
    }

    static func current(defaults: UserDefaults) -> AppearancePreference {
        AppearancePreference(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .dark
    }

    func store(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    /// Applies the preference to the running app. `.system` clears the override so
    /// windows track the Mac's appearance changes live.
    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
