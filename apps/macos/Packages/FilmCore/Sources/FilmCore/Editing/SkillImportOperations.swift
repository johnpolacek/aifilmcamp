import CryptoKit
import Foundation
import GRDB

// PHASE5_DESIGN §14.6's skill-import operations (Plan 019 contract B), in the house
// shape: `MutationEffect`-returning statics that open no transaction.
//
// The undo posture is the **media-import posture verbatim** (§7.1): the tree is copied
// and verified before the row lands; undo removes the row (and any selection) and leaves
// the copied tree as an orphan — file bytes are never journal payload; redo re-verifies
// the retained tree against `tree_sha256` and refuses via `.importedSkillTreeMissing` if
// it is gone or altered, never trusting a stale copy. Orphaned trees join the typed
// maintenance sweep beside Clear Orphaned Media (`orphanedSkillTrees()` /
// `clearOrphanedSkillTrees(confirming:)`, `ProjectSession+Skills.swift`).
//
// Every stored path is bundle- or descriptor-relative — no absolute path is ever
// persisted, so the bundle moves and the selection survives (§4.3).

enum SkillImportOperations {

    // MARK: - Tree verification (the FilmCore gate's shared half)

    /// Re-walks the imported tree under the bundle's `skills/` root and compares its
    /// digest against the row's stored value — `.importedSkillTreeMissing` when gone or
    /// altered. One validation authority with `SkillTreeOperations`; the run gate calls
    /// this for early feedback and Plan 021's materialiser boundary is the authority.
    static func verifyTree(
        relativeRoot: String, expectedTreeSHA256: String, media: BundleContainment
    ) throws {
        let root = media.rootURL.appending(path: relativeRoot)
        let manifest: SkillTreeOperations.TreeManifest
        do {
            manifest = try SkillTreeOperations.manifest(of: root)
        } catch {
            // An unreadable walk is a missing-or-hostile tree either way.
            throw ProjectStoreError.importedSkillTreeMissing
        }
        guard manifest.treeDigest() == expectedTreeSHA256 else {
            throw ProjectStoreError.importedSkillTreeMissing
        }
    }

    // MARK: - importSceneSkill / removeImportedSkill (§14.6)

