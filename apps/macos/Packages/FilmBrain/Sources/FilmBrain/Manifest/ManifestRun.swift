import FilmCore
import Foundation

/// What the manifest run is doing, for the Manifest section's progress line.
public struct ManifestRunProgress: Equatable, Sendable {
    public enum Stage: String, Equatable, Sendable {
        case planning, running, apply, completed, failed
    }
    public let stage: Stage
    public let message: String

    public init(stage: Stage, message: String) {
        self.stage = stage
        self.message = message
    }
}

public enum ManifestRunError: Error, Equatable, LocalizedError, Sendable {
    case noScreenplay
    case alreadyRunning
    case refused(ManifestRunGate.Refusal)
    /// The §8.1 pre-flight: an over-budget project fails **before any request is made**,
    /// with the size named, never by silent truncation.
    case inputTooLarge(ManifestInputTooLarge)

    public var errorDescription: String? {
        switch self {
        case .noScreenplay: "Import a screenplay before inferring the asset manifest."
        case .alreadyRunning: "A manifest run is already active."
        case let .refused(refusal): refusal.errorDescription
        case let .inputTooLarge(failure): failure.errorDescription
        }
    }
}

/// The one-request manifest-inference run (PHASE2_DESIGN §8.1; Plan 012 contract C).
///
/// `ExtractionRun`'s shape, minus everything a single request does not need: no chunker, no
/// fan-out, no reconcile pass, no resume. The generic `StructuredJobRunner` owns the job
/// state machine — this coordinator only gates, builds the input, and commits.
///
/// The commit closure is the whole of §8.1's stated runner change: it writes the
/// zero-counter report, hands the validated result to FilmCore as a `ManifestProposal`, and
/// returns `.completedByClosure` because `applyManifestRun` completed the parent inside its
/// own transaction.
public actor ManifestRun {
    private let project: any ProjectTools
    private let adapter: any HarnessAdapter
    private var runner: StructuredJobRunner<InferManifestTask>?
    private var continuation: AsyncStream<ManifestRunProgress>.Continuation?
    public private(set) var lastReport: ManifestApplyReport?
    public private(set) var runJobID: UUID?

    public init(project: any ProjectTools, adapter: any HarnessAdapter) {
        self.project = project
        self.adapter = adapter
    }

    public func progress() -> AsyncStream<ManifestRunProgress> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    /// The §9 disclosure acknowledgement is the UI's to obtain (Plan 012 step 3); this
    /// coordinator exposes the door the sheet calls so the run itself never writes it.
    public func acknowledgeDisclosure() async throws {
        try await project.acknowledgeDisclosure()
    }

    /// Runs inference to a committed `ManifestApplyReport`.
    ///
    /// - Parameter settings: the run's captured knobs. `inputBudgetUTF16` of `0` means "the
    ///   pinned default"; whatever value is used is what the report records, so a recorded
    ///   run is reproducible against the settings it actually ran with (§8.5).
    @discardableResult
    public func start(
        engine: String,
        engineVersion: String,
        settings: ManifestSettings = ManifestSettings()
    ) async throws -> ManifestApplyReport {
        guard runner == nil else { throw ManifestRunError.alreadyRunning }
        lastReport = nil
        emit(.planning, "Preparing manifest inference")
        guard let script = try await project.script() else { throw ManifestRunError.noScreenplay }

        // The gate is asked here so the run declines without creating a job row; FilmCore
        // throws the same three refusals from `createJob` regardless (§3.6).
        if let refusal = ManifestRunGate.refusal(
            scriptID: script.id, jobs: try await project.jobHistory()
        ) {
            emit(.failed, refusal.localizedDescription)
            continuation?.finish()
            throw ManifestRunError.refused(refusal)
        }

        let snapshot = try await project.manifestInput()
        let budget = settings.inputBudgetUTF16 > 0
            ? settings.inputBudgetUTF16
            : ManifestInputBudget.defaultUTF16Limit
        do {
            try ManifestInputBudget.check(snapshot, limit: budget)
        } catch let failure as ManifestInputTooLarge {
            emit(.failed, failure.localizedDescription)
            continuation?.finish()
            throw ManifestRunError.inputTooLarge(failure)
        }
        let captured = ManifestSettings(
            model: settings.model, effort: settings.effort, inputBudgetUTF16: budget
        )

        let runID = UUID()
        runJobID = runID
        let runner = StructuredJobRunner(
            task: InferManifestTask(input: snapshot.input),
            projectTools: project,
            adapter: adapter,
            progressHandler: { [weak self] message in
                Task { await self?.emit(.running, message) }
            }
        )
        self.runner = runner
        defer { self.runner = nil }

        let project = self.project
        do {
            let result = try await runner.run(
                input: StructuredTaskInput(
                    jobID: runID,
                    text: snapshot.text,
                    scriptID: script.id,
                    scriptSHA256: script.sha256,
                    requestedModel: captured.model,
                    reasoningEffort: captured.effort
                ),
                engine: engine,
                engineVersion: engineVersion,
                commit: { output, jobID, usage in
                    // §8.5: the zero-counter report goes in through the public typed door
                    // **before** apply — the job is `committing`, not completed, so the
                    // setter accepts it. The post-apply rewrite happens inside the apply
                    // transaction.
                    try await project.setManifestReport(
                        jobID: jobID, ManifestApplyReport(settings: captured)
                    )
                    let proposal = try ManifestProposalBuilder.build(
                        output,
                        scriptID: script.id,
                        scriptSHA256: script.sha256,
                        settings: captured
                    )
                    _ = try await project.applyManifestRun(
                        proposal, runJobID: jobID, usage: usage
                    )
                    // `applyManifestRun` completed the parent in its own transaction.
                    return .completedByClosure
                }
            )
            _ = result
        } catch {
            emit(.failed, (error as? LocalizedError)?.errorDescription ?? "The manifest run failed.")
            continuation?.finish()
            throw error
        }

        let report = try await project.jobHistory()
            .first { $0.id == runID }?
            .manifestReport
        lastReport = report
        emit(.completed, "Manifest inference complete")
        continuation?.finish()
        guard let report else {
            throw ProjectStoreError.databaseCommit("The manifest run recorded no report.")
        }
        return report
    }

    public func cancel() async throws {
        try await runner?.cancel()
    }

    private func emit(_ stage: ManifestRunProgress.Stage, _ message: String) {
        continuation?.yield(.init(stage: stage, message: message))
    }
}

