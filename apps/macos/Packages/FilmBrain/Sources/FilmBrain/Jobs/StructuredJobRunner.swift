import CryptoKit
import FilmCore
import Foundation

/// A job that ended before it produced a validated, committed result.
///
/// Phase 0's analyze-screenplay job failure under its general name: same `code`/`message`
/// shape, same job codes (`cancelled`, `missing_terminal_success`, `codex_error`,
/// `process_exit`, `harness_failure`, `database_commit`). Validation codes arrive
/// unchanged from `StructuredValidationFailure`.
public struct StructuredJobFailure: Error, Equatable, LocalizedError, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Who completed the parent job — the commit closure, or the runner (PHASE2_DESIGN §8.1).
///
/// Phase 1's commit closures wrote canonical rows and left the job in `committing`, so the
/// runner completed it afterwards. Phase 2's `applyManifestRun` completes the parent
/// *inside* its own apply transaction, so report, usage, and completion stay atomic; a
/// second `completeJob` would then throw on the illegal `completed → completed`
/// transition and surface a committed run as failed. Exactly-once completion is carried by
/// this type rather than by re-reading job state, so a closure that forgets to say which it
/// did cannot compile.
///
/// **Reference seam** (the `docs/plans/README.md` rule for lifecycle changes): the relevant
/// seam is RxCode's backend-owned job lifecycle, already adopted at this runner's creation
/// in Plan 003. Nothing new is adopted or rejected here — the change is a guarded skip
/// inside the existing state machine, and no reference project models a
/// commit-closure-completes-the-job shape.
public enum CommitOutcome: String, Equatable, Sendable {
    /// The closure already drove the job to `completed` (its own transaction did it).
    case completedByClosure
    /// The job is still `committing`; the runner completes it.
    case runnerCompletes
}

