import SwiftUI

/// The `Settings` scene of contract C (⌘,): General / Codex / Advanced.
struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            codex
                .tabItem { Label("Codex", systemImage: "terminal") }
            ImageGeneratorSettingsView()
                .tabItem { Label("Images", systemImage: "photo.badge.plus") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 560, height: 390)
    }

    private var general: some View {
        Form {
            Picker("Appearance", selection: appearanceBinding) {
                ForEach(AppearancePreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("appearanceSetting")
            LabeledContent("Version", value: Self.versionText)
            Text("Each project opens in its own window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("generalSettingsTab")
    }

    /// Writes through to the saved preference and applies it live — every open window
    /// follows `NSApp.appearance` immediately, and System resumes tracking the Mac.
    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference.current },
            set: { newValue in
                newValue.store()
                newValue.apply()
            }
        )
    }

    private var codex: some View {
        VStack {
            CodexStatusView(coordinator: coordinator)
            Spacer()
        }
        .padding(20)
        .accessibilityIdentifier("codexSettingsTab")
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
