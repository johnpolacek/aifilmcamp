import Foundation

/// Which door produced an `.acceptAll` group (PHASE1_DESIGN §6).
///
/// `acceptFacts(refs)` and `acceptAllProposed()` journal the same compound case over the
/// same payload — the pairs they flipped — and differ only in what the undo menu calls
/// them, so the discriminator lives here rather than in two nearly identical cases.
public enum AcceptScope: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    /// `acceptFacts(refs)` — "Accept 2 Facts".
    case facts
    /// `acceptAllProposed()` — "Accept All Proposed".
    case allProposed
}

/// One controlled mutation of a project (PHASE1_DESIGN §3.8).
///
/// The inverse of an operation is **returned by `mutate` in `MutationEffect.inverse`**,
/// not stored as a property here: payload-driven inverses such as `unmerge` carry their
/// snapshots as associated values, so the enum would otherwise have to be self-describing.
///
/// Plan 003 declared this type with only the two non-invertible screenplay cases; Plan 005
/// **extends** it with §6's complete operation list, the inverse-only primitives of §3.8's
/// table, and the compound cases the group level journals.
///
/// Cases that a human invokes and the Entity menu names per kind (`createEntity`,
/// `renameEntity`, `deleteEntity`, `rejectEntity`, `unrejectEntity`) carry the entity's
/// `kind` so `displayName` can say "Rename Character" rather than "Rename Entity"; the
/// public wrappers read it off the row inside the same transaction.
public enum EditOperation: Codable, Equatable, Sendable {

    // MARK: - Screenplay (Plan 003, §5.5)

    /// The first screenplay import into an empty project. Non-invertible.
    /// Human append, preserving existing scenes; journaled and non-invertible.
    case appendScenes(scriptID: UUID, expectedSHA256: String, text: String)
    case importScreenplay(scriptID: UUID, displayName: String)
    /// Replacing an existing screenplay wholesale (§5.5). Non-invertible.
    case replaceScreenplay(scriptID: UUID, previousScriptID: UUID, displayName: String)

    // MARK: - Entities (§6)

    /// The id is part of the operation so redo restores the row it first created.
    case createEntity(id: UUID, kind: EntityKind, name: String, description: String)
    /// Hard delete; refused with `.rejectInsteadOfDelete` on `ai`/`parser` rows that are
    /// not already rejected.
    case deleteEntity(id: UUID, kind: EntityKind)
    case rejectEntity(id: UUID, kind: EntityKind)
    /// `priorState` is the state the tombstone replaced; `nil` asks for §6's fallback
    /// (`accepted` for a `created_source = 'parser'` row, `proposed` otherwise).
    case unrejectEntity(id: UUID, kind: EntityKind, priorState: ReviewState?)
    case renameEntity(id: UUID, kind: EntityKind, name: String)
    case setDescription(id: UUID, text: String)
    case reclassify(id: UUID, kind: EntityKind)
    case setRelevance(id: UUID, isRelevant: Bool)
    /// Locations only; `nil` clears the parent.
    case setLocationParent(id: UUID, parentID: UUID?)

    // MARK: - Aliases (§3.5)

    /// `aliasID` pins the row id so an undone `removeAlias` comes back with its original
    /// id; `restoring` carries that row's full snapshot when this op is an inverse.
    case addAlias(entityID: UUID, alias: String, aliasID: UUID?, restoring: [RowSnapshot])
    case removeAlias(aliasID: UUID)

    // MARK: - Merge and split (§3.5)

    /// One source is the scalar operation; more than one is the compound the group level
    /// journals over one child merge per source.
    ///
    /// `nameAliasIDs` pins the id of the source-name alias each child merge inserts — one
    /// per source, in order — so `unmerge` → redo brings that alias back with the id it
    /// first had, exactly as `newEntityID` does for a split. An entry missing from the
    /// list, or one whose insert is skipped because the target already holds the
    /// normalized form, is simply unused.
    case mergeEntities(sourceIDs: [UUID], into: UUID, nameAliasIDs: [UUID])
    /// Human-only. `newEntityID` and `newAliasID` are part of the operation so
    /// unsplit → redo restores both rows with their original ids.
    case splitEntity(
        entityID: UUID,
        aliasIDs: [UUID],
        newName: String,
        newEntityID: UUID,
        newAliasID: UUID?,
        movedAppearanceIDs: [UUID]
    )

    // MARK: - Scenes (§6, §4.3)

    /// Upserts on `(scene_id, entity_id, role)`; `appearanceID` pins the row id for redo.
    case setSceneEntity(sceneID: UUID, entityID: UUID, role: SceneEntityRole, appearanceID: UUID?)
    case removeSceneEntity(appearanceID: UUID)
    /// Writes the scene's synopsis PROV set only (§4.3).
    case setSynopsis(sceneID: UUID, text: String)
    /// Stores a scene-local screenplay replacement while preserving imported source bytes.
    /// `nil` clears the override and returns the scene to its imported text.
    case setSceneText(sceneID: UUID, text: String?)
    /// Stores scene-specific performance, blocking, eyeline, and camera intent for the
    /// next generated prompt without rewriting screenplay content.
    case setScenePromptDirection(sceneID: UUID, text: String)

    // MARK: - States, events, relationships (§4.3)

    /// `id` is `nil` for a fresh add and set when this op restores a hard-deleted row;
    /// `restoring` then carries that row's snapshot (§3.8's "add with the original id").
    case addState(
        id: UUID?,
        entityID: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID?,
        restoring: [RowSnapshot]
    )
    case editState(
        id: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID?
    )
    case removeState(id: UUID)
    case addEvent(
        id: UUID?,
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID?,
        restoring: [RowSnapshot]
    )
    case editEvent(
        id: UUID,
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID?
    )
    case removeEvent(id: UUID)
    case addRelationship(
        id: UUID?,
        fromEntityID: UUID,
        toEntityID: UUID,
        kind: RelationshipKind,
        description: String,
        restoring: [RowSnapshot]
    )
    case removeRelationship(id: UUID)

    // MARK: - Locks (§3.7)

    case lock(subject: SubjectRef, field: LockField)
    case unlock(subject: SubjectRef, field: LockField)

    // MARK: - Review (§3.6)

    /// The per-fact child `acceptFacts` and `acceptAllProposed` group.
    case acceptFact(SubjectRef)
    /// `acceptFact`'s inverse: it restores `priorState` and clears `reviewed_at`.
    case unacceptFact(SubjectRef, priorState: ReviewState)

    // MARK: - Inverse-only primitives (§3.8's table)

