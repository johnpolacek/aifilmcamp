import CryptoKit
import Foundation
import GRDB

// The scene-package exporter (PHASE5_DESIGN §3.8, §4.1; Plan 019 contract C) — the first
// code ever to write into `exports/`.
//
// Exports are **derived artifacts** (§3.1): nothing under `exports/` is journaled,
// undoable, or read back by the app. But the write itself is **staged, verified, then
// atomic**: the package is built complete in a sibling staging directory
// (`scene-<ordinal>.staging`, removed on entry if a prior attempt left one, never listed
// as a package); every copied reference is re-hashed and must equal the approved version's
// stored SHA-256 **before** that hash is recorded — a mismatch refuses via
// `.packageReferenceVerificationFailed` naming the file, and the export writes nothing
// rather than shipping bytes that disagree with their manifest; only a fully verified
// staging directory replaces the destination, so a mid-copy failure leaves the previous
// valid export untouched and no partial package can exist at the destination path.
//
// The output is **deterministic to the byte** given the same rows: sortedKeys JSON, no
// timestamps, no job ids, and no locale-dependent values.
//
// Export is **not** an `EditOperation`: it writes no canonical row, appears in no journal,
// and is not undoable (§3.8). Batch export loops over the Generation Ready set under the
// active profile P; it performs no generation, spends nothing.

/// One written package manifest (§4.1). Field list is part of the package identity:
/// additions require a `schemaVersion` bump here, never a silent edit.
struct ScenePackageManifest: Codable, Equatable, Sendable {
    struct Reference: Codable, Equatable, Sendable {
        var position: Int
        var `class`: String
        var name: String
        var role: String
        var exclusion: String
        var fidelity: String
        var filename: String
        var sha256: String
        var pixelWidth: Int
        var pixelHeight: Int
    }

    struct ContinuityEntry: Codable, Equatable, Sendable {
        var entity: String
        var category: String
        var description: String
    }

    var schemaVersion: Int = 2
    var sceneOrdinal: Int
    var sceneHeading: String
    var sceneSynopsis: String
    var targetProfileID: String
    var durationSeconds: Int?
    var aspectRatio: String
    var resolution: String
    var references: [Reference]
    var continuity: [ContinuityEntry]
    var styleBible: String
    var setNumber: Int
    var cardNumber: Int
    var cardTitle: String
    var inputDigest: String
    var promptSource: String
    var skillID: String
}

/// The written-manifest result (§4.4): directory, file list, byte counts.
public struct ScenePackageExport: Equatable, Sendable {
    public let sceneID: UUID
    /// Bundle-relative directory of the written package, e.g. `exports/scenes/scene-027`.
    public let relativeDirectory: String
    /// Bundle-relative files of the package, sorted.
    public let files: [String]
    public let byteCount: Int64

    public init(sceneID: UUID, relativeDirectory: String, files: [String], byteCount: Int64) {
        self.sceneID = sceneID
        self.relativeDirectory = relativeDirectory
        self.files = files
        self.byteCount = byteCount
    }
}

public struct ScenePromptCardMaterialization: Equatable, Sendable {
    public struct Reference: Equatable, Sendable {
        public let position: Int
        public let relativePath: String
        public let fileURL: URL

        public init(position: Int, relativePath: String, fileURL: URL) {
            self.position = position
            self.relativePath = relativePath
            self.fileURL = fileURL
        }
    }

    public let cardID: UUID
    public let directoryURL: URL
    public let references: [Reference]

    public init(cardID: UUID, directoryURL: URL, references: [Reference]) {
        self.cardID = cardID
        self.directoryURL = directoryURL
        self.references = references
    }
}

public struct ScenePackageExporter {
    private let database: ProjectDatabase
    private let containment: BundleContainment
    private let bundleURL: URL

    /// Internal: the exporter is reachable through the `ProjectSession+Export` doors —
    /// never constructed ad hoc by UI code.
    init(database: ProjectDatabase, bundleURL: URL) {
        self.database = database
        self.bundleURL = bundleURL.standardizedFileURL
        self.containment = BundleContainment(rootURL: bundleURL.standardizedFileURL)
    }

