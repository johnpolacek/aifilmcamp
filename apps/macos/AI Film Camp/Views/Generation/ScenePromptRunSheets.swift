import FilmBrain
import FilmCore
import SwiftUI

/// PHASE5_DESIGN §9's scene-prompt-run sheets (Plan 021 contract D), in the shape the
/// asset-prompt sheets give theirs. The one-time disclosure copy is
/// `ScenePromptDisclosureText`, verbatim.
///
/// §9's batch variant ships only with the evidence-gated batch driver (§14.1), which is
/// skipped whole while its gate is unmet — nothing batch-shaped renders here.

/// §9's first-run acknowledgement, shown when `projects.disclosure_acknowledged_at` is
/// nil. Nothing is sent until Continue.
struct ScenePromptDisclosureSheet: View {
    let continueAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Before preparing scene prompts", systemImage: "hand.raised.fill")
                .font(.title2.bold())
            Text(ScenePromptDisclosureText.firstRun)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scenePromptDisclosureText")
            HStack {
                Button("Cancel", role: .cancel, action: cancelAction)
                Spacer()
                Button("Continue", action: continueAction)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("continueScenePromptDisclosureButton")
            }
        }
        .padding(24)
        .frame(width: 580)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scenePromptDisclosureSheet")
    }
}

/// §8.5's report, in the shape the asset report gives its counters.
struct ScenePromptReportSheet: View {
    let report: ScenePromptApplyReport
    let summary: ScenePromptRunSummary?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scene prompt generated").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Prompt number")
                    Text(report.promptNumber, format: .number)
                        .monospacedDigit()
                        .accessibilityIdentifier("scenePromptReport_PromptNumber")
                }
                GridRow {
                    Text("References")
                    Text(report.referenceCount, format: .number)
                        .monospacedDigit()
                        .accessibilityIdentifier("scenePromptReport_References")
                }
            }
            Text("Profile: \(report.targetProfile).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("scenePromptReportTargetProfile")
            if let summary {
                Divider()
                Text("Run summary").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("Mode")
                        Text(summary.qualityMode == .highQuality ? "High Quality" : "Standard")
                    }
                    timingRow("Prepare", milliseconds: summary.preparationMilliseconds)
                    timingRow(
                        summary.qualityMode == .highQuality ? "Draft request" : "Generate request",
                        milliseconds: summary.draftMilliseconds,
                        usage: summary.draftUsage
                    )
                    if let improvementUsage = summary.improvementUsage {
                        timingRow(
                            "Improve request",
                            milliseconds: summary.improvementMilliseconds,
                            usage: improvementUsage
                        )
                    }
                    timingRow(
                        "Validate & save",
                        milliseconds: summary.validationAndSaveMilliseconds
                    )
                    GridRow {
                        Text("Total")
                        Text(Self.duration(summary.totalMilliseconds))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
                Text(Self.usageBreakdown(summary.totalUsage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scenePromptReportTokenBreakdown")
                Text(
                    "\(summary.requestCount) model request"
                        + (summary.requestCount == 1 ? "" : "s")
                        + summary.effectiveModel.map { " · \($0)" }.orEmpty
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("scenePromptReportRunSummary")
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("scenePromptReportDoneButton")
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scenePromptReportSheet")
    }

    @ViewBuilder
    private func timingRow(
        _ title: String,
        milliseconds: Int,
        usage: JobUsage? = nil
    ) -> some View {
        GridRow {
            Text(title)
            Text(Self.timingDetail(milliseconds: milliseconds, usage: usage))
                .monospacedDigit()
        }
    }

    private static func timingDetail(milliseconds: Int, usage: JobUsage?) -> String {
        guard let usage else { return duration(milliseconds) }
        let input = (usage.inputTokens ?? 0).formatted()
        let output = (usage.outputTokens ?? 0).formatted()
        return "\(duration(milliseconds)) · \(input) in · \(output) out"
    }

    private static func duration(_ milliseconds: Int) -> String {
        if milliseconds < 1_000 { return "\(milliseconds) ms" }
        let seconds = milliseconds / 1_000
        if seconds < 60 {
            return String(format: "%.1f s", Double(milliseconds) / 1_000)
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private static func usageBreakdown(_ usage: JobUsage) -> String {
        var parts = ["Input \((usage.inputTokens ?? 0).formatted())"]
        if let cached = usage.cachedInputTokens {
            parts.append("cached \(cached.formatted())")
        }
        if let cacheWrite = usage.cacheWriteInputTokens {
            parts.append("cache write \(cacheWrite.formatted())")
        }
        parts.append("output \((usage.outputTokens ?? 0).formatted())")
        if let reasoning = usage.reasoningOutputTokens {
            parts.append("reasoning \(reasoning.formatted())")
        }
        return parts.joined(separator: " · ")
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