    /// `deleteEntity`'s inverse: the whole entity graph, lock rows included, by original id.
    case restoreEntity(graph: [RowSnapshot])
    /// `mergeEntities`' inverse: restore the snapshots, re-point `moved` back, and delete
    /// every row the merge `created` (the source-name alias on the target included).
    ///
    /// `target` is carried rather than inferred: a merge of a bare entity — no aliases, no
    /// dependents, and a name alias skipped because a third entity held the form — creates
    /// and moves nothing, so there would be no row left to read it off, and the redo would
    /// silently become impossible.
    case unmerge(
        target: UUID,
        created: [SubjectRef],
        moved: [SubjectRef],
        snapshots: [RowSnapshot]
    )
    /// `splitEntity`'s inverse — never a plain merge, which would leave an alias on the
    /// source that did not exist before the split (§3.5).
    case unsplit(created: [SubjectRef], moved: [SubjectRef], sourceSnapshot: [RowSnapshot])
    /// The tombstoning primitive behind `removeState`/`removeEvent`/`removeRelationship`
    /// on `ai` rows.
    case rejectSubject(SubjectRef)
    case unrejectSubject(SubjectRef, priorState: ReviewState)

    // MARK: - Compound (§3.8's group level)

    /// Batch UI actions, and the inverse of any group — the children in reverse order.
    case batch([EditOperation])
    /// `acceptFacts(refs)` and `acceptAllProposed()`; the payload lists **exactly** the
    /// pairs flipped, and the inverse flips those and nothing else.
    case acceptAll(refs: [SubjectRef], scope: AcceptScope)

    // MARK: - Requirements (PHASE2_DESIGN §7.2)

    /// §7.2's human create. Validation: non-empty name, both §4.3 uniques, the
    /// `tier`/`typeID` pairing, the type row's kind/project agreement, and §3.3's **pool**
    /// (non-rejected, relevant) — the 2+ rule, the prop exception, and `manifest_inclusion`
    /// bound Build and the AI, never a deliberate human add.
    ///
    /// A variant seeds §3.5's dependency rows on the entity's existing active canonical
    /// requirements, skipping any pair a rejected tombstone covers.
    case createRequirement(
        id: UUID,
        entityID: UUID,
        tier: AssetRequirementTier,
        typeID: UUID?,
        name: String,
        reason: String,
        outfitSourceVersionID: UUID? = nil
    )
    /// The engine-internal case with **fixed `parser` provenance**; only
    /// `refreshCanonicalRequirements` emits it (§5.2). It also seeds §3.5's mirror
    /// dependency rows — each existing variant of the entity gains a dependency on the new
    /// canonical — because that is what "provenance is fixed by the operation, not by
    /// trusting a caller" means for the seeded rows too.
    case createCanonicalRequirement(id: UUID, entityID: UUID, typeID: UUID, name: String)
    /// Hard delete: `human`-created or already-rejected rows only, and **refused while an
    /// asset row exists**. Everything else tombstones instead, as entity delete does.
    case deleteRequirement(id: UUID)
    /// `deleteRequirement`'s inverse: the row graph — scene links, basis rows, dependencies
    /// both directions, and lock rows — back by original id.
    case restoreRequirement(graph: [RowSnapshot])
    /// §7.2's tombstone. Recomputes an existing asset to `deprecated` in the same group.
    case rejectRequirement(id: UUID)
    /// `nil` asks for §6's fallback (`accepted` for a `created_source = 'parser'` row,
    /// `proposed` otherwise). Recomputes the asset **from** `deprecated` — checking both of
    /// rule 1's causes, so a still-`not_needed` requirement leaves it deprecated (§6.3).
    case unrejectRequirement(id: UUID, priorState: ReviewState?)
    /// Re-checks `UNIQUE(entity_id, name_normalized)` and rewrites `name_normalized`.
    case renameRequirement(id: UUID, name: String)
    case setRequirementReason(id: UUID, text: String)
    /// The roadmap's "mark optional" and "mark no dedicated asset needed"; recomputes the
    /// asset in-group (§6.3 rule 1).
    case setRequirementNecessity(id: UUID, necessity: RequirementNecessity)
    /// Variant tier only. `linkID` pins the row id so an undone removal comes back with its
    /// original id, and `restoring` carries that row's snapshot when this op is an inverse —
    /// the `addAlias` shape, for the same §3.8 reason.
    ///
    /// A human add whose `(requirement_id, scene_id)` matches a **tombstoned** row
    /// un-rejects that row (one journal entry, inverse = reject) instead of raw-failing the
    /// UNIQUE key.
    case addRequirementScene(
        requirementID: UUID,
        sceneID: UUID,
        linkID: UUID?,
        restoring: [RowSnapshot]
    )
    /// Removal of an `ai`/`parser` row tombstones it (Phase 1 §3.6).
    case removeRequirementScene(linkID: UUID)
    /// Human scene-specific suppression of one linked reference. The entity's
    /// appearance, requirement, media, and membership in every other scene stay intact.
    case excludeReferenceFromScene(
        sceneID: UUID,
        requirementID: UUID,
        exclusionID: UUID?,
        restoring: [RowSnapshot]
    )
    case includeReferenceInScene(exclusionID: UUID)
    /// Full-graph cycle and self-edge check before any write; both endpoints non-rejected.
    /// A human add matching a tombstoned pair un-rejects it — after the cycle check.
    case addDependency(
        requirementID: UUID,
        dependsOnID: UUID,
        dependencyID: UUID?,
        restoring: [RowSnapshot]
    )
    /// Removal of an `ai`/`parser` row tombstones it, which is what makes a deliberate
    /// removal stick across refreshes and inference (§3.5).
    case removeDependency(id: UUID)
    /// §7.2's combine, fully specified there: variant tier only, cross-entity sources
    /// permitted, assets merged by the total survivor rule, sources tombstoned.
    case combineRequirements(sourceIDs: [UUID], into: UUID)
    /// `combineRequirements`' payload-driven, hand-ordered inverse.
    case uncombineRequirements(payload: RequirementCombinePayload)
    /// §7.2's split: `sceneIDs` must be a **nonempty proper subset** of the source's stored
    /// links; the source keeps its asset and the split-off requirement is born empty.
    case splitRequirement(id: UUID, sceneIDs: [UUID], newName: String, newID: UUID)
    /// `splitRequirement`'s payload-driven inverse: every created row deleted, copies
    /// included, and every moved row back byte-identically.
    case unsplitRequirement(payload: RequirementSplitPayload)
    /// §3.3's override, human-only.
    case setManifestInclusion(entityID: UUID, inclusion: ManifestInclusion)

    // MARK: - Template entries (§7.2; settings, not facts)

    case setTemplateEntryEnabled(typeID: UUID, isEnabled: Bool)
    case renameTemplateEntry(typeID: UUID, displayName: String)
    case setTemplateEntryOrder(typeID: UUID, sortOrder: Int)
    case addTemplateEntry(
        id: UUID,
        kind: EntityKind,
        code: String,
        displayName: String,
        sortOrder: Int
    )
    /// Refused while **any** requirement references the entry, tombstoned rows included —
    /// `ON DELETE RESTRICT` backs it. Disable instead.
    case removeTemplateEntry(typeID: UUID)
    /// `removeTemplateEntry`'s inverse.
    case restoreTemplateEntry(snapshot: [RowSnapshot])

    // MARK: - Assets and versions (§7.3; Plan 011 step 1)

