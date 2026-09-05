import FilmCore
import SwiftUI

/// PHASE2_DESIGN §7.2's combine over the Manifest list's multi-selection: the operator
/// picks which variant **survives**, and every other selected row is combined into it.
///
/// The refusals are FilmCore's and are surfaced verbatim — a lock on any participant, a
/// canonical-tier row, a cycle the combined graph would create. Cross-entity sources are
/// permitted, so the sheet does not require one entity; the combined requirement lives on
/// the survivor's entity.
struct CombineRequirementsSheet: View {
    @Bindable var model: ProjectWindowModel

    @State private var targetID: UUID?
    @State private var isCombining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Combine \(candidates.count) Requirements")
                .font(.headline)
                .accessibilityIdentifier("combineSheetTitle")

            Text("Everything else you selected is combined into the requirement you keep. Its scenes, dependencies, basis rows, and media move with it; the sources are kept as rejected so a later run cannot bring the duplicate back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Keep").font(.subheadline)
            List(candidates, selection: targetBinding) { candidate in
                Text("\(candidate.entityName) — \(candidate.name)").tag(candidate.id)
            }
            .frame(minHeight: 140)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("combineTargetList")
            .accessibilityLabel("Requirement to keep")

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { model.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelCombineButton")
                    .accessibilityLabel("Cancel combine")
                Button("Combine") { combine() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(targetID == nil || isCombining)
                    .accessibilityIdentifier("confirmCombineButton")
                    .accessibilityLabel("Combine requirements")
            }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("combineRequirementsSheet")
        .accessibilityLabel("Combine requirements")
        // The first row is preselected so the common case is one click; §7.2 gives the
        // survivor no default of its own.
        .onAppear { targetID = targetID ?? candidates.first?.id }
    }

    private var candidates: [RequirementSummary] { model.selectedRequirementSummaries }

    private var targetBinding: Binding<UUID?> {
        Binding(get: { targetID }, set: { targetID = $0 ?? targetID })
    }

    private func combine() {
        guard let targetID else { return }
        let sources = candidates.map(\.id).filter { $0 != targetID }
        guard !sources.isEmpty else { return }
        isCombining = true
        Task {
            await model.combineRequirements(sourceIDs: sources, into: targetID)
            isCombining = false
            model.presentedSheet = nil
        }
    }
}
