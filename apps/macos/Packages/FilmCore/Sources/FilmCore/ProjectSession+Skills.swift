import Darwin
import Foundation
import GRDB

/// PHASE5_DESIGN §14.6's skill-import doors and the typed orphan surface (Plan 019
/// contract B), on `ProjectSession`.
///
/// * **Import.** The media-import discipline at tree scale: the source is walked once
///   through `SkillTreeOperations` (safe relative paths, symlink refusal), copied into
///   `skills/<skill id>/`, re-walked, and verified against the computed digest **before**
///   any row lands; then one transaction journals import + auto-select as one grouped
///   entry (the shipped `batch` op) — one ⌘Z step. A throw removes the staged tree.
/// * **Orphaned trees.** Listed by `orphanedSkillTrees()` with per-tree byte counts,
///   deleted after the caller confirms, serialized through this actor, touching no rows
///   and journaling nothing — the Clear Orphaned Media pattern's shape at tree scale.
///   Recursive directory deletion happens nowhere outside this operation's containment
///   checks.
public extension ProjectSession {

    // MARK: - Import (§14.6)

    /// Imports a custom skill tree into the bundle and selects it for the project.
    ///
    /// The entry and routing paths are descriptor-relative and must exist in the walked
    /// tree; refusals name the problem rather than sanitising (the materialiser's rule).
    @discardableResult
    func importSceneSkill(
        from sourceURL: URL,
        displayName: String? = nil,
        entryRelativePath: String,
        routingRelativePath: String = "",
        actor: MutationActor = .human
    ) throws -> ImportedSkill {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let containment = BundleContainment(rootURL: layout.rootURL)

        // Walk the source once: safe paths, no symlinks, every file hashed.
        let manifest = try SkillTreeOperations.manifest(of: sourceURL)
        guard manifest.sha256[entryRelativePath] != nil else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "The skill has no file at \"\(entryRelativePath)\"."
            )
        }
        if !routingRelativePath.isEmpty {
            guard manifest.sha256[routingRelativePath] != nil else {
                throw ProjectStoreError.sceneOperationRefused(
                    reason: "The skill has no routing file at \"\(routingRelativePath)\"."
                )
            }
        }

        let skillID = UUID()
        let relativeRoot = "skills/\(skillID.uuidString)"
        let treeSHA256 = manifest.treeDigest()

        // Copy whole, then verify the copy against the computed digest before the row
        // lands — a copy bug refuses here instead of shipping bytes that disagree with
        // their manifest. The containment boundary is the new subtree root, which must
        // exist before the first descriptor-relative write.
        let destinationRoot = layout.rootURL.appending(path: relativeRoot)
        try FileManager.default.createDirectory(
            at: destinationRoot, withIntermediateDirectories: true
        )
        try SkillTreeOperations.copyTree(manifest, from: sourceURL, to: destinationRoot)
        do {
            let copied = try SkillTreeOperations.manifest(of: destinationRoot)
            guard copied.treeDigest() == treeSHA256 else {
                throw ProjectStoreError.sceneOperationRefused(
                    reason: "The copied skill files do not match their manifest."
                )
            }
        } catch {
            _ = try? Self.removeTree(relativeRoot: relativeRoot, in: containment)
            throw error
        }

        do {
            let imported = try database.queue.write { db -> ImportedSkill in
                let children: [EditOperation] = [
                    .importSceneSkill(
                        id: skillID, relativeRoot: relativeRoot,
                        displayName: displayName ?? sourceURL.lastPathComponent,
                        entryRelativePath: entryRelativePath,
                        routingRelativePath: routingRelativePath,
                        treeSHA256: treeSHA256, restoring: []
                    ),
                    .selectSceneSkill(skillID: skillID),
                ]
                _ = try EditPrimitives.performGroup(
                    children, as: .batch(children), actor: actor, jobID: actor.jobID,
                    media: containment, in: db
                )
                guard let imported = try Self.importedSkill(id: skillID, in: db) else {
                    throw ProjectStoreError.invalidBundle
                }
                return imported
            }
            return imported
        } catch {
            _ = try? Self.removeTree(relativeRoot: relativeRoot, in: containment)
            throw error
        }
    }

    /// §14.6's selection flip; `nil` restores the bundled default. Stales nothing.
    @discardableResult
    func selectSceneSkill(skillID: UUID?, actor: MutationActor = .human) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .selectSceneSkill(skillID: skillID), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// The selected custom skill, when one is.
    func selectedSkill() throws -> ImportedSkill? {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.read { db in
            guard let idRaw = try String.fetchOne(
                db, sql: "SELECT scene_skill_id FROM projects"
            ), let id = UUID(uuidString: idRaw) else { return nil }
            return try Self.importedSkill(id: id, in: db)
        }
    }

    /// Every imported skill, creation order.
    func importedSkills() throws -> [ImportedSkill] {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM imported_skills ORDER BY created_at, id")
                .map(Self.decodeImportedSkill)
        }
    }

    // MARK: - The FilmCore run gate (early feedback)

    /// Re-verifies the selected skill's retained tree against its stored `tree_sha256`.
    /// Early feedback only — Plan 021's coordinator passes the stored digest into the
    /// materialiser, whose staging walk is the authoritative comparison (§8.6). The
    /// bundled default carries no row and is exempt.
    func verifySelectedSkillTree() throws {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let containment = BundleContainment(rootURL: layout.rootURL)
        return try database.queue.read { db in
            guard let idRaw = try String.fetchOne(
                db, sql: "SELECT scene_skill_id FROM projects"
            ), let id = UUID(uuidString: idRaw),
               let skill = try Self.importedSkill(id: id, in: db)
            else { return }
            try SkillImportOperations.verifyTree(
                relativeRoot: skill.relativeRoot,
                expectedTreeSHA256: skill.treeSHA256,
                media: containment
            )
        }
    }

    // MARK: - Orphaned skill trees (the typed, confirmed sweep)

    /// One unreferenced `skills/` subtree, with the figures the confirm names before
    /// clearing.
    struct OrphanedSkillTree: Equatable, Sendable {
        public let relativeRoot: String
        public let fileCount: Int
        public let byteCount: Int64
    }

    /// Walks `skills/` and lists the subtrees no `imported_skills` row references — the
    /// shipped orphaned-media walk's shape at tree scale: path-based enumerator, hidden
    /// files skipped, symlinks never followed and never reported. Sorted by root.
    func orphanedSkillTrees() throws -> [OrphanedSkillTree] {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let referenced = try database.queue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT relative_root FROM imported_skills"))
        }
        let skillsRoot = layout.rootURL.appending(path: "skills", directoryHint: .isDirectory)
        var trees: [OrphanedSkillTree] = []
        let names = (try? FileManager.default.contentsOfDirectory(atPath: skillsRoot.path))?
            .sorted() ?? []
        let fileManager = FileManager.default
        for name in names where !name.hasPrefix(".") {
            let root = skillsRoot.appending(path: name)
            let attributes = (try? fileManager.attributesOfItem(atPath: root.path)) ?? [:]
            guard (attributes[.type] as? FileAttributeType) == .typeDirectory else { continue }
            let relativeRoot = "skills/\(name)"
            guard !referenced.contains(relativeRoot) else { continue }
            var files = 0
            var bytes: Int64 = 0
            if let walker = fileManager.enumerator(atPath: root.path) {
                while let subpath = walker.nextObject() as? String {
                    let full = root.appending(path: subpath).path
                    let item = (try? fileManager.attributesOfItem(atPath: full)) ?? [:]
                    guard (item[.type] as? FileAttributeType) == .typeRegular else { continue }
                    files += 1
                    bytes += Int64((item[.size] as? NSNumber)?.int64Value ?? 0)
                }
            }
            trees.append(
                OrphanedSkillTree(
                    relativeRoot: relativeRoot, fileCount: files, byteCount: bytes
                )
            )
        }
        return trees
    }

    /// Deletes the orphaned trees the caller confirmed. Every root is re-checked against
    /// the rows inside this call — a tree that stopped being an orphan between listing
    /// and confirmation is left alone — and anything outside `skills/` (or deeper than
    /// one component under it) is refused outright. Touches no rows, journals nothing;
    /// non-invertible by construction.
    @discardableResult
    func clearOrphanedSkillTrees(confirming roots: [String]) throws -> ClearedCacheSummary {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let referenced = try database.queue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT relative_root FROM imported_skills"))
        }
        let containment = BundleContainment(rootURL: layout.rootURL)
        var bytes: Int64 = 0
        var removed = 0
        for root in roots {
            // Containment first: exactly `skills/<one component>`, referenced by no row.
            let components = root.split(separator: "/").map(String.init)
            guard components.count == 2, components[0] == "skills",
                  !components[1].isEmpty, !components[1].hasPrefix(".")
            else { continue }
            guard !referenced.contains(root) else { continue }
            let size = try Self.removeTree(relativeRoot: root, in: containment)
            if size >= 0 {
                bytes += UInt64(size) <= UInt64(Int64.max) ? Int64(size) : Int64.max
                removed += 1
            }
        }
        return ClearedCacheSummary(bytesFreed: bytes, filesRemoved: removed)
    }
}