/// PHASE1_DESIGN §3.10's generic runner: Phase 0's analyze-screenplay job state machine,
/// generalized over a `StructuredTask` rather than redesigned.
///
/// Named `StructuredJobRunner` rather than `StructuredJob` because a nested `Task`
/// spelling would shadow `Swift.Task` inside every `async` body here.
public actor StructuredJobRunner<T: StructuredTask> {
    private let task: T
    private let projectTools: any ProjectTools
    private let adapter: any HarnessAdapter
    private let progressHandler: @Sendable (String) -> Void
    private var activeJobID: UUID?
    private var isCommitting = false

    public init(
        task: T,
        projectTools: any ProjectTools,
        adapter: any HarnessAdapter,
        progressHandler: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.task = task
        self.projectTools = projectTools
        self.adapter = adapter
        self.progressHandler = progressHandler
    }

    /// Runs one job to a validated result.
    ///
    /// With a `commit` closure the job is a **parent** run and owns the canonical
    /// transaction: `validating → committing → commit → completeJob`. Without one it is
    /// a **child** and finishes `validating → completed` without writing anything
    /// canonical (§3.9) — FilmCore refuses that transition for a parent, so a
    /// commit-less run must pass its parent's id.
    ///
    /// The closure returns a `CommitOutcome`, and the runner calls its own `completeJob`
    /// **only** on `.runnerCompletes` (PHASE2_DESIGN §8.1).
    ///
    /// - Parameter parentJobID: the run this job belongs to; `nil` makes this job the run.
    public func run(
        input: StructuredTaskInput,
        engine: String,
        engineVersion: String,
        parentJobID: UUID? = nil,
        commit: (@Sendable (T.Output, UUID, JobUsage) async throws -> CommitOutcome)? = nil
    ) async throws -> StructuredRunResult<T.Output> {
        let jobID = input.jobID
        // All children of a run share one workspace so Codex's cached prompt prefix
        // survives; only the result/log paths are per job (§8.4).
        let runID = parentJobID ?? jobID
        let workspace = try await projectTools.prepareRunWorkspace(runID: runID)
        let paths = try await projectTools.prepareChildPaths(runID: runID, jobID: jobID)
        let request = JobRequest(
            id: jobID,
            task: task.taskName,
            engine: engine,
            engineVersion: engineVersion,
            requestedModel: input.requestedModel,
            schemaVersion: task.schemaVersion,
            inputSHA256: Self.digest(of: input.text),
            logRelativePath: paths.logRelativePath,
            resultRelativePath: paths.resultRelativePath,
            parentJobID: parentJobID,
            chunkIndex: input.chunkIndex,
            chunkCount: input.chunkCount,
            scriptID: input.scriptID,
            scriptSHA256: input.scriptSHA256
        )
        _ = try await projectTools.createJob(request)
        activeJobID = jobID
        isCommitting = false
        defer {
            activeJobID = nil
            isCommitting = false
        }

        do {
            _ = try await projectTools.transitionJob(
                id: jobID,
                to: .discoveringHarness,
                progress: "Preparing harness"
            )
            progressHandler("Preparing harness")
            _ = try await projectTools.transitionJob(
                id: jobID,
                to: .running,
                progress: "Working"
            )
            progressHandler("Working")
            let harnessRequest = HarnessRequest(
                jobID: jobID,
                prompt: try task.prompt(for: input),
                workspaceURL: workspace.workspaceURL,
                schemaURL: task.schemaURL,
                resultURL: paths.resultURL,
                logURL: paths.logURL,
                model: input.requestedModel,
                reasoningEffort: input.reasoningEffort
            )
            var usage = JobUsage.empty
            var didComplete = false
            var terminalFailure: StructuredJobFailure?
            let stream = await adapter.events(for: harnessRequest)
            for try await event in stream {
                switch event {
                case let .started(_, effectiveModel):
                    try await projectTools.setEffectiveModel(jobID: jobID, effectiveModel: effectiveModel)
                case let .completed(recordedUsage):
                    usage = recordedUsage
                    didComplete = true
                // Plan 003 consumes no `HarnessFailureKind`: every failure is terminal
                // for the job. Plan 007's run coordinator reads the kind.
                case let .failed(code, message, _):
                    terminalFailure = .init(code: code, message: message)
                case .cancelled:
                    _ = try await projectTools.transitionJob(
                        id: jobID,
                        to: .cancelled,
                        progress: "Cancelled"
                    )
                    throw StructuredJobFailure(code: "cancelled", message: "The job was cancelled.")
                case let .progress(message), let .diagnostic(message):
                    progressHandler(message)
                case .decodeWarning:
                    progressHandler("The harness emitted an unrecognized event line.")
                case .unknown:
                    break
                }
                if terminalFailure != nil { break }
            }
            if let terminalFailure {
                try await fail(jobID: jobID, failure: terminalFailure)
                throw terminalFailure
            }
            guard didComplete else {
                let failure = StructuredJobFailure(
                    code: "missing_terminal_success",
                    message: "The harness ended without a successful terminal event."
                )
                try await fail(jobID: jobID, failure: failure)
                throw failure
            }

            _ = try await projectTools.transitionJob(
                id: jobID,
                to: .validating,
                progress: "Validating result"
            )
            progressHandler("Validating result")
            let output: T.Output
            do {
                output = try task.validate(resultFileAt: paths.resultURL)
            } catch let validation as StructuredValidationFailure {
                let failure = StructuredJobFailure(
                    code: validation.code.rawValue,
                    message: validation.message
                )
                try await fail(jobID: jobID, failure: failure)
                throw failure
            }

            guard let commit else {
                // A child job finishes here: its validated result file is an input to the
                // run's own commit, and nothing canonical is written (§3.9).
                let job = try await projectTools.transitionJob(
                    id: jobID,
                    to: .completed,
                    progress: "Completed"
                )
                return StructuredRunResult(job: job, output: output, usage: usage)
            }

            _ = try await projectTools.transitionJob(
                id: jobID,
                to: .committing,
                progress: "Finishing commit"
            )
            progressHandler("Finishing commit")
            isCommitting = true
            do {
                let outcome = try await commit(output, jobID, usage)
                let job: Job
                switch outcome {
                case .runnerCompletes:
                    job = try await projectTools.completeJob(id: jobID, usage: usage)
                case .completedByClosure:
                    // The closure's own transaction completed the job with its report and
                    // usage; completing again would throw `completed → completed`.
                    guard let completed = try await projectTools.jobHistory()
                        .first(where: { $0.id == jobID })
                    else { throw ProjectStoreError.jobNotFound }
                    job = completed
                }
                return StructuredRunResult(job: job, output: output, usage: usage)
            } catch {
                let failure = StructuredJobFailure(
                    code: "database_commit",
                    message: "The validated result could not be committed."
                )
                try? await fail(jobID: jobID, failure: failure)
                throw failure
            }
        } catch let failure as StructuredJobFailure {
            throw failure
        } catch is CancellationError {
            await adapter.cancel(jobID: jobID)
            try? await cancelCoreJob(jobID)
            throw StructuredJobFailure(code: "cancelled", message: "The job was cancelled.")
        } catch {
            let failure = StructuredJobFailure(
                code: "harness_failure",
                message: "The harness failed before producing a validated result."
            )
            try? await fail(jobID: jobID, failure: failure)
            throw failure
        }
    }

    public func cancel() async throws {
        guard let jobID = activeJobID else { return }
        if isCommitting { throw ProjectStoreError.cancellationTooLate }
        await adapter.cancel(jobID: jobID)
    }

    /// `jobs.input_sha256` — the digest of this job's own input text (§8.2 replaces it
    /// with a reuse key for chunk attempts in Plan 007).
    private static func digest(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func cancelCoreJob(_ jobID: UUID) async throws {
        _ = try await projectTools.transitionJob(
            id: jobID,
            to: .cancelled,
            progress: "Cancelled",
            failureCode: nil,
            failureMessage: nil
        )
    }

    private func fail(jobID: UUID, failure: StructuredJobFailure) async throws {
        _ = try await projectTools.transitionJob(
            id: jobID,
            to: .failed,
            progress: "Failed",
            failureCode: failure.code,
            failureMessage: failure.message
        )
    }
}
