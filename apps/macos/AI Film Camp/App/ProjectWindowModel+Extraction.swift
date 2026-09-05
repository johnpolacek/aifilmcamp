import FilmBrain
import FilmCore
import Foundation

@MainActor
extension ProjectWindowModel {
    /// §3.6's one-run rule: analysis is offered until one has applied, never after.
    /// FilmCore refuses a second run outright (`.extractionAlreadyApplied`); this only
    /// keeps the toolbar from offering what the store would reject.
    ///
    /// §3.6 closes analysis a second way: a completed manifest run **permanently closes
    /// extraction for that screenplay**, because the manifest is built on the canonical data
    /// analysis would otherwise rewrite. `analyzeClosedByManifestReason` is the sentence the
    /// action shows for itself when that is why it is unavailable.
    var canAnalyze: Bool {
        script != nil && activeExtractionRun == nil && extractionAdapterFactory != nil
            && !isClosed && !hasAppliedExtractionRun && !extractionIsClosedByManifest
            && activeManifestRun == nil && analysisWorkflow == nil
    }

    /// A completed `extractScreenplay` parent that actually applied — the one run this
    /// project gets. A legacy all-chunks-failed row was incorrectly marked completed by
    /// older builds; `didApplyExtraction` keeps that unapplied attempt retryable.
    var hasAppliedExtractionRun: Bool {
        runs.contains { $0.job.didApplyExtraction }
    }

    var analyzeButtonTitle: String { "Analyze Screenplay" }

    /// The import summary's primary continuation. It closes the summary and reveals the
    /// parsed first scene before preparing analysis's single request-count/disclosure
    /// confirmation. Preparing is local; no Codex request starts until the operator chooses
    /// the sheet's one Continue & Analyze action.
    func analyzeImportedScreenplay() async {
        guard presentedImportSummary != nil, canAnalyze else { return }
        await dismissImportSummary()
        await prepareExtraction()
    }

    func prepareExtraction() async {
        guard canAnalyze, let extractionAdapterFactory else { return }
        do {
            let adapter = try extractionAdapterFactory()
            var settings = extractionSettingsProvider()
            if settings.chunkBudget <= 0 { settings.chunkBudget = 32_000 }
            let run = ExtractionRun(project: session, adapter: adapter, bundleURL: bundleURL)
            let requests = try await run.plannedRequestCount(
                engine: "codex",
                engineVersion: "current",
                settings: settings,
                budgetUTF16: settings.chunkBudget
            )
            let requiresDisclosure = try await session.disclosureAcknowledgedAt() == nil
            preparedExtraction = PreparedExtraction(
                run: run,
                settings: settings,
                requestCount: requests,
                requiresDisclosure: requiresDisclosure
            )
            analysisWorkflow = AnalysisWorkflowPresentation(
                requestCount: requests,
                requiresDisclosure: requiresDisclosure
            )
        } catch {
            self.error = .project(error)
            preparedExtraction = nil
        }
    }

    func cancelPreparedExtraction() {
        guard analysisWorkflow?.phase == .confirmation else { return }
        analysisWorkflow = nil
        preparedExtraction = nil
    }

    func startPreparedExtraction() async {
        guard let preparedExtraction, activeExtractionRun == nil else { return }
        if preparedExtraction.requiresDisclosure {
            do {
                try await session.acknowledgeDisclosure()
            } catch {
                self.preparedExtraction = nil
                presentAnalysisFailure(
                    message: "The privacy acknowledgement could not be saved. \(error.localizedDescription)",
                    details: []
                )
                return
            }
        }
        self.preparedExtraction = nil
        activeExtractionRun = preparedExtraction.run
        extractionProgress = .init(stage: .planning, message: "Planning extraction")
        updateAnalysisWorkflow { workflow in
            workflow.phase = .running
            workflow.startedAt = Date()
            workflow.activity = [
                AnalysisActivityEntry(
                    at: Date(),
                    message: "Prepared about \(preparedExtraction.requestCount) Codex requests."
                ),
            ]
        }
        await startProgressObservation(for: preparedExtraction.run)
        await executeExtraction(preparedExtraction.run) {
            try await preparedExtraction.run.start(
                engine: "codex",
                engineVersion: "current",
                settings: preparedExtraction.settings,
                budgetUTF16: preparedExtraction.settings.chunkBudget
            )
        }
    }

