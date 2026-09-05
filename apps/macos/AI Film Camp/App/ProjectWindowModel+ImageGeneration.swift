import AppKit
import FilmBrain
import FilmCore
import Foundation

/// Plan 024's app orchestration. FilmBrain owns discovery, arguments, process lifecycle,
/// progress, cancellation, and output bounds; FilmCore owns prompt/media validation and
/// every canonical write. This layer only joins those two doors for one window.
@MainActor
extension ProjectWindowModel {
    private static var maximumReferencePromptBytes: Int { 65_536 }

    var generatedCandidateSelection: GeneratedCandidateSelectionPresentation? {
        guard let requirementID = referenceCreationRequirementID else { return nil }
        return generatedCandidateSelections[requirementID]
    }

    func referenceImageJobState(for requirementID: UUID) -> ReferenceImageJobState? {
        referenceImageJobStates[requirementID]
    }

    func generatedCandidateSelection(
        for requirementID: UUID
    ) -> GeneratedCandidateSelectionPresentation? {
        generatedCandidateSelections[requirementID]
    }

    func referenceImageJobIsBusy(for requirementID: UUID) -> Bool {
        referenceImageJobStates[requirementID]?.isBusy == true
    }

    func referenceImageJobIsImporting(for requirementID: UUID) -> Bool {
        guard let state = referenceImageJobStates[requirementID] else { return false }
        if case .importing = state.phase { return true }
        return false
    }

    var activeReferenceImageJobIsCommitting: Bool {
        guard let requirementID = activeReferenceImageQueueItem?.requirementID else {
            return false
        }
        return referenceImageJobIsImporting(for: requirementID)
    }

    func referenceImageJobProgressMessage(for requirementID: UUID) -> String? {
        referenceImageJobStates[requirementID]?.message
    }

    func referenceImageJobError(for requirementID: UUID) -> String? {
        guard let state = referenceImageJobStates[requirementID],
              case let .failed(message) = state.phase else {
            return nil
        }
        return message
    }

    func beginReferenceImageCreation(
        requirementID: UUID,
        mode: ReferenceImageCreationMode = .create,
        automaticallyPreparePrompt: Bool = false
    ) async {
        guard referenceCreationRequirementID == nil
                || referenceCreationRequirementID == requirementID
        else { return }
        referenceCreationRequirementID = requirementID
        referenceImageCreationMode = mode
        referenceIncludesCurrentImage = mode == .edit
        referenceImageGenerationAttachment =
            retainedReferenceImageGenerationAttachments[requirementID]
        referencePromptSaveTask?.cancel()
        referencePromptSaveTask = nil
        referencePromptDraft = ""
        referencePromptDraftID = nil
        referencePromptDraftRevision = 0
        referencePromptSavedRevision = 0
        referencePromptValidationMessage = nil
        imageGenerationProgress = nil
        referenceImageGenerationErrorMessage = referenceImageJobError(for: requirementID)
        await loadReferenceImageCreationDetail(requirementID: requirementID)
        guard Task.isCancelled == false,
              referenceCreationRequirementID == requirementID
        else { return }

        // Missing-reference detail is itself the creation workflow. It may prepare the
        // prompt as soon as it opens; the existing one-time disclosure still prevents any
        // outbound request until the filmmaker acknowledges it. Direct regeneration and
        // modal editing both keep their explicit launch behavior.
        if referenceImageCreationDetail?.requirement.id == requirementID,
           referenceImageCreationDetail?.currentPrompt == nil,
           automaticallyPreparePrompt {
            await preparePromptRun()
        }

        guard Task.isCancelled == false,
              referenceCreationRequirementID == requirementID
        else { return }
        await refreshReferenceImageGeneratorStatus()
        guard Task.isCancelled == false,
              referenceCreationRequirementID == requirementID
        else { return }

        // Prompt application and the generator capability probe can both trigger a model
        // refresh. Reload through the focused requirement door before deciding whether a
        // generation context exists, so the inline editor never loses its new prompt to a
        // refresh race.
        await refreshReferenceImageCreationContext()
    }

    func endReferenceImageCreation() async {
        // Closing detaches presentation only. A queued or active job owns frozen inputs
        // and continues independently until project-window teardown or toolbar Cancel.
        if referenceImageDisclosureGate == nil {
            cancelPreparedPromptRun()
        }
        presentedPromptReport = nil
        if activePromptRun != nil, activeReferenceImageQueueItem == nil {
            await cancelPromptRun()
        }
        _ = await flushReferencePromptDraft()
        referencePromptSaveTask?.cancel()
        referencePromptSaveTask = nil
        referenceCreationRequirementID = nil
        referenceImageCreationDetail = nil
        referenceImageCreationMode = .create
        referenceIncludesCurrentImage = false
        referenceImageGenerationAttachment = nil
        referenceImageGenerationContext = nil
        imageGeneratorStatus = nil
        imageGenerationProgress = nil
        referenceImageGenerationErrorMessage = nil
    }

    /// Reloads both the visible prompt and FilmCore's generation commit token. Prompt
    /// generation calls this directly so its completed prompt replaces progress in place.
    func refreshReferenceImageCreationContext() async {
        guard let requirementID = referenceCreationRequirementID else { return }
        await loadReferenceImageCreationDetail(requirementID: requirementID)
        guard Task.isCancelled == false,
              referenceCreationRequirementID == requirementID
        else { return }
        guard let prompt = referenceImageCreationDetail?.currentPrompt else {
            referenceImageGenerationContext = nil
            return
        }
        initializeReferencePromptDraft(promptID: prompt.id, body: prompt.body)
        await reloadReferenceGenerationContextOnly()
    }

    /// Rebuilds readiness from the current app-wide provider and Keychain state without
    /// resetting the open creation workflow. Inline credential entry calls this after a
    /// successful save so Generate can become available immediately.
    func refreshReferenceImageGeneratorStatus() async {
        guard let requirementID = referenceCreationRequirementID else { return }
        let status = await imageGeneratorFactory(ImageGeneratorPreferences.provider()).status()
        guard Task.isCancelled == false,
              referenceCreationRequirementID == requirementID
        else { return }
        imageGeneratorStatus = status
    }

    var referenceImageGenerationDisabledReason: String? {
        if let requirementID = referenceCreationRequirementID,
           referenceImageJobStates[requirementID]?.preventsDuplicate == true {
            return "This reference is already queued, running, or awaiting selection."
        }
        guard referenceImageCreationDetail?.currentPrompt != nil else {
            return "Preparing an image-generation prompt…"
        }
        if let validation = referencePromptValidationMessage {
            return validation
        }
        guard let context = referenceImageGenerationContext else {
            return "Loading canonical reference inputs…"
        }
        if let refusal = context.refusalReason { return refusal }
        let provider = ImageGeneratorPreferences.provider()
        let attachments = referenceImageGenerationAttachment.map { [$0] } ?? []
        let referenceCount = context.orderedDependencies.count + attachments.count
        if referenceCount > provider.maximumReferenceImages {
            return ImageGenerationError.unsupportedReferenceCount(
                providerName: provider.displayName,
                count: referenceCount,
                maximum: provider.maximumReferenceImages
            ).localizedDescription
        }
        if let maximum = provider.maximumCharacterReferences {
            let characterCount = context.orderedDependencies.filter {
                $0.entityKind == .character || $0.entityKind == .creature
            }.count + attachments.filter {
                $0.entityKind == .character || $0.entityKind == .creature
            }.count
            if characterCount > maximum {
                return ImageGenerationError.unsupportedCharacterReferenceCount(
                    providerName: provider.displayName,
                    count: characterCount,
                    maximum: maximum
                ).localizedDescription
            }
        }
        if let maximum = provider.maximumNonCharacterReferences {
            let nonCharacterCount = context.orderedDependencies.filter {
                $0.entityKind != .character && $0.entityKind != .creature
            }.count + attachments.filter {
                $0.entityKind != .character && $0.entityKind != .creature
            }.count
            if nonCharacterCount > maximum {
                return ImageGenerationError.unsupportedReferenceCount(
                    providerName: provider.displayName,
                    count: nonCharacterCount,
                    maximum: maximum
                ).localizedDescription
            }
        }
        guard let status = imageGeneratorStatus else { return "Checking the local generator…" }
        if case .ready = status { return nil }
        return imageGeneratorStatusMessage(status)
    }