    /// §7.3's `createAsset`. Composed into the **first import's** group, so first-import
    /// undo *and redo* work; the requirement must be active (§6.4).
    ///
    /// `restoring` carries the asset row's snapshot when this op is `removeAssetRow`'s
    /// inverse — the `addAlias` shape, for the same §3.8 reason: a redo must bring the row
    /// back byte-identically rather than stamp a fresh `created_at`.
    case createAsset(id: UUID, requirementID: UUID, restoring: [RowSnapshot])
    /// `createAsset`'s inverse: **rows only, never files** (§4.1's orphan rule). Its own
    /// inverse is a `createAsset` carrying the snapshot it took.
    case removeAssetRow(assetID: UUID)
    /// The journaled half of media import (§7.3). The file is staged **before** the
    /// transaction and removed on any throw (§4.1); `versionNumber` is max + 1 assigned
    /// in-transaction; the import is refused while the requirement is inactive (§6.3) and
    /// clears a standing explicit rejection.
    ///
    /// Applying it — first time or as a redo — **re-verifies that the file exists and that
    /// its SHA-256 still matches** before inserting the row (§7.3's pinned walk), which is
    /// why it needs the bundle's containment rather than the database alone.
    case importAssetVersion(
        versionID: UUID,
        assetID: UUID,
        versionNumber: Int,
        relativePath: RelativeProjectPath,
        sha256: String,
        byteCount: Int,
        originalFileName: String,
        mediaKind: MediaKind,
        pixelWidth: Int?,
        pixelHeight: Int?,
        /// PHASE3_DESIGN §7.3's lineage stamp: which prompt produced this version. The
        /// caller's claim, never inferred from data; every shipped call site passes `nil`
        /// until Plan 015's workshop passes the current prompt's id.
        promptID: UUID?,
        restoring: [RowSnapshot]
    )
    /// `importAssetVersion`'s inverse: the **row only**, the file kept as an orphan (§4.1).
    /// Asset-row changes the import made are restored from the snapshot it took.
    case removeVersionRow(versionID: UUID)
    /// §7.3's version verdict. Its inverse is the payload-driven prior-status restore.
    case rejectVersion(versionID: UUID)
    /// The **user gesture**: un-rejecting is "reconsider", so it always lands
    /// `needs_review` (§6.3's first stated asymmetry). Its inverse is `rejectVersion`.
    case unrejectVersion(versionID: UUID)
    /// `rejectVersion`'s inverse: the snapshotted prior status back **exactly** — inverse
    /// application is byte-identical restoration, not a gesture (§6.3).
    case restoreVersionStatus(versionID: UUID, status: AssetVersionStatus)
    /// §7.3: **non-invertible**. Allowed only on a `rejected` version; the row goes in the
    /// transaction and the file after commit (§4.1), and removing the last version clears a
    /// standing explicit rejection.
    case deleteVersion(versionID: UUID)
    /// Plan 024's archive-only destroyer: **non-invertible**, and accepted only while the
    /// version is `needs_review`. The caller owns the permanent-delete confirmation.
    case deleteArchivedVersion(versionID: UUID)
    /// §7.3: **non-invertible**. The asset row, its version rows, and — after commit —
    /// their files.
    case deleteAsset(id: UUID)
    /// §7.3's `approveVersion`, in **one** transaction: the previously approved version is
    /// demoted to `needs_review` *first* (the partial unique index is enforced per
    /// statement), the target is approved, §6.3's recompute writes the status, the asset's
    /// **own** staleness is cleared (§3.5's first clearing gesture), and — only when the
    /// approved version actually *changed* — every asset of every requirement that depends
    /// on this one is marked stale. The affected set names all of them.
    case approveVersion(assetID: UUID, versionID: UUID)
    /// `approveVersion`'s **hand-ordered, payload-driven** inverse (§7.3). Never a gesture:
    /// there is no "unapprove" in the design, only the undo of an approve.
    case unapproveVersion(payload: AssetApprovalPayload)
    /// Plan 024's direct-card clear gesture. The named version must currently be approved.
    case archiveCurrentVersion(assetID: UUID, versionID: UUID)
    /// Hand-ordered inverse of `archiveCurrentVersion`: neutralize any current approval,
    /// then restore every snapshotted row byte-identically.
    case restoreArchivedVersion(payload: AssetArchivePayload)
    /// §3.5's second staleness-clearing gesture — the explicit "Mark Current".
    case clearAssetStale(assetID: UUID)
    /// `clearAssetStale`'s inverse: the three staleness columns back from the snapshot.
    /// Inverse-only; the payload exists so the case is total outside `.inverting` mode.
    case restoreAssetStale(assetID: UUID, snapshot: [RowSnapshot])
    /// Internal bundle-sync primitive used only inside a successful image-edit group.
    case markAssetStale(assetID: UUID, reason: String)
    case restoreMarkedAssetStale(assetID: UUID, snapshot: [RowSnapshot], reason: String)
    /// §6.3 rule 3's standing explicit rejection. Precondition: no approved version.
    case rejectAsset(assetID: UUID)
    /// `rejectAsset`'s inverse, and a gesture of its own.
    case unrejectAsset(assetID: UUID)
    case setAssetNotes(id: UUID, text: String)
    case setVersionNotes(id: UUID, text: String)

    // MARK: - Prompts (PHASE3_DESIGN §7.2; Plan 014 contract B)

    /// §7.2's `createPrompt` — the human path (§5.4). The requirement must be **accepted**
    /// and active; *not* blockage-gated (§3.3 — a human pasting their own prompt is
    /// overriding the plan deliberately). `prompt_number` = max + 1 in-transaction;
    /// `input_digest` is computed in-transaction by `AssetPromptInputBuilder` (it hashes
    /// inputs, not the body). Composition into a first gesture's group happens at the
    /// call site (§7.1); `restoring` makes the redo byte-identical, the `createAsset`
    /// shape.
    case createPrompt(
        id: UUID,
        requirementID: UUID,
        body: String,
        targetModel: String,
        restoring: [RowSnapshot]
    )
    /// §7.2's engine-internal apply op (§3.7, §8.4 step 2) — only
    /// `applyAssetPromptRun` emits it (Plan 016), and nothing in the app emits it after
    /// Plan 014. The digest and format version are **supplied by the caller** (the
    /// applier's step-0 rebuilt value, never re-rendered here); the citation rows are
    /// derived in-op from §3.3's shared ordering over the rendered references. Fixed
    /// `ai` provenance on its own asset-row and prompt-row inserts in one mutate; born
    /// `accepted` through its own insert, never the shared `insertProvenance`. Same
    /// preconditions as `createPrompt` plus §3.3's blockage refusal.
    case attachGeneratedPrompt(
        promptID: UUID,
        assetID: UUID,
        requirementID: UUID,
        body: String,
        targetModel: String,
        guidance: String,
        inputDigest: String,
        inputFormatVersion: Int,
        skillIdentity: AssetPromptSkillIdentity
    )
    /// Its inverse: snapshot restore removing its prompt, citation, and asset-row inserts
    /// **together** (§7.2).
    case removeAttachedPrompt(payload: GeneratedPromptPayload)
    /// §7.2's `setPromptBody`: current prompt only; converts `source` to `human` (skill
    /// provenance survives on `created_source`, §4.3); same body validation as create;
    /// leaves `input_digest` untouched. Its own inverse, prior value.
    case setPromptBody(promptID: UUID, body: String)
    /// §7.2's `deletePrompt`: any row, current or history; snapshots the prompt row, its
    /// citations, and every citing `asset_versions.prompt_id` value it nulls (§4.3's
    /// rule — those versions may live under another requirement's asset after a combine).
    /// Rows only — no file is ever involved.
    case deletePrompt(promptID: UUID)
    /// `deletePrompt`'s inverse: everything back byte-identically, the nulled stamps
    /// included.
    case restoreDeletedPrompt(payload: DeletedPromptPayload)
    /// §7.2's `markAssetInProgress` (§14.7): an explicit, journaled gesture setting
    /// `in_progress_since` to now. Refused while any version row exists (§5.5, §6.1);
    /// composes `createAsset` per §7.1 when no row exists. Recompute runs.
    case markAssetInProgress(requirementID: UUID)
    /// §7.2's `clearAssetInProgress`. Its inverse restores the prior timestamp
    /// byte-exactly — never a re-stamp (§7.1).
    case clearAssetInProgress(assetID: UUID)
    /// `clearAssetInProgress`'s inverse-only arm: the prior marker value back exactly.
    case restoreAssetInProgress(assetID: UUID, timestamp: Date?)