    // MARK: - Grains (§5.3)

    /// One scene. A stale single-scene export is permitted only through the §14.7 confirm,
    /// which names the stale reason; without it the refusal carries the reason so the
    /// confirm copy can quote it verbatim.
    public func exportScene(
        sceneID: UUID, confirmingStaleReason: String? = nil
    ) throws -> ScenePackageExport {
        try database.queue.read { db in
            let resolved = try Self.resolve(
                sceneID: sceneID, confirmingStaleReason: confirmingStaleReason, in: db
            )
            return try write(resolved)
        }
    }

    /// A sequence: every Generation Ready scene of the sequence, ordinal order — pure file
    /// work over the fresh set, no confirm needed (§14.7).
    public func exportSequence(sequenceID: UUID) throws -> [ScenePackageExport] {
        let sceneIDs = try database.queue.read { db -> [UUID] in
            try UUID.fetchAll(
                db,
                sql: """
                    SELECT id FROM scenes WHERE sequence_id = ? AND script_id =
                        (SELECT current_script_id FROM projects)
                    ORDER BY ordinal
                    """,
                arguments: [sequenceID.uuidString]
            )
        }
        return try database.queue.read { db in
            var exports: [ScenePackageExport] = []
            for sceneID in sceneIDs {
                guard let resolved = try Self.resolveIfGenerationReady(sceneID: sceneID, in: db)
                else { continue }
                exports.append(try write(resolved))
            }
            return exports
        }
    }

    /// All Generation Ready scenes under the active profile P, ordinal order.
    public func exportAllGenerationReady() throws -> [ScenePackageExport] {
        try database.queue.read { db in
            let graph = try ProjectRepository.readinessGraph(in: db)
            let readiness = ProjectRepository.deriveReadiness(graph)

            var exports: [ScenePackageExport] = []
            for row in readiness.scenes where !row.isExcluded {
                guard row.state == .assetReady else { continue }
                guard let resolved = try Self.resolveIfGenerationReady(
                    sceneID: row.sceneID, in: db
                ) else { continue }
                exports.append(try write(resolved))
            }
            return exports
        }
    }

    /// Materializes exactly one card's immutable citations for multi-file Finder drag.
    public func materializeCardReferences(cardID: UUID) throws -> ScenePromptCardMaterialization {
        let detail = try database.queue.read { db -> ScenePromptSetDetail.Card in
            guard let setID = try UUID.fetchOne(
                db, sql: "SELECT set_id FROM scene_prompt_cards WHERE id = ?",
                arguments: [cardID.uuidString]
            ), let row = try ProjectRepository.scenePromptSet(id: setID, in: db)
            else { throw ProjectStoreError.sceneOperationRefused(reason: "Prompt card not found.") }
            let set = try ProjectRepository.scenePromptSetDetail(row, staleReason: nil, in: db)
            guard let card = set.cards.first(where: { $0.card.id == cardID }) else {
                throw ProjectStoreError.sceneOperationRefused(reason: "Prompt card not found.")
            }
            return card
        }
        let leaf = "card-\(cardID.uuidString.lowercased())"
        let staging = try RelativeProjectPath("exports/handoffs/\(leaf).staging")
        let destination = try RelativeProjectPath("exports/handoffs/\(leaf)")
        _ = try? containment.removeDirectoryTree(at: staging)
        try containment.write(Data(), to: try RelativeProjectPath("\(staging.rawValue)/.build"))
        _ = try containment.removeIfPresent(at: try RelativeProjectPath("\(staging.rawValue)/.build"))
        do {
            var staged: [(Int, String)] = []
            for reference in detail.references {
                let data = try readContained(try RelativeProjectPath(reference.relativePath))
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest == reference.sha256 else {
                    throw ProjectStoreError.packageReferenceVerificationFailed(
                        path: reference.relativePath
                    )
                }
                let ext = (reference.relativePath as NSString).pathExtension.lowercased()
                let name = String(format: "%02d", reference.position)
                    + (ext.isEmpty ? "" : "." + ext)
                try writeBytes(data, to: try RelativeProjectPath("\(staging.rawValue)/\(name)"))
                staged.append((reference.position, name))
            }
            _ = try? containment.removeDirectoryTree(at: destination)
            try containment.renameEntry(at: staging, to: destination)
            let directoryURL = bundleURL.appending(path: destination.rawValue, directoryHint: .isDirectory)
            return ScenePromptCardMaterialization(
                cardID: cardID,
                directoryURL: directoryURL,
                references: staged.map { position, name in
                    let relative = "\(destination.rawValue)/\(name)"
                    return .init(
                        position: position,
                        relativePath: relative,
                        fileURL: bundleURL.appending(path: relative)
                    )
                }
            )
        } catch {
            _ = try? containment.removeDirectoryTree(at: staging)
            throw error
        }
    }

