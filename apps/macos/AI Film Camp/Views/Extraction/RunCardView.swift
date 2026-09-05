import FilmCore
import SwiftUI

struct RunCardView: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headline)
                .font(.headline)
            if let run = currentRun {
                Text("\(tokenTotal(run.usage)) tokens total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // A manifest run is childless by design (§8.1: one request, no fan-out), so
                // the chunk lines below are simply absent rather than totalling nothing.
                ForEach(children(of: run)) { child in
                    HStack {
                        Text(attemptTitle(child))
                        Spacer()
                        Text(child.progressStage == Job.reusedProgressStage
                             ? Job.reusedProgressStage : child.state.displayName)
                        Text("\(tokenTotal(child.usage))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            if model.activeExtractionRun != nil {
                HStack {
                    if model.extractionProgress?.stage == .paused {
                        Button("Resume") { Task { await model.resumeExtraction() } }
                            .accessibilityIdentifier("resumeExtractionButton")
                    } else {
                        Button("Pause") { Task { await model.pauseExtraction() } }
                            .accessibilityIdentifier("pauseExtractionButton")
                    }
                    Button("Cancel", role: .destructive) {
                        Task { await model.cancelExtraction() }
                    }
                    .accessibilityIdentifier("cancelExtractionButton")
                }
            }
            // The manifest run has no pause and no resume — one request either finishes or
            // is cancelled (§8.1).
            if model.activeManifestRun != nil {
                Button("Cancel", role: .destructive) {
                    Task { await model.cancelManifestRun() }
                }
                .accessibilityIdentifier("cancelManifestRunButton")
            }
        }
    }

    /// The active run's own progress line — the manifest run's when one is running, so the
    /// card never labels a manifest run "Analysis run".
    private var headline: String {
        if model.activeManifestRun != nil {
            return model.manifestProgress?.message ?? "Manifest run"
        }
        return model.extractionProgress?.message ?? "Analysis run"
    }

    private var currentRun: RunSummary? { model.runs.last }

    private func children(of run: RunSummary) -> [Job] {
        model.jobs.filter { $0.parentJobID == run.id }.sorted {
            if $0.chunkIndex != $1.chunkIndex { return ($0.chunkIndex ?? Int.max) < ($1.chunkIndex ?? Int.max) }
            return ($0.attemptIndex ?? 0) < ($1.attemptIndex ?? 0)
        }
    }

    private func attemptTitle(_ job: Job) -> String {
        if let chunk = job.chunkIndex {
            return "Chunk \(chunk + 1) · attempt \((job.attemptIndex ?? 0) + 1)"
        }
        return job.task
    }

    private func tokenTotal(_ usage: JobUsage) -> Int {
        (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
    }
}
