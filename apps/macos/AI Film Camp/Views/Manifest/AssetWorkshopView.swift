import FilmCore
import SwiftUI

/// PHASE3_DESIGN §5.1's in-content master–detail: the workshop beside the narrowed
/// requirement list, hosting the shipped `AssetSlotView` wholesale (§5.9's re-host —
/// every identifier rides verbatim) and adding §5.2–§5.5's header, Used In, references,
/// and prompt panels.
///
/// Presentation only: every action routes through `ProjectWindowModel+Workshop` and
/// `+Assets`; enablement is read-driven (§5.8); refusals surface FilmCore's copy verbatim
/// through `runEdit`.
struct AssetWorkshopView: View {
    @Bindable var model: ProjectWindowModel

    @State private var confirmEmptySlot = false
    @State private var writePromptSheet = false
    @State private var editingBody = false
    @State private var bodyDraft = ""
    @State private var deletePromptTarget: (id: UUID, number: Int, isCurrent: Bool)?

    var body: some View {
        Group {
            if let detail = model.requirementDetail, model.workshopRequirementID != nil {
                ScrollView { content(detail) }
            } else {
                ContentUnavailableView(
                    "Select a requirement",
                    systemImage: ProjectSection.manifest.systemImage
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assetWorkshop")
        .accessibilityLabel("Asset Workshop")
        .task(id: model.selectedRequirementID) {
            await model.loadRequirementDetail()
            await model.loadWorkshopPromptHistory()
        }
        .task(id: model.refreshToken) {
            await model.loadWorkshopPromptHistory()
        }
    }

    private func content(_ detail: RequirementDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(detail)
            usedIn(detail)
            references(detail)
            promptPanel(detail)
            // The shipped slot surface, re-hosted verbatim (§5.9): import, versions,
            // approval, staleness, notes. Its identifiers ride with it.
            AssetSlotView(model: model, detail: detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .confirmationDialog(
            model.workshopEmptySlotConfirm(),
            isPresented: $confirmEmptySlot,
            titleVisibility: .visible,
            presenting: detail.asset?.id
        ) { assetID in
            Button("Empty Slot", role: .destructive) {
                Task { await model.deleteAssetAndClose(assetID: assetID) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            deletePromptConfirmText,
            isPresented: Binding(
                get: { deletePromptTarget != nil },
                set: { if !$0 { deletePromptTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletePromptTarget
        ) { target in
            Button("Delete Prompt", role: .destructive) {
                Task { await model.deleteWorkshopPrompt(promptID: target.id) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $writePromptSheet) {
            WritePromptSheet(model: model)
        }
    }

    private var deletePromptConfirmText: String {
        guard let target = deletePromptTarget else { return "" }
        return model.workshopDeletePromptConfirm(
            number: target.number, isCurrent: target.isCurrent
        )
    }

    // MARK: - §5.2 Header: identity chips, state badge, drift badges, menu

    @ViewBuilder
    private func header(_ detail: RequirementDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(detail.entity.name) — \(detail.requirement.name)")
                    .font(.title3.weight(.medium))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("workshopTitle")
                    .accessibilityLabel("Workshop: \(detail.entity.name) — \(detail.requirement.name)")
                Spacer(minLength: 8)
                Menu("New Variant Requirement…") {
                    Button("New Variant Requirement…") {
                        Task { await model.addVariantRequirement(entityID: detail.entity.id) }
                    }
                    .accessibilityIdentifier("addVariantRequirementButton")
                    .accessibilityLabel("Add a variant requirement to \(detail.entity.name)")
                    if detail.asset != nil {
                        Button("Empty Slot…") { confirmEmptySlot = true }
                            .accessibilityIdentifier("emptySlotButton")
                            .accessibilityLabel("Delete this slot's media; prompts are kept")
                    }
                }
                .accessibilityIdentifier("workshopHeaderMenu")
            }

            HStack(spacing: 6) {
                tierBadge(detail)
                Text(detail.requirement.necessity.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // §5.2: the OVERVIEW state — Needed with no asset row (§6.1).
                Text(noAssetNeeded(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("workshopStatusBadge")
                    .accessibilityLabel("Workshop status: \(statusName(detail))")
                Spacer(minLength: 0)
            }

            // §5.2's badge row: the drift badges of Phase 2 §5.3 and the two requirement
            // badges moved here from the inspector (Plan 015 contract A).
            HStack(spacing: 6) {
                if detail.isBlocked {
                    Text("Blocked by an unsatisfied dependency")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("requirementBlockedBadge")
                        .accessibilityLabel("Blocked by an unsatisfied dependency")
                }
                if detail.isStale {
                    Text("Stale")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("requirementStaleBadge")
                        .accessibilityLabel("Stale")
                }
                ForEach(detail.drift.badges(sceneCount: detail.requiredBy.count), id: \.self) { badge in
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("requirementDriftBadge")
                        .accessibilityLabel(badge)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tierBadge(_ detail: RequirementDetail) -> some View {
        Text(detail.requirement.tier.displayName)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .accessibilityLabel("Tier: \(detail.requirement.tier.displayName)")
    }

    /// §6.1: a requirement with no asset row displays Needed.
    private func noAssetNeeded(_ detail: RequirementDetail) -> String {
        "State: \(statusName(detail))"
    }

    private func statusName(_ detail: RequirementDetail) -> String {
        detail.displayStatus.displayName
    }

    // MARK: - §5.2 Used In

    @ViewBuilder
    private func usedIn(_ detail: RequirementDetail) -> some View {
        if !detail.requiredBy.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Used In").font(.headline)
                ForEach(detail.requiredBy) { scene in
                    Button {
                        Task { await model.reveal(.scene(id: scene.id, highlight: nil)) }
                    } label: {
                        Text(sceneTitle(scene.id)).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("usedInSceneButton")
                    .accessibilityLabel("Used in \(sceneTitle(scene.id))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sceneTitle(_ id: UUID) -> String {
        guard let scene = model.scenes.first(where: { $0.id == id }) else { return "Scene" }
        return "\(scene.ordinal). \(scene.heading)"
    }

    // MARK: - §5.3 References: planned dependencies whole

    @ViewBuilder
    private func references(_ detail: RequirementDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("References").font(.headline)
                Spacer(minLength: 8)
                Button("Add Reference…") { showAddReference = true }
                    .disabled(model.isWorkshopRequirementWholeLocked)
                .accessibilityIdentifier("addReferenceButton")
                .accessibilityLabel("Add a reference dependency")
                .disabled(model.isWorkshopRequirementWholeLocked)
                Button("Reveal All") {
                    Task { await model.revealAllReferences(detail: detail) }
                }
                .accessibilityIdentifier("revealAllReferencesButton")
                .disabled(satisfiedCount(detail) == 0)
            }
            if detail.plannedDependencies.isEmpty {
                Text("No references yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("referencesEmptyText")
            }
            ForEach(Array(detail.plannedDependencies.enumerated()), id: \.element.id) {
                index, dependency in
                ReferenceRow(model: model, position: index, dependency: dependency)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showAddReference) {
            AddReferenceSheet(model: model, requirementID: detail.requirement.id)
        }
    }

    @State private var showAddReference = false

    private func satisfiedCount(_ detail: RequirementDetail) -> Int {
        detail.plannedDependencies.filter { $0.isSatisfied }.count
    }

    // MARK: - §5.4–§5.5 The prompt panel

    @ViewBuilder
    private func promptPanel(_ detail: RequirementDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Prompt").font(.headline)
                Spacer(minLength: 8)
                generateControls(detail)
            }

            if let current = detail.currentPrompt {
                promptStaleBadge(current)
                Text(current.body)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("workshopPromptBody")
                    .accessibilityLabel("Current prompt body")

                metadataLine(current)

                HStack(spacing: 8) {
                    Button("Copy Prompt") { model.copyWorkshopPrompt(includeGuidance: false) }
                        .accessibilityIdentifier("copyPromptButton")
                        .disabled(!model.canCopyPrompt)
                    Button("Copy with Guidance") {
                        model.copyWorkshopPrompt(includeGuidance: true)
                    }
                    .accessibilityIdentifier("copyPromptWithGuidanceButton")
                    .disabled(!model.canCopyPromptWithGuidance)
                    Button("Edit Body…") {
                        bodyDraft = current.body
                        editingBody = true
                    }
                    .accessibilityIdentifier("editPromptBodyButton")
                    .disabled(!model.canEditPromptBody)
                    Spacer()
                    Button("Mark In Progress") {
                        Task { await model.markWorkshopInProgress() }
                    }
                    .accessibilityIdentifier("markInProgressButton")
                    .disabled(!model.canMarkInProgress)
                    if detail.inProgressSince != nil {
                        Button("Clear In Progress") {
                            Task { await model.clearWorkshopInProgress() }
                        }
                        .accessibilityIdentifier("clearInProgressButton")
                        .disabled(!model.canClearInProgress)
                    }
                }

                historyDisclosure(detail)
            } else {
                Text("No prompt yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("promptEmptyText")
            }

            HStack(spacing: 8) {
                Button("Write Prompt…") { writePromptSheet = true }
                    .accessibilityIdentifier("writePromptButton")
                    .disabled(!model.canWritePrompt)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $editingBody) {
            EditPromptBodySheet(model: model, current: detail.currentPrompt) {
                editingBody = false
            }
        }
    }

    /// §5.4/§5.8: Generate / Regenerate render per shown-when but **disabled** — Plan 016
    /// wires them; the reason is the window model's, never guessed here.
    private func generateControls(_ detail: RequirementDetail) -> some View {
        let hasPrompt = detail.currentPrompt != nil
        return Button(hasPrompt ? "Regenerate…" : "Generate…") {
            Task { await model.preparePromptRun() }
        }
        .accessibilityIdentifier(hasPrompt ? "regeneratePromptButton" : "generatePromptButton")
        .disabled(model.generateDisabledReason != nil)
        .help(model.generateDisabledReason ?? "")
    }

    /// §3.4/§6.2: the **prompt**-stale badge, distinct from the asset stale badge.
    @ViewBuilder
    private func promptStaleBadge(_ current: AssetPromptDetail) -> some View {
        if current.isStale {
            Text("Prompt built from earlier inputs — Regenerate")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("workshopPromptStaleBadge")
                .accessibilityLabel("Prompt built from earlier inputs")
        }
    }

    private func metadataLine(_ current: AssetPromptDetail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !current.targetModel.isEmpty {
                Text("Target model: \(current.targetModel)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !current.guidance.isEmpty {
                Text("Guidance: \(current.guidance)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !current.skillID.isEmpty {
                Text("Skill: \(current.skillID)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// §3.2's history disclosure: superseded prompts, each deletable.
    @ViewBuilder
    private func historyDisclosure(_ detail: RequirementDetail) -> some View {
        let history = model.workshopPromptHistory.filter {
            $0.id != detail.currentPrompt?.id
        }
        if !history.isEmpty {
            DisclosureGroup("History (\(history.count))") {
                ForEach(history) { row in
                    HStack {
                        Text("Prompt \(row.promptNumber)").font(.caption)
                        Spacer()
                        Button("Delete…") {
                            deletePromptTarget = (row.id, row.promptNumber, false)
                        }
                        .accessibilityIdentifier("deletePromptButton_\(row.promptNumber)")
                    }
                }
            }
            .font(.caption)
            .accessibilityIdentifier("promptHistoryDisclosure")
        }
    }
}


// MARK: - Subviews (references panel, prompt sheets)

/// One planned dependency (§3.3): designator on satisfied rows only, the unsatisfied
/// marker in its place; class and the derived role/exclusion/fidelity read-only.
struct ReferenceRow: View {
    let model: ProjectWindowModel
    let position: Int
    let dependency: PlannedDependency

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if dependency.isSatisfied, let designator = dependency.designator {
                    Text("@Image \(designator)")
                        .font(.caption.weight(.medium))
                        .accessibilityIdentifier("referenceDesignator_\(position)")
                } else {
                    Text("no approved version yet")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("referenceUnsatisfiedMarker_\(position)")
                }
            }
            .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(dependency.entityName) — \(dependency.requirementName)")
                    .font(.caption)
                    .accessibilityIdentifier("referenceRow_\(position)")
                Text("\(dependency.class.rawValue) · \(dependency.attributes.role)"
                        + (dependency.attributes.exclusion.isEmpty
                            ? "" : " · \(dependency.attributes.exclusion)")
                        + " · \(dependency.attributes.fidelity.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("referenceAttributesLabel_\(position)")
            }
            Spacer(minLength: 0)
            Button("Remove") {
                Task { await model.removeWorkshopReference(dependencyID: dependency.dependencyID) }
            }
            .buttonStyle(.borderless)
            .disabled(model.isWorkshopRequirementWholeLocked)
            .accessibilityIdentifier("removeReferenceButton_\(position)")
        }
        .padding(.vertical, 2)
    }
}

/// §5.4's Write Prompt sheet (§14.5): body plus an optional target-model line.
struct WritePromptSheet: View {
    @Bindable var model: ProjectWindowModel
    @Environment(\.dismiss) private var dismiss
    @State private var bodyText = ""
    @State private var targetModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Write Prompt").font(.headline)
            TextField("Prompt body", text: $bodyText, axis: .vertical)
                .lineLimit(6 ... 14)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("writePromptBodyField")
            TextField("Target model (optional)", text: $targetModel)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("writePromptTargetModelField")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Write Prompt") {
                    let body = bodyText
                    let target = targetModel
                    Task {
                        await model.createWorkshopPrompt(body: body, targetModel: target)
                        dismiss()
                    }
                }
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("commitWritePromptButton")
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

/// §7.2's `setPromptBody` surface: current prompt only.
struct EditPromptBodySheet: View {
    let model: ProjectWindowModel
    let current: AssetPromptDetail?
    let onDone: () -> Void
    @State private var bodyText = ""
    @State private var loadedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Prompt Body").font(.headline)
            TextField("Prompt body", text: $bodyText, axis: .vertical)
                .lineLimit(10 ... 18)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("editPromptBodyField")
            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save") {
                    guard let current else { return }
                    let body = bodyText
                    Task {
                        await model.setWorkshopPromptBody(promptID: current.id, body: body)
                        onDone()
                    }
                }
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("commitEditPromptBodyButton")
            }
        }
        .padding(20)
        .frame(width: 520)
        .task(id: current?.id) {
            guard loadedID != current?.id else { return }
            loadedID = current?.id
            bodyText = current?.body ?? ""
        }
    }
}

/// §5.3's Add Reference picker: approved requirements project-wide (`addDependency`
/// underneath — the cycle check is the engine's).
struct AddReferenceSheet: View {
    let model: ProjectWindowModel
    let requirementID: UUID
    @Environment(\.dismiss) private var dismiss

    var candidates: [RequirementSummary] {
        model.scopedRequirementSummaries.filter { candidate in
            candidate.id != requirementID
                && candidate.displayStatus == .approved
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Reference").font(.headline)
            Text("Approved requirements only — every reference is another requirement's "
                    + "approved asset.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if candidates.isEmpty {
                Text("No approved requirements yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("addReferenceEmptyText")
            }
            ForEach(candidates) { candidate in
                Button {
                    let id = candidate.id
                    Task {
                        await model.addWorkshopReference(dependencyRequirementID: id)
                        dismiss()
                    }
                } label: {
                    Text("\(candidate.entityName) — \(candidate.name)")
                }
                .accessibilityIdentifier("addReferenceCandidateRow")
            }
            Spacer()
            HStack { Spacer(); Button("Cancel") { dismiss() } }
        }
        .padding(20)
        .frame(width: 420, height: 360)
    }
}