    var referenceImageGenerationSettings: ImageGenerationSettings? {
        if referenceImageCreationDetail?.referenceTypeCode == "full_body" {
            return ImageGenerationSettings(aspectRatio: .landscape16x9)
        }
        return referenceImageGenerationContext.map {
            ImageGenerationSettings.smartDefault(for: $0.entityKind)
        }
    }

    var inPlaceReferenceGenerationProgressMessage: String {
        if let requirementID = inPlaceReferenceGenerationRequirementID,
           let message = referenceImageJobProgressMessage(for: requirementID) {
            return message
        }
        if pendingPromptDisclosure != nil {
            return "Waiting for approval…"
        }
        if activePromptRun != nil {
            return promptProgress?.message ?? "Preparing the image prompt…"
        }
        if isImportingGeneratedCandidate || isReferenceImageCommitInProgress {
            return "Adding the image to the project…"
        }
        if let imageGenerationProgress {
            return imageGenerationProgress.presentationMessage
        }
        switch inPlaceReferenceGenerationKind {
        case .bodyFromFace:
            return "Preparing the body from the approved face…"
        case .regenerate:
            return "Preparing image regeneration…"
        case .missingReference, .none:
            return "Preparing image generation…"
        }
    }

    /// Plan 029's single-action character continuation. It deliberately reuses the
    /// ordinary prompt, provider, validation, and FilmCore commit doors; only candidate
    /// selection and navigation are collapsed for this one-candidate bundle operation.
    func generateBodyFromFace(requirementID: UUID) async {
        await beginInPlaceReferenceGeneration(
            requirementID: requirementID,
            kind: .bodyFromFace
        )
    }

    /// Filled-reference regeneration is a single explicit paid-request gesture. The
    /// visible saved prompt is reused, one candidate is requested, and the validated
    /// result replaces the current image through the existing atomic import path.
    func regenerateWorkspaceReference(requirementID: UUID) async {
        await beginInPlaceReferenceGeneration(
            requirementID: requirementID,
            kind: .regenerate
        )
    }

    /// Missing-card Generate collapses prompt preparation and one-candidate generation
    /// without navigating away from the scene. Existing FilmCore refusals still gate it.
    func generateMissingReference(requirementID: UUID) async {
        guard _scenePackageDetail?.plan.first(where: {
            $0.requirementID == requirementID
        })?.isSatisfied == false else { return }
        if let refusal = workspaceReferenceCreationRefusals[requirementID] {
            inPlaceReferenceGenerationFailedRequirementID = requirementID
            inPlaceReferenceGenerationErrorMessage = refusal
            return
        }
        await beginInPlaceReferenceGeneration(
            requirementID: requirementID,
            kind: .missingReference
        )
    }

    private func beginInPlaceReferenceGeneration(
        requirementID: UUID,
        kind: InPlaceReferenceGenerationKind
    ) async {
        guard referenceImageJobIsBusy(for: requirementID) == false,
              generatedCandidateSelections[requirementID] == nil
        else { return }

        let capturedDetail = try? await session.requirement(id: requirementID)
        let mode: ReferenceImageCreationMode = kind == .regenerate ? .regenerate : .create
        let requestedSettings = (kind == .bodyFromFace
            || capturedDetail?.referenceTypeCode == "full_body")
            ? ImageGenerationSettings(aspectRatio: .landscape16x9)
            : nil
        let attachments = retainedReferenceImageGenerationAttachments[requirementID]
            .map { [$0] } ?? []
        var prepared: PreparedReferenceImageJob?
        if let detail = capturedDetail, let promptBody = detail.currentPrompt?.body,
           let preliminaryContext = try? await session.referenceImageGenerationContext(
               requirementID: requirementID,
               generationPromptBody: nil,
               includeCurrentImage: false
           ) {
            let effectivePrompt = providerPromptBody(
                basePrompt: promptBody,
                context: preliminaryContext,
                mode: mode,
                requirementTypeCode: detail.referenceTypeCode
            )
            if let context = try? await session.referenceImageGenerationContext(
                requirementID: requirementID,
                generationPromptBody: effectivePrompt,
                includeCurrentImage: false
            ) {
                prepared = PreparedReferenceImageJob(
                    context: context,
                    prompt: effectivePrompt,
                    entityName: detail.entity.name,
                    requirementName: detail.requirement.name,
                    requirementTypeCode: detail.referenceTypeCode,
                    settings: requestedSettings
                        ?? ImageGenerationSettings.smartDefault(for: context.entityKind),
                    attachments: attachments,
                    visualAmendment: nil,
                    includeCurrentImage: false
                )
            }
        }
        inPlaceReferenceGenerationFailedRequirementID = nil
        inPlaceReferenceGenerationErrorMessage = nil
        enqueueReferenceImageJob(ReferenceImageQueueItem(
            requirementID: requirementID,
            mode: mode,
            kind: kind,
            candidateCount: 1,
            requestedSettings: requestedSettings,
            provider: ImageGeneratorPreferences.provider(),
            capturedPromptBody: capturedDetail?.currentPrompt?.body,
            attachments: attachments,
            prepared: prepared
        ))
    }

    func continueInPlaceReferenceGenerationIfReady() async {
        // Retained for the existing prompt-run completion callback. Queued jobs prepare
        // their own prompt and resume directly, so there is no window-global continuation.
    }

    func cancelInPlaceReferenceGeneration() async {
        await cancelReferenceImageGeneration()
    }

    func failInPlaceReferenceGenerationIfNeeded(message: String) async {
        guard let requirementID = inPlaceReferenceGenerationRequirementID else { return }
        referenceImageJobStates[requirementID] = .failed(message)
        inPlaceReferenceGenerationFailedRequirementID = requirementID
        inPlaceReferenceGenerationErrorMessage = message
    }

    var referenceImageProvider: ImageProviderDescriptor {
        ImageGeneratorPreferences.provider()
    }

