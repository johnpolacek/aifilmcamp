import FilmCore
import SwiftUI

/// The requirement inspector (PHASE2_DESIGN §5.3, §6.1, §7.6, §8.6) over
/// `ProjectReading.requirement(id:)`: name, reason, necessity, the scenes it is required
/// by, dependencies in both directions, basis citations with their evidence, the
/// provenance line, locks, the review actions, and the badges.
///
/// A **locked** field renders read-only with an Unlock control beside it (§3.7), exactly
/// as the entity inspector does, so the way out of a lock is always visible.
struct RequirementInspectorView: View {
    @Bindable var model: ProjectWindowModel

    @State private var nameDraft = ""
    @State private var reasonDraft = ""
    @State private var loadedRequirementID: UUID?

    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        Group {
            if model.selection(in: .manifest).count > 1 {
                ScrollView { multipleSelection }
            } else if let detail = model.requirementDetail {
                ScrollView { content(detail) }
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: ProjectSection.manifest.systemImage
                )
            }
        }
        .accessibilityIdentifier("requirementInspector")
        .accessibilityLabel("Requirement inspector")
        .task(id: model.selectedRequirementID) {
            await model.loadRequirementDetail()
        }
    }

    // MARK: - Multi-selection: only the actions valid for the whole selection

    private var multipleSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(model.selection(in: .manifest).count) selected")
                .font(.headline)
                .accessibilityIdentifier("requirementSelectionCount")
                .accessibilityLabel("\(model.selection(in: .manifest).count) requirements selected")

            if model.canCombineRequirementSelection {
                Button("Combine…") { model.presentedSheet = .combineRequirements }
                    .accessibilityIdentifier("combineRequirementsButton")
                    .accessibilityLabel("Combine selected requirements")
            }
            if model.canAcceptRequirementSelection {
                Button("Accept") { Task { await model.acceptRequirementSelection() } }
                    .accessibilityIdentifier("acceptRequirementSelectionButton")
                    .accessibilityLabel("Accept selected requirements")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - One requirement

    @ViewBuilder
    private func content(_ detail: RequirementDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            identity(detail)
            badges(detail)
            reviewActions(detail)
            reason(detail)
            necessity(detail)
            requiredBy(detail)
            dependencies(detail)
            basis(detail)
            lockSummary(detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .task(id: detail.requirement.id) {
            guard loadedRequirementID != detail.requirement.id else { return }
            loadedRequirementID = detail.requirement.id
            nameDraft = detail.requirement.name
            reasonDraft = detail.requirement.reason
        }
        .onChange(of: detail.requirement.name) { _, stored in nameDraft = stored }
        .onChange(of: detail.requirement.reason) { _, stored in reasonDraft = stored }
        .onChange(of: model.renamingRequirementID) { _, renaming in
            guard renaming == detail.requirement.id else { return }
            nameDraft = detail.requirement.name
            isNameFieldFocused = true
        }
    }

    // MARK: Name and provenance

    @ViewBuilder
    private func identity(_ detail: RequirementDetail) -> some View {
        let subject = SubjectRef(kind: .requirement, id: detail.requirement.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if model.renamingRequirementID == detail.requirement.id {
                    TextField("Name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFieldFocused)
                        .onSubmit { commitRename(detail) }
                        .onExitCommand { model.cancelRequirementRename() }
                        .accessibilityIdentifier("requirementNameField")
                        .accessibilityLabel("Requirement name")
                    Button("Rename") { commitRename(detail) }
                        .accessibilityIdentifier("commitRequirementRenameButton")
                        .accessibilityLabel("Commit rename")
                } else {
                    Text(detail.requirement.name)
                        .font(.title3)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("requirementNameText")
                        .accessibilityLabel("Requirement name: \(detail.requirement.name)")
                    Spacer(minLength: 8)
                    if !model.isRequirementLocked(detail.requirement.id, field: .name) {
                        Button("Rename") { model.beginRequirementRename() }
                            .accessibilityIdentifier("renameRequirementButton")
                            .accessibilityLabel("Rename \(detail.requirement.name)")
                    }
                    LockButton(model: model, subject: subject, field: .name, name: "Name")
                }
            }

            Text("\(detail.entity.name) · \(detail.requirement.tier.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("requirementEntityText")
                .accessibilityLabel(
                    "Item: \(detail.entity.name), tier: \(detail.requirement.tier.displayName)"
                )

            HStack(spacing: 6) {
                Spacer(minLength: 8)
                LockButton(model: model, subject: subject, field: .whole, name: "Record")
            }
        }
    }

    // MARK: §5.3's drift and §6.1's display state

    @ViewBuilder
    private func badges(_ detail: RequirementDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // §6.1: the media axis, kept visually apart from the review state above.
            Text("Asset: \(detail.displayStatus.displayName)")
                .font(.caption)
                .accessibilityIdentifier("requirementStatusText")
                .accessibilityLabel("Asset state: \(detail.displayStatus.displayName)")
            ForEach(detail.drift.badges(sceneCount: detail.requiredBy.count), id: \.self) { badge in
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("requirementDriftBadge")
                    .accessibilityLabel(badge)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Accept / Reject (§8.6's grammar, without inference)

    @ViewBuilder
    private func reviewActions(_ detail: RequirementDetail) -> some View {
        HStack(spacing: 8) {
            if detail.requirement.provenance.reviewState == .proposed {
                Button("Accept") { Task { await model.acceptRequirement(id: detail.requirement.id) } }
                    .accessibilityIdentifier("acceptRequirementButton")
                    .accessibilityLabel("Accept \(detail.requirement.name)")
            }
            if detail.requirement.provenance.reviewState == .rejected {
                Button("Restore") {
                    Task { await model.unrejectRequirement(id: detail.requirement.id) }
                }
                .accessibilityIdentifier("unrejectRequirementButton")
                .accessibilityLabel("Restore \(detail.requirement.name)")
            } else {
                Button("Reject") { Task { await model.rejectRequirement(id: detail.requirement.id) } }
                    .accessibilityIdentifier("rejectRequirementButton")
                    .accessibilityLabel("Reject \(detail.requirement.name)")
            }
            // §7.2 routes this: a `human` row is removed outright, a `parser` or `ai` row
            // is tombstoned instead, and a row with media is refused.
            Button("Delete") { Task { await model.deleteRequirement(id: detail.requirement.id) } }
                .accessibilityIdentifier("deleteRequirementButton")
                .accessibilityLabel("Delete \(detail.requirement.name)")
            Spacer(minLength: 0)
        }
    }

    // MARK: Reason and necessity

    @ViewBuilder
    private func reason(_ detail: RequirementDetail) -> some View {
        let subject = SubjectRef(kind: .requirement, id: detail.requirement.id)
        sectionBox(
            "Reason",
            lock: LockButton(model: model, subject: subject, field: .reason, name: "Reason")
        ) {
            if model.isRequirementLocked(detail.requirement.id, field: .reason) {
                Text(detail.requirement.reason.isEmpty ? "No reason yet." : detail.requirement.reason)
                    .foregroundStyle(detail.requirement.reason.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("requirementReasonText")
                    .accessibilityLabel("Reason, locked")
                    .accessibilityValue(
                        detail.requirement.reason.isEmpty ? "No reason yet." : detail.requirement.reason
                    )
            } else {
                TextField("No reason yet.", text: $reasonDraft, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .textFieldStyle(.roundedBorder)
                    .tracksTextEditing(model)
                    .accessibilityIdentifier("requirementReasonField")
                    .accessibilityLabel("Reason")
                HStack {
                    Spacer()
                    Button("Save Reason") {
                        let text = reasonDraft
                        Task { await model.setRequirementReason(id: detail.requirement.id, text: text) }
                    }
                    .disabled(reasonDraft == detail.requirement.reason)
                    .accessibilityIdentifier("saveRequirementReasonButton")
                    .accessibilityLabel("Save reason")
                }
            }
        }
    }

    @ViewBuilder
    private func necessity(_ detail: RequirementDetail) -> some View {
        let subject = SubjectRef(kind: .requirement, id: detail.requirement.id)
        sectionBox(
            "Necessity",
            lock: LockButton(model: model, subject: subject, field: .necessity, name: "Necessity")
        ) {
            if model.isRequirementLocked(detail.requirement.id, field: .necessity) {
                Text(detail.requirement.necessity.displayName)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("requirementNecessityText")
                    .accessibilityLabel("Necessity, locked: \(detail.requirement.necessity.displayName)")
            } else {
                Picker("Necessity", selection: necessityBinding(detail)) {
                    ForEach(RequirementNecessity.allCases, id: \.self) { necessity in
                        Text(necessity.displayName).tag(necessity)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("requirementNecessityPicker")
                .accessibilityLabel("Necessity")
            }
        }
    }

    // MARK: Required by, dependencies, basis

    /// §5.2: derived from `scene_entities` for a canonical row, the stored links for a
    /// variant — the read layer decides which, and the inspector just lists what it got.
    @ViewBuilder
    private func requiredBy(_ detail: RequirementDetail) -> some View {
        sectionBox("Required By") {
            if detail.requiredBy.isEmpty {
                Text("No scenes yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("requirementScenesEmptyText")
                    .accessibilityLabel("No scenes yet")
            } else {
                ForEach(detail.requiredBy) { scene in
                    sceneJumpButton(sceneID: scene.id, title: sceneTitle(scene.id), highlight: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func dependencies(_ detail: RequirementDetail) -> some View {
        if !detail.dependsOn.isEmpty || !detail.dependents.isEmpty {
            sectionBox("Dependencies") {
                if !detail.dependsOn.isEmpty {
                    Text("Depends on").font(.caption).foregroundStyle(.secondary)
                    ForEach(detail.dependsOn) { edge in
                        dependencyRow(edge, identifier: "requirementDependsOnRow")
                    }
                }
                if !detail.dependents.isEmpty {
                    Text("Depended on by").font(.caption).foregroundStyle(.secondary)
                    ForEach(detail.dependents) { edge in
                        dependencyRow(edge, identifier: "requirementDependentRow")
                    }
                }
            }
        }
    }

    private func dependencyRow(_ edge: RequirementDependencyEdge, identifier: String) -> some View {
        HStack(spacing: 6) {
            Button {
                Task { await model.revealRequirement(id: edge.otherRequirementID) }
            } label: {
                Text("\(edge.otherEntityName) — \(edge.otherRequirementName)")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.link)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(
                "\(edge.otherEntityName) — \(edge.otherRequirementName), "
                    + (edge.isSatisfied ? "satisfied" : "unsatisfied")
            )
            Text(edge.isSatisfied ? "satisfied" : "unsatisfied")
                .font(.caption2)
                .foregroundStyle(edge.isSatisfied ? Color.secondary : Color.orange)
        }
    }

    /// Basis rows are immutable citations (§3.7); their **underlying facts'** evidence is
    /// what jumps to a scene.
    @ViewBuilder
    private func basis(_ detail: RequirementDetail) -> some View {
        if !detail.basis.isEmpty {
            sectionBox("Basis") {
                ForEach(detail.basis) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(basisLine(row))
                            .font(.caption)
                            .accessibilityIdentifier("requirementBasisText")
                            .accessibilityLabel("Basis: \(basisLine(row))")
                        ForEach(row.evidence) { evidence in
                            sceneJumpButton(
                                sceneID: evidence.sceneID,
                                title: "“\(evidence.quote)” — \(sceneTitle(evidence.sceneID))",
                                highlight: evidence.range
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lockSummary(_ detail: RequirementDetail) -> some View {
        if !detail.locks.isEmpty {
            sectionBox("Locks") {
                ForEach(detail.locks, id: \.self) { lock in
                    Label(lock.isWholeRecord ? "Whole record" : lock.field, systemImage: "lock.fill")
                        .accessibilityLabel(
                            "Locked: \(lock.isWholeRecord ? "whole record" : lock.field)"
                        )
                }
            }
        }
    }

    // MARK: - Bindings and helpers

    private func necessityBinding(_ detail: RequirementDetail) -> Binding<RequirementNecessity> {
        Binding(
            get: { detail.requirement.necessity },
            set: { necessity in
                guard necessity != detail.requirement.necessity else { return }
                Task {
                    await model.setRequirementNecessity(
                        id: detail.requirement.id, necessity: necessity
                    )
                }
            }
        )
    }

    private func commitRename(_ detail: RequirementDetail) {
        let name = nameDraft
        Task { await model.commitRequirementRename(id: detail.requirement.id, name: name) }
    }

    private func basisLine(_ row: RequirementBasisDetail) -> String {
        let state = row.factReviewState?.displayName ?? "Missing"
        return "\(row.basis.subjectKind.rawValue.capitalized) · \(state)"
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
}