    // MARK: - Scene prompts and project generation settings (PHASE5_DESIGN §7.1; Plan 019 contract A)

    /// §7.1's `createScenePrompt` — **the human counterpart of the AI attach, with the same
    /// provenance contract**: §8.1's pre-flight (Asset Ready read from Plan 017's snapshot,
    /// counted scene, cataloged profile, within the profile limit) and, inside its own
    /// transaction, a rebuild of the §8.2 input through `ScenePromptInputBuilder.snapshot` —
    /// the one capture path the apply's step 0 shares — recording digest,
    /// `input_format_version`, citation rows from the plan the digest was computed over,
    /// and profile settings. Provenance `human`/`human`; the skill triple is empty (the v6
    /// CHECK binds it). `restoring` makes the redo byte-identical, the `createPrompt` shape.
    case createScenePrompt(
        id: UUID,
        sceneID: UUID,
        body: String,
        guidance: String,
        durationSeconds: Int?,
        aspectRatio: String,
        resolution: String,
        restoring: [RowSnapshot]
    )
    /// §7.1's `setScenePromptBody`: current prompt only; converts provenance `source` to
    /// `human` while `created_source` keeps skill provenance; captured citations and digest
    /// are untouched — they record what the prompt was written against, not what it says.
    /// Its own inverse, prior value.
    case setScenePromptBody(promptID: UUID, body: String)
    /// §7.1's `deleteScenePrompt`: any row, current or history; snapshots the prompt row
    /// and its citation rows. Delete-the-newest restores the prior row to current by rule
    /// (§3.1 — current is the highest number).
    case deleteScenePrompt(promptID: UUID)
    /// `deleteScenePrompt`'s inverse: everything back byte-identically.
    case restoreDeletedScenePrompt(payload: DeletedScenePromptPayload)
    /// Phase 5c canonical set operations. The singular cases above remain decode-only
    /// compatibility for journals created by schema v8.
    case createScenePromptSet(
        setID: UUID, sceneID: UUID, cards: [ScenePromptCardDraft], restoring: [RowSnapshot]
    )
    case editScenePromptCard(cardID: UUID, draft: ScenePromptCardDraft)
    case addScenePromptCard(cardID: UUID, setID: UUID, draft: ScenePromptCardDraft)
    case deleteScenePromptCard(cardID: UUID)
    case reorderScenePromptCards(setID: UUID, orderedCardIDs: [UUID])
    case deleteScenePromptSet(setID: UUID)
    case restoreScenePromptSet(payload: ScenePromptSetSnapshotPayload)
    /// §3.6's style bible — one free-text document per project, digest input, so editing it
    /// stales every scene prompt in the project (deliberate, §6.2). Own inverse, prior text.
    case setStyleBible(text: String)
    /// §3.3's headline flip — the persisted active target profile P every headline state,
    /// count, and batch set reads against. Trivially invertible; stales nothing (§6.2 —
    /// each prompt row's digest is its own profile's).
    case setGenerationTargetProfile(profileID: String)

    // MARK: - Skill import (PHASE5_DESIGN §14.6; Plan 019 contract B)

    /// §14.6's import-into-bundle: the `imported_skills` row for a tree already copied
    /// under `skills/`. **The media-import posture verbatim** (§7.1): every mode re-verifies
    /// the retained tree against `tree_sha256` through the containment **before any write**
    /// — the apply trusts nothing about its caller's copy, and the redo refuses via
    /// `.importedSkillTreeMissing` when the orphaned tree was swept or altered. Undo
    /// removes the row (and any selection) and leaves the tree an orphan; file bytes are
    /// never journal payload. `restoring` makes the redo byte-identical once verified.
    case importSceneSkill(
        id: UUID,
        relativeRoot: String,
        displayName: String,
        entryRelativePath: String,
        routingRelativePath: String,
        treeSHA256: String,
        restoring: [RowSnapshot]
    )
    /// `importSceneSkill`'s inverse: the row out, the tree stays. The payload carries the
    /// row as inserted so the redo restores byte-identically after re-verification.
    case removeImportedSkill(payload: ImportedSkillPayload)
    /// §14.6's selection flip — `projects.scene_skill_id`; `nil` selects the bundled
    /// default. Trivially invertible; stales nothing (skill payload is outside the
    /// digest, §7.1). Own inverse, prior value.
    case selectSceneSkill(skillID: UUID?)

    // MARK: - The scene-prompt AI attach (PHASE5_DESIGN §7.1, §8.4; Plan 021 contract C)

    /// §8.4 step 2's engine-internal apply op — the `attachGeneratedPrompt` shape at
    /// scene scale, and **the AI actor's entire scene write surface** (§3.9). Only
    /// `applyScenePromptRun` emits it. The digest and format version are supplied by the
    /// caller (the applier's step-0 rebuilt value, never re-rendered here); the citation
    /// rows are derived in-op from §3.2's plan over the state the digest was computed
    /// against. Fixed `ai` provenance on its own inserts in one mutate; born `accepted`
    /// through its own insert, never the shared `insertProvenance`. Step 1's cheap
    /// preconditions — the scene still counted, the persisted profile still cataloged —
    /// are re-checked here, outside the digest.
    case attachGeneratedScenePrompt(
        promptID: UUID,
        sceneID: UUID,
        body: String,
        guidance: String,
        durationSeconds: Int?,
        aspectRatio: String,
        resolution: String,
        inputDigest: String,
        inputFormatVersion: Int,
        skillIdentity: AssetPromptSkillIdentity
    )
    /// Its inverse: snapshot restore removing its prompt and citation inserts
    /// **together** (§7.1).
    case removeAttachedScenePrompt(payload: GeneratedScenePromptPayload)
    case attachGeneratedScenePromptSet(
        setID: UUID,
        sceneID: UUID,
        cards: [ScenePromptCardDraft],
        inputDigest: String,
        inputFormatVersion: Int,
        skillIdentity: AssetPromptSkillIdentity
    )
    case removeAttachedScenePromptSet(payload: ScenePromptSetSnapshotPayload)