    func updateReferencePromptDraft(_ body: String) {
        guard referencePromptDraft != body else { return }
        referencePromptDraft = body
        referencePromptDraftRevision &+= 1
        referencePromptValidationMessage = validateReferencePrompt(body)
        referencePromptSaveTask?.cancel()
        if referenceImageCreationMode == .edit {
            referencePromptSaveTask = nil
            referenceImageGenerationContext = nil
            guard referencePromptValidationMessage == nil else { return }
            Task { await reloadReferenceGenerationContextOnly() }
            return
        }
        guard referencePromptValidationMessage == nil else { return }
        referencePromptSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(600))
                guard Task.isCancelled == false else { return }
                await self?.beginDebouncedReferencePromptFlush()
            } catch {}
        }
    }

    func setReferenceIncludesCurrentImage(_ include: Bool) {
        guard referenceImageCreationMode == .regenerate else { return }
        referenceIncludesCurrentImage = include
        referenceImageGenerationContext = nil
        Task { await reloadReferenceGenerationContextOnly() }
    }

    func chooseReferenceImageGenerationAttachment() async {
        guard let requirementID = referenceCreationRequirementID,
              referenceImageJobStates[requirementID]?.preventsDuplicate != true,
              let url = await imageChooser()
        else { return }
        await attachReferenceImageGenerationAttachment(from: url)
    }

    /// Picker and drag-and-drop gestures share one validated, ephemeral attachment path.
    /// FilmCore freezes the bytes and metadata; the view only supplies the dropped URL.
    func attachReferenceImageGenerationAttachment(from url: URL) async {
        guard let requirementID = referenceCreationRequirementID,
              referenceImageJobStates[requirementID]?.preventsDuplicate != true,
              let entityKind = referenceImageCreationDetail?.entity.kind
        else { return }

        do {
            let attachment = try await session
                .referenceImageGenerationAttachment(from: url, entityKind: entityKind)
            guard referenceCreationRequirementID == requirementID else { return }
            referenceImageGenerationAttachment = attachment
            retainedReferenceImageGenerationAttachments[requirementID] = attachment
            referenceImageGenerationErrorMessage = nil
        } catch {
            referenceImageGenerationErrorMessage = error.localizedDescription
        }
    }

    func removeReferenceImageGenerationAttachment() {
        guard let requirementID = referenceCreationRequirementID,
              referenceImageJobStates[requirementID]?.preventsDuplicate != true
        else { return }
        retainedReferenceImageGenerationAttachments[requirementID] = nil
        referenceImageGenerationAttachment = nil
        referenceImageGenerationErrorMessage = nil
    }

    func copyReferencePrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(referencePromptDraft, forType: .string)
    }

    /// Removes the current prompt through FilmCore's undoable mutation boundary. The
    /// creation sheet then falls back to prompt preparation without stacking another
    /// confirmation surface over this workflow.
    func removeReferencePrompt() async {
        guard isSavingReferencePrompt == false,
              isRemovingReferencePrompt == false,
              let requirementID = referenceCreationRequirementID,
              referenceImageJobStates[requirementID]?.preventsDuplicate != true,
              let promptID = referenceImageCreationDetail?.currentPrompt?.id
        else { return }

        referencePromptSaveTask?.cancel()
        referencePromptSaveTask = nil
        isRemovingReferencePrompt = true
        defer { isRemovingReferencePrompt = false }

        let removed = await runEdit {
            try await self.session.deletePrompt(promptID: promptID, actor: .human)
        }
        guard removed else { return }

        referencePromptDraft = ""
        referencePromptDraftID = nil
        referencePromptDraftRevision = 0
        referencePromptSavedRevision = 0
        referencePromptValidationMessage = nil
        referenceImageGenerationContext = nil
        referenceImageGenerationErrorMessage = nil
        await loadWorkspaceReference(requirementID: requirementID)
    }

    @discardableResult
    func flushReferencePromptDraft() async -> Bool {
        referencePromptSaveTask?.cancel()
        referencePromptSaveTask = nil
        if referenceImageCreationMode == .edit {
            referencePromptValidationMessage = validateReferencePrompt(referencePromptDraft)
            guard referencePromptValidationMessage == nil else { return false }
            await reloadReferenceGenerationContextOnly()
            return referenceImageGenerationContext != nil
        }
        if isSavingReferencePrompt {
            while isSavingReferencePrompt {
                do {
                    try await Task.sleep(for: .milliseconds(20))
                } catch {
                    return false
                }
            }
            if referencePromptSavedRevision < referencePromptDraftRevision {
                return await flushReferencePromptDraft()
            }
            return referencePromptValidationMessage == nil
        }

        let validation = validateReferencePrompt(referencePromptDraft)
        guard validation == nil else {
            referencePromptValidationMessage = validation
            return false
        }
        guard referencePromptDraftID != nil else { return false }

        isSavingReferencePrompt = true
        defer { isSavingReferencePrompt = false }
        repeat {
            guard let promptID = referencePromptDraftID else { return false }
            let body = referencePromptDraft
            let revision = referencePromptDraftRevision
            do {
                if referenceImageCreationDetail?.currentPrompt?.body != body {
                    let entry = try await session.setPromptBody(
                        promptID: promptID, body: body, actor: .human
                    )
                    didApply(entry)
                    await refresh()
                }
                referencePromptSavedRevision = revision
                await reloadReferenceGenerationContextOnly()
            } catch {
                referencePromptValidationMessage = error.localizedDescription
                self.error = .project(error)
                return false
            }
        } while referencePromptSavedRevision < referencePromptDraftRevision
        return true
    }

    func generateReferenceImages(
        candidateCount: Int,
        settings: ImageGenerationSettings? = nil
    ) async {
        guard (1...4).contains(candidateCount),
              let requirementID = referenceCreationRequirementID,
              referenceImageJobStates[requirementID]?.preventsDuplicate != true,
              generatedCandidateSelections[requirementID] == nil
        else { return }
        referenceImageGenerationErrorMessage = nil
        referenceImageJobStates[requirementID] = nil
        defer {
            if referenceImageJobStates[requirementID]?.preventsDuplicate != true,
               let message = referenceImageGenerationErrorMessage {
                referenceImageJobStates[requirementID] = .failed(message)
            }
        }
        guard await flushReferencePromptDraft() else {
            referenceImageGenerationErrorMessage = referencePromptValidationMessage
                ?? "The image prompt could not be saved."
            return
        }
        await reloadReferenceGenerationContextOnly()
        if let referencePromptValidationMessage {
            referenceImageGenerationErrorMessage = referencePromptValidationMessage
            return
        }
        guard let context = referenceImageGenerationContext,
              let detail = referenceImageCreationDetail else {
            if referenceImageGenerationErrorMessage == nil {
                referenceImageGenerationErrorMessage =
                    "Canonical reference inputs could not be loaded."
            }
            return
        }
        if let refusal = context.refusalReason {
            referenceImageGenerationErrorMessage = ProjectStoreError
                .assetOperationRefused(reason: refusal)
                .localizedDescription
            return
        }
        let frozenPrompt = providerPromptBody(
            basePrompt: referencePromptDraft,
            context: context
        )
        let attachments = referenceImageGenerationAttachment.map { [$0] } ?? []
        guard context.matchesPromptBody(frozenPrompt) else {
            referenceImageGenerationErrorMessage = ReferenceImageCreationError
                .promptChanged
                .localizedDescription
            return
        }
        let chosenSettings = settings
            ?? referenceImageGenerationSettings
            ?? ImageGenerationSettings.smartDefault(for: context.entityKind)
        let prepared = PreparedReferenceImageJob(
            context: context,
            prompt: frozenPrompt,
            entityName: detail.entity.name,
            requirementName: detail.requirement.name,
            requirementTypeCode: detail.referenceTypeCode,
            settings: chosenSettings,
            attachments: attachments,
            visualAmendment: referenceImageCreationMode == .edit
                ? ImageGenerationVisualAmendment(
                    instruction: referencePromptDraft,
                    scope: context.entityKind == .character && context.tier == .canonical
                        ? .characterBundle
                        : .requirement
                )
                : nil,
            includeCurrentImage: referenceIncludesCurrentImage
        )
        enqueueReferenceImageJob(ReferenceImageQueueItem(
            requirementID: requirementID,
            mode: referenceImageCreationMode,
            kind: nil,
            candidateCount: candidateCount,
            requestedSettings: chosenSettings,
            provider: ImageGeneratorPreferences.provider(),
            capturedPromptBody: referencePromptDraft,
            attachments: attachments,
            prepared: prepared
        ))
    }

    private func enqueueReferenceImageJob(_ item: ReferenceImageQueueItem) {
        guard referenceImageJobStates[item.requirementID]?.preventsDuplicate != true,
              generatedCandidateSelections[item.requirementID] == nil
        else { return }
        referenceImageJobStates[item.requirementID] = .queued
        referenceImageQueue.append(item)
        startNextReferenceImageJobIfNeeded()
    }

    func startNextReferenceImageJobIfNeeded() {
        guard isClosed == false,
              referenceImageGenerationTask == nil,
              activeReferenceImageQueueItem == nil,
              activePromptRun == nil,
              preparedPromptRun == nil,
              pendingPromptDisclosure == nil,
              referenceImageQueue.isEmpty == false
        else { return }

        let item = referenceImageQueue.removeFirst()
        let runID = item.id
        activeReferenceImageQueueItem = item
        inPlaceReferenceGenerationRequirementID = item.requirementID
        inPlaceReferenceGenerationKind = item.kind
        referenceImageGenerationRunID = runID
        referenceImageJobStates[item.requirementID] = .preparingPrompt
        imageGenerationProgress = .init(stage: .preparing)
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performQueuedReferenceImageGeneration(item, runID: runID)
        }
        referenceImageGenerationTask = task
    }

    private func performQueuedReferenceImageGeneration(
        _ item: ReferenceImageQueueItem,
        runID: UUID
    ) async {
        var outputDirectory: URL?
        var retainOutputDirectory = false
        defer {
            if retainOutputDirectory == false, let outputDirectory {
                removeGenerationCache(outputDirectory)
            }
            finishQueuedReferenceImageGeneration(item: item, runID: runID)
        }

        do {
            var prepared = try await prepareReferenceImageQueueItem(item, runID: runID)
            try requireCurrentImageGenerationRun(runID)

            // Rebuild FilmCore's complete launch token immediately before materialising
            // inputs and making the paid request. The atomic import repeats this check.
            let canonicalContext = try await session.referenceImageGenerationContext(
                requirementID: item.requirementID,
                generationPromptBody: prepared.prompt,
                includeCurrentImage: prepared.includeCurrentImage
            )
            guard canonicalContext == prepared.context else {
                throw ReferenceImageCreationError.canonicalStateChanged
            }
            prepared.context = canonicalContext
            if let refusal = canonicalContext.refusalReason {
                throw ProjectStoreError.assetOperationRefused(reason: refusal)
            }
            try validateProviderCapacity(
                provider: item.provider,
                context: canonicalContext,
                attachments: prepared.attachments
            )

            let directory = ProjectBundleLayout(rootURL: bundleURL).cacheDirectoryURL
                .appending(path: "jobs", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
                .appending(path: "image-generation", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            outputDirectory = directory
            let references = try await generationReferences(
                for: canonicalContext,
                attachments: prepared.attachments,
                in: directory
            )
            try requireCurrentImageGenerationRun(runID)

            // Constructing the captured provider's generator here is what delays the
            // Keychain read until execution begins.
            let generator = imageGeneratorFactory(item.provider)
            activeImageGenerator = generator
            let status = await generator.status()
            imageGeneratorStatus = status
            try requireCurrentImageGenerationRun(runID)
            guard case .ready = status else {
                throw ImageGenerationError.generatorUnavailable(status)
            }

            referenceImageJobStates[item.requirementID] = .generating(nil)
            await observeImageGenerationProgress(
                generator, requirementID: item.requirementID
            )
            let result = try await generator.generate(ImageGenerationRequest(
                prompt: prepared.prompt,
                references: references,
                outputDirectoryURL: directory,
                candidateCount: item.candidateCount,
                settings: prepared.settings
            ))
            try requireCurrentImageGenerationRun(runID)
            try await validateGeneratedCandidates(result.candidates)
            try requireCurrentImageGenerationRun(runID)

            let selection = GeneratedCandidateSelectionPresentation(
                requirementID: item.requirementID,
                context: canonicalContext,
                entityName: prepared.entityName,
                requirementName: prepared.requirementName,
                candidates: result.candidates,
                result: result,
                settings: prepared.settings,
                attachments: prepared.attachments,
                visualAmendment: prepared.visualAmendment,
                outputDirectoryURL: directory
            )
            let automaticallyImports = selection.candidates.count == 1
                && (item.mode == .create || item.mode == .edit)
            if automaticallyImports {
                referenceImageJobStates[item.requirementID] = .importing
                imageGenerationProgress = .init(stage: .importing)
                isReferenceImageCommitInProgress = true
                let summary = try await session.importGeneratedCandidates(
                    requirementID: selection.requirementID,
                    from: selection.candidates.map(\.fileURL),
                    selectedIndex: 0,
                    context: selection.context,
                    metadata: generationMetadata(
                        result: selection.result,
                        settings: selection.settings,
                        selectedIndex: 0,
                        attachments: selection.attachments,
                        visualAmendment: selection.visualAmendment
                    ),
                    actor: .human
                )
                didApply(summary.entry)
                await refresh()
                await loadScenePackageDetail()
                if referenceCreationRequirementID == item.requirementID {
                    await loadReferenceImageCreationDetail(requirementID: item.requirementID)
                }
                // Publish success only after the saved image has reached the card.
                referenceImageJobStates[item.requirementID] = .completed(
                    versionID: summary.selectedVersionID
                )
            } else {
                generatedCandidateSelections[item.requirementID] = selection
                referenceImageJobStates[item.requirementID] = .awaitingSelection
                retainOutputDirectory = true
            }
        } catch is CancellationError {
            referenceImageJobStates[item.requirementID] = nil
        } catch ImageGenerationError.cancelled {
            referenceImageJobStates[item.requirementID] = nil
        } catch {
            if Task.isCancelled {
                referenceImageJobStates[item.requirementID] = nil
                return
            }
            isReferenceImageCommitInProgress = false
            let message = error.localizedDescription
            referenceImageJobStates[item.requirementID] = .failed(message)
            if referenceCreationRequirementID == item.requirementID {
                referenceImageGenerationErrorMessage = message
            }
            inPlaceReferenceGenerationFailedRequirementID = item.requirementID
            inPlaceReferenceGenerationErrorMessage = message
        }
    }

    private func prepareReferenceImageQueueItem(
        _ item: ReferenceImageQueueItem,
        runID: UUID
    ) async throws -> PreparedReferenceImageJob {
        if let prepared = item.prepared { return prepared }

        var detail = try await session.requirement(id: item.requirementID)
        if item.kind == .bodyFromFace, detail.referenceTypeCode != "full_body" {
            throw ReferenceImageCreationError.bodySlotUnavailable
        }
        if item.kind == .missingReference,
           detail.versions.contains(where: { $0.status == .approved }) {
            throw ReferenceImageCreationError.currentImageAlreadyExists
        }
        if item.kind == .regenerate,
           detail.versions.contains(where: { $0.status == .approved }) == false {
            throw ReferenceImageCreationError.currentImageMissing
        }
        if detail.currentPrompt == nil, item.capturedPromptBody == nil {
            try await prepareQueuedReferencePrompt(
                requirementID: item.requirementID, runID: runID
            )
            detail = try await session.requirement(id: item.requirementID)
        }
        guard let promptBody = item.capturedPromptBody ?? detail.currentPrompt?.body else {
            throw ReferenceImageCreationError.promptUnavailable
        }

        let includeCurrentImage = item.mode == .edit
        let preliminaryContext = try await session.referenceImageGenerationContext(
            requirementID: item.requirementID,
            generationPromptBody: nil,
            includeCurrentImage: includeCurrentImage
        )
        let effectivePrompt = providerPromptBody(
            basePrompt: promptBody,
            context: preliminaryContext,
            mode: item.mode,
            requirementTypeCode: detail.referenceTypeCode
        )
        guard effectivePrompt.lengthOfBytes(using: .utf8)
            <= Self.maximumReferencePromptBytes
        else { throw ReferenceImageCreationError.promptTooLong }
        let context = try await session.referenceImageGenerationContext(
            requirementID: item.requirementID,
            generationPromptBody: effectivePrompt,
            includeCurrentImage: includeCurrentImage
        )
        return PreparedReferenceImageJob(
            context: context,
            prompt: effectivePrompt,
            entityName: detail.entity.name,
            requirementName: detail.requirement.name,
            requirementTypeCode: detail.referenceTypeCode,
            settings: item.requestedSettings
                ?? ImageGenerationSettings.smartDefault(for: context.entityKind),
            attachments: item.attachments,
            visualAmendment: nil,
            includeCurrentImage: includeCurrentImage
        )
    }

    private func prepareQueuedReferencePrompt(
        requirementID: UUID,
        runID: UUID
    ) async throws {
        guard let extractionAdapterFactory else {
            throw ReferenceImageCreationError.promptGeneratorUnavailable
        }
        guard let descriptor = Self.defaultPromptSkillDescriptor else {
            throw PromptRunError.materialisationFailed(
                "The bundled prompt skill is missing from this copy of AI Film Camp."
            )
        }
        if try await session.disclosureAcknowledgedAt() == nil {
            let gate = ReferenceImageDisclosureGate()
            referenceImageDisclosureGate = gate
            pendingPromptDisclosure = PromptDisclosurePresentation()
            referenceImageJobStates[requirementID] = .waitingForApproval
            guard await gate.wait(), Task.isCancelled == false else {
                throw CancellationError()
            }
            try requireCurrentImageGenerationRun(runID)
        }

        referenceImageJobStates[requirementID] = .preparingPrompt
        let run = AssetPromptRun(
            project: session,
            adapter: try extractionAdapterFactory(),
            descriptor: descriptor,
            bundleRoot: session.bundleURL
        )
        activePromptRun = run
        await startPromptProgressObservation(for: run)
        defer {
            activePromptRun = nil
            promptProgressTask?.cancel()
            promptProgressTask = nil
        }
        let outcome = try await run.start(
            requirementID: requirementID,
            engine: "codex",
            engineVersion: "current",
            settings: AssetPromptSettings(inputBudgetUTF16: 0)
        )
        didApply(outcome.entry)
        try requireCurrentImageGenerationRun(runID)
        await refresh()
    }

    private func validateProviderCapacity(
        provider: ImageProviderDescriptor,
        context: ReferenceImageGenerationContext,
        attachments: [ReferenceImageGenerationAttachment]
    ) throws {
        let referenceCount = context.orderedDependencies.count + attachments.count
        guard referenceCount <= provider.maximumReferenceImages else {
            throw ImageGenerationError.unsupportedReferenceCount(
                providerName: provider.displayName,
                count: referenceCount,
                maximum: provider.maximumReferenceImages
            )
        }
        let characterCount = context.orderedDependencies.filter {
            $0.entityKind == .character || $0.entityKind == .creature
        }.count + attachments.filter {
            $0.entityKind == .character || $0.entityKind == .creature
        }.count
        if let maximum = provider.maximumCharacterReferences,
           characterCount > maximum {
            throw ImageGenerationError.unsupportedCharacterReferenceCount(
                providerName: provider.displayName,
                count: characterCount,
                maximum: maximum
            )
        }
        let nonCharacterCount = referenceCount - characterCount
        if let maximum = provider.maximumNonCharacterReferences,
           nonCharacterCount > maximum {
            throw ImageGenerationError.unsupportedReferenceCount(
                providerName: provider.displayName,
                count: nonCharacterCount,
                maximum: maximum
            )
        }
    }

    private func finishQueuedReferenceImageGeneration(
        item: ReferenceImageQueueItem,
        runID: UUID
    ) {
        guard activeReferenceImageQueueItem?.id == item.id,
              referenceImageGenerationRunID == runID
        else { return }
        imageGenerationProgressTask?.cancel()
        imageGenerationProgressTask = nil
        activeImageGenerator = nil
        referenceImageGenerationTask = nil
        referenceImageGenerationRunID = nil
        activeReferenceImageQueueItem = nil
        inPlaceReferenceGenerationRequirementID = nil
        inPlaceReferenceGenerationKind = nil
        imageGenerationProgress = nil
        isReferenceImageCommitInProgress = false
        startNextReferenceImageJobIfNeeded()
    }

    func chooseGeneratedCandidate(at selectedIndex: Int) async {
        guard let selection = generatedCandidateSelection,
              selection.candidates.indices.contains(selectedIndex),
              referenceImageGenerationTask == nil,
              generatedCandidateImportTask == nil
        else { return }

        let runID = UUID()
        generatedCandidateImportRunID = runID
        isImportingGeneratedCandidate = true
        isReferenceImageCommitInProgress = true
        imageGenerationProgress = .init(stage: .importing)
        referenceImageGenerationErrorMessage = nil
        referenceImageJobStates[selection.requirementID] = .importing
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performGeneratedCandidateImport(
                selection: selection, selectedIndex: selectedIndex, runID: runID
            )
        }
        generatedCandidateImportTask = task
        await task.value
    }

    private func performGeneratedCandidateImport(
        selection: GeneratedCandidateSelectionPresentation,
        selectedIndex: Int,
        runID: UUID
    ) async {
        defer { finishGeneratedCandidateImport(runID: runID) }
        do {
            try requireCurrentCandidateImport(runID)
            let summary = try await session.importGeneratedCandidates(
                requirementID: selection.requirementID,
                from: selection.candidates.map(\.fileURL),
                selectedIndex: selectedIndex,
                context: selection.context,
                metadata: generationMetadata(
                    result: selection.result,
                    settings: selection.settings,
                    selectedIndex: selectedIndex,
                    attachments: selection.attachments,
                    visualAmendment: selection.visualAmendment
                ),
                actor: .human
            )
            // The mutation has committed; reflect it and release disposable candidates
            // before cancellation can suppress app bookkeeping.
            didApply(summary.entry)
            generatedCandidateSelections[selection.requirementID] = nil
            removeGenerationCache(selection.outputDirectoryURL)
            try requireCurrentCandidateImport(runID)
            await refresh()
            try requireCurrentCandidateImport(runID)
            await loadReferenceImageCreationDetail(requirementID: selection.requirementID)
            await loadScenePackageDetail()
            await reloadReferenceGenerationContextOnly()
            referenceImageJobStates[selection.requirementID] = .completed(
                versionID: summary.selectedVersionID
            )
        } catch is CancellationError {
        } catch {
            if generatedCandidateImportRunID == runID {
                referenceImageGenerationErrorMessage = error.localizedDescription
                referenceImageJobStates[selection.requirementID] = .failed(
                    error.localizedDescription
                )
            }
        }
    }

    func cancelGeneratedCandidateSelection() {
        guard isImportingGeneratedCandidate == false,
              let selection = generatedCandidateSelection
        else { return }
        generatedCandidateSelections[selection.requirementID] = nil
        referenceImageJobStates[selection.requirementID] = nil
        referenceImageGenerationErrorMessage = nil
        removeGenerationCache(selection.outputDirectoryURL)
    }

    func cancelReferenceImageGeneration() async {
        let task = referenceImageGenerationTask
        if activeReferenceImageJobIsCommitting {
            // FilmCore's grouped import is the non-cancellable commit phase. Window/sheet
            // close waits for it so the journal and undo registration stay in lockstep.
            await task?.value
            return
        }
        referenceImageDisclosureGate?.resolve(false)
        referenceImageDisclosureGate = nil
        task?.cancel()
        if let activeImageGenerator { await activeImageGenerator.cancel() }
        if let activePromptRun { try? await activePromptRun.cancel() }
        await task?.value
    }

    func cancelAllReferenceImageGeneration() async {
        referenceImageQueue.removeAll()
        await cancelReferenceImageGeneration()
        await cancelGeneratedCandidateImport()
        for selection in generatedCandidateSelections.values {
            removeGenerationCache(selection.outputDirectoryURL)
        }
        generatedCandidateSelections.removeAll()
        referenceImageJobStates.removeAll()
    }

    func cancelGeneratedCandidateImport() async {
        let task = generatedCandidateImportTask
        if isReferenceImageCommitInProgress {
            await task?.value
            return
        }
        generatedCandidateImportRunID = nil
        task?.cancel()
        await task?.value
        generatedCandidateImportTask = nil
        isImportingGeneratedCandidate = false
        if referenceImageGenerationTask == nil { imageGenerationProgress = nil }
    }

    func imageGeneratorStatusMessage(_ status: ImageGeneratorStatus) -> String {
        switch status {
        case .helperUnavailable:
            "The bundled image helper is unavailable. Reinstall Film Camp."
        case let .helperIncompatible(reason):
            reason
        case let .providerNotConfigured(name):
            "Missing image generation API Key for \(name)."
        case let .ready(context):
            context.provider.credentialStatusLabel
        }
    }

    private func initializeReferencePromptDraft(promptID: UUID, body: String) {
        if referenceImageCreationMode == .edit {
            if referencePromptDraftID != promptID {
                referencePromptDraftID = promptID
                referencePromptDraft = ""
                referencePromptDraftRevision = 0
                referencePromptSavedRevision = 0
            }
            referencePromptValidationMessage = validateReferencePrompt(referencePromptDraft)
            return
        }
        if referencePromptDraftID != promptID {
            referencePromptDraftID = promptID
            referencePromptDraft = body
            referencePromptDraftRevision = 0
            referencePromptSavedRevision = 0
            referencePromptValidationMessage = validateReferencePrompt(body)
        } else if referencePromptSavedRevision == referencePromptDraftRevision,
                  isSavingReferencePrompt == false {
            referencePromptDraft = body
            referencePromptValidationMessage = validateReferencePrompt(body)
        }
    }

    func outfitEditInstruction(title: String, details: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = "Change the character’s outfit to: \(title)."
        return details.isEmpty ? instruction : instruction + "\nAdditional outfit details: " + details
    }

    func outfitEditValidationMessage(title: String, details: String) -> String? {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return "Enter an outfit title."
        }
        return validateReferencePrompt(outfitEditInstruction(title: title, details: details))
    }

    private func validateReferencePrompt(_ body: String) -> String? {
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return referenceImageCreationMode == .edit
                ? "Describe the edit to apply to the current image."
                : "Enter an image prompt before generating."
        }
        if body.lengthOfBytes(using: .utf8) > Self.maximumReferencePromptBytes {
            return "Keep the prompt under 65,536 UTF-8 bytes."
        }
        return nil
    }

    private func beginDebouncedReferencePromptFlush() async {
        referencePromptSaveTask = nil
        _ = await flushReferencePromptDraft()
    }

    private func loadReferenceImageCreationDetail(requirementID: UUID) async {
        guard !isClosed, referenceCreationRequirementID == requirementID else {
            referenceImageCreationDetail = nil
            return
        }
        do {
            referenceImageCreationDetail = try await session.requirement(id: requirementID)
        } catch {
            referenceImageCreationDetail = nil
            referenceImageGenerationErrorMessage = error.localizedDescription
            self.error = .project(error)
        }
    }

    private func reloadReferenceGenerationContextOnly() async {
        guard let requirementID = referenceCreationRequirementID,
              referenceImageCreationDetail?.currentPrompt != nil
        else {
            referenceImageGenerationContext = nil
            return
        }
        do {
            if referenceImageCreationMode == .edit,
               validateReferencePrompt(referencePromptDraft) != nil {
                referenceImageGenerationContext = nil
                return
            }
            let preliminaryContext = try await session
                .referenceImageGenerationContext(
                    requirementID: requirementID,
                    generationPromptBody: nil,
                    includeCurrentImage: referenceIncludesCurrentImage
                )
            let effectivePrompt = providerPromptBody(
                basePrompt: referencePromptDraft,
                context: preliminaryContext
            )
            guard effectivePrompt.lengthOfBytes(using: .utf8)
                <= Self.maximumReferencePromptBytes
            else {
                referenceImageGenerationContext = nil
                referencePromptValidationMessage =
                    "The prompt and current visual direction exceed 65,536 UTF-8 bytes."
                return
            }
            referenceImageGenerationContext = try await session
                .referenceImageGenerationContext(
                    requirementID: requirementID,
                    generationPromptBody: effectivePrompt,
                    includeCurrentImage: referenceIncludesCurrentImage
                )
        } catch {
            referenceImageGenerationContext = nil
            referenceImageGenerationErrorMessage = error.localizedDescription
            self.error = .project(error)
        }
    }

    private func generationReferences(
        for context: ReferenceImageGenerationContext,
        attachments: [ReferenceImageGenerationAttachment],
        in outputDirectory: URL
    ) async throws -> [ImageGenerationReference] {
        let inputs = try await session.referenceImageGenerationInputs(context: context)
        let inputDirectory = outputDirectory.appending(
            path: "references", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: inputDirectory, withIntermediateDirectories: true
        )
        var result: [ImageGenerationReference] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let suffix = input.fileExtension.isEmpty ? "img" : input.fileExtension
            let url = inputDirectory.appending(
                path: String(format: "reference-%02d.%@", index + 1, suffix)
            )
            try input.data.write(to: url, options: .atomic)
            result.append(ImageGenerationReference(
                id: input.requirementID,
                imageURL: url,
                entityKind: input.entityKind
            ))
        }
        for (offset, attachment) in attachments.enumerated() {
            try Task.checkCancellation()
            let suffix = attachment.fileExtension.isEmpty ? "img" : attachment.fileExtension
            let index = inputs.count + offset + 1
            let url = inputDirectory.appending(
                path: String(format: "reference-%02d.%@", index, suffix)
            )
            try attachment.data.write(to: url, options: .atomic)
            result.append(ImageGenerationReference(
                id: attachment.id,
                imageURL: url,
                entityKind: attachment.entityKind
            ))
        }
        return result
    }

    private func generationMetadata(
        result: ImageGenerationResult,
        settings: ImageGenerationSettings,
        selectedIndex: Int,
        attachments: [ReferenceImageGenerationAttachment],
        visualAmendment: ImageGenerationVisualAmendment?
    ) -> ImageGenerationCommitMetadata {
        ImageGenerationCommitMetadata(
            providerID: result.providerID,
            modelID: result.modelID,
            helperProtocolVersion: result.helperProtocolVersion,
            aspectRatio: settings.aspectRatio.rawValue,
            requestedWidth: result.requestedSize.width,
            requestedHeight: result.requestedSize.height,
            candidateCount: result.candidates.count,
            selectedCandidateIndex: selectedIndex,
            attachments: attachments,
            visualAmendment: visualAmendment
        )
    }

    /// Prompt composition itself does not mutate stored text. Provider requests receive
    /// a deterministic final block where current canonical imagery, current canonical
    /// descriptions, and human edits outrank older prose.
    private func providerPromptBody(
        basePrompt: String,
        context: ReferenceImageGenerationContext,
        mode: ReferenceImageCreationMode? = nil,
        requirementTypeCode: String? = nil
    ) -> String {
        let resolvedMode = mode ?? referenceImageCreationMode
        let resolvedTypeCode = requirementTypeCode ?? referenceImageCreationDetail?.referenceTypeCode
        if resolvedMode == .edit {
            var lines = [
                "EDIT THE SUPPLIED CURRENT IMAGE:",
                "Reference 1 is the current target image. Return that same image with the requested visual change fully implemented.",
                "The request is mandatory and overrides any conflicting detail in the current image. Preserve only details that do not conflict with it.",
                "If the request describes a role, custody status, occupation, era, or dress code, express it through a complete, unmistakable wardrobe change on every applicable depiction. Do not merely add words, logos, badges, labels, numbers, or accessories to the existing clothes unless the request explicitly asks for them.",
                "Do not invent visible writing or insignia as a substitute for the requested visual change.",
                "",
                "REQUESTED CHANGE:",
                basePrompt,
            ]
            if resolvedTypeCode == "full_body" {
                lines.append(contentsOf: [
                    "",
                    "NON-NEGOTIABLE CHARACTER-SHEET STRUCTURE:",
                    "Keep the two figures in their current positions, scale, pose, framing, background, and body. Apply the requested change consistently to both views.",
                    "The left/front figure must remain headless with a clean neckline cutoff and no face.",
                    "The right/rear figure must retain the complete back of the head, ears, neck, and hairstyle, with no face visible.",
                    "Do not add, restore, invent, or reveal a head or face on the front figure.",
                    "Final check: the requested change is fully visible on both figures; left/front has no head; right/rear has the complete back of the head.",
                ])
            }
            return lines.joined(separator: "\n")
        }
        let hasCanonicalCharacterReference = context.orderedDependencies.contains {
            $0.entityKind == .character
        }
        let canonicalDescriptions: [String] = context.orderedDependencies.compactMap {
            dependency -> String? in
            guard dependency.entityKind == .character,
                  let body = dependency.promptBody?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ),
                  body.isEmpty == false
            else { return nil }
            return "\(dependency.requirementName): \(body)"
        }

        // A bundle body update is a continuation of the approved face, not a replay of
        // an independently generated legacy body prompt. Excluding that older prose is
        // intentional: models may follow its obsolete wardrobe even when a later block
        // says the face is authoritative. The editable face prompt supplies the character
        // direction while this fixed instruction supplies only the body-sheet layout.
        if resolvedTypeCode == "full_body",
           canonicalDescriptions.isEmpty == false {
            var lines = [
                "Create one 16:9 character reference sheet on a plain neutral-grey seamless background.",
                "Show two full-length figures side by side at the same scale: a straight-on front body view on the left and a straight-on rear body view on the right.",
                "Only the front figure is headless, with a clean neckline cutoff and no face. The rear figure must include the complete back of the head, ears, neck, and hairstyle as seen from directly behind; do not remove or crop the rear head, and do not show a face in the rear view.",
                "Both figures must be fully visible through the shoes, with neutral posture, matching build, and the exact same wardrobe.",
                "Use the supplied canonical face image and the current character description below as the sole authority for identity, physical appearance, the rear hairstyle, and wardrobe.",
                "The current character description completely replaces any older body wardrobe direction. Do not add a jacket, tie, outer layer, or other garment unless the current description explicitly asks for it.",
                "Do not copy the face reference's framing, crop, pose, composition, or background.",
                "Final layout check: the left/front figure has no head; the right/rear figure has a complete back-of-head and hairstyle.",
                "",
                "CURRENT AUTHORITATIVE CHARACTER DESCRIPTION:",
            ]
            lines.append(contentsOf: canonicalDescriptions)
            if context.activeVisualAmendments.isEmpty == false {
                lines.append(
                    "Apply these human-authored visual amendments, oldest to newest; later amendments win:"
                )
                lines.append(contentsOf: context.activeVisualAmendments.enumerated().map {
                    "\($0.offset + 1). \($0.element.instruction)"
                })
            }
            return lines.joined(separator: "\n")
        }

        guard hasCanonicalCharacterReference || context.activeVisualAmendments.isEmpty == false
        else { return basePrompt }

        var lines = [basePrompt, ""]
        lines.append(
            "CURRENT CANONICAL VISUAL DIRECTION — HIGHER PRIORITY THAN CONFLICTING TEXT ABOVE:"
        )
        if hasCanonicalCharacterReference {
            lines.append(
                "Treat the current canonical reference images as authoritative for visible identity, physical appearance, hair, and wardrobe."
            )
        }
        lines.append(
            "Carry only applicable character appearance details; do not copy source framing, crop, pose, composition, or background."
        )
        if canonicalDescriptions.isEmpty == false {
            lines.append(
                "Use these current canonical character descriptions for applicable appearance and wardrobe details; they override conflicts in the generation prompt above:"
            )
            lines.append(contentsOf: canonicalDescriptions)
        }
        if context.activeVisualAmendments.isEmpty == false {
            lines.append(
                "Apply these human-authored visual amendments, oldest to newest; later amendments win:"
            )
            lines.append(contentsOf: context.activeVisualAmendments.enumerated().map {
                "\($0.offset + 1). \($0.element.instruction)"
            })
        }
        return lines.joined(separator: "\n")
    }

    private func observeImageGenerationProgress(
        _ generator: any ImageGenerating,
        requirementID: UUID
    ) async {
        imageGenerationProgressTask?.cancel()
        let stream = await generator.progress()
        imageGenerationProgressTask = Task { [weak self] in
            for await progress in stream {
                guard let self, Task.isCancelled == false else { return }
                self.imageGenerationProgress = progress
                self.referenceImageJobStates[requirementID] = .generating(progress)
            }
        }
    }

    private func finishGeneratedCandidateImport(runID: UUID) {
        guard generatedCandidateImportRunID == runID else { return }
        generatedCandidateImportTask = nil
        generatedCandidateImportRunID = nil
        isImportingGeneratedCandidate = false
        isReferenceImageCommitInProgress = false
        imageGenerationProgress = nil
    }

    private func requireCurrentImageGenerationRun(_ runID: UUID) throws {
        try Task.checkCancellation()
        guard referenceImageGenerationRunID == runID else { throw CancellationError() }
    }

    private func requireCurrentCandidateImport(_ runID: UUID) throws {
        try Task.checkCancellation()
        guard generatedCandidateImportRunID == runID else { throw CancellationError() }
    }

    private func validateGeneratedCandidates(
        _ candidates: [ImageGenerationCandidate]
    ) async throws {
        let validation = Task.detached(priority: .utility) {
            for candidate in candidates {
                try Task.checkCancellation()
                let data = try Data(contentsOf: candidate.fileURL)
                _ = try AssetPathing.inspectForImport(
                    data, fileName: candidate.fileURL.lastPathComponent
                )
            }
        }
        try await withTaskCancellationHandler {
            try await validation.value
        } onCancel: {
            validation.cancel()
        }
    }

    private func removeGenerationCache(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
        // Remove the now-empty UUID parent when possible; never walk above that exact node.
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }
}

