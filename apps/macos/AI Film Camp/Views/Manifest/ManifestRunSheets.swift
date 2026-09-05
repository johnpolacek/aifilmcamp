import FilmCore
import SwiftUI

/// PHASE2_DESIGN §9's first-run acknowledgement, shown when
/// `projects.disclosure_acknowledged_at` is nil — which a project can legitimately reach
/// without ever running extraction (bare import + Build + inference).
///
/// The copy is `ManifestDisclosureText.firstRun`, verbatim; acceptance stores the
/// acknowledgement through the door extraction shares. Nothing is sent until Continue.
struct ManifestDisclosureSheet: View {
    let continueAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Before building the manifest", systemImage: "hand.raised.fill")
                .font(.title2.bold())
            Text(ManifestDisclosureText.firstRun)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manifestDisclosureText")
            HStack {
                Button("Cancel", role: .cancel, action: cancelAction)
                Spacer()
                Button("Continue", action: continueAction)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("continueManifestDisclosureButton")
            }
        }
        .padding(24)
        .frame(width: 580)
        .accessibilityIdentifier("manifestDisclosureSheet")
    }
}

/// §9's compact confirm sheet, shown before **every** manifest run.
struct ManifestConfirmSheet: View {
    let inferAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Infer Asset Manifest?")
                .font(.title2.bold())
            Text(ManifestDisclosureText.everyRun)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manifestConfirmText")
            HStack {
                Button("Cancel", role: .cancel, action: cancelAction)
                Spacer()
                Button("Infer", action: inferAction)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("confirmInferManifestButton")
            }
        }
        .padding(24)
        .frame(width: 560)
        .accessibilityIdentifier("manifestConfirmSheet")
    }
}

/// §8.5's counters, in the shape `ApplyReportSheet` gives extraction's.
struct ManifestReportSheet: View {
    let report: ManifestApplyReport
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manifest inference complete").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                reportRow("Created", report.created)
                reportRow("Skipped existing", report.skippedExisting)
                reportRow("Skipped rejected", report.skippedRejected)
                reportRow("Skipped protected", report.skippedProtected)
                reportRow("Skipped locked", report.skippedLocked)
                reportRow("Suggestions", report.suggestions.count)
            }
            Text(
                "Created \(report.created); skipped existing \(report.skippedExisting); "
                    + "suggestions \(report.suggestions.count)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("manifestReportSummary")
            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("manifestReportDoneButton")
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .accessibilityIdentifier("manifestReportSheet")
    }

    private func reportRow(_ title: String, _ value: Int) -> some View {
        GridRow {
            Text(title)
            Text(value, format: .number)
                .monospacedDigit()
                .accessibilityIdentifier("manifestReport_\(title)")
                .accessibilityLabel("\(title) \(value)")
        }
    }
}
