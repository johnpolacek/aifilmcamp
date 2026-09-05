import Foundation
import GRDB

/// §8.4's apply at scene scale (PHASE5_DESIGN §8.4; Plan 021 contract C).
/// `AssetPromptApplier`'s shape verbatim — step 0's digest guard replacing every
/// per-reference existence check, one invertible journal entry through the engine, the
/// report written through the internal `in db:` primitive (`writeScenePromptReport`) —
/// never the public typed door, which opens its own transaction — and the parent
/// completed **inside** the transaction with its usage.
enum ScenePromptApplier {
    static func apply(
        _ proposal: ScenePromptProposal,
        runJobID: UUID,
        usage: JobUsage,
        in db: Database
    ) throws -> ScenePromptApplyOutcome {
        let actor = MutationActor.ai(jobID: runJobID)
        let started = ContinuousClock.now

        // The parent, its task, and the digest it recorded at launch.
        guard let jobRow = try Row.fetchOne(
            db,
            sql: "SELECT state, parent_job_id, task, input_sha256 FROM jobs WHERE id = ?",
            arguments: [runJobID.uuidString]
        ) else { throw ProjectStoreError.jobNotFound }
        let task: String = jobRow["task"]
        guard task == Job.scenePromptTask else {
            throw ProjectStoreError.wrongJobTask(expected: Job.scenePromptTask, found: task)
        }
        let state = Job.State(rawValue: jobRow["state"]) ?? .failed
        let parentID: String? = jobRow["parent_job_id"]
        guard parentID == nil, state == .committing else {
            throw ProjectStoreError.illegalJobTransition(from: state, to: .completed)
        }

        // §8.4 step 0. One comparison instead of a dozen predicates: equal ⟹ the scene,
        // its plan, every reference's approved bytes, the style bible, and the profile
        // still stand exactly as validated; different ⟹ nothing is applied.
        let recordedDigest: String = jobRow["input_sha256"]
        let rebuilt = try ScenePromptInputBuilder.snapshot(
            sceneID: proposal.sceneID, in: db
        )
        guard rebuilt.digest == recordedDigest else {
            throw ProjectStoreError.scenePromptInputChangedDuringRun
        }
        let cleanBasis = try ScenePromptInputBuilder.snapshot(
            sceneID: proposal.sceneID,
            creativeDirectionOverride: "",
            in: db
        )

        // Steps 1–2: `attachGeneratedScenePrompt` re-checks the cheap preconditions
        // outside the digest (scene still counted, profile still cataloged) and performs
        // the **one invertible entry** — citations derived in-op from §3.2's plan over
        // the state the digest was computed against (§3.9 is the AI actor's entire write
        // surface). One-time direction is consumed by that same transaction; the prompt
        // row therefore uses the clean basis digest while the report retains the exact
        // request digest.
        let promptID = UUID()
        let skillIdentity = AssetPromptSkillIdentity(
            id: proposal.settings.skillID,
            entryPath: proposal.settings.skillEntryPath,
            entrySHA256: proposal.settings.skillEntrySHA256
        )
        let entry = try EditPrimitives.perform(
            .attachGeneratedScenePrompt(
                promptID: promptID,
                sceneID: proposal.sceneID,
                body: proposal.body,
                guidance: proposal.guidance,
                durationSeconds: proposal.durationSeconds,
                aspectRatio: proposal.aspectRatio,
                resolution: proposal.resolution,
                inputDigest: cleanBasis.digest,
                inputFormatVersion: ScenePromptInputBuilder.schemaVersion,
                skillIdentity: skillIdentity
            ),
            actor: actor,
            jobID: runJobID,
            in: db
        )

        // Step 3: the report and usage land with the parent's completion, in this
        // transaction — the `writeAssetPromptReport` shape verbatim.
        let promptNumber = try Int.fetchOne(
            db,
            sql: "SELECT prompt_number FROM scene_prompts WHERE id = ?",
            arguments: [promptID.uuidString]
        ) ?? 0
        let referenceCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM scene_prompt_references WHERE prompt_id = ?",
            arguments: [promptID.uuidString]
        ) ?? 0
        var report = ScenePromptApplyReport(
            sceneID: proposal.sceneID,
            targetProfile: TargetProfileCatalog.defaultProfileID,
            setID: promptID,
            setNumber: promptNumber,
            cardCount: 1,
            referenceCount: referenceCount,
            inputDigest: recordedDigest,
            formatVersion: ScenePromptInputBuilder.schemaVersion,
            settings: proposal.settings
        )
        // The persisted active profile P — the run targets it by §3.3's rule, and the
        // step-0 digest guard has proven it did not move mid-run.
        report.targetProfile = try String.fetchOne(
            db, sql: "SELECT generation_target_profile FROM projects"
        ) ?? TargetProfileCatalog.defaultProfileID
        report.durationMs = Int((ContinuousClock.now - started).components.seconds * 1_000)
        try ProjectRepository.writeScenePromptReport(report, jobID: runJobID, in: db)
        try completeParent(runJobID: runJobID, usage: usage, in: db)

