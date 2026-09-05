import Foundation
import GRDB

/// PHASE5_DESIGN §7.1's scene-prompt and project-generation doors (Plan 019 contract A),
/// on `ProjectSession`. Same shape as every editing wrapper: one synchronous
/// `database.queue.write`, one transaction, one journal row.
public extension ProjectSession {
    /// §7.1's `createScenePrompt` — the human Write Scene Prompt path and the human
    /// counterpart of the AI attach. The §8.2 input is rebuilt in-transaction by the op;
    /// this door mints the prompt id so a redo restores the row this call first made.
    @discardableResult
    func createScenePrompt(
        sceneID: UUID,
        body: String,
        guidance: String = "",
        durationSeconds: Int? = nil,
        aspectRatio: String = "",
        resolution: String = "",
        actor: MutationActor = .human
    ) throws -> JournalEntry {
        try createScenePromptSet(
            sceneID: sceneID,
            cards: [ScenePromptCardDraft(
                body: body, guidance: guidance, durationSeconds: durationSeconds,
                aspectRatio: aspectRatio, resolution: resolution
            )],
            actor: actor
        )
    }

    @discardableResult
    func createScenePromptSet(
        sceneID: UUID,
        cards: [ScenePromptCardDraft],
        actor: MutationActor = .human
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .createScenePromptSet(
                    setID: UUID(), sceneID: sceneID, cards: cards, restoring: []
                ),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func editScenePromptCard(
        cardID: UUID, draft: ScenePromptCardDraft, actor: MutationActor = .human
    ) throws -> JournalEntry {
        try performSet(.editScenePromptCard(cardID: cardID, draft: draft), actor: actor)
    }

    @discardableResult
    func addScenePromptCard(
        setID: UUID, draft: ScenePromptCardDraft, actor: MutationActor = .human
    ) throws -> JournalEntry {
        try performSet(
            .addScenePromptCard(cardID: UUID(), setID: setID, draft: draft), actor: actor
        )
    }

    @discardableResult
    func deleteScenePromptCard(
        cardID: UUID, actor: MutationActor = .human
    ) throws -> JournalEntry {
        try performSet(.deleteScenePromptCard(cardID: cardID), actor: actor)
    }

    @discardableResult
    func reorderScenePromptCards(
        setID: UUID, orderedCardIDs: [UUID], actor: MutationActor = .human
    ) throws -> JournalEntry {
        try performSet(
            .reorderScenePromptCards(setID: setID, orderedCardIDs: orderedCardIDs), actor: actor
        )
    }

    @discardableResult
    func deleteScenePromptSet(
        setID: UUID, actor: MutationActor = .human
    ) throws -> JournalEntry {
        try performSet(.deleteScenePromptSet(setID: setID), actor: actor)
    }

    /// §7.1's `setScenePromptBody`: current prompt only; converts provenance `source` to
    /// `human`; citations and digest untouched.
    @discardableResult
    func setScenePromptBody(
        promptID: UUID, body: String, actor: MutationActor = .human
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setScenePromptBody(promptID: promptID, body: body),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §7.1's `deleteScenePrompt`: any row, current or history alike; delete-the-newest
    /// restores the prior row to current by rule (§3.1).
    @discardableResult
    func deleteScenePrompt(promptID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .deleteScenePrompt(promptID: promptID), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §3.6's style bible. Digest input — every scene prompt stales as a consequence
    /// (§6.2), which is the staleness surface doing its job, not a bug.
    @discardableResult
    func setStyleBible(text: String, actor: MutationActor = .human) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setStyleBible(text: text), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §3.3's headline flip for the whole project. Stales nothing (§6.2).
    @discardableResult
    func setGenerationTargetProfile(
        profileID: String, actor: MutationActor = .human
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setGenerationTargetProfile(profileID: profileID),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }
}

private extension ProjectSession {
    func performSet(_ operation: EditOperation, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                operation, actor: actor, jobID: actor.jobID, in: db
            )
        }
    }
}
