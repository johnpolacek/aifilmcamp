import FilmCore
import Foundation

/// §3.11's editing commands on the window model: one awaitable `async` method per
/// `ScreenplayEditing` operation the UI can invoke.
///
/// Every command has the same four beats, and nothing else:
///
/// 1. perform it on the session as `.human` — the window model never constructs an
///    `EditOperation` and never touches the database;
/// 2. `didApply(_:)` the returned `JournalEntry`, which registers its inverse on the
///    window's `UndoManager` **synchronously** (§3.8);
/// 3. `refresh()`, so the state the views read is current before the command returns;
/// 4. surface any refusal — FilmCore's wording, verbatim — through `error`.
///
/// No command starts fire-and-forget work: a caller that awaits one has the whole effect.
@MainActor
extension ProjectWindowModel {

    // MARK: - The shape of a command

    /// The command body, for the operations that return nothing but their entry.
    ///
    /// Internal rather than private so `ProjectWindowModel+Manifest.swift` — the same four
    /// beats over PHASE2_DESIGN §7.2's operations — runs through this one shape instead of
    /// growing a second copy of it.
    @discardableResult
    func runEdit(_ body: () async throws -> JournalEntry) async -> Bool {
        await runEdit { (entry: try await body(), value: ()) } != nil
    }

    /// The command body, for `createEntity` / `splitEntity` / `mergeEntities`, whose
    /// results the UI needs (the row to select, the aliases a merge had to skip).
    ///
    /// **No undo group is opened here.** Grouping happens synchronously around the one
    /// registration, inside `registerUndoAction`, and never spans an `await`: a group held
    /// open across the session call would make any `removeAllActions()` that lands in the
    /// middle (an AI entry seen by `refresh()`, a refused inverse, an import) reset the
    /// grouping level and crash on the close, and would let a direct Edit ▸ Undo nest a
    /// second group. A batch action is still exactly one undo step for free: `performGroup`
    /// returns one `JournalEntry`, so `didApply` registers exactly one action.
    ///
    /// A refused command registers nothing at all — no empty group is left behind to mask
    /// the previous action's menu title or swallow the next ⌘Z.
    func runEdit<Value>(
        _ body: () async throws -> (entry: JournalEntry, value: Value)
    ) async -> Value? {
        guard !isClosed else { return nil }
        do {
            let result = try await body()
            didApply(result.entry)
            await refresh()
            return result.value
        } catch {
            self.error = .project(error)
            return nil
        }
    }

    // MARK: - Entities (§6)

    /// Returns the new entity's id so the caller can select the row it just made.
    @discardableResult
    func createEntity(kind: EntityKind, name: String, description: String = "") async -> UUID? {
        await runEdit {
            let created = try await self.session.createEntity(
                kind: kind, name: name, description: description, actor: .human
            )
            return (entry: created.entry, value: created.entityID)
        }
    }

    func renameEntity(id: UUID, name: String) async {
        await runEdit { try await self.session.renameEntity(id: id, name: name, actor: .human) }
    }

    func setDescription(id: UUID, text: String) async {
        await runEdit { try await self.session.setDescription(id: id, text: text, actor: .human) }
    }

    /// §6: Delete hard-deletes only a `human` row or one already `rejected`. On a `parser`
    /// or `ai` row FilmCore refuses with `.rejectInsteadOfDelete(entityID:)` and the UI's
    /// Delete becomes `rejectEntity` — the tombstone that keeps the row's aliases so a
    /// re-import maps back to it and it stays rejected (§3.6).
    func deleteEntity(id: UUID) async {
        await runEdit {
            do {
                return try await self.session.deleteEntity(id: id, actor: .human)
            } catch ProjectStoreError.rejectInsteadOfDelete {
                return try await self.session.rejectEntity(id: id, actor: .human)
            }
        }
    }

    func rejectEntity(id: UUID) async {
        await runEdit { try await self.session.rejectEntity(id: id, actor: .human) }
    }

    func unrejectEntity(id: UUID) async {
        await runEdit { try await self.session.unrejectEntity(id: id, actor: .human) }
    }

    func reclassify(id: UUID, kind: EntityKind) async {
        await runEdit { try await self.session.reclassify(id: id, kind: kind, actor: .human) }
    }

    func setRelevance(id: UUID, isRelevant: Bool) async {
        await runEdit {
            try await self.session.setRelevance(id: id, isRelevant: isRelevant, actor: .human)
        }
    }

    /// "Move into…" (§6): locations only, refusing self and cycles.
    func setLocationParent(id: UUID, parentID: UUID?) async {
        await runEdit {
            try await self.session.setLocationParent(id: id, parentID: parentID, actor: .human)
        }
    }

    // MARK: - Batch actions (§3.8's group level: one journal row, one undo step)

