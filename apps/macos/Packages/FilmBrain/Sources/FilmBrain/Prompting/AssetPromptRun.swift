import FilmCore
import Foundation

/// What the prompt run is doing, for the workshop's progress line.
public struct PromptRunProgress: Equatable, Sendable {
    public enum Stage: String, Equatable, Sendable {
        case planning, running, apply, completed, failed
    }
    public let stage: Stage
    public let message: String
    public static let generatingMessage = "Codex is generating the image prompt."

    public init(stage: Stage, message: String) {
        self.stage = stage
        self.message = message
    }
}

public enum PromptRunError: Error, Equatable, Sendable {
    case alreadyRunning
    case refused(AssetPromptRunGate.Refusal)
    /// The §8.1 pre-flight: an over-budget input fails **before any request is made**,
    /// with the size named, never by silent truncation (§11 defers chunking deliberately).
    case inputTooLarge(measuredUTF16: Int, limitUTF16: Int)
    /// The materialiser refused the skill (unsafe path, symlink, unreadable tree).
    case materialisationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "A prompt run is already active."
        case let .refused(refusal): refusal.error.errorDescription
        case let .inputTooLarge(measured, limit):
            ProjectStoreError.assetPromptInputOverBudget(
                measuredUTF16: measured, limitUTF16: limit
            ).errorDescription
        case let .materialisationFailed(reason):
            "The prompt skill could not be staged for this run: \(reason)"
        }
    }
}