    // MARK: - Resolution (one read transaction per batch)

    /// Everything one package needs, resolved inside the caller's read transaction.
    struct Resolved {
        let sceneID: UUID
        let ordinal: Int
        let heading: String
        let synopsis: String
        let profile: TargetProfile
        let continuity: ContinuityContext
        let styleBible: String
        let promptSet: ScenePromptSetDetail
    }

    static func resolveIfGenerationReady(
        sceneID: UUID, in db: Database
    ) throws -> Resolved? {
        let graph = try ProjectRepository.readinessGraph(in: db)
        let readiness = ProjectRepository.deriveReadiness(graph)
        guard let readyRow = readiness.scenes.first(where: { $0.sceneID == sceneID }),
              !readyRow.isExcluded, readyRow.state == .assetReady
        else { return nil }
        let profileID = try ProjectRepository.activeProfileID(in: db)
        guard let current = try ProjectRepository.currentScenePromptSet(
            sceneID: sceneID, profileID: profileID, in: db
        ) else { return nil }
        // Fresh only (§14.7): batch grains loop the Generation Ready set, which excludes
        // stale prompts by predicate.
        guard try ProjectRepository.scenePromptSetStaleReason(current, in: db) == nil
        else { return nil }
        return try resolve(sceneID: sceneID, confirmingStaleReason: nil, in: db)
    }

