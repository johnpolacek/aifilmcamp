import AppKit
import FilmBrain
import FilmCore
import Foundation
import Observation
import SwiftUI

/// The one shared owner of Codex status, Finder URL routing, recent documents, and the set
/// of open `ProjectWindowModel`s (PHASE1_DESIGN §3.11, Plan 004 contract A).
///
/// `AppDelegate` constructs it in `applicationWillFinishLaunching`, which precedes
/// `application(_:open:)` — so the one-shot URL handler is installed before any Finder URL
/// arrives and before any scene appears.
@MainActor
@Observable
final class AppCoordinator {
    /// A v1 bundle waiting on the one-way upgrade modal (§5.5). `MigrationUpgradeSheet`
    /// presents it from the Welcome window and answers with `upgradeConfirmed(url:)` or
    /// `upgradeCancelled()`.
    struct PendingUpgrade: Identifiable, Equatable {
        let url: URL
        var id: URL { url }
    }

    /// A screenplay picked for a new project, already parsed and validated, with
    /// the title the confirmation sheet prefills.
    struct PendingProjectCreation: Identifiable, Equatable {
        let id = UUID()
        let sourceURL: URL
        let preview: ScreenplayPreview

        static func == (lhs: PendingProjectCreation, rhs: PendingProjectCreation) -> Bool {
            lhs.id == rhs.id
        }
    }

    let services: AppServices

    private(set) var harnessStatus: HarnessStatus?
    /// `true` until the first detection completes. The status is `nil` rather than
    /// `.notInstalled` so the Welcome and Settings surfaces show a spinner instead of
    /// flashing "Codex not installed" during the launch probe.
    /// Open projects, keyed by **standardized + symlink-resolved** bundle URL.
    private(set) var windowModels: [URL: ProjectWindowModel] = [:]
    /// Welcome's Projects list, in order: recent documents (most recently used first),
    /// then `.aifilm` bundles discovered on the Desktop and in Documents that are not
    /// already listed. `NSDocumentController.recentDocumentURLs` is not observable, so the
    /// list is a mirror refreshed wherever its inputs can change.
    private(set) var recentURLs: [URL] = []
    var pendingUpgrade: PendingUpgrade?
    /// A screenplay chosen for a new project and parsed, waiting on the title
    /// confirmation sheet (`NewProjectSheet`). The bundle is created only after
    /// the operator confirms — never before.
    var pendingCreation: PendingProjectCreation?
    var error: UserFacingError?

    @ObservationIgnored private var windows: [URL: NSWindow] = [:]
    @ObservationIgnored private var delegates: [URL: ProjectWindowDelegate] = [:]
    /// Window teardown in flight; `applicationShouldTerminate` waits on all of it.
    @ObservationIgnored private var outstandingCloses: [UUID: Task<Void, Never>] = [:]
    /// The scene actions are plain closures because the coordinator cannot retain SwiftUI
    /// environment values such as `OpenWindowAction` and `DismissWindowAction` directly.
    @ObservationIgnored private var openProjectWindow: ((URL) -> Void)?
    @ObservationIgnored private var openSceneWindow: ((String) -> Void)?
    @ObservationIgnored private var dismissSceneWindow: ((String) -> Void)?
    @ObservationIgnored private var dismissProjectWindow: ((URL) -> Void)?
    /// URLs that arrived (from Finder, typically) before any scene could give us
    /// `openWindow`. Flushed by `installWindowActions`.
    @ObservationIgnored private var queuedOpenURLs: [URL] = []
    @ObservationIgnored private var didStart = false

    init(services: AppServices, appDelegate: AppDelegate) {
        self.services = services
        // Contract A: installed **once**, here, never from a view's `onAppear` — Welcome is
        // a scene that closes and reopens, and a re-assignment would re-flush or stale the
        // one-shot queue.
        appDelegate.openURLsHandler = { [weak self] urls in
            guard let self, let first = urls.first else { return }
            Task { await self.open(url: first) }
        }
        refreshRecentDocuments()
    }

    // MARK: - Canonical URLs

