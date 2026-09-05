import Foundation
import GRDB

/// `ScreenplayEditing` on `ProjectSession` (PHASE1_DESIGN §6, §3.8).
///
/// Every wrapper has the same shape: one synchronous `database.queue.write` on the actor —
/// no `await` inside it, so the actor cannot be reentered across a write — one transaction,
/// one journal row, and the `JournalEntry` returned so the app can register undo.
///
/// **No public operation is ever called from inside another**: `DatabaseQueue` is not
/// reentrant and a nested `write` deadlocks. Compound behavior comes from `mutate` and the
/// group level, never from calling a wrapper.
public extension ProjectSession {

    /// §6's rename. The previous name survives as an alias (§3.5) and the row becomes
    /// `source = 'human'` / `accepted` with `reviewed_at` stamped (§3.6).
    @discardableResult
    func renameEntity(id: UUID, name: String, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            // The op carries the entity's kind so the undo menu can say "Rename Character";
            // it is read inside the same transaction the rename runs in.
            guard let entity = try EntityOperations.fetch(id: id, in: db) else {
                throw ProjectStoreError.entityNotFound
            }
            return try EditPrimitives.perform(
                .renameEntity(id: id, kind: entity.kind, name: name),
                actor: actor,
                jobID: actor.jobID,
                in: db
            )
        }
    }

    /// §6's create. The id is minted here and travels in the operation, so a redo
    /// restores the row this call first made rather than a new one.
    @discardableResult
    func createEntity(
        kind: EntityKind,
        name: String,
        description: String = "",
        actor: MutationActor
    ) throws -> (entry: JournalEntry, entityID: UUID) {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            let entityID = UUID()
            let entry = try EditPrimitives.perform(
                .createEntity(id: entityID, kind: kind, name: name, description: description),
                actor: actor,
                jobID: actor.jobID,
                in: db
            )
            return (entry, entityID)
        }
    }

    /// §6's hard delete. Only a `human` row or one already `rejected` may be deleted;
    /// anything else is a tombstone case and throws `.rejectInsteadOfDelete`.
    @discardableResult
    func deleteEntity(id: UUID, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .deleteEntity(id: id, kind: try kind(of: id, in: db)),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §6's reject: a verdict, not a delete. Aliases and dependent rows stay.
    @discardableResult
    func rejectEntity(id: UUID, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .rejectEntity(id: id, kind: try kind(of: id, in: db)),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §6's unreject. Invoked directly it carries no `priorState`, so the operation reads
    /// the state the tombstone replaced out of the journal's own snapshot.
    @discardableResult
    func unrejectEntity(id: UUID, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .unrejectEntity(id: id, kind: try kind(of: id, in: db), priorState: nil),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func setDescription(id: UUID, text: String, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setDescription(id: id, text: text), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §6's reclassify: the aliases move to the new kind with the entity (§3.5).
    @discardableResult
    func reclassify(id: UUID, kind: EntityKind, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .reclassify(id: id, kind: kind), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func setRelevance(id: UUID, isRelevant: Bool, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setRelevance(id: id, isRelevant: isRelevant),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §6's "Move into…": locations only, refusing self and cycles by ancestor walk.
    @discardableResult
    func setLocationParent(id: UUID, parentID: UUID?, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setLocationParent(id: id, parentID: parentID),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §3.5's `addAlias`. The row id is minted here so an undone removal comes back with
    /// its original id.
    @discardableResult
    func addAlias(entityID: UUID, alias: String, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .addAlias(entityID: entityID, alias: alias, aliasID: UUID(), restoring: []),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func removeAlias(aliasID: UUID, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .removeAlias(aliasID: aliasID), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    // MARK: - Batch actions (§3.8's group level)

    /// One journal row, one undo step, one child `mutate` per entity.
    @discardableResult
    func deleteEntities(ids: [UUID], actor: MutationActor) throws -> JournalEntry {
        try performBatch(ids: ids, actor: actor) { id, kind in .deleteEntity(id: id, kind: kind) }
    }

    @discardableResult
    func rejectEntities(ids: [UUID], actor: MutationActor) throws -> JournalEntry {
        try performBatch(ids: ids, actor: actor) { id, kind in .rejectEntity(id: id, kind: kind) }
    }

    @discardableResult
    func setRelevance(ids: [UUID], isRelevant: Bool, actor: MutationActor) throws -> JournalEntry {
        try performBatch(ids: ids, actor: actor) { id, _ in
            .setRelevance(id: id, isRelevant: isRelevant)
        }
    }

    // MARK: - Merge and split (§3.5)

    /// §3.5's merge. One source is a single `perform`; more than one is a `performGroup`
    /// over one child merge per source, so the batch is still one journal row.
    @discardableResult
    func mergeEntities(
        sourceIDs: [UUID],
        into targetID: UUID,
        actor: MutationActor
    ) throws -> MergeResult {
        guard let database else { throw ProjectStoreError.sessionClosed }
        guard !sourceIDs.isEmpty else {
            throw ProjectStoreError.mergeRefused(reason: "Choose at least one item to merge.")
        }
        guard !sourceIDs.contains(targetID) else {
            throw ProjectStoreError.mergeRefused(
                reason: "The item you are merging into cannot also be one of the sources."
            )
        }
        // One id per source, minted here and carried in the operation, so a redo brings
        // each source-name alias back with the id it first had (§3.8).
        let nameAliasIDs = sourceIDs.map { _ in UUID() }
        return try database.queue.write { db in
            let compound = EditOperation.mergeEntities(
                sourceIDs: sourceIDs, into: targetID, nameAliasIDs: nameAliasIDs
            )
            if sourceIDs.count == 1 {
                let result = try EditPrimitives.performDetailed(
                    compound, actor: actor, jobID: actor.jobID, in: db
                )
                return MergeResult(entry: result.entry, skippedAliases: result.effect.skippedAliases)
            }
            let children = zip(sourceIDs, nameAliasIDs).map { source, aliasID in
                EditOperation.mergeEntities(
                    sourceIDs: [source], into: targetID, nameAliasIDs: [aliasID]
                )
            }
            let result = try EditPrimitives.performGroupDetailed(
                children, as: compound, actor: actor, jobID: actor.jobID, in: db
            )
            return MergeResult(entry: result.entry, skippedAliases: result.effect.skippedAliases)
        }
    }

    /// §3.5's split — human-only; an `.ai` attempt throws `.protectedFact`.
    @discardableResult
    func splitEntity(
        entityID: UUID,
        aliasIDs: [UUID],
        newName: String,
        movedAppearanceIDs: [UUID] = [],
        actor: MutationActor
    ) throws -> (entry: JournalEntry, entityID: UUID) {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            let newEntityID = UUID()
            let entry = try EditPrimitives.perform(
                .splitEntity(
                    entityID: entityID,
                    aliasIDs: aliasIDs,
                    newName: newName,
                    newEntityID: newEntityID,
                    // Pinned like `newEntityID`, so a redo restores the same alias row.
                    newAliasID: UUID(),
                    movedAppearanceIDs: movedAppearanceIDs
                ),
                actor: actor,
                jobID: actor.jobID,
                in: db
            )
            return (entry, newEntityID)
        }
    }

    // MARK: - Locks (§3.7)

    /// §6's `lock`. `LockPolicy` decides whether the subject kind admits that field;
    /// anything else throws `.invalidLockField(subjectKind:field:)`.
    @discardableResult
    func lock(subject: SubjectRef, field: LockField, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .lock(subject: subject, field: field), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §6's `unlock` — the explicit gesture a locked field needs before it can be edited.
    @discardableResult
    func unlock(subject: SubjectRef, field: LockField, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .unlock(subject: subject, field: field), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    // MARK: - Review (§3.6)

    /// §6's `acceptFacts`: one `performGroup` of `acceptFact` children, one journal row
    /// whose payload lists **exactly** the pairs it flipped.
    ///
    /// Accepting an entity accepts its alias **and appearance** rows — they are what Plan
    /// 006 exports as `aliases`/`appearsIn` — so the expansion happens here, before the
    /// group is built, and the pairs it produces are the payload.
    @discardableResult
    func acceptFacts(refs: [SubjectRef], actor: MutationActor) throws -> JournalEntry {
        try acceptGroup(scope: .facts, actor: actor) { db in
            try ReviewOperations.expand(refs: refs, in: db)
        }
    }

    /// §6's `acceptAllProposed`: every `proposed` fact row in the project, in one group.
    @discardableResult
    func acceptAllProposed(actor: MutationActor) throws -> JournalEntry {
        try acceptGroup(scope: .allProposed, actor: actor) { db in
            try ReviewOperations.proposedRefs(in: db)
        }
    }

    // MARK: - Scenes (§6)

    /// Upserts the appearance on `(scene, entity, role)`. A hand-added appearance carries
    /// no `matched_alias_id` — no alias produced it (§3.5).
    @discardableResult
    func setSceneEntity(
        sceneID: UUID,
        entityID: UUID,
        role: SceneEntityRole,
        actor: MutationActor
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setSceneEntity(
                    sceneID: sceneID, entityID: entityID, role: role,
                    // Pinned here so an undone removal comes back with its original id.
                    appearanceID: UUID()
                ),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func removeSceneEntity(id: UUID, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .removeSceneEntity(appearanceID: id), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §6's `setSynopsis`: the scene's synopsis PROV column set, and no other column
    /// (§4.3).
    @discardableResult
    func setSynopsis(sceneID: UUID, text: String, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setSynopsis(sceneID: sceneID, text: text), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func setSceneText(
        sceneID: UUID,
        text: String?,
        actor: MutationActor
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setSceneText(sceneID: sceneID, text: text),
                actor: actor,
                jobID: actor.jobID,
                in: db
            )
        }
    }

    @discardableResult
    func setScenePromptDirection(
        sceneID: UUID,
        text: String,
        actor: MutationActor
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setScenePromptDirection(sceneID: sceneID, text: text),
                actor: actor,
                jobID: actor.jobID,
                in: db
            )
        }
    }

    // MARK: - States, events, relationships (§4.3, §6)

    @discardableResult
    func addState(
        entityID: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID?,
        actor: MutationActor
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .addState(
                    id: UUID(), entityID: entityID, category: category, description: description,
                    startSceneID: startSceneID, endSceneID: endSceneID, restoring: []
                ),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func editState(
        id: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID?,
        actor: MutationActor
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .editState(
                    id: id, category: category, description: description,
                    startSceneID: startSceneID, endSceneID: endSceneID
                ),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// Tombstones an `ai` row and hard-deletes a `human` one (§6).
    @discardableResult
    func removeState(id: UUID, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .removeState(id: id), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func addEvent(
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID?,
        actor: MutationActor
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .addEvent(
                    id: UUID(), sceneID: sceneID, entityID: entityID, description: description,
                    resultingStateID: resultingStateID, restoring: []
                ),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func editEvent(
        id: UUID,
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID?,
        actor: MutationActor
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .editEvent(
                    id: id, sceneID: sceneID, entityID: entityID, description: description,
                    resultingStateID: resultingStateID
                ),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func removeEvent(id: UUID, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .removeEvent(id: id), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func addRelationship(
        fromEntityID: UUID,
        toEntityID: UUID,
        kind: RelationshipKind,
        description: String,
        actor: MutationActor
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .addRelationship(
                    id: UUID(), fromEntityID: fromEntityID, toEntityID: toEntityID,
                    kind: kind, description: description, restoring: []
                ),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    @discardableResult
    func removeRelationship(id: UUID, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .removeRelationship(id: id), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    // MARK: - Requirements (PHASE2_DESIGN §7.2)

    /// §7.2's human create. The id is minted here and travels in the operation, so a redo
    /// restores the row this call first made.
    @discardableResult
    func createRequirement(
        entityID: UUID,
        tier: AssetRequirementTier,
        typeID: UUID? = nil,
        name: String,
        reason: String = "",
        actor: MutationActor
    ) throws -> (entry: JournalEntry, requirementID: UUID) {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            let requirementID = UUID()
            let entry = try EditPrimitives.perform(
                .createRequirement(
                    id: requirementID, entityID: entityID, tier: tier, typeID: typeID,
                    name: name, reason: reason
                ),
                actor: actor, jobID: actor.jobID, in: db
            )
            return (entry, requirementID)
        }
    }

    /// §7.2's hard delete: `human`-created or already-rejected rows only, refused while an
    /// asset row exists; anything else tombstones instead.
    @discardableResult
    func deleteRequirement(id: UUID, actor: MutationActor) throws -> JournalEntry {
        try performRequirement(.deleteRequirement(id: id), actor: actor)
    }

    @discardableResult
    func rejectRequirement(id: UUID, actor: MutationActor) throws -> JournalEntry {
        try performRequirement(.rejectRequirement(id: id), actor: actor)
    }

    /// Invoked directly it carries no `priorState`, so the operation falls back to §6's rule.
    @discardableResult
    func unrejectRequirement(id: UUID, actor: MutationActor) throws -> JournalEntry {
        try performRequirement(.unrejectRequirement(id: id, priorState: nil), actor: actor)
    }

    @discardableResult
    func renameRequirement(id: UUID, name: String, actor: MutationActor) throws -> JournalEntry {
        try performRequirement(.renameRequirement(id: id, name: name), actor: actor)
    }

    @discardableResult
    func setRequirementReason(id: UUID, text: String, actor: MutationActor) throws -> JournalEntry {
        try performRequirement(.setRequirementReason(id: id, text: text), actor: actor)
    }

    @discardableResult
    func setRequirementNecessity(
        id: UUID,
        necessity: RequirementNecessity,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .setRequirementNecessity(id: id, necessity: necessity), actor: actor
        )
    }

    /// Variant tier only. The link id is minted here so an undone removal comes back with
    /// its original id.
    @discardableResult
    func addRequirementScene(
        requirementID: UUID,
        sceneID: UUID,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .addRequirementScene(
                requirementID: requirementID, sceneID: sceneID, linkID: UUID(), restoring: []
            ),
            actor: actor
        )
    }

    @discardableResult
    func removeRequirementScene(linkID: UUID, actor: MutationActor) throws -> JournalEntry {
        try performRequirement(.removeRequirementScene(linkID: linkID), actor: actor)
    }

    @discardableResult
    func excludeReferenceFromScene(
        sceneID: UUID,
        requirementID: UUID,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .excludeReferenceFromScene(
                sceneID: sceneID,
                requirementID: requirementID,
                exclusionID: UUID(),
                restoring: []
            ),
            actor: actor
        )
    }

    @discardableResult
    func excludeReferencesFromScene(
        sceneID: UUID,
        requirementIDs: [UUID],
        actor: MutationActor
    ) throws -> JournalEntry {
        guard requirementIDs.isEmpty == false,
              Set(requirementIDs).count == requirementIDs.count
        else {
            throw ProjectStoreError.requirementOperationRefused(
                reason: "Choose one or more distinct references to remove from this scene."
            )
        }
        let operations = requirementIDs.map { requirementID in
            EditOperation.excludeReferenceFromScene(
                sceneID: sceneID,
                requirementID: requirementID,
                exclusionID: UUID(),
                restoring: []
            )
        }
        return try performRequirement(.batch(operations), actor: actor)
    }

    @discardableResult
    func includeReferenceInScene(
        exclusionID: UUID,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .includeReferenceInScene(exclusionID: exclusionID),
            actor: actor
        )
    }

    @discardableResult
    func addDependency(
        requirementID: UUID,
        dependsOnID: UUID,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .addDependency(
                requirementID: requirementID, dependsOnID: dependsOnID,
                dependencyID: UUID(), restoring: []
            ),
            actor: actor
        )
    }

    @discardableResult
    func removeDependency(id: UUID, actor: MutationActor) throws -> JournalEntry {
        try performRequirement(.removeDependency(id: id), actor: actor)
    }

    /// §7.2's combine: variant tier only, cross-entity sources permitted, assets merged by
    /// the total survivor rule, sources tombstoned.
    @discardableResult
    func combineRequirements(
        sourceIDs: [UUID],
        into targetID: UUID,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .combineRequirements(sourceIDs: sourceIDs, into: targetID), actor: actor
        )
    }

    /// §7.2's split. `sceneIDs` must be a nonempty proper subset of the source's stored
    /// links; the new id is minted here so a redo restores the same row.
    @discardableResult
    func splitRequirement(
        id: UUID,
        sceneIDs: [UUID],
        newName: String,
        actor: MutationActor
    ) throws -> (entry: JournalEntry, requirementID: UUID) {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            let newID = UUID()
            let entry = try EditPrimitives.perform(
                .splitRequirement(id: id, sceneIDs: sceneIDs, newName: newName, newID: newID),
                actor: actor, jobID: actor.jobID, in: db
            )
            return (entry, newID)
        }
    }

    /// §3.3's override — human-only.
    @discardableResult
    func setManifestInclusion(
        entityID: UUID,
        inclusion: ManifestInclusion,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .setManifestInclusion(entityID: entityID, inclusion: inclusion), actor: actor
        )
    }

    // MARK: - The template (§7.2)

    @discardableResult
    func setTemplateEntryEnabled(
        typeID: UUID,
        isEnabled: Bool,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .setTemplateEntryEnabled(typeID: typeID, isEnabled: isEnabled), actor: actor
        )
    }

    @discardableResult
    func renameTemplateEntry(
        typeID: UUID,
        displayName: String,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .renameTemplateEntry(typeID: typeID, displayName: displayName), actor: actor
        )
    }

    @discardableResult
    func setTemplateEntryOrder(
        typeID: UUID,
        sortOrder: Int,
        actor: MutationActor
    ) throws -> JournalEntry {
        try performRequirement(
            .setTemplateEntryOrder(typeID: typeID, sortOrder: sortOrder), actor: actor
        )
    }

    @discardableResult
    func addTemplateEntry(
        kind: EntityKind,
        code: String,
        displayName: String,
        sortOrder: Int,
        actor: MutationActor
    ) throws -> (entry: JournalEntry, typeID: UUID) {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            let typeID = UUID()
            let entry = try EditPrimitives.perform(
                .addTemplateEntry(
                    id: typeID, kind: kind, code: code, displayName: displayName,
                    sortOrder: sortOrder
                ),
                actor: actor, jobID: actor.jobID, in: db
            )
            return (entry, typeID)
        }
    }

    /// Refused while any requirement references the entry, tombstoned rows included.
    @discardableResult
    func removeTemplateEntry(typeID: UUID, actor: MutationActor) throws -> JournalEntry {
        try performRequirement(.removeTemplateEntry(typeID: typeID), actor: actor)
    }

    // MARK: - Build Asset Manifest (§5.2)

    /// §5.2's **Build Asset Manifest**: idempotent, repeatable, and journaling **nothing**
    /// when there is nothing to create.
    ///
    /// The guard runs before `performGroup` — which always journals once invoked — so an
    /// idempotent no-op Build writes no journal row and returns `entry: nil`. Name
    /// collisions are counted skips, never throws (§5.2).
    func refreshCanonicalRequirements(actor: MutationActor) throws -> ManifestBuildResult {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            let plan = try RequirementOperations.buildPlan(in: db)
            guard !plan.children.isEmpty else {
                return ManifestBuildResult(
                    created: 0, collisions: plan.collisions, entry: nil
                )
            }
            let entry = try EditPrimitives.performGroup(
                plan.children,
                as: .refreshCanonicalRequirements,
                actor: actor,
                jobID: actor.jobID,
                in: db
            )
            return ManifestBuildResult(
                created: plan.children.count, collisions: plan.collisions, entry: entry
            )
        }
    }

    /// The **only** public door for applying an inverse (§3.8) — there is no generic
    /// "apply this operation" entry point, and the window model never builds an
    /// `EditOperation`.
    ///
    /// Refuses a non-invertible entry, one that is not live, one whose affected set meets a
    /// later live human edit's, or one whose rows have moved, with
    /// `.inverseNoLongerApplicable(reason:)` **before writing anything**.
    @discardableResult
    func applyInverse(entryID: Int64, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            // The containment travels with the inverse because a redo of an import
            // re-verifies its file before re-inserting the row (PHASE2_DESIGN §7.3).
            try InverseApplication.apply(
                entryID: entryID, actor: actor, media: mediaContainment, in: db
            )
        }
    }

    /// §3.8's selective revert of one run: one transaction, one **non-invertible** journal
    /// row whose payload holds every row the revert put back, and the report the Jobs
    /// section reads out ("Reverted 412 changes; 3 skipped because you edited them").
    ///
    /// The walk itself is `RevertOperations`, reached — like every other operation — through
    /// `perform`, which is what makes "one transaction, one journal row" true here too.
    ///
    /// Task-agnostic (PHASE2_DESIGN §7.5): `requireNewestRun` orders `extractScreenplay`
    /// and `inferAssetManifest` parents in one journal-sequence ordering, so this one door
    /// reverts either kind of run and refuses either when a newer one exists. The journal
    /// row keeps the `.revertExtractionRun` case — renaming it would rewrite the meaning of
    /// every entry already recorded in a shipped project.
    @discardableResult
    func revertRun(jobID: UUID, actor: MutationActor) throws -> RevertReport {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            let outcome = try EditPrimitives.performDetailed(
                .revertExtractionRun(jobID: jobID), actor: actor, jobID: actor.jobID, in: db
            )
            // The `.revertExtractionRun` branch of `mutate` always reports; the fallback
            // exists so a report can never be a crash.
            return outcome.effect.revertReport
                ?? RevertReport(jobID: jobID, reverted: 0, skipped: 0, skippedSubjects: [])
        }
    }
}

private extension ProjectSession {
    /// The shared shape of every scalar requirement and template wrapper: one
    /// `database.queue.write`, one transaction, one journal row.
    func performRequirement(_ op: EditOperation, actor: MutationActor) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(op, actor: actor, jobID: actor.jobID, in: db)
        }
    }

    /// The kind an entity-shaped operation carries so the undo menu can say
    /// "Rename Character"; read inside the transaction the operation runs in.
    func kind(of id: UUID, in db: Database) throws -> EntityKind {
        guard let entity = try EntityOperations.fetch(id: id, in: db) else {
            throw ProjectStoreError.entityNotFound
        }
        return entity.kind
    }

    /// The shared shape of `acceptFacts` and `acceptAllProposed`: the pairs are collected
    /// inside the transaction, the compound `op` carries exactly those pairs, and the
    /// group inverts them — and nothing else — in reverse order (§6).
    func acceptGroup(
        scope: AcceptScope,
        actor: MutationActor,
        refs: @escaping (Database) throws -> [SubjectRef]
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            let refs = try refs(db)
            let compound = EditOperation.acceptAll(refs: refs, scope: scope)
            return try EditPrimitives.performGroup(
                refs.map { EditOperation.acceptFact($0) },
                as: compound,
                actor: actor,
                jobID: actor.jobID,
                in: db
            )
        }
    }

    /// The shared shape of the batch wrappers: one `performGroup`, one journal row whose
    /// `op` is the `.batch` compound, and one undo step.
    func performBatch(
        ids: [UUID],
        actor: MutationActor,
        makeOperation: @escaping (UUID, EntityKind) -> EditOperation
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            var children: [EditOperation] = []
            for id in ids { children.append(makeOperation(id, try kind(of: id, in: db))) }
            return try EditPrimitives.performGroup(
                children, as: .batch(children), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }
}