    static func resolve(
        sceneID: UUID, confirmingStaleReason: String?, in db: Database
    ) throws -> Resolved {
        let graph = try ProjectRepository.readinessGraph(in: db)
        guard let scene = graph.scenes.first(where: { $0.id == sceneID }) else {
            throw ProjectStoreError.sceneNotFound
        }
        let readiness = ProjectRepository.deriveReadiness(graph)
        guard let readyRow = readiness.scenes.first(where: { $0.sceneID == sceneID }) else {
            throw ProjectStoreError.sceneNotFound
        }
        guard !readyRow.isExcluded else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "Excluded scenes are not prepared for generation."
            )
        }

        let profileID = try ProjectRepository.activeProfileID(in: db)
        guard let profile = TargetProfileCatalog.profile(id: profileID) else {
            throw ProjectStoreError.generationTargetProfileMissing(id: profileID)
        }

        guard let prompt = try ProjectRepository.currentScenePromptSet(
            sceneID: sceneID, profileID: profileID, in: db
        ) else {
            throw ProjectStoreError.scenePackageExportRequiresPrompt
        }

        // §14.7: staleness informs rather than blocks, but an export crosses the boundary —
        // the one gesture states the risk once, naming the reason.
        let staleReason = try ProjectRepository.scenePromptSetStaleReason(prompt, in: db)
        if let staleReason {
            guard confirmingStaleReason == Self.confirmReason(for: staleReason) else {
                throw ProjectStoreError.scenePackageStaleExportRequiresConfirm(
                    reason: Self.staleReasonText(staleReason)
                )
            }
        }

        // §5.5's enablement: within the profile limit, or the refusal names both numbers.
        let plan = try ProjectRepository.sceneReferencePlan(sceneID: sceneID, graph: graph, in: db)
        let satisfied = plan.count(where: \.isSatisfied)
        guard satisfied <= profile.imageReferenceLimit else {
            throw ProjectStoreError.sceneReferencesExceedProfileLimit(
                count: satisfied, limit: profile.imageReferenceLimit
            )
        }

        let continuity = try ProjectRepository.sceneContinuityContext(
            sceneID: sceneID, graph: graph, in: db
        )
        let styleBible = try String.fetchOne(db, sql: "SELECT style_bible FROM projects") ?? ""

        let detail = try ProjectRepository.scenePromptSetDetail(
            prompt, staleReason: staleReason, in: db
        )
        return Resolved(
            sceneID: sceneID,
            ordinal: scene.ordinal,
            heading: scene.heading,
            synopsis: scene.synopsis,
            profile: profile,
            continuity: continuity,
            styleBible: styleBible,
            promptSet: detail
        )
    }

    /// The exact token the caller must confirm with — the stale reason as the reads spell
    /// it, so the UI's confirm names what moved.
    static func confirmReason(for reason: ScenePromptStaleReason) -> String {
        switch reason {
        case .inputsChanged: "inputs changed"
        case .olderInputFormat: "older input format"
        }
    }

    static func staleReasonText(_ reason: ScenePromptStaleReason) -> String {
        switch reason {
        case .inputsChanged: "inputs changed"
        case .olderInputFormat: "older input format"
        }
    }

    // MARK: - The staged, verified, atomic write

    /// Three-digit ordinal directory names, stable across renames (§4.1).
    static func packageName(_ ordinal: Int) -> String {
        String(format: "scene-%03d", ordinal)
    }

    private func write(_ resolved: Resolved) throws -> ScenePackageExport {
        let name = Self.packageName(resolved.ordinal)
        let stagingPath = try RelativeProjectPath("exports/scenes/\(name).staging")
        let destinationPath = try RelativeProjectPath("exports/scenes/\(name)")

        // The staging convention: removed on entry if a prior attempt left one, never
        // enumerated as a package. (The marker write is what materializes the directory
        // through the containment walk; it is removed again immediately.)
        _ = try? containment.removeDirectoryTree(at: stagingPath)
        try containment.write(Data(), to: try RelativeProjectPath("\(stagingPath.rawValue)/.build"))
        _ = try containment.removeIfPresent(at: try RelativeProjectPath("\(stagingPath.rawValue)/.build"))

        do {
            var files: [RelativeProjectPath] = []
            var bytes: Int64 = 0

            for cardDetail in resolved.promptSet.cards {
                let card = cardDetail.card
                let titleSlug = AssetPathing.slug(card.title).isEmpty
                    ? "prompt" : AssetPathing.slug(card.title)
                let cardName = String(format: "card-%03d", card.order) + "-" + titleSlug
                let cardRoot = "\(stagingPath.rawValue)/\(cardName)"

                let promptPath = try RelativeProjectPath("\(cardRoot)/prompt.md")
                try writeBytes(Data(card.body.utf8), to: promptPath)
                files.append(promptPath)
                bytes += Int64(card.body.utf8.count)

                var manifestReferences: [ScenePackageManifest.Reference] = []
                var usedNames: Set<String> = []
                for reference in cardDetail.references {
                    let sourcePath = try RelativeProjectPath(reference.relativePath)
                    let data = try readContained(sourcePath)
                    let actualDigest = SHA256.hash(data: data)
                        .map { String(format: "%02x", $0) }.joined()
                    guard actualDigest == reference.sha256 else {
                        throw ProjectStoreError.packageReferenceVerificationFailed(
                            path: reference.relativePath
                        )
                    }
                    let slug = AssetPathing.slug(reference.displayName)
                    let ext = (reference.relativePath as NSString).pathExtension.lowercased()
                    var filename = String(format: "%02d", reference.position) + "-" + slug
                        + (ext.isEmpty ? "" : "." + ext)
                    var index = 2
                    while usedNames.contains(filename) {
                        filename = String(format: "%02d", reference.position)
                            + "-" + slug + "-\(index)" + (ext.isEmpty ? "" : "." + ext)
                        index += 1
                    }
                    usedNames.insert(filename)
                    let referencePath = try RelativeProjectPath(
                        "\(cardRoot)/references/\(filename)"
                    )
                    try writeBytes(data, to: referencePath)
                    files.append(referencePath)
                    bytes += Int64(data.count)
                    manifestReferences.append(ScenePackageManifest.Reference(
                        position: reference.position,
                        class: reference.class.rawValue,
                        name: reference.displayName,
                        role: reference.role,
                        exclusion: reference.exclusion,
                        fidelity: reference.fidelity.rawValue,
                        filename: "references/\(filename)",
                        sha256: actualDigest,
                        pixelWidth: reference.pixelWidth ?? 0,
                        pixelHeight: reference.pixelHeight ?? 0
                    ))
                }

                let manifest = ScenePackageManifest(
                    sceneOrdinal: resolved.ordinal,
                    sceneHeading: resolved.heading,
                    sceneSynopsis: resolved.synopsis,
                    targetProfileID: resolved.profile.id,
                    durationSeconds: card.durationSeconds,
                    aspectRatio: card.aspectRatio,
                    resolution: card.resolution,
                    references: manifestReferences,
                    continuity: resolved.continuity.entries.map {
                        ScenePackageManifest.ContinuityEntry(
                            entity: $0.entityName, category: $0.category.rawValue,
                            description: $0.description
                        )
                    },
                    styleBible: resolved.styleBible,
                    setNumber: resolved.promptSet.set.setNumber,
                    cardNumber: card.order,
                    cardTitle: card.title,
                    inputDigest: resolved.promptSet.set.inputDigest,
                    promptSource: resolved.promptSet.set.provenance.source.rawValue,
                    skillID: resolved.promptSet.set.skillID
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let jsonData = try encoder.encode(manifest)
                let jsonPath = try RelativeProjectPath("\(cardRoot)/scene.json")
                try writeBytes(jsonData, to: jsonPath)
                files.append(jsonPath)
                bytes += Int64(jsonData.count)
            }

            // Only a fully verified staging directory replaces the destination. The old
            // export steps aside first and comes back if anything fails, so the
            // destination path never holds a partial package and a failure leaves the
            // previous valid export byte-identical.
            let trashPath = try RelativeProjectPath(
                "exports/scenes/.\(name).trash-\(UUID().uuidString)"
            )
            var movedAside = false
            if try containment.entryKind(at: destinationPath) != .missing {
                try containment.renameEntry(at: destinationPath, to: trashPath)
                movedAside = true
            }
            do {
                try containment.renameEntry(at: stagingPath, to: destinationPath)
            } catch {
                if movedAside {
                    try? containment.renameEntry(at: trashPath, to: destinationPath)
                }
                throw error
            }
            if movedAside {
                _ = try? containment.removeDirectoryTree(at: trashPath)
            }

            // Report destination-relative paths — the staging name never escapes.
            let prefix = destinationPath.rawValue
            return ScenePackageExport(
                sceneID: resolved.sceneID,
                relativeDirectory: prefix,
                files: files.map { path in
                    prefix + path.rawValue.dropFirst(stagingPath.rawValue.count)
                }.sorted(),
                byteCount: bytes
            )
        } catch {
            // A refused or failed export writes nothing at the destination; the staging
            // residue is cleaned up by hand, descriptor-relative.
            _ = try? containment.removeDirectoryTree(at: stagingPath)
            throw error
        }
    }

    // MARK: - Contained byte plumbing

    private func writeBytes(_ data: Data, to path: RelativeProjectPath) throws {
        try containment.write(data, to: path)
    }

    /// Reads one bundle file through the containment's no-follow descriptor.
    private func readContained(_ path: RelativeProjectPath) throws -> Data {
        try containment.withReadDescriptor(at: path) { descriptor in
            var data = Data()
            let bufferSize = 1 << 16
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while true {
                let count = Darwin.read(descriptor, buffer, bufferSize)
                if count < 0 {
                    throw ProjectStoreError.mediaFileDamaged(
                        path: path.rawValue, reason: "unreadable (error \(errno))"
                    )
                }
                if count == 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }
}

extension ProjectRepository {
    /// The persisted active profile id, defaulting like every other reader (§3.5).
    static func activeProfileID(in db: Database) throws -> String {
        try String.fetchOne(db, sql: "SELECT generation_target_profile FROM projects")
            ?? TargetProfileCatalog.defaultProfileID
    }
}
