import FilmCore
import SwiftUI

/// §3.5's merge over a multi-selection: the operator picks which of the selected entities
/// **survives**, and every other selected row is merged into it.
///
/// The refusals are FilmCore's — a lock over a source or over one of its aliases, a
/// whole-record lock on the target, a kind mismatch — and are surfaced verbatim. A source
/// name whose normalized form already belongs to an unrelated third entity is not a
/// refusal at all: the alias insert is skipped and reported, and this sheet is where that
/// report is read.
struct MergeSheet: View {
    @Bindable var model: ProjectWindowModel

    @State private var targetID: UUID?
    @State private var skippedAliases: [String] = []
    @State private var isMerging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Merge \(candidates.count) Entities")
                .font(.headline)
                .accessibilityIdentifier("mergeSheetTitle")

            if skippedAliases.isEmpty {
                Text("Everything else you selected is merged into the entity you keep. Its aliases, appearances, states, events, relationships, and evidence move with it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Keep").font(.subheadline)
                List(candidates, selection: targetBinding) { candidate in
                    Text(candidate.name).tag(candidate.id)
                }
                .frame(minHeight: 140)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("mergeTargetList")
                .accessibilityLabel("Entity to keep")
            } else {
                Text("Merged. These names already belong to another entity of the same kind, so they were not added as aliases: \(skippedAliases.joined(separator: ", ")).")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mergeSkippedAliases")
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if skippedAliases.isEmpty {
                    Button("Cancel") { model.presentedSheet = nil }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("cancelMergeButton")
                        .accessibilityLabel("Cancel merge")
                    Button("Merge") { merge() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(targetID == nil || isMerging)
                        .accessibilityIdentifier("confirmMergeButton")
                        .accessibilityLabel("Merge entities")
                } else {
                    Button("Done") { model.presentedSheet = nil }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("mergeDoneButton")
                        .accessibilityLabel("Done")
                }
            }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mergeSheet")
        .accessibilityLabel("Merge entities")
        // The first row is preselected so the common case is one click; §3.5 gives the
        // outcome no default of its own, so any of them is as good a survivor.
        .onAppear { targetID = targetID ?? candidates.first?.id }
    }

    private var candidates: [EntitySummary] { model.selectedEntitySummaries }

    private var targetBinding: Binding<UUID?> {
        Binding(get: { targetID }, set: { targetID = $0 ?? targetID })
    }

    private func merge() {
        guard let targetID else { return }
        let sources = candidates.map(\.id).filter { $0 != targetID }
        guard !sources.isEmpty else { return }
        isMerging = true
        Task {
            let skipped = await model.mergeEntities(sourceIDs: sources, into: targetID)
            isMerging = false
            // A refusal has already surfaced through the window's alert; nothing more to
            // report here, so the sheet just closes.
            guard let skipped, !skipped.isEmpty else {
                model.presentedSheet = nil
                return
            }
            skippedAliases = skipped
        }
    }
}