/// The FilmBrain → FilmCore conversion (Plan 012 contract C): the validated result becomes
/// the value type FilmCore's applier takes, and nothing else crosses the seam.
///
/// FilmCore may not import FilmBrain, so the mapping lives on this side. `ManifestProposal`'s
/// throwing init re-checks lengths and confidence the way `ExtractionProposal`'s does, which
/// is what keeps an unvalidated result from ever reaching apply.
public enum ManifestProposalBuilder: Sendable {
    public static func build(
        _ result: InferManifestResult,
        scriptID: UUID,
        scriptSHA256: String,
        settings: ManifestSettings
    ) throws -> ManifestProposal {
        try ManifestProposal(
            scriptID: scriptID,
            scriptSHA256: scriptSHA256,
            settings: settings,
            variants: result.variants.map {
                ProposedVariantRequirement(
                    entityID: $0.entityId,
                    name: $0.name,
                    reason: $0.reason,
                    sceneOrdinals: $0.sceneOrdinals,
                    basis: ProposedRequirementBasis(
                        stateIDs: $0.basisStateIds,
                        eventIDs: $0.basisEventIds,
                        appearanceIDs: $0.basisAppearanceIds
                    ),
                    confidence: $0.confidence
                )
            },
            importantProps: result.importantProps.map {
                ProposedPropRequirement(
                    entityID: $0.entityId,
                    reason: $0.reason,
                    basis: ProposedRequirementBasis(
                        stateIDs: $0.basisStateIds,
                        eventIDs: $0.basisEventIds,
                        appearanceIDs: $0.basisAppearanceIds
                    ),
                    confidence: $0.confidence
                )
            },
            inclusionSuggestions: result.inclusionSuggestions.map(\.inclusionSuggestion)
        )
    }
}
