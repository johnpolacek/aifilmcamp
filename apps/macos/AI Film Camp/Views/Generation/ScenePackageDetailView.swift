import AppKit
import FilmCore
import SwiftUI

/// PHASE5_DESIGN §5.2's scene package view (Plan 020 contracts B–C): the header with both
/// state axes visibly distinct, the project-wide profile picker, the §3.2 reference plan,
/// the continuity context, and the prompt panel over Plan 019's operations.
///
/// Presentation only. Enablement is §5.5's table decided by reads (`+Generation`); refusal
/// copy is FilmCore's strings verbatim. Generate/Regenerate (Plan 021) render here behind
/// `ScenePromptRunGate`'s mirror — §5.5's shown-when table literally: Generate always,
/// Regenerate when a current prompt exists.
struct ScenePackageDetailView: View {
    private enum ScrollTarget: Hashable {
        case promptPanel
    }

    @Bindable var model: ProjectWindowModel
    var promptRevealToken = 0

    @State private var writePromptSheet = false
    @State private var cardEditor: PromptCardEditorPresentation?
    @State private var deleteCardTarget: ScenePromptCard?
    @State private var deleteSetTarget: ScenePromptSet?
    @State private var creativeDirectionEditor = false
    @State private var directionGenerationSceneID: UUID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let detail = model.scenePackageDetail,
               let selectedID = model.selectedReferenceRequirementID,
               let reference = detail.plan.first(where: { $0.requirementID == selectedID }),
               let requirement = model.requirementDetail,
               requirement.requirement.id == selectedID {
                SceneReferenceDetailView(
                    model: model,
                    reference: reference,
                    detail: requirement,
                    generateBodyReference: reference.templateCode == "face_closeup"
                        && reference.isSatisfied
                        ? detail.plan.first {
                            $0.entityID == reference.entityID
                                && $0.templateCode == "full_body"
                        }
                        : nil
                )
            } else if let detail = model.scenePackageDetail {
                ScrollViewReader { proxy in
                    ScrollView { content(detail) }
                        .onChange(of: promptRevealToken) { _, _ in
                            // Wait until the report has closed and the card has laid out.
                            Task { @MainActor in
                                await Task.yield()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(ScrollTarget.promptPanel, anchor: .top)
                                }
                            }
                        }
                        .onChange(of: model.isReplacingScenePrompt) { _, replacing in
                            guard replacing else { return }
                            Task { @MainActor in
                                await Task.yield()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(ScrollTarget.promptPanel, anchor: .top)
                                }
                            }
                        }
                        .onChange(of: model.scenePromptProgress) { _, progress in
                            guard progress != nil else { return }
                            Task { @MainActor in
                                await Task.yield()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(ScrollTarget.promptPanel, anchor: .top)
                                }
                            }
                        }
                }
            } else if let scene = model.sceneDetail {
                ScrollView { unpreparedContent(scene) }
            } else {
                ContentUnavailableView(
                    "Select a scene",
                    systemImage: ProjectSection.generation.systemImage
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CampAppearance.canvas)
        .task(id: model.selectedPackageSceneID) {
            await model.loadScenePackageDetail()
            await model.loadGenerationHistory()
        }
        .task(id: model.refreshToken) {
            await model.loadGenerationHistory()
        }
        .task { await model.selectFirstWorkspaceSceneIfNeeded() }
    }

    private func unpreparedContent(_ detail: SceneDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(detail.scene.ordinal). \(detail.scene.heading)")
                    .font(CampAppearance.title(26))
                Spacer()
                Label(SceneWorkspaceStatus.needsImages.rawValue, systemImage: SceneWorkspaceStatus.needsImages.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SceneDataView(model: model, package: nil)
            switch model.workspaceNextAction {
            case .analyzeScreenplay:
                Button(model.analyzeButtonTitle) { Task { await model.prepareExtraction() } }
                    .buttonStyle(CampPrimaryButtonStyle())
                    .disabled(!model.canAnalyze)
                    .accessibilityIdentifier("sceneWorkspace.nextAction.analyze")
            case .buildReferenceList:
                Button("Build Reference List") { Task { await model.buildAssetManifest() } }
                    .buttonStyle(CampPrimaryButtonStyle())
                    .accessibilityIdentifier("sceneWorkspace.nextAction.buildReferences")
            default:
                Text("Use Project Actions to prepare references for this scene.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func content(_ detail: ScenePackageDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(detail)
            overLimitRefusal(detail)
            SceneDataView(model: model, package: detail)
            RequiredReferencesGrid(
                model: model,
                references: detail.plan,
                onOpen: { reference in
                    Task {
                        await model.openReferenceDetail(
                            requirementID: reference.requirementID
                        )
                    }
                }
            )
            inlineNextAction
            promptPanel(detail)
                .id(ScrollTarget.promptPanel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        // §14.7's stale-export confirm names the reason the store refused with.
        .confirmationDialog(
            staleConfirmText,
            isPresented: Binding(
                get: { model.pendingStaleExport != nil },
                set: { if !$0 { model.cancelStaleExport() } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingStaleExport
        ) { pending in
            Button("Export Anyway") {
                Task { await model.confirmStaleExport() }
            }
            .accessibilityIdentifier("confirmStaleExportButton")
            Button("Cancel", role: .cancel) { model.cancelStaleExport() }
        } message: { _ in
            Text(staleConfirmMessage)
        }
        .sheet(isPresented: $writePromptSheet) {
            WriteScenePromptSheet(model: model, sceneID: detail.sceneID)
        }
        .sheet(item: $cardEditor) { presentation in
            ScenePromptCardEditorSheet(model: model, presentation: presentation) {
                cardEditor = nil
            }
        }
        .sheet(isPresented: $creativeDirectionEditor, onDismiss: {
            guard let sceneID = directionGenerationSceneID else { return }
            directionGenerationSceneID = nil
            // Close the editor before the run can present its first-run disclosure.
            Task {
                guard model.selectedPackageSceneID == sceneID else { return }
                await model.prepareScenePromptRun()
            }
        }) {
            ScenePromptDirectionSheet(
                model: model,
                sceneID: detail.sceneID,
                regeneratesPrompt: detail.currentSet != nil
            ) {
                directionGenerationSceneID = detail.sceneID
            }
        }
    }

    // MARK: - Header: ordinal + heading, both axes, the picker, staleness

    private func header(_ detail: ScenePackageDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(detail.ordinal). \(detail.heading)")
                    .font(CampAppearance.title(26))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("generation.package.title")
                    .accessibilityLabel("Scene \(detail.ordinal): \(detail.heading)")
                Spacer(minLength: 8)

                let status = model.workspaceStatus(forSceneID: detail.sceneID)
                Label(status.rawValue, systemImage: status.systemImage)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(CampAppearance.inset, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityIdentifier("sceneWorkspace.status")
                    .accessibilityLabel("Scene status: \(status.rawValue)")

            }

            if let current = detail.currentSet, current.isStale {
                Text("Prompt built from earlier inputs (\(staleReasonText(current.staleReason)))")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("generation.package.staleBadge")
                    .accessibilityLabel(
                        "Stale: \(staleReasonText(current.staleReason))"
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// §3.2: the budget refuses, never truncates — inline, naming both numbers.
    @ViewBuilder
    private func overLimitRefusal(_ detail: ScenePackageDetail) -> some View {
        if detail.referencesExceedProfileLimit {
            let satisfied = detail.plan.filter(\.isSatisfied).count
            Text(
                "This scene plans \(satisfied) reference images; \(detail.activeProfile.displayName) "
                    + "accepts \(detail.activeProfile.imageReferenceLimit). Open a reference "
                    + "below and mark it optional or not needed to reduce the set."
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("generation.package.overLimitRefusal")
        }
    }

    // MARK: - The reference plan (§3.2 order)

    private func referencePlan(_ detail: ScenePackageDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("References").font(.headline)
            if detail.plan.isEmpty {
                Text("No references yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("generation.package.referencesEmpty")
            }
            ForEach(Array(detail.plan.enumerated()), id: \.element.id) { index, reference in
                referenceRow(index, reference)
            }
            // Optional requirements render greyed below the planned rows, tagged
            // `optional`, un-designated, never counted (§3.2).
            ForEach(detail.optionalRequirements) { optional in
                HStack(spacing: 8) {
                    Text("optional")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Text("\(optional.entityName) — \(optional.requirementName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("generation.package.optionalRow.\(optional.requirementID.uuidString.prefix(8))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One planned reference in plan order: designator, name, class, satisfaction.
    /// An unsatisfied row carries the deep link into the Asset Workshop through Plan 017's
    /// `RevealTarget.requirement` — reused, not re-minted (§5.4).
    private func referenceRow(_ index: Int, _ reference: ScenePlannedReference) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                if reference.isSatisfied, let designator = reference.designator {
                    Text("@Image \(designator)")
                        .font(.caption.weight(.medium))
                } else {
                    Button("no approved version yet") {
                        Task { await model.reveal(.requirement(id: reference.requirementID)) }
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                }
            }
            .frame(width: 140, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(reference.entityName) — \(reference.requirementName)")
                    .font(.caption)
                    .foregroundStyle(reference.isSatisfied ? .primary : .secondary)
                Text(attributesLine(reference))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("generation.package.referenceRow.\(index + 1)")
    }

    private func attributesLine(_ reference: ScenePlannedReference) -> String {
        let attributes = reference.attributes
        return "\(reference.class.rawValue) · \(attributes.role)"
            + (attributes.exclusion.isEmpty ? "" : " · \(attributes.exclusion)")
            + " · \(attributes.fidelity.rawValue)"
    }

    // MARK: - Continuity (read-only, as derived)

    private func continuityContext(_ detail: ScenePackageDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Continuity").font(.headline)
            if detail.continuity.entries.isEmpty {
                Text("No continuity states enter this scene.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("generation.package.continuityEmpty")
            }
            ForEach(detail.continuity.entries) { entry in
                HStack(spacing: 6) {
                    Text(entry.entityName).font(.caption)
                    Text(entry.category.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("generation.package.continuityRow")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The prompt panel (§5.2, Phase 3's pattern at scene scale)

    private func promptPanel(_ detail: ScenePackageDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CampSectionLabel("Seedance Prompt")
                Spacer()
                Text(detail.activeProfile.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let progress = model.scenePromptProgress {
                ScenePromptGenerationProgress(
                    progress: progress,
                    startedAt: model.scenePromptRunStartedAt,
                    qualityMode: model.scenePromptQualityMode,
                    cancel: { Task { await model.cancelScenePromptRun() } }
                )
            }

            if !detail.creativeDirection.isEmpty, !model.isReplacingScenePrompt {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Direction for Next Generation")
                        .font(.caption.weight(.semibold))
                    Text(detail.creativeDirection)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: CampAppearance.radius))
                .accessibilityIdentifier("generation.package.creativeDirection")
            }

            if let current = detail.currentSet, !model.isReplacingScenePrompt {
                ForEach(Array(current.cards.enumerated()), id: \.element.id) { index, card in
                    ScenePromptCardView(
                        model: model,
                        position: index + 1,
                        detail: card,
                        canDelete: current.cards.count > 1,
                        canMoveUp: index > 0,
                        canMoveDown: index + 1 < current.cards.count,
                        onDelete: {
                            deleteCardTarget = card.card
                        },
                        onMoveUp: {
                            moveCard(in: current, from: index, to: index - 1)
                        },
                        onMoveDown: {
                            moveCard(in: current, from: index, to: index + 1)
                        }
                    )
                }

                HStack {
                    Button("Add Prompt Card…") {
                        cardEditor = PromptCardEditorPresentation(setID: current.set.id)
                    }
                    .accessibilityIdentifier("generation.package.addCard")
                    Spacer()
                    Button("Delete Prompt Set…", role: .destructive) {
                        deleteSetTarget = current.set
                    }
                    .accessibilityIdentifier("generation.package.deleteSet")
                }

                setHistoryDisclosure(detail)
            } else if !model.isReplacingScenePrompt {
                Text("No prompt cards yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("generation.package.promptEmpty")
            }

            if promptActionsAreAvailable(for: detail), !model.isReplacingScenePrompt {
                HStack(spacing: 8) {
                    Button(promptGenerationButtonTitle(for: detail)) {
                        Task { await model.prepareScenePromptRun() }
                    }
                    .buttonStyle(CampPrimaryButtonStyle())
                    .disabled(model.sceneGenerateDisabledReason != nil)
                    .help(model.sceneGenerateDisabledReason ?? "")
                    .accessibilityIdentifier(
                        detail.currentSet == nil
                            ? "generation.package.generate"
                            : "generation.package.regenerate"
                    )
                    .accessibilityLabel(promptGenerationButtonTitle(for: detail))
                    Picker("Quality", selection: $model.scenePromptQualityMode) {
                        Text("Standard · 1 request")
                            .tag(ScenePromptQualityMode.standard)
                        Text("High Quality · 2 requests")
                            .tag(ScenePromptQualityMode.highQuality)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(model.scenePromptProgress != nil)
                    .accessibilityIdentifier("generation.package.promptQuality")
                    Button("Write Prompt…") { writePromptSheet = true }
                        .accessibilityIdentifier("generation.package.writePrompt")
                        .accessibilityLabel("Write Prompt")
                    Button("Add Direction…") {
                        creativeDirectionEditor = true
                    }
                    .disabled(model.sceneGenerateDisabledReason != nil)
                    .help(model.sceneGenerateDisabledReason ?? "Add direction and generate the scene prompt")
                    .accessibilityIdentifier("generation.package.editCreativeDirection")
                    .accessibilityLabel("Add Creative Direction")
                    Button("Export Scene Package…") {
                        if let id = model.selectedPackageSceneID {
                            Task { await model.exportScenePackage(sceneID: id) }
                        }
                    }
                    .disabled(!model.canExportScenePackage)
                    .accessibilityIdentifier("generation.package.export")
                    .accessibilityLabel("Export Scene Package")
                    Spacer(minLength: 0)
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .campPanel()
        .confirmationDialog(
            "Delete this prompt card?",
            isPresented: Binding(
                get: { deleteCardTarget != nil },
                set: { if !$0 { deleteCardTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteCardTarget
        ) { card in
            Button("Delete Prompt Card", role: .destructive) {
                Task { await model.deleteScenePromptCard(cardID: card.id) }
            }
            .accessibilityIdentifier("generation.package.confirmDeleteCard")
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete prompt set \(deleteSetTarget?.setNumber ?? 0)? The previous set becomes current.",
            isPresented: Binding(
                get: { deleteSetTarget != nil },
                set: { if !$0 { deleteSetTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteSetTarget
        ) { set in
            Button("Delete Prompt Set", role: .destructive) {
                Task { await model.deleteScenePromptSet(setID: set.id) }
            }
            .accessibilityIdentifier("generation.package.confirmDeleteSet")
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var inlineNextAction: some View {
        switch model.workspaceNextAction {
        case .addImage:
            EmptyView()
        case .generatePrompt, .updatePrompt:
            EmptyView()
        case .analyzeScreenplay:
            Button(model.analyzeButtonTitle) { Task { await model.prepareExtraction() } }
                .buttonStyle(CampPrimaryButtonStyle())
                .disabled(!model.canAnalyze)
                .accessibilityIdentifier("sceneWorkspace.nextAction.analyze")
        case .buildReferenceList:
            Button("Build Reference List") { Task { await model.buildAssetManifest() } }
                .buttonStyle(CampPrimaryButtonStyle())
                .disabled(!model.canBuildAssetManifest)
                .accessibilityIdentifier("sceneWorkspace.nextAction.buildReferences")
        case .importScreenplay, nil:
            EmptyView()
        }
    }

    private func promptGenerationButtonTitle(for detail: ScenePackageDetail) -> String {
        guard let current = detail.currentSet else { return "Generate Prompt…" }
        return current.isStale ? "Update Prompt…" : "Regenerate Prompt…"
    }

    private func setHistoryDisclosure(_ detail: ScenePackageDetail) -> some View {
        let history = model.generationPromptSetHistory.filter { $0.set.id != detail.currentSet?.set.id }
        return Group {
            if !history.isEmpty {
                DisclosureGroup("History (\(history.count))") {
                    ForEach(history, id: \.set.id) { row in
                        HStack {
                            Text("Set \(row.set.setNumber) · \(row.cards.count) card\(row.cards.count == 1 ? "" : "s")")
                                .font(.caption)
                            Spacer()
                            Text(row.set.humanEdited ? "Human edited" : "Generated")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption)
                .accessibilityIdentifier("generation.package.historyDisclosure")
            }
        }
    }

    private func moveCard(in set: ScenePromptSetDetail, from: Int, to: Int) {
        guard set.cards.indices.contains(from), set.cards.indices.contains(to) else { return }
        var ids = set.cards.map(\.card.id)
        ids.swapAt(from, to)
        Task {
            await model.reorderScenePromptCards(setID: set.set.id, orderedCardIDs: ids)
        }
    }

    /// Preparation blockers own the scene's next gesture. Keeping prompt handoff
    /// controls out of the panel until those blockers are cleared prevents a disabled
    /// second workflow from competing with the one actionable instruction above it.
    private func promptActionsAreAvailable(for detail: ScenePackageDetail) -> Bool {
        guard model.workspaceStatus(forSceneID: detail.sceneID) != .needsImages else {
            return false
        }
        switch model.workspaceNextAction {
        case .analyzeScreenplay, .buildReferenceList, .addImage, .importScreenplay:
            return false
        case .generatePrompt, .updatePrompt, nil:
            return true
        }
    }

    // MARK: - Copy helpers

    private func assetReadyLabel(_ state: SceneReadinessState) -> String {
        switch state {
        case .assetReady: "Asset Ready"
        case .partial: "Partial"
        case .blocked: "Blocked"
        }
    }

    private func packageStateLabel(_ state: ScenePackageState) -> String {
        switch state {
        case .needsPreparation: "Needs Preparation"
        case .generationReady: "Generation Ready"
        case .stale: "Stale"
        }
    }

    /// §3.4's reason spellings, verbatim — the confirm copy quotes the store.
    private func staleReasonText(_ reason: ScenePromptStaleReason?) -> String {
        switch reason {
        case .olderInputFormat: "older input format"
        case .inputsChanged, nil: "inputs changed"
        }
    }

    private var staleConfirmText: String {
        guard let pending = model.pendingStaleExport else { return "" }
        return "This package's inputs changed since its prompt was prepared (\(pending.reason)). Export it anyway?"
    }

    private var staleConfirmMessage: String {
        "The exported files are built from the stored prompt and its recorded citations."
    }
}

// MARK: - Plan 023 scene-first workspace pieces

private struct SceneDataView: View {
    @Bindable var model: ProjectWindowModel
    let package: ScenePackageDetail?
    @State private var isEntitiesExpanded = false
    @State private var isContinuityExpanded = false
    @State private var isScreenplayExpanded = false
    @State private var inspectedEntity: Entity?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CampSectionLabel("Scene Data")
                .accessibilityIdentifier("sceneData.disclosure")
                .accessibilityLabel("Scene Data")

            if let detail = model.sceneDetail {
                SceneSynopsisEditor(model: model, scene: detail.scene)

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isEntitiesExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(isEntitiesExpanded ? 90 : 0))
                                .foregroundStyle(.secondary)
                            Text("Entities").font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sceneData.entitiesDisclosure")
                    .accessibilityLabel("Entities")
                    .accessibilityValue(isEntitiesExpanded ? "Expanded" : "Collapsed")

                    if isEntitiesExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Spacer()
                                Button("Edit Entities…") {
                                    model.presentedSheet = .sceneEntities(sceneID: detail.scene.id)
                                }
                                .accessibilityIdentifier("sceneData.editEntities")
                            }
                            ForEach(SceneEntityRole.allCases, id: \.self) { role in
                                let rows = detail.entities(role: role)
                                if rows.isEmpty == false {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(role.displayName).font(.caption.weight(.semibold))
                                        ForEach(rows) { entity in
                                            HStack {
                                                Button(entity.name) {
                                                    let section = section(for: entity.kind)
                                                    model.setSelection([entity.id], in: section)
                                                    inspectedEntity = entity
                                                }
                                                .buttonStyle(.link)
                                                .accessibilityIdentifier("sceneData.entityLink")
                                                Spacer()
                                                Button("Add State") {
                                                    model.presentedSheet = .addState(entityID: entity.id)
                                                }
                                                .buttonStyle(.borderless)
                                                .accessibilityIdentifier("sceneData.addState")
                                            }
                                            .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isContinuityExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(isContinuityExpanded ? 90 : 0))
                                .foregroundStyle(.secondary)
                            Text("Continuity").font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sceneData.continuityDisclosure")
                    .accessibilityLabel("Continuity")
                    .accessibilityValue(isContinuityExpanded ? "Expanded" : "Collapsed")

                    if isContinuityExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Spacer()
                                Button("Add Event…") { model.presentedSheet = .addEvent }
                                    .accessibilityIdentifier("sceneData.addEvent")
                            }
                            if package?.continuity.entries.isEmpty != false {
                                Text("No continuity states enter this scene.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(detail.states) { state in
                                HStack {
                                    Text("\(model.entityNames[state.entityID] ?? "Entity") · \(state.category.displayName): \(state.description)")
                                        .font(.caption)
                                    Spacer()
                                    Button("Edit") { model.presentedSheet = .editState(state) }
                                        .buttonStyle(.borderless)
                                        .accessibilityIdentifier("sceneData.editState")
                                }
                            }
                            ForEach(model.continuityEvents.filter { $0.sceneID == detail.scene.id }) { event in
                                HStack {
                                    Text(event.description).font(.caption)
                                    Spacer()
                                    Button("Edit") { model.presentedSheet = .editEvent(event) }
                                        .buttonStyle(.borderless)
                                        .accessibilityIdentifier("sceneData.editEvent")
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isScreenplayExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(isScreenplayExpanded ? 90 : 0))
                                .foregroundStyle(.secondary)
                            Text("Screenplay").font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sceneData.screenplayDisclosure")
                    .accessibilityLabel("Screenplay")
                    .accessibilityValue(isScreenplayExpanded ? "Expanded" : "Collapsed")

                    if isScreenplayExpanded {
                        InlineSceneScreenplayEditor(
                            model: model,
                            sceneID: detail.scene.id,
                            storedText: model.sceneDetailText
                        )
                        .id(detail.scene.id)
                        .padding(.top, 8)
                    }
                }
            }
        }
        .sheet(item: $inspectedEntity) { entity in
            let entitySection = section(for: entity.kind)
            EntityInspectorView(model: model, section: entitySection, entityID: entity.id)
                .frame(minWidth: 520, minHeight: 620)
                .accessibilityIdentifier("sceneData.entityInspectorSheet")
        }
    }

    private func section(for kind: EntityKind) -> ProjectSection {
        switch kind {
        case .character: .characters
        case .location: .locations
        case .prop: .props
        case .vehicle: .vehicles
        case .creature: .creatures
        case .object: .objects
        }
    }
}

private struct InlineSceneScreenplayEditor: View {
    @Bindable var model: ProjectWindowModel
    let sceneID: UUID
    let storedText: String

    @State private var draft: String
    @State private var saveTask: Task<Void, Never>?
    @State private var editRevision = 0

    init(model: ProjectWindowModel, sceneID: UUID, storedText: String) {
        self.model = model
        self.sceneID = sceneID
        self.storedText = storedText
        _draft = State(initialValue: storedText)
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 220)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: CampAppearance.radius))
            .overlay(RoundedRectangle(cornerRadius: CampAppearance.radius).stroke(Color.secondary.opacity(0.25)))
            .tracksTextEditing(model)
            .accessibilityIdentifier("sceneData.screenplayText")
            .accessibilityLabel("Screenplay")
            .onChange(of: draft) { _, text in
                saveTask?.cancel()
                saveTask = nil
                guard text != storedText,
                      text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                else { return }

                editRevision &+= 1
                let revision = editRevision
                saveTask = Task {
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        return
                    }
                    guard Task.isCancelled == false else { return }
                    await model.setSceneText(sceneID: sceneID, text: text)
                    guard editRevision == revision else { return }
                    saveTask = nil
                }
            }
            .onChange(of: storedText) { _, text in
                guard saveTask == nil, draft != text else { return }
                draft = text
            }
    }
}

private struct RequiredReferencesGrid: View {
    let model: ProjectWindowModel
    let references: [ScenePlannedReference]
    let onOpen: (ScenePlannedReference) -> Void
    @State private var isAddingReference = false
    @State private var isChoosingCharacterBundle = false

    private var bundles: [SceneReferenceBundle] {
        var seen: Set<UUID> = []
        return references.compactMap { reference in
            guard seen.insert(reference.entityID).inserted else { return nil }
            return SceneReferenceBundle(
                entityID: reference.entityID,
                entityName: reference.entityName,
                entityKind: reference.entityKind,
                references: references.filter { $0.entityID == reference.entityID }
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CampSectionLabel("Required References")
                Spacer()
                Button {
                    isChoosingCharacterBundle = true
                } label: {
                    Label("Choose Character Bundle", systemImage: "person.crop.rectangle.stack")
                }
                .accessibilityIdentifier("sceneReferences.chooseCharacterBundle")
                Button {
                    isAddingReference = true
                } label: {
                    Label("Add Image Reference", systemImage: "plus")
                }
                .accessibilityIdentifier("sceneReferences.addImageReference")
            }
            if references.isEmpty {
                Text("No required references for this scene.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sceneReferences.empty")
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(bundles) { bundle in
                        SceneReferenceBundleCard(
                            model: model,
                            bundle: bundle,
                            onOpen: onOpen
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("sceneReferences.grid")
        .sheet(isPresented: $isChoosingCharacterBundle) {
            if let sceneID = model.selectedPackageSceneID {
                CharacterBundlePicker(
                    model: model, sceneID: sceneID,
                    currentRequirementIDs: Set(references.map(\.requirementID))
                )
            }
        }
        .sheet(isPresented: $isAddingReference) {
            AddSceneImageReferenceSheet(
                model: model,
                existingRequirementIDs: Set(references.map(\.requirementID))
            )
        }
    }
}

private struct AddSceneImageReferenceSheet: View {
    @Bindable var model: ProjectWindowModel
    let existingRequirementIDs: Set<UUID>

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [RequirementSummary] = []
    @State private var isLoading = true
    @State private var uploadName = ""
    @State private var isUploading = false
    @State private var uploadedReferenceName: String?

    private var available: [RequirementSummary] {
        candidates.filter { existingRequirementIDs.contains($0.id) == false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(uploadedReferenceName == nil ? "Add Image Reference" : "Image Reference Added")
                        .font(CampAppearance.title(20))
                    Text(
                        uploadedReferenceName == nil
                            ? "Upload a new image or choose an approved project image for this scene's next prompt."
                            : "Regenerate the prompt now, or close this window to update it manually."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if uploadedReferenceName == nil {
                    Button("Done") { dismiss() }
                }
            }

            if let uploadedReferenceName {
                Spacer()
                ContentUnavailableView(
                    "Reference Ready",
                    systemImage: "checkmark.circle.fill",
                    description: Text("“\(uploadedReferenceName)” is now included in this scene.")
                )
                Spacer()
                HStack {
                    Spacer()
                    Button("Manually Update") { dismiss() }
                        .accessibilityIdentifier("sceneReferences.upload.manualUpdate")
                    Button("Regenerate Prompt") {
                        dismiss()
                        Task { await model.prepareScenePromptRun() }
                    }
                    .buttonStyle(CampPrimaryButtonStyle())
                    .disabled(model.sceneGenerateDisabledReason != nil)
                    .help(model.sceneGenerateDisabledReason ?? "")
                    .accessibilityIdentifier("sceneReferences.upload.regeneratePrompt")
                }
            } else {
                GroupBox("Upload a new scene reference") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Give the image a descriptive role, such as “Main Screen — RustCorp Helicopter Feed.”")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Reference name (optional)", text: $uploadName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isUploading)
                            .accessibilityIdentifier("sceneReferences.upload.name")

                        HStack(spacing: 10) {
                            Button("Add Image…") {
                                isUploading = true
                                Task {
                                    defer { isUploading = false }
                                    guard let url = await model.chooseSceneImageReferenceUpload()
                                    else { return }
                                    if uploadName.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty {
                                        uploadName = suggestedName(for: url)
                                    }
                                    let name = uploadName.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )
                                    let added = await model.uploadImageReferenceToCurrentScene(
                                        name: name,
                                        from: url
                                    )
                                    if added {
                                        uploadedReferenceName = name
                                    }
                                }
                            }
                            .buttonStyle(CampPrimaryButtonStyle())
                            .disabled(isUploading)
                            .accessibilityIdentifier("sceneReferences.upload.add")

                            Spacer()

                            if isUploading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .padding(6)
                }

                Text("Approved Project Images")
                    .font(.headline)

                if isLoading {
                    ProgressView("Loading approved images…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if available.isEmpty {
                    ContentUnavailableView(
                        "No Other Approved Images",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Choose an image above to upload it directly.")
                    )
                } else {
                    List(available) { requirement in
                        HStack(spacing: 12) {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(requirement.entityName)
                                    .font(.body.weight(.medium))
                                Text(requirement.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") {
                                Task {
                                    await model.addImageReferenceToCurrentScene(requirement)
                                    candidates.removeAll { $0.id == requirement.id }
                                }
                            }
                            .buttonStyle(CampPrimaryButtonStyle())
                            .controlSize(.small)
                            .accessibilityIdentifier("sceneReferences.add.\(requirement.id.uuidString)")
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 560)
        .task {
            candidates = await model.approvedImageReferenceCandidates()
            isLoading = false
        }
    }

    private func suggestedName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { word in
                let value = String(word)
                return value.prefix(1).uppercased() + value.dropFirst()
            }
            .joined(separator: " ")
    }
}

private struct ScenePromptGenerationProgress: View {
    let progress: ScenePromptRunProgressPresentation
    let startedAt: Date?
    let qualityMode: ScenePromptQualityMode
    let cancel: () -> Void

    private var steps: [String] {
        qualityMode == .highQuality
            ? ["Context", "Connect", "Draft", "Improve", "Validate", "Save"]
            : ["Context", "Connect", "Generate", "Validate", "Save"]
    }

    private var currentStep: Int {
        switch progress.stage {
        case "planning", "preparingContext": 0
        case "preparingHarness": 1
        case "running", "generating": 2
        case "reviewing": 3
        case "validating": qualityMode == .highQuality ? 4 : 3
        case "apply", "saving", "completed": qualityMode == .highQuality ? 5 : 4
        case "failed": 0
        default: 0
        }
    }

    private var title: String {
        switch progress.stage {
        case "planning", "preparingContext": "Preparing scene context"
        case "preparingHarness": "Connecting to Codex"
        case "running", "generating": qualityMode == .highQuality
            ? "Writing the draft prompt" : "Writing and reviewing the prompt"
        case "reviewing": "Improving the draft prompt"
        case "validating": qualityMode == .highQuality
            ? "Validating the improved prompt" : "Validating the final prompt"
        default: "Saving scene prompt"
        }
    }

    private var passLabel: String? {
        switch progress.stage {
        case "running", "generating": qualityMode == .highQuality ? "Pass 1 of 2" : "1 request"
        case "reviewing": qualityMode == .highQuality ? "Pass 2 of 2" : nil
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(progress.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let startedAt {
                            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                            Text([passLabel, "Elapsed \(Self.format(elapsed))"]
                                .compactMap { $0 }
                                .joined(separator: " · "))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 12)
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        Rectangle()
                            .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(height: 1)
                    }
                    Label {
                        Text(step)
                    } icon: {
                        Image(systemName: index < currentStep
                            ? "checkmark.circle.fill"
                            : index == currentStep ? "circle.inset.filled" : "circle")
                    }
                    .font(.caption2)
                    .foregroundStyle(index <= currentStep ? Color.accentColor : Color.secondary)
                    .fixedSize()
                }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: CampAppearance.radius))
        .overlay(RoundedRectangle(cornerRadius: CampAppearance.radius).stroke(Color.accentColor.opacity(0.25)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("generation.package.runProgress")
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        if whole < 60 { return "\(whole)s" }
        return "\(whole / 60)m \(whole % 60)s"
    }
}

private struct SceneReferenceBundle: Identifiable {
    let entityID: UUID
    let entityName: String
    let entityKind: EntityKind
    let references: [ScenePlannedReference]

    var id: UUID { entityID }

    var orderedReferences: [ScenePlannedReference] {
        references.sorted {
            let left = slotRank($0)
            let right = slotRank($1)
            if left != right { return left < right }
            return ($0.requirementName.lowercased(), $0.requirementID.uuidString)
                < ($1.requirementName.lowercased(), $1.requirementID.uuidString)
        }
    }

    var face: ScenePlannedReference? {
        references.first { $0.templateCode == "face_closeup" }
    }

    var body: ScenePlannedReference? {
        references.first { $0.templateCode == "full_body" }
    }

    var readyCount: Int { references.filter(\.isSatisfied).count }
    var syncCount: Int { references.filter(\.isStale).count }

    private func slotRank(_ reference: ScenePlannedReference) -> Int {
        guard entityKind == .character else { return 0 }
        return switch reference.templateCode {
        case "face_closeup": 0
        case "full_body": 1
        default: 2
        }
    }
}

private struct SceneReferenceBundleCard: View {
    let model: ProjectWindowModel
    let bundle: SceneReferenceBundle
    let onOpen: (ScenePlannedReference) -> Void
    @State private var outfitReference: ScenePlannedReference?

    private var bodyReadyFromFace: ScenePlannedReference? {
        guard bundle.entityKind == .character,
              bundle.face?.isSatisfied == true,
              let body = bundle.body
        else { return nil }
        return body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bundle.entityName)
                        .font(CampAppearance.title(20))
                        .lineLimit(1)
                    Text(bundle.entityKind == .character
                         ? "Character Bundle · \(bundle.body?.class == .look ? bundle.body?.requirementName ?? "Outfit" : "Original Outfit")"
                         : "\(bundle.entityKind.rawValue.capitalized) Bundle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Label(
                    bundle.syncCount > 0
                        ? "\(bundle.syncCount) needs sync"
                        : "\(bundle.readyCount) of \(bundle.references.count) ready",
                    systemImage: bundle.syncCount > 0
                        ? "arrow.triangle.2.circlepath"
                        : bundle.readyCount == bundle.references.count
                            ? "checkmark.circle.fill" : "square.stack.3d.up"
                )
                .font(.caption)
                .foregroundStyle(
                    bundle.syncCount > 0
                        ? Color.orange
                        : bundle.readyCount == bundle.references.count
                            ? Color.green : Color.secondary
                )
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(bundle.orderedReferences) { reference in
                    SceneReferenceCard(
                        model: model,
                        reference: reference,
                        localNumber: reference.designator,
                        showsEntityName: false,
                        isGenerating: model.referenceImageJobIsBusy(
                            for: reference.requirementID
                        ),
                        generationMessage: model.referenceImageJobProgressMessage(
                            for: reference.requirementID
                        ) ?? "Preparing image generation…",
                        generationError: model.referenceImageJobError(
                            for: reference.requirementID
                        ),
                        onOpen: { onOpen(reference) }
                    )
                }
            }

            if bundle.entityKind == .character,
               let body = bundle.body, body.isSatisfied {
                if model.referenceImageJobIsBusy(for: body.requirementID) == false {
                    HStack {
                        Spacer()
                        Button {
                            outfitReference = body
                        } label: {
                            Label("Change Outfit…", systemImage: "tshirt")
                        }
                        .buttonStyle(CampPrimaryButtonStyle())
                        .disabled(
                            model.referenceImageJobState(for: body.requirementID)?
                                .preventsDuplicate == true
                        )
                        .help("Create a new outfit bundle for this scene, preserving the original.")
                        .accessibilityLabel("Change outfit for \(bundle.entityName)")
                        .accessibilityIdentifier(
                            "sceneReferences.changeOutfit.\(bundle.entityID.uuidString.prefix(8))"
                        )
                        if bodyReadyFromFace != nil, body.class == .identity {
                            Button("Update Body from Face") {
                                Task {
                                    await model.generateBodyFromFace(
                                        requirementID: body.requirementID
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                model.referenceImageJobState(for: body.requirementID)?
                                    .preventsDuplicate == true
                            )
                            .accessibilityIdentifier(
                                "sceneReferences.generateBodyFromFace.\(bundle.entityID.uuidString.prefix(8))"
                            )
                        }
                    }
                }
            } else if bundle.entityKind == .character,
                      bundle.face?.isSatisfied == false,
                      bundle.body?.isSatisfied == false {
                Text("Create Face Closeup first to generate the body from it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Remove from Scene", role: .destructive) {
                    Task {
                        await model.removeReferencesFromCurrentScene(
                            requirementIDs: bundle.orderedReferences.map(\.requirementID)
                        )
                    }
                }
                .buttonStyle(.bordered)
                .help("Remove all image references in this bundle from this scene. You can undo this change.")
                .accessibilityLabel("Remove \(bundle.entityName) references from scene")
                .accessibilityIdentifier(
                    "sceneReferences.removeFromScene.\(bundle.entityID.uuidString.prefix(8))"
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .campPanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "sceneReferences.bundle.\(bundle.entityID.uuidString.prefix(8))"
        )
        .sheet(item: $outfitReference) { reference in
            ReferenceImageCreationSheet(
                model: model,
                reference: reference,
                mode: .edit,
                editFocus: .outfit
            )
        }
    }
}

private struct ScenePromptCardView: View {
    let model: ProjectWindowModel
    let position: Int
    let detail: ScenePromptSetDetail.Card
    let canDelete: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        @Bindable var editor = model.inlinePromptEditor(for: detail.card)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Prompt \(position)", text: $editor.fields.title)
                    .font(.headline)
                    .textFieldStyle(.plain)
                    .tracksTextEditing(model)
                    .accessibilityLabel("Prompt card title")
                    .accessibilityIdentifier("generation.package.cardTitle.\(position)")
                Text("\(position)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Move Up", action: onMoveUp).disabled(!canMoveUp)
                    Button("Move Down", action: onMoveDown).disabled(!canMoveDown)
                    Divider()
                    Button("Delete…", role: .destructive, action: onDelete)
                        .disabled(!canDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("generation.package.cardMenu.\(position)")
            }

            PromptCardReferenceStrip(model: model, card: detail)

            TextEditor(text: $editor.fields.body)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .frame(minHeight: 280)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                .tracksTextEditing(model)
                .accessibilityIdentifier("generation.package.promptBody.\(position)")
                .accessibilityLabel("Prompt \(position), saves automatically")

            DisclosureGroup("Prompt Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Guidance (optional)", text: $editor.fields.guidance, axis: .vertical)
                        .accessibilityLabel("Prompt guidance")
                        .accessibilityIdentifier("generation.package.guidance.\(position)")
                    HStack {
                        TextField("Duration s", text: $editor.fields.duration)
                            .accessibilityLabel("Duration in seconds")
                            .accessibilityIdentifier("generation.package.duration.\(position)")
                        TextField("Aspect ratio", text: $editor.fields.aspectRatio)
                            .accessibilityLabel("Aspect ratio")
                            .accessibilityIdentifier("generation.package.aspectRatio.\(position)")
                        TextField("Resolution", text: $editor.fields.resolution)
                            .accessibilityLabel("Resolution")
                            .accessibilityIdentifier("generation.package.resolution.\(position)")
                    }
                }
                .textFieldStyle(.roundedBorder)
                .tracksTextEditing(model)
                .padding(.top, 6)
            }
            .font(.caption)

            if let error = editor.errorMessage {
                Label("Changes not saved: \(error)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("generation.package.promptSaveError.\(position)")
            }

            HStack(spacing: 8) {
                Button("Copy Prompt") { editor.copyPrompt() }
                    .accessibilityIdentifier("generation.package.copyPrompt.\(position)")
                Button("Reveal Images") {
                    Task { await model.revealScenePromptCardReferences(cardID: detail.card.id) }
                }
                .disabled(detail.references.isEmpty)
                .accessibilityIdentifier("generation.package.revealReferences.\(position)")
                Spacer()
                Text(editor.isSaving ? "Saving…" : (editor.hasChanges ? "Unsaved changes" : "Saved automatically"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("generation.package.promptSaveStatus.\(position)")
            }
        }
        .onAppear { editor.synchronize(detail.card) }
        .onChange(of: detail.card) { _, card in editor.synchronize(card) }
        .onDisappear { Task { await editor.flush() } }
        .padding(12)
        .campPanel()
        .accessibilityIdentifier("generation.package.card.\(position)")
    }
}

private struct PromptCardReferenceStrip: View {
    let model: ProjectWindowModel
    let card: ScenePromptSetDetail.Card
    @State private var materialization: ScenePromptCardMaterialization?

    var body: some View {
        let mapped = card.references.sorted { $0.position < $1.position }
        if mapped.isEmpty == false {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(mapped) { reference in
                        PromptCardReferenceThumbnail(
                            model: model,
                            reference: reference,
                            fileURL: materialization?.references.first {
                                $0.position == reference.position
                            }?.fileURL
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("generation.package.cardReferences")
            .task(id: card.card.id) {
                materialization = await model.prepareScenePromptCardReferences(
                    cardID: card.card.id
                )
            }
        }
    }
}

private struct SceneReferenceCard: View {
    let model: ProjectWindowModel
    let reference: ScenePlannedReference
    let localNumber: Int?
    let showsEntityName: Bool
    let isGenerating: Bool
    let generationMessage: String
    let generationError: String?
    let onOpen: () -> Void
    @State private var image: NSImage?
    @State private var fileURL: URL?
    @State private var damage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if isGenerating {
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.large)
                        Text(generationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "sceneReferences.generating.\(reference.requirementID.uuidString.prefix(8))"
                    )
                } else if reference.isSatisfied {
                    Button(action: onOpen) {
                        GeometryReader { geometry in
                            ZStack {
                                if let image {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(
                                            width: geometry.size.width,
                                            height: geometry.size.height
                                        )
                                        .clipped()
                                } else {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "sceneReferences.currentImage.\(reference.requirementID.uuidString.prefix(8))"
                    )
                    .accessibilityLabel(
                        "\(reference.entityName), \(reference.requirementName), image ready"
                    )
                } else {
                    Button(action: onOpen) {
                        ZStack {
                            Image(systemName: "photo.badge.plus")
                                .font(.largeTitle)
                                .foregroundStyle(Color.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sceneReferences.addImage.\(reference.requirementID.uuidString.prefix(8))")
                    .accessibilityLabel(
                        "Open \(reference.entityName), \(reference.requirementName), image missing"
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .clipped()
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: CampAppearance.radius))
            .clipShape(RoundedRectangle(cornerRadius: CampAppearance.radius))

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    if let localNumber {
                        Text("@Image \(localNumber)")
                            .font(.caption.weight(.semibold))
                    }
                    if showsEntityName {
                        Text(reference.entityName).font(.subheadline.weight(.medium)).lineLimit(1)
                    }
                    Text(reference.requirementName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if reference.isStale {
                        Label("Needs Sync", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)

            if reference.isSatisfied == false, isGenerating == false {
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await model.generateMissingReference(
                                requirementID: reference.requirementID
                            )
                        }
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                    .buttonStyle(CampPrimaryButtonStyle())
                    .disabled(quickGenerateDisabledReason != nil)
                    .help(quickGenerateDisabledReason ?? "Create the prompt and generate this image")
                    .accessibilityIdentifier(
                        "sceneReferences.generate.\(reference.requirementID.uuidString.prefix(8))"
                    )
                }
            }
            if let generationError {
                Label(generationError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier(
                        "sceneReferences.generationError.\(reference.requirementID.uuidString.prefix(8))"
                    )
            }
            if let damage {
                Text(damage).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(12)
        .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.primary.opacity(0.025)
                Button(action: onOpen) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: CampAppearance.radius))
        }
        .overlay(RoundedRectangle(cornerRadius: CampAppearance.radius).stroke(Color.primary.opacity(0.10)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sceneReferences.card.\(reference.requirementID.uuidString.prefix(8))")
        .task(id: reference.approvedVersion?.relativePath) {
            guard let approved = reference.approvedVersion,
                  let version = await model.workspaceAssetVersion(
                    requirementID: reference.requirementID,
                    versionID: approved.versionID
                  )
            else {
                fileURL = nil
                image = nil
                damage = nil
                return
            }
            fileURL = await model.workspaceVersionURL(version)
            let containment = model.mediaContainment
            let loaded = await Task.detached(priority: .utility) {
                AssetPreviewLoader.load(
                    containment: containment, version: version, size: .card
                )
            }.value
            damage = loaded.damage
            image = loaded.thumbnailPNG.flatMap(NSImage.init(data:))
        }
        .onDrag {
            guard let fileURL, let provider = NSItemProvider(contentsOf: fileURL) else {
                return NSItemProvider()
            }
            return provider
        }
    }

    private var previewAspectRatio: CGFloat {
        reference.templateCode == "full_body" ? 16.0 / 9.0 : 4.0 / 3.0
    }

    private var quickGenerateDisabledReason: String? {
        if model.referenceImageJobState(for: reference.requirementID)?
            .preventsDuplicate == true {
            return "This image is already queued, generating, or awaiting selection."
        }
        return model.workspaceReferenceCreationRefusals[reference.requirementID]
    }
}

private struct PromptCardReferenceThumbnail: View {
    let model: ProjectWindowModel
    let reference: ScenePromptCardReference
    let fileURL: URL?
    @State private var image: NSImage?
    @State private var damage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: damage == nil ? "photo" : "exclamationmark.triangle")
                        .foregroundStyle(damage == nil ? Color.secondary : Color.orange)
                }
            }
            .frame(width: 112, height: 82)
            .clipped()
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: CampAppearance.radius))
            .clipShape(RoundedRectangle(cornerRadius: CampAppearance.radius))
            Text("@Image \(reference.position)").font(.caption.weight(.semibold))
            Text(reference.displayName).font(.caption2).lineLimit(2)
            if let damage {
                Text(damage).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .frame(width: 112, alignment: .leading)
        .task(id: reference.id) {
            let containment = model.mediaContainment
            let loaded = await Task.detached(priority: .utility) {
                AssetPreviewLoader.load(containment: containment, reference: reference)
            }.value
            damage = loaded.damage
            image = loaded.thumbnailPNG.flatMap(NSImage.init(data:))
        }
        .onDrag {
            guard let fileURL, let provider = NSItemProvider(contentsOf: fileURL) else {
                return NSItemProvider()
            }
            return provider
        }
    }
}

private struct ScenePromptDirectionSheet: View {
    let model: ProjectWindowModel
    let sceneID: UUID
    let regeneratesPrompt: Bool
    let onDirectionSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false

    init(
        model: ProjectWindowModel,
        sceneID: UUID,
        regeneratesPrompt: Bool,
        onDirectionSaved: @escaping () -> Void
    ) {
        self.model = model
        self.sceneID = sceneID
        self.regeneratesPrompt = regeneratesPrompt
        self.onDirectionSaved = onDirectionSaved
        _text = State(initialValue: "")
    }

    private var actionTitle: String {
        regeneratesPrompt ? "Add Direction and Regenerate" : "Add Direction and Generate"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Direction")
                .font(CampAppearance.title(20))
            Text(
                "Describe the timing, performance, blocking, eyelines, or camera movement you want. Adding direction starts prompt generation after any required disclosure. This replaces any unsent direction and clears only after successful generation; failed or cancelled runs keep it for retry."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            TextField(
                "For example: Start looking at the screen, then turn to address the agents with natural gestures while the camera makes a slight orbit.",
                text: $text,
                axis: .vertical
            )
            .lineLimit(6 ... 12)
            .textFieldStyle(.roundedBorder)
            .disabled(isSaving)
            .accessibilityIdentifier("generation.package.creativeDirectionField")

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
                Button(actionTitle) {
                    isSaving = true
                    Task {
                        if await model.setScenePromptDirection(sceneID: sceneID, text: text) {
                            onDirectionSaved()
                            dismiss()
                        } else {
                            isSaving = false
                        }
                    }
                }
                .buttonStyle(CampPrimaryButtonStyle())
                .disabled(
                    isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.sceneGenerateDisabledReason != nil
                        || model.selectedPackageSceneID != sceneID
                )
                .help(model.sceneGenerateDisabledReason ?? "")
                .accessibilityIdentifier("generation.package.saveCreativeDirection")
                .accessibilityLabel(actionTitle)
            }
        }
        .padding(20)
        .frame(width: 620)
        .interactiveDismissDisabled(isSaving)
    }
}

/// §7.1's hand-authoring sheet (§14.5 at scene scale): body plus the profile-validated
/// settings triple. Refusals surface FilmCore's copy verbatim.
struct WriteScenePromptSheet: View {
    let model: ProjectWindowModel
    let sceneID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var bodyText = ""
    @State private var guidance = ""
    @State private var durationText = ""
    @State private var aspectRatio = ""
    @State private var resolution = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Write Scene Prompt").font(.headline)
            TextField("Prompt body", text: $bodyText, axis: .vertical)
                .lineLimit(6 ... 14)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("writeScenePromptBodyField")
            TextField("Guidance (optional)", text: $guidance)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("writeScenePromptGuidanceField")
            HStack {
                TextField("Duration s (optional)", text: $durationText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("writeScenePromptDurationField")
                TextField("Aspect ratio (optional)", text: $aspectRatio)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("writeScenePromptAspectField")
                TextField("Resolution (optional)", text: $resolution)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("writeScenePromptResolutionField")
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Write Prompt") {
                    let body = bodyText
                    let notes = guidance
                    let seconds = Int(durationText.trimmingCharacters(in: .whitespaces))
                    let ratio = aspectRatio
                    let res = resolution
                    Task {
                        await model.createScenePrompt(
                            sceneID: sceneID, body: body, guidance: notes,
                            durationSeconds: seconds, aspectRatio: ratio, resolution: res
                        )
                        dismiss()
                    }
                }
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("commitWriteScenePromptButton")
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private struct PromptCardEditorPresentation: Identifiable {
    let id = UUID()
    let setID: UUID
}

private struct ScenePromptCardEditorSheet: View {
    let model: ProjectWindowModel
    let presentation: PromptCardEditorPresentation
    let onDone: () -> Void
    @State private var title = ""
    @State private var bodyText = ""
    @State private var guidance = ""
    @State private var durationText = ""
    @State private var aspectRatio = ""
    @State private var resolution = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Prompt Card").font(.headline)
            TextField("Card title", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("scenePromptCard.title")
            TextField("Prompt body", text: $bodyText, axis: .vertical)
                .lineLimit(10 ... 18)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("scenePromptCard.body")
            TextField("Guidance (optional)", text: $guidance)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("scenePromptCard.guidance")
            HStack {
                TextField("Duration s", text: $durationText)
                    .textFieldStyle(.roundedBorder)
                TextField("Aspect ratio", text: $aspectRatio)
                    .textFieldStyle(.roundedBorder)
                TextField("Resolution", text: $resolution)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save") {
                    let draft = ScenePromptCardDraft(
                        title: title,
                        body: bodyText,
                        guidance: guidance,
                        durationSeconds: Int(durationText.trimmingCharacters(in: .whitespaces)),
                        aspectRatio: aspectRatio,
                        resolution: resolution
                    )
                    Task {
                        await model.addScenePromptCard(setID: presentation.setID, draft: draft)
                        onDone()
                    }
                }
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("scenePromptCard.save")
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

/// §14.6's minimal chooser: import a folder (copied whole into `skills/`, bundle-relative
/// paths only) or select among imports; the bundled default is the `nil` selection.
struct SkillChooserSheet: View {
    @Bindable var model: ProjectWindowModel
    @Environment(\.dismiss) private var dismiss
    @State private var entryPath = "SKILL.md"
    @State private var routingPath = ""
    @State private var folderURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Skill").font(.headline)
            Text(
                "Importing copies a skill tree into this project and selects it. Every stored path stays inside the bundle."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let folder = folderURL {
                TextField("Entry file (descriptor-relative)", text: $entryPath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("skillEntryPathField")
                TextField("Routing file (optional)", text: $routingPath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("skillRoutingPathField")
                Text("Importing “\(folder.lastPathComponent)”.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Import and Select") {
                    Task {
                        await model.importSceneSkill(
                            from: folder, displayName: nil,
                            entryRelativePath: entryPath,
                            routingRelativePath: routingPath
                        )
                        dismiss()
                    }
                }
                .disabled(entryPath.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("commitSkillImportButton")
            } else {
                Button("Choose Folder…") {
                    Task { folderURL = await model.skillChooser() }
                }
                .accessibilityIdentifier("skillChooseFolderButton")
                Text("Pick the skill's folder first; then name its entry file.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Text("Imported Skills").font(.subheadline.weight(.medium))
            if model.importedSkillRows.isEmpty {
                Text("No imported skills yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("skillListEmptyText")
            }
            ForEach(model.importedSkillRows) { skill in
                HStack {
                    Text(skill.displayName).font(.caption)
                    Spacer()
                    if model.selectedSkillRow?.id == skill.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Selected")
                    } else {
                        Button("Select") {
                            Task {
                                await model.selectSceneSkill(skill.id)
                                await model.loadImportedSkills()
                            }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("selectSkillButton")
                    }
                }
                .accessibilityIdentifier("importedSkillRow")
            }
            Button("Use Bundled Default") {
                Task {
                    await model.selectSceneSkill(nil)
                    await model.loadImportedSkills()
                }
            }
            .disabled(model.selectedSkillRow == nil)
            .accessibilityIdentifier("useBundledDefaultSkillButton")

            Spacer()
            HStack { Spacer(); Button("Done") { dismiss() } }
        }
        .padding(20)
        .frame(width: 460, height: 480)
        .task {
            await model.loadImportedSkills()
        }
    }
}