// MARK: - Internals

private extension ProjectSession {
    var layout: ProjectBundleLayout { ProjectBundleLayout(rootURL: bundleURL) }

    static func importedSkill(id: UUID, in db: Database) throws -> ImportedSkill? {
        try Row.fetchOne(
            db, sql: "SELECT * FROM imported_skills WHERE id = ?", arguments: [id.uuidString]
        ).map(decodeImportedSkill)
    }

    static func decodeImportedSkill(_ row: Row) -> ImportedSkill {
        ImportedSkill(
            id: (try? UUID.required(row["id"])) ?? UUID(),
            projectID: (try? UUID.required(row["project_id"])) ?? UUID(),
            displayName: row["display_name"] ?? "",
            relativeRoot: row["relative_root"] ?? "",
            entryRelativePath: row["entry_relative_path"] ?? "",
            routingRelativePath: row["routing_relative_path"] ?? "",
            treeSHA256: row["tree_sha256"] ?? "",
            createdAt: (try? UTCDate.date(from: row["created_at"] ?? "")) ?? Date(timeIntervalSince1970: 0)
        )
    }

    /// Removes one `skills/<name>` tree through the containment's leaf-wise walk.
    /// Returns the bytes freed, or `-1` when the root was already gone.
    static func removeTree(
        relativeRoot: String, in containment: BundleContainment
    ) throws -> Int64 {
        try containment.removeDirectoryTree(at: RelativeProjectPath(relativeRoot))
    }
}

