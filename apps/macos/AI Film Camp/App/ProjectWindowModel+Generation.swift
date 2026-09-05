import AppKit
import FilmCore
import Foundation

/// PHASE5_DESIGN §5's Generation state on the window model (Plan 020).
///
/// The list figures and the Dashboard's Generation Packages block read **one**
/// `scenePackages()` load per refresh beat (§3.3's consistency rule; the plan's STOP 4),
/// so both surfaces can never disagree. Every action routes through FilmCore's §7.1
/// operations or the `ProjectSession+Export` doors; refusals surface FilmCore's strings
/// verbatim through `runEdit`. Generate/Regenerate live in `+ScenePromptRun.swift`
/// (Plan 021) beside this file's reads.
extension ProjectWindowModel {

    // MARK: - The one read

    /// §7.5's package summaries for every counted scene, read on the standard refresh
    /// beat beside `_readinessSnapshot` — the Dashboard block and this section share it.
    var scenePackages: [ScenePackageSummary] { _scenePackages }

    /// Per scene id, for rows and enablement.
    func scenePackage(forSceneID id: UUID) -> ScenePackageSummary? {
        _scenePackages.first { $0.sceneID == id }
    }

    /// The active profile's display name, from the first summary — every row carries it.
    var generationProfileName: String {
        if let profile = TargetProfileCatalog.profile(id: _scenePackages.first?.activeProfileID ?? "") {
            return profile.displayName
        }
        return TargetProfileCatalog.seedance2_5.displayName
    }

    /// The three counts under P, byte-identical to what the Dashboard block renders.
    var generationCounts: (ready: Int, stale: Int, needsPreparation: Int) {
        (
            _scenePackages.filter { $0.packageState == .generationReady }.count,
            _scenePackages.filter { $0.packageState == .stale }.count,
            _scenePackages.filter { $0.packageState == .needsPreparation }.count
        )
    }

    /// §5.3's counts line, naming the active profile:
    /// "Seedance 2.5 — N generation ready · M stale · K needs preparation".
    var generationCountsLine: String {
        let counts = generationCounts
        return "\(generationProfileName) — \(counts.ready) generation ready · "
            + "\(counts.stale) stale · \(counts.needsPreparation) needs preparation"
    }

    /// §5.4's deep link target from the Dashboard's Generation Packages block: navigate to
    /// `.generation` with the package-state filter preset — the readiness drill-down's
    /// shape at package scale.
    func showGenerationFiltered(by state: ScenePackageState) async {
        setGenerationFilter(GenerationPackageFilter(matching: state))
        section = .scenes
        await refresh()
    }

    // MARK: - The filter

    /// The list's package-state filter — a view-model filter over the derived rows, in
    /// the readiness-filter shape. No store query stands behind it (§3.1).
    var generationFilter: GenerationPackageFilter { _generationFilter }

    func setGenerationFilter(_ filter: GenerationPackageFilter) {
        guard filter != _generationFilter else { return }
        _generationFilter = filter
    }

    /// The filtered rows in ordinal order. Excluded scenes are not package rows at all
    /// (§3.3); the list renders them from the readiness snapshot separately.
    var filteredScenePackages: [ScenePackageSummary] {
        _scenePackages.filter { _generationFilter.admits($0) }
    }

    // MARK: - The subject

    /// The scene whose package the detail pane renders.
    var selectedPackageSceneID: UUID? {
        singleSelection(in: .generation)
    }

    /// §7.5's detail payload for the selected scene, loaded on the detail beat.
    var scenePackageDetail: ScenePackageDetail? { _scenePackageDetail }

    func loadScenePackageDetail() async {
        guard !isClosed, let id = selectedPackageSceneID else {
            _scenePackageDetail = nil
            workspaceReferenceArchives = []
            workspaceReferenceCreationRefusals = [:]
            closeReferenceDetail()
            return
        }
        do {
            let detail = try await session.scenePackageDetail(sceneID: id)
            _scenePackageDetail = detail
            workspaceReferenceArchives = try await session.sceneReferenceArchives(sceneID: id)
            workspaceReferenceCreationRefusals = try await session
                .referenceImageCreationRefusals(
                    requirementIDs: detail.plan
                        .filter { $0.isSatisfied == false }
                        .map(\.requirementID)
                )
            if let selectedReferenceRequirementID,
               detail.plan.contains(where: {
                   $0.requirementID == selectedReferenceRequirementID
               }) == false {
                closeReferenceDetail()
            }
        } catch {
            _scenePackageDetail = nil
            workspaceReferenceArchives = []
            workspaceReferenceCreationRefusals = [:]
            closeReferenceDetail()
            self.error = .project(error)
        }
    }

    func loadGenerationHistory() async {
        guard !isClosed, let detail = _scenePackageDetail else {
            generationPromptHistory = []
            generationPromptSetHistory = []
            return
        }
        generationPromptHistory =
            (try? await session.scenePromptHistory(
                sceneID: detail.sceneID, targetProfile: detail.activeProfile.id
            )) ?? []
        generationPromptSetHistory =
            (try? await session.scenePromptSetHistory(
                sceneID: detail.sceneID, targetProfile: detail.activeProfile.id
            )) ?? []
    }

