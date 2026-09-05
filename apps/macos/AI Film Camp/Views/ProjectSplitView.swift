import FilmCore
import SwiftUI

/// Plan 023's scene-first shell: one searchable scene rail and one scene workspace.
/// Project preparation lives in the toolbar rather than competing with scenes as primary
/// navigation.
///
/// It is also the **one** host for this plan's sheets. They are raised through
/// `ProjectWindowModel.presentedSheet` rather than from the view that offers them, because
/// the Entity menu (`EntityCommands`) has a window model and no view to reach into.
struct ProjectSplitView: View {
    let coordinator: AppCoordinator
    @Bindable var model: ProjectWindowModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var projectSettingsPresented = false
    @State private var scenePromptRevealToken = 0

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                detail
            }
            .task { await model.selectFirstWorkspaceSceneIfNeeded() }
        .sheet(isPresented: $projectSettingsPresented) {
            ProjectGenerationSettingsSheet(model: model)
        }
        // Presented on every successful import; Analyze Now enters analysis's single
        // disclosure/request-count confirmation, while Not Now reveals the first scene.
        .sheet(item: $model.presentedImportSummary) { presentation in
            ImportSummarySheet(summary: presentation.summary, onAnalyze: {
                Task { await model.analyzeImportedScreenplay() }
            }, onDismiss: {
                Task { await model.dismissImportSummary() }
            })
        }
        // Shown when this session's open migrated a v1 bundle (§4.2).
        .sheet(item: $model.presentedUpgradeSummary) { presentation in
            UpgradeSummarySheet(summary: presentation.summary) {
                model.presentedUpgradeSummary = nil
            }
        }
        .sheet(item: $model.analysisWorkflow) { _ in
            AnalysisWorkflowSheet(model: model)
        }
        // §9's first-run acknowledgement, shown only when this project has acknowledged
        // none — a bare import + Build + inference reaches it without extraction.
        .sheet(item: $model.pendingManifestDisclosure) { _ in
            ManifestDisclosureSheet {
                Task { await model.continueAfterManifestDisclosure() }
            } cancelAction: {
                model.cancelPreparedManifestRun()
            }
        }
        // §9's compact confirm sheet, before every manifest run.
        .sheet(item: $model.pendingManifestConfirmation) { _ in
            ManifestConfirmSheet {
                Task { await model.startPreparedManifestRun() }
            } cancelAction: {
                model.cancelPreparedManifestRun()
            }
        }
        .sheet(item: $model.presentedManifestReport) { presentation in
            ManifestReportSheet(report: presentation.report) {
                model.presentedManifestReport = nil
            }
        }
        // PHASE3_DESIGN §9 (Plan 016): the prompt run's §8.7 regenerate confirm, first-run
        // acknowledgement, compact per-run confirm, and completion report.
        .sheet(item: rootPromptRegenerateBinding) { _ in
            PromptRegenerateConfirmSheet {
                Task { await model.continueAfterRegenerateConfirm() }
            } cancelAction: {
                cancelRootPromptRun()
            }
        }
        .sheet(item: rootPromptDisclosureBinding) { _ in
            PromptDisclosureSheet {
                Task { await model.continueAfterPromptDisclosure() }
            } cancelAction: {
                cancelRootPromptRun()
            }
        }
        .sheet(item: rootPromptConfirmationBinding) { _ in
            PromptConfirmSheet {
                Task { await model.startPreparedPromptRun() }
            } cancelAction: {
                cancelRootPromptRun()
            }
        }
        .sheet(item: rootPromptReportBinding) { presentation in
            PromptReportSheet(report: presentation.report) {
                model.presentedPromptReport = nil
            }
        }
        // PHASE5_DESIGN §9 (Plan 021): one-time disclosure and completion report.
        .sheet(item: $model.pendingScenePromptDisclosure) { _ in
            ScenePromptDisclosureSheet {
                Task { await model.continueAfterScenePromptDisclosure() }
            } cancelAction: {
                model.cancelPreparedScenePromptRun()
            }
        }
        .sheet(item: $model.presentedScenePromptReport, onDismiss: {
            scenePromptRevealToken += 1
        }) { presentation in
            ScenePromptReportSheet(
                report: presentation.report,
                summary: presentation.summary
            ) {
                model.presentedScenePromptReport = nil
            }
        }
        .sheet(item: $model.presentedRevertReport) { presentation in
            OperationReportSheet(
                title: "Run reverted",
                message: "Reverted \(presentation.report.reverted) changes; \(presentation.report.skipped) skipped because you edited them."
            ) { model.presentedRevertReport = nil }
        }
        .sheet(item: $model.presentedCacheSummary) { presentation in
            OperationReportSheet(
                title: "Job cache cleared",
                message: "Removed \(presentation.summary.filesRemoved) files and freed \(ByteCountFormatter.string(fromByteCount: presentation.summary.bytesFreed, countStyle: .file)). Results and logs were kept."
            ) { model.presentedCacheSummary = nil }
        }
        // §3.8's export report: paths and sizes only — exports are derived artifacts,
        // never read back into the model.
        .sheet(item: $model.presentedExportSummary) { presentation in
            GenerationExportSheet(exports: presentation.exports) {
                model.presentedExportSummary = nil
            }
        }
        // §4.1's Clear Orphaned Media reports like Clear Job Cache, in its own words: it
        // sweeps files no version row references and keeps every referenced image.
        .sheet(item: $model.presentedOrphanSummary) { presentation in
            OperationReportSheet(
                title: "Orphaned media cleared",
                message: "Removed \(presentation.summary.filesRemoved) unreferenced files and freed \(ByteCountFormatter.string(fromByteCount: presentation.summary.bytesFreed, countStyle: .file)). Images your versions reference were kept."
            ) { model.presentedOrphanSummary = nil }
        }
        // Plan 005's editing sheets, all of them, in one place.
        .sheet(item: $model.presentedSheet) { sheet in
            editingSheet(sheet)
        }
        // §5.5's Replace confirmation: allowed only while the project holds nothing but
        // parser facts and unreviewed proposals, and non-invertible either way.
        .confirmationDialog(
            "Replace the screenplay in this project?",
            isPresented: replaceConfirmationBinding,
            titleVisibility: .visible,
            presenting: model.pendingReplace
        ) { pending in
            Button("Replace", role: .destructive) {
                Task { await model.performReplace(pending) }
            }
            .accessibilityIdentifier("confirmReplaceButton")
            Button("Cancel", role: .cancel) { model.cancelPendingReplace() }
        } message: { _ in
            Text(
                "Replacing wipes this project's scenes and entities and imports the new screenplay. This cannot be undone."
            )
        }
            .alert(item: $model.error) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }

            if let lightbox = model.referenceImageLightbox {
                SceneReferenceLightbox(model: model, presentation: lightbox)
                    .zIndex(10)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.referenceImageLightbox?.id)
    }

    /// Prompt-run presentations move to ReferenceImageCreationSheet while that workflow
    /// is open. Only one host observes each item, avoiding competing/nested sheet races.
    private var rootPromptRegenerateBinding: Binding<PromptRegenerateConfirmPresentation?> {
        promptBinding(\.pendingPromptRegenerateConfirm)
    }

    private var rootPromptDisclosureBinding: Binding<PromptDisclosurePresentation?> {
        promptBinding(\.pendingPromptDisclosure)
    }

    private var rootPromptConfirmationBinding: Binding<PromptConfirmationPresentation?> {
        promptBinding(\.pendingPromptConfirmation)
    }

    private var rootPromptReportBinding: Binding<PromptReportPresentation?> {
        promptBinding(\.presentedPromptReport)
    }

    private func promptBinding<Value>(
        _ keyPath: ReferenceWritableKeyPath<ProjectWindowModel, Value?>
    ) -> Binding<Value?> {
        Binding(
            get: {
                guard model.referenceCreationRequirementID == nil
                    || model.inPlaceReferenceGenerationRequirementID != nil
                else { return nil }
                return model[keyPath: keyPath]
            },
            set: { model[keyPath: keyPath] = $0 }
        )
    }

    private func cancelRootPromptRun() {
        if model.inPlaceReferenceGenerationRequirementID != nil {
            Task { await model.cancelInPlaceReferenceGeneration() }
        } else {
            model.cancelPreparedPromptRun()
        }
    }

    /// The sheet the model asked for. Each case reads whatever the editor needs off the
    /// model, so a stale id — a row deleted behind the sheet — closes it rather than
    /// showing an editor over nothing.
    @ViewBuilder
    private func editingSheet(_ sheet: ProjectSheet) -> some View {
        switch sheet {
        case .addScenes:
            AddScenesSheet(model: model)
        case .merge:
            MergeSheet(model: model)
        case .split:
            if let detail = model.entityDetail {
                SplitSheet(model: model, detail: detail)
            } else {
                missingSubjectSheet
            }
        case .moveInto:
            MoveIntoSheet(model: model)
        case .journal:
            EditJournalView(model: model)
        case let .addState(entityID):
            StateEditorSheet(model: model, entityID: entityID, existing: nil)
        case let .editState(state):
            StateEditorSheet(model: model, entityID: state.entityID, existing: state)
        case .addEvent:
            EventEditorSheet(model: model, existing: nil)
        case let .editEvent(event):
            EventEditorSheet(model: model, existing: event)
        case let .addRelationship(entityID):
            RelationshipEditorSheet(model: model, fromEntityID: entityID)
        case .combineRequirements:
            CombineRequirementsSheet(model: model)
        case let .sceneEntities(sceneID):
            if let detail = model.sceneDetail, detail.scene.id == sceneID {
                SceneEntitiesEditor(model: model, detail: detail)
            } else {
                missingSubjectSheet
            }
        }
    }

    private var missingSubjectSheet: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "That row is no longer in this project.",
                systemImage: "exclamationmark.triangle"
            )
            Button("Done") { model.presentedSheet = nil }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("missingSubjectDoneButton")
                .accessibilityLabel("Done")
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 220)
    }

    private var deletionTitle: String {
        let count = model.pendingEntityDeletion?.ids.count ?? 0
        return count == 1 ? "Delete this entity?" : "Delete \(count) entities?"
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.pendingEntityDeletion != nil },
            set: { if !$0 { model.cancelPendingDeletion() } }
        )
    }

    private var replaceConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.pendingReplace != nil },
            set: { if !$0 { model.cancelPendingReplace() } }
        )
    }

    // MARK: - Scene rail

    private var sidebar: some View {
        SceneWorkspaceRail(model: model)
            .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
    }

    // MARK: - Scene workspace

    @ViewBuilder
    private var detail: some View {
        ScenePackageDetailView(model: model, promptRevealToken: scenePromptRevealToken)
            .toolbar { toolbarContent }
            // §3.11: Delete confirms. §6 then routes each row — a `parser` or `ai` row
            // is tombstoned rather than hard-deleted, which is what "Reject/Delete"
            // names.
            //
            // It hangs here rather than beside §5.5's Replace dialog on purpose: two
            // `confirmationDialog`s on one view compete for the same presentation slot,
            // and the second one silently never appears.
            .confirmationDialog(
                deletionTitle,
                isPresented: deletionConfirmationBinding,
                titleVisibility: .visible,
                presenting: model.pendingEntityDeletion
            ) { pending in
                Button("Delete", role: .destructive) {
                    Task { await model.performDeletion(pending) }
                }
                .accessibilityIdentifier("confirmDeleteEntityButton")
                Button("Cancel", role: .cancel) { model.cancelPendingDeletion() }
            } message: { _ in
                Text(
                    "Rows the parser or a run created are kept as rejected so they cannot come back on the next import; rows you added are removed outright."
                )
            }
    }

    /// §7.3's two destructive media gestures, behind one dialog.
    ///
    /// It hangs on `content` rather than beside the entity-delete dialog for the reason
    /// that one documents: two `confirmationDialog`s on **one** view compete for the same
    /// presentation slot and the second silently never appears. `content` is a different
    /// view, so this one presents.
    @ViewBuilder
    private var contentWithMediaConfirmation: some View {
        content
            .confirmationDialog(
                model.pendingMediaDeletion?.title ?? "Delete this media?",
                isPresented: mediaDeletionBinding,
                titleVisibility: .visible,
                presenting: model.pendingMediaDeletion
            ) { pending in
                Button("Delete", role: .destructive) {
                    Task { await model.performMediaDeletion(pending) }
                }
                .accessibilityIdentifier("confirmDeleteMediaButton")
                Button("Cancel", role: .cancel) { model.cancelPendingMediaDeletion() }
            } message: { pending in
                Text(pending.message)
            }
    }

    private var mediaDeletionBinding: Binding<Bool> {
        Binding(
            get: { model.pendingMediaDeletion != nil },
            set: { if !$0 { model.cancelPendingMediaDeletion() } }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch model.section {
        case .dashboard:
            // PHASE4_DESIGN §5.3: the readiness rollup, blockers before totals. The
            // Suggestions panel is Plan 018's and does not render here.
            DashboardView(model: model)
        case .scenes:
            SceneTableView(model: model)
        case .continuity:
            ContinuityListView(model: model)
        case .jobs:
            RunsListView(model: model) { url in coordinator.reveal(url) }
        case .manifest:
            // PHASE3_DESIGN §5.1's in-content master–detail (Plan 015): the requirement
            // list narrows to a master pane; the workshop renders beside it for the
            // selected requirement.
            HStack(spacing: 0) {
                ManifestListView(model: model)
                    .frame(width: 300)
                Divider()
                AssetWorkshopView(model: model)
            }
        case .generation:
            // PHASE5_DESIGN §5.1's in-content master–detail (Plan 020): the scene list
            // narrows to a master pane; the package view renders beside it. §14.7's
            // stale-export confirm hangs on the detail view — its surface owns Export.
            HStack(spacing: 0) {
                GenerationListView(model: model)
                    .frame(width: 340)
                Divider()
                ScenePackageDetailView(model: model)
            }
        case .characters, .locations, .props, .vehicles, .creatures, .objects:
            EntityListView(model: model, section: model.section)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        switch model.section {
        case .scenes:
            SceneDetailView(model: model)
        case .characters, .locations, .props, .vehicles, .creatures, .objects:
            EntityInspectorView(model: model, section: model.section)
        case .manifest:
            RequirementInspectorView(model: model)
        case .continuity, .jobs, .dashboard:
            // Continuity is edited in place — every row carries its own Edit and remove
            // controls — so the inspector has nothing to add. The run card is Plan 007's.
            // The dashboard is a read with its panels in the content column (§5.1).
            ContentUnavailableView("No Selection", systemImage: model.section.systemImage)
        case .generation:
            // PHASE5_DESIGN §5.1: the package view is the detail; the inspector adds
            // nothing (the same posture as the Manifest section's workshop pane).
            ContentUnavailableView("No Selection", systemImage: model.section.systemImage)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Before the first run there is no status to inspect. Showing the status control
        // then made it claim "Analyze Screenplay" while only opening an empty popover,
        // beside a second icon-only button that performed the real action.
        if model.hasActiveWorkspaceRun {
            ToolbarItem {
                WorkspaceRunStatusToolbarItem(model: model)
            }
        } else if !model.runs.isEmpty {
            ToolbarItem {
                RunStatusToolbarItem(model: model)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(model.script == nil ? "Import Screenplay…" : "Replace Screenplay…") {
                    Task { await importScreenplay() }
                }
                .disabled(model.isImporting)
                .accessibilityIdentifier("projectActions.importScreenplay")

                Divider()

                Button(model.analyzeButtonTitle) {
                    Task { await model.prepareExtraction() }
                }
                .disabled(!model.canAnalyze)
                .help(model.analyzeClosedByManifestReason ?? model.analyzeButtonTitle)
                .accessibilityIdentifier("projectActions.analyzeScreenplay")

                Button("Build Reference List") {
                    Task { await model.buildAssetManifest() }
                }
                .disabled(!model.canBuildAssetManifest)
                .accessibilityIdentifier("projectActions.buildReferences")

                Button("AI Reference Inference…") {
                    Task { await model.prepareManifestRun() }
                }
                .disabled(!model.canInferManifest)
                .help(model.manifestRunRefusalMessage ?? "")
                .accessibilityIdentifier("projectActions.inferReferences")

                Divider()

                Button("Project Settings…") { projectSettingsPresented = true }
                    .accessibilityIdentifier("projectActions.settings")
            } label: {
                Label("Project Actions", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("projectActionsMenu")
            .accessibilityLabel("Project Actions")
        }
    }

    /// §5.3's toolbar grains (Plan 020 contract A): Export All Generation Ready, and
    /// Export Sequence — one item per sequence, each enabled only when it holds ≥ 1
    /// Generation Ready scene under the active profile.
    @ToolbarContentBuilder
    private var generationToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.exportAllGenerationReady() }
            } label: {
                Label("Export All Generation Ready", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(!model.canExportAllReady)
            .accessibilityIdentifier("generation.exportAllReady")
            .accessibilityLabel("Export All Generation Ready")
        }
        if !model.sequences.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Menu("Export Sequence") {
                    ForEach(model.sequences) { sequence in
                        Button(sequence.title.isEmpty ? "Sequence \(sequence.ordinal)" : sequence.title) {
                            Task { await model.exportSequence(sequenceID: sequence.id) }
                        }
                        .disabled(!model.sequenceHasReadyScenes(sequence.id))
                        .accessibilityIdentifier("generation.exportSequence.\(sequence.ordinal)")
                    }
                }
                .disabled(!model.canExportAllReady)
                .accessibilityIdentifier("generation.exportSequenceMenu")
                .accessibilityLabel("Export Sequence")
            }
        }
    }

    /// One of contract D's three entry points, and the same code path as ⇧⌘I.
    private func importScreenplay() async {
        guard let url = await coordinator.services.panels.screenplayToImport() else { return }
        await model.importScreenplay(from: url)
    }

    private var sectionBinding: Binding<ProjectSection?> {
        Binding(
            get: { model.section },
            set: { if let new = $0 { model.section = new } }
        )
    }
}

