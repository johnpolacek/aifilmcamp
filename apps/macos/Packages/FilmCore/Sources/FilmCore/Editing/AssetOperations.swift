import Foundation
import GRDB

/// The asset and version half of PHASE2_DESIGN §7.3's operation table.
///
/// Shaped exactly like `RequirementOperations`: `MutationEffect`-returning static funcs plus
/// `precheck*` helpers, and **no transaction opened** — the reentrancy test globs
/// `Editing/*.swift`, so this file is covered automatically (§7.1).
///
/// Two rules run through every function here and are stated once:
///
/// * **`AssetStatusRecompute` is the only writer of `assets.status`** (§6.3). No operation
///   below assigns a status; each one changes the facts the five rules read — a version row,
///   a version's own verdict, `rejected_explicitly` — and then asks for the recompute.
/// * **Rows first, files second** (§4.1). `deleteVersion` and `deleteAsset` remove rows
///   inside the transaction and report their paths through `MutationEffect.removedMediaPaths`
///   so the session wrapper unlinks them **after commit**. Nothing here touches the
///   filesystem, with one exception: `importAssetVersion` *reads* the staged file to verify
///   it still exists and still hashes to what the row claims (§7.3's pinned redo walk).
enum AssetOperations {

    // MARK: - Row access

    /// The columns an asset operation needs.
    struct AssetRow {
        let id: UUID
        let projectID: UUID
        let requirementID: UUID
        let status: AssetStatus
        let rejectedExplicitly: Bool
        let notes: String

        var ref: SubjectRef { SubjectRef(kind: .asset, id: id) }
    }

    /// The columns a version operation needs.
    struct VersionRow {
        let id: UUID
        let assetID: UUID
        let versionNumber: Int
        let status: AssetVersionStatus
        let relativePath: RelativeProjectPath
        let sha256: String
        let byteCount: Int
        let originalFileName: String
        let mediaKind: MediaKind
        let pixelWidth: Int?
        let pixelHeight: Int?
        let notes: String
        /// §7.3's lineage stamp, when the import carried one.
        var promptID: UUID?

        var ref: SubjectRef { SubjectRef(kind: .version, id: id) }
    }

    static func fetchAsset(id: UUID, in db: Database) throws -> AssetRow? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM assets WHERE id = ?", arguments: [id.uuidString]
        ) else { return nil }
        return try decodeAsset(row)
    }

    static func requireAsset(id: UUID, in db: Database) throws -> AssetRow {
        guard let asset = try fetchAsset(id: id, in: db) else {
            throw ProjectStoreError.assetNotFound
        }
        return asset
    }

    static func asset(ofRequirement requirementID: UUID, in db: Database) throws -> AssetRow? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM assets WHERE requirement_id = ?",
            arguments: [requirementID.uuidString]
        ) else { return nil }
        return try decodeAsset(row)
    }

    static func decodeAsset(_ row: Row) throws -> AssetRow {
        guard let status = AssetStatus(rawValue: row["status"]) else {
            throw ProjectStoreError.invalidBundle
        }
        return AssetRow(
            id: try UUID.required(row["id"]),
            projectID: try UUID.required(row["project_id"]),
            requirementID: try UUID.required(row["requirement_id"]),
            status: status,
            rejectedExplicitly: (row["rejected_explicitly"] as Int) != 0,
            notes: row["notes"]
        )
    }

    static func fetchVersion(id: UUID, in db: Database) throws -> VersionRow? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM asset_versions WHERE id = ?", arguments: [id.uuidString]
        ) else { return nil }
        return try decodeVersion(row)
    }

    static func requireVersion(id: UUID, in db: Database) throws -> VersionRow {
        guard let version = try fetchVersion(id: id, in: db) else {
            throw ProjectStoreError.assetVersionNotFound
        }
        return version
    }

    static func decodeVersion(_ row: Row) throws -> VersionRow {
        guard let status = AssetVersionStatus(rawValue: row["status"]),
              let mediaKind = MediaKind(rawValue: row["media_kind"])
        else { throw ProjectStoreError.invalidBundle }
        return VersionRow(
            id: try UUID.required(row["id"]),
            assetID: try UUID.required(row["asset_id"]),
            versionNumber: row["version_number"],
            status: status,
            relativePath: try RelativeProjectPath(row["relative_path"]),
            sha256: row["sha256"],
            byteCount: row["byte_count"],
            originalFileName: row["original_file_name"],
            mediaKind: mediaKind,
            pixelWidth: row["pixel_width"],
            pixelHeight: row["pixel_height"],
            notes: row["notes"],
            promptID: (row["prompt_id"] as String?).flatMap(UUID.init(uuidString:))
        )
    }

    /// The lineage stamp a version carries, read fresh for the inverse's payload.
    static func stampedPromptID(versionID: UUID, in db: Database) -> UUID? {
        (try? String.fetchOne(
            db, sql: "SELECT prompt_id FROM asset_versions WHERE id = ?",
            arguments: [versionID.uuidString]
        ) ?? nil).flatMap(UUID.init(uuidString:))
    }

    /// §4.1: one greater than the asset's current maximum. Deleted versions leave gaps and
    /// numbers are never reused while a higher one stands, so this is `MAX + 1` and never a
    /// count.
    static func nextVersionNumber(assetID: UUID, in db: Database) throws -> Int {
        let maximum = try Int.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(version_number), 0) FROM asset_versions WHERE asset_id = ?",
            arguments: [assetID.uuidString]
        ) ?? 0
        return maximum + 1
    }

    static func versionCount(assetID: UUID, in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM asset_versions WHERE asset_id = ?",
            arguments: [assetID.uuidString]
        ) ?? 0
    }

    static func hasApprovedVersion(assetID: UUID, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM asset_versions WHERE asset_id = ? AND status = 'approved'
                )
                """,
            arguments: [assetID.uuidString]
        ) ?? false
    }

    // MARK: - The recompute, reached from an asset row

    /// §6.3's recompute for one asset, looked up through its requirement.
    ///
    /// `AssetStatusRecompute` is **not** redefined here (Plan 010's maintenance note): this
    /// only supplies the two requirement facts rule 1 needs and calls the one function.
    @discardableResult
    static func recompute(
        assetID: UUID,
        in db: Database
    ) throws -> AssetStatusRecompute.Applied {
        let asset = try requireAsset(id: assetID, in: db)
        return try recompute(requirementID: asset.requirementID, in: db)
    }

    @discardableResult
    static func recompute(
        requirementID: UUID,
        in db: Database
    ) throws -> AssetStatusRecompute.Applied {
        let requirement = try RequirementOperations.require(id: requirementID, in: db)
        return try AssetStatusRecompute.recompute(
            requirementID: requirementID,
            reviewState: requirement.reviewState,
            necessity: requirement.necessity,
            in: db
        )
    }

    // MARK: - §6.4's active predicate over a stored requirement

    /// §6.4's `active(requirement)`, over the rows rather than over already-fetched domain
    /// values — the guard `createAsset` and `importAssetVersion` share.
    ///
    /// `ManifestQualification.isActive` is the **only** implementation of the predicate; this
    /// loads its four facts and asks it.
    static func isActive(requirementID: UUID, in db: Database) throws -> Bool {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT r.review_state AS r_state, r.necessity AS r_necessity,
                       e.review_state AS e_state, e.is_relevant AS e_relevant
                FROM asset_requirements r
                JOIN entities e ON e.id = r.entity_id
                WHERE r.id = ?
                """,
            arguments: [requirementID.uuidString]
        ) else { throw ProjectStoreError.requirementNotFound }
        guard let reviewState = ReviewState(rawValue: row["r_state"]),
              let necessity = RequirementNecessity(rawValue: row["r_necessity"]),
              let entityReviewState = ReviewState(rawValue: row["e_state"])
        else { throw ProjectStoreError.invalidBundle }
        return ManifestQualification.isActive(
            ManifestQualification.RequirementFacts(
                reviewState: reviewState,
                necessity: necessity,
                entityReviewState: entityReviewState,
                entityIsRelevant: (row["e_relevant"] as Int) != 0
            )
        )
    }

    private static func requireActive(requirementID: UUID, in db: Database) throws {
        guard try isActive(requirementID: requirementID, in: db) else {
            throw ProjectStoreError.requirementInactive(requirementID: requirementID)
        }
    }
}