    /// §5.2's **Build Asset Manifest**: the compound a `performGroup` of
    /// `createCanonicalRequirement` children journals. `compoundChildren` is deliberately
    /// `nil` for it — the children depend on database state, and that property must stay a
    /// pure function, so the refresh builds them at the `performGroup` call site.
    case refreshCanonicalRequirements

    // MARK: - Runs (§3.8, §8.5; Plan 007 populates them)

    /// The trailing summary row of an apply. Non-invertible: a run is reversed only
    /// through `revertExtractionRun`, and selective revert skips this row.
    case applyExtractionRun(ApplyReport)
    /// The trailing summary row of a **manifest** apply (PHASE2_DESIGN §8.4 step 6, §8.5).
    /// Non-invertible with `compoundChildren = nil`, exactly like `.applyExtractionRun`,
    /// and skipped by selective revert for the same reason: it carries the report and
    /// nothing else.
    case applyManifestRun(ManifestApplyReport)
    /// Selective revert of a run. Non-invertible — revert is not itself undoable.
    case revertExtractionRun(jobID: UUID)

    /// `true` for the prompt apply's own case (PHASE3_DESIGN §13.11): the one AI entry
    /// whose arrival must not clear the app's undo stack, because the apply is invertible
    /// by design. Plan 016's undo bridge reads this instead of pattern-matching.
    public var isAttachGeneratedPrompt: Bool {
        if case .attachGeneratedPrompt = self { return true }
        return false
    }

    /// The scene-scale twin (PHASE5_DESIGN §8.4): `attachGeneratedScenePrompt`'s arrival
    /// must not clear the stack either — ⌘Z reads "Undo Generate Scene Prompt".
    public var isAttachGeneratedScenePrompt: Bool {
        switch self {
        case .attachGeneratedScenePrompt, .attachGeneratedScenePromptSet:
            return true
        default:
            return false
        }
    }

    /// The human-facing name of the operation, as the journal and the undo menu show it.
    ///
    /// This is the **only** source of undo action names (§3.8).
    public var displayName: String {
        switch self {
        case .appendScenes: "Add Scenes"
        case .importScreenplay: "Import Screenplay"
        case .replaceScreenplay: "Replace Screenplay"

        case let .createEntity(_, kind, _, _): "Create \(kind.undoNoun)"
        case let .deleteEntity(_, kind): "Delete \(kind.undoNoun)"
        case let .rejectEntity(_, kind): "Reject \(kind.undoNoun)"
        case let .unrejectEntity(_, kind, _): "Restore \(kind.undoNoun)"
        case let .renameEntity(_, kind, _): "Rename \(kind.undoNoun)"
        case .setDescription: "Change Description"
        case .reclassify: "Change Kind"
        case .setRelevance: "Change Relevance"
        case .setLocationParent: "Move Location"

        case .addAlias: "Add Alias"
        case .removeAlias: "Remove Alias"

        case .mergeEntities: "Merge Entities"
        case .splitEntity: "Split Entity"

        case .setSceneEntity: "Add Entity to Scene"
        case .removeSceneEntity: "Remove Entity from Scene"
        case .setSynopsis: "Edit Synopsis"
        case .setSceneText: "Edit Screenplay"
        case .setScenePromptDirection: "Add Direction"

        case .addState: "Add State"
        case .editState: "Edit State"
        case .removeState: "Remove State"
        case .addEvent: "Add Continuity Event"
        case .editEvent: "Edit Continuity Event"
        case .removeEvent: "Remove Continuity Event"
        case .addRelationship: "Add Relationship"
        case .removeRelationship: "Remove Relationship"

        case let .lock(_, field): "Lock \(field.displayName)"
        case let .unlock(_, field): "Unlock \(field.displayName)"

        case .acceptFact: "Accept Fact"
        case .unacceptFact: "Unaccept Fact"

        case .restoreEntity: "Restore Entity"
        case .unmerge: "Unmerge Entities"
        case .unsplit: "Unsplit Entity"
        case .rejectSubject: "Reject Fact"
        case .unrejectSubject: "Restore Fact"

        case let .batch(children): Self.batchName(children)
        case let .acceptAll(refs, scope):
            scope == .allProposed ? "Accept All Proposed" : Self.counted("Accept", refs.count, "Fact", "Facts")

        case .createRequirement: "Create Requirement"
        case .createCanonicalRequirement: "Add Canonical Requirement"
        case .deleteRequirement: "Delete Requirement"
        case .restoreRequirement: "Restore Requirement"
        case .rejectRequirement: "Reject Requirement"
        case .unrejectRequirement: "Restore Requirement"
        case .renameRequirement: "Rename Requirement"
        case .setRequirementReason: "Change Requirement Reason"
        case .setRequirementNecessity: "Change Requirement Necessity"
        case .addRequirementScene: "Add Scene to Requirement"
        case .removeRequirementScene: "Remove Scene from Requirement"
        case .excludeReferenceFromScene: "Remove Reference from Scene"
        case .includeReferenceInScene: "Restore Reference to Scene"
        case .addDependency: "Add Dependency"
        case .removeDependency: "Remove Dependency"
        case .combineRequirements: "Combine Requirements"
        case .uncombineRequirements: "Uncombine Requirements"
        case .splitRequirement: "Split Requirement"
        case .unsplitRequirement: "Unsplit Requirement"
        case .setManifestInclusion: "Change Manifest Inclusion"

        case let .setTemplateEntryEnabled(_, isEnabled):
            isEnabled ? "Enable Template Entry" : "Disable Template Entry"
        case .renameTemplateEntry: "Rename Template Entry"
        case .setTemplateEntryOrder: "Reorder Template Entry"
        case .addTemplateEntry: "Add Template Entry"
        case .removeTemplateEntry: "Remove Template Entry"
        case .restoreTemplateEntry: "Restore Template Entry"

        case .createAsset: "Add Asset"
        case .removeAssetRow: "Remove Asset"
        case .importAssetVersion: "Import Reference Image"
        case .removeVersionRow: "Remove Reference Image"
        case .rejectVersion: "Reject Version"
        case .unrejectVersion: "Reconsider Version"
        case .restoreVersionStatus: "Restore Version Status"
        case .deleteVersion: "Delete Version"
        case .deleteArchivedVersion: "Delete Archived Image"
        case .deleteAsset: "Delete Asset"
        case .approveVersion: "Approve Version"
        case .unapproveVersion: "Restore Previous Approval"
        case .archiveCurrentVersion: "Archive Reference Image"
        case .restoreArchivedVersion: "Restore Archived Reference Image"
        case .clearAssetStale: "Mark Current"
        case .restoreAssetStale: "Restore Stale Badge"
        case .markAssetStale: "Synchronize Character Bundle"
        case .restoreMarkedAssetStale: "Restore Character Bundle Sync"
        case .rejectAsset: "Reject Asset"
        case .unrejectAsset: "Restore Asset"
        case .createPrompt: "Write Prompt"
        case .attachGeneratedPrompt: "Generate Prompt"
        case .removeAttachedPrompt: "Generate Prompt"
        case .setPromptBody: "Edit Prompt"
        case .deletePrompt: "Delete Prompt"
        case .restoreDeletedPrompt: "Delete Prompt"
        case .markAssetInProgress: "Mark In Progress"
        case .clearAssetInProgress: "Clear In Progress"
        case .restoreAssetInProgress: "Clear In Progress"
        case .setAssetNotes: "Change Asset Notes"
        case .setVersionNotes: "Change Version Notes"

        case .createScenePrompt: "Write Scene Prompt"
        case .setScenePromptBody: "Edit Scene Prompt"
        case .deleteScenePrompt: "Delete Scene Prompt"
        case .restoreDeletedScenePrompt: "Delete Scene Prompt"
        case .createScenePromptSet: "Write Prompt Set"
        case .editScenePromptCard: "Edit Prompt Card"
        case .addScenePromptCard: "Add Prompt Card"
        case .deleteScenePromptCard: "Delete Prompt Card"
        case .reorderScenePromptCards: "Reorder Prompt Cards"
        case .deleteScenePromptSet: "Delete Prompt Set"
        case .restoreScenePromptSet: "Edit Prompt Set"
        case .setStyleBible: "Set Style Bible"
        case .setGenerationTargetProfile: "Change Target Profile"

        case .importSceneSkill: "Import Skill"
        case .removeImportedSkill: "Import Skill"
        case .selectSceneSkill: "Select Skill"

        case .attachGeneratedScenePrompt: "Generate Scene Prompt"
        case .removeAttachedScenePrompt: "Generate Scene Prompt"
        case .attachGeneratedScenePromptSet: "Generate Prompt Set"
        case .removeAttachedScenePromptSet: "Generate Prompt Set"

        case .refreshCanonicalRequirements: "Build Asset Manifest"

        case .applyExtractionRun: "Apply Analysis Run"
        case .applyManifestRun: "Apply Manifest Run"
        case .revertExtractionRun: "Revert Analysis Run"
        }
    }