    @discardableResult
    static func importSceneSkill(
        id: UUID,
        relativeRoot: String,
        displayName: String,
        entryRelativePath: String,
        routingRelativePath: String,
        treeSHA256: String,
        restoring: [RowSnapshot],
        actor: MutationActor,
        mode: MutationMode = .apply,
        media: BundleContainment,
        in db: Database
    ) throws -> MutationEffect {
        // Verify first — nothing is written before the retained tree matches its digest,
        // which is why a redo whose orphaned file Clear Orphaned Skill Trees swept
        // refuses cleanly (the pinned import walk's posture).
        try verifyTree(relativeRoot: relativeRoot, expectedTreeSHA256: treeSHA256, media: media)

        if !restoring.isEmpty {
            // Redo: byte-identical through the snapshots once verified.
            try RowGraph.restore(restoring, in: db)
            return MutationEffect(
                inverse: .removeImportedSkill(payload: ImportedSkillPayload(
                    skillRow: restoring.first { $0.table == "imported_skills" }
                        ?? RowSnapshot(table: "imported_skills", columns: [:])
                )),
                affected: [SubjectRef(kind: .script, id: id)],
                snapshots: []
            )
        }

        let projectID = try ProjectRepository.requireProjectID(in: db)
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO imported_skills (
                    id, project_id, display_name, relative_root, entry_relative_path,
                    routing_relative_path, tree_sha256, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString, projectID.uuidString, displayName, relativeRoot,
                entryRelativePath, routingRelativePath, treeSHA256, timestamp,
            ]
        )
        guard let inserted = try RowSnapshotStore.capture(
            table: "imported_skills", id: id, in: db
        ) else {
            throw ProjectStoreError.invalidBundle
        }
        return MutationEffect(
            inverse: .removeImportedSkill(payload: ImportedSkillPayload(skillRow: inserted)),
            affected: [SubjectRef(kind: .script, id: id)],
            snapshots: []
        )
    }

    /// The inverse arm: the row out, the tree stays an orphan. Redo restores byte-identically.
    static func removeImportedSkill(
        payload: ImportedSkillPayload, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        if case .inverting = mode {
            guard case let .string(raw)? = payload.skillRow.columns["id"],
                  let id = UUID(uuidString: raw)
            else { throw ProjectStoreError.invalidBundle }
            // The selection is already back to its prior value — this group child runs
            // after `selectSceneSkill`'s inverse in the batch order — so the row can go.
            try RowSnapshotStore.delete(table: "imported_skills", id: id, in: db)
        } else {
            // Redo: restore exactly what was inserted (the caller verified the tree).
            try RowGraph.restore(payload.snapshots, in: db)
        }
        var affected: Set<SubjectRef> = []
        if case let .string(raw)? = payload.skillRow.columns["id"],
           let id = UUID(uuidString: raw) {
            affected.insert(SubjectRef(kind: .script, id: id))
        }
        let restored = Self.string(payload.skillRow, "id").flatMap(UUID.init(uuidString:))
        return MutationEffect(
            inverse: .importSceneSkill(
                id: restored ?? UUID(),
                relativeRoot: Self.string(payload.skillRow, "relative_root") ?? "",
                displayName: Self.string(payload.skillRow, "display_name") ?? "",
                entryRelativePath: Self.string(payload.skillRow, "entry_relative_path") ?? "",
                routingRelativePath: Self.string(payload.skillRow, "routing_relative_path") ?? "",
                treeSHA256: Self.string(payload.skillRow, "tree_sha256") ?? "",
                restoring: payload.snapshots
            ),
            affected: affected,
            snapshots: mode.isInverting ? [] : []
        )
    }

    // MARK: - selectSceneSkill (§14.6)

    static func selectSceneSkill(
        skillID: UUID?, actor: MutationActor, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        try RequirementOperations.requireHuman(actor, subject: SubjectRef(kind: .script, id: UUID()))
        let projectID = try ProjectRepository.requireProjectID(in: db)
        var collector = SnapshotCollector()
        try collector.capture(table: "projects", id: projectID, in: db)
        let priorRaw = try String.fetchOne(
            db, sql: "SELECT scene_skill_id FROM projects WHERE id = ?",
            arguments: [projectID.uuidString]
        )
        let prior = priorRaw.flatMap(UUID.init(uuidString:))

        if let entry = mode.invertedEntry {
            // Undo/redo restores the projects row byte-identically — updated_at included.
            guard let current = try RowSnapshotStore.capture(
                table: "projects", id: projectID, in: db
            ) else {
                throw ProjectStoreError.missingProject
            }
            try RowGraph.restore(entry.snapshots.filter { $0.table == "projects" }, in: db)
            return MutationEffect(
                inverse: .selectSceneSkill(skillID: current.columns["scene_skill_id"]
                    .flatMap { if case let .string(raw) = $0 { UUID(uuidString: raw) } else { nil } }),
                affected: [SubjectRef(kind: .script, id: projectID)],
                snapshots: [current]
            )
        }

        try db.execute(
            sql: """
                UPDATE projects SET scene_skill_id = ?, updated_at = ? WHERE id = ?
                """,
            arguments: [skillID?.uuidString, UTCDate.string(from: Date()), projectID.uuidString]
        )
        // Stales nothing (§6.2): the skill payload is outside the §8.2 digest.
        return MutationEffect(
            inverse: .selectSceneSkill(skillID: prior),
            affected: [SubjectRef(kind: .script, id: projectID)],
            snapshots: collector.snapshots
        )
    }

    private static func string(_ snapshot: RowSnapshot, _ column: String) -> String? {
        if case let .string(value)? = snapshot.columns[column] { return value }
        return nil
    }
}

extension MutationMode {
    var isInverting: Bool {
        if case .inverting = self { return true }
        return false
    }
}
