import AppKit
import FilmBrain
import FilmCore
import SwiftUI

/// One focused workflow for prompt preparation, local generation, and candidate choice.
/// Missing reference detail embeds it beneath the preview; filled-reference iteration
/// presents the same workflow modally. Canonical reads and mutations remain on the window
/// model/FilmCore boundary.
struct ReferenceImageCreationSheet: View {
    enum PresentationStyle {
        case sheet
        case inline
    }

    enum EditFocus {
        case general
        case outfit
    }

    @Bindable var model: ProjectWindowModel
    let reference: ScenePlannedReference
    let mode: ReferenceImageCreationMode
    var presentationStyle: PresentationStyle = .sheet
    var editFocus: EditFocus = .general

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ImageGeneratorPreferences.providerIDKey) private var providerID =
        ImageProviderDescriptor.googleNanoBanana2.id
    @State private var outfitName = ""
    @State private var outfitDetails = ""
    @State private var outfitSceneID: UUID?
    @State private var createdOutfitRequirementID: UUID?
    @State private var isCreatingOutfit = false
    private var workingRequirementID: UUID { createdOutfitRequirementID ?? reference.requirementID }

    @State private var candidateCount = 1
    @State private var generationStarted = false
    @State private var isClosing = false
    @State private var credentialModel = ImageGeneratorSettingsModel()
    @State private var credentialProviderID = ImageProviderDescriptor.googleNanoBanana2.id
    @State private var apiKey = ""
    @State private var isShowingAPIKeyEntry = false
    @State private var attachmentThumbnail: NSImage?
    @State private var isReferenceImageDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if presentationStyle == .sheet {
                header
                Divider()
            }

            generationError

            if editFocus == .outfit {
                outfitSummary
            }

            if model.referenceImageCreationDetail?.currentPrompt == nil, editFocus != .outfit {
                promptPreparation
            } else if mode == .edit {
                promptEditor
                if editFocus == .outfit {
                    Text("Create Outfit for Scene sends a copy of the current body image, its reference inputs, and your instruction to \(model.referenceImageProvider.displayName). This makes one provider request and may incur charges.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    generatorStatus
                }
                if let selection = model.generatedCandidateSelection {
                    candidateChooser(selection)
                } else {
                    editSubmitButton
                }
                generationProgress
            } else if let selection = model.generatedCandidateSelection {
                promptEditor
                candidateChooser(selection)
                generationProgress
            } else {
                promptEditor
                generationOptions
                dependencySummary
                generatorStatus
                generationProgress
            }

            if presentationStyle == .sheet, mode != .edit {
                Spacer(minLength: 0)
            }
            if mode != .edit {
                footer
            }
        }
        .padding(presentationStyle == .sheet ? 22 : 16)
        .frame(
            minWidth: presentationStyle == .sheet ? 680 : nil,
            idealWidth: presentationStyle == .sheet ? 760 : nil,
            minHeight: presentationStyle == .sheet ? 560 : nil,
            idealHeight: presentationStyle == .sheet ? 650 : nil,
            alignment: .topLeading
        )
        .overlay {
            if isReferenceImageDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.08))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7]))
                    Label("Drop image reference", systemImage: "photo.badge.plus")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                }
                .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard mode != .edit,
                  generationControlsAreDisabled == false,
                  let url = urls.first(where: ProjectWindowModel.acceptsDroppedImage)
            else { return false }
            Task { await model.attachReferenceImageGenerationAttachment(from: url) }
            return true
        } isTargeted: { isTargeted in
            isReferenceImageDropTargeted = isTargeted
                && mode != .edit
                && generationControlsAreDisabled == false
        }
        .interactiveDismissDisabled(isCreatingOutfit)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            presentationStyle == .sheet
                ? "referenceImage.creationSheet"
                : "referenceImage.inlineWorkflow"
        )
        .task(id: reference.requirementID) {
            outfitSceneID = model.selectedPackageSceneID
            credentialProviderID = providerID
            if presentationStyle == .sheet,
               model.referenceCreationRequirementID != reference.requirementID {
                await model.beginReferenceImageCreation(
                    requirementID: reference.requirementID,
                    mode: mode,
                    automaticallyPreparePrompt: false
                )
            }
            await credentialModel.refresh(provider: appWideProvider)
        }
        .task(id: model.referenceImageGenerationAttachment?.id) {
            guard let data = model.referenceImageGenerationAttachment?.data else {
                attachmentThumbnail = nil
                return
            }
            attachmentThumbnail = await Task.detached(priority: .utility) {
                NSImage(data: data)
            }.value
        }
        .onChange(of: model.referenceImageCreationDetail?.currentPrompt?.id) {
            guard model.referenceImageCreationDetail?.currentPrompt != nil else { return }
            Task { await model.refreshReferenceImageCreationContext() }
        }
        .onChange(of: completedVersionID) {
            guard generationStarted,
                  completedVersionID != nil
            else { return }
            if presentationStyle == .sheet {
                close()
            }
        }
        .onChange(of: providerID) {
            Task {
                await credentialModel.refresh(provider: appWideProvider)
                await model.refreshReferenceImageGeneratorStatus()
            }
        }
        .onDisappear {
            guard isClosing == false else { return }
            Task { await model.endReferenceImageCreation() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sheetTitle).font(.title2.bold())
                Text("\(reference.entityName) — \(reference.requirementName)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .disabled(
                model.referenceImageJobIsImporting(for: workingRequirementID)
                    || model.isRemovingReferencePrompt
            )
            .disabled(isCreatingOutfit)
            .accessibilityLabel("Close")
        }
    }

    private var outfitSummary: some View {
        HStack(alignment: .top, spacing: 16) {
            if let version = model.referenceImageCreationDetail?.versions.first(
                where: { $0.status == .approved }
            ) {
                ReferenceVersionImage(
                    model: model,
                    version: version,
                    size: .card,
                    minimumHeight: 110
                )
                .frame(width: 196, height: 110)
                .clipped()
                .accessibilityLabel("Current body reference")
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("Outfit title, e.g. Bathrobe", text: $outfitName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(createdOutfitRequirementID != nil || isCreatingOutfit)
                    .accessibilityLabel("Outfit title")
                    .accessibilityIdentifier("referenceImage.outfitName")
                Text("A title is all you need")
                    .font(.headline)
                Text("Add details below if you want a specific color, fabric, or fit. The character’s build, hair, pose, and face reference stay the same.")
                Text("Creates a new bundle for this scene. The original outfit and other scenes stay unchanged. You can reuse either bundle from Choose Character Bundle.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("referenceImage.outfitSummary")
    }

    private var missingPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let progress = model.promptProgress, model.activePromptRun != nil {
                ProgressView()
                Text(progress.message).font(.callout).foregroundStyle(.secondary)
            } else {
                Label("An image prompt is needed first.", systemImage: "text.badge.plus")
                    .font(.headline)
                Text("Film Camp will build it from this reference and its canonical dependencies. You can edit it before generating the image.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Generate Prompt") {
                    Task { await model.preparePromptRun() }
                }
                .disabled(promptWorkflowIsPending)
                .accessibilityIdentifier("referenceImage.generatePrompt")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Prompt preparation keeps the one-time disclosure and edited-prompt warning inside
    /// this workflow. Missing detail starts preparation automatically; this retry surface
    /// remains available if preparation was cancelled or could not start.
    @ViewBuilder
    private var promptPreparation: some View {
        if model.pendingPromptRegenerateConfirm != nil {
            inlinePromptWorkflow {
                PromptRegenerateConfirmSheet {
                    Task { await model.continueAfterRegenerateConfirm() }
                } cancelAction: {
                    model.cancelPreparedPromptRun()
                }
            }
        } else if model.pendingPromptDisclosure != nil {
            inlinePromptWorkflow {
                PromptDisclosureSheet {
                    Task { await model.continueAfterPromptDisclosure() }
                } cancelAction: {
                    model.cancelPreparedPromptRun()
                }
            }
        } else {
            inlinePromptWorkflow { missingPrompt }
        }
    }

    private func inlinePromptWorkflow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("referenceImage.promptPreparation")
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editFocus == .outfit {
                Text("Details (optional)").font(.headline)
            }
            if mode != .edit {
                HStack {
                    Text("Image Prompt").font(.headline)
                    referenceImageAttachmentSlot
                    Spacer()
                    if model.isSavingReferencePrompt {
                        ProgressView().controlSize(.small)
                        Text("Saving…").font(.caption).foregroundStyle(.secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    Button {
                        model.copyReferencePrompt()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy prompt")
                    .accessibilityLabel("Copy image prompt")
                    .accessibilityIdentifier("referenceImage.copyPrompt")
                    Button(role: .destructive) {
                        Task { await model.removeReferencePrompt() }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove prompt")
                    .disabled(
                        model.isSavingReferencePrompt
                            || model.isRemovingReferencePrompt
                            || model.referenceImageJobIsBusy(
                                for: workingRequirementID
                            )
                    )
                    .accessibilityLabel("Remove image prompt")
                    .accessibilityIdentifier("referenceImage.removePrompt")
                }
            }
            ZStack(alignment: .topLeading) {
                if mode == .edit,
                   promptBinding.wrappedValue.isEmpty {
                    Text(editFocus == .outfit
                         ? "For example: White cotton, tied at the waist, with slippers."
                         : "Describe only what should change, such as “Make her hair more feminine” or “Change her shirt to a button-down with no tie or jacket.”")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: promptBinding)
                    .disabled(isCreatingOutfit || generationControlsAreDisabled)
                    .font(mode == .edit ? .body : .body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(6)
            }
            .frame(minHeight: mode == .edit ? 110 : 170)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10)))
            .accessibilityLabel(editFocus == .outfit ? "Outfit details, optional" : mode == .edit ? "Edit instruction" : "Image prompt")
            .accessibilityIdentifier(
                mode == .edit
                    ? "referenceImage.editInstruction"
                    : "referenceImage.promptEditor"
            )

            if editFocus == .outfit,
               outfitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
               let message = model.outfitEditValidationMessage(title: outfitName, details: outfitDetails) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if mode != .edit,
               let message = model.referencePromptValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var editSubmitButton: some View {
        HStack {
            Spacer()
            Button(editFocus == .outfit ? (createdOutfitRequirementID == nil ? "Create Outfit for Scene" : "Retry Outfit Edit") : "Submit Edit") {
                Task {
                    if editFocus == .outfit {
                        model.updateReferencePromptDraft(
                            model.outfitEditInstruction(title: outfitName, details: outfitDetails)
                        )
                    }
                    if editFocus == .outfit, createdOutfitRequirementID == nil {
                        guard let sceneID = outfitSceneID else { return }
                        isCreatingOutfit = true
                        let createdID = await model.createSceneCharacterOutfit(
                            sourceRequirementID: reference.requirementID,
                            sceneID: sceneID, name: outfitName
                        )
                        isCreatingOutfit = false
                        guard let createdID else { return }
                        createdOutfitRequirementID = createdID
                    }
                    generationStarted = true
                    await model.generateReferenceImages(candidateCount: 1)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(outfitSubmitIsDisabled)
            .help(editFocus == .outfit ? "Create and generate an outfit for this scene" : model.referenceImageGenerationDisabledReason ?? "Submit this edit")
            .accessibilityIdentifier("referenceImage.generate")
        }
    }

    private var outfitSubmitIsDisabled: Bool {
        if editFocus == .outfit {
            return isCreatingOutfit || outfitSceneID == nil
                || model.outfitEditValidationMessage(title: outfitName, details: outfitDetails) != nil
                || model.referenceImageJobState(for: workingRequirementID)?.preventsDuplicate == true
                || model.imageGeneratorStatus == nil
        }
        return model.referenceImageGenerationDisabledReason != nil
    }

    private var generationOptions: some View {
        VStack(alignment: .leading, spacing: 7) {
            if mode == .regenerate {
                Toggle(
                    "Include current image as reference",
                    isOn: Binding(
                        get: { model.referenceIncludesCurrentImage },
                        set: { model.setReferenceIncludesCurrentImage($0) }
                    )
                )
                .accessibilityIdentifier("referenceImage.includeCurrent")
            }

            HStack(spacing: 18) {
                Stepper("Images: \(candidateCount)", value: $candidateCount, in: 1...4)
                    .accessibilityIdentifier("referenceImage.candidateCount")
                if let settings = model.referenceImageGenerationSettings {
                    Text("Using \(model.referenceImageProvider.displayName) · \(settings.aspectRatio.rawValue) · 1K")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("Generate sends this \(mode == .edit ? "edit instruction" : "prompt") and the canonical images listed below directly to \(model.referenceImageProvider.displayName) using your API key. This makes \(candidateCount) provider request\(candidateCount == 1 ? "" : "s") and may incur charges.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var referenceImageAttachmentSlot: some View {
        ZStack(alignment: .trailing) {
            Button {
                Task { await model.chooseReferenceImageGenerationAttachment() }
            } label: {
                if let attachment = model.referenceImageGenerationAttachment {
                    HStack(spacing: 6) {
                        Group {
                            if let attachmentThumbnail {
                                Image(nsImage: attachmentThumbnail)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 24, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(attachment.originalFileName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.trailing, 22)
                } else {
                    Text("+ Add or drop image")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 156, height: 28)
            .disabled(generationControlsAreDisabled)
            .help(
                model.referenceImageGenerationAttachment == nil
                    ? "Add an image to guide this generation"
                    : "Replace the image reference"
            )
            .accessibilityIdentifier("referenceImage.attachReference")

            if model.referenceImageGenerationAttachment != nil {
                Button {
                    model.removeReferenceImageGenerationAttachment()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(generationControlsAreDisabled)
                .help("Remove image reference")
                .accessibilityLabel("Remove image reference")
                .accessibilityIdentifier("referenceImage.removeAttachment")
                .padding(.trailing, 6)
            }
        }
        .frame(width: 156, height: 28)
    }

    @ViewBuilder
    private var dependencySummary: some View {
        if let context = model.referenceImageGenerationContext,
           context.orderedDependencies.isEmpty == false {
            VStack(alignment: .leading, spacing: 5) {
                Text("Image references").font(.subheadline.weight(.medium))
                ForEach(context.orderedDependencies) { dependency in
                    Label(dependency.requirementName, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var generatorStatus: some View {
        if let status = model.imageGeneratorStatus {
            switch status {
            case .providerNotConfigured:
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Label(
                            "Missing image generation API Key",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("referenceImage.generatorStatus")

                        Button("Add API Key") {
                            credentialProviderID = providerID
                            apiKey = ""
                            isShowingAPIKeyEntry = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("referenceImage.addAPIKey")
                    }
                    if isShowingAPIKeyEntry {
                        inlineAPIKeyEntry
                    }
                }
            case let .ready(context):
                configuredCredentialLabel(context.provider)
            case .helperUnavailable, .helperIncompatible:
                VStack(alignment: .leading, spacing: 6) {
                    if credentialProviderID == providerID,
                       credentialModel.isConfigured {
                        configuredCredentialLabel(appWideProvider)
                    }
                    HStack {
                        Label(
                            model.imageGeneratorStatusMessage(status),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("referenceImage.generatorStatus")
                        SettingsLink { Text("Open Settings") }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var inlineAPIKeyEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Provider", selection: $credentialProviderID) {
                ForEach(ImageProviderCatalog.builtIn) { provider in
                    Text(provider.displayName).tag(provider.id)
                }
            }
            .accessibilityIdentifier("referenceImage.apiKeyProvider")

            if credentialModel.isConfigured {
                configuredCredentialLabel(credentialProvider)
            }

            SecureField(
                credentialModel.isConfigured ? "Enter a replacement API key" : "Enter API key",
                text: $apiKey
            )
            .textContentType(.password)
            .accessibilityLabel("API key")
            .accessibilityIdentifier("referenceImage.apiKeyField")

            HStack {
                if credentialModel.isConfigured,
                   apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Use \(credentialProvider.displayName)") {
                        Task { await useConfiguredProvider() }
                    }
                    .disabled(credentialModel.isWorking)
                    .accessibilityIdentifier("referenceImage.useConfiguredProvider")
                } else {
                    Button(credentialModel.isConfigured ? "Replace API Key" : "Add API Key") {
                        Task { await saveInlineAPIKey() }
                    }
                    .disabled(
                        credentialModel.isWorking
                            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityIdentifier("referenceImage.saveAPIKey")
                }

                Button("Cancel", role: .cancel) {
                    apiKey = ""
                    credentialProviderID = providerID
                    isShowingAPIKeyEntry = false
                }
                .disabled(credentialModel.isWorking)

                if credentialModel.isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Link("Get an API key", destination: credentialProvider.credentialHelpURL)
            }

            if let message = credentialModel.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("The key is stored only in this Mac’s Keychain and is never shown again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.10)))
        .task(id: credentialProviderID) {
            apiKey = ""
            await credentialModel.refresh(provider: credentialProvider)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("referenceImage.apiKeyEntry")
    }

    private func configuredCredentialLabel(
        _ provider: ImageProviderDescriptor
    ) -> some View {
        Label(provider.credentialStatusLabel, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(.green)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("referenceImage.apiKeyConfigured")
    }

    @ViewBuilder
    private var generationProgress: some View {
        if model.referenceImageJobIsBusy(for: workingRequirementID),
           let message = model.referenceImageJobProgressMessage(
               for: workingRequirementID
           ) {
            HStack(spacing: 10) {
                ProgressView()
                Text(message)
                    .font(.callout)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer()
                if model.inPlaceReferenceGenerationRequirementID
                    == workingRequirementID,
                   model.activeReferenceImageJobIsCommitting == false {
                    Button("Cancel", role: .cancel) {
                        Task { await model.cancelReferenceImageGeneration() }
                    }
                    .accessibilityIdentifier("referenceImage.cancelGeneration")
                }
            }
        }
    }

    @ViewBuilder
    private var generationError: some View {
        if let message = model.referenceImageGenerationErrorMessage
            ?? model.referenceImageJobError(for: workingRequirementID) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.24))
                )
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("referenceImage.generationError")
        }
    }

    private func candidateChooser(
        _ selection: GeneratedCandidateSelectionPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if selection.candidates.count > 1 {
                Text("Choose the current image").font(.headline)
                Text("The image you choose becomes current. The others are kept in Archived Images.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(Array(selection.candidates.enumerated()), id: \.element.id) { index, candidate in
                    VStack(spacing: 8) {
                        CandidateImagePreview(url: candidate.fileURL)
                        Button(
                            selection.candidates.count == 1
                                ? "Use This Image"
                                : "Use Image \(index + 1)"
                        ) {
                            generationStarted = true
                            Task { await model.chooseGeneratedCandidate(at: index) }
                        }
                        .disabled(
                            model.referenceImageJobIsImporting(
                                for: workingRequirementID
                            )
                                || model.referenceImageGenerationTask != nil
                        )
                        .accessibilityIdentifier("referenceImage.chooseCandidate.\(index + 1)")
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.generatedCandidateSelection != nil {
                Button("Discard Results", role: .cancel) {
                    model.cancelGeneratedCandidateSelection()
                }
                .disabled(
                    model.referenceImageJobIsImporting(for: workingRequirementID)
                )
                .accessibilityIdentifier("referenceImage.discardCandidates")
            }
            Spacer()
            if presentationStyle == .sheet {
                Button("Done") { close() }
                    .disabled(
                        model.referenceImageJobIsImporting(for: workingRequirementID)
                            || model.isRemovingReferencePrompt
                    )
            }
            if model.referenceImageCreationDetail?.currentPrompt != nil,
               model.generatedCandidateSelection == nil {
                Button(generateButtonTitle) {
                    generationStarted = true
                    Task { await model.generateReferenceImages(candidateCount: candidateCount) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.referenceImageGenerationDisabledReason != nil)
                .help(model.referenceImageGenerationDisabledReason ?? "Generate with the local image generator")
                .accessibilityIdentifier("referenceImage.generate")
            }
        }
    }

    private var promptWorkflowIsPending: Bool {
        model.referenceImageGenerationTask != nil
            || model.pendingPromptRegenerateConfirm != nil
            || model.pendingPromptDisclosure != nil
            || model.preparedPromptRun != nil
            || model.activePromptRun != nil
    }

    private var sheetTitle: String {
        if editFocus == .outfit { return "Change Outfit" }
        return switch mode {
        case .create: "Create Reference Image"
        case .regenerate: "Regenerate Reference Image"
        case .edit: "Edit Reference Image"
        }
    }

    private var generateButtonTitle: String {
        if mode == .edit { return candidateCount == 1 ? "Generate Edit" : "Generate Edits" }
        return candidateCount == 1 ? "Generate Image" : "Generate Images"
    }

    private var promptBinding: Binding<String> {
        if editFocus == .outfit { return $outfitDetails }
        return Binding(
            get: { model.referencePromptDraft },
            set: { model.updateReferencePromptDraft($0) }
        )
    }

    private var generationControlsAreDisabled: Bool {
        model.referenceImageJobState(for: workingRequirementID)?.preventsDuplicate == true
    }

    private var completedVersionID: UUID? {
        model.referenceImageJobState(for: workingRequirementID)?.completedVersionID
    }

    private var appWideProvider: ImageProviderDescriptor {
        ImageProviderCatalog.provider(id: providerID) ?? .googleNanoBanana2
    }

    private var credentialProvider: ImageProviderDescriptor {
        ImageProviderCatalog.provider(id: credentialProviderID) ?? .googleNanoBanana2
    }

    private func saveInlineAPIKey() async {
        let provider = credentialProvider
        guard await credentialModel.save(apiKey, provider: provider) else { return }
        apiKey = ""
        providerID = provider.id
        await model.refreshReferenceImageGeneratorStatus()
        isShowingAPIKeyEntry = false
    }

    private func useConfiguredProvider() async {
        guard credentialModel.isConfigured else { return }
        providerID = credentialProvider.id
        await model.refreshReferenceImageGeneratorStatus()
        isShowingAPIKeyEntry = false
    }

    private func close() {
        guard isClosing == false, isCreatingOutfit == false,
              model.referenceImageJobIsImporting(for: workingRequirementID) == false,
              model.isRemovingReferencePrompt == false
        else { return }
        isClosing = true
        Task {
            await model.endReferenceImageCreation()
            dismiss()
        }
    }
}

private struct CandidateImagePreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 240)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .task(id: url) {
            image = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        }
    }
}