    /// SwiftUI matches an existing `WindowGroup` window by value equality, so a raw
    /// `/var/…` and a resolved `/private/var/…` would otherwise open the same bundle twice.
    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    // MARK: - Codex status

    var isCodexReady: Bool {
        guard let status = harnessStatus, case .ready = status else { return false }
        return true
    }

    /// `true` while detection is in flight (before the first probe lands).
    var isCheckingCodex: Bool { harnessStatus == nil }

    var codexStatusText: String {
        guard let status = harnessStatus else { return "Checking Codex…" }
        switch status {
        case .notInstalled: return "Codex not installed"
        case let .installedButUnauthenticated(path, version): return "Codex \(version) is signed out at \(path)"
        case let .installedButIncompatible(path, version, missing):
            return "Codex \(version) at \(path) is incompatible (missing \(missing.joined(separator: ", ")))"
        case let .ready(context, version, mode, _):
            return "Ready — Codex \(version), \(mode.rawValue), \(context.executableURL.path)"
        case let .detectionFailed(message): return message
        }
    }

    var codexStatusSummaryText: String {
        guard let status = harnessStatus else { return "Checking Codex…" }
        switch status {
        case .notInstalled: return "Codex not installed"
        case .installedButUnauthenticated: return "Codex signed out"
        case .installedButIncompatible: return "Codex incompatible"
        case .ready: return "Codex ready"
        case .detectionFailed: return "Codex unavailable"
        }
    }

    func refreshCodex() async {
        harnessStatus = await services.detectCodex()
    }

    /// Launch work that must not be tied to a scene's lifetime.
    func start() async {
        guard !didStart else { return }
        didStart = true
        await refreshCodex()
    }

    // MARK: - Window actions

    /// Scenes hand the coordinator the environment actions it cannot read for itself.
    func installWindowActions(
        openProjectWindow: @escaping (URL) -> Void,
        openSceneWindow: @escaping (String) -> Void,
        dismissSceneWindow: @escaping (String) -> Void,
        dismissProjectWindow: @escaping (URL) -> Void
    ) {
        self.openProjectWindow = openProjectWindow
        self.openSceneWindow = openSceneWindow
        self.dismissSceneWindow = dismissSceneWindow
        self.dismissProjectWindow = dismissProjectWindow
        guard !queuedOpenURLs.isEmpty else { return }
        let urls = queuedOpenURLs
        queuedOpenURLs.removeAll()
        Task { [weak self] in
            for url in urls { await self?.open(url: url) }
        }
    }

    // MARK: - Opening

    /// Screenplay-first Create Project (owner decision 2026-08-25): choose a
    /// screenplay, parse and validate it, confirm the derived title — and only
    /// then create the bundle. The empty-project path survives as
    /// `createEmptyProject()`, its own explicit command.
    ///
    func createProject() async {
        guard let sourceURL = await services.panels.screenplayToImport(title: "Choose a Screenplay")
        else { return }
        let preview: ScreenplayPreview
        do {
            preview = try await Task.detached(priority: .userInitiated) {
                try ScreenplayPreview.preview(at: sourceURL)
            }.value
        } catch {
            // Nothing was created: the file is refused before any bundle exists.
            self.error = UserFacingError(
                title: "Screenplay Error",
                message: (error as? LocalizedError)?.errorDescription
                    ?? "The screenplay could not be read."
            )
            return
        }
        pendingCreation = PendingProjectCreation(sourceURL: sourceURL, preview: preview)
    }

    /// The confirmation sheet's Create action. Dismisses the sheet first (the
    /// same gesture-before-state discipline as `performReplace`), creates the
    /// bundle beside the chosen screenplay with the confirmed title, imports in
    /// the same breath, and only then presents the window.
    func confirmCreateProject(named title: String) async {
        guard let pending = pendingCreation else { return }
        pendingCreation = nil
        let confirmedTitle = ScreenplayPreview.projectTitle(from: title)
            ?? pending.preview.suggestedTitle
        let destination = Self.availableProjectDestination(
            beside: pending.sourceURL,
            title: confirmedTitle
        )
        await create(at: destination, importing: pending.sourceURL)
    }