    func pauseExtraction() async {
        guard let activeExtractionRun else { return }
        do {
            try await activeExtractionRun.pause()
        } catch {
            self.error = .project(error)
        }
    }

    func resumeExtraction() async {
        guard let activeExtractionRun else { return }
        updateAnalysisWorkflow { $0.phase = .running }
        recordAnalysisActivity("Resuming the paused analysis.")
        await executeExtraction(activeExtractionRun) {
            try await activeExtractionRun.resume()
        }
    }

    func cancelExtraction() async {
        guard let activeExtractionRun else { return }
        do {
            try await activeExtractionRun.cancel()
        } catch ExtractionRunError.cancelled {
            // Cancellation is the requested outcome.
        } catch {
            self.error = .project(error)
        }
        extractionProgressTask?.cancel()
        extractionProgressTask = nil
        self.activeExtractionRun = nil
        extractionProgress = .init(stage: .cancelled, message: "Analysis cancelled")
        recordAnalysisActivity("Analysis cancelled. No screenplay changes were applied.")
        updateAnalysisWorkflow { $0.phase = .cancelled }
        await refresh()
    }

    func dismissAnalysisWorkflow() {
        guard analysisWorkflow?.phase.isTerminal == true else { return }
        analysisWorkflow = nil
    }

    func clearJobCache() async {
        do {
            presentedCacheSummary = CacheSummaryPresentation(
                summary: try await session.clearJobCache()
            )
        } catch {
            self.error = .project(error)
        }
    }

    func revertNewestRunAndPresentReport() async {
        guard let report = await revertLastRun() else { return }
        presentedRevertReport = RevertReportPresentation(report: report)
    }

    func addMissingEntity() async {
        guard let kind = section.entityKind else { return }
        let existing = entitySummaries[kind] ?? []
        let noun = kind.displayName
        let taken = Set(existing.map { $0.name.lowercased() })
        var name = "New \(noun)"
        var suffix = 2
        while taken.contains(name.lowercased()) {
            name = "New \(noun) \(suffix)"
            suffix += 1
        }
        guard let id = await createEntity(kind: kind, name: name) else { return }
        // Human additions are accepted immediately and therefore do not belong in the
        // Proposed filter. Reveal the created row before selecting it so the next
        // changes() refresh cannot prune the selection while the operator renames it.
        if entityReviewFilter != .all {
            await setEntityReviewFilter(.all)
        }
        setSelection([id], in: section)
        await loadEntityDetail()
        beginRename()
    }

    private func startProgressObservation(for run: ExtractionRun) async {
        extractionProgressTask?.cancel()
        // Install the actor's continuation before start() can emit. Creating a Task that
        // obtains the stream later races fast recorded runs and can leave the toolbar
        // permanently showing the locally seeded "Planning extraction" state.
        let stream = await run.progress()
        extractionProgressTask = Task { [weak self] in
            for await progress in stream {
                guard let self, !Task.isCancelled else { return }
                self.extractionProgress = progress
                if let runID = await run.runJobID {
                    self.updateAnalysisWorkflow { $0.runID = runID }
                }
                self.recordAnalysisActivity(self.activityMessage(for: progress))
                guard self.analysisWorkflow?.phase.isTerminal == false else { continue }
                switch progress.stage {
                case .paused:
                    self.updateAnalysisWorkflow { $0.phase = .paused }
                case .planning, .warmup, .fanout, .reconcile, .apply:
                    self.updateAnalysisWorkflow { $0.phase = .running }
                case .completed, .failed, .cancelled:
                    break
                }
            }
        }
    }

