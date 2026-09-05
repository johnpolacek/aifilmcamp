import FilmCore
import SwiftUI

/// The edit journal (§3.8), reached from **Edit ▸ Show Edit Journal…** — a sheet, not a
/// sidebar section (§3.11).
///
/// Read-only by construction: an entry is undone through ⌘Z, and a run through Revert
/// last run. There is no public generic "apply this operation" door, so there is nothing
/// here to click.
struct EditJournalView: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Journal")
                .font(.headline)
                .accessibilityIdentifier("editJournalTitle")

            if model.journalEntries.isEmpty {
                ContentUnavailableView("No edits yet.", systemImage: "list.bullet.rectangle")
            } else {
                List(model.journalEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.op.displayName)
                        Text("\(actorName(entry)) · \(Self.timestamp.string(from: entry.at))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("editJournalList")
                .accessibilityLabel("Edit journal entries")
            }

            HStack {
                Spacer()
                Button("Done") { model.presentedSheet = nil }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("editJournalDoneButton")
                    .accessibilityLabel("Done")
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 380)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editJournalSheet")
        .accessibilityLabel("Edit journal")
    }

    /// "You" for a human edit, the run for an AI one — the same distinction §3.6 keeps in
    /// `source` versus `created_source`.
    private func actorName(_ entry: JournalEntry) -> String {
        switch entry.actor {
        case .human: "You"
        case .ai:
            entry.jobID.flatMap { jobID in
                model.runs.first { $0.job.id == jobID }.map { "Run \($0.runNumber)" }
            } ?? "AI"
        }
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