// MARK: - createAsset / removeAssetRow (§7.3)

extension AssetOperations {
    /// §7.3's `createAsset`. The id travels in the operation so a redo restores the row this
    /// call first made; `restoring` makes the redo byte-identical.
    static func createAsset(
        id: UUID,
        requirementID: UUID,
        restoring: [RowSnapshot],
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        if !restoring.isEmpty {
            // The inverse-of-the-inverse path: the row comes back exactly as it was, its
            // `status` included — which agrees with §6.3 by construction, because the
            // status it carries is the one the recompute wrote.
            try RowGraph.restore(restoring, in: db)
            return MutationEffect(
                inverse: .removeAssetRow(assetID: id),
                affected: [SubjectRef(kind: .asset, id: id)],
                snapshots: []
            )
        }

        let requirement = try RequirementOperations.require(id: requirementID, in: db)
        try RequirementOperations.requireHuman(actor, subject: requirement.ref)
        try requireActive(requirementID: requirementID, in: db)
        guard try asset(ofRequirement: requirementID, in: db) == nil else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "That requirement already has an asset."
            )
        }

        let timestamp = UTCDate.string(from: Date())
        var arguments: StatementArguments = [
            id.uuidString, requirement.projectID.uuidString, requirementID.uuidString,
            // A fresh slot has no versions, so §6.3 rule 5 is the only reachable answer;
            // the recompute below writes it rather than this insert trusting itself.
            AssetStatus.needed.rawValue,
        ]
        arguments += RequirementOperations.insertProvenance(actor, timestamp: timestamp)
        try db.execute(
            sql: """
                INSERT INTO assets (
                    id, project_id, requirement_id, status, is_stale, stale_since,
                    stale_reason, rejected_explicitly, notes,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, 0, NULL, NULL, 0, '', ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: arguments
        )
        let applied = try recompute(requirementID: requirementID, in: db)
        return MutationEffect(
            inverse: .removeAssetRow(assetID: id),
            affected: Set([SubjectRef(kind: .asset, id: id)]).union(applied.affected),
            snapshots: []
        )
    }

    /// `createAsset`'s inverse: **rows only, never files** (§4.1). Version rows go with it
    /// through the schema's `ON DELETE CASCADE`, which is why the capture is a graph.
    static func removeAssetRow(assetID: UUID, in db: Database) throws -> MutationEffect {
        let asset = try requireAsset(id: assetID, in: db)
        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: assetID, in: db)
        collector.add(contentsOf: try RowSnapshotStore.captureAll(
            table: "asset_versions", where: "asset_id = ?", arguments: [assetID.uuidString], in: db
        ))
        try db.execute(sql: "DELETE FROM assets WHERE id = ?", arguments: [assetID.uuidString])
        return MutationEffect(
            inverse: .createAsset(
                id: assetID, requirementID: asset.requirementID, restoring: collector.snapshots
            ),
            affected: [asset.ref],
            snapshots: collector.snapshots
        )
    }
}

// MARK: - importAssetVersion / removeVersionRow (§7.3, §4.1)

extension AssetOperations {
    /// The journaled half of media import.
    ///
    /// The order matters and is contract:
    ///
    /// 1. **Verify the file** — it exists under the bundle, opened no-follow, and still
    ///    hashes to `sha256` (§7.3's pinned walk: a redo after Clear Orphaned Media removed
    ///    the file refuses, naming it). Nothing is written before this passes.
    /// 2. Refuse while the requirement is inactive (§6.3: media cannot resurrect a
    ///    deprecated slot).
    /// 3. Snapshot the asset row, clear a standing `rejected_explicitly`, insert the version.
    /// 4. Recompute (§6.3 rules 2–5).
    static func importAssetVersion(
        versionID: UUID,
        assetID: UUID,
        versionNumber: Int,
        relativePath: RelativeProjectPath,
        sha256: String,
        byteCount: Int,
        originalFileName: String,
        mediaKind: MediaKind,
        pixelWidth: Int?,
        pixelHeight: Int?,
        promptID: UUID?,
        restoring: [RowSnapshot],
        actor: MutationActor,
        media: BundleContainment,
        in db: Database
    ) throws -> MutationEffect {
        try verifyMedia(at: relativePath, sha256: sha256, byteCount: byteCount, using: media)

        let asset = try requireAsset(id: assetID, in: db)
        try RequirementOperations.requireHuman(actor, subject: asset.ref)
        try requireActive(requirementID: asset.requirementID, in: db)
        // §7.3: a non-nil stamp must name a prompt of the same requirement — Swift
        // validation, so a caller cannot fabricate lineage across slots.
        if let promptID {
            let owner = try String.fetchOne(
                db,
                sql: "SELECT requirement_id FROM asset_prompts WHERE id = ?",
                arguments: [promptID.uuidString]
            )
            guard owner == asset.requirementID.uuidString else {
                throw ProjectStoreError.assetOperationRefused(
                    reason: "That prompt does not belong to this requirement."
                )
            }
        }

        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: assetID, in: db)

        if !restoring.isEmpty {
            // The redo path (§3.8): every touched row back **byte-identically**, the
            // version row's `created_at` and the asset row's recomputed `status` included.
            // No recompute runs here — the restored status is the one the recompute wrote,
            // so the inverse path "agrees by construction" (§6.3) instead of stamping a
            // fresh `updated_at` over a byte-identical restore. The verification above still
            // ran, so a redo whose file has gone was refused before this line.
            for snapshot in restoring where snapshot.table == "asset_versions" {
                if case let .string(raw)? = snapshot.columns["id"], let id = UUID(uuidString: raw) {
                    try collector.capture(table: "asset_versions", id: id, in: db)
                }
            }
            try RowGraph.restore(restoring, in: db)
            return MutationEffect(
                inverse: .removeVersionRow(versionID: versionID),
                affected: Set([asset.ref, SubjectRef(kind: .version, id: versionID)])
                    .union(RowGraph.subjects(of: restoring)),
                snapshots: collector.snapshots
            )
        } else {
            let timestamp = UTCDate.string(from: Date())
            var arguments: StatementArguments = [
                versionID.uuidString, assetID.uuidString, versionNumber,
                AssetVersionStatus.needsReview.rawValue, relativePath.rawValue, sha256,
                byteCount, originalFileName, mediaKind.rawValue, pixelWidth, pixelHeight,
                promptID?.uuidString,
            ]
            arguments += RequirementOperations.insertProvenance(actor, timestamp: timestamp)
            try db.execute(
                sql: """
                    INSERT INTO asset_versions (
                        id, asset_id, version_number, status, relative_path, sha256,
                        byte_count, original_file_name, media_kind, pixel_width, pixel_height,
                        notes, prompt_id, source, confidence, review_state, reviewed_at,
                        job_id, created_source, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: arguments
            )
        }

        // §6.1's third exclusion leg: arriving media ends the generation attempt. The
        // asset row was snapshotted above, so the inverse restores the marker from there.
        try db.execute(
            sql: "UPDATE assets SET in_progress_since = NULL WHERE id = ?",
            arguments: [assetID.uuidString]
        )

        // §6.3 rule 3: importing media clears a standing explicit rejection. Deliberately
        // after the restore, so a redo lands on the same answer as the first apply.
        if try requireAsset(id: assetID, in: db).rejectedExplicitly {
            try db.execute(
                sql: "UPDATE assets SET rejected_explicitly = 0, updated_at = ? WHERE id = ?",
                arguments: [UTCDate.string(from: Date()), assetID.uuidString]
            )
        }
        let applied = try recompute(requirementID: asset.requirementID, in: db)
        collector.add(contentsOf: applied.snapshots)
        return MutationEffect(
            inverse: .removeVersionRow(versionID: versionID),
            affected: Set([asset.ref, SubjectRef(kind: .version, id: versionID)])
                .union(applied.affected),
            snapshots: collector.snapshots
        )
    }

    /// `importAssetVersion`'s inverse: the **row only**. §4.1 is explicit — "undoing an
    /// import leaves the file and removes only the row" — so the file becomes an orphan,
    /// which is a maintenance concern and not a correctness one.
    static func removeVersionRow(
        versionID: UUID,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        let version = try requireVersion(id: versionID, in: db)
        let asset = try requireAsset(id: version.assetID, in: db)

        var collector = SnapshotCollector()
        try collector.capture(table: "asset_versions", id: versionID, in: db)
        try collector.capture(table: "assets", id: version.assetID, in: db)
        let generationRunID = try String.fetchOne(
            db,
            sql: "SELECT image_generation_run_id FROM asset_versions WHERE id = ?",
            arguments: [versionID.uuidString]
        ).flatMap(UUID.init(uuidString:))

        try db.execute(
            sql: "DELETE FROM asset_versions WHERE id = ?", arguments: [versionID.uuidString]
        )
        if let generationRunID {
            let hasRemainingCandidates = try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM asset_versions WHERE image_generation_run_id = ?
                    )
                    """,
                arguments: [generationRunID.uuidString]
            ) ?? false
            if !hasRemainingCandidates {
                try collector.capture(table: "image_generation_runs", id: generationRunID, in: db)
                collector.add(contentsOf: try RowSnapshotStore.captureAll(
                    table: "image_generation_references",
                    where: "run_id = ?",
                    arguments: [generationRunID.uuidString],
                    in: db
                ))
                collector.add(contentsOf: try RowSnapshotStore.captureAll(
                    table: "image_generation_amendments",
                    where: "run_id = ?",
                    arguments: [generationRunID.uuidString],
                    in: db
                ))
                try db.execute(
                    sql: "DELETE FROM image_generation_runs WHERE id = ?",
                    arguments: [generationRunID.uuidString]
                )
            }
        }
        let restoring = collector.snapshots
        // Undoing an import restores the asset row the import rewrote **byte-identically**
        // rather than recomputing it: §3.8 contracts byte-identity for the restoring
        // direction, and the snapshotted status is the one §6.3 produced before the import.
        // Applied as a fresh gesture — there is no public door for that — it recomputes.
        if let entry = mode.invertedEntry,
           let assetSnapshot = entry.snapshot(table: "assets", id: version.assetID) {
            try RowSnapshotStore.restore(assetSnapshot, in: db)
        } else {
            let applied = try recompute(requirementID: asset.requirementID, in: db)
            collector.add(contentsOf: applied.snapshots)
        }

        return MutationEffect(
            inverse: .importAssetVersion(
                versionID: versionID,
                assetID: version.assetID,
                versionNumber: version.versionNumber,
                relativePath: version.relativePath,
                sha256: version.sha256,
                byteCount: version.byteCount,
                originalFileName: version.originalFileName,
                mediaKind: version.mediaKind,
                pixelWidth: version.pixelWidth,
                pixelHeight: version.pixelHeight,
                promptID: stampedPromptID(versionID: versionID, in: db),
                restoring: restoring
            ),
            affected: [asset.ref, version.ref],
            snapshots: collector.snapshots
        )
    }

    /// §4.1's integrity read, done through the containment walk: the file is opened
    /// no-follow under the bundle root, its size checked cheaply, and its SHA-256 compared.
    ///
    /// A missing file, a symlinked component or leaf, a changed size, and a changed hash are
    /// all refusals — and all of them are reported **before** the row goes in.
    static func verifyMedia(
        at path: RelativeProjectPath,
        sha256: String,
        byteCount: Int,
        using media: BundleContainment
    ) throws {
        _ = try verifiedMediaData(
            at: path, sha256: sha256, byteCount: byteCount, using: media
        )
    }

    /// Reads once through the no-follow descriptor and returns only bytes that match the
    /// database's size and digest. Image generation uses the returned snapshot so a later
    /// path swap cannot change what the provider receives.
    static func verifiedMediaData(
        at path: RelativeProjectPath,
        sha256: String,
        byteCount: Int,
        using media: BundleContainment
    ) throws -> Data {
        guard byteCount > 0, byteCount <= MediaImportLimits.maximumByteCount else {
            throw ProjectStoreError.mediaFileDamaged(
                path: path.rawValue, reason: "its recorded size is outside the media limit"
            )
        }
        let data: Data
        do {
            data = try media.withReadDescriptor(at: path) { descriptor in
                var metadata = stat()
                guard fstat(descriptor, &metadata) == 0,
                      (metadata.st_mode & S_IFMT) == S_IFREG
                else {
                    throw ProjectStoreError.mediaFileDamaged(
                        path: path.rawValue, reason: "it is not a readable regular file"
                    )
                }
                guard metadata.st_size == byteCount else {
                    throw ProjectStoreError.mediaFileDamaged(
                        path: path.rawValue,
                        reason: "it is \(metadata.st_size) bytes and the project recorded \(byteCount)"
                    )
                }
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
                return try handle.read(upToCount: byteCount + 1) ?? Data()
            }
        } catch let error as BundleContainmentError {
            if case .missingComponent = error {
                throw ProjectStoreError.mediaFileMissing(path: path.rawValue)
            }
            throw error
        }
        guard data.count == byteCount else {
            throw ProjectStoreError.mediaFileDamaged(
                path: path.rawValue,
                reason: "it is \(data.count) bytes and the project recorded \(byteCount)"
            )
        }
        guard data.sha256Hex == sha256 else {
            throw ProjectStoreError.mediaFileDamaged(
                path: path.rawValue, reason: "its contents no longer match what was imported"
            )
        }
        return data
    }
}

// MARK: - Version verdicts (§7.3, §6.3's first asymmetry)

extension AssetOperations {
    /// §7.3's `rejectVersion`. Its inverse is the payload-driven prior-status restore, so
    /// undoing it puts back whatever the version was — `needs_review` or `approved` — rather
    /// than performing the `unrejectVersion` gesture.
    static func rejectVersion(
        versionID: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertVersion(versionID: versionID, entry: entry, in: db) { _ in
                .unrejectVersion(versionID: versionID)
            }
        }
        let version = try requireVersion(id: versionID, in: db)
        return try setVersionStatus(
            version,
            to: .rejected,
            actor: actor,
            inverse: .restoreVersionStatus(versionID: versionID, status: version.status),
            in: db
        )
    }

    /// The **user gesture**: always `needs_review` (§6.3 — un-rejecting is "reconsider",
    /// not "restore"). Its inverse is `rejectVersion`.
    static func unrejectVersion(
        versionID: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertVersion(versionID: versionID, entry: entry, in: db) { _ in
                .rejectVersion(versionID: versionID)
            }
        }
        let version = try requireVersion(id: versionID, in: db)
        return try setVersionStatus(
            version,
            to: .needsReview,
            actor: actor,
            inverse: .rejectVersion(versionID: versionID),
            in: db
        )
    }

    /// `rejectVersion`'s inverse: the snapshotted prior status back **exactly**.
    ///
    /// Reached through `applyInverse`, which runs it in `.inverting` mode — the byte-identical
    /// restore. The `.apply` branch exists so the case is total, and re-states the same
    /// intent as a plain write.
    ///
    /// **Its redo is `rejectVersion`, and only ever that** (Plan 011 step 2's open question,
    /// resolved against §6.3's table): `restoreVersionStatus` is emitted by exactly one
    /// producer — `rejectVersion`'s `MutationEffect.inverse` — so undoing it is re-applying
    /// that reject. The other operation that demotes a version, `approveVersion`, does **not**
    /// route its demotion through this case: the demoted row travels inside
    /// `AssetApprovalPayload.snapshots`, and the whole approve is undone as one hand-ordered
    /// payload case. That is what keeps the inverse graph a two-node cycle here
    /// (`rejectVersion` ⇄ `restoreVersionStatus`) rather than a case two operations can reach.
    ///
    /// The one interaction that remains is a `status: .approved` payload — reject the
    /// approved version, approve a different one, then undo the reject — and it is refused
    /// **before any write** by `precheckRestoreVersionStatus`, because restoring a second
    /// approved row would hit the partial unique index (§7.3).
    static func restoreVersionStatus(
        versionID: UUID,
        status: AssetVersionStatus,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertVersion(versionID: versionID, entry: entry, in: db) { _ in
                .rejectVersion(versionID: versionID)
            }
        }
        let version = try requireVersion(id: versionID, in: db)
        return try setVersionStatus(
            version,
            to: status,
            actor: actor,
            inverse: .restoreVersionStatus(versionID: versionID, status: version.status),
            in: db
        )
    }

    /// The write shape the three verdict operations share: snapshot the version and its
    /// asset, write **only** `status`, recompute.
    private static func setVersionStatus(
        _ version: VersionRow,
        to status: AssetVersionStatus,
        actor: MutationActor,
        inverse: EditOperation,
        in db: Database
    ) throws -> MutationEffect {
        let asset = try requireAsset(id: version.assetID, in: db)
        try RequirementOperations.requireHuman(actor, subject: version.ref)

        var collector = SnapshotCollector()
        try collector.capture(table: "asset_versions", id: version.id, in: db)
        try collector.capture(table: "assets", id: version.assetID, in: db)
        try db.execute(
            sql: "UPDATE asset_versions SET status = ?, updated_at = ? WHERE id = ?",
            arguments: [status.rawValue, UTCDate.string(from: Date()), version.id.uuidString]
        )
        let applied = try recompute(requirementID: asset.requirementID, in: db)
        collector.add(contentsOf: applied.snapshots)
        return MutationEffect(
            inverse: inverse,
            affected: Set([version.ref, asset.ref]).union(applied.affected),
            snapshots: collector.snapshots
        )
    }

    /// The `.inverting` half every version verdict shares: the version row and its asset row
    /// back exactly as the entry found them, and the operation that would apply the change
    /// again.
    private static func invertVersion(
        versionID: UUID,
        entry: JournalEntry,
        in db: Database,
        redo: (VersionRow) -> EditOperation
    ) throws -> MutationEffect {
        let version = try requireVersion(id: versionID, in: db)
        var affected: Set<SubjectRef> = [version.ref]
        var priors: [RowSnapshot] = []
        var restorable: [RowSnapshot] = []

        if let snapshot = entry.snapshot(table: "asset_versions", id: versionID) {
            restorable.append(snapshot)
            if let current = try RowSnapshotStore.capture(
                table: "asset_versions", id: versionID, in: db
            ) {
                priors.append(current)
            }
        }
        if let snapshot = entry.snapshot(table: "assets", id: version.assetID) {
            restorable.append(snapshot)
            affected.insert(SubjectRef(kind: .asset, id: version.assetID))
            if let current = try RowSnapshotStore.capture(
                table: "assets", id: version.assetID, in: db
            ) {
                priors.append(current)
            }
        }
        guard !restorable.isEmpty else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has a version verdict to restore."
            )
        }
        try RowGraph.restore(restorable, in: db)
        return MutationEffect(inverse: redo(version), affected: affected, snapshots: priors)
    }
}

// MARK: - approveVersion and its hand-ordered inverse (§7.3, §3.5)

extension AssetOperations {
    /// Plan 024's clear-current gesture. Unlike approving a replacement, changing the
    /// canonical version to `nil` always marks direct dependents stale.
    static func archiveCurrentVersion(
        assetID: UUID,
        versionID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        let asset = try requireAsset(id: assetID, in: db)
        let version = try requireVersion(id: versionID, in: db)
        try RequirementOperations.requireHuman(actor, subject: version.ref)
        guard version.assetID == assetID else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "That version belongs to a different asset."
            )
        }
        guard version.status == .approved else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "Only the current reference image can be archived from its card."
            )
        }

        let timestamp = UTCDate.string(from: Date())
        var collector = SnapshotCollector()
        var affected: Set<SubjectRef> = [asset.ref, version.ref]

        try collector.capture(table: "asset_versions", id: versionID, in: db)
        try db.execute(
            sql: "UPDATE asset_versions SET status = ?, updated_at = ? WHERE id = ?",
            arguments: [AssetVersionStatus.needsReview.rawValue, timestamp, versionID.uuidString]
        )

        try collector.capture(table: "assets", id: assetID, in: db)
        let applied = try recompute(requirementID: asset.requirementID, in: db)
        collector.add(contentsOf: applied.snapshots)
        affected.formUnion(applied.affected)

        let requirement = try RequirementOperations.require(id: asset.requirementID, in: db)
        let reason = staleReason(dependencyName: requirement.name)
        var staleAssetIDs: [UUID] = [assetID]
        for dependentID in try dependentAssetIDs(ofRequirement: asset.requirementID, in: db) {
            try collector.capture(table: "assets", id: dependentID, in: db)
            try db.execute(
                sql: """
                    UPDATE assets
                    SET is_stale = 1, stale_since = ?, stale_reason = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [timestamp, reason, timestamp, dependentID.uuidString]
            )
            staleAssetIDs.append(dependentID)
            affected.insert(SubjectRef(kind: .asset, id: dependentID))
        }

        let payload = AssetArchivePayload(
            assetID: assetID,
            versionID: versionID,
            staleAssetIDs: staleAssetIDs,
            snapshots: collector.snapshots
        )
        return MutationEffect(
            inverse: .restoreArchivedVersion(payload: payload),
            affected: affected,
            snapshots: collector.snapshots
        )
    }

    /// Hand-ordered inverse: the partial unique index requires a neutralization before the
    /// approved snapshot can be restored. Conflict checks normally guarantee no replacement
    /// exists, but this ordering also keeps the primitive safe when replayed internally.
    static func restoreArchivedVersion(
        payload: AssetArchivePayload,
        in db: Database
    ) throws -> MutationEffect {
        try db.execute(
            sql: """
                UPDATE asset_versions
                SET status = ?
                WHERE asset_id = ? AND status = 'approved'
                """,
            arguments: [AssetVersionStatus.needsReview.rawValue, payload.assetID.uuidString]
        )
        try RowGraph.restore(payload.snapshots, in: db)

        var affected = RowGraph.subjects(of: payload.snapshots)
        affected.insert(SubjectRef(kind: .asset, id: payload.assetID))
        affected.insert(SubjectRef(kind: .version, id: payload.versionID))
        for id in payload.staleAssetIDs {
            affected.insert(SubjectRef(kind: .asset, id: id))
        }
        return MutationEffect(
            inverse: .archiveCurrentVersion(
                assetID: payload.assetID,
                versionID: payload.versionID
            ),
            affected: affected,
            snapshots: []
        )
    }

    /// §7.3's `approveVersion`, in one transaction and in this order:
    ///
    /// 1. **Demote first.** `index_asset_versions_approved` is enforced per statement, so
    ///    the previously approved version becomes `needs_review` before the target is
    ///    promoted. Doing it the other way round fails on the index, undo or redo alike.
    /// 2. Approve the target.
    /// 3. Clear the asset's **own** `is_stale`/`stale_since`/`stale_reason` — §3.5's first
    ///    of the two staleness-clearing gestures.
    /// 4. Recompute (§6.3). The recompute is the only writer of `assets.status`, so an
    ///    approve on an inactive requirement lands `deprecated`-with-an-approved-version,
    ///    which §6.1 explicitly permits; no activity precondition is invented here.
    /// 5. Fan out §3.5's staleness — **only when the approved version changed**. First
    ///    approval marks nothing, and marking never cascades transitively: the assets of
    ///    the requirements that depend on *this* requirement are marked, and no further.
    ///
    /// The affected set names every touched row, dependents included, so conflict detection
    /// sees the staleness.
    static func approveVersion(
        assetID: UUID,
        versionID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        let asset = try requireAsset(id: assetID, in: db)
        let version = try requireVersion(id: versionID, in: db)
        try RequirementOperations.requireHuman(actor, subject: version.ref)
        guard version.assetID == assetID else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "That version belongs to a different asset."
            )
        }
        // Approving the version that already holds the approval is a **no-op refusal**, not
        // a silent success: §6.3's row promotes a target and demotes a *previously* approved
        // one, and an operation that changes nothing must not journal an undo step.
        guard version.status != .approved else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "That version is already the approved one."
            )
        }

        let timestamp = UTCDate.string(from: Date())
        var collector = SnapshotCollector()
        var affected: Set<SubjectRef> = [asset.ref, version.ref]

        // 1. Demote first.
        let priorApproved = try approvedVersionID(assetID: assetID, in: db)
        if let priorApproved {
            try collector.capture(table: "asset_versions", id: priorApproved, in: db)
            affected.insert(SubjectRef(kind: .version, id: priorApproved))
            try db.execute(
                sql: "UPDATE asset_versions SET status = ?, updated_at = ? WHERE id = ?",
                arguments: [
                    AssetVersionStatus.needsReview.rawValue, timestamp, priorApproved.uuidString,
                ]
            )
        }

        // 2. Approve the target.
        try collector.capture(table: "asset_versions", id: versionID, in: db)
        try db.execute(
            sql: "UPDATE asset_versions SET status = ?, updated_at = ? WHERE id = ?",
            arguments: [AssetVersionStatus.approved.rawValue, timestamp, versionID.uuidString]
        )

        // 3. The asset row is snapshotted **before** its staleness is cleared; the
        //    recompute's own snapshot of the same row arrives later and the collector keeps
        //    the first, which is the one the inverse needs.
        try collector.capture(table: "assets", id: assetID, in: db)
        try db.execute(
            sql: """
                UPDATE assets
                SET is_stale = 0, stale_since = NULL, stale_reason = NULL, updated_at = ?
                WHERE id = ?
                """,
            arguments: [timestamp, assetID.uuidString]
        )

        // 4. §6.3's one recompute.
        let applied = try recompute(requirementID: asset.requirementID, in: db)
        collector.add(contentsOf: applied.snapshots)
        affected.formUnion(applied.affected)

        // 5. §3.5's fan-out, one level only.
        var staleAssetIDs: [UUID] = [assetID]
        if priorApproved != nil {
            let requirement = try RequirementOperations.require(id: asset.requirementID, in: db)
            let reason = staleReason(dependencyName: requirement.name)
            for dependentID in try dependentAssetIDs(ofRequirement: asset.requirementID, in: db) {
                try collector.capture(table: "assets", id: dependentID, in: db)
                try db.execute(
                    sql: """
                        UPDATE assets
                        SET is_stale = 1, stale_since = ?, stale_reason = ?, updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [timestamp, reason, timestamp, dependentID.uuidString]
                )
                staleAssetIDs.append(dependentID)
                affected.insert(SubjectRef(kind: .asset, id: dependentID))
            }
        }

        let payload = AssetApprovalPayload(
            assetID: assetID,
            versionID: versionID,
            priorApprovedVersionID: priorApproved,
            staleAssetIDs: staleAssetIDs,
            snapshots: collector.snapshots
        )
        return MutationEffect(
            inverse: .unapproveVersion(payload: payload),
            affected: affected,
            snapshots: collector.snapshots
        )
    }

    /// `approveVersion`'s inverse: **demote, then restore** (§7.3).
    ///
    /// The demotion writes nothing the restore does not overwrite — `versionID`'s own row is
    /// in `snapshots` — so the result is byte-identical while never letting two `approved`
    /// rows of one asset exist between two statements.
    static func unapproveVersion(
        payload: AssetApprovalPayload,
        in db: Database
    ) throws -> MutationEffect {
        try db.execute(
            sql: "UPDATE asset_versions SET status = ? WHERE id = ?",
            arguments: [AssetVersionStatus.needsReview.rawValue, payload.versionID.uuidString]
        )
        try RowGraph.restore(payload.snapshots, in: db)

        var affected = RowGraph.subjects(of: payload.snapshots)
        affected.insert(SubjectRef(kind: .asset, id: payload.assetID))
        affected.insert(SubjectRef(kind: .version, id: payload.versionID))
        if let prior = payload.priorApprovedVersionID {
            affected.insert(SubjectRef(kind: .version, id: prior))
        }
        for id in payload.staleAssetIDs { affected.insert(SubjectRef(kind: .asset, id: id)) }
        return MutationEffect(
            inverse: .approveVersion(assetID: payload.assetID, versionID: payload.versionID),
            affected: affected,
            snapshots: []
        )
    }

    /// The asset's approved version, if it has one (§4.3's partial unique index gives at
    /// most one).
    static func approvedVersionID(assetID: UUID, in db: Database) throws -> UUID? {
        guard let raw = try String.fetchOne(
            db,
            sql: "SELECT id FROM asset_versions WHERE asset_id = ? AND status = 'approved'",
            arguments: [assetID.uuidString]
        ) else { return nil }
        return try UUID.required(raw)
    }

    /// The assets of every requirement that **depends on** `requirementID` (§3.5's
    /// direction: dependents are marked when their dependency's approval changes).
    ///
    /// A `rejected` dependency row is a tombstone — `removeDependency` on an `ai`/`parser`
    /// row leaves one, and §3.5's seeding respects it — so the edge no longer exists and
    /// nothing travels along it. Requirement *activity* is deliberately not filtered: §3.5
    /// marks the dependents' assets, and a retired slot's stale badge is a read-time concern.
    static func dependentAssetIDs(ofRequirement requirementID: UUID, in db: Database) throws -> [UUID] {
        try String
            .fetchAll(
                db,
                sql: """
                    SELECT a.id FROM assets a
                    JOIN asset_dependencies d ON d.requirement_id = a.requirement_id
                    WHERE d.depends_on_requirement_id = ? AND d.review_state <> 'rejected'
                    ORDER BY a.id
                    """,
                arguments: [requirementID.uuidString]
            )
            .map { try UUID.required($0) }
    }

    /// §3.5's reason, naming the dependency whose approved version changed. One spelling,
    /// here, so the UI's stale badge and the tests read the same sentence.
    static func staleReason(dependencyName: String) -> String {
        "“\(dependencyName)” has a different approved reference image."
    }
}

// MARK: - clearAssetStale (§3.5's second clearing gesture, §7.3)

extension AssetOperations {
    static func markAssetStale(
        assetID: UUID,
        reason: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertAsset(assetID: assetID, entry: entry, in: db) {
                .restoreMarkedAssetStale(
                    assetID: assetID,
                    snapshot: currentAssetSnapshot(assetID, in: db),
                    reason: reason
                )
            }
        }
        let asset = try requireAsset(id: assetID, in: db)
        try RequirementOperations.requireHuman(actor, subject: asset.ref)
        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: assetID, in: db)
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                UPDATE assets
                SET is_stale = 1, stale_since = ?, stale_reason = ?, updated_at = ?
                WHERE id = ?
                """,
            arguments: [timestamp, reason, timestamp, assetID.uuidString]
        )
        return MutationEffect(
            inverse: .restoreMarkedAssetStale(
                assetID: assetID,
                snapshot: collector.snapshots,
                reason: reason
            ),
            affected: [asset.ref],
            snapshots: collector.snapshots
        )
    }

    static func restoreMarkedAssetStale(
        assetID: UUID,
        snapshot: [RowSnapshot],
        reason: String,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertAsset(assetID: assetID, entry: entry, in: db) {
                .markAssetStale(assetID: assetID, reason: reason)
            }
        }
        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: assetID, in: db)
        try RowGraph.restore(snapshot, in: db)
        return MutationEffect(
            inverse: .markAssetStale(assetID: assetID, reason: reason),
            affected: [SubjectRef(kind: .asset, id: assetID)],
            snapshots: collector.snapshots
        )
    }

    /// The explicit "Mark Current". Writes only the three staleness columns; `status` is
    /// untouched, because staleness is a flag and not a state (§6.2).
    static func clearAssetStale(
        assetID: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertAsset(assetID: assetID, entry: entry, in: db) {
                .restoreAssetStale(assetID: assetID, snapshot: currentAssetSnapshot(assetID, in: db))
            }
        }
        let asset = try requireAsset(id: assetID, in: db)
        try RequirementOperations.requireHuman(actor, subject: asset.ref)
        guard try isStale(assetID: assetID, in: db) else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "That asset is not marked stale."
            )
        }
        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: assetID, in: db)
        try db.execute(
            sql: """
                UPDATE assets
                SET is_stale = 0, stale_since = NULL, stale_reason = NULL, updated_at = ?
                WHERE id = ?
                """,
            arguments: [UTCDate.string(from: Date()), assetID.uuidString]
        )
        return MutationEffect(
            inverse: .restoreAssetStale(assetID: assetID, snapshot: collector.snapshots),
            affected: [asset.ref],
            snapshots: collector.snapshots
        )
    }

    /// `clearAssetStale`'s inverse. Reached through `applyInverse` in `.inverting` mode —
    /// the byte-identical restore; the `.apply` branch writes the payload back and exists so
    /// the case is total.
    static func restoreAssetStale(
        assetID: UUID,
        snapshot: [RowSnapshot],
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertAsset(assetID: assetID, entry: entry, in: db) {
                .clearAssetStale(assetID: assetID)
            }
        }
        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: assetID, in: db)
        try RowGraph.restore(snapshot, in: db)
        return MutationEffect(
            inverse: .clearAssetStale(assetID: assetID),
            affected: [SubjectRef(kind: .asset, id: assetID)],
            snapshots: collector.snapshots
        )
    }

    static func isStale(assetID: UUID, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT is_stale FROM assets WHERE id = ?",
            arguments: [assetID.uuidString]
        ) ?? false
    }

    /// The asset row as it stands right now, as an inverse payload — the redo operation an
    /// `.inverting` branch hands back has to carry it, and that closure cannot throw.
    static func currentAssetSnapshot(_ assetID: UUID, in db: Database) -> [RowSnapshot] {
        guard let snapshot = try? RowSnapshotStore.capture(table: "assets", id: assetID, in: db)
        else { return [] }
        return [snapshot]
    }
}