enum ReferenceImageCreationMode: Equatable, Sendable {
    case create
    case regenerate
    case edit
}

enum InPlaceReferenceGenerationKind: Equatable, Sendable {
    case missingReference
    case bodyFromFace
    case regenerate
}

struct ReferenceImageJobState {
    enum Phase {
        case queued
        case waitingForApproval
        case preparingPrompt
        case generating(ImageGenerationProgress?)
        case awaitingSelection
        case importing
        case failed(String)
        case completed(versionID: UUID)
    }

    let phase: Phase

    static let queued = Self(phase: .queued)
    static let waitingForApproval = Self(phase: .waitingForApproval)
    static let preparingPrompt = Self(phase: .preparingPrompt)
    static let awaitingSelection = Self(phase: .awaitingSelection)
    static let importing = Self(phase: .importing)
    static func completed(versionID: UUID) -> Self {
        Self(phase: .completed(versionID: versionID))
    }
    static func generating(_ progress: ImageGenerationProgress?) -> Self {
        Self(phase: .generating(progress))
    }
    static func failed(_ message: String) -> Self {
        Self(phase: .failed(message))
    }

    var completedVersionID: UUID? {
        guard case let .completed(versionID) = phase else { return nil }
        return versionID
    }

    var isBusy: Bool {
        switch phase {
        case .queued, .waitingForApproval, .preparingPrompt, .generating, .importing:
            true
        case .awaitingSelection, .failed, .completed:
            false
        }
    }

