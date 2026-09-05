import Foundation
import FilmScript
import GRDB

struct ProjectRepository: Sendable {
    let database: ProjectDatabase

    /// The one project row's id — every project-scoped operation needs it.
    static func requireProjectID(in db: Database) throws -> UUID {
        let raw = try String.fetchOne(db, sql: "SELECT id FROM projects")
        guard let id = raw.flatMap(UUID.init(uuidString:)) else {
            throw ProjectStoreError.missingProject
        }
        return id
    }

    /// Creates the one `projects` row of an **empty** project (§4.1), and seeds the
    /// current requirement template.
    ///
    /// A fresh bundle runs every migration over an empty database, so migration seeders
    /// find no project row. Schema v11's current-policy seeder runs here in the same
    /// transaction as the insert. Schemas 12–13 do not change the requirement template,
    /// so v11 remains the current template seeder.
    func initialize(projectName: String) throws {
        let timestamp = UTCDate.string(from: Date())
        let projectID = UUID().uuidString
        try database.queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO projects (
                        id, name, bundle_schema_version, current_script_id,
                        disclosure_acknowledged_at, created_at, updated_at
                    ) VALUES (?, ?, ?, NULL, NULL, ?, ?)
                    """,
                arguments: [
                    projectID, projectName, FilmCoreVersion.bundleSchema,
                    timestamp, timestamp,
                ]
            )
            try SchemaV11.seedRequirementTemplate(projectID: projectID, now: timestamp, in: db)
        }
    }

    func validateProject() throws -> Project {
        try database.queue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM projects")
            guard rows.count == 1 else { throw ProjectStoreError.missingProject }
            let project = try decodeProject(rows[0])
            guard project.bundleSchemaVersion == FilmCoreVersion.bundleSchema else {
                throw ProjectStoreError.invalidBundle
            }
            return project
        }
    }

    /// The project's script, resolved through `projects.current_script_id`; `nil` until a
    /// screenplay is imported.
    func script() throws -> Script? {
        try database.queue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT scripts.* FROM scripts
                JOIN projects ON projects.current_script_id = scripts.id
                """) else { return nil }
            return try decodeScript(row)
        }
    }

    /// The warnings persisted at import or migration, for `UpgradeSummary`.
    func persistedParseWarnings() throws -> [ParseWarning] {
        try database.queue.read { db in
            var warnings: [ParseWarning] = []
            for json in try String.fetchAll(db, sql: "SELECT parse_warnings_json FROM scripts ORDER BY created_at") {
                warnings.append(contentsOf: decodeWarnings(json))
            }
            return warnings
        }
    }

    func createJob(_ request: JobRequest, projectID: UUID) throws -> Job {
        try database.queue.write { db in
            // Phase 0's "one active job" becomes "one active **run**" (§3.9): a second
            // parent is refused while a parent is non-terminal and not `paused`; children
            // of the active run may execute concurrently.
            if request.parentJobID == nil {
                let activeRuns = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM jobs
                        WHERE parent_job_id IS NULL
                          AND state NOT IN ('completed','failed','cancelled','paused')
                        """
                ) ?? 0
                guard activeRuns == 0 else { throw ProjectStoreError.mutationInProgress }
                // §3.6's one-run rule: analysis is a one-time bootstrap, so a second
                // `extractScreenplay` parent is refused once one has *applied*. Only
                // `completed` counts — a failed or cancelled attempt applied nothing (apply
                // and the parent's completion share one transaction), so it may retry; a
                // paused run resumes as itself rather than creating a parent; and reverting
                // leaves the job row `completed`, so it cannot reopen eligibility. Enforced
                // here, not in the UI, so no path around it exists.
                //
                // The gate is scoped to the **script**, not the project, because §5.5's
                // Replace deletes `scripts` and `entities` but not `jobs`: a project-scoped
                // count would see the superseded run and strand a freshly replaced
                // screenplay as parsed-but-unanalyzable. Replace is itself allowed only
                // while no protected fact or lock exists and it wipes every entity, so the
                // screenplay it installs has never been analyzed and gets its one run —
                // it cannot stack a second analysis onto curated data.
                if request.task == Job.extractionTask, let scriptID = request.scriptID {
                    let applied = try completedRunCount(
                        task: Job.extractionTask, scriptID: scriptID, in: db
                    )
                    guard applied == 0 else {
                        throw ProjectStoreError.extractionAlreadyApplied
                    }
                    // §3.6's second half: a completed manifest run **permanently closes
                    // extraction for that screenplay**. Spending the analysis afterwards
                    // would change canonical facts underneath requirements, basis
                    // citations, and approvals already built on them.
                    guard try completedRunCount(
                        task: Job.manifestTask, scriptID: scriptID, in: db
                    ) == 0 else {
                        throw ProjectStoreError.extractionClosedByManifest
                    }
                }
                // §3.6/§8.1's manifest gates, script-scoped for exactly the reason the
                // extraction latch is: Replace deletes `scripts` and `entities` but not
                // `jobs`, so a project-scoped gate would strand a replaced screenplay that
                // could then be neither analyzed nor manifested.
                if request.task == Job.manifestTask, let scriptID = request.scriptID {
                    // Run-once: a failed or cancelled attempt applied nothing (apply and
                    // the parent's completion share one transaction), so it may retry.
                    guard try completedRunCount(
                        task: Job.manifestTask, scriptID: scriptID, in: db
                    ) == 0 else {
                        throw ProjectStoreError.manifestAlreadyApplied
                    }
                    // Refused while any extraction run is non-terminal **or paused**: the
                    // one-active-run rule above exempts `paused`, and a paused run may
                    // otherwise resume and apply after the manifest exists.
                    let liveExtraction = try Int.fetchOne(
                        db,
                        sql: """
                            SELECT COUNT(*) FROM jobs
                            WHERE parent_job_id IS NULL
                              AND task = ?
                              AND state NOT IN ('completed','failed','cancelled')
                              AND script_id = ?
                            """,
                        arguments: [Job.extractionTask, scriptID.uuidString]
                    ) ?? 0
                    guard liveExtraction == 0 else {
                        throw ProjectStoreError.manifestRefusedDuringExtraction
                    }
                }
                // PHASE3_DESIGN §8.1's paused-run gate for prompt runs: a prompt is refused
                // while any extraction or manifest run is non-terminal or paused — Phase
                // 2 §3.6's own gate, adopted for the same recorded reason. Prompt runs are
                // never latched (§3.1): no run-once rule of their own.
                if request.task == Job.assetPromptTask {
                    let liveBootstraps = try Int.fetchOne(
                        db,
                        sql: """
                            SELECT COUNT(*) FROM jobs
                            WHERE parent_job_id IS NULL
                              AND task IN (?, ?)
                              AND state NOT IN ('completed','failed','cancelled')
                            """,
                        arguments: [Job.extractionTask, Job.manifestTask]
                    ) ?? 0
                    guard liveBootstraps == 0 else {
                        throw ProjectStoreError.promptRunRequiresIdleBootstraps
                    }
                }
            }
            try db.execute(
                sql: """
                    INSERT INTO jobs (
                        id, project_id, task, engine, engine_version, requested_model,
                        schema_version, input_sha256, state, progress_stage,
                        log_relative_path, result_relative_path,
                        parent_job_id, chunk_index, chunk_count, attempt_index,
                        supersedes_job_id, script_id, script_sha256
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'queued', 'Queued', ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    request.id.uuidString, projectID.uuidString, request.task,
                    request.engine, request.engineVersion, request.requestedModel,
                    request.schemaVersion, request.inputSHA256,
                    request.logRelativePath.rawValue, request.resultRelativePath.rawValue,
                    request.parentJobID?.uuidString, request.chunkIndex, request.chunkCount,
                    request.attemptIndex, request.supersedesJobID?.uuidString,
                    request.scriptID?.uuidString, request.scriptSHA256,
                ]
            )
            return try fetchJob(request.id, in: db)
        }
    }

    /// Completed parent runs of one task for one **script** — the shared shape of §3.6's
    /// three bootstrap gates. Only `completed` counts: a failed or cancelled attempt
    /// applied nothing, a paused run resumes as itself rather than creating a parent, and
    /// reverting leaves the job row `completed` so it cannot reopen eligibility.
    private func completedRunCount(task: String, scriptID: UUID, in db: Database) throws -> Int {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM jobs
                WHERE parent_job_id IS NULL
                  AND task = ?
                  AND state = 'completed'
                  AND script_id = ?
                """,
            arguments: [task, scriptID.uuidString]
        )
        let jobs = try rows.map(decodeJob)
        if task == Job.extractionTask {
            return jobs.filter(\.didApplyExtraction).count
        }
        return jobs.count
    }

    func transitionJob(
        id: UUID,
        to next: Job.State,
        progress: String,
        failureCode: String? = nil,
        failureMessage: String? = nil
    ) throws -> Job {
        try database.queue.write { db in
            let current = try fetchJob(id, in: db)
            guard current.state.canTransition(to: next) else {
                if next == .cancelled && current.state == .committing {
                    throw ProjectStoreError.cancellationTooLate
                }
                throw ProjectStoreError.illegalJobTransition(from: current.state, to: next)
            }
            // `validating → completed` is syntactically legal for every job, but a parent
            // owns the canonical transaction and must go through `committing` (§3.9).
            if current.state == .validating, next == .completed, current.parentJobID == nil {
                throw ProjectStoreError.illegalJobTransition(from: .validating, to: .completed)
            }
            let startedAt = next == .running && current.startedAt == nil ? UTCDate.string(from: Date()) : nil
            let endedAt = next.isTerminal ? UTCDate.string(from: Date()) : nil
            try db.execute(
                sql: """
                    UPDATE jobs
                    SET state = ?, progress_stage = ?,
                        started_at = COALESCE(started_at, ?),
                        ended_at = COALESCE(?, ended_at),
                        failure_code = ?, failure_message = ?
                    WHERE id = ?
                    """,
                arguments: [next.rawValue, progress, startedAt, endedAt, failureCode, failureMessage, id.uuidString]
            )
            return try fetchJob(id, in: db)
        }
    }

    /// Records usage and transitions to `completed` in one transaction — the surviving half
    /// of the deleted `applyAnalysis` (Plan 003 contract B).
    func completeJob(id: UUID, usage: JobUsage, progress: String) throws -> Job {
        try database.queue.write { db in
            let current = try fetchJob(id, in: db)
            guard current.state.canTransition(to: .completed) else {
                throw ProjectStoreError.illegalJobTransition(from: current.state, to: .completed)
            }
            if current.state == .validating, current.parentJobID == nil {
                throw ProjectStoreError.illegalJobTransition(from: .validating, to: .completed)
            }
            try db.execute(
                sql: """
                    UPDATE jobs SET state = 'completed', progress_stage = ?,
                        input_tokens = ?, cached_input_tokens = ?, cache_write_input_tokens = ?,
                        output_tokens = ?, reasoning_output_tokens = ?, ended_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    progress,
                    usage.inputTokens, usage.cachedInputTokens, usage.cacheWriteInputTokens,
                    usage.outputTokens, usage.reasoningOutputTokens,
                    UTCDate.string(from: Date()), id.uuidString,
                ]
            )
            return try fetchJob(id, in: db)
        }
    }

    func updateEffectiveModel(jobID: UUID, effectiveModel: String?) throws {
        try database.queue.write { db in
            try db.execute(
                sql: "UPDATE jobs SET effective_model = ? WHERE id = ?",
                arguments: [effectiveModel, jobID.uuidString]
            )
        }
    }

    /// The §8.2 input for one requirement (PHASE3_DESIGN §8.1). A read: opens nothing,
    /// writes nothing — the builder runs inside the caller's read transaction.
    func assetPromptInput(requirementID: UUID) throws -> AssetPromptInputSnapshot {
        try database.queue.read { db in
            try AssetPromptInputBuilder.snapshot(requirementID: requirementID, in: db)
        }
    }

    /// The §8.2 input for one scene (PHASE5_DESIGN §8.1, §8.2). A read: opens nothing,
    /// writes nothing — the builder runs inside the caller's read transaction. FilmBrain
    /// calls this when launching a `generateScenePrompt` run; §8.4 step 0 rebuilds the
    /// same value inside the apply transaction.
    func scenePromptInput(sceneID: UUID) throws -> ScenePromptInputSnapshot {
        try database.queue.read { db in
            try ScenePromptInputBuilder.snapshot(sceneID: sceneID, in: db)
        }
    }

    func setApplyReport(jobID: UUID, report: ApplyReport) throws {
        try setReport(jobID: jobID, task: Job.extractionTask, report: report)
    }

    /// The manifest run's typed door onto the same column (PHASE2_DESIGN §7.5, §8.5).
    func setManifestReport(jobID: UUID, report: ManifestApplyReport) throws {
        try setReport(jobID: jobID, task: Job.manifestTask, report: report)
    }

    /// The one writer of `jobs.apply_report`, gated on **task** as well as on
    /// parent-and-not-completed.
    ///
    /// One nullable JSON column carries two report types (§8.5), so the task gate is what
    /// makes a wrong-task report unrepresentable rather than merely undecodable: a
    /// `ManifestApplyReport` can never land on an extraction run, and an `ApplyReport`
    /// never on a manifest one. The completed-job refusal stands as before — a run's
    /// post-apply rewrite happens **inside** the apply transaction, not through this door.
    private func setReport(jobID: UUID, task expected: String, report: some Encodable) throws {
        try database.queue.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT parent_job_id, state, task FROM jobs WHERE id = ?",
                arguments: [jobID.uuidString]
            ) else { throw ProjectStoreError.jobNotFound }
            let parentID: String? = row["parent_job_id"]
            let state = Job.State(rawValue: row["state"]) ?? .failed
            guard parentID == nil, state != .completed else {
                throw ProjectStoreError.illegalJobTransition(from: state, to: state)
            }
            let task: String = row["task"]
            guard task == expected else {
                throw ProjectStoreError.wrongJobTask(expected: expected, found: task)
            }
            let json = String(decoding: try JournalCoding.encoder.encode(report), as: UTF8.self)
            try db.execute(
                sql: "UPDATE jobs SET apply_report = ? WHERE id = ?",
                arguments: [json, jobID.uuidString]
            )
        }
    }

    /// The **internal `in db:` report primitive** (PHASE2_DESIGN §8.5).
    ///
    /// The public `setManifestReport` opens its own transaction and refuses a completed
    /// job, so it can only ever be the pre-apply zero-counter write; the post-apply rewrite
    /// has to land inside the apply transaction, beside the parent's completion, the way
    /// extraction's applier writes `apply_report` in its completion UPDATE. It takes the
    /// caller's `Database` handle and opens nothing, exactly like everything under
    /// `Editing/`.
    static func writeManifestReport(
        _ report: ManifestApplyReport,
        jobID: UUID,
        in db: Database
    ) throws {
        let json = String(decoding: try JournalCoding.encoder.encode(report), as: UTF8.self)
        try db.execute(
            sql: "UPDATE jobs SET apply_report = ? WHERE id = ? AND task = ?",
            arguments: [json, jobID.uuidString, Job.manifestTask]
        )
        guard db.changesCount == 1 else {
            throw ProjectStoreError.databaseCommit("The manifest report could not be written.")
        }
    }

    /// The **internal `in db:` report primitive** for a prompt run (PHASE3_DESIGN §8.4
    /// step 3) — the `writeManifestReport` shape verbatim.
    ///
    /// §8.4 writes the report **inside** the apply transaction, and Phase 3 has no
    /// pre-apply zero-counter write, so the applier's real caller is this primitive: it
    /// takes the caller's `Database` handle and opens nothing.
    static func writeAssetPromptReport(
        _ report: AssetPromptApplyReport,
        jobID: UUID,
        in db: Database
    ) throws {
        let json = String(decoding: try JournalCoding.encoder.encode(report), as: UTF8.self)
        try db.execute(
            sql: "UPDATE jobs SET apply_report = ? WHERE id = ? AND task = ?",
            arguments: [json, jobID.uuidString, Job.assetPromptTask]
        )
        guard db.changesCount == 1 else {
            throw ProjectStoreError.databaseCommit("The prompt report could not be written.")
        }
    }

    /// The **internal `in db:` report primitive** for a scene-prompt run (PHASE5_DESIGN
    /// §8.4 step 3) — the `writeAssetPromptReport` shape verbatim. The §8.4 apply writes
    /// the report **inside** its transaction, beside the parent's completion.
    static func writeScenePromptReport(
        _ report: ScenePromptApplyReport,
        jobID: UUID,
        in db: Database
    ) throws {
        let json = String(decoding: try JournalCoding.encoder.encode(report), as: UTF8.self)
        try db.execute(
            sql: "UPDATE jobs SET apply_report = ? WHERE id = ? AND task = ?",
            arguments: [json, jobID.uuidString, Job.scenePromptTask]
        )
        guard db.changesCount == 1 else {
            throw ProjectStoreError.databaseCommit(
                "The scene prompt report could not be written."
            )
        }
    }

    func ensureJobCacheCanBeCleared() throws {
        try database.queue.read { db in
            let active = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM jobs WHERE state NOT IN ('completed','failed','cancelled')"
            ) ?? 0
            guard active == 0 else { throw ProjectStoreError.mutationInProgress }
        }
    }

    func jobs() throws -> [Job] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM jobs ORDER BY rowid").map(decodeJob)
        }
    }

    /// §3.9's abandoned-job reaping, run by `ProjectBundle.open`.
    ///
    /// A bundle has a single writer, so a job left non-terminal by a previous launch can
    /// only be abandoned: the process that owned it is gone. Calyx's identity check is
    /// deliberately **not** adopted — there is no pid/host column to verify against, and
    /// inventing one would claim a multi-writer guarantee this storage does not make.
    /// `paused` survives relaunch by contract and is never reaped.
    @discardableResult
    func reapAbandonedJobs() throws -> Int {
        try database.queue.write { db in
            try db.execute(
                sql: """
                    UPDATE jobs
                    SET state = 'failed', progress_stage = 'Abandoned',
                        failure_code = 'abandoned',
                        failure_message = 'The process running this job did not finish.',
                        ended_at = COALESCE(ended_at, ?)
                    WHERE state NOT IN ('completed','failed','cancelled','paused')
                    """,
                arguments: [UTCDate.string(from: Date())]
            )
            return db.changesCount
        }
    }

    /// `true` while any run is non-terminal **or** paused — import and replace are
    /// refused then (§5.5).
    func hasActiveOrPausedRun() throws -> Bool {
        try database.queue.read { db in
            (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM jobs WHERE state NOT IN ('completed','failed','cancelled')"
            ) ?? 0) > 0
        }
    }

    /// §5.5's replace guard: refused once any row is human-sourced, any AI row has been
    /// accepted, or any lock exists.
    func canReplaceScreenplay() throws -> Bool {
        try database.queue.read { db in try Self.canReplaceScreenplay(in: db) }
    }

    static func canReplaceScreenplay(in db: Database) throws -> Bool {
        // Any media at all refuses Replace outright, whatever its provenance
        // (PHASE2_DESIGN §7.5): replace destroys the scenes the manifest is anchored to,
        // and an imported file is protected work by its existence — an `assets` or
        // `asset_versions` row is only ever created by a human import or, since
        // PHASE3_DESIGN §3.7/§6.1, by a prompt run's own anchor insert — but the gate
        // counts rows **unconditionally** ("whatever its provenance"), so that widening
        // of who may create an asset row changes nothing here (§7.3's no-widening chain).
        for table in ["assets", "asset_versions"] {
            if (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0) > 0 { return false }
        }
        // Every table carrying PROV, plus the scene synopsis field and `evidence`
        // (which has `source` but no review state).
        //
        // The v4 fact tables join the enumeration (§7.5). `asset_requirement_basis` is
        // deliberately **not** among them: it carries no `review_state` at all — a reduced
        // citation block like `evidence`'s — and a basis row exists only alongside the
        // requirement it justifies, so a protected basis row without a protected
        // requirement is unrepresentable. `asset_requirement_types` is likewise absent:
        // template rows are settings, seeded identically into every project, and are not
        // work the filmmaker would lose to a Replace.
        let provTables = [
            "sequences", "entities", "entity_aliases", "scene_entities",
            "entity_states", "continuity_events", "entity_relationships",
            "asset_requirements", "asset_requirement_scenes", "asset_dependencies",
        ]
        for table in provTables {
            let protected = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM \(table)
                    WHERE source = 'human' OR (source = 'ai' AND review_state = 'accepted')
                    """
            ) ?? 0
            if protected > 0 { return false }
        }
        if (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM evidence WHERE source = 'human'") ?? 0) > 0 {
            return false
        }
        if (try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM scenes
                WHERE synopsis_source = 'human'
                   OR (synopsis_source = 'ai' AND synopsis_review_state = 'accepted')
                """
        ) ?? 0) > 0 { return false }
        if (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM locks") ?? 0) > 0 { return false }
        return true
    }

    /// Records the first-run privacy acknowledgement (§9); a second call is a no-op.
    func acknowledgeDisclosure(at date: Date = Date()) throws {
        try database.queue.write { db in
            try db.execute(
                sql: """
                    UPDATE projects
                    SET disclosure_acknowledged_at = COALESCE(disclosure_acknowledged_at, ?),
                        updated_at = ?
                    """,
                arguments: [UTCDate.string(from: date), UTCDate.string(from: date)]
            )
        }
    }

    private func fetchJob(_ id: UUID, in db: Database) throws -> Job {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM jobs WHERE id = ?", arguments: [id.uuidString]) else {
            throw ProjectStoreError.jobNotFound
        }
        return try decodeJob(row)
    }
}
