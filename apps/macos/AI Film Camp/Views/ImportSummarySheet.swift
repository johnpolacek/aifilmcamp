import FilmCore
import SwiftUI

/// What one import wrote (contract D): format, scenes, characters, locations, sequences,
/// and the parser's warnings. Presented on **every** successful import; its primary action
/// continues into analysis's existing disclosure and request-count confirmation, while
/// dismissing it reveals the first scene without analyzing.
struct ImportSummarySheet: View {
    let summary: ImportSummary
    let onAnalyze: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Screenplay Imported")
                    .font(.title2.weight(.semibold))
                Text(summary.displayName)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Format", value: formatName, identifier: "importedFormat")
                row("Scenes", value: "\(summary.sceneCount)", identifier: "importedSceneCount")
                row("Characters", value: "\(summary.characterCount)", identifier: "importedCharacterCount")
                row("Locations", value: "\(summary.locationCount)", identifier: "importedLocationCount")
                row("Sequences", value: "\(summary.sequenceCount)", identifier: "importedSequenceCount")
            }

            warnings

            VStack(alignment: .leading, spacing: 4) {
                Text("Next: analyze the screenplay")
                    .font(.headline)
                Text(
                    "Identify characters, locations, props, continuity, and asset needs. "
                        + "You’ll review privacy details and the Codex request count before anything is sent."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("postImportAnalysisPrompt")

            HStack {
                Spacer()
                Button("Not Now", role: .cancel, action: onDismiss)
                    // Kept for the existing import automation contract; the action is now
                    // named for the choice it represents rather than generic dismissal.
                    .accessibilityIdentifier("importSummaryDoneButton")
                    .accessibilityLabel("Not Now")
                Button("Analyze Now", action: onAnalyze)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("importSummaryAnalyzeButton")
                    .accessibilityLabel("Analyze Screenplay Now")
            }
        }
        .padding(24)
        .frame(minWidth: 480)
        // `.contain` keeps the sheet a container: identifying it without this collapses it
        // into one element and hides the counts and buttons from accessibility clients.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importSummarySheet")
        .accessibilityLabel("Import Summary")
    }

    @ViewBuilder
    private var warnings: some View {
        if summary.warnings.isEmpty {
            Text("No parser warnings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("importWarnings")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Parser Warnings")
                    .font(.headline)
                ForEach(Array(summary.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("importWarnings")
        }
    }

    private var formatName: String {
        switch summary.format {
        case .fountain: "Fountain"
        case .fdx: "Final Draft"
        case .text: "Plain Text"
        case .pdf: "PDF"
        }
    }

    private func row(_ label: String, value: String, identifier: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
        }
    }
}
