import AppKit
import FilmCore
import Foundation

/// Plan 023's one presentation-level status. It is deliberately derived from the
/// existing readiness/package reads and is never persisted.
enum SceneWorkspaceStatus: String, CaseIterable, Sendable {
    case needsImages = "Needs Images"
    case readyForPrompt = "Ready for Prompt"
    case ready = "Ready"
    case updatePrompt = "Update Prompt"

    var systemImage: String {
        switch self {
        case .needsImages: "photo.badge.exclamationmark"
        case .readyForPrompt: "text.badge.plus"
        case .ready: "checkmark.circle.fill"
        case .updatePrompt: "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }
}

struct SceneWorkspaceRow: Identifiable, Sendable {
    let scene: Scene
    let status: SceneWorkspaceStatus

    var id: UUID { scene.id }
}

enum SceneWorkspaceNextAction: Equatable, Sendable {
    case importScreenplay
    case analyzeScreenplay
    case buildReferenceList
    case addImage(requirementID: UUID)
    case generatePrompt
    case updatePrompt
}

@MainActor
extension ProjectWindowModel {
    var selectedReferenceArchivedVersions: [AssetVersion] {
        guard let selectedReferenceRequirementID else { return [] }
        return workspaceReferenceArchives.first {
            $0.requirementID == selectedReferenceRequirementID
        }?.versions ?? []
    }

    var hasActiveWorkspaceRun: Bool {
        activeScenePromptRun != nil || activePromptRun != nil
            || activeManifestRun != nil || activeExtractionRun != nil
            || referenceImageGenerationTask != nil || isImportingGeneratedCandidate
    }

    var workspaceRunMessage: String {
        if activeScenePromptRun != nil, let progress = scenePromptProgress {
            return progress.message
        }
        if activePromptRun != nil, let progress = promptProgress { return progress.message }
        if activeManifestRun != nil, let progress = manifestProgress { return progress.message }
        if activeExtractionRun != nil, let progress = extractionProgress { return progress.message }
        if let requirementID = activeReferenceImageQueueItem?.requirementID,
           let message = referenceImageJobProgressMessage(for: requirementID) {
            return message
        }
        if let progress = imageGenerationProgress { return progress.presentationMessage }
        return "Working"
    }

    func cancelWorkspaceRun() async {
        if activeReferenceImageJobIsCommitting {
            return
        } else if referenceImageGenerationTask != nil {
            await cancelReferenceImageGeneration()
        } else if isImportingGeneratedCandidate {
            await cancelGeneratedCandidateImport()
        } else if activeScenePromptRun != nil {
            await cancelScenePromptRun()
        } else if activePromptRun != nil {
            await cancelPromptRun()
        } else if activeManifestRun != nil {
            await cancelManifestRun()
        } else if activeExtractionRun != nil {
            await cancelExtraction()
        }
    }

    /// One query for the only primary navigation surface.
    var workspaceSearchText: String {
        get { searchText(in: .scenes) }
        set { setSearchText(newValue, in: .scenes) }
    }

    var workspaceRows: [SceneWorkspaceRow] {
        let query = workspaceSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return scenes
            .filter { $0.ordinal > 0 && !$0.isOmitted }
            .filter { scene in
                query.isEmpty
                    || scene.heading.localizedCaseInsensitiveContains(query)
                    || (sceneTexts[scene.id]?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .map { SceneWorkspaceRow(scene: $0, status: workspaceStatus(forSceneID: $0.id)) }
    }

    var selectedWorkspaceSceneID: UUID? {
        selectedPackageSceneID ?? selectedSceneID
    }

    func workspaceStatus(forSceneID sceneID: UUID) -> SceneWorkspaceStatus {
        // Parser-only scenes do not yet know their production references. Calling a
        // zero-reference placeholder "Ready for Prompt" would contradict the promoted
        // Analyze action and expose handoff controls before preparation is complete.
        if !hasAppliedExtractionRun && !extractionIsClosedByManifest {
            return .needsImages
        }
        return Self.workspaceStatus(package: scenePackage(forSceneID: sceneID))
    }

    static func workspaceStatus(package: ScenePackageSummary?) -> SceneWorkspaceStatus {
        guard let package else { return .needsImages }
        switch package.packageState {
        case .generationReady:
            return .ready
        case .stale:
            return .updatePrompt
        case .needsPreparation:
            guard package.assetReadyState == .assetReady else { return .needsImages }
            return package.satisfiedCount < package.plannedCount
                ? .needsImages
                : .readyForPrompt
        }
    }

    /// The rail owns scene selection. Both legacy detail reads are selected together so
    /// Scene Data and the generation handoff always describe the same scene.
    func selectWorkspaceScene(_ id: UUID?) async {
        closeReferenceDetail()
        let ids = id.map { Set([$0]) } ?? []
        setSelection(ids, in: .scenes)
        if let id, scenePackage(forSceneID: id) != nil {
            setSelection([id], in: .generation)
        } else {
            setSelection([], in: .generation)
        }
        section = .scenes
        await loadSceneDetail()
        await loadScenePackageDetail()
        await loadGenerationHistory()
    }

    func selectFirstWorkspaceSceneIfNeeded() async {
        guard selectedWorkspaceSceneID == nil, let first = workspaceRows.first else { return }
        await selectWorkspaceScene(first.id)
    }

    /// Only the next blocking gesture is promoted inline. Project Actions keeps every
    /// preparation command available without turning these into automatic jobs.
    var workspaceNextAction: SceneWorkspaceNextAction? {
        guard script != nil else { return .importScreenplay }
        if !hasAppliedExtractionRun && !extractionIsClosedByManifest {
            // Preserve an already-materialized blocker, but do not let parser-only
            // character/location candidates displace the one-time Analyze action.
            if let missing = scenePackageDetail?.plan.first(where: { !$0.isSatisfied }) {
                return .addImage(requirementID: missing.requirementID)
            }
            return .analyzeScreenplay
        }
        // Analysis can discover a character or location used by only this scene. Those
        // entities qualify for references, but an older project may predate the policy or
        // may not have run Build since analysis. Materialize their slots before promoting
        // one of the scene's already-existing image blockers.
        if selectedSceneNeedsReferenceListBuild { return .buildReferenceList }
        if let missing = scenePackageDetail?.plan.first(where: { !$0.isSatisfied }) {
            return .addImage(requirementID: missing.requirementID)
        }
        if let detail = scenePackageDetail {
            if detail.currentSet == nil, detail.assetReadyState == .assetReady {
                return .generatePrompt
            }
            if detail.currentSet?.isStale == true { return .updatePrompt }
        }
        // An analyzed zero-reference scene is valid only when no qualifying visible entity
        // is waiting for its canonical slots.
        if requirementSummaries.isEmpty { return .buildReferenceList }
        return nil
    }

    private var selectedSceneNeedsReferenceListBuild: Bool {
        guard let sceneDetail, sceneDetail.scene.id == selectedWorkspaceSceneID else {
            return false
        }
        let missingEntityIDs = Set(entitiesMissingCanonicalSet.map(\.id))
        return sceneDetail.appearances.contains { appearance in
            missingEntityIDs.contains(appearance.entityID)
                && ManifestQualification.countsAsVisible(appearance.role)
        }
    }

    /// Resolves a reference through the same containment check as every Finder/preview
    /// path. Views receive a URL only after FilmCore's bundle-relative path is validated.
    func workspaceReferenceURL(_ version: ScenePlannedReference.ApprovedVersion) async -> URL? {
        do {
            let relative = try RelativeProjectPath(version.relativePath)
            guard try mediaContainment.entryKind(at: relative) == .file else { return nil }
            return try await session.resolve(relative)
        } catch {
            self.error = .project(error)
            return nil
        }
    }

    func workspaceVersionURL(_ version: AssetVersion) async -> URL? {
        do {
            guard try mediaContainment.entryKind(at: version.relativePath) == .file else {
                return nil
            }
            return try await session.resolve(version.relativePath)
        } catch {
            self.error = .project(error)
            return nil
        }
    }

    /// Compatibility read for the singular-prompt UI. It follows the immutable version
    /// id, not the requirement's currently approved version, so prompt history cannot
    /// silently show newer media. Plan 022 replaces this with card-reference rows that
    /// expose their citation directly.
    func workspaceAssetVersion(requirementID: UUID, versionID: UUID) async -> AssetVersion? {
        do {
            return try await session.requirement(id: requirementID).versions.first {
                $0.id == versionID
            }
        } catch {
            self.error = .project(error)
            return nil
        }
    }

    /// Loads the focused requirement without borrowing the Manifest section's filtered
    /// selection. Scene-plan membership is validated by `openReferenceDetail` first.
    func loadWorkspaceReference(requirementID: UUID) async {
        guard !isClosed else {
            requirementDetail = nil
            return
        }
        do {
            requirementDetail = try await session.requirement(id: requirementID)
        } catch {
            requirementDetail = nil
            self.error = .project(error)
        }
    }

    /// Opens a required reference inside the scene workspace. A stale or unrelated id is
    /// ignored rather than borrowing the Manifest inspector's selection.
    func openReferenceDetail(requirementID: UUID) async {
        guard _scenePackageDetail?.plan.contains(where: {
            $0.requirementID == requirementID
        }) == true else {
            closeReferenceDetail()
            return
        }
        selectedReferenceRequirementID = requirementID
        referenceImageLightbox = nil
        await loadWorkspaceReference(requirementID: requirementID)
        guard requirementDetail?.requirement.id == requirementID else {
            closeReferenceDetail()
            return
        }
        let hasCurrentImage = requirementDetail?.versions.contains {
            $0.status == .approved
        } == true
        if hasCurrentImage == false {
            guard referenceCreationRequirementID == nil
                    || referenceCreationRequirementID == requirementID
            else { return }
            // Selecting the detail removes the card that launched this method, which
            // cancels SwiftUI's card-owned Task. Own preparation independently so that
            // navigation cannot cancel the automatic prompt before it starts.
            let preparation = Task { @MainActor [weak self] in
                await self?.beginReferenceImageCreation(
                    requirementID: requirementID,
                    automaticallyPreparePrompt: true
                )
            }
            await preparation.value
        }
    }

    func closeReferenceDetail() {
        selectedReferenceRequirementID = nil
        referenceImageLightbox = nil
    }

    func presentReferenceImage(
        _ version: AssetVersion,
        accessibilityLabel: String
    ) {
        guard selectedReferenceRequirementID != nil else { return }
        referenceImageLightbox = ReferenceImageLightboxPresentation(
            version: version,
            accessibilityLabel: accessibilityLabel
        )
    }

    func dismissReferenceImage() {
        referenceImageLightbox = nil
    }

    func copySelectedReferencePrompt() {
        guard selectedReferenceRequirementID == requirementDetail?.requirement.id,
              let body = requirementDetail?.currentPrompt?.body
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
    }

    /// Saves an intentional correction to a reference's reusable prompt through
    /// FilmCore's undoable mutation boundary. Canonical dependency prompts are included
    /// in later generation contexts, so a face-prompt wardrobe correction also guides
    /// an explicit body update.
    @discardableResult
    func saveWorkspaceReferencePromptBody(
        requirementID: UUID,
        body: String
    ) async -> Bool {
        guard selectedReferenceRequirementID == requirementID,
              requirementDetail?.requirement.id == requirementID,
              let prompt = requirementDetail?.currentPrompt
        else { return false }
        guard prompt.body != body else { return true }

        let saved = await runEdit {
            try await self.session.setPromptBody(
                promptID: prompt.id,
                body: body,
                actor: .human
            )
        }
        guard saved else { return false }
        await loadWorkspaceReference(requirementID: requirementID)
        await loadScenePackageDetail()
        return true
    }

    func setWorkspaceReferenceNecessity(
        requirementID: UUID,
        necessity: RequirementNecessity
    ) async {
        await setRequirementNecessity(id: requirementID, necessity: necessity)
        await loadWorkspaceReference(requirementID: requirementID)
        await loadScenePackageDetail()
    }

    func removeReferenceFromCurrentScene(requirementID: UUID) async {
        await removeReferencesFromCurrentScene(requirementIDs: [requirementID])
    }

    /// Removes a reference or an entire bundle from only the open scene, in one undo step.
    /// FilmCore preserves screenplay appearances, requirements, media, and other scene links.
    func removeReferencesFromCurrentScene(requirementIDs: [UUID]) async {
        guard let sceneID = selectedPackageSceneID else { return }
        let removed = await runEdit {
            try await self.session.excludeReferencesFromScene(
                sceneID: sceneID,
                requirementIDs: requirementIDs,
                actor: .human
            )
        }
        guard removed else { return }
        if let selectedReferenceRequirementID,
           requirementIDs.contains(selectedReferenceRequirementID) {
            closeReferenceDetail()
        }
        await loadScenePackageDetail()
    }

    /// Approved project images that can be explicitly added to the open scene. This read
    /// intentionally ignores the Manifest view's current filters.
    func approvedImageReferenceCandidates() async -> [RequirementSummary] {
        guard !isClosed else { return [] }
        do {
            return try await session.requirementSummaries(
                kind: nil,
                tier: nil,
                reviewState: nil,
                includeRejected: false
            )
            .filter { $0.isActive && $0.displayStatus == .approved }
            .sorted {
                "\($0.entityName)\u{0}\($0.name)".localizedStandardCompare(
                    "\($1.entityName)\u{0}\($1.name)"
                ) == .orderedAscending
            }
        } catch {
            self.error = .project(error)
            return []
        }
    }

    /// Links an approved reference to the open scene using the domain's existing
    /// canonical/variant ownership rules. Canonical images travel with their entity;
    /// variants carry a direct scene link.
    func addImageReferenceToCurrentScene(_ requirement: RequirementSummary) async {
        guard let sceneID = selectedPackageSceneID else { return }
        if requirement.entityKind == .character, requirement.typeCode == "full_body" {
            if let bundle = await savedCharacterOutfitBundles().first(where: { $0.id == requirement.id }) {
                _ = await useCharacterOutfit(bundle, sceneID: sceneID)
            }
            return
        }
        if let exclusionID = try? await session.sceneReferenceExclusionID(
            sceneID: sceneID,
            requirementID: requirement.id
        ) {
            let restored = await runEdit {
                try await self.session.includeReferenceInScene(
                    exclusionID: exclusionID,
                    actor: .human
                )
            }
            guard restored else { return }
            await loadScenePackageDetail()
            return
        }
        let added: Bool
        switch requirement.tier {
        case .canonical:
            added = await runEdit {
                try await self.session.setSceneEntity(
                    sceneID: sceneID,
                    entityID: requirement.entityID,
                    role: .present,
                    actor: .human
                )
            }
        case .variant:
            added = await runEdit {
                try await self.session.addRequirementScene(
                    requirementID: requirement.id,
                    sceneID: sceneID,
                    actor: .human
                )
            }
        }
        guard added else { return }
        await loadScenePackageDetail()
    }

    func savedCharacterOutfitBundles() async -> [CharacterOutfitBundle] {
        do { return try await session.characterOutfitBundles() }
        catch { self.error = .project(error); return [] }
    }

    func useCharacterOutfit(_ bundle: CharacterOutfitBundle, sceneID: UUID) async -> Bool {
        let changed = await runEdit {
            try await self.session.useCharacterOutfit(
                bodyRequirementID: bundle.bodyRequirementID, sceneID: sceneID
            )
        }
        if changed { await loadScenePackageDetail() }
        return changed
    }

    /// Fork before generation: subsequent paid work can only replace the new variant.
    func createSceneCharacterOutfit(
        sourceRequirementID: UUID, sceneID: UUID, name: String
    ) async -> UUID? {
        let instruction = referencePromptDraft
        do {
            let created = try await session.createCharacterOutfit(
                sceneID: sceneID, sourceRequirementID: sourceRequirementID, name: name
            )
            didApply(created.entry)
            await endReferenceImageCreation()
            await refresh()
            await loadScenePackageDetail()
            await beginReferenceImageCreation(requirementID: created.requirementID, mode: .edit)
            updateReferencePromptDraft(instruction)
            return created.requirementID
        } catch {
            referenceImageGenerationErrorMessage = error.localizedDescription
            return nil
        }
    }

    /// Chooses a source image without exposing AppKit file panels to the SwiftUI view.
    func chooseSceneImageReferenceUpload() async -> URL? {
        guard !isClosed else { return nil }
        return await imageChooser()
    }

    /// Direct upload is one FilmCore operation: create an approved scene-specific
    /// reference, import its bytes, and attach it to the selected scene.
    @discardableResult
    func uploadImageReferenceToCurrentScene(name: String, from url: URL) async -> Bool {
        guard !isClosed, let sceneID = selectedPackageSceneID else { return false }
        do {
            let imported = try await session.importSceneImageReference(
                sceneID: sceneID,
                name: name,
                from: url,
                actor: .human
            )
            didApply(imported.entry)
            await refresh()
            await loadScenePackageDetail()
            return true
        } catch {
            self.error = .project(error)
            return false
        }
    }

    /// Import and current approval are one journaled operation and one undo step.
    func chooseAndMakeWorkspaceReferenceCurrent(requirementID: UUID) async {
        guard !isClosed, let url = await imageChooser() else { return }
        await makeWorkspaceReferenceCurrent(requirementID: requirementID, from: url)
    }

    func makeWorkspaceReferenceCurrent(requirementID: UUID, from url: URL) async {
        guard !isClosed else { return }
        do {
            let imported = try await session.importAndApproveAssetVersion(
                requirementID: requirementID, from: url, actor: .human, promptID: nil
            )
            didApply(imported.entry)
            await refresh()
            await loadWorkspaceReference(requirementID: requirementID)
            await loadScenePackageDetail()
        } catch {
            self.error = .project(error)
        }
    }

    /// The filled-card hover action. FilmCore performs the approved-version demotion,
    /// direct-dependent staleness fan-out, and byte-identical inverse in one journal entry.
    func archiveWorkspaceReference(requirementID: UUID) async {
        await runEdit {
            try await self.session.archiveCurrentVersion(
                requirementID: requirementID, actor: .human
            )
        }
        await loadScenePackageDetail()
        if selectedReferenceRequirementID == requirementID {
            await loadWorkspaceReference(requirementID: requirementID)
        }
    }

    /// Restoring from the collapsed archive is the existing canonical approval gesture;
    /// any current image is demoted to the same archive by that operation.
    func restoreWorkspaceReference(_ version: AssetVersion) async {
        let openRequirementID = selectedReferenceRequirementID
        await runEdit {
            try await self.session.approveVersion(
                assetID: version.assetID, versionID: version.id, actor: .human
            )
        }
        await loadScenePackageDetail()
        if let openRequirementID {
            await loadWorkspaceReference(requirementID: openRequirementID)
        }
    }

    /// Called only after the archive section's destructive confirmation.
    func deleteArchivedWorkspaceReference(_ version: AssetVersion) async {
        await runEdit {
            try await self.session.deleteArchivedVersion(
                versionID: version.id, actor: .human
            )
        }
        await loadScenePackageDetail()
        if let requirementID = selectedReferenceRequirementID {
            await loadWorkspaceReference(requirementID: requirementID)
        }
    }

    func setWorkspaceStyleBible(_ text: String) async {
        await runEdit { try await self.session.setStyleBible(text: text, actor: .human) }
        workspaceStyleBible = text
    }

    func loadWorkspaceSettings() async {
        workspaceStyleBible = (try? await session.styleBible()) ?? ""
        await loadImportedSkills()
    }
}