/// The one-request asset-prompt run (PHASE3_DESIGN §8.1; Plan 016 contract C).
///
/// `ManifestRun`'s shape at single-requirement scale — no chunker, no fan-out, no resume.
/// One run covers one requirement; there is **no run-once gate and nothing closes** (§3.1):
/// a prompt is derived output that re-runs freely, serialized only by the shipped
/// one-active-run rule and the §8.1 paused-run gate.
///
/// Before the session starts, the skill is materialised for this run (arm B, §3.5): a
/// shared copy under `cache/skills/` plus this run's own `workspace/skill/` clone, whose
/// entry file the rendered instructions name by absolute path. Nothing about the cache
/// location is persisted anywhere (§3.5's fourth rule).
public actor AssetPromptRun {
    private let project: any ProjectTools
    private let adapter: any HarnessAdapter
    private let descriptor: PromptSkillDescriptor
    /// The project bundle root — where `cache/skills/` lives (§4.1). A parameter because
    /// FilmBrain never resolves a bundle itself; the app passes its session's root.
    private let bundleRoot: URL
    private var runner: StructuredJobRunner<GenerateAssetPromptTask>?
    private var continuation: AsyncStream<PromptRunProgress>.Continuation?
    public private(set) var lastOutcome: AssetPromptApplyOutcome?
    public private(set) var lastReport: AssetPromptApplyReport?
    public private(set) var runJobID: UUID?

    public init(
        project: any ProjectTools,
        adapter: any HarnessAdapter,
        descriptor: PromptSkillDescriptor,
        bundleRoot: URL
    ) {
        self.project = project
        self.adapter = adapter
        self.descriptor = descriptor
        self.bundleRoot = bundleRoot
    }

    public func progress() -> AsyncStream<PromptRunProgress> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    /// Runs generation to a committed `AssetPromptApplyOutcome`.
    ///
    /// - Parameter settings: model/effort from the shared Advanced surface plus the budget,
    ///   captured into `AssetPromptSettings` with the skill identity (§8.1); a preference
    ///   edited mid-run does not apply (§8.5).
    @discardableResult
    public func start(
        requirementID: UUID,
        engine: String,
        engineVersion: String,
        settings: AssetPromptSettings
    ) async throws -> AssetPromptApplyOutcome {
        guard runner == nil else { throw PromptRunError.alreadyRunning }
        lastOutcome = nil
        lastReport = nil
        emit(.planning, "Preparing prompt generation")

        // The gate is asked here so the run declines without creating a job row; FilmCore
        // throws its refusals from `createJob`/apply regardless (§8.1).
        let detail = try await project.requirement(id: requirementID)
        if let refusal = AssetPromptRunGate.refusal(
            detail: detail,
            bootstrapsIdle: try await !project.jobHistory().contains(where: {
                $0.parentJobID == nil
                    && ($0.task == Job.extractionTask || $0.task == Job.manifestTask)
                    && !$0.state.isTerminal
            })
        ) {
            emit(.failed, refusal.error.localizedDescription)
            continuation?.finish()
            throw PromptRunError.refused(refusal)
        }

        // The §8.2 snapshot is both the request payload and the one digest of §3.4.
        let snapshot = try await project.assetPromptInput(requirementID: requirementID)
        let budget = settings.inputBudgetUTF16 > 0
            ? settings.inputBudgetUTF16
            : AssetPromptInputBudget.defaultUTF16Limit
        do {
            try AssetPromptInputBudget.check(text: snapshot.text, limit: budget)
        } catch let failure as AssetPromptInputTooLarge {
            emit(.failed, failure.localizedDescription)
            continuation?.finish()
            throw PromptRunError.inputTooLarge(
                measuredUTF16: failure.measuredUTF16, limitUTF16: failure.limitUTF16
            )
        }

        // Materialise the skill for THIS run before the workspace is put to use (arm B):
        // shared copy once per tree digest, then this run's clone under workspace/skill/.
        let runID = UUID()
        let workspace = try await project.prepareRunWorkspace(runID: runID)
        let materializer = PromptSkillMaterializer(
            descriptor: descriptor, bundleRoot: bundleRoot
        )
        let materialized: MaterializedSkill
        do {
            materialized = try materializer.materialize(workspaceURL: workspace.workspaceURL)
        } catch {
            emit(.failed, error.localizedDescription)
            continuation?.finish()
            throw PromptRunError.materialisationFailed(error.localizedDescription)
        }

        // The settings travel with the report: captured knobs + descriptor-relative
        // provenance (§3.5's fourth rule — never an absolute cache path).
        let captured = AssetPromptSettings(
            model: settings.model,
            effort: settings.effort,
            inputBudgetUTF16: budget,
            skillID: descriptor.id,
            skillEntryPath: descriptor.entryRelativePath,
            skillEntrySHA256: materialized.entrySHA256
        )

        runJobID = runID
        let runner = StructuredJobRunner(
            task: GenerateAssetPromptTask(
                input: snapshot.input,
                skillEntryPath: materialized.entryURL.path,
                skillRoutingPath: materialized.routingURL?.path
            ),
            projectTools: project,
            adapter: adapter,
            progressHandler: { [weak self] _ in
                Task { await self?.emit(.running, PromptRunProgress.generatingMessage) }
            }
        )
        self.runner = runner
        defer { self.runner = nil }

        let project = self.project
        do {
            _ = try await runner.run(
                input: StructuredTaskInput(
                    jobID: runID,
                    text: snapshot.text,
                    requestedModel: captured.model,
                    reasoningEffort: captured.effort
                ),
                engine: engine,
                engineVersion: engineVersion,
                commit: { output, jobID, usage in
                    // The validated result becomes the value FilmCore's applier takes;
                    // the proposal's throwing init re-checks the storage-side limits.
                    let proposal = try AssetPromptProposal(
                        requirementID: requirementID,
                        body: output.prompt.body,
                        targetModel: output.prompt.targetModel,
                        guidance: output.prompt.guidance,
                        settings: captured
                    )
                    let outcome = try await project.applyAssetPromptRun(
                        proposal, runJobID: jobID, usage: usage
                    )
                    // `applyAssetPromptRun` completed the parent in its own transaction
                    // and returned the journal entry (§13.11's invertible apply).
                    await self.setOutcome(outcome)
                    return .completedByClosure
                }
            )
        } catch {
            emit(.failed, (error as? LocalizedError)?.errorDescription ?? "The prompt run failed.")
            continuation?.finish()
            throw error
        }

        guard let outcome = self.outcome() else {
            throw ProjectStoreError.databaseCommit("The prompt run recorded no outcome.")
        }
        lastReport = outcome.report
        emit(.completed, "Prompt generated")
        continuation?.finish()
        return outcome
    }

    public func cancel() async throws {
        try await runner?.cancel()
    }

    private func setOutcome(_ outcome: AssetPromptApplyOutcome) {
        lastOutcome = outcome
    }

    private func outcome() -> AssetPromptApplyOutcome? {
        lastOutcome
    }

    private func emit(_ stage: PromptRunProgress.Stage, _ message: String) {
        continuation?.yield(.init(stage: stage, message: message))
    }
}
