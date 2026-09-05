import FilmCore
import SwiftUI

/// §3.11's Continuity section, editable in place: continuity events in chronological
/// order — scene · entity · description · resulting state — and the states they resolve
/// to, in the same `(scene ordinal, entity name)` order.
///
/// States are listed here as well as on their entity because they are continuity data:
/// this is where a wardrobe change reads next to the event that caused it, and it is the
/// section the state editor belongs to. A state cannot exist without an entity (§4.3), so
/// it is **added** from that entity's inspector and edited from either place.
struct ContinuityListView: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.continuityEvents.isEmpty, model.continuityStates.isEmpty {
                ContentUnavailableView(
                    ProjectSection.continuity.emptyStateText,
                    systemImage: ProjectSection.continuity.systemImage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        // There is no project-wide states read; they hang off `EntityDetail`, so the
        // section loads them once per refresh instead of on every row.
        .task(id: model.refreshToken) { await model.loadContinuityStates() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button("Add Continuity Event") { model.presentedSheet = .addEvent }
                .disabled(model.scenes.isEmpty)
                .accessibilityIdentifier("addEventButton")
                .accessibilityLabel("Add continuity event")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var list: some View {
        List(selection: selectionBinding) {
            if !model.continuityEvents.isEmpty {
                Section("Events") {
                    ForEach(model.continuityEvents) { event in
                        eventRow(event).tag(event.id)
                    }
                }
            }
            if !model.continuityStates.isEmpty {
                Section("States") {
                    ForEach(model.continuityStates) { state in
                        stateRow(state).tag(state.id)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("continuityList")
        .accessibilityLabel("Continuity events")
    }

    @ViewBuilder
    private func eventRow(_ event: ContinuityEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sceneTitle(event.sceneID))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(event.entityID.flatMap { model.entityNames[$0] } ?? "—")
                    .foregroundStyle(.secondary)
                Text(event.description)
                Spacer(minLength: 8)
                Button("Edit") { model.presentedSheet = .editEvent(event) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("editEventButton")
                    .accessibilityLabel("Edit event: \(event.description)")
                Button {
                    Task { await model.removeEvent(id: event.id) }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("removeEventButton")
                .accessibilityLabel("Remove event: \(event.description)")
            }
            if let stateID = event.resultingStateID {
                Text("Resulting state: \(stateDescription(stateID))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stateRow(_ state: EntityState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stateSpan(state))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(model.entityNames[state.entityID] ?? "—")
                    .foregroundStyle(.secondary)
                Text("\(state.category.displayName): \(state.description)")
                    .accessibilityIdentifier("continuityStateText")
                    .accessibilityLabel("State: \(state.category.displayName): \(state.description)")
                Spacer(minLength: 8)
                Button("Edit") { model.presentedSheet = .editState(state) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("editStateButton")
                    .accessibilityLabel("Edit state: \(state.description)")
                Button {
                    Task { await model.removeState(id: state.id) }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("removeStateButton")
                .accessibilityLabel("Remove state: \(state.description)")
            }
        }
    }

    private func sceneTitle(_ id: UUID) -> String {
        guard let scene = model.scenes.first(where: { $0.id == id }) else { return "Scene" }
        return "\(scene.ordinal). \(scene.heading)"
    }

    private func stateSpan(_ state: EntityState) -> String {
        let start = sceneTitle(state.startSceneID)
        guard let endID = state.endSceneID else { return "From \(start)" }
        return "\(start) → \(sceneTitle(endID))"
    }

    /// Every state in the project is loaded for this section, so a resulting state reads
    /// as its own text rather than as an id.
    private func stateDescription(_ id: UUID) -> String {
        model.continuityStates.first { $0.id == id }?.description
            ?? model.entityDetail?.states.first { $0.id == id }?.description
            ?? "—"
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { model.selection(in: .continuity) },
            set: { model.setSelection($0, in: .continuity) }
        )
    }
}
