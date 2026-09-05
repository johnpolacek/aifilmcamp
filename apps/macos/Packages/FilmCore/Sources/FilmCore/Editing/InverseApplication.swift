import Foundation
import GRDB

/// Applying an earlier entry's inverse (PHASE1_DESIGN §3.8).
///
/// The public door is `ScreenplayEditing.applyInverse(entryID:actor:)`, which opens the
/// one transaction and calls in here; there is deliberately no generic "apply this
/// operation" entry point. Everything below assumes that open transaction.
enum InverseApplication {

    /// Loads the entry, refuses it if §3.8 says it may not be inverted, re-checks the
    /// inverse's own preconditions, and journals the inverse with `inverts_seq` set.
    ///
    /// Every refusal is thrown **before any write**, so an inverse is never partially
    /// applied.
    static func apply(
        entryID: Int64,
        actor: MutationActor,
        media: BundleContainment? = nil,
        in db: Database
    ) throws -> JournalEntry {
        guard let entry = try JournalStore.entry(seq: entryID, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change is no longer in this project's history."
            )
        }
        guard let inverse = entry.inverse else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "“\(entry.op.displayName)” cannot be undone."
            )
        }

        let ledger = try JournalStore.ledger(in: db)
        let live = liveSeqs(ledger)
        guard live.contains(entryID) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change has already been undone."
            )
        }
        guard try !conflictsWithLaterHumanEdit(entry, ledger: ledger, live: live, in: db) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "You have edited something that change touched, so it can no longer be undone."
            )
        }

        try precheck(inverse, entry: entry, media: media, in: db)

        // A compound inverse is journaled by the group level, so its payload keeps the
        // child inverses in order exactly as the original group's did.
        if let children = inverse.compoundChildren {
            return try EditPrimitives.performGroup(
                children,
                as: inverse,
                actor: actor,
                jobID: actor.jobID,
                mode: .inverting(of: entry),
                invertsSeq: entryID,
                media: media,
                in: db
            )
        }
        return try EditPrimitives.perform(
            inverse,
            actor: actor,
            jobID: actor.jobID,
            mode: .inverting(of: entry),
            invertsSeq: entryID,
            media: media,
            in: db
        )
    }

    // MARK: - Liveness and conflicts (§3.8)

    /// Every entry no later live entry has inverted.
    ///
    /// The walk is `seq` descending: the newest entry is live, and an entry is live iff no
    /// **live** entry inverts it. A cancelled inverse (one that was itself undone)
    /// therefore stops cancelling, which is what makes redo possible.
    static func liveSeqs(_ ledger: [JournalLedgerRow]) -> Set<Int64> {
        var live: Set<Int64> = []
        var invertedByLive: Set<Int64> = []
        // `ledger` arrives newest first; the walk depends on that order.
        for row in ledger {
            guard !invertedByLive.contains(row.seq) else { continue }
            live.insert(row.seq)
            if let inverted = row.invertsSeq { invertedByLive.insert(inverted) }
        }
        return live
    }

    /// `true` when `entry.affected` meets the affected set of a later live `human` entry
    /// whose `inverts_seq` is NULL or **less than** `entry.seq`.
    ///
    /// A later inverse of a *newer* entry only restores a state `entry` already saw, so it
    /// never conflicts; an inverse of an *older* one does.
    static func conflictsWithLaterHumanEdit(
        _ entry: JournalEntry,
        ledger: [JournalLedgerRow],
        live: Set<Int64>,
        in db: Database
    ) throws -> Bool {
        for row in ledger where row.seq > entry.seq {
            guard row.isHuman, live.contains(row.seq) else { continue }
            if let inverted = row.invertsSeq, inverted >= entry.seq { continue }
            let affected = try JournalStore.affected(seq: row.seq, in: db)
            if !entry.affected.isDisjoint(with: affected) { return true }
        }
        return false
    }

    // MARK: - Preconditions

    /// Re-checks that the rows an inverse needs are where it left them (§3.8).
    ///
    /// Every operation added by a later step adds its branch here: an inverse that would
    /// fail mid-write must be refused before the first statement runs.
    static func precheck(
        _ op: EditOperation,
        entry: JournalEntry,
        media: BundleContainment? = nil,
        in db: Database
    ) throws {
        switch op {
        case let .renameEntity(id, _, name):
            try EntityOperations.precheckRename(id: id, name: name, entry: entry, in: db)
        case let .createEntity(id, kind, name, _):
            try EntityOperations.precheckCreate(id: id, kind: kind, name: name, in: db)
        case let .deleteEntity(id, _):
            try EntityOperations.precheckScalar(id: id, entry: entry, kinds: [], in: db)
        case let .rejectEntity(id, _):
            try EntityOperations.precheckScalar(id: id, entry: entry, kinds: [.entity], in: db)
        case let .unrejectEntity(id, _, _):
            try EntityOperations.precheckScalar(id: id, entry: entry, kinds: [.entity], in: db)
        case let .setDescription(id, _):
            try EntityOperations.precheckScalar(id: id, entry: entry, kinds: [.entity], in: db)
        case let .setRelevance(id, _):
            try EntityOperations.precheckScalar(id: id, entry: entry, kinds: [.entity], in: db)
        case let .setLocationParent(id, _):
            try EntityOperations.precheckScalar(id: id, entry: entry, kinds: [.entity], in: db)
        case let .reclassify(id, _):
            try EntityOperations.precheckScalar(id: id, entry: entry, kinds: [.entity, .alias], in: db)
        case let .restoreEntity(graph):
            try precheckSnapshots(graph, in: db)
        case let .addAlias(entityID, alias, aliasID, restoring):
            try AliasOperations.precheckAdd(
                entityID: entityID, alias: alias, aliasID: aliasID, restoring: restoring, in: db
            )
        case let .removeAlias(aliasID):
            try AliasOperations.precheckRemove(aliasID: aliasID, in: db)
        case let .mergeEntities(sourceIDs, target, _):
            try MergeSplitOperations.precheckMerge(sourceIDs: sourceIDs, into: target, in: db)
        case let .unmerge(_, created, _, snapshots):
            try MergeSplitOperations.precheckUndo(created: created, snapshots: snapshots, in: db)
        case let .splitEntity(entityID, aliasIDs, newName, newEntityID, _, _):
            try MergeSplitOperations.precheckSplit(
                entityID: entityID, aliasIDs: aliasIDs, newName: newName,
                newEntityID: newEntityID, in: db
            )
        case let .unsplit(created, _, sourceSnapshot):
            try MergeSplitOperations.precheckUndo(created: created, snapshots: sourceSnapshot, in: db)
        case let .setSceneEntity(_, _, _, appearanceID):
            try SceneOperations.precheckSceneEntity(
                appearanceID: appearanceID, entry: entry, in: db
            )
        case let .removeSceneEntity(appearanceID):
            try SceneOperations.precheckRemoveSceneEntity(appearanceID: appearanceID, in: db)
        case let .setSynopsis(sceneID, _):
            try SceneOperations.precheckSynopsis(sceneID: sceneID, in: db)
        case let .setSceneText(sceneID, _):
            try SceneOperations.requireScene(sceneID, in: db)
        case let .setScenePromptDirection(sceneID, _):
            try SceneOperations.requireScene(sceneID, in: db)
        case let .addState(id, _, _, _, _, _, restoring):
            try ContinuityOperations.precheckAdd(
                id: id, table: "entity_states", restoring: restoring, in: db
            )
        case let .editState(id, _, _, _, _):
            try ContinuityOperations.precheckRow(table: "entity_states", id: id, in: db)
        case let .removeState(id):
            try ContinuityOperations.precheckRow(table: "entity_states", id: id, in: db)
        case let .addEvent(id, _, _, _, _, restoring):
            try ContinuityOperations.precheckAdd(
                id: id, table: "continuity_events", restoring: restoring, in: db
            )
        case let .editEvent(id, _, _, _, _):
            try ContinuityOperations.precheckRow(table: "continuity_events", id: id, in: db)
        case let .removeEvent(id):
            try ContinuityOperations.precheckRow(table: "continuity_events", id: id, in: db)
        case let .addRelationship(id, _, _, _, _, restoring):
            try ContinuityOperations.precheckAdd(
                id: id, table: "entity_relationships", restoring: restoring, in: db
            )
        case let .removeRelationship(id):
            try ContinuityOperations.precheckRow(table: "entity_relationships", id: id, in: db)
        case let .lock(subject, field):
            try LockOperations.precheckLock(subject: subject, field: field, in: db)
        case let .unlock(subject, field):
            try LockOperations.precheckUnlock(subject: subject, field: field, in: db)
        case let .acceptFact(ref):
            try ReviewOperations.precheck(ref: ref, in: db)
        case let .unacceptFact(ref, _):
            try ReviewOperations.precheck(ref: ref, in: db)
        case let .rejectSubject(ref):
            try ReviewOperations.precheck(ref: ref, in: db)
        case let .unrejectSubject(ref, _):
            try ReviewOperations.precheck(ref: ref, in: db)
        case let .acceptAll(refs, _):
            for ref in refs { try ReviewOperations.precheck(ref: ref, in: db) }

        // PHASE2_DESIGN §7.5: the new kinds' prechecks. Every refusal is thrown before the
        // first statement of the inverse runs.
        case let .createRequirement(id, entityID, _, _, name, _, _):
            try RequirementOperations.precheckCreate(
                id: id, entityID: entityID, name: name, in: db
            )
        case let .createCanonicalRequirement(id, entityID, _, name):
            try RequirementOperations.precheckCreate(
                id: id, entityID: entityID, name: name, in: db
            )
        case let .deleteRequirement(id):
            try RequirementOperations.precheckRow(id: id, in: db)
        case let .restoreRequirement(graph):
            try precheckSnapshots(graph, in: db)
        case let .rejectRequirement(id):
            try RequirementOperations.precheckRow(id: id, in: db)
        case let .unrejectRequirement(id, _):
            try RequirementOperations.precheckRow(id: id, in: db)
        case let .renameRequirement(id, name):
            try RequirementOperations.precheckRename(id: id, name: name, in: db)
        case let .setRequirementReason(id, _):
            try RequirementOperations.precheckRow(id: id, in: db)
        case let .setRequirementNecessity(id, _):
            try RequirementOperations.precheckRow(id: id, in: db)
        case let .addRequirementScene(_, _, linkID, restoring):
            try RequirementOperations.precheckAddChild(
                table: "asset_requirement_scenes", id: linkID, restoring: restoring, in: db
            )
        case let .removeRequirementScene(linkID):
            try RequirementOperations.precheckChildRow(
                table: "asset_requirement_scenes", id: linkID, in: db
            )
        case let .excludeReferenceFromScene(_, _, exclusionID, restoring):
            try RequirementOperations.precheckAddChild(
                table: "scene_reference_exclusions",
                id: exclusionID,
                restoring: restoring,
                in: db
            )
        case let .includeReferenceInScene(exclusionID):
            try RequirementOperations.precheckChildRow(
                table: "scene_reference_exclusions", id: exclusionID, in: db
            )
        case let .addDependency(_, _, dependencyID, restoring):
            try RequirementOperations.precheckAddChild(
                table: "asset_dependencies", id: dependencyID, restoring: restoring, in: db
            )
        case let .removeDependency(id):
            try RequirementOperations.precheckChildRow(table: "asset_dependencies", id: id, in: db)
        case let .combineRequirements(sourceIDs, targetID):
            try RequirementOperations.precheckCombine(sourceIDs: sourceIDs, into: targetID, in: db)
        case let .uncombineRequirements(payload):
            try precheckSnapshots(payload.snapshots, in: db)
        case let .splitRequirement(id, _, _, newID):
            try RequirementOperations.precheckSplitApply(id: id, newID: newID, in: db)
        case let .unsplitRequirement(payload):
            try RequirementOperations.precheckSplit(payload: payload, in: db)
        case let .setManifestInclusion(entityID, _):
            try EntityOperations.precheckScalar(id: entityID, entry: entry, kinds: [.entity], in: db)
        case let .setTemplateEntryEnabled(typeID, _):
            try TemplateOperations.precheckRow(typeID: typeID, in: db)
        case let .renameTemplateEntry(typeID, _):
            try TemplateOperations.precheckRow(typeID: typeID, in: db)
        case let .setTemplateEntryOrder(typeID, _):
            try TemplateOperations.precheckRow(typeID: typeID, in: db)
        case let .addTemplateEntry(id, _, _, _, _):
            try TemplateOperations.precheckAdd(id: id, in: db)
        case let .removeTemplateEntry(typeID):
            try TemplateOperations.precheckRow(typeID: typeID, in: db)
        case let .restoreTemplateEntry(snapshot):
            try precheckSnapshots(snapshot, in: db)

        // PHASE2_DESIGN §7.3's asset family. The import precheck is the pinned walk's
        // graceful refusal: a version number taken since, or a file that has gone.
        case let .createAsset(id, _, restoring):
            if restoring.isEmpty {
                guard try !RowSnapshotStore.exists(table: "assets", id: id, in: db) else {
                    throw ProjectStoreError.inverseNoLongerApplicable(
                        reason: "That asset has been added again since."
                    )
                }
            } else {
                try precheckSnapshots(restoring, in: db)
            }
        case let .removeAssetRow(assetID):
            try AssetOperations.precheckAsset(id: assetID, in: db)
        case let .importAssetVersion(
            versionID, assetID, versionNumber, relativePath, sha256, byteCount, _, _, _, _, _, _
        ):
            try AssetOperations.precheckImport(
                versionID: versionID, assetID: assetID, versionNumber: versionNumber,
                relativePath: relativePath, sha256: sha256, byteCount: byteCount,
                media: media, in: db
            )
        case let .removeVersionRow(versionID):
            try AssetOperations.precheckVersion(id: versionID, in: db)
        case let .rejectVersion(versionID):
            try AssetOperations.precheckVersion(id: versionID, in: db)
        case let .unrejectVersion(versionID):
            try AssetOperations.precheckVersion(id: versionID, in: db)
        case let .restoreVersionStatus(versionID, status):
            try AssetOperations.precheckRestoreVersionStatus(
                versionID: versionID, status: status, in: db
            )
        case let .approveVersion(assetID, versionID):
            try AssetOperations.precheckApprove(assetID: assetID, versionID: versionID, in: db)
        case let .unapproveVersion(payload):
            // The partial unique index is invisible to `wouldCollide` (§7.3), which is
            // exactly why this inverse demotes before it restores; the snapshot precheck
            // still covers the column-equality uniques of every row it puts back.
            try AssetOperations.precheckVersion(id: payload.versionID, in: db)
            try precheckSnapshots(payload.snapshots, in: db)
        case let .archiveCurrentVersion(assetID, versionID):
            try AssetOperations.precheckArchive(assetID: assetID, versionID: versionID, in: db)
        case let .restoreArchivedVersion(payload):
            try AssetOperations.precheckVersion(id: payload.versionID, in: db)
            try precheckSnapshots(payload.snapshots, in: db)
        case let .clearAssetStale(assetID):
            try AssetOperations.precheckAsset(id: assetID, in: db)
        case let .restoreAssetStale(assetID, _):
            try AssetOperations.precheckAsset(id: assetID, in: db)
        case let .markAssetStale(assetID, _):
            try AssetOperations.precheckAsset(id: assetID, in: db)
        case let .restoreMarkedAssetStale(assetID, snapshot, _):
            try AssetOperations.precheckAsset(id: assetID, in: db)
            try precheckSnapshots(snapshot, in: db)
        case let .rejectAsset(assetID):
            try AssetOperations.precheckAsset(id: assetID, in: db)
        case let .unrejectAsset(assetID):
            try AssetOperations.precheckAsset(id: assetID, in: db)
        case let .setAssetNotes(id, _):
            try AssetOperations.precheckAsset(id: id, in: db)
        case let .setVersionNotes(id, _):
            try AssetOperations.precheckVersion(id: id, in: db)

        // MARK: Prompts (PHASE3_DESIGN §7.2, §7.4; Plan 014)
        case let .createPrompt(_, _, _, _, restoring):
            try precheckSnapshots(restoring, in: db)
        case let .removeAttachedPrompt(payload):
            // Redo restores every inserted row byte-identically; `wouldCollide` over the
            // `(requirement_id, prompt_number)` pair is what refuses a reclaimed number
            // (§7.2's pinned walk).
            try precheckSnapshots(payload.snapshots, in: db)
        case let .setPromptBody(promptID, _):
            try PromptOperations.precheckPrompt(id: promptID, in: db)
        case let .deletePrompt(promptID):
            try PromptOperations.precheckPrompt(id: promptID, in: db)
        case let .restoreDeletedPrompt(payload):
            try precheckSnapshots(payload.snapshots, in: db)

        // PHASE5_DESIGN §7.1's scene-prompt family (Plan 019 contract A). The create's
        // redo restores byte-identically; the payload restore's `wouldCollide` over
        // `(scene_id, target_profile, prompt_number)` refuses a reclaimed number.
        case let .createScenePrompt(_, _, _, _, _, _, _, restoring):
            try precheckSnapshots(restoring, in: db)
        case let .setScenePromptBody(promptID, _):
            try ScenePromptOperations.precheckScenePrompt(id: promptID, in: db)
        case let .deleteScenePrompt(promptID):
            try ScenePromptOperations.precheckScenePrompt(id: promptID, in: db)
        case let .restoreDeletedScenePrompt(payload):
            try precheckSnapshots(payload.snapshots, in: db)
        case let .createScenePromptSet(_, _, _, restoring):
            try precheckSnapshots(restoring, in: db)
        case let .restoreScenePromptSet(payload),
             let .removeAttachedScenePromptSet(payload):
            try precheckSnapshots(payload.snapshots, in: db)
        case .editScenePromptCard, .addScenePromptCard, .deleteScenePromptCard,
             .reorderScenePromptCards, .deleteScenePromptSet,
             .attachGeneratedScenePromptSet:
            break

        // PHASE5_DESIGN §14.6 (Plan 019 contract B). The import's redo re-verifies the
        // retained tree inside `mutate` before restoring; the precheck here only guards
        // the payload's rows. The selection flip's inverse needs nothing — the projects
        // row cannot move.
        case let .importSceneSkill(_, _, _, _, _, _, restoring):
            try precheckSnapshots(restoring, in: db)
        case let .removeImportedSkill(payload):
            try precheckSnapshots(payload.snapshots, in: db)

        case let .batch(children):
            for child in children { try precheck(child, entry: entry, media: media, in: db) }
        default:
            break
        }
    }

    /// Every snapshot an inverse means to write back is either still present, or gone and
    /// free to come back — the check that keeps a payload-driven inverse from failing
    /// halfway through (§3.8).
    static func precheckSnapshots(_ snapshots: [RowSnapshot], in db: Database) throws {
        // The payload's own rows never block each other: a merge collision leaves the
        // survivor holding the loser's unique slot, and this inverse moves both.
        var siblings: [String: Set<String>] = [:]
        for snapshot in snapshots {
            siblings[snapshot.table, default: []].insert(RowSnapshotStore.keyDescription(of: snapshot))
        }
        // Present rows are checked too, and against the values the restore is about to
        // write: a row put back by `UPDATE` can hit a `UNIQUE` constraint a row added
        // since now holds, and §3.8 requires that refusal **before** the first write
        // rather than a raw SQLite error partway through.
        for snapshot in snapshots {
            let ignoring = siblings[snapshot.table] ?? []
            guard try !RowSnapshotStore.wouldCollide(snapshot, ignoring: ignoring, in: db) else {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "Restoring that change would collide with something added since."
                )
            }
        }
    }

    /// The shared half of every precheck: each row the entry touched is either snapshotted
    /// (so the inverse restores it) or still present (so the inverse can delete it), and
    /// no restore would collide with a row that appeared meanwhile.
    static func precheckAffected(
        of entry: JournalEntry,
        kinds: Set<SubjectKind>,
        in db: Database
    ) throws {
        for ref in entry.affected where kinds.contains(ref.kind) {
            guard let table = RowSnapshotStore.table(for: ref.kind) else { continue }
            let exists = try RowSnapshotStore.exists(table: table, id: ref.id, in: db)
            guard let snapshot = entry.snapshot(table: table, id: ref.id) else {
                // The entry created this row; the inverse deletes it again.
                guard exists else {
                    throw ProjectStoreError.inverseNoLongerApplicable(
                        reason: "Something that change added is already gone."
                    )
                }
                continue
            }
            if !exists, try RowSnapshotStore.wouldCollide(snapshot, in: db) {
                throw ProjectStoreError.inverseNoLongerApplicable(
                    reason: "Restoring that change would collide with something added since."
                )
            }
        }
    }

    // MARK: - Restoring

    /// Puts every row `entry` touched (of these kinds) back the way it was: snapshotted
    /// rows restored column for column, rows the entry created deleted again.
    ///
    /// Returns the rows as they were **before** this inverse ran, so the entry this
    /// inverse journals can itself be inverted — which is what redo is.
    static func restoreAffected(
        of entry: JournalEntry,
        kinds: Set<SubjectKind>,
        ownedBy owner: UUID? = nil,
        in db: Database
    ) throws -> (affected: Set<SubjectRef>, snapshots: [RowSnapshot]) {
        var affected: Set<SubjectRef> = []
        var priorSnapshots: [RowSnapshot] = []
        var toRestore: [(ref: SubjectRef, snapshot: RowSnapshot)] = []
        var toDelete: [(ref: SubjectRef, table: String)] = []

        for ref in entry.affected.sorted(by: subjectOrder) where kinds.contains(ref.kind) {
            guard let table = RowSnapshotStore.table(for: ref.kind) else { continue }
            // A group entry's snapshots cover every child, so each child restores only the
            // rows it owns — otherwise the second child of a batch would "restore" rows the
            // first had already put back and record them as its own prior state.
            if let owner, try owningEntityID(of: ref, entry: entry, in: db) != owner { continue }
            affected.insert(ref)
            if let current = try RowSnapshotStore.capture(table: table, id: ref.id, in: db) {
                priorSnapshots.append(current)
            }
            if let snapshot = entry.snapshot(table: table, id: ref.id) {
                toRestore.append((ref, snapshot))
            } else {
                toDelete.append((ref, table))
            }
        }

        // Children first when deleting and parents first when restoring, so a cascade
        // never takes a row the other half of the inverse is about to need.
        for item in toDelete.sorted(by: { deleteOrder($0.ref.kind) < deleteOrder($1.ref.kind) }) {
            try RowSnapshotStore.delete(table: item.table, id: item.ref.id, in: db)
        }
        for item in toRestore.sorted(by: { deleteOrder($1.ref.kind) < deleteOrder($0.ref.kind) }) {
            try RowSnapshotStore.restore(item.snapshot, in: db)
        }
        return (affected, priorSnapshots)
    }

    /// The `.inverting` half of a **single-row** operation: that row — and any evidence
    /// the entry took away with it — back exactly as the entry found it, or gone again
    /// when the entry created it.
    ///
    /// Returns the rows as they were **before** this inverse ran, so the entry this
    /// inverse journals can itself be inverted, plus whether the row was restored (the
    /// entry had removed or overwritten it) or removed (the entry had created it).
    static func invertRow(
        of entry: JournalEntry,
        ref: SubjectRef,
        in db: Database
    ) throws -> (snapshots: [RowSnapshot], restored: Bool) {
        guard let table = RowSnapshotStore.table(for: ref.kind) else {
            throw ProjectStoreError.inverseNoLongerApplicable(
                reason: "That change no longer has anything to restore."
            )
        }
        // `evidence.subject_id` is a polymorphic pointer with no foreign key (§4.3), so
        // evidence about the row travels with it in both directions or it is orphaned —
        // and PHASE2_DESIGN §4.3 gives `asset_requirement_basis.subject_id` exactly the
        // same shape, so a citation of the row travels with it too.
        let evidence = entry.snapshots.filter { snapshot in
            ["evidence", "asset_requirement_basis"].contains(snapshot.table)
                && snapshot.columns["subject_kind"] == .string(ref.kind.rawValue)
                && snapshot.columns["subject_id"] == .string(ref.id.uuidString)
        }
        let evidenceIDs = evidence.compactMap { snapshot -> (table: String, id: UUID)? in
            guard case let .string(raw)? = snapshot.columns["id"], let id = UUID(uuidString: raw)
            else { return nil }
            return (snapshot.table, id)
        }

        var priors: [RowSnapshot] = []
        if let current = try RowSnapshotStore.capture(table: table, id: ref.id, in: db) {
            priors.append(current)
        }
        for companion in evidenceIDs {
            if let current = try RowSnapshotStore.capture(
                table: companion.table, id: companion.id, in: db
            ) {
                priors.append(current)
            }
        }

        if let snapshot = entry.snapshot(table: table, id: ref.id) {
            try RowGraph.restore([snapshot] + evidence, in: db)
            return (priors, true)
        }
        for companion in evidenceIDs {
            try RowSnapshotStore.delete(table: companion.table, id: companion.id, in: db)
        }
        try RowSnapshotStore.delete(table: table, id: ref.id, in: db)
        return (priors, false)
    }

    /// The entity a touched row belongs to, read from the row itself or — when the entry
    /// deleted it — from its snapshot. `nil` for rows that belong to no entity.
    static func owningEntityID(of ref: SubjectRef, entry: JournalEntry, in db: Database) throws -> UUID? {
        if ref.kind == .entity { return ref.id }
        guard let table = RowSnapshotStore.table(for: ref.kind) else { return nil }
        if let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM \(table) WHERE id = ?",
            arguments: [ref.id.uuidString]
        ), row.hasColumn("entity_id"), let raw = row["entity_id"] as String? {
            return try UUID.required(raw)
        }
        if let snapshot = entry.snapshot(table: table, id: ref.id),
           case let .string(raw)? = snapshot.columns["entity_id"] {
            return UUID(uuidString: raw)
        }
        return nil
    }

    /// Dependants before the rows they reference.
    ///
    /// PHASE2_DESIGN §7.5 puts the v4 kinds **ahead** of the Phase 1 ones rather than after
    /// them: a version references its asset, an asset and every scene link, basis row, and
    /// dependency reference their requirement, and a requirement references both its entity
    /// and its template entry — so the whole manifest sub-graph has to go before `entity`,
    /// `scene`, and `templateEntry`. The Phase 1 kinds keep their relative order exactly.
    ///
    /// PHASE3_DESIGN §7.4 **renumbers** rather than appends: `asset_versions` gains
    /// `prompt_id`, so a version must restore *after* its prompt, and a prompt must
    /// restore before its requirement. The pinned constraint set is
    /// `promptReference < version < prompt < requirement`; every shipped kind keeps its
    /// relative order.
    private static func deleteOrder(_ kind: SubjectKind) -> Int {
        switch kind {
        case .promptReference: 0
        case .version: 1
        case .asset: 2
        case .dependency: 3
        case .requirementScene: 4
        case .basis: 5
        case .prompt: 6
        case .requirement: 7
        case .templateEntry: 8
        case .event: 9
        case .state: 10
        case .relationship: 11
        case .appearance: 12
        case .alias: 13
        case .entity: 14
        case .scene: 15
        case .synopsis, .script: 16
        }
    }

    private static func subjectOrder(_ lhs: SubjectRef, _ rhs: SubjectRef) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

extension JournalEntry {
    /// The snapshot this entry took of one row, if it took one.
    func snapshot(table: String, id: UUID) -> RowSnapshot? {
        snapshots.first { $0.table == table && $0.columns["id"] == .string(id.uuidString) }
    }
}
