import CryptoKit
import FilmCore
import Foundation

public struct ExtractionRunProgress: Equatable, Sendable {
    public enum Stage: String, Equatable, Sendable {
        case planning, warmup, fanout, paused, reconcile, apply, completed, failed, cancelled
    }
    public let stage: Stage
    public let message: String

    public init(stage: Stage, message: String) {
        self.stage = stage
        self.message = message
    }
}

public enum ExtractionRunError: Error, Equatable, LocalizedError, Sendable {
    case noScreenplay
    case alreadyRunning
    case notPaused
    case usageLimit(resetHint: String?)
    case unknownModel(String)
    case cancelled
    case reconcileFailed(String)
    case allChunksFailed([String])

    public var errorDescription: String? {
        switch self {
        case .noScreenplay: "Import a screenplay before analyzing it."
        case .alreadyRunning: "An extraction run is already active."
        case .notPaused: "This extraction run is not paused."
        case let .usageLimit(hint): hint ?? "Codex usage is temporarily unavailable."
        case let .unknownModel(model): "Codex rejected model ‘\(model)’."
        case .cancelled: "The extraction run was cancelled."
        case let .reconcileFailed(message): message
        case let .allChunksFailed(details):
            "Every screenplay chunk failed, so nothing was applied. \(details.joined(separator: " "))"
        }
    }
}