    private func executeExtraction(
        _ run: ExtractionRun,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            if let report = await run.lastReport {
                undoManager.removeAllActions()
                syncUndoMenu()
                activeExtractionRun = nil
                extractionProgressTask?.cancel()
                extractionProgressTask = nil
                await refresh()
                let runID = await run.runJobID
                let details = report.chunksFailed > 0
                    ? analysisFailureDetails(for: runID)
                    : []
                extractionProgress = .init(stage: .completed, message: "Analysis complete")
                recordAnalysisActivity("Analysis completed and proposed facts were applied.")
                updateAnalysisWorkflow { workflow in
                    workflow.runID = runID
                    workflow.phase = .completed(
                        AnalysisCompletionPresentation(
                            report: report,
                            failureDetails: details
                        )
                    )
                }
            }
        } catch ExtractionRunError.cancelled {
            activeExtractionRun = nil
            extractionProgressTask?.cancel()
            extractionProgressTask = nil
            extractionProgress = .init(stage: .cancelled, message: "Analysis cancelled")
            recordAnalysisActivity("Analysis cancelled. No screenplay changes were applied.")
            updateAnalysisWorkflow { $0.phase = .cancelled }
            await refresh()
        } catch {
            activeExtractionRun = nil
            extractionProgressTask?.cancel()
            extractionProgressTask = nil
            await refresh()
            let runID = await run.runJobID
            let details = analysisFailureDetails(for: runID)
            extractionProgress = .init(stage: .failed, message: "Analysis failed")
            recordAnalysisActivity("Analysis stopped: \(error.localizedDescription)")
            updateAnalysisWorkflow { $0.runID = runID }
            presentAnalysisFailure(message: error.localizedDescription, details: details)
        }
    }

    private func analysisFailureDetails(for runID: UUID?) -> [AnalysisFailureDetail] {
        guard let runID else { return [] }
        return jobs.filter {
            $0.parentJobID == runID && $0.state == .failed
        }.sorted {
            if $0.chunkIndex != $1.chunkIndex {
                return ($0.chunkIndex ?? Int.max) < ($1.chunkIndex ?? Int.max)
            }
            return ($0.attemptIndex ?? 0) < ($1.attemptIndex ?? 0)
        }.map { job in
            let title: String
            if let chunkIndex = job.chunkIndex {
                title = "Chunk \(chunkIndex + 1) · attempt \((job.attemptIndex ?? 0) + 1)"
            } else if job.task == "reconcileEntities" {
                title = "Entity reconciliation"
            } else {
                title = job.task
            }
            return AnalysisFailureDetail(
                id: job.id,
                title: title,
                code: job.failureCode,
                message: job.failureMessage ?? "The job failed without an additional message."
            )
        }
    }

    private func presentAnalysisFailure(
        message: String,
        details: [AnalysisFailureDetail]
    ) {
        updateAnalysisWorkflow { workflow in
            workflow.phase = .failed(
                AnalysisFailurePresentation(message: message, details: details)
            )
        }
    }

    private func recordAnalysisActivity(_ message: String) {
        updateAnalysisWorkflow { workflow in
            guard workflow.activity.last?.message != message else { return }
            workflow.activity.append(AnalysisActivityEntry(at: Date(), message: message))
        }
    }

    private func updateAnalysisWorkflow(
        _ update: (inout AnalysisWorkflowPresentation) -> Void
    ) {
        guard var workflow = analysisWorkflow else { return }
        update(&workflow)
        analysisWorkflow = workflow
    }

    private func activityMessage(for progress: ExtractionRunProgress) -> String {
        switch progress.stage {
        case .planning:
            "Preparing screenplay chunks and the analysis workspace."
        case .warmup:
            "Sent the first screenplay chunk to Codex; waiting for structured analysis."
        case .fanout:
            "Finished the first chunk request; checking for remaining screenplay chunks."
        case .paused:
            "Analysis paused: \(progress.message)"
        case .reconcile:
            "Reconciling recurring characters, locations, and other entities."
        case .apply:
            "Validating and applying proposed facts in one transaction."
        case .completed:
            "Analysis completed."
        case .failed:
            "Analysis failed: \(progress.message)"
        case .cancelled:
            "Analysis cancelled."
        }
    }
}
