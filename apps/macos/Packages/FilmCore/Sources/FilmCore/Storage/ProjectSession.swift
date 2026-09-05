import FilmScript
import Foundation

/// The one conformer of `ProjectTools` (§3.9a): a thin actor over `ProjectRepository`,
/// `EditPrimitives`, and `ProjectObservationHub`.
public actor ProjectSession: ProjectTools {
    public nonisolated let bundleURL: URL
    private let layout: ProjectBundleLayout
    /// Internal so `ProjectTools+Editing` can open the one write transaction §3.8
    /// requires; nothing outside FilmCore can reach it.
    var database: ProjectDatabase?
    private let initialProject: Project
    private var observationHub: ProjectObservationHub?
    /// Non-nil **exactly** when opening this bundle ran a migration (§4.2); a fresh
    /// `create` yields `nil`.
    public let upgradeSummary: UpgradeSummary?

    /// The descriptor-relative door every media path goes through (§4.1). Internal so
    /// `ProjectSession+Media` and `applyInverse` can reach it; nothing outside FilmCore can.
    var mediaContainment: BundleContainment { BundleContainment(rootURL: layout.rootURL) }

    init(
        layout: ProjectBundleLayout,
        database: ProjectDatabase,
        project: Project,
        upgradeSummary: UpgradeSummary? = nil
    ) {
        self.bundleURL = layout.rootURL
        self.layout = layout
        self.database = database
        self.initialProject = project
        self.upgradeSummary = upgradeSummary
    }

    // MARK: - ProjectReading

    public func projectSnapshot() throws -> Project {
        try repository().validateProject()
    }

    /// The project's script, by `projects.current_script_id`; `nil` until imported.
    public func script() throws -> Script? {
        try repository().script()
    }

    public func scenes() throws -> [Scene] {
        try repository().scenes()
    }

    public func scene(id: UUID) throws -> SceneDetail {
        try repository().sceneDetail(id: id)
    }

    public func sceneText(id: UUID) throws -> String {
        try repository().sceneText(id: id)
    }

    public func sceneReferenceExclusionID(
        sceneID: UUID,
        requirementID: UUID
    ) throws -> UUID? {
        try repository().sceneReferenceExclusionID(
            sceneID: sceneID,
            requirementID: requirementID
        )
    }

    public func sceneExclusions(id: UUID) throws -> [SceneExclusion] {
        try repository().sceneExclusions(id: id)
    }

    public func sequences() throws -> [ScriptSequence] {
        try repository().sequences()
    }

    public func continuityEvents() throws -> [ContinuityEvent] {
        try repository().continuityEvents()
    }

    public func entities(
        kind: EntityKind? = nil,
        reviewState: ReviewState? = nil,
        includeIrrelevant: Bool = true,
        includeRejected: Bool = false
    ) throws -> [Entity] {
        try repository().entities(
            kind: kind,
            reviewState: reviewState,
            includeIrrelevant: includeIrrelevant,
            includeRejected: includeRejected
        )
    }

    public func entitySummaries(
        kind: EntityKind? = nil,
        reviewState: ReviewState? = nil,
        includeIrrelevant: Bool = true,
        includeRejected: Bool = false
    ) throws -> [EntitySummary] {
        try repository().entitySummaries(
            kind: kind,
            reviewState: reviewState,
            includeIrrelevant: includeIrrelevant,
            includeRejected: includeRejected
        )
    }

    public func entity(id: UUID) throws -> EntityDetail {
        try repository().entityDetail(id: id)
    }

    public func locks() throws -> [Lock] {
        try repository().locks()
    }

    // MARK: - ProjectReading: the manifest (PHASE2_DESIGN §7.6)

    public func requirements(
        entityID: UUID,
        includeRejected: Bool = false
    ) throws -> [AssetRequirement] {
        try repository().requirements(entityID: entityID, includeRejected: includeRejected)
    }

    public func requirementSummaries(
        kind: EntityKind? = nil,
        tier: AssetRequirementTier? = nil,
        reviewState: ReviewState? = nil,
        includeRejected: Bool = false
    ) throws -> [RequirementSummary] {
        try repository().requirementSummaries(
            kind: kind,
            tier: tier,
            reviewState: reviewState,
            includeRejected: includeRejected
        )
    }

    public func requirement(id: UUID) throws -> RequirementDetail {
        try repository().requirementDetail(id: id)
    }

    public func manifestSummary() throws -> ManifestSummary {
        try repository().manifestSummary()
    }

    public func missingAssets() throws -> [MissingAsset] {
        try repository().missingAssets()
    }

    /// PHASE4_DESIGN §7.5: one `readinessGraph` load, one derivation — per-scene rows,
    /// the summary fold, and the impact ranking.
    public func readinessSnapshot() throws -> ReadinessSnapshot {
        try repository().readinessSnapshot()
    }

    // MARK: Phase 5a (PHASE5_DESIGN §7.5; Plan 018 contract D)

    public func scenePackages() throws -> [ScenePackageSummary] {
        try repository().scenePackages()
    }

    public func scenePackageDetail(sceneID: UUID) throws -> ScenePackageDetail {
        try repository().scenePackageDetail(sceneID: sceneID)
    }

    public func sceneReferenceArchives(sceneID: UUID) throws -> [SceneReferenceArchive] {
        try repository().sceneReferenceArchives(sceneID: sceneID)
    }

    public func scenePromptHistory(sceneID: UUID, targetProfile: String) throws -> [ScenePrompt] {
        try repository().scenePromptHistory(sceneID: sceneID, targetProfile: targetProfile)
    }

    public func scenePromptSetHistory(
        sceneID: UUID, targetProfile: String
    ) throws -> [ScenePromptSetDetail] {
        try repository().scenePromptSetHistory(sceneID: sceneID, targetProfile: targetProfile)
    }

    public func styleBible() throws -> String {
        try repository().styleBible()
    }

    public func requirementTemplate() throws -> [AssetRequirementType] {
        try repository().requirementTemplate()
    }

    public func manifestInput() throws -> ManifestInputSnapshot {
        try repository().manifestInput()
    }

    /// PHASE3_DESIGN §8.1/§8.2: one requirement's rendered asset-prompt input, built from
    /// canonical data alone. FilmBrain wraps this in `<asset-prompt-input>` for the run;
    /// the digest of this snapshot is what `jobs.input_sha256` records and what the apply's
    /// step-0 guard rebuilds.
    public func assetPromptInput(requirementID: UUID) throws -> AssetPromptInputSnapshot {
        try repository().assetPromptInput(requirementID: requirementID)
    }

    public func referenceImageGenerationContext(
        requirementID: UUID,
        generationPromptBody: String? = nil,
        includeCurrentImage: Bool = false
    ) throws -> ReferenceImageGenerationContext {
        try repository().referenceImageGenerationContext(
            requirementID: requirementID,
            generationPromptBody: generationPromptBody,
            includeCurrentImage: includeCurrentImage
        )
    }

    public func referenceImageGenerationAttachment(
        from sourceURL: URL,
        entityKind: EntityKind
    ) throws -> ReferenceImageGenerationAttachment {
        let fileName = sourceURL.lastPathComponent
        let declaredSize = (try? FileManager.default.attributesOfItem(
            atPath: sourceURL.path
        ))?[.size] as? Int
        if let declaredSize {
            try MediaImportLimits.check(byteCount: declaredSize, fileName: fileName)
        }
        let data = try Data(contentsOf: sourceURL)
        _ = try AssetPathing.inspectForImport(data, fileName: fileName)
        return ReferenceImageGenerationAttachment(
            originalFileName: fileName,
            data: data,
            entityKind: entityKind
        )
    }

    public func referenceImageGenerationInputs(
        context: ReferenceImageGenerationContext
    ) throws -> [ReferenceImageGenerationInput] {
        guard let database else { throw ProjectStoreError.sessionClosed }
        try Task.checkCancellation()
        let current = try database.queue.read { db in
            try ProjectRepository.referenceImageGenerationContext(
                requirementID: context.requirementID,
                generationPromptBodySHA256: context.promptBodySHA256,
                includeCurrentImage: context.includesCurrentImage,
                in: db
            )
        }
        guard current == context, current.refusalReason == nil else {
            throw ProjectStoreError.referenceImageGenerationContextChanged
        }
        return try context.orderedDependencies.map { dependency in
            try Task.checkCancellation()
            let data = try AssetOperations.verifiedMediaData(
                at: dependency.relativePath,
                sha256: dependency.sha256,
                byteCount: dependency.byteCount,
                using: mediaContainment
            )
            return ReferenceImageGenerationInput(
                requirementID: dependency.requirementID,
                entityKind: dependency.entityKind,
                fileExtension: (dependency.relativePath.rawValue as NSString).pathExtension,
                data: data
            )
        }
    }

    public func referenceImageCreationRefusals(
        requirementIDs: [UUID]
    ) throws -> [UUID: String] {
        try repository().referenceImageCreationRefusals(requirementIDs: requirementIDs)
    }

    /// PHASE5_DESIGN §8.1/§8.2: one scene's rendered scene-prompt input, built from
    /// canonical data alone. FilmBrain wraps this in `<scene-prompt-input>` for the run;
    /// the digest of this snapshot is what `jobs.input_sha256` records and what the
    /// apply's step-0 guard rebuilds. After a successful apply consumes one-time
    /// direction, the saved prompt uses the digest of the clean post-consumption basis.
    public func scenePromptInput(sceneID: UUID) throws -> ScenePromptInputSnapshot {
        try repository().scenePromptInput(sceneID: sceneID)
    }

    public func promptHistory(requirementID: UUID) throws -> [AssetPrompt] {
        try repository().promptHistory(requirementID: requirementID)
    }

    /// Files under `assets/` that no `asset_versions` row references (§7.6) — empty until
    /// Plan 011 writes media.
    ///
    /// A read-only listing, so it walks with `FileManager` rather than through
    /// `BundleContainment`'s descriptor walk, with one rule kept: **symlinks are never
    /// followed and never reported**. Reporting a link as orphaned media would invite a
    /// later delete to follow it out of the bundle, which is exactly what §4.1 forbids.
    public func orphanedMedia() throws -> [RelativeProjectPath] {
        guard database != nil else { throw ProjectStoreError.sessionClosed }
        let referenced = try repository().referencedMediaPaths()
        let root = layout.rootURL.appending(path: "assets", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        // The path-based enumerator yields subpaths **relative to** `assets/`, which is what
        // a `RelativeProjectPath` is built from; the URL-based one yields absolute URLs whose
        // `/private` prefix does not match the standardized bundle root.
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var orphans: [RelativeProjectPath] = []
        while let subpath = walker.nextObject() as? String {
            let components = subpath.split(separator: "/")
            // Hidden files are not media the filmmaker imported (`.DS_Store`, staging names).
            guard !components.contains(where: { $0.hasPrefix(".") }) else { continue }
            // `attributesOfItem` does not resolve a symlink: it reports the link itself.
            let attributes = try FileManager.default.attributesOfItem(
                atPath: root.appending(path: subpath).path
            )
            switch attributes[.type] as? FileAttributeType {
            case .some(.typeSymbolicLink):
                // Skipped, never reported. The path-based enumerator does not resolve
                // symbolic links, so there is nothing to descend into either.
                continue
            case .some(.typeRegular):
                let relative = "assets/\(subpath)"
                if !referenced.contains(relative) {
                    orphans.append(try RelativeProjectPath(relative))
                }
            default:
                continue
            }
        }
        return orphans.sorted { $0.rawValue < $1.rawValue }
    }

    public func journal(limit: Int = 100) throws -> [JournalEntry] {
        try repository().journal(limit: limit)
    }

    public func pendingReviewCount() throws -> Int {
        try repository().pendingReviewCount()
    }

    public func extractionProtectionSummary() throws -> ExtractionProtectionSummary {
        try repository().extractionProtectionSummary()
    }

    public func runs() throws -> [RunSummary] {
        try repository().runs()
    }

    public func jobHistory() throws -> [Job] {
        try repository().jobs()
    }

    public func disclosureAcknowledgedAt() throws -> Date? {
        try repository().disclosureAcknowledgedAt()
    }

    // MARK: - JobManaging

    /// `cache/jobs/<run-id>/workspace/` — shared by every child of the run (§4.1).
    public func prepareRunWorkspace(runID: UUID) throws -> ProjectRunWorkspace {
        guard database != nil else { throw ProjectStoreError.sessionClosed }
        let workspacePath = try RelativeProjectPath("cache/jobs/\(runID.uuidString)/workspace")
        let workspaceURL = try workspacePath.resolve(in: layout.rootURL)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        return ProjectRunWorkspace(
            workspaceURL: URL(fileURLWithPath: workspaceURL.path, isDirectory: true),
            workspaceRelativePath: workspacePath
        )
    }

    /// `cache/jobs/<run-id>/<job-id>/{input.txt,result.json}` and
    /// `logs/jobs/<job-id>.jsonl` (§4.1). A childless task passes `runID == jobID`.
    public func prepareChildPaths(runID: UUID, jobID: UUID) throws -> ProjectJobPaths {
        guard database != nil else { throw ProjectStoreError.sessionClosed }
        let directory = "cache/jobs/\(runID.uuidString)/\(jobID.uuidString)"
        let inputPath = try RelativeProjectPath("\(directory)/input.txt")
        let resultPath = try RelativeProjectPath("\(directory)/result.json")
        let logPath = try RelativeProjectPath("logs/jobs/\(jobID.uuidString).jsonl")
        let inputURL = try inputPath.resolve(in: layout.rootURL)
        let resultURL = try resultPath.resolve(in: layout.rootURL)
        let logURL = try logPath.resolve(in: layout.rootURL)
        try FileManager.default.createDirectory(
            at: resultURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return ProjectJobPaths(
            inputURL: inputURL,
            resultURL: resultURL,
            logURL: logURL,
            inputRelativePath: inputPath,
            resultRelativePath: resultPath,
            logRelativePath: logPath
        )
    }

    public func createJob(_ request: JobRequest) throws -> Job {
        try repository().createJob(request, projectID: initialProject.id)
    }

    public func transitionJob(
        id: UUID,
        to state: Job.State,
        progress: String,
        failureCode: String?,
        failureMessage: String?
    ) throws -> Job {
        try repository().transitionJob(
            id: id,
            to: state,
            progress: progress,
            failureCode: failureCode,
            failureMessage: failureMessage
        )
    }

    /// Records usage and completes the job in one transaction.
    public func completeJob(id: UUID, usage: JobUsage, progress: String) throws -> Job {
        try repository().completeJob(id: id, usage: usage, progress: progress)
    }

    public func setEffectiveModel(jobID: UUID, effectiveModel: String?) throws {
        try repository().updateEffectiveModel(jobID: jobID, effectiveModel: effectiveModel)
    }

    public func setApplyReport(jobID: UUID, _ report: ApplyReport) throws {
        try repository().setApplyReport(jobID: jobID, report: report)
    }

    public func setManifestReport(jobID: UUID, _ report: ManifestApplyReport) throws {
        try repository().setManifestReport(jobID: jobID, report: report)
    }

    /// Clear Job Cache over **both** cache roots (PHASE3_DESIGN §3.5, §4.1): `cache/jobs`
    /// keeps its shipped filtered walk — the `workspace || input.txt` predicate is what
    /// lets result JSON survive, and it stays scoped to this root — while `cache/skills/`
    /// is a **second root swept unfiltered**: nothing under
    /// `cache/skills/<skill_id>/<tree-digest-prefix>/` has a workspace component or an
    /// `input.txt`, so reusing the filtered loop there would provably remove zero files.
    /// `ensureJobCacheCanBeCleared`'s no-active-run scope covers both roots by job state.
    public func clearJobCache() throws -> ClearedCacheSummary {
        guard database != nil else { throw ProjectStoreError.sessionClosed }
        try repository().ensureJobCacheCanBeCleared()
        let jobs = try sweepCacheRoot(
            layout.rootURL.appending(path: "cache/jobs", directoryHint: .isDirectory),
            filtered: true
        )
        // PHASE3_DESIGN §3.5: the skill-copy sweep, whole subtree.
        let skills = try sweepCacheRoot(
            layout.rootURL.appending(path: "cache/skills", directoryHint: .isDirectory),
            filtered: false
        )
        return ClearedCacheSummary(
            bytesFreed: jobs.bytesFreed + skills.bytesFreed,
            filesRemoved: jobs.filesRemoved + skills.filesRemoved
        )
    }

    private func sweepCacheRoot(_ root: URL, filtered: Bool) throws -> ClearedCacheSummary {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ClearedCacheSummary(bytesFreed: 0, filesRemoved: 0)
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let files = (FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )?.allObjects.compactMap { $0 as? URL } ?? []).sorted {
            $0.pathComponents.count > $1.pathComponents.count
        }
        var bytes: Int64 = 0
        var count = 0
        for url in files {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if filtered {
                let values = try url.resourceValues(forKeys: keys)
                let isWorkspace = url.pathComponents.contains("workspace")
                let isInput = url.lastPathComponent == "input.txt"
                guard isWorkspace || isInput else { continue }
                if values.isRegularFile == true {
                    bytes += Int64(values.fileSize ?? 0)
                    count += 1
                }
            } else {
                let values = try url.resourceValues(forKeys: keys)
                if values.isRegularFile == true {
                    bytes += Int64(values.fileSize ?? 0)
                    count += 1
                }
            }
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        return ClearedCacheSummary(bytesFreed: bytes, filesRemoved: count)
    }

    public func acknowledgeDisclosure() throws {
        try repository().acknowledgeDisclosure()
    }

    // MARK: - ExtractionApplying

    public func applyExtractionRun(
        _ proposal: ExtractionProposal,
        runJobID: UUID,
        usage: JobUsage
    ) throws -> ApplyReport {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try ExtractionApplier.apply(
                proposal,
                runJobID: runJobID,
                usage: usage,
                in: db
            )
        }
    }

    // MARK: - ManifestApplying

    /// §8.4's apply: one transaction, one actor, one completion (PHASE2_DESIGN §8.4, §8.5).
    public func applyManifestRun(
        _ proposal: ManifestProposal,
        runJobID: UUID,
        usage: JobUsage
    ) throws -> ManifestApplyReport {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try ManifestApplier.apply(
                proposal,
                runJobID: runJobID,
                usage: usage,
                in: db
            )
        }
    }

    // MARK: - PromptApplying

    /// §8.4's apply: one transaction, one actor, one invertible entry, one completion
    /// (PHASE3_DESIGN §8.4; Plan 016 contract C).
    public func applyAssetPromptRun(
        _ proposal: AssetPromptProposal,
        runJobID: UUID,
        usage: JobUsage
    ) throws -> AssetPromptApplyOutcome {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try AssetPromptApplier.apply(
                proposal,
                runJobID: runJobID,
                usage: usage,
                in: db
            )
        }
    }

    // MARK: - ScenePromptApplying

    /// §8.4's apply at scene scale: one transaction, one actor, one invertible entry, one
    /// completion (PHASE5_DESIGN §8.4; Plan 021 contract C).
    public func applyScenePromptRun(
        _ proposal: ScenePromptProposal,
        runJobID: UUID,
        usage: JobUsage
    ) throws -> ScenePromptApplyOutcome {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try ScenePromptApplier.apply(
                proposal,
                runJobID: runJobID,
                usage: usage,
                in: db
            )
        }
    }

    public func applyScenePromptSetRun(
        _ proposal: ScenePromptSetProposal,
        runJobID: UUID,
        usage: JobUsage
    ) throws -> ScenePromptSetApplyOutcome {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try ScenePromptApplier.applySet(
                proposal,
                runJobID: runJobID,
                usage: usage,
                in: db
            )
        }
    }

    // MARK: - ScreenplayImporting

    /// §5.5's replace guard: `false` once the project holds a protected fact or a lock.
    public func canReplaceScreenplay() throws -> Bool {
        try repository().canReplaceScreenplay()
    }

    /// Imports (or, over an existing script, **replaces**) a screenplay.
    ///
    /// Atomicity is a staged copy plus one transaction, because a filesystem copy and a
    /// database write cannot share one: the original is copied into `screenplay/` first
    /// and nothing references it until the transaction commits; any throw from the
    /// transaction deletes the staged file before rethrowing. The source file is never
    /// touched.
    @discardableResult
    public func importScreenplay(from url: URL, actor: MutationActor) throws -> ImportSummary {
        guard database != nil else { throw ProjectStoreError.sessionClosed }
        let document = try ScreenplayImporter.load(url: url)
        return try importScreenplay(document, originalURL: url, actor: actor)
    }

    /// Internal mapper used after the public path parses and validates the source file.
    @discardableResult
    func importScreenplay(
        _ document: ScreenplayDocument,
        originalURL: URL,
        actor: MutationActor
    ) throws -> ImportSummary {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let repository = ProjectRepository(database: database)

        // §5.5 / §3.9: nothing may be imported while a run could still write.
        guard try !repository.hasActiveOrPausedRun() else {
            throw ProjectStoreError.importRefusedDuringRun
        }

        let previousScript = try repository.script()
        if previousScript != nil {
            guard try repository.canReplaceScreenplay() else {
                throw ProjectStoreError.replaceRefusedAfterWork
            }
        }

        // The staged copy goes in through `BundleContainment` (PHASE2_DESIGN §4.1): the
        // bytes are written descriptor-relative under a `screenplay/` directory walked with
        // `O_NOFOLLOW`, so a symlinked component — or a symlinked leaf — refuses the import
        // instead of redirecting it outside the bundle.
        let containment = BundleContainment(rootURL: layout.rootURL)
        let displayName = originalURL.lastPathComponent
        let relativePath = try stagedDestination(for: displayName, in: containment)
        let original = try Data(contentsOf: originalURL)
        try containment.write(original, to: relativePath)

        let projectID = initialProject.id
        let assetID = UUID()
        let scriptID = UUID()
        let operation: EditOperation = previousScript.map {
            .replaceScreenplay(
                scriptID: scriptID,
                previousScriptID: $0.id,
                displayName: displayName
            )
        } ?? .importScreenplay(scriptID: scriptID, displayName: displayName)
        do {
            let written = try database.queue.write { db -> ScreenplayWriteResult in
                try db.execute(
                    sql: """
                        INSERT INTO project_assets (id, project_id, kind, relative_path, sha256, created_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        assetID.uuidString, projectID.uuidString,
                        ProjectAsset.Kind.screenplay.rawValue, relativePath.rawValue,
                        original.sha256Hex, UTCDate.string(from: Date()),
                    ]
                )
                let outcome = try EditPrimitives.performDetailed(
                    operation,
                    actor: actor,
                    jobID: actor.jobID,
                    input: ScreenplayMutationInput(
                        document: document,
                        projectID: projectID,
                        scriptID: scriptID,
                        displayName: displayName,
                        assetID: assetID,
                        assetRelativePath: relativePath
                    ),
                    in: db
                )
                return outcome.effect.screenplayWrite ?? ScreenplayWriteResult()
            }
            return ImportSummary(
                scriptID: scriptID,
                displayName: displayName,
                format: document.format,
                relativePath: relativePath,
                sceneCount: written.sceneCount,
                sequenceCount: written.sequenceCount,
                characterNames: written.characterNames,
                locationNames: written.locationNames,
                warnings: document.warnings,
                replacedPreviousScript: previousScript != nil
            )
        } catch {
            // The staged copy is deleted before rethrowing: a filesystem copy and a
            // database write cannot share a transaction. The removal is descriptor-relative
            // too — `unlinkat` takes the directory entry, never a link's target.
            _ = try? containment.removeIfPresent(at: relativePath)
            throw error
        }
    }

    /// The name the original is staged under: the source's own name, then `-2`, `-3`, …
    /// on collision (§5.5). Only the stem is suffixed, so the extension keeps sniffing.
    ///
    /// The collision probe is the containment walk, not `FileManager`: a symlinked
    /// `screenplay/` or a symlinked candidate leaf **throws** here rather than being
    /// side-stepped into a `-2` name, so the import refuses the planted link (§4.1).
    private func stagedDestination(
        for fileName: String,
        in containment: BundleContainment
    ) throws -> RelativeProjectPath {
        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = fileName
        var suffix = 2
        while true {
            let path = try RelativeProjectPath("screenplay/\(candidate)")
            if try containment.entryKind(at: path) == .missing { return path }
            candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            suffix += 1
        }
    }

    // MARK: - ProjectObserving

    public func changes() -> AsyncStream<ProjectChange> {
        guard let database else { return AsyncStream { $0.finish() } }
        let hub = observationHub ?? ProjectObservationHub(database: database)
        observationHub = hub
        return hub.makeStream()
    }

    // MARK: - Lifecycle

    public func resolve(_ path: RelativeProjectPath) throws -> URL {
        guard database != nil else { throw ProjectStoreError.sessionClosed }
        return try path.resolve(in: layout.rootURL)
    }

    public func close() throws {
        guard let database else { return }
        // Streams are finished **before** the checkpoint so no observation can fire
        // against a database this session is about to let go of (§3.9a).
        observationHub?.finish()
        observationHub = nil
        try database.checkpoint()
        self.database = nil
    }

    private func repository() throws -> ProjectRepository {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return ProjectRepository(database: database)
    }
}
