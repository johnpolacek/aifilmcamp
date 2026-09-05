import FilmCore
import Foundation
import SwiftUI

/// One continuous analysis surface: one confirmation, then visible work and its outcome.
/// The log is deliberately product-level progress only; raw Codex payloads can contain the
/// screenplay and stay in the project job log rather than being copied into view state.
struct AnalysisWorkflowSheet: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        if let workflow = model.analysisWorkflow {
            VStack(alignment: .leading, spacing: 18) {
                content(for: workflow)
            }
            .padding(24)
            .frame(width: 680)
            .frame(minHeight: minimumHeight(for: workflow.phase))
            .interactiveDismissDisabled(workflow.phase.isTerminal == false)
            .accessibilityIdentifier(accessibilityIdentifier(for: workflow.phase))
        }
    }

    @ViewBuilder
    private func content(for workflow: AnalysisWorkflowPresentation) -> some View {
        switch workflow.phase {
        case .confirmation:
            confirmation(workflow)
        case .running:
            progress(workflow, isPaused: false)
        case .paused:
            progress(workflow, isPaused: true)
        case let .completed(completion):
            completionView(completion, workflow: workflow)
        case let .failed(failure):
            failureView(failure, workflow: workflow)
        case .cancelled:
            cancelledView(workflow)
        }
    }

    private func confirmation(_ workflow: AnalysisWorkflowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Analyze Screenplay?", systemImage: "wand.and.stars")
                .font(.title2.bold())

            Label(
                "About \(workflow.requestCount) Codex requests",
                systemImage: "arrow.up.arrow.down.circle"
            )
            Text("Retries may add a few requests. This analysis runs once; afterward you edit the breakdown here.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if workflow.requiresDisclosure {
                Divider()
                Label("Before analyzing", systemImage: "hand.raised.fill")
                    .font(.headline)
                Text(ExtractionDisclosureText.firstRun)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    model.cancelPreparedExtraction()
                }
                Spacer()
                Button(workflow.requiresDisclosure ? "Continue & Analyze" : "Analyze") {
                    Task { await model.startPreparedExtraction() }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("confirmAnalyzeButton")
            }
        }
    }

    private func progress(
        _ workflow: AnalysisWorkflowPresentation,
        isPaused: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.title)
                        .foregroundStyle(.orange)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(isPaused ? "Analysis paused" : "Analyzing screenplay")
                        .font(.title2.bold())
                    Text(model.extractionProgress?.message ?? "Preparing analysis")
                        .foregroundStyle(.secondary)
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("Elapsed").foregroundStyle(.secondary)
                        Text(elapsed(from: workflow.startedAt, to: context.date))
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Screenplay").foregroundStyle(.secondary)
                        Text("\(model.scenes.count) scenes")
                    }
                    GridRow {
                        Text("Plan").foregroundStyle(.secondary)
                        Text("About \(workflow.requestCount) Codex requests")
                    }
                }
            }

            currentWork(workflow)
            activityLog(workflow.activity)

            HStack {
                if isPaused {
                    Button("Resume") {
                        Task { await model.resumeExtraction() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("resumeExtractionButton")
                } else {
                    Button("Pause") {
                        Task { await model.pauseExtraction() }
                    }
                    .disabled(workflow.runID == nil)
                    .accessibilityIdentifier("pauseExtractionButton")
                }
                Spacer()
                Button("Cancel Analysis", role: .destructive) {
                    Task { await model.cancelExtraction() }
                }
                .disabled(workflow.runID == nil)
                .accessibilityIdentifier("cancelExtractionButton")
            }
        }
    }

    @ViewBuilder
    private func currentWork(_ workflow: AnalysisWorkflowPresentation) -> some View {
        let jobs = currentJobs(workflow)
        if jobs.isEmpty == false {
            GroupBox("Current work") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(jobs) { job in
                        HStack {
                            Text(jobTitle(job))
                            Spacer()
                            if job.state == .failed {
                                Text(job.progressStage)
                                    .foregroundStyle(.red)
                            } else {
                                Text(job.progressStage == Job.reusedProgressStage
                                     ? Job.reusedProgressStage : job.state.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func completionView(
        _ completion: AnalysisCompletionPresentation,
        workflow: AnalysisWorkflowPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                completion.failureDetails.isEmpty ? "Analysis complete" : "Analysis complete with warnings",
                systemImage: completion.failureDetails.isEmpty
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(completion.failureDetails.isEmpty ? .green : .orange)

            AnalysisReportView(report: completion.report)
            if completion.failureDetails.isEmpty == false {
                failureDetails(completion.failureDetails)
            }
            activityLog(workflow.activity)
            doneButton()
        }
    }

    private func failureView(
        _ failure: AnalysisFailurePresentation,
        workflow: AnalysisWorkflowPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Analysis failed", systemImage: "xmark.octagon.fill")
                .font(.title2.bold())
                .foregroundStyle(.red)
            Text(failure.message)
                .textSelection(.enabled)
            Text("No screenplay changes were applied. Close this window to retry.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if failure.details.isEmpty == false {
                failureDetails(failure.details)
            }
            activityLog(workflow.activity)
            doneButton()
        }
    }

    private func cancelledView(_ workflow: AnalysisWorkflowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Analysis cancelled", systemImage: "xmark.circle.fill")
                .font(.title2.bold())
            Text("No screenplay changes were applied.")
                .foregroundStyle(.secondary)
            activityLog(workflow.activity)
            doneButton()
        }
    }

    private func failureDetails(_ details: [AnalysisFailureDetail]) -> some View {
        GroupBox("Why it stopped") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(details) { detail in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(detail.title).font(.headline)
                        Text(detail.message).textSelection(.enabled)
                        if let code = detail.code {
                            Text("Code: \(code)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func activityLog(_ entries: [AnalysisActivityEntry]) -> some View {
        GroupBox("Activity log") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(entry.at.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 82, alignment: .leading)
                            Text(entry.message)
                                .font(.caption)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
        }
        .accessibilityIdentifier("analysisActivityLog")
    }

    private func doneButton() -> some View {
        HStack {
            Spacer()
            Button("Done") {
                model.dismissAnalysisWorkflow()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("applyReportDoneButton")
        }
    }

    private func currentJobs(_ workflow: AnalysisWorkflowPresentation) -> [Job] {
        guard let runID = workflow.runID else { return [] }
        return model.jobs.filter { $0.parentJobID == runID }.sorted {
            if $0.chunkIndex != $1.chunkIndex {
                return ($0.chunkIndex ?? Int.max) < ($1.chunkIndex ?? Int.max)
            }
            return ($0.attemptIndex ?? 0) < ($1.attemptIndex ?? 0)
        }
    }

    private func jobTitle(_ job: Job) -> String {
        if let chunkIndex = job.chunkIndex {
            return "Chunk \(chunkIndex + 1) · attempt \((job.attemptIndex ?? 0) + 1)"
        }
        return job.task == "reconcileEntities" ? "Entity reconciliation" : job.task
    }

    private func elapsed(from start: Date?, to end: Date) -> String {
        guard let start else { return "0:00" }
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func minimumHeight(for phase: AnalysisWorkflowPhase) -> CGFloat {
        switch phase {
        case .confirmation: 0
        case .running, .paused: 520
        case .completed, .failed, .cancelled: 420
        }
    }

    private func accessibilityIdentifier(for phase: AnalysisWorkflowPhase) -> String {
        switch phase {
        case .confirmation: "analysisConfirmationSheet"
        case .running, .paused: "analysisProgressSheet"
        case .completed: "applyReportSheet"
        case .failed: "analysisFailureSheet"
        case .cancelled: "analysisCancelledSheet"
        }
    }
}

private struct AnalysisReportView: View {
    let report: ApplyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                reportRow("Applied", report.applied)
                reportRow("Replaced", report.replaced)
                reportRow("Merges applied", report.mergesApplied)
                reportRow("Merge suggestions", report.mergesSuggested)
                reportRow(
                    "Skipped locked",
                    report.skippedLocked,
                    identifier: "applyReportSkippedLocked"
                )
                reportRow("Skipped protected", report.skippedProtected)
                reportRow("Skipped parser-owned", report.skippedParserOwned)
                reportRow("Skipped rejected", report.skippedRejected)
                reportRow("Alias conflicts", report.aliasConflicts)
                reportRow("Unanchored evidence", report.unanchoredEvidence)
                reportRow("Chunks failed", report.chunksFailed)
            }
            if report.uncoveredSceneOrdinals.isEmpty == false {
                Text("Uncovered scenes: \(report.uncoveredSceneOrdinals.map(String.init).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(
                "Skipped locked \(report.skippedLocked); skipped parser-owned \(report.skippedParserOwned)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("applyReportSummary")
        }
    }

    private func reportRow(
        _ title: String,
        _ value: Int,
        identifier: String? = nil
    ) -> some View {
        GridRow {
            Text(title)
            Text(value, format: .number)
                .monospacedDigit()
                .accessibilityIdentifier(identifier ?? "applyReport_\(title)")
                .accessibilityLabel("\(title) \(value)")
        }
    }
}
