import AppKit
import FilmBrain
import FilmCore
import Foundation
import UniformTypeIdentifiers

@MainActor
struct ProjectPanelService {
    func destinationForNewProject() async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create Empty AI Film Camp Project"
        panel.nameFieldStringValue = "My Film.aifilm"
        panel.allowedContentTypes = [.aiFilmProject]
        panel.canCreateDirectories = true
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        return url.pathExtension == "aifilm" ? url : url.appendingPathExtension("aifilm")
    }

    func projectToOpen() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open AI Film Camp Project"
        panel.allowedContentTypes = [.aiFilmProject]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return await panel.begin() == .OK ? panel.url : nil
    }

    /// The screenplay chooser behind all three import entry points.
    ///
    /// The panel accepts `.fountain`, `.fdx`, `.txt`, and `.pdf`. The broad
    /// system types plus the extension predicate avoid conflicts with exported
    /// UTI declarations from installed screenwriting applications.
    func screenplayToImport(title: String = "Import Screenplay") async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [.plainText, .xml, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let delegate = ScreenplayOpenPanelDelegate()
        panel.delegate = delegate
        defer { withExtendedLifetime(delegate) {} }
        return await panel.begin() == .OK ? panel.url : nil
    }

    /// The reference-image chooser behind the requirement inspector's Add Image action.
    func imageToImport() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Add Reference Image"
        panel.allowedContentTypes = [.png, .jpeg, .webP, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return await panel.begin() == .OK ? panel.url : nil
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Enables only the screenplay extensions the importer accepts.
///
/// `NSOpenPanel.delegate` is weak, so the caller retains this value while the
/// panel is presented.
final class ScreenplayOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    static let allowedExtensions: Set<String> = ["fountain", "txt", "fdx", "pdf"]

    nonisolated func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue { return true }
        return Self.allowedExtensions.contains(url.pathExtension.lowercased())
    }
}

struct AppServices: Sendable {
    let extractionConcurrencyOverride: Int?

    init(extractionConcurrencyOverride: Int? = nil) {
        self.extractionConcurrencyOverride = extractionConcurrencyOverride
    }

    static func configured(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppServices {
        #if DEBUG
        let concurrency = argument(after: "--film-camp-extraction-concurrency", in: arguments)
            .flatMap(Int.init)
            .flatMap { $0 > 0 ? $0 : nil }
        return AppServices(extractionConcurrencyOverride: concurrency)
        #else
        return AppServices()
        #endif
    }

    #if DEBUG
    private static func argument(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
    #endif

    @MainActor
    var panels: ProjectPanelService { ProjectPanelService() }

    func detectCodex() async -> HarnessStatus {
        await CodexLocator().locate()
    }

    func makeAdapter(status: HarnessStatus?) throws -> any HarnessAdapter {
        guard case .some(.ready(let context, _, _, _)) = status else {
            throw UserFacingServiceError.codexUnavailable
        }
        return CodexHarnessAdapter(context: context)
    }
}

enum UserFacingServiceError: Error, LocalizedError {
    case codexUnavailable

    var errorDescription: String? {
        "Codex is not ready. Install Codex, run codex login, and refresh its status."
    }
}
