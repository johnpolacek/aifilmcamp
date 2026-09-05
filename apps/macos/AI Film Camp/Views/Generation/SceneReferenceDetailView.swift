import AppKit
import FilmCore
import SwiftUI

/// Plan 026's focused reference workspace. It consumes the existing RequirementDetail and
/// scene-plan reads; every mutation still crosses the window model into FilmCore.
struct SceneReferenceDetailView: View {
    let model: ProjectWindowModel
    let reference: ScenePlannedReference
    let detail: RequirementDetail
    let generateBodyReference: ScenePlannedReference?

    @State private var deletionTarget: AssetVersion?
    @State private var isEditingImage = false
    @State private var basePromptDraft = ""
    @State private var basePromptDraftID: UUID?
    @State private var isSavingBasePrompt = false

    private var currentVersion: AssetVersion? {
        detail.versions.first { $0.status == .approved }
    }

    private var archivedVersions: [AssetVersion] {
        model.selectedReferenceArchivedVersions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        currentImage
                            .frame(minWidth: 360, maxWidth: .infinity)
                            .frame(height: 360)
                        informationColumn
                            .frame(width: 310, height: 360, alignment: .topLeading)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        currentImage.frame(height: 360)
                        informationColumn.frame(height: 360)
                    }
                }
                if model.generatedCandidateSelection(for: reference.requirementID) != nil {
                    candidateSelectionWorkspace
                } else if currentVersion == nil {
                    generationWorkspace
                } else {
                    promptSection
                }
                archiveSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 16)
        }
        .background(CampAppearance.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sceneReference.detail")
        .task(id: detail.currentPrompt?.id) {
            synchronizeBasePromptDraft(force: true)
        }
        .onChange(of: detail.currentPrompt?.body) { _, _ in
            synchronizeBasePromptDraft(force: false)
        }
        .onChange(of: currentVersion?.id) { oldValue, newValue in
            guard isEditingImage,
                  oldValue != nil,
                  newValue != oldValue,
                  model.generatedCandidateSelection == nil
            else { return }
            isEditingImage = false
        }
        .confirmationDialog(
            "Delete this archived image permanently?",
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if $0 == false { deletionTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletionTarget
        ) { version in
            Button("Delete Permanently", role: .destructive) {
                Task { await model.deleteArchivedWorkspaceReference(version) }
            }
            .accessibilityIdentifier("sceneReference.confirmDeleteArchived")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the image from the project and cannot be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.closeReferenceDetail()
            } label: {
                Label("Back to Scene", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("sceneReference.back")

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(detail.entity.name)
                    .textSelection(.enabled)
                Spacer(minLength: 18)
                Text(detail.requirement.name)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .font(CampAppearance.title(26))
            .frame(maxWidth: .infinity)
        }
    }

    private var currentImage: some View {
        Group {
            if let currentVersion {
                Button {
                    model.presentReferenceImage(
                        currentVersion,
                        accessibilityLabel: "Current image for \(detail.entity.name), \(detail.requirement.name)"
                    )
                } label: {
                    ReferenceVersionImage(
                        model: model,
                        version: currentVersion,
                        size: .expanded,
                        minimumHeight: 360
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sceneReference.currentImage")
                .accessibilityLabel(
                    "Open current image for \(detail.entity.name), \(detail.requirement.name)"
                )
            } else {
                ContentUnavailableView(
                    "Missing Image",
                    systemImage: "photo.badge.plus",
                    description: Text("Upload an image or generate one from the saved prompt.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: CampAppearance.radius))
                .accessibilityIdentifier("sceneReference.missingImage")
            }
        }
    }

    @ViewBuilder
    private var informationColumn: some View {
        if isEditingImage {
            editWorkspace
        } else {
            VStack(alignment: .leading, spacing: 14) {
                statusLine
                Divider()
                metadataRow("Reference class", reference.class.rawValue)
                metadataRow("Role", reference.attributes.role)
                Divider()
                actions
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .campPanel()
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Label(
                currentVersion == nil ? "Missing" : "Current",
                systemImage: currentVersion == nil ? "photo.badge.exclamationmark" : "checkmark.circle.fill"
            )
            .foregroundStyle(currentVersion == nil ? Color.orange : Color.green)
            Spacer()
            Text(reference.designator.map { "@Image \($0)" } ?? "No designator")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("sceneReference.status")
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if currentVersion != nil {
                if let body = generateBodyReference {
                    Button(
                        body.isSatisfied ? "Update Body from Face" : "Generate Body from Face"
                    ) {
                        Task {
                            guard await saveBasePromptIfNeeded() else { return }
                            model.closeReferenceDetail()
                            await model.generateBodyFromFace(
                                requirementID: body.requirementID
                            )
                        }
                    }
                    .buttonStyle(CampPrimaryButtonStyle())
                    .accessibilityIdentifier("sceneReference.generateBodyFromFace")
                }
                if detail.requirement.outfitSourceVersionID != nil {
                    Text("Editing this saved outfit updates every scene using it. Use Change Outfit on the bundle to create a separate look.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Edit Image…") {
                    isEditingImage = true
                }
                .accessibilityIdentifier("sceneReference.editImage")
                Button("Archive Image", role: .destructive) {
                    Task {
                        await model.archiveWorkspaceReference(
                            requirementID: reference.requirementID
                        )
                    }
                }
                .accessibilityIdentifier("sceneReference.archiveCurrent")
            }
            Button("Remove from Scene", role: .destructive) {
                Task {
                    await model.removeReferenceFromCurrentScene(
                        requirementID: reference.requirementID
                    )
                }
            }
            .help("Remove this image reference from this scene. You can undo this change.")
            .accessibilityIdentifier("sceneReference.removeFromScene")
        }
    }

    private var editWorkspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edit Image")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                    }
                Spacer()
                Button("Cancel") {
                    isEditingImage = false
                }
                .disabled(
                    model.referenceImageJobIsImporting(for: reference.requirementID)
                )
                .padding(.trailing, 14)
            }
            .background(Color.primary.opacity(0.025))

            Divider()

            ScrollView {
                ReferenceImageCreationSheet(
                    model: model,
                    reference: reference,
                    mode: .edit,
                    presentationStyle: .inline
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .campPanel()
        .clipShape(RoundedRectangle(cornerRadius: CampAppearance.radius))
        .task(id: reference.requirementID) {
            await model.beginReferenceImageCreation(
                requirementID: reference.requirementID,
                mode: .edit
            )
        }
    }

    private var generationWorkspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("Generate from Prompt")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                    }

                Spacer()

                Button {
                    Task {
                        await model.chooseAndMakeWorkspaceReferenceCurrent(
                            requirementID: reference.requirementID
                        )
                    }
                } label: {
                    Label("Upload Image", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("sceneReference.upload")
                .padding(.trailing, 14)
            }
            .background(Color.primary.opacity(0.025))

            Divider()

            ReferenceImageCreationSheet(
                model: model,
                reference: reference,
                mode: .create,
                presentationStyle: .inline
            )
        }
        .campPanel()
        .clipShape(RoundedRectangle(cornerRadius: CampAppearance.radius))
    }

    private var candidateSelectionWorkspace: some View {
        ReferenceImageCreationSheet(
            model: model,
            reference: reference,
            mode: .regenerate,
            presentationStyle: .inline
        )
        .campPanel()
        .clipShape(RoundedRectangle(cornerRadius: CampAppearance.radius))
    }

    @ViewBuilder
    private var promptSection: some View {
        if detail.currentPrompt != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CampSectionLabel("Base Image Prompt")
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(basePromptDraft, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy base image prompt")
                    .accessibilityIdentifier("sceneReference.copyPrompt")
                    .accessibilityLabel("Copy base image prompt")
                }
                TextEditor(text: $basePromptDraft)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: CampAppearance.radius))
                    .accessibilityIdentifier("sceneReference.prompt")

                Text(
                    "This reusable prompt guides regeneration and bundle updates. Current approved images and human visual changes still override conflicting details."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(
                    "Regenerate sends this prompt and its canonical reference images directly to \(model.referenceImageProvider.displayName) using your API key. This makes 1 provider request and may incur charges."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let validation = basePromptValidationMessage {
                    Label(validation, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if basePromptIsDirty {
                    HStack {
                        Spacer()
                        Button(isSavingBasePrompt ? "Saving…" : "Save Prompt") {
                            Task { _ = await saveBasePromptIfNeeded() }
                        }
                        .buttonStyle(CampPrimaryButtonStyle())
                        .disabled(isSavingBasePrompt || basePromptValidationMessage != nil)
                        .accessibilityIdentifier("sceneReference.savePrompt")
                    }
                }

                if detail.visualAmendments.isEmpty == false {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Current Visual Changes")
                            .font(.subheadline.weight(.semibold))
                        ForEach(detail.visualAmendments) { amendment in
                            Label(amendment.instruction, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.accentColor.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: CampAppearance.radius)
                    )
                    .accessibilityIdentifier("sceneReference.visualAmendments")
                }

                if model.referenceImageJobIsBusy(for: reference.requirementID) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            model.referenceImageJobProgressMessage(
                                for: reference.requirementID
                            ) ?? "Preparing image generation…"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.inPlaceReferenceGenerationRequirementID
                            == reference.requirementID {
                            Button("Cancel") {
                                Task { await model.cancelInPlaceReferenceGeneration() }
                            }
                            .disabled(model.activeReferenceImageJobIsCommitting)
                            .accessibilityIdentifier("sceneReference.cancelRegeneration")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("sceneReference.regenerationProgress")
                } else {
                    HStack {
                        Spacer()
                        Button("Regenerate from Prompt") {
                            Task {
                                guard await saveBasePromptIfNeeded() else { return }
                                await model.regenerateWorkspaceReference(
                                    requirementID: reference.requirementID
                                )
                            }
                        }
                        .disabled(
                            isSavingBasePrompt
                                || basePromptValidationMessage != nil
                                || model.referenceImageJobState(
                                    for: reference.requirementID
                                )?.preventsDuplicate == true
                        )
                        .accessibilityIdentifier("sceneReference.regenerate")
                    }
                }

                if let message = model.referenceImageJobError(
                    for: reference.requirementID
                ) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sceneReference.regenerationError")
                }
            }
        }
    }

    private var basePromptIsDirty: Bool {
        guard let prompt = detail.currentPrompt else { return false }
        return basePromptDraft != prompt.body
    }

    private var basePromptValidationMessage: String? {
        if basePromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter an image prompt."
        }
        if basePromptDraft.lengthOfBytes(using: .utf8) > 65_536 {
            return "Keep the prompt under 65,536 UTF-8 bytes."
        }
        return nil
    }

    private func synchronizeBasePromptDraft(force: Bool) {
        guard let prompt = detail.currentPrompt else {
            basePromptDraft = ""
            basePromptDraftID = nil
            return
        }
        guard force || basePromptDraftID != prompt.id || basePromptIsDirty == false else {
            return
        }
        basePromptDraft = prompt.body
        basePromptDraftID = prompt.id
    }

    @MainActor
    private func saveBasePromptIfNeeded() async -> Bool {
        guard basePromptValidationMessage == nil else { return false }
        guard basePromptIsDirty else { return true }
        isSavingBasePrompt = true
        defer { isSavingBasePrompt = false }
        let saved = await model.saveWorkspaceReferencePromptBody(
            requirementID: reference.requirementID,
            body: basePromptDraft
        )
        return saved
    }

    @ViewBuilder
    private var archiveSection: some View {
        if archivedVersions.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                CampSectionLabel("Archived Images")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(archivedVersions) { version in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                model.presentReferenceImage(
                                    version,
                                    accessibilityLabel: "Archived image version \(version.versionNumber) for \(detail.entity.name), \(detail.requirement.name)"
                                )
                            } label: {
                                ReferenceVersionImage(
                                    model: model,
                                    version: version,
                                    size: .card,
                                    minimumHeight: 150
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("sceneReference.archivedImage.\(version.id.uuidString.prefix(8))")
                            Text("Version \(version.versionNumber)")
                                .font(.caption.weight(.medium))
                            HStack {
                                Button("Restore") {
                                    Task { await model.restoreWorkspaceReference(version) }
                                }
                                .accessibilityIdentifier("sceneReference.restore.\(version.id.uuidString.prefix(8))")
                                Button(role: .destructive) {
                                    deletionTarget = version
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("sceneReference.deleteArchived.\(version.id.uuidString.prefix(8))")
                                .accessibilityLabel("Delete archived version \(version.versionNumber) permanently")
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: CampAppearance.radius))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sceneReference.archives")
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }
}

/// One validated, bounded decode used by detail, archive cards, and the lightbox.
struct ReferenceVersionImage: View {
    let model: ProjectWindowModel
    let version: AssetVersion
    let size: AssetPreviewLoader.PreviewSize
    let minimumHeight: CGFloat

    @State private var image: NSImage?
    @State private var damage: String?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let damage {
                ContentUnavailableView(damage, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: CampAppearance.radius))
        .clipShape(RoundedRectangle(cornerRadius: CampAppearance.radius))
        .task(id: "\(version.relativePath.rawValue)-\(size.rawValue)") {
            let containment = model.mediaContainment
            let loaded = await Task.detached(priority: .utility) {
                AssetPreviewLoader.load(
                    containment: containment, version: version, size: size
                )
            }.value
            damage = loaded.damage
            image = loaded.thumbnailPNG.flatMap(NSImage.init(data:))
        }
    }
}

/// Root-level viewer: no file URL, Quick Look, or raw decode path exists here.
struct SceneReferenceLightbox: View {
    let model: ProjectWindowModel
    let presentation: ReferenceImageLightboxPresentation

    @FocusState private var closeFocused: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.94).ignoresSafeArea()
            ReferenceVersionImage(
                model: model,
                version: presentation.version,
                size: .expanded,
                minimumHeight: 0
            )
            .padding(54)
            .accessibilityLabel(presentation.accessibilityLabel)

            Button {
                model.dismissReferenceImage()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(18)
            .focused($closeFocused)
            .accessibilityIdentifier("sceneReference.lightbox.close")
            .accessibilityLabel("Close expanded image")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sceneReference.lightbox")
        .accessibilityLabel(presentation.accessibilityLabel)
        .onAppear { closeFocused = true }
        .onExitCommand { model.dismissReferenceImage() }
    }
}