// MARK: - The two destroyers of media (§7.3, §4.1's rows-first rule)

extension AssetOperations {
    /// §7.3's `deleteVersion`: **non-invertible**, allowed only on a `rejected` version.
    ///
    /// The row goes here; the file goes after commit, through
    /// `MutationEffect.removedMediaPaths`. Removing the **last** version clears a standing
    /// explicit rejection (§6.3), which is what makes the slot come back `needed` rather
    /// than `rejected`.
    static func deleteVersion(
        versionID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        let version = try requireVersion(id: versionID, in: db)
        let asset = try requireAsset(id: version.assetID, in: db)
        let generationRunID = try generationRunID(versionID: versionID, in: db)
        try RequirementOperations.requireHuman(actor, subject: version.ref)
        guard version.status == .rejected else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "Only a rejected version can be deleted. Reject it first."
            )
        }

        var collector = SnapshotCollector()
        try collector.capture(table: "asset_versions", id: versionID, in: db)
        try collector.capture(table: "assets", id: version.assetID, in: db)
        try db.execute(
            sql: "DELETE FROM asset_versions WHERE id = ?", arguments: [versionID.uuidString]
        )
        try deleteOrphanedGenerationRuns(generationRunID.map { [$0] } ?? [], in: db)
        if try versionCount(assetID: version.assetID, in: db) == 0 {
            try db.execute(
                sql: "UPDATE assets SET rejected_explicitly = 0, updated_at = ? WHERE id = ?",
                arguments: [UTCDate.string(from: Date()), version.assetID.uuidString]
            )
        }
        let applied = try recompute(requirementID: asset.requirementID, in: db)
        collector.add(contentsOf: applied.snapshots)

        return MutationEffect(
            inverse: nil,
            affected: Set([version.ref, asset.ref]).union(applied.affected),
            snapshots: collector.snapshots,
            removedMediaPaths: [version.relativePath]
        )
    }

    /// Plan 024's confirmed permanent deletion from Archived Images. The confirmation is
    /// presentation policy; FilmCore enforces that only an archived (`needs_review`) row
    /// reaches this non-invertible, rows-first/files-second primitive.
    static func deleteArchivedVersion(
        versionID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        let version = try requireVersion(id: versionID, in: db)
        let asset = try requireAsset(id: version.assetID, in: db)
        let generationRunID = try generationRunID(versionID: versionID, in: db)
        try RequirementOperations.requireHuman(actor, subject: version.ref)
        guard version.status == .needsReview else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "Only an archived image can be permanently deleted here."
            )
        }

        var collector = SnapshotCollector()
        try collector.capture(table: "asset_versions", id: versionID, in: db)
        try collector.capture(table: "assets", id: version.assetID, in: db)
        try db.execute(
            sql: "DELETE FROM asset_versions WHERE id = ?",
            arguments: [versionID.uuidString]
        )
        try deleteOrphanedGenerationRuns(generationRunID.map { [$0] } ?? [], in: db)
        let applied = try recompute(requirementID: asset.requirementID, in: db)
        collector.add(contentsOf: applied.snapshots)

        return MutationEffect(
            inverse: nil,
            affected: Set([version.ref, asset.ref]).union(applied.affected),
            snapshots: collector.snapshots,
            removedMediaPaths: [version.relativePath]
        )
    }

    /// §7.3's `deleteAsset`: **non-invertible**. The asset row, its version rows, and —
    /// after commit — their files.
    static func deleteAsset(
        id: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        let asset = try requireAsset(id: id, in: db)
        try RequirementOperations.requireHuman(actor, subject: asset.ref)

        let versionRows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM asset_versions WHERE asset_id = ? ORDER BY version_number",
            arguments: [id.uuidString]
        )
        let versions = try versionRows.map(decodeVersion)
        let generationRunIDs = Set(versionRows.compactMap { row in
            (row["image_generation_run_id"] as String?).flatMap(UUID.init(uuidString:))
        })

        var collector = SnapshotCollector()
        for row in versionRows { collector.add(table: "asset_versions", row: row) }
        try collector.capture(table: "assets", id: id, in: db)

        // Explicit, not left to `ON DELETE CASCADE`: the affected set has to name every row
        // the operation took, and a cascade names none of them.
        try db.execute(
            sql: "DELETE FROM asset_versions WHERE asset_id = ?", arguments: [id.uuidString]
        )
        try deleteOrphanedGenerationRuns(Array(generationRunIDs), in: db)
        try db.execute(sql: "DELETE FROM assets WHERE id = ?", arguments: [id.uuidString])

        var affected: Set<SubjectRef> = [asset.ref]
        for version in versions { affected.insert(version.ref) }

        // §7.3 / §14.2 (owner-decided 2026-08-22): Empty Slot spares prompt history. When
        // prompts remain, a **fresh anchor** is composed — new id, human provenance, no
        // marker, no standing rejection — and recomputed, so an emptied slot with a good
        // prompt honestly reads `prompt_ready`. With no prompts, nothing is composed and
        // the requirement displays Needed.
        let promptCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM asset_prompts WHERE requirement_id = ?",
            arguments: [asset.requirementID.uuidString]
        ) ?? 0
        if promptCount > 0 {
            let freshID = UUID()
            let timestamp = UTCDate.string(from: Date())
            try db.execute(
                sql: """
                    INSERT INTO assets (
                        id, project_id, requirement_id, status, is_stale, stale_since,
                        stale_reason, rejected_explicitly, notes,
                        source, confidence, review_state, reviewed_at, job_id,
                        created_source, created_at, updated_at
                    ) VALUES (?, ?, ?, 'needed', 0, NULL, NULL, 0, '',
                              'human', NULL, 'accepted', NULL, NULL, 'human', ?, ?)
                    """,
                arguments: [
                    freshID.uuidString, asset.projectID.uuidString,
                    asset.requirementID.uuidString, timestamp, timestamp,
                ]
            )
            _ = try recompute(requirementID: asset.requirementID, in: db)
            affected.insert(SubjectRef(kind: .asset, id: freshID))
        }

        return MutationEffect(
            inverse: nil,
            affected: affected,
            snapshots: collector.snapshots,
            removedMediaPaths: versions.map(\.relativePath)
        )
    }

    private static func generationRunID(versionID: UUID, in db: Database) throws -> UUID? {
        try String.fetchOne(
            db,
            sql: "SELECT image_generation_run_id FROM asset_versions WHERE id = ?",
            arguments: [versionID.uuidString]
        ).flatMap(UUID.init(uuidString:))
    }

    private static func deleteOrphanedGenerationRuns(_ ids: [UUID], in db: Database) throws {
        for id in ids {
            try db.execute(sql: """
                DELETE FROM image_generation_runs
                WHERE id = ? AND NOT EXISTS (
                    SELECT 1 FROM asset_versions WHERE image_generation_run_id = ?
                )
                """, arguments: [id.uuidString, id.uuidString])
        }
    }
}

