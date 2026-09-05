import FilmCore
import SwiftUI

/// The **one** shared entity inspector of §3.11 over `ProjectReading.entity(id:)`, now
/// editable: rename, description, relevance, kind, aliases, per-field locks, accept and
/// reject, and the states, events, and relationships that hang off the entity.
///
/// All six kinds are served here; there is no per-kind copy. A **locked** field renders
/// read-only with an Unlock control beside it (§3.7) rather than a disabled editor, so
/// the way out of a lock is always visible.
struct EntityInspectorView: View {
    @Bindable var model: ProjectWindowModel
    let section: ProjectSection
    var entityID: UUID? = nil

    @State private var nameDraft = ""
    @State private var descriptionDraft = ""
    @State private var loadedEntityID: UUID?

    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        Group {
            if entityID == nil, model.selection(in: section).count > 1 {
                ScrollView { multipleSelection }
            } else if let detail = model.entityDetail {
                ScrollView { content(detail) }
            } else {
                ContentUnavailableView("No Selection", systemImage: section.systemImage)
            }
        }
        .accessibilityIdentifier("entityInspector")
        .accessibilityLabel("Entity inspector")
        .task(id: inspectedEntityID) {
            await model.loadEntityDetail(id: inspectedEntityID)
        }
        .task(id: model.refreshToken) {
            guard entityID != nil else { return }
            await model.loadEntityDetail(id: inspectedEntityID)
        }
    }

    // MARK: - Multi-selection (§3.11: a count, and only the valid actions)

    private var multipleSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(model.selection(in: section).count) selected")
                .font(.headline)
                .accessibilityIdentifier("entitySelectionCount")
                .accessibilityLabel("\(model.selection(in: section).count) entities selected")

            if model.canMergeSelection {
                Button("Merge…") { model.presentedSheet = .merge }
                    .accessibilityIdentifier("mergeSelectionButton")
                    .accessibilityLabel("Merge selected entities")
            }
            if model.canMoveSelectionIntoLocation {
                Button("Move into…") { model.presentedSheet = .moveInto }
                    .accessibilityIdentifier("moveIntoSelectionButton")
                    .accessibilityLabel("Move selected locations into another location")
            }
            if model.canAcceptSelection {
                Button("Accept") { Task { await model.acceptSelection() } }
                    .accessibilityIdentifier("acceptSelectionButton")
                    .accessibilityLabel("Accept selected entities")
            }
            if model.canMarkSelectionIrrelevant {
                Button("Mark Irrelevant") {
                    Task { await model.setRelevance(ids: model.selectedEntityIDs, isRelevant: false) }
                }
                .accessibilityIdentifier("markIrrelevantSelectionButton")
                .accessibilityLabel("Mark selected entities irrelevant")
            }
            Button("Delete") { model.confirmDeletion(of: model.selectedEntityIDs) }
                .accessibilityIdentifier("deleteSelectionButton")
                .accessibilityLabel("Delete selected entities")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - One entity

    @ViewBuilder
    private func content(_ detail: EntityDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            identity(detail)
            reviewActions(detail)
            description(detail)
            aliases(detail)
            appearances(detail)
            states(detail)
            events(detail)
            relationships(detail)
            evidence(detail)
            lockSummary(detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .task(id: detail.entity.id) {
            guard loadedEntityID != detail.entity.id else { return }
            loadedEntityID = detail.entity.id
            nameDraft = detail.entity.name
            descriptionDraft = detail.entity.description
        }
        .onChange(of: detail.entity.description) { _, stored in descriptionDraft = stored }
        .onChange(of: detail.entity.name) { _, stored in nameDraft = stored }
        .onChange(of: model.renamingEntityID) { _, renaming in
            guard renaming == detail.entity.id else { return }
            nameDraft = detail.entity.name
            isNameFieldFocused = true
        }
    }

    // MARK: Name, kind, relevance

    @ViewBuilder
    private func identity(_ detail: EntityDetail) -> some View {
        let subject = SubjectRef(kind: .entity, id: detail.entity.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if model.renamingEntityID == detail.entity.id {
                    TextField("Name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFieldFocused)
                        .onSubmit { commitRename(detail) }
                        .onExitCommand { model.cancelRename() }
                        .accessibilityIdentifier("entityNameField")
                        .accessibilityLabel("Name")
                    Button("Rename") { commitRename(detail) }
                        .accessibilityIdentifier("commitRenameButton")
                        .accessibilityLabel("Commit rename")
                } else {
                    Text(detail.entity.name)
                        .font(.title3)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("entityNameText")
                        .accessibilityLabel("Name: \(detail.entity.name)")
                    Spacer(minLength: 8)
                    if !model.isLocked(subject, field: .name) {
                        Button("Rename") { model.beginRename(entityID: detail.entity.id) }
                            .accessibilityIdentifier("renameEntityButton")
                            .accessibilityLabel("Rename \(detail.entity.name)")
                    }
                    LockButton(model: model, subject: subject, field: .name, name: "Name")
                }
            }

            HStack(spacing: 6) {
                if model.isLocked(subject, field: .kind) {
                    Text(detail.entity.kind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("entityKindText")
                        .accessibilityLabel("Kind, locked: \(detail.entity.kind.displayName)")
                } else {
                    Picker("Kind", selection: kindBinding(detail)) {
                        ForEach(EntityKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("entityKindPicker")
                    .accessibilityLabel("Kind")
                }
                Spacer(minLength: 8)
                LockButton(model: model, subject: subject, field: .kind, name: "Kind")
            }

            HStack(spacing: 6) {
                if model.isLocked(subject, field: .isRelevant) {
                    Text(detail.entity.isRelevant ? "Relevant" : "Irrelevant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("entityRelevanceText")
                        .accessibilityLabel(
                            "Relevance, locked: \(detail.entity.isRelevant ? "relevant" : "irrelevant")"
                        )
                } else {
                    Toggle("Relevant", isOn: relevanceBinding(detail))
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("entityRelevanceToggle")
                        .accessibilityLabel("Relevant")
                }
                Spacer(minLength: 8)
                LockButton(model: model, subject: subject, field: .isRelevant, name: "Relevance")
            }

            HStack(spacing: 6) {
                Spacer(minLength: 8)
                LockButton(model: model, subject: subject, field: .whole, name: "Record")
            }
        }
    }

    private var inspectedEntityID: UUID? {
        entityID ?? model.singleSelection(in: section)
    }

    // MARK: Accept / reject (§3.6)

    @ViewBuilder
    private func reviewActions(_ detail: EntityDetail) -> some View {
        HStack(spacing: 8) {
            if detail.entity.provenance.reviewState == .proposed {
                Button("Accept") {
                    Task {
                        await model.acceptFacts(refs: [SubjectRef(kind: .entity, id: detail.entity.id)])
                    }
                }
                .accessibilityIdentifier("acceptEntityButton")
                .accessibilityLabel("Accept \(detail.entity.name)")
            }
            if detail.entity.provenance.reviewState == .rejected {
                // §6's `unrejectEntity`: the tombstone comes back as whatever it was
                // before the rejection.
                Button("Restore") { Task { await model.unrejectEntity(id: detail.entity.id) } }
                    .accessibilityIdentifier("unrejectEntityButton")
                    .accessibilityLabel("Restore \(detail.entity.name)")
            } else {
                // §3.6: on a `parser` or `ai` row this tombstones rather than deletes,
                // which is what "Reject" names; FilmCore routes it.
                Button("Reject") { model.confirmDeletion(of: [detail.entity.id]) }
                    .accessibilityIdentifier("rejectEntityButton")
                    .accessibilityLabel("Reject \(detail.entity.name)")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Description

    @ViewBuilder
    private func description(_ detail: EntityDetail) -> some View {
        let subject = SubjectRef(kind: .entity, id: detail.entity.id)
        sectionBox("Description", lock: LockButton(model: model, subject: subject, field: .description, name: "Description")) {
            if model.isLocked(subject, field: .description) {
                Text(detail.entity.description.isEmpty ? "No description yet." : detail.entity.description)
                    .foregroundStyle(detail.entity.description.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("entityDescriptionText")
                    .accessibilityLabel("Description, locked")
                    .accessibilityValue(
                        detail.entity.description.isEmpty
                            ? "No description yet."
                            : detail.entity.description
                    )
            } else {
                TextField("No description yet.", text: $descriptionDraft, axis: .vertical)
                    .lineLimit(2 ... 8)
                    .textFieldStyle(.roundedBorder)
                    .tracksTextEditing(model)
                    .accessibilityIdentifier("entityDescriptionField")
                    .accessibilityLabel("Description")
                HStack {
                    Spacer()
                    Button("Save Description") {
                        let text = descriptionDraft
                        Task { await model.setDescription(id: detail.entity.id, text: text) }
                    }
                    .disabled(descriptionDraft == detail.entity.description)
                    .accessibilityIdentifier("saveDescriptionButton")
                    .accessibilityLabel("Save description")
                }
            }
        }
    }

    // MARK: Aliases, appearances, evidence

    @ViewBuilder
    private func aliases(_ detail: EntityDetail) -> some View {
        sectionBox("Aliases") {
            AliasEditor(model: model, detail: detail)
        }
    }

    @ViewBuilder
    private func appearances(_ detail: EntityDetail) -> some View {
        if !detail.appearances.isEmpty {
            sectionBox("Appearances") {
                ForEach(SceneEntityRole.allCases, id: \.self) { role in
                    let rows = detail.appearances.filter { $0.role == role }
                    if !rows.isEmpty {
                        Text(role.displayName).font(.caption).foregroundStyle(.secondary)
                        ForEach(rows) { appearance in
                            sceneJumpButton(
                                sceneID: appearance.sceneID,
                                title: sceneTitle(appearance.sceneID),
                                highlight: nil
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func evidence(_ detail: EntityDetail) -> some View {
        if !detail.evidence.isEmpty {
            sectionBox("Evidence") {
                ForEach(detail.evidence) { evidence in
                    sceneJumpButton(
                        sceneID: evidence.sceneID,
                        title: "“\(evidence.quote)” — \(sceneTitle(evidence.sceneID))",
                        highlight: evidence.range
                    )
                }
            }
        }
    }

    // MARK: States, events, relationships

    @ViewBuilder
    private func states(_ detail: EntityDetail) -> some View {
        sectionBox("States") {
            ForEach(detail.states) { state in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(state.category.displayName): \(state.description)")
                            .textSelection(.enabled)
                            .accessibilityIdentifier("entityStateText")
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
                    Text(stateSpan(state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Add State") { model.presentedSheet = .addState(entityID: detail.entity.id) }
                .accessibilityIdentifier("addStateButton")
                .accessibilityLabel("Add state to \(detail.entity.name)")
        }
    }

    @ViewBuilder
    private func events(_ detail: EntityDetail) -> some View {
        if !detail.events.isEmpty {
            sectionBox("Events") {
                ForEach(detail.events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(event.description).textSelection(.enabled)
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
                        Text(sceneTitle(event.sceneID))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func relationships(_ detail: EntityDetail) -> some View {
        sectionBox("Relationships") {
            ForEach(detail.relationships) { relationship in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(relationshipLine(relationship, entityID: detail.entity.id))
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button {
                            Task { await model.removeRelationship(id: relationship.id) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("removeRelationshipButton")
                        .accessibilityLabel("Remove relationship")
                    }
                }
            }
            Button("Add Relationship") {
                model.presentedSheet = .addRelationship(entityID: detail.entity.id)
            }
            .accessibilityIdentifier("addRelationshipButton")
            .accessibilityLabel("Add relationship to \(detail.entity.name)")
        }
    }

    @ViewBuilder
    private func lockSummary(_ detail: EntityDetail) -> some View {
        if !detail.locks.isEmpty {
            sectionBox("Locks") {
                ForEach(detail.locks, id: \.self) { lock in
                    Label(
                        lock.isWholeRecord ? "Whole record" : lock.field,
                        systemImage: "lock.fill"
                    )
                    .accessibilityLabel(
                        "Locked: \(lock.isWholeRecord ? "whole record" : lock.field)"
                    )
                }
            }
        }
    }

    // MARK: - Bindings and helpers

    private func kindBinding(_ detail: EntityDetail) -> Binding<EntityKind> {
        Binding(
            get: { detail.entity.kind },
            set: { kind in
                guard kind != detail.entity.kind else { return }
                Task { await model.reclassify(id: detail.entity.id, kind: kind) }
            }
        )
    }

    private func relevanceBinding(_ detail: EntityDetail) -> Binding<Bool> {
        Binding(
            get: { detail.entity.isRelevant },
            set: { isRelevant in
                Task { await model.setRelevance(id: detail.entity.id, isRelevant: isRelevant) }
            }
        )
    }

    private func commitRename(_ detail: EntityDetail) {
        let name = nameDraft
        Task { await model.commitRename(id: detail.entity.id, name: name) }
    }

    @ViewBuilder
    private func sectionBox(
        _ title: String,
        lock: LockButton? = nil,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.headline)
                Spacer(minLength: 8)
                if let lock { lock }
            }
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Evidence and appearances jump to the scene, flashing the span (§3.11).
    private func sceneJumpButton(sceneID: UUID, title: String, highlight: UTF16Range?) -> some View {
        Button {
            Task { await model.reveal(.scene(id: sceneID, highlight: highlight)) }
        } label: {
            Text(title)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.link)
        .accessibilityIdentifier("revealSceneButton")
        .accessibilityLabel("Reveal scene: \(sceneTitle(sceneID))")
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

    private func relationshipLine(_ relationship: EntityRelationship, entityID: UUID) -> String {
        let otherID = relationship.fromEntityID == entityID
            ? relationship.toEntityID
            : relationship.fromEntityID
        let other = model.entityNames[otherID] ?? "Unknown"
        let arrow = relationship.fromEntityID == entityID ? "→" : "←"
        let description = relationship.description.isEmpty ? "" : " · \(relationship.description)"
        return "\(arrow) \(other) · \(relationship.kind.displayName)\(description)"
    }
}
