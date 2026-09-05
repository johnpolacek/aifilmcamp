import FilmCore
import SwiftUI

/// §6's "Move into…": re-parents the selected locations, or clears their parent.
///
/// Cycles are FilmCore's to refuse (`.invalidParent(reason:)` by an ancestor walk), and
/// this sheet surfaces that refusal verbatim rather than reimplementing the walk over
/// rows the list does not carry. It only removes the obvious impossibility — a location
/// cannot be moved into itself.
///
/// `setLocationParent` is a scalar operation (§6 lists no batch form), so a multiple
/// selection is one move per location and therefore one undo step each; the move stops at
/// the first refusal so the operator sees which one failed.
struct MoveIntoSheet: View {
    @Bindable var model: ProjectWindowModel

    @State private var parentID: UUID?
    @State private var isMoving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityIdentifier("moveIntoSheetTitle")

            Text("Move into").font(.subheadline)
            List(selection: $parentID) {
                Text("No parent location")
                    .tag(UUID?.none)
                ForEach(candidates) { candidate in
                    Text(candidate.name).tag(UUID?.some(candidate.id))
                }
            }
            .frame(minHeight: 180)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("moveIntoParentList")
            .accessibilityLabel("Parent location")

            HStack {
                Spacer()
                Button("Cancel") { model.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelMoveIntoButton")
                    .accessibilityLabel("Cancel move")
                Button("Move") { move() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isMoving)
                    .accessibilityIdentifier("confirmMoveIntoButton")
                    .accessibilityLabel("Move location")
            }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moveIntoSheet")
        .accessibilityLabel("Move into location")
    }

    private var moved: [EntitySummary] { model.selectedEntitySummaries }

    private var title: String {
        moved.count == 1 ? "Move \(moved[0].name)" : "Move \(moved.count) Locations"
    }

    /// Every other location. The ancestor walk that rules out a descendant is FilmCore's.
    private var candidates: [EntitySummary] {
        let movedIDs = Set(moved.map(\.id))
        return (model.entitySummaries[.location] ?? []).filter { !movedIDs.contains($0.id) }
    }

    private func move() {
        let ids = moved.map(\.id)
        guard !ids.isEmpty else { return }
        isMoving = true
        Task {
            for id in ids {
                await model.setLocationParent(id: id, parentID: parentID)
                // FilmCore refused this one — the alert already says why, and continuing
                // would bury it under the next refusal.
                if model.error != nil { break }
            }
            isMoving = false
            model.presentedSheet = nil
        }
    }
}
