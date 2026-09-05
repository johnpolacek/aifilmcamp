import Foundation
import FilmScript
import GRDB

/// Everything a screenplay operation needs that does not belong in a journal payload.
///
/// A `ScreenplayDocument` is a parse result, not a fact about the project, so it travels
/// beside the `EditOperation` rather than inside it.
struct ScreenplayMutationInput {
    var document: ScreenplayDocument
    var projectID: UUID
    var scriptID: UUID
    var displayName: String
    var assetID: UUID
    var assetRelativePath: RelativeProjectPath
}

/// Whether a mutation is a fresh edit or the application of an earlier entry's inverse.
///
/// It is the difference between §3.6's "stamp `reviewed_at` now" and §3.8's "restore the
/// snapshotted `updated_at`, `reviewed_at`, `review_state`, `source`, and `created_source`
/// of every row you touch, and delete every row the entry created". An inverse never
/// stamps "now", which is what makes apply → inverse byte-identical across all columns.
enum MutationMode {
    case apply
    case inverting(of: JournalEntry)
    /// Plan 007's stale `ai/proposed` cleanup. It is not a public editing mode: only the
    /// extraction applier uses it, and only rows verified replaceable enter it.
    case replacingAIProposal
    /// The extraction applier's deterministic post-processing pass. Its journal entry is
    /// owned by the AI run so selective Revert can remove it, while the canonical rows it
    /// creates retain their fixed `parser` provenance. Public manifest builds never use
    /// this mode.
    case refreshingCanonicalRequirements

    /// The entry being undone, when there is one.
    var invertedEntry: JournalEntry? {
        switch self {
        case .apply, .replacingAIProposal, .refreshingCanonicalRequirements: nil
        case let .inverting(entry): entry
        }
    }

    var isReplacingAIProposal: Bool {
        if case .replacingAIProposal = self { return true }
        return false
    }
}

/// An operation whose `mutate` branch a later step of Plan 005 still owes.
///
/// It exists so the `mutate` switch can stay **exhaustive** — adding an `EditOperation`
/// case must break the build, which a `default:` clause would silently prevent.
struct UnimplementedOperation: Error, CustomStringConvertible {
    let op: EditOperation
    var description: String { "\(op.displayName) is not implemented yet." }
}

/// The three internal levels of PHASE1_DESIGN §3.8.
///
/// Every one of them assumes an **open transaction** and never opens one: `DatabaseQueue`
/// is not reentrant, so a nested write deadlocks rather than fails. The public wrappers on
/// `ProjectSession` own the transaction; nothing under `Editing/` opens one — which
/// `EditingReentrancyTests` checks by reading these files, since a deadlock cannot be
/// caught by the test that triggers it.
enum EditPrimitives {

    // MARK: - mutate