// MARK: - The slot-level verdict and the notes (§7.3)

extension AssetOperations {
    /// §6.3 rule 3's standing explicit rejection. Precondition: **no approved version** —
    /// an approved slot is not one you reject, you approve a different version or delete it.
    static func rejectAsset(
        assetID: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertAsset(assetID: assetID, entry: entry, in: db) {
                .unrejectAsset(assetID: assetID)
            }
        }
        let asset = try requireAsset(id: assetID, in: db)
        try RequirementOperations.requireHuman(actor, subject: asset.ref)
        guard try !hasApprovedVersion(assetID: assetID, in: db) else {
            throw ProjectStoreError.assetOperationRefused(
                reason: "This asset has an approved version. Reject that version first."
            )
        }
        return try setRejectedExplicitly(
            asset, to: true, inverse: .unrejectAsset(assetID: assetID), in: db
        )
    }

    static func unrejectAsset(
        assetID: UUID,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertAsset(assetID: assetID, entry: entry, in: db) {
                .rejectAsset(assetID: assetID)
            }
        }
        let asset = try requireAsset(id: assetID, in: db)
        try RequirementOperations.requireHuman(actor, subject: asset.ref)
        return try setRejectedExplicitly(
            asset, to: false, inverse: .rejectAsset(assetID: assetID), in: db
        )
    }

    private static func setRejectedExplicitly(
        _ asset: AssetRow,
        to value: Bool,
        inverse: EditOperation,
        in db: Database
    ) throws -> MutationEffect {
        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: asset.id, in: db)
        try db.execute(
            sql: "UPDATE assets SET rejected_explicitly = ?, updated_at = ? WHERE id = ?",
            arguments: [value ? 1 : 0, UTCDate.string(from: Date()), asset.id.uuidString]
        )
        let applied = try recompute(requirementID: asset.requirementID, in: db)
        collector.add(contentsOf: applied.snapshots)
        return MutationEffect(
            inverse: inverse,
            affected: Set([asset.ref]).union(applied.affected),
            snapshots: collector.snapshots
        )
    }

    static func setAssetNotes(
        id: UUID,
        text: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertAsset(assetID: id, entry: entry, in: db) {
                .setAssetNotes(id: id, text: (try? requireAsset(id: id, in: db))?.notes ?? "")
            }
        }
        let asset = try requireAsset(id: id, in: db)
        try RequirementOperations.requireHuman(actor, subject: asset.ref)
        var collector = SnapshotCollector()
        try collector.capture(table: "assets", id: id, in: db)
        try db.execute(
            sql: "UPDATE assets SET notes = ?, updated_at = ? WHERE id = ?",
            arguments: [text, UTCDate.string(from: Date()), id.uuidString]
        )
        return MutationEffect(
            inverse: .setAssetNotes(id: id, text: asset.notes),
            affected: [asset.ref],
            snapshots: collector.snapshots
        )
    }

    static func setVersionNotes(
        id: UUID,
        text: String,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            return try invertVersion(versionID: id, entry: entry, in: db) { version in
                .setVersionNotes(id: id, text: version.notes)
            }
        }
        let version = try requireVersion(id: id, in: db)
        try RequirementOperations.requireHuman(actor, subject: version.ref)
        var collector = SnapshotCollector()
        try collector.capture(table: "asset_versions", id: id, in: db)
        try db.execute(
            sql: "UPDATE asset_versions SET notes = ?, updated_at = ? WHERE id = ?",
            arguments: [text, UTCDate.string(from: Date()), id.uuidString]
        )
        return MutationEffect(
            inverse: .setVersionNotes(id: id, text: version.notes),
            affected: [version.ref],
            snapshots: collector.snapshots
        )
    }

    /// The `.inverting` half the asset-row operations share.
    private static func invertAsset(
        assetID: UUID,
        entry: JournalEntry,
        in db: Database,
        redo: () -> EditOperation
    ) throws -> MutationEffect {
        let ref = SubjectRef(kind: .asset, id: assetID)
        guard let restorable = entry.snapshot(table: "assets", id: assetID) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has an asset to restore."
            )
        }
        let inverse = redo()
        var priors: [RowSnapshot] = []
        if let current = try RowSnapshotStore.capture(table: "assets", id: assetID, in: db) {
            priors.append(current)
        }
        try RowGraph.restore([restorable], in: db)
        return MutationEffect(inverse: inverse, affected: [ref], snapshots: priors)
    }
}