    /// Delete over a multi-selection, routed **per row** as §6 requires: a `human` row (or
    /// one already `rejected`) is hard-deleted, a `parser` or `ai` row is tombstoned.
    ///
    /// A homogeneous selection — everything Phase 1a's list can produce in one gesture, and
    /// the overwhelming norm — is a single `performGroup`: one journal row, one undo step.
    /// A genuinely mixed selection needs one group of deletes and one of rejects, because
    /// FilmCore exposes `deleteEntities(ids:)` and `rejectEntities(ids:)` and no mixed
    /// wrapper; taking the tombstone for the whole batch instead would be one step but
    /// would quietly refuse to delete a row §6 says is the operator's to delete. Correct
    /// semantics win. (A mixed `performGroup` wrapper would be a FilmCore change — §6's
    /// operation list, not this step.)
    func deleteEntities(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        let (deletable, tombstoned) = await partitionForDelete(ids: ids)
        if !deletable.isEmpty {
            await runEdit { try await self.session.deleteEntities(ids: deletable, actor: .human) }
        }
        if !tombstoned.isEmpty {
            await runEdit { try await self.session.rejectEntities(ids: tombstoned, actor: .human) }
        }
    }

    /// Splits a selection by §6's rule, preserving the caller's order in each half. A row
    /// that cannot be read is left to FilmCore to refuse rather than guessed at.
    private func partitionForDelete(ids: [UUID]) async -> (deletable: [UUID], tombstoned: [UUID]) {
        var deletable: [UUID] = []
        var tombstoned: [UUID] = []
        for id in ids {
            guard let entity = try? await session.entity(id: id).entity else {
                deletable.append(id)
                continue
            }
            let hardDeletable = entity.provenance.source == .human
                || entity.provenance.reviewState == .rejected
            if hardDeletable { deletable.append(id) } else { tombstoned.append(id) }
        }
        return (deletable, tombstoned)
    }

    func rejectEntities(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        await runEdit { try await self.session.rejectEntities(ids: ids, actor: .human) }
    }

    func setRelevance(ids: [UUID], isRelevant: Bool) async {
        guard !ids.isEmpty else { return }
        await runEdit {
            try await self.session.setRelevance(ids: ids, isRelevant: isRelevant, actor: .human)
        }
    }

    // MARK: - Aliases (§3.5)

    func addAlias(entityID: UUID, alias: String) async {
        await runEdit { try await self.session.addAlias(entityID: entityID, alias: alias, actor: .human) }
    }

    func removeAlias(aliasID: UUID) async {
        await runEdit { try await self.session.removeAlias(aliasID: aliasID, actor: .human) }
    }

    // MARK: - Merge and split (§3.5)

    /// Returns the source names whose normalized form already belonged to an unrelated
    /// third entity, so the merge sheet can report them; a skipped alias is never a throw.
    @discardableResult
    func mergeEntities(sourceIDs: [UUID], into targetID: UUID) async -> [String]? {
        await runEdit {
            let result = try await self.session.mergeEntities(
                sourceIDs: sourceIDs, into: targetID, actor: .human
            )
            return (entry: result.entry, value: result.skippedAliases)
        }
    }

    /// Returns the new entity's id for the caller to select.
    @discardableResult
    func splitEntity(
        entityID: UUID,
        aliasIDs: [UUID],
        newName: String,
        movedAppearanceIDs: [UUID] = []
    ) async -> UUID? {
        await runEdit {
            let split = try await self.session.splitEntity(
                entityID: entityID,
                aliasIDs: aliasIDs,
                newName: newName,
                movedAppearanceIDs: movedAppearanceIDs,
                actor: .human
            )
            return (entry: split.entry, value: split.entityID)
        }
    }

    // MARK: - Scenes (§6)

    func setSceneEntity(sceneID: UUID, entityID: UUID, role: SceneEntityRole) async {
        await runEdit {
            try await self.session.setSceneEntity(
                sceneID: sceneID, entityID: entityID, role: role, actor: .human
            )
        }
    }

    func removeSceneEntity(id: UUID) async {
        await runEdit { try await self.session.removeSceneEntity(id: id, actor: .human) }
    }

    func setSynopsis(sceneID: UUID, text: String) async {
        await runEdit { try await self.session.setSynopsis(sceneID: sceneID, text: text, actor: .human) }
    }

    /// Stores a scene-local screenplay override. The imported script remains immutable,
    /// while every scene read and prompt-generation input resolves through this text.
    @discardableResult
    func setSceneText(sceneID: UUID, text: String) async -> Bool {
        await runEdit {
            try await self.session.setSceneText(sceneID: sceneID, text: text, actor: .human)
        }
    }

    /// Stores one-time filmmaker direction for the next scene-prompt generation. A
    /// successful generated-prompt apply consumes it atomically; failed and cancelled
    /// runs leave it available for retry.
    @discardableResult
    func setScenePromptDirection(sceneID: UUID, text: String) async -> Bool {
        await runEdit {
            try await self.session.setScenePromptDirection(
                sceneID: sceneID,
                text: text,
                actor: .human
            )
        }
    }

    // MARK: - States, events, relationships (§4.3, §6)