    // MARK: - Enablement (§5.5's table, decided by reads)

    var canCopyScenePrompt: Bool {
        _scenePackageDetail?.currentPrompt != nil
    }

    var canRevealSceneReferences: Bool {
        (_scenePackageDetail?.plan.filter(\.isSatisfied).count ?? 0) >= 1
    }

    var canExportScenePackage: Bool {
        guard let detail = _scenePackageDetail else { return false }
        return detail.currentSet != nil && !detail.referencesExceedProfileLimit
    }

    var canExportAllReady: Bool {
        generationCounts.ready >= 1
    }

    /// Whether Export Sequence may run for a sequence: ≥ 1 Generation Ready scene in it.
    func sequenceHasReadyScenes(_ sequenceID: UUID) -> Bool {
        let sceneIDs = Set(
            scenes.filter { $0.sequenceID == sequenceID && $0.ordinal > 0 }.map(\.id)
        )
        return _scenePackages.contains {
            $0.packageState == .generationReady && sceneIDs.contains($0.sceneID)
        }
    }

    // MARK: - Commands

    /// §14.5's human authoring at scene scale: `createScenePrompt`, with its provenance
    /// parity contract inside FilmCore.
    func createScenePrompt(
        sceneID: UUID, body: String, guidance: String = "",
        durationSeconds: Int? = nil, aspectRatio: String = "", resolution: String = ""
    ) async {
        await runEdit {
            try await self.session.createScenePrompt(
                sceneID: sceneID, body: body, guidance: guidance,
                durationSeconds: durationSeconds, aspectRatio: aspectRatio,
                resolution: resolution, actor: .human
            )
        }
    }

    func setScenePromptBody(promptID: UUID, body: String) async {
        await runEdit {
            try await self.session.setScenePromptBody(promptID: promptID, body: body, actor: .human)
        }
    }

    func editScenePromptCard(cardID: UUID, draft: ScenePromptCardDraft) async {
        await runEdit {
            try await self.session.editScenePromptCard(cardID: cardID, draft: draft)
        }
    }

    func addScenePromptCard(setID: UUID, draft: ScenePromptCardDraft) async {
        await runEdit {
            try await self.session.addScenePromptCard(setID: setID, draft: draft)
        }
    }

    func deleteScenePromptCard(cardID: UUID) async {
        await inlinePromptEditors[cardID]?.discard()
        guard await runEdit({ try await self.session.deleteScenePromptCard(cardID: cardID) }) else {
            inlinePromptEditors[cardID]?.resumeAfterFailedDeletion()
            return
        }
        inlinePromptEditors[cardID] = nil
    }

    func reorderScenePromptCards(setID: UUID, orderedCardIDs: [UUID]) async {
        await runEdit {
            try await self.session.reorderScenePromptCards(
                setID: setID, orderedCardIDs: orderedCardIDs
            )
        }
    }

    func deleteScenePromptSet(setID: UUID) async {
        let editorIDs = inlinePromptEditors.filter { $0.value.setID == setID }.map(\.key)
        for id in editorIDs { await inlinePromptEditors[id]?.discard() }
        guard await runEdit({ try await self.session.deleteScenePromptSet(setID: setID) }) else {
            for id in editorIDs { inlinePromptEditors[id]?.resumeAfterFailedDeletion() }
            return
        }
        for id in editorIDs { inlinePromptEditors[id] = nil }
    }

    /// Delete-the-newest as the restore gesture (§3.1); history rows delete too.
    func deleteScenePrompt(promptID: UUID) async {
        await runEdit {
            try await self.session.deleteScenePrompt(promptID: promptID, actor: .human)
        }
    }

    /// §3.3/§3.5's project-wide headline flip. Stales nothing (§6.2).
    func setGenerationTargetProfile(_ profileID: String) async {
        await runEdit {
            try await self.session.setGenerationTargetProfile(profileID: profileID, actor: .human)
        }
    }

    /// Copy Prompt writes the current body byte-exact (§5.2) — a pure read.
    func copyScenePrompt() {
        guard let current = _scenePackageDetail?.currentPrompt else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(current.body, forType: .string)
    }

