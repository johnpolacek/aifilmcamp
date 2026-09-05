import FilmCore
import SwiftUI

/// The **one-way** v1 upgrade modal (§5.5, contract D).
///
/// `ProjectBundle.inspect(at:)` reports the schema version without opening the database, so
/// this is shown *before* anything is migrated. Cancel opens nothing; Upgrade opens the
/// bundle — which is what migrates it — and the window then shows `UpgradeSummarySheet`.
struct MigrationUpgradeSheet: View {
    let url: URL
    let onCancel: () -> Void
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Upgrade This Project?")
                    .font(.title2.weight(.semibold))
                Text(url.deletingPathExtension().lastPathComponent)
                    .foregroundStyle(.secondary)
            }

            Text("This project was made by an earlier version of AI Film Camp. Opening it upgrades it, and the upgrade cannot be undone.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Scenes are rebuilt from the screenplay parser.",
                    systemImage: "film"
                )
                Label(
                    "Scene synopses written by the model are dropped when the new scene count differs.",
                    systemImage: "text.badge.minus"
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Duplicate the project in Finder first if you want to keep a copy of the old version.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("migrationCancelButton")
                    .accessibilityLabel("Cancel")
                Button("Upgrade", action: onUpgrade)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("migrationUpgradeButton")
                    .accessibilityLabel("Upgrade")
            }
        }
        .padding(24)
        .frame(minWidth: 460)
        // `.contain` keeps the sheet a container: identifying it without this collapses it
        // into one element and hides the counts and buttons from accessibility clients.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("migrationUpgradeSheet")
        .accessibilityLabel("Upgrade Project")
    }
}

/// What the migration actually did (§4.2), from `ProjectSession.upgradeSummary`.
///
/// Distinct from `ImportSummarySheet`: `open` yields a session rather than an
/// `ImportSummary`, and the parse warnings exist only because Plan 003 persists them.
struct UpgradeSummarySheet: View {
    let summary: UpgradeSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Upgraded")
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Bundle format", value: "Version \(summary.fromVersion) → \(summary.toVersion)")
                row("Scenes", value: "\(summary.sceneCount)")
                row("Entities", value: "\(summary.entityCount)")
                row("Sequences", value: "\(summary.sequenceCount)")
                row("Synopses dropped", value: "\(summary.synopsesDropped)")
            }

            warnings

            HStack {
                Spacer()
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("upgradeSummaryDoneButton")
                    .accessibilityLabel("Done")
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        // `.contain` keeps the sheet a container: identifying it without this collapses it
        // into one element and hides the counts and buttons from accessibility clients.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upgradeSummarySheet")
        .accessibilityLabel("Upgrade Summary")
    }

    @ViewBuilder
    private var warnings: some View {
        if summary.parseWarnings.isEmpty {
            Text("No parser warnings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Parser Warnings")
                    .font(.headline)
                ForEach(Array(summary.parseWarnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
    }
}