    /// §3.8's `mutate`: applies the operation and returns its inverse plus the rows it
    /// touched. Journals nothing.
    static func mutate(
        _ op: EditOperation,
        actor: MutationActor,
        mode: MutationMode = .apply,
        input: ScreenplayMutationInput? = nil,
        media: BundleContainment? = nil,
        in db: Database
    ) throws -> MutationEffect {
        precondition(db.isInsideTransaction, "mutate must run inside an open transaction (§3.8)")
        switch op {
        case let .appendScenes(scriptID, expectedSHA256, text):
            return try SceneAppendOperations.append(
                scriptID: scriptID, expectedSHA256: expectedSHA256, text: text, actor: actor, in: db
            )

        case .importScreenplay:
            return try writeScreenplay(requiredInput(input), actor: actor, in: db)

        case let .replaceScreenplay(_, previousScriptID, _):
            let input = requiredInput(input)
            // Script-scoped rows and all entities go; §5.5's guard is the caller's.
            try db.execute(
                sql: "DELETE FROM scripts WHERE id = ?", arguments: [previousScriptID.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM entities WHERE project_id = ?", arguments: [input.projectID.uuidString]
            )
            return try writeScreenplay(input, actor: actor, in: db)

        case let .renameEntity(id, _, name):
            return try EntityOperations.rename(id: id, to: name, actor: actor, mode: mode, in: db)

        case let .createEntity(id, kind, name, description):
            return try EntityOperations.create(
                id: id, kind: kind, name: name, description: description,
                actor: actor, mode: mode, in: db
            )

        case let .deleteEntity(id, _):
            return try EntityOperations.delete(id: id, actor: actor, mode: mode, in: db)

        case let .restoreEntity(graph):
            return try EntityOperations.restore(graph: graph, in: db)

        case let .rejectEntity(id, _):
            return try EntityOperations.reject(id: id, actor: actor, mode: mode, in: db)

        case let .unrejectEntity(id, _, priorState):
            return try EntityOperations.unreject(
                id: id, priorState: priorState, actor: actor, mode: mode, in: db
            )

        case let .setDescription(id, text):
            return try EntityOperations.setDescription(
                id: id, text: text, actor: actor, mode: mode, in: db
            )

        case let .reclassify(id, kind):
            return try EntityOperations.reclassify(
                id: id, kind: kind, actor: actor, mode: mode, in: db
            )

        case let .setRelevance(id, isRelevant):
            return try EntityOperations.setRelevance(
                id: id, isRelevant: isRelevant, actor: actor, mode: mode, in: db
            )

        case let .setLocationParent(id, parentID):
            return try EntityOperations.setLocationParent(
                id: id, parentID: parentID, actor: actor, mode: mode, in: db
            )

        case let .addAlias(entityID, alias, aliasID, restoring):
            return try AliasOperations.add(
                entityID: entityID, alias: alias, aliasID: aliasID, restoring: restoring,
                actor: actor, in: db
            )

        case let .removeAlias(aliasID):
            return try AliasOperations.remove(aliasID: aliasID, actor: actor, in: db)

        case let .mergeEntities(sourceIDs, targetID, nameAliasIDs):
            // More than one source is a group of single-source merges (§3.5); `mutate` is
            // the only place that expansion may happen, because a public wrapper may never
            // call another one.
            guard sourceIDs.count == 1 else {
                guard let children = op.compoundChildren, !children.isEmpty else {
                    throw ProjectStoreError.mergeRefused(reason: "Choose at least one item to merge.")
                }
                return try combine(children, actor: actor, mode: mode, input: input, media: media, in: db).effect
            }
            return try MergeSplitOperations.merge(
                sourceID: sourceIDs[0], into: targetID, nameAliasID: nameAliasIDs.first,
                actor: actor, mode: mode, in: db
            )

        case let .unmerge(target, created, moved, snapshots):
            return try MergeSplitOperations.unmerge(
                target: target, created: created, moved: moved, snapshots: snapshots, in: db
            )

        case let .splitEntity(entityID, aliasIDs, newName, newEntityID, newAliasID, movedAppearanceIDs):
            return try MergeSplitOperations.split(
                entityID: entityID, aliasIDs: aliasIDs, newName: newName,
                newEntityID: newEntityID, newAliasID: newAliasID,
                movedAppearanceIDs: movedAppearanceIDs,
                actor: actor, mode: mode, in: db
            )

        case let .unsplit(created, moved, sourceSnapshot):
            return try MergeSplitOperations.unsplit(
                created: created, moved: moved, sourceSnapshot: sourceSnapshot, in: db
            )

        case let .batch(children):
            return try combine(children, actor: actor, mode: mode, input: input, media: media, in: db).effect

        case let .setSceneEntity(sceneID, entityID, role, appearanceID):
            return try SceneOperations.setSceneEntity(
                sceneID: sceneID, entityID: entityID, role: role, appearanceID: appearanceID,
                actor: actor, mode: mode, in: db
            )

        case let .removeSceneEntity(appearanceID):
            return try SceneOperations.removeSceneEntity(
                appearanceID: appearanceID, actor: actor, in: db
            )

        case let .setSynopsis(sceneID, text):
            return try SceneOperations.setSynopsis(
                sceneID: sceneID, text: text, actor: actor, mode: mode, in: db
            )

        case let .setSceneText(sceneID, text):
            return try SceneOperations.setSceneText(sceneID: sceneID, text: text, in: db)

        case let .setScenePromptDirection(sceneID, text):
            return try SceneOperations.setScenePromptDirection(
                sceneID: sceneID, text: text, in: db
            )

        case let .addState(id, entityID, category, description, startSceneID, endSceneID, restoring):
            return try ContinuityOperations.addState(
                id: id, entityID: entityID, category: category, description: description,
                startSceneID: startSceneID, endSceneID: endSceneID, restoring: restoring,
                actor: actor, in: db
            )

        case let .editState(id, category, description, startSceneID, endSceneID):
            return try ContinuityOperations.editState(
                id: id, category: category, description: description,
                startSceneID: startSceneID, endSceneID: endSceneID,
                actor: actor, mode: mode, in: db
            )

        case let .removeState(id):
            return try ContinuityOperations.removeState(id: id, actor: actor, mode: mode, in: db)

        case let .addEvent(id, sceneID, entityID, description, resultingStateID, restoring):
            return try ContinuityOperations.addEvent(
                id: id, sceneID: sceneID, entityID: entityID, description: description,
                resultingStateID: resultingStateID, restoring: restoring, actor: actor, in: db
            )

        case let .editEvent(id, sceneID, entityID, description, resultingStateID):
            return try ContinuityOperations.editEvent(
                id: id, sceneID: sceneID, entityID: entityID, description: description,
                resultingStateID: resultingStateID, actor: actor, mode: mode, in: db
            )

        case let .removeEvent(id):
            return try ContinuityOperations.removeEvent(id: id, actor: actor, mode: mode, in: db)

        case let .addRelationship(id, fromEntityID, toEntityID, kind, description, restoring):
            return try ContinuityOperations.addRelationship(
                id: id, fromEntityID: fromEntityID, toEntityID: toEntityID, kind: kind,
                description: description, restoring: restoring, actor: actor, in: db
            )

        case let .removeRelationship(id):
            return try ContinuityOperations.removeRelationship(
                id: id, actor: actor, mode: mode, in: db
            )

        case let .lock(subject, field):
            return try LockOperations.lock(
                subject: subject, field: field, actor: actor, mode: mode, in: db
            )

        case let .unlock(subject, field):
            return try LockOperations.unlock(subject: subject, field: field, actor: actor, in: db)

        case let .acceptFact(ref):
            return try ReviewOperations.accept(ref: ref, actor: actor, mode: mode, in: db)

        case let .unacceptFact(ref, priorState):
            return try ReviewOperations.unaccept(
                ref: ref, priorState: priorState, actor: actor, mode: mode, in: db
            )

        case let .rejectSubject(ref):
            return try ReviewOperations.reject(ref: ref, actor: actor, mode: mode, in: db)

        case let .unrejectSubject(ref, priorState):
            return try ReviewOperations.unreject(
                ref: ref, priorState: priorState, actor: actor, mode: mode, in: db
            )

        case .acceptAll:
            // One `acceptFact` child per pair in the payload — the same expansion the
            // group level journals, so a compound reached through `mutate` (a batch child,
            // say) behaves exactly as `acceptFacts` does.
            guard let children = op.compoundChildren else {
                throw UnimplementedOperation(op: op)
            }
            return try combine(children, actor: actor, mode: mode, input: input, media: media, in: db).effect

        case let .revertExtractionRun(jobID):
            // §3.8's selective revert: it applies the run's inverses through this level so
            // the whole revert is the **one** journal row `perform` writes above it.
            return try RevertOperations.revert(jobID: jobID, actor: actor, in: db)

        // MARK: Requirements and the template (PHASE2_DESIGN §7.2)

        case let .createRequirement(id, entityID, tier, typeID, name, reason, outfitSourceVersionID):
            return try RequirementOperations.create(
                id: id, entityID: entityID, tier: tier, typeID: typeID, name: name,
                reason: reason, outfitSourceVersionID: outfitSourceVersionID, actor: actor, in: db
            )

        case let .createCanonicalRequirement(id, entityID, typeID, name):
            return try RequirementOperations.createCanonical(
                id: id, entityID: entityID, typeID: typeID, name: name,
                actor: actor, mode: mode, in: db
            )

        case let .deleteRequirement(id):
            return try RequirementOperations.delete(id: id, actor: actor, mode: mode, in: db)

        case let .restoreRequirement(graph):
            return try RequirementOperations.restore(graph: graph, in: db)

        case let .rejectRequirement(id):
            return try RequirementOperations.reject(id: id, actor: actor, mode: mode, in: db)

        case let .unrejectRequirement(id, priorState):
            return try RequirementOperations.unreject(
                id: id, priorState: priorState, actor: actor, mode: mode, in: db
            )

        case let .renameRequirement(id, name):
            return try RequirementOperations.rename(
                id: id, to: name, actor: actor, mode: mode, in: db
            )

        case let .setRequirementReason(id, text):
            return try RequirementOperations.setReason(
                id: id, text: text, actor: actor, mode: mode, in: db
            )

        case let .setRequirementNecessity(id, necessity):
            return try RequirementOperations.setNecessity(
                id: id, necessity: necessity, actor: actor, mode: mode, in: db
            )

        case let .addRequirementScene(requirementID, sceneID, linkID, restoring):
            return try RequirementOperations.addScene(
                requirementID: requirementID, sceneID: sceneID, linkID: linkID,
                restoring: restoring, actor: actor, mode: mode, in: db
            )

        case let .removeRequirementScene(linkID):
            return try RequirementOperations.removeScene(
                linkID: linkID, actor: actor, mode: mode, in: db
            )

        case let .excludeReferenceFromScene(sceneID, requirementID, exclusionID, restoring):
            return try RequirementOperations.excludeReferenceFromScene(
                sceneID: sceneID,
                requirementID: requirementID,
                exclusionID: exclusionID,
                restoring: restoring,
                actor: actor,
                in: db
            )

        case let .includeReferenceInScene(exclusionID):
            return try RequirementOperations.includeReferenceInScene(
                exclusionID: exclusionID,
                actor: actor,
                in: db
            )

        case let .addDependency(requirementID, dependsOnID, dependencyID, restoring):
            return try RequirementOperations.addDependency(
                requirementID: requirementID, dependsOnID: dependsOnID,
                dependencyID: dependencyID, restoring: restoring,
                actor: actor, mode: mode, in: db
            )

        case let .removeDependency(id):
            return try RequirementOperations.removeDependency(
                id: id, actor: actor, mode: mode, in: db
            )

        case let .combineRequirements(sourceIDs, targetID):
            return try RequirementOperations.combine(
                sourceIDs: sourceIDs, into: targetID, actor: actor, in: db
            )

        case let .uncombineRequirements(payload):
            return try RequirementOperations.uncombine(payload: payload, in: db)

        case let .splitRequirement(id, sceneIDs, newName, newID):
            return try RequirementOperations.split(
                id: id, sceneIDs: sceneIDs, newName: newName, newID: newID, actor: actor, in: db
            )

        case let .unsplitRequirement(payload):
            return try RequirementOperations.unsplit(payload: payload, in: db)

        case let .setManifestInclusion(entityID, inclusion):
            return try RequirementOperations.setManifestInclusion(
                entityID: entityID, inclusion: inclusion, actor: actor, mode: mode, in: db
            )

        case let .setTemplateEntryEnabled(typeID, isEnabled):
            return try TemplateOperations.setEnabled(
                typeID: typeID, isEnabled: isEnabled, actor: actor, mode: mode, in: db
            )

        case let .renameTemplateEntry(typeID, displayName):
            return try TemplateOperations.rename(
                typeID: typeID, displayName: displayName, actor: actor, mode: mode, in: db
            )

        case let .setTemplateEntryOrder(typeID, sortOrder):
            return try TemplateOperations.setOrder(
                typeID: typeID, sortOrder: sortOrder, actor: actor, mode: mode, in: db
            )

        case let .addTemplateEntry(id, kind, code, displayName, sortOrder):
            return try TemplateOperations.add(
                id: id, kind: kind, code: code, displayName: displayName,
                sortOrder: sortOrder, actor: actor, in: db
            )

        case let .removeTemplateEntry(typeID):
            return try TemplateOperations.remove(typeID: typeID, actor: actor, in: db)

        case let .restoreTemplateEntry(snapshot):
            return try TemplateOperations.restore(snapshot: snapshot, in: db)

        // MARK: Assets and versions (PHASE2_DESIGN §7.3)

        case let .createAsset(id, requirementID, restoring):
            return try AssetOperations.createAsset(
                id: id, requirementID: requirementID, restoring: restoring, actor: actor, in: db
            )

        case let .removeAssetRow(assetID):
            return try AssetOperations.removeAssetRow(assetID: assetID, in: db)

        case let .importAssetVersion(
            versionID, assetID, versionNumber, relativePath, sha256, byteCount,
            originalFileName, mediaKind, pixelWidth, pixelHeight, promptID, restoring
        ):
            return try AssetOperations.importAssetVersion(
                versionID: versionID, assetID: assetID, versionNumber: versionNumber,
                relativePath: relativePath, sha256: sha256, byteCount: byteCount,
                originalFileName: originalFileName, mediaKind: mediaKind,
                pixelWidth: pixelWidth, pixelHeight: pixelHeight, promptID: promptID,
                restoring: restoring, actor: actor, media: requiredMedia(media), in: db
            )

        case let .removeVersionRow(versionID):
            return try AssetOperations.removeVersionRow(versionID: versionID, mode: mode, in: db)

        case let .rejectVersion(versionID):
            return try AssetOperations.rejectVersion(
                versionID: versionID, actor: actor, mode: mode, in: db
            )

        case let .unrejectVersion(versionID):
            return try AssetOperations.unrejectVersion(
                versionID: versionID, actor: actor, mode: mode, in: db
            )

        case let .restoreVersionStatus(versionID, status):
            return try AssetOperations.restoreVersionStatus(
                versionID: versionID, status: status, actor: actor, mode: mode, in: db
            )

        case let .deleteVersion(versionID):
            return try AssetOperations.deleteVersion(
                versionID: versionID, actor: actor, in: db
            )

        case let .deleteArchivedVersion(versionID):
            return try AssetOperations.deleteArchivedVersion(
                versionID: versionID, actor: actor, in: db
            )

        case let .deleteAsset(id):
            return try AssetOperations.deleteAsset(id: id, actor: actor, in: db)

        case let .approveVersion(assetID, versionID):
            return try AssetOperations.approveVersion(
                assetID: assetID, versionID: versionID, actor: actor, in: db
            )

        case let .unapproveVersion(payload):
            return try AssetOperations.unapproveVersion(payload: payload, in: db)

        case let .archiveCurrentVersion(assetID, versionID):
            return try AssetOperations.archiveCurrentVersion(
                assetID: assetID, versionID: versionID, actor: actor, in: db
            )

        case let .restoreArchivedVersion(payload):
            return try AssetOperations.restoreArchivedVersion(payload: payload, in: db)

        case let .clearAssetStale(assetID):
            return try AssetOperations.clearAssetStale(
                assetID: assetID, actor: actor, mode: mode, in: db
            )

        case let .restoreAssetStale(assetID, snapshot):
            return try AssetOperations.restoreAssetStale(
                assetID: assetID, snapshot: snapshot, mode: mode, in: db
            )

        case let .markAssetStale(assetID, reason):
            return try AssetOperations.markAssetStale(
                assetID: assetID, reason: reason, actor: actor, mode: mode, in: db
            )

        case let .restoreMarkedAssetStale(assetID, snapshot, reason):
            return try AssetOperations.restoreMarkedAssetStale(
                assetID: assetID, snapshot: snapshot, reason: reason, mode: mode, in: db
            )

        case let .rejectAsset(assetID):
            return try AssetOperations.rejectAsset(
                assetID: assetID, actor: actor, mode: mode, in: db
            )

        case let .unrejectAsset(assetID):
            return try AssetOperations.unrejectAsset(
                assetID: assetID, actor: actor, mode: mode, in: db
            )

        case let .setAssetNotes(id, text):
            return try AssetOperations.setAssetNotes(
                id: id, text: text, actor: actor, mode: mode, in: db
            )

        case let .setVersionNotes(id, text):
            return try AssetOperations.setVersionNotes(
                id: id, text: text, actor: actor, mode: mode, in: db
            )

        // MARK: Prompts (PHASE3_DESIGN §7.2; Plan 014)

        case let .createPrompt(id, requirementID, body, targetModel, restoring):
            return try PromptOperations.createPrompt(
                id: id, requirementID: requirementID, body: body, targetModel: targetModel,
                restoring: restoring, actor: actor, in: db
            )

        case let .attachGeneratedPrompt(
            promptID, assetID, requirementID, body, targetModel, guidance,
            inputDigest, inputFormatVersion, skillIdentity
        ):
            return try PromptOperations.attachGeneratedPrompt(
                promptID: promptID, assetID: assetID, requirementID: requirementID,
                body: body, targetModel: targetModel, guidance: guidance,
                inputDigest: inputDigest, inputFormatVersion: inputFormatVersion,
                skillIdentity: skillIdentity, actor: actor, mode: mode, in: db
            )

        case let .removeAttachedPrompt(payload):
            return try PromptOperations.removeAttachedPrompt(payload: payload, mode: mode, in: db)

        case let .setPromptBody(promptID, body):
            return try PromptOperations.setPromptBody(
                promptID: promptID, body: body, actor: actor, mode: mode, in: db
            )

        case let .deletePrompt(promptID):
            return try PromptOperations.deletePrompt(promptID: promptID, actor: actor, in: db)

        case let .restoreDeletedPrompt(payload):
            return try PromptOperations.restoreDeletedPrompt(payload: payload, in: db)

        case let .markAssetInProgress(requirementID):
            return try PromptOperations.markAssetInProgress(
                requirementID: requirementID, actor: actor, in: db
            )

        case let .clearAssetInProgress(assetID):
            return try PromptOperations.clearAssetInProgress(
                assetID: assetID, actor: actor, mode: mode, in: db
            )

        case let .restoreAssetInProgress(assetID, timestamp):
            return try PromptOperations.restoreAssetInProgress(
                assetID: assetID, timestamp: timestamp, in: db
            )

        // MARK: Scene prompts and project generation settings (PHASE5_DESIGN §7.1; Plan 019)

        case let .createScenePrompt(
            id, sceneID, body, guidance, durationSeconds, aspectRatio, resolution, restoring
        ):
            return try ScenePromptOperations.createScenePrompt(
                id: id, sceneID: sceneID, body: body, guidance: guidance,
                durationSeconds: durationSeconds, aspectRatio: aspectRatio,
                resolution: resolution, restoring: restoring, actor: actor, in: db
            )

        case let .setScenePromptBody(promptID, body):
            return try ScenePromptOperations.setScenePromptBody(
                promptID: promptID, body: body, actor: actor, mode: mode, in: db
            )

        case let .deleteScenePrompt(promptID):
            return try ScenePromptOperations.deleteScenePrompt(
                promptID: promptID, actor: actor, in: db
            )

        case let .restoreDeletedScenePrompt(payload):
            return try ScenePromptOperations.restoreDeletedScenePrompt(payload: payload, in: db)

        case let .createScenePromptSet(setID, sceneID, cards, restoring):
            return try ScenePromptSetOperations.create(
                setID: setID, sceneID: sceneID, cards: cards, restoring: restoring,
                actor: actor, in: db
            )
        case let .editScenePromptCard(cardID, draft):
            return try ScenePromptSetOperations.editCard(
                cardID: cardID, draft: draft, actor: actor, in: db
            )
        case let .addScenePromptCard(cardID, setID, draft):
            return try ScenePromptSetOperations.addCard(
                cardID: cardID, setID: setID, draft: draft, actor: actor, in: db
            )
        case let .deleteScenePromptCard(cardID):
            return try ScenePromptSetOperations.deleteCard(cardID: cardID, actor: actor, in: db)
        case let .reorderScenePromptCards(setID, cardIDs):
            return try ScenePromptSetOperations.reorder(
                setID: setID, orderedCardIDs: cardIDs, actor: actor, in: db
            )
        case let .deleteScenePromptSet(setID):
            return try ScenePromptSetOperations.deleteSet(setID: setID, actor: actor, in: db)
        case let .restoreScenePromptSet(payload):
            return try ScenePromptSetOperations.restore(payload: payload, in: db)

        case let .setStyleBible(text):
            return try ScenePromptOperations.setStyleBible(text: text, actor: actor, mode: mode, in: db)

        case let .setGenerationTargetProfile(profileID):
            return try ScenePromptOperations.setGenerationTargetProfile(
                profileID: profileID, actor: actor, mode: mode, in: db
            )

        // MARK: Skill import (PHASE5_DESIGN §14.6; Plan 019 contract B)

        case let .importSceneSkill(
            id, relativeRoot, displayName, entryRelativePath, routingRelativePath,
            treeSHA256, restoring
        ):
            return try SkillImportOperations.importSceneSkill(
                id: id, relativeRoot: relativeRoot, displayName: displayName,
                entryRelativePath: entryRelativePath, routingRelativePath: routingRelativePath,
                treeSHA256: treeSHA256, restoring: restoring, actor: actor, mode: mode,
                media: requiredMedia(media), in: db
            )

        case let .removeImportedSkill(payload):
            return try SkillImportOperations.removeImportedSkill(payload: payload, mode: mode, in: db)

        case let .selectSceneSkill(skillID):
            return try SkillImportOperations.selectSceneSkill(
                skillID: skillID, actor: actor, mode: mode, in: db
            )

        // MARK: The scene-prompt AI attach (PHASE5_DESIGN §8.4; Plan 021)

        case let .attachGeneratedScenePrompt(
            promptID, sceneID, body, guidance, durationSeconds, aspectRatio,
            resolution, inputDigest, inputFormatVersion, skillIdentity
        ):
            return try ScenePromptOperations.attachGeneratedScenePrompt(
                promptID: promptID, sceneID: sceneID, body: body, guidance: guidance,
                durationSeconds: durationSeconds, aspectRatio: aspectRatio,
                resolution: resolution, inputDigest: inputDigest,
                inputFormatVersion: inputFormatVersion, skillIdentity: skillIdentity,
                actor: actor, mode: mode, in: db
            )

        case let .removeAttachedScenePrompt(payload):
            return try ScenePromptOperations.removeAttachedScenePrompt(
                payload: payload, mode: mode, in: db
            )

        case let .attachGeneratedScenePromptSet(
            setID, sceneID, cards, inputDigest, inputFormatVersion, skillIdentity
        ):
            return try ScenePromptSetOperations.attachGenerated(
                setID: setID, sceneID: sceneID, cards: cards,
                inputDigest: inputDigest, inputFormatVersion: inputFormatVersion,
                skillIdentity: skillIdentity, actor: actor, mode: mode, in: db
            )
        case let .removeAttachedScenePromptSet(payload):
            return try ScenePromptSetOperations.removeAttached(
                payload: payload, mode: mode, in: db
            )

        case .refreshCanonicalRequirements:
            // §5.2: the compound is journaled by `performGroup` over children the session
            // wrapper builds from database state — `compoundChildren` must stay pure — so
            // reaching this case through `mutate` means the children were not built.
            throw UnimplementedOperation(op: op)

        // Plan 007 fills this one in; the switch stays exhaustive so a new case cannot be
        // added without being handled here.
        case .applyExtractionRun:
            return MutationEffect(inverse: nil)

        // §8.4 step 6's summary row: the report travels in the operation, and the row is
        // never inverted — a manifest run is reversed only through `revertRun`.
        case .applyManifestRun:
            return MutationEffect(inverse: nil)
        }
    }

    // MARK: - perform

    /// §3.8's `perform`: `mutate` plus exactly one journal row and its
    /// `edit_journal_affected` rows.
    @discardableResult
    static func perform(
        _ op: EditOperation,
        actor: MutationActor,
        jobID: UUID?,
        mode: MutationMode = .apply,
        invertsSeq: Int64? = nil,
        input: ScreenplayMutationInput? = nil,
        media: BundleContainment? = nil,
        in db: Database
    ) throws -> JournalEntry {
        try performDetailed(
            op, actor: actor, jobID: jobID, mode: mode, invertsSeq: invertsSeq, input: input,
            media: media, in: db
        ).entry
    }

    /// `perform` plus the effect it produced, so `importScreenplay` can build its summary
    /// and `mergeEntities` can read `skippedAliases` without re-querying the rows.
    static func performDetailed(
        _ op: EditOperation,
        actor: MutationActor,
        jobID: UUID?,
        mode: MutationMode = .apply,
        invertsSeq: Int64? = nil,
        input: ScreenplayMutationInput? = nil,
        media: BundleContainment? = nil,
        in db: Database
    ) throws -> (entry: JournalEntry, effect: MutationEffect) {
        precondition(db.isInsideTransaction, "perform must run inside an open transaction (§3.8)")
        precondition(actor.jobID == jobID, "jobID is nil for .human and the actor's job for .ai (§3.8)")
        let effect = try mutate(op, actor: actor, mode: mode, input: input, media: media, in: db)
        let entry = try JournalStore.append(
            op: op,
            effect: effect,
            actor: actor,
            jobID: jobID,
            invertsSeq: invertsSeq,
            at: Date(),
            in: db
        )
        return (entry, effect)
    }

    // MARK: - performGroup

    /// §3.8's group level: `mutate` per child in order, one journal row whose `op` is the
    /// compound case and whose payload holds every child inverse **in order**.
    ///
    /// The entry's own inverse is the group of those child inverses applied in **reverse**
    /// order, and any child that throws fails the whole transaction.
    @discardableResult
    static func performGroup(
        _ ops: [EditOperation],
        as compound: EditOperation,
        actor: MutationActor,
        jobID: UUID?,
        mode: MutationMode = .apply,
        invertsSeq: Int64? = nil,
        input: ScreenplayMutationInput? = nil,
        media: BundleContainment? = nil,
        in db: Database
    ) throws -> JournalEntry {
        try performGroupDetailed(
            ops, as: compound, actor: actor, jobID: jobID, mode: mode,
            invertsSeq: invertsSeq, input: input, media: media, in: db
        ).entry
    }

    static func performGroupDetailed(
        _ ops: [EditOperation],
        as compound: EditOperation,
        actor: MutationActor,
        jobID: UUID?,
        mode: MutationMode = .apply,
        invertsSeq: Int64? = nil,
        input: ScreenplayMutationInput? = nil,
        media: BundleContainment? = nil,
        in db: Database
    ) throws -> (entry: JournalEntry, effect: MutationEffect) {
        precondition(db.isInsideTransaction, "performGroup must run inside an open transaction (§3.8)")
        precondition(actor.jobID == jobID, "jobID is nil for .human and the actor's job for .ai (§3.8)")
        let combined = try combine(ops, actor: actor, mode: mode, input: input, media: media, in: db)
        let entry = try JournalStore.append(
            op: compound,
            effect: combined.effect,
            actor: actor,
            jobID: jobID,
            invertsSeq: invertsSeq,
            childInverses: combined.childInverses,
            at: Date(),
            in: db
        )
        return (entry, combined.effect)
    }

    /// Runs the children in order and folds their effects into one: affected unioned,
    /// snapshots and skipped aliases concatenated, the inverse reversed.
    private static func combine(
        _ ops: [EditOperation],
        actor: MutationActor,
        mode: MutationMode,
        input: ScreenplayMutationInput?,
        media: BundleContainment?,
        in db: Database
    ) throws -> (effect: MutationEffect, childInverses: [EditOperation]) {
        var affected: Set<SubjectRef> = []
        var snapshots: [RowSnapshot] = []
        var skippedAliases: [String] = []
        var childInverses: [EditOperation] = []
        var removedMediaPaths: [RelativeProjectPath] = []
        var isInvertible = true

        for child in ops {
            let effect = try mutate(child, actor: actor, mode: mode, input: input, media: media, in: db)
            affected.formUnion(effect.affected)
            snapshots.append(contentsOf: effect.snapshots)
            skippedAliases.append(contentsOf: effect.skippedAliases)
            removedMediaPaths.append(contentsOf: effect.removedMediaPaths)
            if let inverse = effect.inverse {
                childInverses.append(inverse)
            } else {
                isInvertible = false
            }
        }

        let inverse: EditOperation? = isInvertible ? .batch(childInverses.reversed()) : nil
        return (
            MutationEffect(
                inverse: inverse,
                affected: affected,
                snapshots: snapshots,
                skippedAliases: skippedAliases,
                removedMediaPaths: removedMediaPaths
            ),
            childInverses
        )
    }

    /// The bundle a media operation verifies its file against (PHASE2_DESIGN §4.1, §7.3).
    ///
    /// `importAssetVersion` re-reads the staged file before inserting its row — that is what
    /// makes a redo after Clear Orphaned Media refuse instead of leaving a row pointing at
    /// nothing — so it needs the containment walk, not the database alone. Only
    /// `ProjectSession` builds that operation, and only with its own bundle root, so its
    /// absence is a programmer error rather than a condition the app could recover from —
    /// exactly the shape `requiredInput` has for a screenplay parse.
    private static func requiredMedia(_ media: BundleContainment?) -> BundleContainment {
        guard let media else {
            preconditionFailure("A media operation requires its BundleContainment (§4.1)")
        }
        return media
    }

    /// The parse result a screenplay operation travels with. Only FilmCore builds those
    /// two operations, and only alongside their input, so its absence is a programmer
    /// error rather than a condition the app could recover from.
    private static func requiredInput(_ input: ScreenplayMutationInput?) -> ScreenplayMutationInput {
        guard let input else {
            preconditionFailure("A screenplay operation requires its ScreenplayMutationInput (§3.8)")
        }
        return input
    }

    // MARK: - The import-shaped path

    /// Inserts the script row and the whole §5.3 parser graph, and points
    /// `projects.current_script_id` at the new script.
    private static func writeScreenplay(
        _ input: ScreenplayMutationInput,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        let now = Date()
        let document = input.document
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        try db.execute(
            sql: """
                INSERT INTO scripts (
                    id, project_id, display_name, source_asset_id, format, original_asset_id,
                    source_text, sha256, title_page_json, parser_version, parse_warnings_json,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                input.scriptID.uuidString, input.projectID.uuidString, input.displayName,
                input.assetID.uuidString, document.format.rawValue, input.assetID.uuidString,
                document.sourceText, document.sourceText.sha256HexOfUTF8,
                String(decoding: try encoder.encode(document.titlePage), as: UTF8.self),
                FilmScriptVersion.parser,
                String(decoding: try encoder.encode(document.warnings), as: UTF8.self),
                UTCDate.string(from: now),
            ]
        )

        let written = try ScreenplayWriter.write(
            document: document,
            projectID: input.projectID,
            scriptID: input.scriptID,
            jobID: actor.jobID,
            now: now,
            in: db
        )

        try db.execute(
            sql: "UPDATE projects SET current_script_id = ?, updated_at = ? WHERE id = ?",
            arguments: [input.scriptID.uuidString, UTCDate.string(from: now), input.projectID.uuidString]
        )

        var affected: Set<SubjectRef> = [SubjectRef(kind: .script, id: input.scriptID)]
        for id in written.sceneIDsByOrdinal.values { affected.insert(SubjectRef(kind: .scene, id: id)) }
        for id in written.entityIDs { affected.insert(SubjectRef(kind: .entity, id: id)) }
        for id in written.aliasIDs { affected.insert(SubjectRef(kind: .alias, id: id)) }
        for id in written.appearanceIDs { affected.insert(SubjectRef(kind: .appearance, id: id)) }

        // Evidence rows are covered by their subjects: `SubjectKind` has no `evidence`
        // case, and every parser evidence row's subject is one of the appearances above.

        // Non-invertible by contract (§3.8): the inverse is `nil`, stated in the UI.
        return MutationEffect(
            inverse: nil,
            affected: affected,
            snapshots: [],
            screenplayWrite: written
        )
    }
}
