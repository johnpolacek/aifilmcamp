import Foundation
import GRDB

/// §8.4's apply (Plan 016 contract C). `ManifestApplier`'s shape, minus everything a
/// single-row write does not need — no savepoint fan-out, no summary op. What stays
/// exactly: step 0's digest guard replacing every per-reference existence check, the
/// parent completed **inside** the transaction with its usage and its report, and the
/// report written through the internal `in db:` primitive (`writeAssetPromptReport`) —
/// never the public typed door, which opens its own transaction and refuses a completed
/// job (the recorded Phase 2 lesson).
enum AssetPromptApplier {
    static func apply(
        _ proposal: AssetPromptProposal,
        runJobID: UUID,
        usage: JobUsage,
        in db: Database
    ) throws -> AssetPromptApplyOutcome {
        let actor = MutationActor.ai(jobID: runJobID)
        let started = ContinuousClock.now

        // The parent, its task, and the digest it recorded at launch.
        guard let jobRow = try Row.fetchOne(
            db,
            sql: "SELECT state, parent_job_id, task, input_sha256 FROM jobs WHERE id = ?",
            arguments: [runJobID.uuidString]
        ) else { throw ProjectStoreError.jobNotFound }
        let task: String = jobRow["task"]
        guard task == Job.assetPromptTask else {
            throw ProjectStoreError.wrongJobTask(expected: Job.assetPromptTask, found: task)
        }
        let state = Job.State(rawValue: jobRow["state"]) ?? .failed
        let parentID: String? = jobRow["parent_job_id"]
        guard parentID == nil, state == .committing else {
            throw ProjectStoreError.illegalJobTransition(from: state, to: .completed)
        }

        // §8.4 step 0. One comparison instead of a dozen predicates: equal ⟹ the
        // requirement, its facts, and every reference the prompt names still stand exactly
        // as validated; different ⟹ nothing is applied.
        let recordedDigest: String = jobRow["input_sha256"]
        let rebuilt = try AssetPromptInputBuilder.snapshot(
            requirementID: proposal.requirementID, in: db
        )
        guard rebuilt.digest == recordedDigest else {
            throw ProjectStoreError.assetPromptInputChangedDuringRun
        }

        // Steps 1–2: `attachGeneratedPrompt` re-checks the preconditions that are outside
        // the digest (locks, the requirement's review state) and performs the **one
        // invertible entry** — consuming Plan 014's pinned engine signature exactly. The
        // applier supplies the step-0 rebuilt digest and the builder's format version; the
        // operation derives the citations (§3.7 is the AI actor's entire write surface).
        let promptID = UUID()
        let assetID = UUID()
        let skillIdentity = AssetPromptSkillIdentity(
            id: proposal.settings.skillID,
            entryPath: proposal.settings.skillEntryPath,
            entrySHA256: proposal.settings.skillEntrySHA256
        )
        let entry = try EditPrimitives.perform(
            .attachGeneratedPrompt(
                promptID: promptID,
                assetID: assetID,
                requirementID: proposal.requirementID,
                body: proposal.body,
                targetModel: proposal.targetModel,
                guidance: proposal.guidance,
                inputDigest: rebuilt.digest,
                inputFormatVersion: AssetPromptInputBuilder.schemaVersion,
                skillIdentity: skillIdentity
            ),
            actor: actor,
            jobID: runJobID,
            in: db
        )

        // Step 3: the report and usage land with the parent's completion, in this
        // transaction — the `writeManifestReport` shape verbatim.
        let promptNumber = try Int.fetchOne(
            db,
            sql: "SELECT prompt_number FROM asset_prompts WHERE id = ?",
            arguments: [promptID.uuidString]
        ) ?? 0
        let referenceCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM asset_prompt_references WHERE prompt_id = ?",
            arguments: [promptID.uuidString]
        ) ?? 0
        var report = AssetPromptApplyReport(
            requirementID: proposal.requirementID,
            promptID: promptID,
            promptNumber: promptNumber,
            referenceCount: referenceCount,
            targetModel: proposal.targetModel,
            settings: proposal.settings
        )
        report.durationMs = Int((ContinuousClock.now - started).components.seconds * 1_000)
        try ProjectRepository.writeAssetPromptReport(report, jobID: runJobID, in: db)
        try completeParent(runJobID: runJobID, usage: usage, in: db)

        // Step 4: outcome for the workshop's undo registration (§13.11).
        return AssetPromptApplyOutcome(report: report, entry: entry)
    }

    /// The shipped in-transaction parent completion with usage — the manifest applier's
    /// private helper, replicated here because prompt runs complete exactly once too.
    ///
    /// Prompt runs are deliberately **outside** the revert machinery (§7.4, §8.4): no
    /// summary op exists on this path, so the selective-revert walk naturally skips them;
    /// `generateAssetPrompt` must never join `requireNewestRun`'s closed task list.
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
