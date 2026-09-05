import SwiftUI

@main
struct AIFilmCampApp: App {
    init() {
        CampAppearance.registerFonts()
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The delegate owns the coordinator (it is constructed in
    /// `applicationWillFinishLaunching`, before any scene exists), so the App reads it back
    /// through the adaptor rather than defaulting a `@State`.
    private var coordinator: AppCoordinator { appDelegate.coordinator }

    var body: some Scene {
        // Scene order plus the explicit launch behaviors of contract A: Welcome is the only
        // window a cold launch presents; project windows are opened by value, never
        // auto-presented.
        Window("Welcome", id: AIFilmCampScene.welcome) {
            WelcomeView(coordinator: coordinator)
                .tint(CampAppearance.accent)
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 800, height: 720)
        .windowResizability(.contentMinSize)

        WindowGroup(for: URL.self) { $url in
            ProjectRootView(coordinator: coordinator, url: url)
                .tint(CampAppearance.accent)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(coordinator: coordinator)
            // §3.11's Entity menu is its own block so the File/Edit/View items and the
            // per-entity actions stay legible apart.
            EntityCommands()
        }

        Settings {
            SettingsView(coordinator: coordinator)
                .tint(CampAppearance.accent)
        }
    }
}

/// Hands the coordinator the window actions it cannot read for itself, and gives the
/// enclosing `NSWindow` its accessibility identifier.
struct SceneWindowBridge: View {
    let coordinator: AppCoordinator
    let accessibilityIdentifier: String
    var onWindow: (@MainActor (NSWindow) -> Void)?

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        WindowBridge(accessibilityIdentifier: accessibilityIdentifier) { window in
            onWindow?(window)
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .onAppear {
            // The environment actions are captured as closures: `AppShellTests` drives the
            // coordinator with stubs, and neither action type is constructible in a test.
            coordinator.installWindowActions(
                openProjectWindow: { openWindow(value: $0) },
                openSceneWindow: { openWindow(id: $0) },
                dismissSceneWindow: { dismissWindow(id: $0) },
                dismissProjectWindow: { dismissWindow(value: $0) }
            )
        }
    }
}