// MARK: - Prompt operations (PHASE3_DESIGN §7.2; Plan 014 contract B)

public extension ProjectSession {
    /// §7.2's `createPrompt` — the human Write Prompt path. Composes `createAsset` when
    /// the requirement has no slot yet (§7.1's group shape: the group inverse is the
    /// children's inverses in reverse order, `removeAssetRow` last, so undo of a first
    /// gesture on a bare requirement leaves **no asset row**). Not blockage-gated (§3.3).
    @discardableResult
    func createPrompt(
        requirementID: UUID,
        body: String,
        targetModel: String = "",
        actor: MutationActor = .human
    ) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            let promptID = UUID()
            var children: [EditOperation] = []
            if try AssetOperations.asset(ofRequirement: requirementID, in: db) == nil {
                children.append(
                    .createAsset(id: UUID(), requirementID: requirementID, restoring: [])
                )
            }
            children.append(
                .createPrompt(
                    id: promptID, requirementID: requirementID, body: body,
                    targetModel: targetModel, restoring: []
                )
            )
            return try EditPrimitives.performGroup(
                children, as: .batch(children), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §7.2's `setPromptBody`: current prompt only; converts `source` to `human`.
    @discardableResult
    func setPromptBody(promptID: UUID, body: String, actor: MutationActor = .human) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .setPromptBody(promptID: promptID, body: body),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §7.2's `deletePrompt`: any row, current or history alike.
    @discardableResult
    func deletePrompt(promptID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .deletePrompt(promptID: promptID),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §7.2's `markAssetInProgress` (§14.7): an explicit, journaled gesture. Refused while
    /// any version row exists (`.inProgressRequiresNoVersions`); composes `createAsset`
    /// per §7.1 when no slot exists yet.
    @discardableResult
    func markAssetInProgress(requirementID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            var children: [EditOperation] = []
            if try AssetOperations.asset(ofRequirement: requirementID, in: db) == nil {
                children.append(
                    .createAsset(id: UUID(), requirementID: requirementID, restoring: [])
                )
            }
            children.append(.markAssetInProgress(requirementID: requirementID))
            return try EditPrimitives.performGroup(
                children, as: .batch(children), actor: actor, jobID: actor.jobID, in: db
            )
        }
    }

    /// §7.2's `clearAssetInProgress`.
    @discardableResult
    func clearAssetInProgress(assetID: UUID, actor: MutationActor = .human) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try EditPrimitives.perform(
                .clearAssetInProgress(assetID: assetID),
                actor: actor, jobID: actor.jobID, in: db
            )
        }
    }
}