    /// `false` for every operation whose inverse is always `nil` — stated in the UI before
    /// it runs. An operation may still turn out non-invertible at `mutate` time; this is
    /// the static half of the answer.
    ///
    /// **Every** PHASE2_DESIGN §7.2 operation is invertible — the table there names an
    /// inverse for each of them, `refreshCanonicalRequirements` included (a `.batch` of its
    /// children's inverses) — so none of them appears in the `false` list. §7.3's
    /// `deleteAsset` and `deleteVersion`, and §8.5's `applyManifestRun`, are the
    /// non-invertible Phase 2 cases, and they belong to Plans 011 and 012.
    public var isInvertible: Bool {
        switch self {
        case .appendScenes, .importScreenplay, .replaceScreenplay, .applyExtractionRun, .applyManifestRun,
             .revertExtractionRun:
            false
        // §7.3's two destroyers of media, stated in the UI before they run.
        case .deleteAsset, .deleteVersion, .deleteArchivedVersion:
            false
        case let .batch(children):
            !children.isEmpty && children.allSatisfy(\.isInvertible)
        default:
            true
        }
    }

    /// The children a compound case groups, or `nil` when the case is not compound.
    ///
    /// `applyInverse` and the batch wrappers route through this so a compound inverse is
    /// journaled by `performGroup` — one row whose payload holds the child inverses in
    /// order — rather than as an opaque single operation.
    var compoundChildren: [EditOperation]? {
        switch self {
        case let .batch(children):
            children
        case let .acceptAll(refs, _):
            refs.map { EditOperation.acceptFact($0) }
        case let .mergeEntities(sourceIDs, target, nameAliasIDs) where sourceIDs.count > 1:
            sourceIDs.enumerated().map { index, source in
                EditOperation.mergeEntities(
                    sourceIDs: [source],
                    into: target,
                    // Deliberately not minted here: `compoundChildren` must be a pure
                    // function of the operation, or a redo would draw a different id.
                    nameAliasIDs: index < nameAliasIDs.count ? [nameAliasIDs[index]] : []
                )
            }
        // PHASE2_DESIGN §7.5: **every** new case returns `nil`,
        // `refreshCanonicalRequirements` included — its children depend on database state
        // and this property must stay a pure function, so the refresh builds them at the
        // `performGroup` call site instead.
        default:
            nil
        }
    }

    /// "Delete 4 Entities": a batch names its children's shared verb, or its size.
    private static func batchName(_ children: [EditOperation]) -> String {
        let count = children.count
        guard let first = children.first else { return "No Changes" }
        func all(_ predicate: (EditOperation) -> Bool) -> Bool { children.allSatisfy(predicate) }

        // PHASE2_DESIGN §7.3: a media import is a group — the implicit accept of a
        // proposed requirement, `createAsset`, and the version insert — and the filmmaker
        // performed **one** gesture, so the undo menu names that gesture rather than
        // counting its parts. (Pure, like the rest of this function: it reads the
        // children and nothing else.)
        if children.contains(where: \.isImportAssetVersion) { return "Import Reference Image" }
        // §14.6: import + auto-select journals as one grouped entry — one gesture, so the
        // undo menu names that gesture rather than counting its parts (Plan 019).
        if children.contains(where: \.isImportSceneSkill) { return "Import Skill" }

        switch first {
        case .deleteEntity where all(\.isDeleteEntity):
            return counted("Delete", count, "Entity", "Entities")
        case .rejectEntity where all(\.isRejectEntity):
            return counted("Reject", count, "Entity", "Entities")
        case .unrejectEntity where all(\.isUnrejectEntity):
            return counted("Restore", count, "Entity", "Entities")
        case .setRelevance where all(\.isSetRelevance):
            return counted("Change Relevance of", count, "Entity", "Entities")
        case .mergeEntities where all(\.isMergeEntities):
            return "Merge Entities"
        case .acceptFact where all(\.isAcceptFact):
            return counted("Accept", count, "Fact", "Facts")
        case .unacceptFact where all(\.isUnacceptFact):
            return counted("Unaccept", count, "Fact", "Facts")
        // PHASE2_DESIGN §7.5's counted batch names ("Delete 3 Requirements").
        case .deleteRequirement where all(\.isDeleteRequirement):
            return counted("Delete", count, "Requirement", "Requirements")
        case .rejectRequirement where all(\.isRejectRequirement):
            return counted("Reject", count, "Requirement", "Requirements")
        case .unrejectRequirement where all(\.isUnrejectRequirement):
            return counted("Restore", count, "Requirement", "Requirements")
        case .setRequirementNecessity where all(\.isSetRequirementNecessity):
            return counted("Change Necessity of", count, "Requirement", "Requirements")
        case .createCanonicalRequirement where all(\.isCreateCanonicalRequirement):
            return "Build Asset Manifest"
        default:
            return counted("", count, "Change", "Changes")
        }
    }