private struct OperationReportSheet: View {
    let title: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            Text(message)
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("exportReportDoneButton")
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

/// §3.8's export report (Plan 020): what was written and where, inside the bundle.
private struct GenerationExportSheet: View {
    let exports: [ScenePackageExport]
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scene Packages Exported").font(.title2.bold())
            if exports.isEmpty {
                Text("Nothing was exported.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(exports.enumerated()), id: \.element.sceneID) { _, export in
                VStack(alignment: .leading, spacing: 2) {
                    Text(export.relativeDirectory)
                        .font(.caption.weight(.medium))
                        .textSelection(.enabled)
                    Text("\(export.files.count) files · \(ByteCountFormatter.string(fromByteCount: export.byteCount, countStyle: .file))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("exportReportRow")
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("exportReportDoneButton")
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

/// `.searchable` is scoped to the section (§3.11) — present for Scenes and the six entity
/// sections, absent for Continuity and Jobs.
private struct SectionSearchModifier: ViewModifier {
    @Bindable var model: ProjectWindowModel

    func body(content: Content) -> some View {
        if model.section.supportsSearch {
            content.searchable(
                text: searchBinding,
                placement: .toolbar,
                prompt: "Search \(model.section.title)"
            )
        } else {
            content
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { model.searchText(in: model.section) },
            set: { model.setSearchText($0, in: model.section) }
        )
    }
}