    /// New screenplay-first projects live beside their source screenplay. Never
    /// overwrite an existing bundle: follow Finder's familiar numbered-copy
    /// convention (`Title.aifilm`, `Title 2.aifilm`, ...).
    static func availableProjectDestination(
        beside screenplayURL: URL,
        title: String,
        fileManager: FileManager = .default
    ) -> URL {
        let directory = screenplayURL.deletingLastPathComponent().standardizedFileURL
        var copyNumber = 1
        while true {
            let suffix = copyNumber == 1 ? "" : " \(copyNumber)"
            let candidate = directory.appending(
                path: "\(title)\(suffix).aifilm",
                directoryHint: .isDirectory
            )
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            copyNumber += 1
        }
    }

    func cancelCreateProject() {
        pendingCreation = nil
    }

    /// Create Empty Project: the old flow, kept as its own explicit command.
    func createEmptyProject() async {
        guard let destination = await services.panels.destinationForNewProject() else { return }
        await create(at: destination, importing: nil)
    }

    /// The one creation path behind both commands: make the bundle, import the
    /// screenplay when there is one, and present the window. A failure after the
    /// bundle exists closes the session and removes the just-created bundle —
    /// it holds nothing the operator made — before surfacing the error.
    ///
    /// Internal so `AppShellTests` can drive it without a save panel.
    func create(at destination: URL, importing sourceURL: URL?) async {
        var session: ProjectSession?
        do {
            let created = try ProjectBundle.create(
                at: destination,
                name: destination.deletingPathExtension().lastPathComponent
            )
            session = created
            if let sourceURL {
                _ = try await created.importScreenplay(from: sourceURL, actor: .human)
            }
            let key = Self.canonical(destination)
            await present(session: created, at: key)
            if sourceURL != nil {
                await windowModels[key]?.prepareExtraction()
            }
        } catch {
            if let session {
                try? await session.close()
                try? FileManager.default.removeItem(at: Self.canonical(destination))
            }
            // A refusal that owns its wording (§5.5, PDFReader's diagnostics)
            // surfaces verbatim; anything else gets text that matches where it
            // happened — a failed import left nothing behind, a failed create
            // never made anything.
            self.error = session == nil
                ? .project(error)
                : UserFacingError(
                    title: "Screenplay Error",
                    message: (error as? LocalizedError)?.errorDescription
                        ?? "The screenplay could not be imported."
                )
        }
    }

    func openProject() async {
        guard let url = await services.panels.projectToOpen() else { return }
        await open(url: url)
    }

    /// The one open path: canonicalize → `inspect` → (v1 ⇒ modal) → open → window.
    func open(url: URL) async {
        let key = Self.canonical(url)
        if windowModels[key] != nil {
            activateWindow(for: key)
            return
        }
        guard openProjectWindow != nil else {
            // A Finder URL beat the first scene; replay it once `openWindow` exists.
            queuedOpenURLs.append(key)
            return
        }
        do {
            let inspection = try ProjectBundle.inspect(at: key)
            if inspection.needsOneWayUpgrade {
                // The destructive Phase 0 migration, and only that one: nothing is opened
                // until the operator confirms. Every later migration is non-destructive and
                // silent by contract (§4.2a), so this gate is "schema 1", never "a migration
                // is pending" — otherwise every existing project would open with a modal
                // warning that its scenes are about to be rebuilt.
                requestUpgrade(at: key)
                return
            }
            let session = try ProjectBundle.open(at: key)
            await present(session: session, at: key)
        } catch {
            self.error = .project(error)
        }
    }

    /// Arms the one-way upgrade modal (§5.5). The modal is hosted by the Welcome window —
    /// the one scene that exists whether or not a project is open — so the Welcome window is
    /// brought back first when a Finder open of a v1 bundle arrives with it closed.
    private func requestUpgrade(at key: URL) {
        openSceneWindow?(AIFilmCampScene.welcome)
        pendingUpgrade = PendingUpgrade(url: key)
    }

    /// The Upgrade continuation of the v1 modal (`MigrationUpgradeSheet`): opening the
    /// bundle is what migrates it, and the resulting session carries the `UpgradeSummary`
    /// the window then shows.
    func upgradeConfirmed(url: URL) async {
        let key = Self.canonical(url)
        pendingUpgrade = nil
        do {
            let session = try ProjectBundle.open(at: key)
            await present(session: session, at: key)
        } catch {
            self.error = .project(error)
        }
    }