    func copyScenePromptCard(_ card: ScenePromptCard) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.body, forType: .string)
    }

    func prepareScenePromptCardReferences(
        cardID: UUID
    ) async -> ScenePromptCardMaterialization? {
        do {
            return try await session.materializeScenePromptCardReferences(cardID: cardID)
        } catch {
            self.error = .project(error)
            return nil
        }
    }

    func revealScenePromptCardReferences(cardID: UUID) async {
        guard let materialization = await prepareScenePromptCardReferences(cardID: cardID),
              let firstImage = materialization.references.first else {
            return
        }
        // Reveal a file so Finder shows the images inside the card folder, not its parent.
        finderRevealer(firstImage.fileURL)
    }

    /// §5.2: every satisfied reference's approved file, Finder-revealed through the
    /// injected revealer (no view touches `NSWorkspace`). Each path pays §4.1's
    /// containment rule like every other reveal (`revealVersionInFinder`'s shape).
    func revealSceneReferences() async {
        guard !isClosed, let detail = _scenePackageDetail else { return }
        for reference in detail.plan where reference.isSatisfied {
            guard let version = reference.approvedVersion,
                  let relative = try? RelativeProjectPath(version.relativePath)
            else { continue }
            do {
                let kind = try mediaContainment.entryKind(at: relative)
                guard kind == .file else { continue }
                finderRevealer(try await session.resolve(relative))
            } catch {
                self.error = .project(error)
            }
        }
    }

    // MARK: - Export (§3.8 through the session doors)

    /// One scene. A stale export arms §14.7's confirm naming the reason; confirming
    /// re-calls with the token the refusal carried.
    func exportScenePackage(sceneID: UUID, confirmingStaleReason: String? = nil) async {
        do {
            if let setID = try await session.scenePackageDetail(sceneID: sceneID).currentSet?.set.id {
                guard await flushInlinePromptEditors(setID: setID) else { return }
            }
            let exports = try await session.exportScenePackage(
                sceneID: sceneID, confirmingStaleReason: confirmingStaleReason
            )
            presentedExportSummary = GenerationExportPresentation(exports: [exports])
        } catch {
            // §14.7: a stale single-scene export is refused once, arming the confirm that
            // names the reason; every other refusal surfaces verbatim.
            if let storeError = error as? ProjectStoreError,
               case let .scenePackageStaleExportRequiresConfirm(reason) = storeError {
                pendingStaleExport = PendingStaleExport(sceneID: sceneID, reason: reason)
            } else {
                self.error = .project(error)
            }
        }
    }

    func confirmStaleExport() async {
        guard let pending = pendingStaleExport else { return }
        pendingStaleExport = nil
        await exportScenePackage(sceneID: pending.sceneID, confirmingStaleReason: pending.reason)
    }

    func cancelStaleExport() {
        pendingStaleExport = nil
    }

    func exportSequence(sequenceID: UUID) async {
        guard await flushInlinePromptEditors() else { return }
        do {
            let exports = try await session.exportSequencePackages(sequenceID: sequenceID)
            presentedExportSummary = GenerationExportPresentation(exports: exports)
        } catch {
            self.error = .project(error)
        }
    }

    func exportAllGenerationReady() async {
        guard await flushInlinePromptEditors() else { return }
        do {
            let exports = try await session.exportAllGenerationReadyPackages()
            presentedExportSummary = GenerationExportPresentation(exports: exports)
        } catch {
            self.error = .project(error)
        }
    }

    // MARK: - The §14.6 skill chooser (import / select)

    /// Imports a custom skill tree and auto-selects it (one ⌘Z step inside FilmCore).
    func importSceneSkill(from url: URL, displayName: String?, entryRelativePath: String, routingRelativePath: String) async {
        do {
            _ = try await session.importSceneSkill(
                from: url, displayName: displayName,
                entryRelativePath: entryRelativePath,
                routingRelativePath: routingRelativePath, actor: .human
            )
            await refresh()
            await loadImportedSkills()
        } catch {
            self.error = .project(error)
        }
    }

    /// The selection flip; `nil` restores the bundled default (§4.3). Stales nothing.
    func selectSceneSkill(_ skillID: UUID?) async {
        let applied = await runEdit {
            try await self.session.selectSceneSkill(skillID: skillID, actor: .human)
        }
        if applied { await loadImportedSkills() }
    }

    /// The §14.6 chooser's folder action: pick a tree, then import through the shipped
    /// door. The entry path is descriptor-relative and mandatory; the routing file is
    /// optional. Refusals surface FilmCore's copy verbatim.
    func chooseAndImportSceneSkill(entryRelativePath: String, routingRelativePath: String) async {
        guard !isClosed, let url = await skillChooser() else { return }
        await importSceneSkill(
            from: url, displayName: nil, entryRelativePath: entryRelativePath,
            routingRelativePath: routingRelativePath
        )
    }

    func loadImportedSkills() async {
        importedSkillRows = (try? await session.importedSkills()) ?? []
        selectedSkillRow = try? await session.selectedSkill()
    }
}

/// The Generation list's package-state scopes.
enum GenerationPackageFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case generationReady
    case stale
    case needsPreparation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .generationReady: "Generation Ready"
        case .stale: "Stale"
        case .needsPreparation: "Needs Preparation"
        }
    }

    func admits(_ row: ScenePackageSummary) -> Bool {
        switch self {
        case .all: true
        case .generationReady: row.packageState == .generationReady
        case .stale: row.packageState == .stale
        case .needsPreparation: row.packageState == .needsPreparation
        }
    }

    init(matching state: ScenePackageState) {
        self = switch state {
        case .generationReady: .generationReady
        case .stale: .stale
        case .needsPreparation: .needsPreparation
        }
    }
}