    /// "Accept 1 Fact" / "Accept 2 Facts".
    private static func counted(_ verb: String, _ count: Int, _ singular: String, _ plural: String) -> String {
        let noun = count == 1 ? singular : plural
        return verb.isEmpty ? "\(count) \(noun)" : "\(verb) \(count) \(noun)"
    }

    private var isDeleteEntity: Bool { if case .deleteEntity = self { true } else { false } }
    private var isRejectEntity: Bool { if case .rejectEntity = self { true } else { false } }
    private var isUnrejectEntity: Bool { if case .unrejectEntity = self { true } else { false } }
    private var isSetRelevance: Bool { if case .setRelevance = self { true } else { false } }
    private var isMergeEntities: Bool { if case .mergeEntities = self { true } else { false } }
    private var isAcceptFact: Bool { if case .acceptFact = self { true } else { false } }
    private var isUnacceptFact: Bool { if case .unacceptFact = self { true } else { false } }
    private var isDeleteRequirement: Bool { if case .deleteRequirement = self { true } else { false } }
    private var isRejectRequirement: Bool { if case .rejectRequirement = self { true } else { false } }
    private var isUnrejectRequirement: Bool {
        if case .unrejectRequirement = self { true } else { false }
    }
    private var isSetRequirementNecessity: Bool {
        if case .setRequirementNecessity = self { true } else { false }
    }
    private var isImportAssetVersion: Bool {
        if case .importAssetVersion = self { true } else { false }
    }
    private var isImportSceneSkill: Bool {
        if case .importSceneSkill = self { true } else { false }
    }
    private var isCreateCanonicalRequirement: Bool {
        if case .createCanonicalRequirement = self { true } else { false }
    }
}

// MARK: - Payloads for the merge/split-shaped inverses (PHASE2_DESIGN §7.2)

/// Everything `uncombineRequirements` needs to put a combine back byte-identically.
///
/// Nothing is guessed at undo time: a combine **creates no row**, so the whole inverse is
/// "neutralize, then restore". `neutralizeVersionIDs` is the hand-ordering §7.2 demands —
/// the survivor's approved version is demoted to `needs_review` before any snapshot goes
/// back, because the `WHERE status = 'approved'` partial unique index is enforced per
/// statement and is invisible to the snapshot store's collision precheck (§7.3, §7.5). Every
/// id in that list is also snapshotted, so the demotion is undone by the restore that
/// follows it.
public struct RequirementCombinePayload: Codable, Equatable, Hashable, Sendable {
    /// The requirement everything moved onto.
    public let target: UUID
    /// The requirements that were tombstoned, in the order the combine consumed them —
    /// which is also the order version renumbering used.
    public let sourceIDs: [UUID]
    /// Rows the combine re-pointed: scene links, basis rows, dependencies, the surviving
    /// asset, and the version rows that moved under it.
    public let moved: [SubjectRef]
    /// Rows the combine removed: collision losers, and the losing asset rows.
    public let removed: [SubjectRef]
    /// Version rows to demote **before** restoring anything (see above).
    public let neutralizeVersionIDs: [UUID]
    /// Full snapshots of every row the combine touched, as it was before.
    public let snapshots: [RowSnapshot]

    public init(
        target: UUID,
        sourceIDs: [UUID],
        moved: [SubjectRef],
        removed: [SubjectRef],
        neutralizeVersionIDs: [UUID],
        snapshots: [RowSnapshot]
    ) {
        self.target = target
        self.sourceIDs = sourceIDs
        self.moved = moved
        self.removed = removed
        self.neutralizeVersionIDs = neutralizeVersionIDs
        self.snapshots = snapshots
    }
}

/// Everything `unapproveVersion` needs to put an `approveVersion` back byte-identically
/// (PHASE2_DESIGN §7.3).
///
/// The inverse is **hand-ordered, not a generic snapshot restore**, for the reason §7.3
/// states: `index_asset_versions_approved` is a `WHERE status = 'approved'` partial unique
/// index, enforced per statement and invisible to `RowSnapshotStore.wouldCollide`, so
/// restoring the prior approved row while the newly approved one still stands fails. The
/// inverse therefore demotes `versionID` to `needs_review` **first** and only then restores
/// the snapshots — the same "neutralize, then restore" shape as
/// `RequirementCombinePayload.neutralizeVersionIDs`.
///
/// Nothing is recomputed at undo time: every column of every touched row — the two version
/// rows' statuses, the target asset's `status` and its three staleness columns, and each
/// dependent asset's staleness — travels in `snapshots`.
/// The skill identity one prompt run recorded (PHASE3_DESIGN §3.5, §8.1) —
/// descriptor-relative provenance, never an absolute cache path. Travels on
/// `attachGeneratedPrompt` so the prompt row's three columns land in the same mutate.
public struct AssetPromptSkillIdentity: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var entryPath: String
    public var entrySHA256: String

    public init(id: String, entryPath: String, entrySHA256: String) {
        self.id = id
        self.entryPath = entryPath
        self.entrySHA256 = entrySHA256
    }
}

/// Everything `removeAttachedPrompt` needs to undo or redo a generated-prompt attach
/// (§7.2): snapshots of every row the attach inserted — the anchored asset row when it
/// composed one (§6.1), the prompt row, and its citation rows — taken **as inserted**, so
/// the inverse deletes them by id and the redo restores them byte-identically.
public struct GeneratedPromptPayload: Codable, Equatable, Hashable, Sendable {
    public let requirementID: UUID
    public let assetRow: RowSnapshot?
    public let promptRow: RowSnapshot
    public let citationRows: [RowSnapshot]

    public init(
        requirementID: UUID,
        assetRow: RowSnapshot?,
        promptRow: RowSnapshot,
        citationRows: [RowSnapshot]
    ) {
        self.requirementID = requirementID
        self.assetRow = assetRow
        self.promptRow = promptRow
        self.citationRows = citationRows
    }

    /// Every row the attach inserted, asset row first.
    public var snapshots: [RowSnapshot] {
        (assetRow.map { [$0] } ?? []) + [promptRow] + citationRows
    }
}

/// Everything `restoreDeletedPrompt` puts back (§7.2): the deleted prompt row, its
/// citation rows, and every `asset_versions` row whose `prompt_id` the delete nulled —
/// those versions may belong to another requirement's asset after a combine (§4.3's
/// symmetric rule). Restored byte-identically; nothing recomputed at undo time.
public struct DeletedPromptPayload: Codable, Equatable, Hashable, Sendable {
    public let requirementID: UUID
    /// The anchored asset row as it was before the delete's recompute rewrote its status,
    /// so the inverse restores the slot byte-identically instead of recomputing (§3.8).
    public let assetRow: RowSnapshot?
    public let promptRow: RowSnapshot
    public let citationRows: [RowSnapshot]
    public let citingVersionRows: [RowSnapshot]