// MARK: - Preconditions for the inverses (§3.8, §7.3's pinned walk)

extension AssetOperations {
    static func precheckAsset(id: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "assets", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That asset is no longer in this project."
            )
        }
    }

    static func precheckVersion(id: UUID, in db: Database) throws {
        guard try RowSnapshotStore.exists(table: "asset_versions", id: id, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That version is no longer in this project."
            )
        }
    }

    /// `approveVersion` as an inverse (the redo of an undone approve): both rows are still
    /// there, and the target is not already the approved one.
    static func precheckApprove(assetID: UUID, versionID: UUID, in db: Database) throws {
        try precheckAsset(id: assetID, in: db)
        try precheckVersion(id: versionID, in: db)
        guard try requireVersion(id: versionID, in: db).status != .approved else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That version is already the approved one."
            )
        }
    }

    /// `archiveCurrentVersion` as an inverse/redo: the exact version must still be current.
    static func precheckArchive(assetID: UUID, versionID: UUID, in db: Database) throws {
        try precheckAsset(id: assetID, in: db)
        try precheckVersion(id: versionID, in: db)
        let version = try requireVersion(id: versionID, in: db)
        guard version.assetID == assetID, version.status == .approved else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That image is no longer the current reference."
            )
        }
    }

    /// The partial unique index, made visible to the one inverse that could hit it (§7.3).
    ///
    /// `RowSnapshotStore.wouldCollide` models column-equality uniques only, so nothing else
    /// would catch "restore this row to `approved` while another approved row of the same
    /// asset stands" — the sequence being: reject the approved version, approve a different
    /// one, undo the reject.
    static func precheckRestoreVersionStatus(
        versionID: UUID,
        status: AssetVersionStatus,
        in db: Database
    ) throws {
        try precheckVersion(id: versionID, in: db)
        guard status == .approved else { return }
        let version = try requireVersion(id: versionID, in: db)
        if let standing = try approvedVersionID(assetID: version.assetID, in: db),
           standing != versionID {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Another version has been approved since, so this one cannot come back."
            )
        }
    }

    /// §7.3's pinned walk, as a precheck.
    ///
    /// Two refusals, both **before any write**:
    ///
    /// * `UNIQUE(asset_id, version_number)` or `UNIQUE(relative_path)` now held by another
    ///   row — the case the walk names: undo an import, import again (which computes the
    ///   same `max + 1` and lands at `v3-2.png` per the collision rule), then redo the
    ///   original. A graceful refusal, not a corruption.
    /// * The file is gone or no longer hashes to what the row claimed — the case Clear
    ///   Orphaned Media creates.
    static func precheckImport(
        versionID: UUID,
        assetID: UUID,
        versionNumber: Int,
        relativePath: RelativeProjectPath,
        sha256: String,
        byteCount: Int,
        media: BundleContainment?,
        in db: Database
    ) throws {
        // The asset row is deliberately **not** required to exist yet: a redo of a *first*
        // import is a group whose earlier child restores it, and every child of a batch is
        // prechecked before any of them runs. `mutate` requires it at apply time.
        let collides = try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM asset_versions
                    WHERE id <> ?
                      AND ((asset_id = ? AND version_number = ?) OR relative_path = ?)
                )
                """,
            arguments: [
                versionID.uuidString, assetID.uuidString, versionNumber, relativePath.rawValue,
            ]
        ) ?? false
        guard !collides else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "Another image has taken that version number since, so this one cannot come back."
            )
        }
        if let media {
            try verifyMedia(at: relativePath, sha256: sha256, byteCount: byteCount, using: media)
        }
    }
}