    func addState(
        entityID: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID? = nil
    ) async {
        await runEdit {
            try await self.session.addState(
                entityID: entityID, category: category, description: description,
                startSceneID: startSceneID, endSceneID: endSceneID, actor: .human
            )
        }
    }

    func editState(
        id: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID? = nil
    ) async {
        await runEdit {
            try await self.session.editState(
                id: id, category: category, description: description,
                startSceneID: startSceneID, endSceneID: endSceneID, actor: .human
            )
        }
    }

    func removeState(id: UUID) async {
        await runEdit { try await self.session.removeState(id: id, actor: .human) }
    }

    func addEvent(
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID? = nil
    ) async {
        await runEdit {
            try await self.session.addEvent(
                sceneID: sceneID, entityID: entityID, description: description,
                resultingStateID: resultingStateID, actor: .human
            )
        }
    }

    func editEvent(
        id: UUID,
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID? = nil
    ) async {
        await runEdit {
            try await self.session.editEvent(
                id: id, sceneID: sceneID, entityID: entityID, description: description,
                resultingStateID: resultingStateID, actor: .human
            )
        }
    }

    func removeEvent(id: UUID) async {
        await runEdit { try await self.session.removeEvent(id: id, actor: .human) }
    }

    func addRelationship(
        fromEntityID: UUID,
        toEntityID: UUID,
        kind: RelationshipKind,
        description: String
    ) async {
        await runEdit {
            try await self.session.addRelationship(
                fromEntityID: fromEntityID, toEntityID: toEntityID,
                kind: kind, description: description, actor: .human
            )
        }
    }

    func removeRelationship(id: UUID) async {
        await runEdit { try await self.session.removeRelationship(id: id, actor: .human) }
    }

    // MARK: - Locks (§3.7)

    func lock(subject: SubjectRef, field: LockField) async {
        await runEdit { try await self.session.lock(subject: subject, field: field, actor: .human) }
    }

    func unlock(subject: SubjectRef, field: LockField) async {
        await runEdit { try await self.session.unlock(subject: subject, field: field, actor: .human) }
    }

    /// Whether a `locks` row pins this subject's field, or the whole record (§3.7).
    ///
    /// This is the **editability** question: a field covered by a whole-record lock is
    /// just as unwritable as one locked by name.
    func isLocked(_ subject: SubjectRef, field: LockField) -> Bool {
        locks.contains {
            $0.subject == subject && ($0.isWholeRecord || $0.field == field.rawValue)
        }
    }

    /// Whether **this exact** `(subject, field)` lock row exists — what a `LockButton`
    /// toggles. A whole-record lock is not an unlockable `name` lock, so unlocking one
    /// field must never be offered as a way out of the other.
    func hasLock(_ subject: SubjectRef, field: LockField) -> Bool {
        locks.contains { $0.subject == subject && $0.field == field.rawValue }
    }

    // MARK: - Review (§3.6)

    func acceptFacts(refs: [SubjectRef]) async {
        guard !refs.isEmpty else { return }
        await runEdit { try await self.session.acceptFacts(refs: refs, actor: .human) }
    }

    /// Guarded so an empty project never journals an `.acceptAll(refs: [])` — a row whose
    /// payload flips nothing, whose inverse flips nothing, and whose only effect is an undo
    /// action that does nothing. `pendingReviewCount()` is the app-side half of the check;
    /// the exact `refs.isEmpty` guard belongs beside `ReviewOperations.proposedRefs` in
    /// FilmCore (§6), which this step does not touch.
    func acceptAllProposed() async {
        guard !isClosed else { return }
        guard let pending = try? await session.pendingReviewCount(), pending > 0 else { return }
        await runEdit { try await self.session.acceptAllProposed(actor: .human) }
    }

    // MARK: - Revert (§3.8)

    /// The Jobs section's "Revert last run": only the newest run is revertible, and a
    /// revert is **not** itself undoable — a successful one clears the stack.
    ///
    /// It deliberately does not go through `runEdit`: its journal entry is non-invertible,
    /// so registering it would be wrong, and the stack has to go even though the entry
    /// applied cleanly.
    ///
    /// "Newest" is **task-agnostic** (PHASE2_DESIGN §7.5, Plan 012 contract C/D): the newest
    /// completed run of either `extractScreenplay` or `inferAssetManifest` resolves here and
    /// routes through the one `revertRun` door. `RevertOperations`' widened newest-run gate
    /// remains the authority — this only picks the run the button offers.
    @discardableResult
    func revertLastRun() async -> RevertReport? {
        guard let run = newestRevertableRun else { return nil }
        return await revertRun(jobID: run.job.id)
    }

    @discardableResult
    func revertRun(jobID: UUID) async -> RevertReport? {
        guard !isClosed else { return nil }
        do {
            // Task-agnostic (PHASE2_DESIGN §7.5): "Revert last run" reverts the newest
            // completed run of either task through the one widened gate.
            let report = try await session.revertRun(jobID: jobID, actor: .human)
            undoManager.removeAllActions()
            await refresh()
            return report
        } catch {
            self.error = .project(error)
            return nil
        }
    }
}