    /// Cancel opens nothing (§5.5).
    func upgradeCancelled() {
        pendingUpgrade = nil
    }

    private func present(session: ProjectSession, at key: URL) async {
        // `ProjectUndoManager`, not a stock one: it is what disables the system Edit ▸
        // Undo / Redo items while an inverse applies, and what keeps one command one undo
        // step (Plan 005 §3.8, `UndoBridge.swift`).
        let model = makeWindowModel(session: session, undoManager: ProjectUndoManager())
        windowModels[key] = model
        delegates[key]?.model = model
        noteRecentDocument(key)
        await model.start()
        openProjectWindow?(key)
        dismissWelcome()
    }

    private func activateWindow(for key: URL) {
        // SwiftUI matches by value: opening the same URL again fronts the existing window.
        openProjectWindow?(key)
        windows[key]?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Restoration

    /// Production keeps window restoration, so SwiftUI re-presents project windows on
    /// relaunch **without** `openWindow`. The root view adopts its URL through the same
    /// `inspect` → v1 modal → open path, so a v1 bundle can never migrate unannounced.
    func adopt(url: URL) async {
        let key = Self.canonical(url)
        if windowModels[key] != nil {
            dismissWelcome()
            return
        }
        do {
            let inspection = try ProjectBundle.inspect(at: key)
            if inspection.needsOneWayUpgrade {
                requestUpgrade(at: key)
                return
            }
            let session = try ProjectBundle.open(at: key)
            let model = makeWindowModel(session: session, undoManager: ProjectUndoManager())
            windowModels[key] = model
            delegates[key]?.model = model
            noteRecentDocument(key)
            await model.start()
            dismissWelcome()
        } catch {
            // Missing or unreadable: surface it and let the restored window go.
            self.error = .project(error)
            dismissProjectWindow?(key)
        }
    }

    func model(for url: URL) -> ProjectWindowModel? {
        windowModels[Self.canonical(url)]
    }

    // MARK: - Window bridge

    /// Installs the one `ProjectWindowDelegate` for this window, preserving SwiftUI's.
    func attach(window: NSWindow, for url: URL) {
        let key = Self.canonical(url)
        windows[key] = window
        if let existing = delegates[key] {
            existing.model = windowModels[key]
            if window.delegate !== existing { window.delegate = existing }
            return
        }
        let delegate = ProjectWindowDelegate(
            next: window.delegate,
            model: windowModels[key]
        ) { [weak self] model in
            self?.windowWillClose(model)
        }
        delegates[key] = delegate
        window.delegate = delegate
    }

    private func windowWillClose(_ model: ProjectWindowModel) {
        let key = Self.canonical(model.bundleURL)
        windowModels.removeValue(forKey: key)
        delegates.removeValue(forKey: key)
        windows.removeValue(forKey: key)
        let id = UUID()
        // One of the two detached tasks the design permits; the coordinator tracks it so
        // quit cannot outrun the database close (the Finder smoke's `lsof` check).
        outstandingCloses[id] = Task { [weak self] in
            await model.close()
            self?.outstandingCloses[id] = nil
        }
        if windowModels.isEmpty {
            // Welcome is coming back: rescan so its Projects list reflects anything that
            // moved onto disk while the project was open.
            refreshRecentDocuments()
            openSceneWindow?(AIFilmCampScene.welcome)
        }
    }

    /// Awaited by `applicationShouldTerminate` before it replies.
    func awaitOutstandingCloses() async {
        while let (id, task) = outstandingCloses.first {
            await task.value
            outstandingCloses.removeValue(forKey: id)
        }
    }

    private func dismissWelcome() {
        dismissSceneWindow?(AIFilmCampScene.welcome)
    }

    // MARK: - Recent documents

    private func noteRecentDocument(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecentDocuments()
    }

    func clearRecentDocuments() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        refreshRecentDocuments()
    }