    public init(
        requirementID: UUID,
        assetRow: RowSnapshot?,
        promptRow: RowSnapshot,
        citationRows: [RowSnapshot],
        citingVersionRows: [RowSnapshot]
    ) {
        self.requirementID = requirementID
        self.assetRow = assetRow
        self.promptRow = promptRow
        self.citationRows = citationRows
        self.citingVersionRows = citingVersionRows
    }

    /// Every row to put back; `RowGraph.restore` orders them by its FK-safe `tableOrder`.
    public var snapshots: [RowSnapshot] {
        (assetRow.map { [$0] } ?? []) + [promptRow] + citationRows + citingVersionRows
    }
}

/// Everything `restoreDeletedScenePrompt` puts back (§7.1): the deleted scene-prompt row
/// and its citation rows, restored byte-identically. Rows only — no file is ever involved.
public struct DeletedScenePromptPayload: Codable, Equatable, Hashable, Sendable {
    public let sceneID: UUID
    public let promptRow: RowSnapshot
    public let citationRows: [RowSnapshot]

    public init(sceneID: UUID, promptRow: RowSnapshot, citationRows: [RowSnapshot]) {
        self.sceneID = sceneID
        self.promptRow = promptRow
        self.citationRows = citationRows
    }

    /// Every row to put back; `RowGraph.restore` orders them by its FK-safe `tableOrder`.
    public var snapshots: [RowSnapshot] { [promptRow] + citationRows }
}

/// Everything `removeAttachedScenePrompt` needs to undo or redo a generated scene-prompt
/// attach (PHASE5_DESIGN §7.1, §8.4): snapshots of every row the attach inserted — the
/// prompt row and its citation rows — taken **as inserted**, so the inverse deletes them
/// by id and the redo restores them byte-identically. No asset row exists at scene scope.
public struct GeneratedScenePromptPayload: Codable, Equatable, Hashable, Sendable {
    public let sceneID: UUID
    public let promptRow: RowSnapshot
    public let citationRows: [RowSnapshot]

    public init(sceneID: UUID, promptRow: RowSnapshot, citationRows: [RowSnapshot]) {
        self.sceneID = sceneID
        self.promptRow = promptRow
        self.citationRows = citationRows
    }

    /// Every row the attach inserted.
    public var snapshots: [RowSnapshot] { [promptRow] + citationRows }
}

/// Full v9 prompt-set graph for atomic undo/redo of a generated set or any manual card
/// adjustment. Rows are restored in FK-safe order by `RowGraph`.
public struct ScenePromptSetSnapshotPayload: Codable, Equatable, Hashable, Sendable {
    public let setID: UUID
    public let sceneID: UUID
    public let rows: [RowSnapshot]

    public init(setID: UUID, sceneID: UUID, rows: [RowSnapshot]) {
        self.setID = setID
        self.sceneID = sceneID
        self.rows = rows
    }

    public var snapshots: [RowSnapshot] { rows }
}

/// Everything `removeImportedSkill` needs (§14.6): the `imported_skills` row as inserted,
/// so the redo restores byte-identically after re-verifying the retained tree. The copied
/// tree itself is never payload — undo orphans it by design.
public struct ImportedSkillPayload: Codable, Equatable, Hashable, Sendable {
    public let skillRow: RowSnapshot

    public init(skillRow: RowSnapshot) {
        self.skillRow = skillRow
    }

    public var snapshots: [RowSnapshot] { [skillRow] }
}

public struct AssetApprovalPayload: Codable, Equatable, Hashable, Sendable {
    /// The asset whose canonical version changed.
    public let assetID: UUID
    /// The version the approve promoted — the row the inverse demotes before restoring.
    public let versionID: UUID
    /// The version that held the approval before, when there was one. `nil` marks a **first
    /// approval**, which is also why no dependent was marked stale (§3.5).
    public let priorApprovedVersionID: UUID?
    /// Every asset whose staleness columns the approve wrote: the target (cleared) first,
    /// then the dependents it marked, in the order they were marked.
    public let staleAssetIDs: [UUID]
    /// Full snapshots of every row the approve touched, as it was before.
    public let snapshots: [RowSnapshot]

    public init(
        assetID: UUID,
        versionID: UUID,
        priorApprovedVersionID: UUID?,
        staleAssetIDs: [UUID],
        snapshots: [RowSnapshot]
    ) {
        self.assetID = assetID
        self.versionID = versionID
        self.priorApprovedVersionID = priorApprovedVersionID
        self.staleAssetIDs = staleAssetIDs
        self.snapshots = snapshots
    }
}

/// Everything the archive gesture's inverse needs to restore the removed current image
/// and the one-level dependent staleness fan-out byte-identically.
public struct AssetArchivePayload: Codable, Equatable, Hashable, Sendable {
    public let assetID: UUID
    public let versionID: UUID
    public let staleAssetIDs: [UUID]
    public let snapshots: [RowSnapshot]

    public init(
        assetID: UUID,
        versionID: UUID,
        staleAssetIDs: [UUID],
        snapshots: [RowSnapshot]
    ) {
        self.assetID = assetID
        self.versionID = versionID
        self.staleAssetIDs = staleAssetIDs
        self.snapshots = snapshots
    }
}

/// Everything `unsplitRequirement` needs: the rows the split created — the new requirement,
/// the basis **copies** an overlapping footprint produced, and the seeded dependency rows —
/// and full snapshots of the rows it moved, so nothing is recomputed at undo time.
public struct RequirementSplitPayload: Codable, Equatable, Hashable, Sendable {
    public let sourceID: UUID
    public let newID: UUID
    public let newName: String
    /// The scenes the split moved, as the redo would name them again.
    public let sceneIDs: [UUID]
    public let created: [SubjectRef]
    public let moved: [SubjectRef]
    public let snapshots: [RowSnapshot]

    public init(
        sourceID: UUID,
        newID: UUID,
        newName: String,
        sceneIDs: [UUID],
        created: [SubjectRef],
        moved: [SubjectRef],
        snapshots: [RowSnapshot]
    ) {
        self.sourceID = sourceID
        self.newID = newID
        self.newName = newName
        self.sceneIDs = sceneIDs
        self.created = created
        self.moved = moved
        self.snapshots = snapshots
    }
}

/// The noun an undo action name uses for an entity kind ("Rename **Character**").
///
/// Deliberately not `EntityKind.displayName`: the app target already declares one of
/// those, and a second public spelling of the same name would be ambiguous there.
extension EntityKind {
    var undoNoun: String {
        switch self {
        case .character: "Character"
        case .location: "Location"
        case .prop: "Prop"
        case .vehicle: "Vehicle"
        case .creature: "Creature"
        case .object: "Object"
        }
    }
}
