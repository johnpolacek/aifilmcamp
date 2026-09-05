import FilmCore
import SwiftUI

/// PHASE3_DESIGN §9's prompt-run sheets (Plan 016 contract E), in the shape the manifest
/// sheets give theirs. The copy is `PromptDisclosureText`, verbatim, asserted
/// character for character by `PromptRunModelTests`.
///
/// §9's batch variant ships only with the evidence-gated batch driver (§14.1, deferred on
/// the recorded Plan 016 posture), so nothing batch-shaped renders here.

/// §9's first-run acknowledgement, shown when `projects.disclosure_acknowledged_at` is nil
/// — reachable without either bootstrap acknowledged. Nothing is sent until Continue.
struct PromptDisclosureSheet: View {
    let continueAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Before generating prompts", systemImage: "hand.raised.fill")
                .font(.title2.bold())
            Text(PromptDisclosureText.firstRun)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("promptDisclosureText")
            HStack {
                Button("Cancel", role: .cancel, action: cancelAction)
                Spacer()
                Button("Continue", action: continueAction)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("continuePromptDisclosureButton")
            }
        }
        .padding(24)
        .frame(width: 580)
        // `.contain` keeps the sheet a container: identifying it without this collapses it
        // into one element and hides the buttons from accessibility clients (the ImportSummarySheet
        // posture).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promptDisclosureSheet")
    }
}

/// §9's compact confirm sheet, shown before **every** prompt run.
struct PromptConfirmSheet: View {
    let generateAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate this prompt?").font(.title2.bold())
            Text(PromptDisclosureText.everyRun)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("promptConfirmText")
            HStack {
                Button("Cancel", role: .cancel, action: cancelAction)
                Spacer()
                Button("Generate", action: generateAction)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("confirmGeneratePromptButton")
            }
        }
        .padding(24)
        .frame(width: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promptConfirmSheet")
    }
}

/// §8.7's regenerate-over-human-prompt confirm — the sheet that says where the edited
/// prompt went ("your edited prompt stays in history").
struct PromptRegenerateConfirmSheet: View {
    let continueAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Regenerate over your edited prompt?").font(.title2.bold())
            Text(WorkshopConfirmText.regenerateOverHumanPrompt)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("promptRegenerateConfirmText")
            Text(PromptDisclosureText.everyRun)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", role: .cancel, action: cancelAction)
                Spacer()
                Button("Continue", action: continueAction)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("confirmPromptRegenerateButton")
            }
        }
        .padding(24)
        .frame(width: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promptRegenerateConfirmSheet")
    }
}

/// §8.5's report, in the shape the manifest report gives its counters.
struct PromptReportSheet: View {
    let report: AssetPromptApplyReport
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prompt generated").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                reportRow("Prompt", report.promptNumber)
                reportRow("References", report.referenceCount)
            }
            if !report.targetModel.isEmpty {
                Text("Routed to \(report.targetModel).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("promptReportTargetModel")
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("promptReportDoneButton")
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promptReportSheet")
    }

    private func reportRow(_ title: String, _ value: Int) -> some View {
        GridRow {
            Text(title)
            Text(value, format: .number)
                .monospacedDigit()
                .accessibilityIdentifier("promptReport_\(title)")
                .accessibilityLabel("\(title) \(value)")
        }
    }
}
