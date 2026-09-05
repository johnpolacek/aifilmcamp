import CryptoKit
import Foundation
import FilmScript

public enum ProjectBundle {
    /// Creates an **empty** project (PHASE1_DESIGN §4.1).
    ///
    /// Phase 1 projects hold no screenplay until `importScreenplay(from:actor:)` puts one
    /// there; automation imports the bundled sample after creation.
    public static func create(
        at destinationURL: URL,
        name: String,
        fileManager: FileManager = .default
    ) throws -> ProjectSession {
        let destination = destinationURL.standardizedFileURL
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ProjectStoreError.targetAlreadyExists
        }
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appending(
            path: ".\(destination.lastPathComponent).staging-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        var shouldCleanStaging = true
        defer {
            if shouldCleanStaging {
                try? fileManager.removeItem(at: staging)
            }
        }

        let stagingLayout = ProjectBundleLayout(rootURL: staging)
        try stagingLayout.createDirectories(fileManager: fileManager)
        let database = try ProjectDatabase(url: stagingLayout.databaseURL, creating: true)
        let repository = ProjectRepository(database: database)
        try repository.initialize(projectName: name)
        _ = try repository.validateProject()
        try database.checkpoint()
        try fileManager.moveItem(at: staging, to: destination)
        shouldCleanStaging = false
        return try open(at: destination, fileManager: fileManager)
    }

    /// Opens a bundle, migrating it if needed. The returned session reports any upgrade
    /// through `upgradeSummary`.
    public static func open(
        at bundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> ProjectSession {
        let layout = ProjectBundleLayout(rootURL: bundleURL)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: layout.rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectStoreError.invalidBundle
        }
        let values = try layout.databaseURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ProjectStoreError.invalidDatabaseFile
        }
        let database = try ProjectDatabase(url: layout.databaseURL, creating: false)
        let repository = ProjectRepository(database: database)
        let project = try repository.validateProject()
        // §3.9: a job left non-terminal by a previous launch was abandoned with its
        // process. `paused` survives relaunch by contract and is left alone.
        try repository.reapAbandonedJobs()
        // The summary reports the warnings that were *persisted*, not a second parse.
        let summary = database.upgradeSummary.map { summary in
            UpgradeSummary(
                fromVersion: summary.fromVersion,
                toVersion: summary.toVersion,
                sceneCount: summary.sceneCount,
                entityCount: summary.entityCount,
                sequenceCount: summary.sequenceCount,
                synopsesDropped: summary.synopsesDropped,
                parseWarnings: (try? repository.persistedParseWarnings()) ?? summary.parseWarnings
            )
        }
        return ProjectSession(
            layout: layout,
            database: database,
            project: project,
            upgradeSummary: summary
        )
    }

    /// Copies a **closed** bundle directory to a new location (PHASE1_DESIGN §3.11's
    /// Duplicate Project…).
    ///
    /// This is a byte copy, not a migration: the schema, the project id, and every row are
    /// carried over unchanged. The caller is responsible for closing the source session
    /// first — an open session may still hold uncheckpointed WAL frames.
    ///
    /// - Throws: `ProjectStoreError.invalidBundle` when the source is not a directory
    ///   holding a `project.db`, and `.targetAlreadyExists` when the destination exists.
    public static func duplicate(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let source = sourceURL.standardizedFileURL
        let destination = destinationURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectStoreError.invalidBundle
        }
        let sourceLayout = ProjectBundleLayout(rootURL: source)
        guard fileManager.fileExists(atPath: sourceLayout.databaseURL.path) else {
            throw ProjectStoreError.invalidBundle
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ProjectStoreError.targetAlreadyExists
        }

        // Stage beside the destination so a partial copy is never visible under the final
        // name — the same discipline `create` uses.
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appending(
            path: ".\(destination.lastPathComponent).duplicating-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        var shouldCleanStaging = true
        defer {
            if shouldCleanStaging {
                try? fileManager.removeItem(at: staging)
            }
        }
        try fileManager.copyItem(at: source, to: staging)
        try fileManager.moveItem(at: staging, to: destination)
        shouldCleanStaging = false
    }

    /// Reports a bundle's schema version **without opening the database**.
    ///
    /// `ProjectDatabase` migrates unconditionally, so the upgrade modal (Plan 004) cannot
    /// use it to decide whether to offer the upgrade. SQLite's file header carries
    /// `user_version` as a 4-byte big-endian integer at offset 60; a missing or short file
    /// is `.invalidBundle`.
    public static func inspect(
        at bundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> BundleInspection {
        let layout = ProjectBundleLayout(rootURL: bundleURL)
        guard let handle = try? FileHandle(forReadingFrom: layout.databaseURL) else {
            throw ProjectStoreError.invalidBundle
        }
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 64), header.count == 64 else {
            throw ProjectStoreError.invalidBundle
        }
        let version = header[60...].reduce(Int(0)) { ($0 << 8) | Int($1) }
        return BundleInspection(bundleURL: layout.rootURL, schemaVersion: version)
    }
}

extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    /// SHA-256 over this string's UTF-8 bytes — the digest `scripts.sha256` records.
    var sha256HexOfUTF8: String {
        Data(utf8).sha256Hex
    }
}