    var preventsDuplicate: Bool {
        switch phase {
        case .failed, .completed:
            false
        case .queued, .waitingForApproval, .preparingPrompt, .generating,
             .awaitingSelection, .importing:
            true
        }
    }

    var message: String? {
        switch phase {
        case .queued:
            "Waiting to generate image…"
        case .waitingForApproval:
            "Waiting for approval…"
        case .preparingPrompt:
            "Preparing the image prompt…"
        case let .generating(progress):
            progress?.presentationMessage ?? "Preparing the local generator…"
        case .awaitingSelection:
            "Choose an image to continue."
        case .importing:
            "Adding the image to the project…"
        case let .failed(message):
            message
        case .completed:
            nil
        }
    }
}

struct ReferenceImageQueueItem: Identifiable {
    let id = UUID()
    let requirementID: UUID
    let mode: ReferenceImageCreationMode
    let kind: InPlaceReferenceGenerationKind?
    let candidateCount: Int
    let requestedSettings: ImageGenerationSettings?
    let provider: ImageProviderDescriptor
    let capturedPromptBody: String?
    let attachments: [ReferenceImageGenerationAttachment]
    let prepared: PreparedReferenceImageJob?
}

struct PreparedReferenceImageJob {
    var context: ReferenceImageGenerationContext
    let prompt: String
    let entityName: String
    let requirementName: String
    let requirementTypeCode: String?
    let settings: ImageGenerationSettings
    let attachments: [ReferenceImageGenerationAttachment]
    let visualAmendment: ImageGenerationVisualAmendment?
    let includeCurrentImage: Bool
}

