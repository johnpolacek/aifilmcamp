import AppKit
import FilmCore
import Foundation
import Observation

/// Window-owned drafts survive scene navigation; FilmCore still validates and journals
/// every save. Only the debounce is cancellable, never an in-flight transaction.
@MainActor @Observable
final class ScenePromptCardInlineEditor {
    struct Fields: Equatable {
        var title: String
        var body: String
        var guidance: String
        var duration: String
        var aspectRatio: String
        var resolution: String

        init(_ card: ScenePromptCard) {
            title = card.title
            body = card.body
            guidance = card.guidance
            duration = card.durationSeconds.map(String.init) ?? ""
            aspectRatio = card.aspectRatio
            resolution = card.resolution
        }

        func draft() throws -> ScenePromptCardDraft {
            let durationText = duration.trimmingCharacters(in: .whitespacesAndNewlines)
            guard durationText.isEmpty || Int(durationText) != nil else {
                throw ProjectStoreError.sceneOperationRefused(
                    reason: "Duration must be a whole number of seconds."
                )
            }
            return ScenePromptCardDraft(
                title: title, body: body, guidance: guidance,
                durationSeconds: Int(durationText), aspectRatio: aspectRatio,
                resolution: resolution
            )
        }
    }

    var fields: Fields { didSet { if !synchronizing { scheduleSave() } } }
    private(set) var savedFields: Fields
    private(set) var errorMessage: String?
    private(set) var isSaving = false
    @ObservationIgnored private weak var model: ProjectWindowModel?
    @ObservationIgnored private let cardID: UUID
    @ObservationIgnored let setID: UUID
    @ObservationIgnored private var synchronizing = false
    @ObservationIgnored private var discarded = false
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var commit: Task<Bool, Never>?

    init(model: ProjectWindowModel, card: ScenePromptCard) {
        self.model = model
        cardID = card.id
        setID = card.setID
        fields = Fields(card)
        savedFields = Fields(card)
    }

    var hasChanges: Bool { !discarded && fields != savedFields }

    func discard() async {
        discarded = true
        debounce?.cancel()
        debounce = nil
        if let commit { _ = await commit.value }
    }

    func resumeAfterFailedDeletion() {
        discarded = false
        scheduleSave()
    }

    func synchronize(_ card: ScenePromptCard) {
        guard !hasChanges, !isSaving else { return }
        synchronizing = true
        fields = Fields(card)
        savedFields = fields
        synchronizing = false
    }

    private func scheduleSave() {
        debounce?.cancel()
        debounce = nil
        errorMessage = nil
        guard hasChanges else { return }
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard let self else { return }
            self.debounce = nil
            await self.flush()
        }
    }

    func flush() async {
        debounce?.cancel()
        debounce = nil
        if let commit { _ = await commit.value }
        guard let model, !model.isClosed else { return }
        while hasChanges {
            // Other flush callers may have started a save while this one was awaiting.
            if let commit {
                guard await commit.value else { return }
                continue
            }
            let snapshot = fields
            isSaving = true
            let task = Task { @MainActor in
                defer {
                    self.isSaving = false
                    self.commit = nil
                }
                do {
                    let entry = try await model.session.editScenePromptCard(
                        cardID: self.cardID, draft: snapshot.draft()
                    )
                    model.didApply(entry)
                    await model.refresh()
                    self.savedFields = snapshot
                    self.errorMessage = nil
                    return true
                } catch {
                    self.errorMessage = error.localizedDescription
                    return false
                }
            }
            commit = task
            guard await task.value else { return }
        }
    }

    func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fields.body, forType: .string)
    }
}

extension ProjectWindowModel {
    func inlinePromptEditor(for card: ScenePromptCard) -> ScenePromptCardInlineEditor {
        if let editor = inlinePromptEditors[card.id] { return editor }
        let editor = ScenePromptCardInlineEditor(model: self, card: card)
        inlinePromptEditors[card.id] = editor
        return editor
    }

    @discardableResult
    func flushInlinePromptEditors(setID: UUID? = nil) async -> Bool {
        let editors = Array(inlinePromptEditors.values).filter {
            setID == nil || $0.setID == setID
        }
        for editor in editors { await editor.flush() }
        return editors.allSatisfy { !$0.hasChanges }
    }
}