        // Step 4: outcome for the Generation section's undo registration.
        return ScenePromptApplyOutcome(report: report, entry: entry)
    }

    /// Version-two apply. The digest guard, complete set graph, journal entry, report,
    /// usage, and parent completion share this transaction.
    static func applySet(
        _ proposal: ScenePromptSetProposal,
        runJobID: UUID,
        usage: JobUsage,
        in db: Database
    ) throws -> ScenePromptSetApplyOutcome {
        let actor = MutationActor.ai(jobID: runJobID)
        let started = ContinuousClock.now
        guard let jobRow = try Row.fetchOne(
            db,
            sql: "SELECT state, parent_job_id, task, input_sha256 FROM jobs WHERE id = ?",
            arguments: [runJobID.uuidString]
        ) else { throw ProjectStoreError.jobNotFound }
        let task: String = jobRow["task"]
        guard task == Job.scenePromptTask else {
            throw ProjectStoreError.wrongJobTask(expected: Job.scenePromptTask, found: task)
        }
        let state = Job.State(rawValue: jobRow["state"]) ?? .failed
        let parentID: String? = jobRow["parent_job_id"]
        guard parentID == nil, state == .committing else {
            throw ProjectStoreError.illegalJobTransition(from: state, to: .completed)
        }
        let recordedDigest: String = jobRow["input_sha256"]
        let rebuilt = try ScenePromptInputBuilder.snapshot(sceneID: proposal.sceneID, in: db)
        guard rebuilt.digest == recordedDigest else {
            throw ProjectStoreError.scenePromptInputChangedDuringRun
        }
        let cleanBasis = try ScenePromptInputBuilder.snapshot(
            sceneID: proposal.sceneID,
            creativeDirectionOverride: "",
            in: db
        )

        let setID = UUID()
        let skillIdentity = AssetPromptSkillIdentity(
            id: proposal.settings.skillID,
            entryPath: proposal.settings.skillEntryPath,
            entrySHA256: proposal.settings.skillEntrySHA256
        )
        let entry = try EditPrimitives.perform(
            .attachGeneratedScenePromptSet(
                setID: setID,
                sceneID: proposal.sceneID,
                cards: proposal.cards,
                inputDigest: cleanBasis.digest,
                inputFormatVersion: ScenePromptInputBuilder.schemaVersion,
                skillIdentity: skillIdentity
            ),
            actor: actor,
            jobID: runJobID,
            in: db
        )

        let setNumber = try Int.fetchOne(
            db,
            sql: "SELECT set_number FROM scene_prompt_sets WHERE id = ?",
            arguments: [setID.uuidString]
        ) ?? 0
        let referenceCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM scene_prompt_card_references r
                JOIN scene_prompt_cards c ON c.id = r.card_id
                WHERE c.set_id = ?
                """,
            arguments: [setID.uuidString]
        ) ?? 0
        var report = ScenePromptApplyReport(
            sceneID: proposal.sceneID,
            targetProfile: try String.fetchOne(
                db, sql: "SELECT generation_target_profile FROM projects"
            ) ?? TargetProfileCatalog.defaultProfileID,
            setID: setID,
            setNumber: setNumber,
            cardCount: proposal.cards.count,
            referenceCount: referenceCount,
            inputDigest: recordedDigest,
            formatVersion: ScenePromptInputBuilder.schemaVersion,
            settings: proposal.settings
        )
        report.durationMs = Int((ContinuousClock.now - started).components.seconds * 1_000)
        try ProjectRepository.writeScenePromptReport(report, jobID: runJobID, in: db)
        try completeParent(runJobID: runJobID, usage: usage, in: db)
        guard let set = try ProjectRepository.scenePromptSet(id: setID, in: db) else {
            throw ProjectStoreError.databaseCommit("The committed prompt set could not be read.")
        }
        let detail = try ProjectRepository.scenePromptSetDetail(set, staleReason: nil, in: db)
        return ScenePromptSetApplyOutcome(report: report, entry: entry, set: detail)
    }

    /// The shipped in-transaction parent completion with usage — the asset applier's
    /// private helper, replicated because scene-prompt runs complete exactly once too.
    ///
    /// Scene-prompt runs are deliberately **outside** the revert machinery (§7.4's rule
    /// carried forward): no summary op exists on this path, so the selective-revert walk
    /// naturally skips them; `generateScenePrompt` must never join
    /// `requireNewestRun`'s closed task list (test-asserted like its sibling).
    private static func completeParent(
        runJobID: UUID,
        usage: JobUsage,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE jobs SET state = 'completed', progress_stage = 'Completed',
                    input_tokens = ?, cached_input_tokens = ?, cache_write_input_tokens = ?,
                    output_tokens = ?, reasoning_output_tokens = ?, ended_at = ?
                WHERE id = ? AND state = 'committing'
                """,
            arguments: [
                usage.inputTokens, usage.cachedInputTokens, usage.cacheWriteInputTokens,
                usage.outputTokens, usage.reasoningOutputTokens,
                UTCDate.string(from: Date()), runJobID.uuidString,
            ]
        )
        guard db.changesCount == 1 else {
            throw ProjectStoreError.databaseCommit("Parent completion failed.")
        }
    }
}