public actor ExtractionRun {
    private struct Context: Sendable {
        let runID: UUID
        let script: Script
        let settings: ExtractionSettings
        let engine: String
        let engineVersion: String
        let chunks: [ExtractionChunk]
    }

    private enum ChunkOutcome: Sendable {
        case completed(CompletedChunkExtraction, JobUsage)
        case failed(chunkIndex: Int)
        case paused(resetHint: String?)
        case unknownModel
    }

    private let project: any ProjectTools
    private let adapter: any HarnessAdapter
    private let bundleURL: URL
    private let retryBackoff: Duration
    private var context: Context?
    private var completed: [Int: CompletedChunkExtraction] = [:]
    private var childUsage: [UUID: JobUsage] = [:]
    private var activeJobIDs = Set<UUID>()
    private var pausedHint: String?
    private var cancelled = false
    private var continuation: AsyncStream<ExtractionRunProgress>.Continuation?
    public private(set) var lastReport: ApplyReport?
    public private(set) var runJobID: UUID?

    public init(
        project: any ProjectTools,
        adapter: any HarnessAdapter,
        bundleURL: URL,
        retryBackoff: Duration = .seconds(5)
    ) {
        self.project = project
        self.adapter = adapter
        self.bundleURL = bundleURL
        self.retryBackoff = retryBackoff
    }

    public func progress() -> AsyncStream<ExtractionRunProgress> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    public func plannedRequestCount(
        engine: String = "codex",
        engineVersion: String = "current",
        settings: ExtractionSettings = ExtractionSettings(),
        budgetUTF16: Int = 32_000
    ) async throws -> Int {
        let script = try await requireScript()
        let chunks = try await buildChunks(budgetUTF16: budgetUTF16)
        let history = try await project.jobHistory()
        var launches = 0
        for chunk in chunks {
            let key = reuseKey(
                chunk: chunk,
                engine: engine,
                engineVersion: engineVersion,
                model: settings.chunkModel,
                effort: settings.chunkEffort
            )
            let reusable = history.contains {
                $0.task == "extractChunk" && $0.state == .completed && $0.inputSHA256 == key
                    && $0.scriptID == script.id
            }
            if !reusable { launches += 1 }
        }
        return launches + 1
    }

    public func start(
        engine: String,
        engineVersion: String,
        settings: ExtractionSettings,
        budgetUTF16: Int = 32_000
    ) async throws {
        guard context == nil else { throw ExtractionRunError.alreadyRunning }
        cancelled = false
        completed = [:]
        childUsage = [:]
        lastReport = nil
        emit(.planning, "Planning extraction")
        let script = try await requireScript()
        let chunks = try await buildChunks(budgetUTF16: budgetUTF16)
        let runID = UUID()
        runJobID = runID
        let captured = ExtractionSettings(
            chunkModel: settings.chunkModel,
            chunkEffort: settings.chunkEffort,
            reconcileModel: settings.reconcileModel,
            reconcileEffort: settings.reconcileEffort,
            chunkBudget: budgetUTF16,
            concurrency: max(1, settings.concurrency == 0 ? adapter.capabilities.recommendedConcurrency : settings.concurrency)
        )
        let parent = JobRequest(
            id: runID,
            task: "extractScreenplay",
            engine: engine,
            engineVersion: engineVersion,
            requestedModel: captured.chunkModel,
            schemaVersion: ExtractChunkSchema.version,
            inputSHA256: digest("\(script.sha256):\(budgetUTF16)"),
            logRelativePath: try RelativeProjectPath("logs/jobs/\(runID.uuidString).jsonl"),
            resultRelativePath: try RelativeProjectPath("cache/jobs/\(runID.uuidString)/result.json"),
            chunkCount: chunks.count,
            scriptID: script.id,
            scriptSHA256: script.sha256
        )
        _ = try await project.createJob(parent)
        try await project.setApplyReport(jobID: runID, ApplyReport(settings: captured))
        _ = try await project.transitionJob(id: runID, to: .discoveringHarness, progress: "Preparing extraction")
        _ = try await project.transitionJob(id: runID, to: .running, progress: "Extracting screenplay")
        let context = Context(
            runID: runID,
            script: script,
            settings: captured,
            engine: engine,
            engineVersion: engineVersion,
            chunks: chunks
        )
        self.context = context
        try await runExecution(context)
    }

    public func resume() async throws {
        guard let context, pausedHint != nil else { throw ExtractionRunError.notPaused }
        pausedHint = nil
        // Resume is an auditable continuation, not an in-memory shortcut. Completed
        // chunks are discovered through the normal reuse path, copied into fresh
        // attempts, and revalidated before reconcile runs again.
        completed = [:]
        _ = try await project.transitionJob(
            id: context.runID,
            to: .running,
            progress: "Resuming extraction"
        )
        try await runExecution(context)
    }

    public func pause() async throws {
        guard let context else { return }
        guard pausedHint == nil else { return }
        pausedHint = "Paused by operator."
        for id in activeJobIDs { await adapter.cancel(jobID: id) }
        _ = try await project.transitionJob(id: context.runID, to: .paused, progress: "Paused")
        emit(.paused, "Paused")
    }

    public func cancel() async throws {
        guard let context else { return }
        cancelled = true
        for id in activeJobIDs { await adapter.cancel(jobID: id) }
        let job = try await project.jobHistory().first { $0.id == context.runID }
        if let job, !job.state.isTerminal, job.state != .committing {
            _ = try await project.transitionJob(id: context.runID, to: .cancelled, progress: "Cancelled")
        }
        emit(.cancelled, "Cancelled")
        continuation?.finish()
        self.context = nil
        throw ExtractionRunError.cancelled
    }

    public func previewReplacement() async throws -> Int {
        try await project.entities(
            kind: nil, reviewState: .proposed, includeIrrelevant: true, includeRejected: false
        ).filter { $0.provenance.isReplaceable }.count
    }

    private func execute(_ context: Context) async throws {
        var failures = Set<Int>()
        let pending = context.chunks.filter { completed[$0.index] == nil }
        if let first = pending.first, adapter.capabilities.prefersWarmUp {
            emit(.warmup, "Analyzing the first chunk")
            try await consume(try await runChunk(first, context: context), failures: &failures, context: context)
            if pausedHint != nil { return }
        }
        let remaining = context.chunks.filter { completed[$0.index] == nil && !failures.contains($0.index) }
        emit(.fanout, "Analyzing screenplay chunks")
        let width = max(1, context.settings.concurrency)
        var offset = 0
        while offset < remaining.count {
            if cancelled { throw ExtractionRunError.cancelled }
            let batch = Array(remaining[offset..<min(remaining.count, offset + width)])
            let outcomes = try await withThrowingTaskGroup(of: ChunkOutcome.self) { group in
                for chunk in batch {
                    group.addTask { try await self.runChunk(chunk, context: context) }
                }
                var values: [ChunkOutcome] = []
                for try await value in group { values.append(value) }
                return values
            }
            for outcome in outcomes {
                try await consume(outcome, failures: &failures, context: context)
            }
            if pausedHint != nil { return }
            offset += batch.count
        }
        try await finish(context: context, failures: failures)
    }

    private func runExecution(_ context: Context) async throws {
        do {
            try await execute(context)
        } catch let error as ExtractionRunError {
            if case .usageLimit = error { return }
            try await recordRunFailure(error, context: context)
            throw error
        } catch {
            try await recordRunFailure(error, context: context)
            throw error
        }
    }

    private func recordRunFailure(_ error: any Error, context: Context) async throws {
        let current = try await project.jobHistory().first { $0.id == context.runID }
        if let current, !current.state.isTerminal {
            let code: String
            let message: String
            switch error {
            case let extraction as ExtractionRunError:
                switch extraction {
                case .unknownModel: code = "unknown_model"
                case .cancelled: code = "cancelled"
                case .reconcileFailed: code = "reconcile_failed"
                case .allChunksFailed: code = "all_chunks_failed"
                default: code = "extraction_failed"
                }
                message = extraction.localizedDescription
            default:
                code = "extraction_failed"
                message = "The extraction run failed."
            }
            if case ExtractionRunError.cancelled = error {
                _ = try? await project.transitionJob(
                    id: context.runID, to: .cancelled, progress: "Cancelled"
                )
                emit(.cancelled, message)
            } else {
                _ = try? await project.transitionJob(
                    id: context.runID, to: .failed, progress: "Failed",
                    failureCode: code, failureMessage: message
                )
                emit(.failed, message)
            }
        }
        continuation?.finish()
        self.context = nil
    }

    private func consume(
        _ outcome: ChunkOutcome,
        failures: inout Set<Int>,
        context: Context
    ) async throws {
        switch outcome {
        case let .completed(output, usage):
            completed[output.chunkIndex] = output
            _ = usage
        case let .failed(index):
            failures.insert(index)
        case let .paused(hint):
            pausedHint = hint ?? "Codex usage is temporarily unavailable."
            _ = try await project.transitionJob(
                id: context.runID, to: .paused,
                progress: hint ?? "Codex usage limit reached"
            )
            emit(.paused, hint ?? "Codex usage limit reached")
        case .unknownModel:
            let model = context.settings.chunkModel ?? "account default"
            _ = try await project.transitionJob(
                id: context.runID, to: .failed, progress: "Failed",
                failureCode: "unknown_model",
                failureMessage: "Codex rejected model ‘\(model)’."
            )
            emit(.failed, "Codex rejected the selected model")
            self.context = nil
            throw ExtractionRunError.unknownModel(model)
        }
    }

    private func runChunk(_ chunk: ExtractionChunk, context: Context) async throws -> ChunkOutcome {
        let key = reuseKey(
            chunk: chunk,
            engine: context.engine,
            engineVersion: context.engineVersion,
            model: context.settings.chunkModel,
            effort: context.settings.chunkEffort
        )
        if let reused = try await reuseChunk(chunk, key: key, context: context) {
            return .completed(reused, .empty)
        }
        var supersedes = try await project.jobHistory().reversed().first {
            $0.task == "extractChunk" && $0.chunkIndex == chunk.index
                && $0.scriptID == context.script.id
        }?.id
        for attempt in 0...1 {
            let outcome = try await launchChunk(
                chunk,
                key: key,
                attemptIndex: try await nextAttemptIndex(chunk: chunk.index, context: context),
                supersedes: supersedes,
                context: context
            )
            switch outcome {
            case let .completed(output, usage): return .completed(output, usage)
            case let .failed(index): return .failed(chunkIndex: index)
            case let .paused(hint): return .paused(resetHint: hint)
            case .unknownModel: return .unknownModel
            case .retryable(let jobID):
                supersedes = jobID
                if attempt == 0 { try await Task.sleep(for: retryBackoff) }
            }
        }
        return .failed(chunkIndex: chunk.index)
    }

    private enum AttemptOutcome: Sendable {
        case completed(CompletedChunkExtraction, JobUsage)
        case retryable(UUID)
        case failed(Int)
        case paused(String?)
        case unknownModel
    }

    private func launchChunk(
        _ chunk: ExtractionChunk,
        key: String,
        attemptIndex: Int,
        supersedes: UUID?,
        context: Context
    ) async throws -> AttemptOutcome {
        let jobID = UUID()
        let paths = try await project.prepareChildPaths(runID: context.runID, jobID: jobID)
        try Data(chunk.text.utf8).write(to: paths.inputURL, options: .atomic)
        _ = try await project.createJob(JobRequest(
            id: jobID, task: "extractChunk", engine: context.engine,
            engineVersion: context.engineVersion, requestedModel: context.settings.chunkModel,
            schemaVersion: ExtractChunkSchema.version, inputSHA256: key,
            logRelativePath: paths.logRelativePath, resultRelativePath: paths.resultRelativePath,
            parentJobID: context.runID, chunkIndex: chunk.index, chunkCount: context.chunks.count,
            attemptIndex: attemptIndex, supersedesJobID: supersedes,
            scriptID: context.script.id, scriptSHA256: context.script.sha256
        ))
        activeJobIDs.insert(jobID)
        defer { activeJobIDs.remove(jobID) }
        _ = try await project.transitionJob(id: jobID, to: .discoveringHarness, progress: "Preparing harness")
        _ = try await project.transitionJob(id: jobID, to: .running, progress: "Working")
        let task = ExtractChunkTask(chunk: chunk)
        let input = StructuredTaskInput(
            jobID: jobID, text: chunk.text, scriptID: context.script.id,
            scriptSHA256: context.script.sha256, chunkIndex: chunk.index,
            chunkCount: context.chunks.count, requestedModel: context.settings.chunkModel,
            reasoningEffort: context.settings.chunkEffort
        )
        let request = HarnessRequest(
            jobID: jobID, prompt: try task.prompt(for: input),
            workspaceURL: try await project.prepareRunWorkspace(runID: context.runID).workspaceURL,
            schemaURL: task.schemaURL, resultURL: paths.resultURL, logURL: paths.logURL,
            model: context.settings.chunkModel, reasoningEffort: context.settings.chunkEffort
        )
        var usage = JobUsage.empty
        var completedSuccessfully = false
        do {
            let stream = await adapter.events(for: request)
            for try await event in stream {
                switch event {
                case let .started(_, model): try await project.setEffectiveModel(jobID: jobID, effectiveModel: model)
                case let .completed(value): usage = value; completedSuccessfully = true
                case let .failed(code, message, kind):
                    _ = try await project.transitionJob(
                        id: jobID, to: .failed, progress: "Failed", failureCode: code, failureMessage: message
                    )
                    switch kind {
                    case .usageLimit(let hint): return .paused(hint)
                    case .retryable: return .retryable(jobID)
                    case .unknownModel: return .unknownModel
                    case .fatal: return .failed(chunk.index)
                    }
                case .cancelled:
                    _ = try? await project.transitionJob(id: jobID, to: .cancelled, progress: "Cancelled")
                    return .failed(chunk.index)
                default: break
                }
            }
        } catch {
            _ = try? await project.transitionJob(
                id: jobID, to: .failed, progress: "Failed",
                failureCode: "adapter_error", failureMessage: "The harness response could not be read."
            )
            return .failed(chunk.index)
        }
        guard completedSuccessfully else {
            _ = try await project.transitionJob(
                id: jobID, to: .failed, progress: "Failed",
                failureCode: "missing_terminal_success", failureMessage: "The harness ended early."
            )
            return .failed(chunk.index)
        }
        _ = try await project.transitionJob(id: jobID, to: .validating, progress: "Validating")
        do {
            let result = try task.validate(resultFileAt: paths.resultURL)
            let job = try await project.completeJob(id: jobID, usage: usage)
            childUsage[job.id] = usage
            return .completed(.init(chunkIndex: chunk.index, result: result), usage)
        } catch let failure as StructuredValidationFailure {
            let diagnostic = validationDiagnostic(failure, subject: "screenplay chunk")
            _ = try await project.transitionJob(
                id: jobID, to: .failed, progress: "Failed",
                failureCode: diagnostic.code, failureMessage: diagnostic.message
            )
            return .failed(chunk.index)
        } catch {
            _ = try await project.transitionJob(
                id: jobID, to: .failed, progress: "Failed",
                failureCode: "validation_error",
                failureMessage: "The screenplay chunk result could not be validated."
            )
            return .failed(chunk.index)
        }
    }

    private func reuseChunk(
        _ chunk: ExtractionChunk,
        key: String,
        context: Context
    ) async throws -> CompletedChunkExtraction? {
        let history = try await project.jobHistory()
        guard let source = history.reversed().first(where: {
            $0.task == "extractChunk" && $0.state == .completed && $0.inputSHA256 == key
                && $0.chunkIndex == chunk.index
        }) else { return nil }
        let sourceURL = try source.resultRelativePath.resolve(in: bundleURL)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
        let jobID = UUID()
        let paths = try await project.prepareChildPaths(runID: context.runID, jobID: jobID)
        do {
            try Data(contentsOf: sourceURL).write(to: paths.resultURL, options: .atomic)
            try Data(chunk.text.utf8).write(to: paths.inputURL, options: .atomic)
            let task = ExtractChunkTask(chunk: chunk)
            let result = try task.validate(resultFileAt: paths.resultURL)
            _ = try await project.createJob(JobRequest(
                id: jobID, task: "extractChunk", engine: context.engine,
                engineVersion: context.engineVersion, requestedModel: context.settings.chunkModel,
                schemaVersion: ExtractChunkSchema.version, inputSHA256: key,
                logRelativePath: paths.logRelativePath, resultRelativePath: paths.resultRelativePath,
                parentJobID: context.runID, chunkIndex: chunk.index, chunkCount: context.chunks.count,
                attemptIndex: try await nextAttemptIndex(chunk: chunk.index, context: context),
                supersedesJobID: source.id, scriptID: context.script.id,
                scriptSHA256: context.script.sha256
            ))
            for state in [Job.State.discoveringHarness, .running, .validating] {
                _ = try await project.transitionJob(
                    id: jobID, to: state, progress: Job.reusedProgressStage
                )
            }
            _ = try await project.completeJob(
                id: jobID,
                usage: .empty,
                progress: Job.reusedProgressStage
            )
            childUsage[jobID] = .empty
            return .init(chunkIndex: chunk.index, result: result)
        } catch {
            return nil
        }
    }

    private func finish(context: Context, failures: Set<Int>) async throws {
        if cancelled { throw ExtractionRunError.cancelled }
        let completedChunks = completed.values.sorted { $0.chunkIndex < $1.chunkIndex }
        let covered = Set(completedChunks.flatMap { $0.result.scenes.map(\.sceneOrdinal) })
        let uncovered = context.chunks.flatMap(\.scenes).map(\.ordinal).filter { !covered.contains($0) }
        if completedChunks.isEmpty {
            throw ExtractionRunError.allChunksFailed(
                try await chunkFailureDetails(context: context)
            )
        }
        emit(.reconcile, "Reconciling entities")
        let reconcile = try await runReconcile(chunks: completedChunks, context: context)
        let proposal = try ExtractionProposalBuilder.build(
            scriptID: context.script.id,
            scriptSHA256: context.script.sha256,
            settings: context.settings,
            chunks: completedChunks,
            reconcile: reconcile,
            chunksFailed: failures.count,
            uncoveredSceneOrdinals: uncovered
        )
        _ = try await project.transitionJob(id: context.runID, to: .validating, progress: "Validating run")
        _ = try await project.transitionJob(id: context.runID, to: .committing, progress: "Finishing commit")
        emit(.apply, "Applying proposed facts")
        let report = try await project.applyExtractionRun(
            proposal,
            runJobID: context.runID,
            usage: JobUsage.sum(childUsage.values)
        )
        lastReport = report
        emit(.completed, "Analysis complete")
        continuation?.finish()
        self.context = nil
    }

    private func runReconcile(
        chunks: [CompletedChunkExtraction],
        context: Context
    ) async throws -> ReconcileResult {
        let input = try await ReconcileInputBuilder.build(
            chunks: chunks.map { ($0.chunkIndex, $0.result) },
            project: project
        )
        let payload = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let jobID = UUID()
        let paths = try await project.prepareChildPaths(runID: context.runID, jobID: jobID)
        try Data(payload.utf8).write(to: paths.inputURL, options: .atomic)
        _ = try await project.createJob(JobRequest(
            id: jobID, task: "reconcileEntities", engine: context.engine,
            engineVersion: context.engineVersion, requestedModel: context.settings.reconcileModel,
            schemaVersion: ReconcileEntitiesSchema.version, inputSHA256: digest(payload),
            logRelativePath: paths.logRelativePath, resultRelativePath: paths.resultRelativePath,
            parentJobID: context.runID, attemptIndex: 0,
            scriptID: context.script.id, scriptSHA256: context.script.sha256
        ))
        activeJobIDs.insert(jobID)
        defer { activeJobIDs.remove(jobID) }
        _ = try await project.transitionJob(id: jobID, to: .discoveringHarness, progress: "Preparing harness")
        _ = try await project.transitionJob(id: jobID, to: .running, progress: "Reconciling")
        let names = Set(input.chunkEntities.map(\.name))
        let task = ReconcileEntitiesTask(
            existingIDs: Set(input.canonicalEntities.map(\.id)),
            chunkEntityNames: names
        )
        let taskInput = StructuredTaskInput(
            jobID: jobID, text: payload, scriptID: context.script.id,
            scriptSHA256: context.script.sha256,
            requestedModel: context.settings.reconcileModel,
            reasoningEffort: context.settings.reconcileEffort
        )
        let request = HarnessRequest(
            jobID: jobID, prompt: try task.prompt(for: taskInput),
            workspaceURL: try await project.prepareRunWorkspace(runID: context.runID).workspaceURL,
            schemaURL: task.schemaURL, resultURL: paths.resultURL, logURL: paths.logURL,
            model: context.settings.reconcileModel, reasoningEffort: context.settings.reconcileEffort
        )
        var usage = JobUsage.empty
        var success = false
        do {
            for try await event in await adapter.events(for: request) {
                switch event {
                case let .completed(value): usage = value; success = true
                case let .started(_, model): try await project.setEffectiveModel(jobID: jobID, effectiveModel: model)
                case let .failed(code, message, kind):
                    _ = try await project.transitionJob(
                        id: jobID, to: .failed, progress: "Failed",
                        failureCode: code, failureMessage: message
                    )
                    switch kind {
                    case let .usageLimit(hint):
                        pausedHint = hint ?? "Codex usage is temporarily unavailable."
                        _ = try await project.transitionJob(
                            id: context.runID, to: .paused,
                            progress: hint ?? "Codex usage limit reached"
                        )
                        emit(.paused, pausedHint!)
                        throw ExtractionRunError.usageLimit(resetHint: hint)
                    case .unknownModel:
                        throw ExtractionRunError.unknownModel(
                            context.settings.reconcileModel ?? "account default"
                        )
                    case .retryable, .fatal:
                        throw ExtractionRunError.reconcileFailed(message)
                    }
                case .cancelled:
                    _ = try? await project.transitionJob(
                        id: jobID, to: .cancelled, progress: "Cancelled"
                    )
                    throw ExtractionRunError.cancelled
                default: break
                }
            }
        } catch let error as ExtractionRunError {
            throw error
        } catch {
            _ = try? await project.transitionJob(
                id: jobID, to: .failed, progress: "Failed",
                failureCode: "adapter_error", failureMessage: "The reconcile response could not be read."
            )
            throw ExtractionRunError.reconcileFailed("The reconcile response could not be read.")
        }
        guard success else { throw ExtractionRunError.reconcileFailed("Reconcile ended early.") }
        _ = try await project.transitionJob(id: jobID, to: .validating, progress: "Validating")
        let result: ReconcileResult
        do {
            result = try task.validate(resultFileAt: paths.resultURL)
        } catch let failure as StructuredValidationFailure {
            let diagnostic = validationDiagnostic(failure, subject: "entity reconciliation")
            _ = try? await project.transitionJob(
                id: jobID, to: .failed, progress: "Failed",
                failureCode: diagnostic.code,
                failureMessage: diagnostic.message
            )
            throw ExtractionRunError.reconcileFailed(diagnostic.message)
        } catch {
            _ = try? await project.transitionJob(
                id: jobID, to: .failed, progress: "Failed",
                failureCode: "validation_error",
                failureMessage: "The entity reconciliation result could not be validated."
            )
            throw ExtractionRunError.reconcileFailed(
                "The entity reconciliation result could not be validated."
            )
        }
        _ = try await project.completeJob(id: jobID, usage: usage)
        childUsage[jobID] = usage
        return result
    }

    private func nextAttemptIndex(chunk: Int, context: Context) async throws -> Int {
        let attempts = try await project.jobHistory().filter {
            $0.parentJobID == context.runID && $0.chunkIndex == chunk
        }.compactMap(\.attemptIndex)
        return (attempts.max() ?? -1) + 1
    }

    private func chunkFailureDetails(context: Context) async throws -> [String] {
        let attempts = try await project.jobHistory().filter {
            $0.parentJobID == context.runID && $0.task == "extractChunk"
                && $0.state == .failed && $0.chunkIndex != nil
        }
        var newestByChunk: [Int: Job] = [:]
        for attempt in attempts {
            guard let chunkIndex = attempt.chunkIndex else { continue }
            if let current = newestByChunk[chunkIndex],
               (current.attemptIndex ?? 0) > (attempt.attemptIndex ?? 0)
            {
                continue
            }
            newestByChunk[chunkIndex] = attempt
        }
        return context.chunks.map { chunk in
            let attempt = newestByChunk[chunk.index]
            let reason = attempt?.failureMessage
                ?? attempt?.failureCode
                ?? "Codex did not return a usable result."
            return "Chunk \(chunk.index + 1): \(reason)"
        }
    }

    private func validationDiagnostic(
        _ failure: StructuredValidationFailure,
        subject: String
    ) -> (code: String, message: String) {
        guard failure.code == .semanticViolation else {
            return (failure.code.rawValue, failure.message)
        }
        if let semantic = ExtractionSemanticCode(rawValue: failure.message) {
            return (semantic.rawValue, semantic.failureMessage)
        }
        return (
            failure.code.rawValue,
            "Codex returned a \(subject) result that failed semantic validation."
        )
    }

    private func requireScript() async throws -> Script {
        guard let script = try await project.script() else { throw ExtractionRunError.noScreenplay }
        return script
    }

    private func buildChunks(budgetUTF16: Int) async throws -> [ExtractionChunk] {
        let scenes = try await project.scenes()
        var text: [UUID: String] = [:]
        for scene in scenes {
            text[scene.id] = ChunkTextBuilder.redact(
                sceneText: try await project.sceneText(id: scene.id),
                exclusions: try await project.sceneExclusions(id: scene.id),
                sceneStartUTF16: scene.range.start
            ).text
        }
        return ExtractionChunker.chunks(
            scenes: scenes,
            modelText: { text[$0] ?? "" },
            budgetUTF16: budgetUTF16
        )
    }

    private func reuseKey(
        chunk: ExtractionChunk,
        engine: String,
        engineVersion: String,
        model: String?,
        effort: String?
    ) -> String {
        digest([
            ExtractChunkPrompt.instructionsSHA256,
            String(ExtractChunkSchema.version),
            String(ExtractChunkValidator.version),
            engine,
            engineVersion,
            model ?? "<account-default>",
            effort ?? "<account-default>",
            chunk.text,
        ].joined(separator: "\u{1F}"))
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func emit(_ stage: ExtractionRunProgress.Stage, _ message: String) {
        continuation?.yield(.init(stage: stage, message: message))
    }
}
