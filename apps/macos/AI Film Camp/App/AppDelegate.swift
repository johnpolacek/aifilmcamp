import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingOpenURLs: [URL] = []
    private var startTask: Task<Void, Never>?

    private var storedCoordinator: AppCoordinator?

    /// The app's one `AppCoordinator`, owned here because `AIFilmCampApp` cannot give a
    /// `@State` default a value that reads the delegate adaptor. The App reads it back
    /// through the adaptor instead.
    ///
    /// Constructed on first access rather than only in `applicationWillFinishLaunching`:
    /// SwiftUI evaluates the `App`'s scene content before that callback runs. Whichever
    /// comes first, construction still precedes `application(_:open:)` and any window, so
    /// the one-shot URL handler is never installed twice or late.
    var coordinator: AppCoordinator {
        if let storedCoordinator { return storedCoordinator }
        let created = AppCoordinator(services: .configured(), appDelegate: self)
        storedCoordinator = created
        return created
    }

    var openURLsHandler: (([URL]) -> Void)? {
        didSet {
            guard let openURLsHandler, !pendingOpenURLs.isEmpty else { return }
            let urls = pendingOpenURLs
            pendingOpenURLs.removeAll()
            openURLsHandler(urls)
        }
    }

    /// Runs **before** `application(_:open:)` and before any scene appears, so the
    /// coordinator's one-shot URL handler is installed ahead of every Finder URL — and
    /// the saved appearance is on before the first window draws, so a dark default never
    /// flashes light.
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = coordinator
        AppearancePreference.current.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launch work (Codex detection, the recorded Finder smoke) must not be tied to a
        // scene's lifetime: Welcome closes as soon as a project window opens.
        let coordinator = coordinator
        startTask = Task { await coordinator.start() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let openURLsHandler {
            openURLsHandler(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    /// Quit waits for every window's `session.close()` so no database is left open — the
    /// Finder smoke's `lsof` check depends on it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator = storedCoordinator else { return .terminateNow }
        Task {
            await coordinator.awaitOutstandingCloses()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
