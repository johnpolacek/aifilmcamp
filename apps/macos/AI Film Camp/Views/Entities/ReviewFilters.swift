import FilmCore
import SwiftUI

/// The useful exception filters over the entity list. Validated AI output is active by
/// default, so Proposed / Accepted no longer ask the user to perform routine triage.
///
/// It is a store query, not a view predicate — the model re-reads
/// `entitySummaries(reviewState:includeRejected:)` — because a **rejected** row is
/// excluded by every default read (§3.6) and can be seen no other way. Plan 007 extends
/// this same control with the Unanchored filter and the review banner; it does not add a
/// second one.
struct ReviewFilters: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach([EntityReviewFilter.all, .rejected, .unanchored]) { filter in
                button(filter)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entityReviewFilters")
        .accessibilityLabel("Review filter")
    }

    private func button(_ filter: EntityReviewFilter) -> some View {
        let isActive = model.entityReviewFilter == filter
        return Button {
            Task { await model.setEntityReviewFilter(filter) }
        } label: {
            Text(filter.title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    isActive ? Color.accentColor.opacity(0.25) : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("entityFilter_\(filter.rawValue)")
        .accessibilityLabel("Show \(filter.title.lowercased()) entities")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
