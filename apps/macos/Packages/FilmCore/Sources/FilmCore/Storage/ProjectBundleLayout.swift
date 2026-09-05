import Foundation

public struct ProjectBundleLayout: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public var databaseURL: URL { rootURL.appending(path: "project.db") }
    public var screenplayDirectoryURL: URL { rootURL.appending(path: "screenplay", directoryHint: .isDirectory) }
    public var assetsDirectoryURL: URL { rootURL.appending(path: "assets", directoryHint: .isDirectory) }
    public var exportsDirectoryURL: URL { rootURL.appending(path: "exports", directoryHint: .isDirectory) }
    public var cacheDirectoryURL: URL { rootURL.appending(path: "cache", directoryHint: .isDirectory) }
    public var logsDirectoryURL: URL { rootURL.appending(path: "logs", directoryHint: .isDirectory) }

    public static let requiredDirectories = ["screenplay", "assets", "exports", "cache", "logs"]

    func createDirectories(fileManager: FileManager) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: false)
        for component in Self.requiredDirectories {
            try fileManager.createDirectory(
                at: rootURL.appending(path: component, directoryHint: .isDirectory),
                withIntermediateDirectories: false
            )
        }
    }
}