    private func refreshRecentDocuments() {
        var seen: Set<URL> = []
        var urls: [URL] = []
        for url in NSDocumentController.shared.recentDocumentURLs {
            let canonical = Self.canonical(url)
            guard canonical.pathExtension.lowercased() == "aifilm",
                  FileManager.default.fileExists(atPath: canonical.path),
                  seen.insert(canonical).inserted
            else { continue }
            urls.append(canonical)
        }
        // A bundle the app has never opened — a moved project, a new machine — is not in
        // the recents, so Welcome's Projects list also reads what the Desktop and
        // Documents folders hold.
        for url in Self.discoverableProjects(in: localScanRoots()) where seen.insert(url).inserted {
            urls.append(url)
        }
        recentURLs = urls
    }

    /// The folders the Welcome scan looks in.
    private func localScanRoots() -> [URL] {
        let fileManager = FileManager.default
        return fileManager.urls(for: .desktopDirectory, in: .userDomainMask)
            + fileManager.urls(for: .documentDirectory, in: .userDomainMask)
    }

    /// Shallow scan of the given folders for `.aifilm` bundles: the folder itself and one
    /// directory level below it, sorted by name. Depth is deliberately bounded because the
    /// scan runs on the main thread beside the recents refresh; a folder macOS will not
    /// let the app read (TCC) simply contributes nothing.
    static func discoverableProjects(
        in bases: [URL],
        fileManager: FileManager = .default
    ) -> [URL] {
        var folders: [URL] = []
        for base in bases {
            folders.append(base)
            for child in contents(of: base, fileManager: fileManager)
            where child.isDirectory {
                folders.append(child.url)
            }
        }
        var found: [URL] = []
        for folder in folders {
            for child in contents(of: folder, fileManager: fileManager)
            where child.url.pathExtension.lowercased() == "aifilm" && child.isDirectory {
                found.append(canonical(child.url))
            }
        }
        return found.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                == .orderedAscending
        }
    }

    private static func contents(
        of directory: URL,
        fileManager: FileManager
    ) -> [(url: URL, isDirectory: Bool)] {
        let children = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return children.map { url in
            (url, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false)
        }
    }

    private func makeWindowModel(
        session: ProjectSession,
        undoManager: UndoManager
    ) -> ProjectWindowModel {
        ProjectWindowModel(
            session: session,
            undoManager: undoManager,
            extractionAdapterFactory: { [weak self] in
                guard let self else { throw UserFacingServiceError.codexUnavailable }
                // A pending probe (`harnessStatus == nil`) refuses like any non-ready status.
                return try self.services.makeAdapter(status: self.harnessStatus)
            },
            extractionSettingsProvider: { [weak self] in
                guard let self else { return ExtractionPreferences.settings() }
                return ExtractionPreferences.settings(
                    chunkBudget: 32_000,
                    concurrency: self.services.extractionConcurrencyOverride ?? 0
                )
            },
            // The reference-image panel and Finder reveal are injected, keeping those
            // AppKit services out of the window model and SwiftUI views.
            imageChooser: { [weak self] in
                guard let self else { return nil }
                return await self.services.panels.imageToImport()
            },
            finderRevealer: { [weak self] url in
                self?.services.panels.reveal(url)
            }
        )
    }

    func reveal(_ url: URL) {
        services.panels.reveal(url)
    }

    /// File ▸ Delete Project: closes the project (session, window model, window), then
    /// moves the bundle to the Trash. The Trash is the undo story — the app never
    /// hard-deletes a bundle. A failure to trash surfaces and leaves everything open.
    func deleteProject(for url: URL) async {
        let key = Self.canonical(url)
        if let model = windowModels[key] {
            await model.close()
            windowModels[key] = nil
        }
        dismissProjectWindow?(key)
        do {
            try FileManager.default.trashItem(at: key, resultingItemURL: nil)
            // The Open Recent menu rebuilds through `refreshRecentDocuments`, whose
            // existence guard drops the trashed path on its own.
            refreshRecentDocuments()
        } catch {
            self.error = .project(error)
        }
    }

}

/// Scene identifiers used with `openWindow(id:)` / `dismissWindow(id:)`.
enum AIFilmCampScene {
    static let welcome = "welcome"
}