@MainActor
final class ReferenceImageDisclosureGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var resolvedValue: Bool?

    func wait() async -> Bool {
        if let resolvedValue { return resolvedValue }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ value: Bool) {
        guard resolvedValue == nil else { return }
        resolvedValue = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

struct GeneratedCandidateSelectionPresentation: Identifiable {
    let id = UUID()
    let requirementID: UUID
    let context: ReferenceImageGenerationContext
    let entityName: String
    let requirementName: String
    let candidates: [ImageGenerationCandidate]
    let result: ImageGenerationResult
    let settings: ImageGenerationSettings
    let attachments: [ReferenceImageGenerationAttachment]
    let visualAmendment: ImageGenerationVisualAmendment?
    let outputDirectoryURL: URL
}

enum ReferenceImageCreationError: Error, LocalizedError, Sendable {
    case missingCanonicalReference
    case promptChanged
    case canonicalStateChanged
    case bodySlotUnavailable
    case currentImageAlreadyExists
    case currentImageMissing
    case promptUnavailable
    case promptTooLong
    case promptGeneratorUnavailable

    var errorDescription: String? {
        switch self {
        case .missingCanonicalReference:
            "A required canonical reference image is missing or damaged. Restore it before generating this variation."
        case .promptChanged:
            "The prompt changed while generation was being prepared. Try Generate again."
        case .canonicalStateChanged:
            "This reference changed before generation began. Try Generate again."
        case .bodySlotUnavailable:
            "The Headless Full Body slot is no longer available."
        case .currentImageAlreadyExists:
            "This reference already has a current image."
        case .currentImageMissing:
            "This reference no longer has a current image to regenerate."
        case .promptUnavailable:
            "The image prompt could not be prepared."
        case .promptTooLong:
            "The prompt and current visual direction exceed 65,536 UTF-8 bytes."
        case .promptGeneratorUnavailable:
            "Image prompt generation is unavailable."
        }
    }
}

extension ImageGenerationProgress {
    var presentationMessage: String {
        switch stage {
        case .preparing:
            "Preparing the local generator…"
        case let .generating(candidate, total):
            "Generating candidate \(candidate) of \(total)…"
        case let .validating(candidate, total):
            "Validating candidate \(candidate) of \(total)…"
        case let .completed(total):
            "Generated \(total) candidate\(total == 1 ? "" : "s"). Finishing…"
        case .importing:
            "Importing into the project…"
        }
    }
}
