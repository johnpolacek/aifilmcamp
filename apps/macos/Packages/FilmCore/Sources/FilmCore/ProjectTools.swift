import Foundation

// The role protocols of PHASE1_DESIGN §3.9a. Phase 0's single nine-member `ProjectTools`
// becomes a composition so each adapter implements only the role it needs. `ProjectSession`
// is the only conformer in FilmCore.

/// Every v2 read (§6's list).
public protocol ProjectReading: Sendable {
    func projectSnapshot() async throws -> Project
    /// The script named by `projects.current_script_id`; `nil` until a screenplay is imported.
    func script() async throws -> Script?
    func scenes() async throws -> [Scene]
    /// Scene + entities by role + the states active in the scene + ownerless evidence
    /// (synopsis and scene-wide continuity-event rows).
    func scene(id: UUID) async throws -> SceneDetail
    func sceneText(id: UUID) async throws -> String
    func sceneExclusions(id: UUID) async throws -> [SceneExclusion]
    func sequences() async throws -> [ScriptSequence]
    /// Scene-ordinal order; rows with a `NULL` `entity_id` are included.
    func continuityEvents() async throws -> [ContinuityEvent]
    func entities(
        kind: EntityKind?,
        reviewState: ReviewState?,
        includeIrrelevant: Bool,
        includeRejected: Bool
    ) async throws -> [Entity]
    func entitySummaries(
        kind: EntityKind?,
        reviewState: ReviewState?,
        includeIrrelevant: Bool,
        includeRejected: Bool
    ) async throws -> [EntitySummary]
    /// Aliases, appearances, states, events, relationships, evidence, locks, and the
    /// entity's requirement rows (PHASE2_DESIGN §4.4).
    func entity(id: UUID) async throws -> EntityDetail

    // The manifest reads (PHASE2_DESIGN §7.6). Every derived value they return —
    // qualification, active, missing, blocked, stale — comes from `ManifestQualification`,
    // so a list, a badge, and a count can never disagree. All of them exclude rejected rows
    // by default, exactly as the entity reads do.

    /// One entity's requirement rows, canonical before variant.
    func requirements(entityID: UUID, includeRejected: Bool) async throws -> [AssetRequirement]
    /// The manifest list. `kind` filters on the **entity's** kind; `reviewState` on the
    /// requirement's own PROV state.
    func requirementSummaries(
        kind: EntityKind?,
        tier: AssetRequirementTier?,
        reviewState: ReviewState?,
        includeRejected: Bool
    ) async throws -> [RequirementSummary]
    /// The inspector shape: scene links (stored for a variant, derived for a canonical
    /// row), basis rows with their facts' evidence, dependencies both directions, the asset
    /// with its versions, locks, and the derived blocked / active / unreviewed-facts flags.
    func requirement(id: UUID) async throws -> RequirementDetail
    /// §6.4's counts, per kind and overall, plus §5.3's "qualifies but has no canonical
    /// set" entities.
    func manifestSummary() async throws -> ManifestSummary
    /// §6.4's Missing rows, in creation order: canonical first, then variants in dependency
    /// order.
    func missingAssets() async throws -> [MissingAsset]
    /// PHASE4_DESIGN §7.5: the readiness snapshot — per-scene rows, summary fold, and
    /// impact ranking, from one `readinessGraph` load in one read transaction. Every
    /// readiness surface reads this, never a second query (§3.3's consistency rule).
    func readinessSnapshot() async throws -> ReadinessSnapshot
    /// The per-project template (§3.2), disabled entries included.
    func requirementTemplate() async throws -> [AssetRequirementType]
    /// The §8.2 manifest-inference input, built from canonical data alone and rendered
    /// deterministically (PHASE2_DESIGN §3.6, §8.2; `ManifestInputBuilder`).
    ///
    /// FilmBrain calls this when launching an `inferAssetManifest` run — the text is what
    /// the prompt wraps and what `jobs.input_sha256` digests — and §8.4 step 0 rebuilds the
    /// same value inside the apply transaction to prove nothing changed under the run.
    func manifestInput() async throws -> ManifestInputSnapshot
    /// PHASE3_DESIGN §8.1/§8.2: one requirement's rendered asset-prompt input and its
    /// digest (the one prompt digest of §3.4). FilmBrain calls this when launching a
    /// `generateAssetPrompt` run, and §8.4 step 0 rebuilds the same value inside the
    /// apply transaction.
    func assetPromptInput(requirementID: UUID) async throws -> AssetPromptInputSnapshot
    /// Commit token and ordered canonical reference files for one local image-generation
    /// run. The same value must be presented to the grouped import.
    func referenceImageGenerationContext(
        requirementID: UUID,
        generationPromptBody: String?,
        includeCurrentImage: Bool
    ) async throws -> ReferenceImageGenerationContext
    /// Validates and freezes one external image for a single provider run.
    func referenceImageGenerationAttachment(
        from sourceURL: URL,
        entityKind: EntityKind
    ) async throws -> ReferenceImageGenerationAttachment
    /// Revalidates the context and snapshots every canonical dependency through the
    /// bundle's no-follow descriptor door before a local generator is launched.
    func referenceImageGenerationInputs(
        context: ReferenceImageGenerationContext
    ) async throws -> [ReferenceImageGenerationInput]
    /// FilmCore-owned card gates for missing variations, keyed by requirement.
    func referenceImageCreationRefusals(
        requirementIDs: [UUID]
    ) async throws -> [UUID: String]
    /// PHASE5_DESIGN §8.1/§8.2: one scene's rendered scene-prompt input and request
    /// digest. FilmBrain calls this when launching a `generateScenePrompt` run, and
    /// §8.4 step 0 rebuilds the same value inside the apply transaction. A successful
    /// apply consumes any one-time direction and stamps the prompt against the resulting
    /// direction-free canonical basis while the job report retains this request digest.
    func scenePromptInput(sceneID: UUID) async throws -> ScenePromptInputSnapshot
    /// PHASE3_DESIGN §7.5: every prompt row of one requirement, current included (prompts
    /// have no rejected axis), by `prompt_number`. Plan 014's history disclosure reads it.
    func promptHistory(requirementID: UUID) async throws -> [AssetPrompt]
    // MARK: Phase 5a (PHASE5_DESIGN §7.5; Plan 018 contract D)

    /// Every counted scene's package row, ordinal order — asset-ready state read from the
    /// readiness snapshot, package state derived against the active profile P. Excluded
    /// scenes carry no summary (§3.3).
    func scenePackages() async throws -> [ScenePackageSummary]
    /// The §5.2 payload: plan, continuity, current prompt with citations and derived
    /// staleness, history numbers, profile.
    func scenePackageDetail(sceneID: UUID) async throws -> ScenePackageDetail
    /// Archived (`needs_review`) reference images, grouped in the same deterministic order
    /// as the scene's required-reference plan. Empty groups are omitted.
    func sceneReferenceArchives(sceneID: UUID) async throws -> [SceneReferenceArchive]
    /// Every prompt row of `(scene, targetProfile)`, by number ascending.
    func scenePromptHistory(sceneID: UUID, targetProfile: String) async throws -> [ScenePrompt]
    /// Ordered set history, current included, with every card's local immutable citations.
    func scenePromptSetHistory(
        sceneID: UUID, targetProfile: String
    ) async throws -> [ScenePromptSetDetail]
    /// The project's style-bible document; `''` when never set (§3.6).
    func styleBible() async throws -> String
    /// Files under `assets/` that no `asset_versions` row references. Empty until Plan 011
    /// writes media.
    func orphanedMedia() async throws -> [RelativeProjectPath]
    func locks() async throws -> [Lock]
    /// Most recent first.
    func journal(limit: Int) async throws -> [JournalEntry]
    func pendingReviewCount() async throws -> Int
    func extractionProtectionSummary() async throws -> ExtractionProtectionSummary
    /// Parent jobs with usage aggregated over the run.
    func runs() async throws -> [RunSummary]
    func jobHistory() async throws -> [Job]
    func disclosureAcknowledgedAt() async throws -> Date?
}

/// Putting a screenplay into a project, and the §5.5 replace guard.
public protocol ScreenplayImporting: Sendable {
    func previewSceneAppend(text: String) async throws -> SceneAppendPreview
    func appendScenes(_ preview: SceneAppendPreview, actor: MutationActor) async throws -> JournalEntry

    /// Copies `url` into `screenplay/` and writes the whole §5.3 graph in one transaction.
    ///
    /// When the project already has a script this performs §5.5's **Replace**, allowed
    /// only while `canReplaceScreenplay()` is `true`.
    func importScreenplay(from url: URL, actor: MutationActor) async throws -> ImportSummary
    /// `false` once the project holds a protected fact or any lock (§5.5).
    func canReplaceScreenplay() async throws -> Bool
}

/// Runs, chunk jobs, and the paths they write into (§3.9, §4.1).
public protocol JobManaging: Sendable {
    func prepareRunWorkspace(runID: UUID) async throws -> ProjectRunWorkspace
    func prepareChildPaths(runID: UUID, jobID: UUID) async throws -> ProjectJobPaths
    func createJob(_ request: JobRequest) async throws -> Job
    func transitionJob(
        id: UUID,
        to state: Job.State,
        progress: String,
        failureCode: String?,
        failureMessage: String?
    ) async throws -> Job
    /// Records usage and transitions to `completed` in one transaction.
    func completeJob(id: UUID, usage: JobUsage, progress: String) async throws -> Job
    func setEffectiveModel(jobID: UUID, effectiveModel: String?) async throws
    /// Writes an extraction run's report; refuses a job whose task is not
    /// `extractScreenplay`, one that is a child, or one already completed (§7.5).
    func setApplyReport(jobID: UUID, _ report: ApplyReport) async throws
    /// The same door for a manifest run (PHASE2_DESIGN §7.5, §8.5): one nullable JSON
    /// column, two typed setters, each refusing the other's task. Plan 012 is its real
    /// caller — the pre-apply zero-counter write.
    func setManifestReport(jobID: UUID, _ report: ManifestApplyReport) async throws
    func clearJobCache() async throws -> ClearedCacheSummary
    /// PHASE2_DESIGN §4.1's **Clear Orphaned Media**, next to Clear Job Cache: the caller
    /// lists with `orphanedMedia()`, confirms, and passes the confirmed paths here. It runs
    /// through the session (serialized with every write), touches no rows, journals nothing,
    /// and is non-invertible. Paths that stopped being orphans meanwhile are skipped.
    @discardableResult
    func clearOrphanedMedia(confirming paths: [RelativeProjectPath]) async throws -> ClearedCacheSummary
    /// Writes `projects.disclosure_acknowledged_at` (§9); Plan 007 calls it.
    func acknowledgeDisclosure() async throws
}

public struct ClearedCacheSummary: Codable, Equatable, Sendable {
    public let bytesFreed: Int64
    public let filesRemoved: Int

    public init(bytesFreed: Int64, filesRemoved: Int) {
        self.bytesFreed = max(0, bytesFreed)
        self.filesRemoved = max(0, filesRemoved)
    }

    /// PHASE3_DESIGN §3.5: Clear Job Cache sweeps two roots (`cache/jobs` and
    /// `cache/skills`), so its summary is the sum.
    public static func + (lhs: ClearedCacheSummary, rhs: ClearedCacheSummary) -> ClearedCacheSummary {
        ClearedCacheSummary(
            bytesFreed: lhs.bytesFreed + rhs.bytesFreed,
            filesRemoved: lhs.filesRemoved + rhs.filesRemoved
        )
    }

    public static func += (lhs: inout ClearedCacheSummary, rhs: ClearedCacheSummary) {
        lhs = lhs + rhs
    }
}

public extension JobManaging {
    /// Phase 0's convenience overload. It lives here rather than on `ProjectTools`
    /// because a protocol composition cannot be extended.
    func transitionJob(id: UUID, to state: Job.State, progress: String) async throws -> Job {
        try await transitionJob(
            id: id,
            to: state,
            progress: progress,
            failureCode: nil,
            failureMessage: nil
        )
    }

    func completeJob(id: UUID, usage: JobUsage) async throws -> Job {
        try await completeJob(id: id, usage: usage, progress: "Completed")
    }
}

/// Coalesced change notification (§3.9a). No GRDB type appears in the signature.
public protocol ProjectObserving: Sendable {
    func changes() async -> AsyncStream<ProjectChange>
}

/// §6's mutation API. Every call carries a `MutationActor` and returns the applied
/// `JournalEntry` — with its inverse and `displayName` — so the app can register undo.
///
/// Plan 005 step 1 declares the engine's two members: the one scalar operation that
/// exercises it end to end, and the single door for applying an inverse. Steps 2–6 add the
/// rest of §6's list beside them.
public protocol ScreenplayEditing: Sendable {
    /// §6's create. Returns the new entity's id because the UI selects the row it made.
    @discardableResult
    func createEntity(
        kind: EntityKind,
        name: String,
        description: String,
        actor: MutationActor
    ) async throws -> (entry: JournalEntry, entityID: UUID)
    /// Hard delete, allowed only on a `human` row or one already `rejected`; anything else
    /// throws `.rejectInsteadOfDelete(entityID:)` (§3.6).
    @discardableResult
    func deleteEntity(id: UUID, actor: MutationActor) async throws -> JournalEntry
    /// The tombstone that stops resurrection: `rejected` plus a `reviewed_at` stamp, with
    /// aliases and dependent rows retained (§3.6).
    @discardableResult
    func rejectEntity(id: UUID, actor: MutationActor) async throws -> JournalEntry
    /// Restores the state the tombstone replaced (§6).
    @discardableResult
    func unrejectEntity(id: UUID, actor: MutationActor) async throws -> JournalEntry
    /// Renames an entity, keeping the previous name as an alias (§3.5).
    @discardableResult
    func renameEntity(id: UUID, name: String, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func setDescription(id: UUID, text: String, actor: MutationActor) async throws -> JournalEntry
    /// Carries the entity's aliases to the new kind and re-checks uniqueness there (§3.5).
    @discardableResult
    func reclassify(id: UUID, kind: EntityKind, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func setRelevance(id: UUID, isRelevant: Bool, actor: MutationActor) async throws -> JournalEntry
    /// "Move into…": locations only, refusing self and cycles (§6).
    @discardableResult
    func setLocationParent(id: UUID, parentID: UUID?, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func addAlias(entityID: UUID, alias: String, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func removeAlias(aliasID: UUID, actor: MutationActor) async throws -> JournalEntry

    /// The batch UI actions: one journal row, one undo step (§3.8's group level).
    @discardableResult
    func deleteEntities(ids: [UUID], actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func rejectEntities(ids: [UUID], actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func setRelevance(ids: [UUID], isRelevant: Bool, actor: MutationActor) async throws -> JournalEntry

    /// §3.5's merge. `skippedAliases` names the source names whose normalized form already
    /// belonged to an unrelated third entity, so the alias insert was skipped rather than
    /// thrown.
    @discardableResult
    func mergeEntities(
        sourceIDs: [UUID],
        into targetID: UUID,
        actor: MutationActor
    ) async throws -> MergeResult
    /// §3.5's split — human-only. Returns the new entity's id for the UI to select.
    @discardableResult
    func splitEntity(
        entityID: UUID,
        aliasIDs: [UUID],
        newName: String,
        movedAppearanceIDs: [UUID],
        actor: MutationActor
    ) async throws -> (entry: JournalEntry, entityID: UUID)
    /// §3.7's `lock`: pins a subject or one of its fields. `LockPolicy.fields(for:)` is
    /// the enumerated set; anything else throws `.invalidLockField(subjectKind:field:)`.
    @discardableResult
    func lock(subject: SubjectRef, field: LockField, actor: MutationActor) async throws -> JournalEntry
    /// The explicit gesture that makes a locked field editable again (§3.7).
    @discardableResult
    func unlock(subject: SubjectRef, field: LockField, actor: MutationActor) async throws -> JournalEntry

    /// §6's accept: flips `review_state` and stamps `reviewed_at`, and touches neither
    /// `source` nor `job_id`. Accepting an entity accepts its alias and appearance rows.
    @discardableResult
    func acceptFacts(refs: [SubjectRef], actor: MutationActor) async throws -> JournalEntry
    /// Every `proposed` fact row in the project, in one group (§6).
    @discardableResult
    func acceptAllProposed(actor: MutationActor) async throws -> JournalEntry

    /// Upserts an appearance on `(scene, entity, role)` (§6).
    @discardableResult
    func setSceneEntity(
        sceneID: UUID,
        entityID: UUID,
        role: SceneEntityRole,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func removeSceneEntity(id: UUID, actor: MutationActor) async throws -> JournalEntry
    /// Writes the scene's synopsis PROV column set only (§4.3).
    @discardableResult
    func setSynopsis(sceneID: UUID, text: String, actor: MutationActor) async throws -> JournalEntry
    /// Replaces the scene text used by the app and prompt generation without mutating the
    /// imported screenplay. Passing `nil` restores the imported scene text.
    @discardableResult
    func setSceneText(
        sceneID: UUID,
        text: String?,
        actor: MutationActor
    ) async throws -> JournalEntry
    /// Sets optional scene-specific creative direction consumed by prompt generation.
    @discardableResult
    func setScenePromptDirection(
        sceneID: UUID,
        text: String,
        actor: MutationActor
    ) async throws -> JournalEntry

    @discardableResult
    func addState(
        entityID: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID?,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func editState(
        id: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID?,
        actor: MutationActor
    ) async throws -> JournalEntry
    /// Tombstones an `ai` row, hard-deletes a `human` one (§6).
    @discardableResult
    func removeState(id: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func addEvent(
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID?,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func editEvent(
        id: UUID,
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID?,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func removeEvent(id: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func addRelationship(
        fromEntityID: UUID,
        toEntityID: UUID,
        kind: RelationshipKind,
        description: String,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func removeRelationship(id: UUID, actor: MutationActor) async throws -> JournalEntry

    // The requirement and template operations (PHASE2_DESIGN §7.2). Every one of them goes
    // through the same engine as the Phase 1 edits — one transaction, one journal row, one
    // undo step — and none of them creates an `assets` row (Plan 011 owns that).

    @discardableResult
    func createRequirement(
        entityID: UUID,
        tier: AssetRequirementTier,
        typeID: UUID?,
        name: String,
        reason: String,
        actor: MutationActor
    ) async throws -> (entry: JournalEntry, requirementID: UUID)
    /// Hard delete; refused while an asset row exists, and routed to the tombstone for
    /// `ai`/`parser` rows.
    @discardableResult
    func deleteRequirement(id: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func rejectRequirement(id: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func unrejectRequirement(id: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func renameRequirement(id: UUID, name: String, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func setRequirementReason(id: UUID, text: String, actor: MutationActor) async throws -> JournalEntry
    /// Human-only (§7.1); recomputes any existing asset in the same group (§6.3).
    @discardableResult
    func setRequirementNecessity(
        id: UUID,
        necessity: RequirementNecessity,
        actor: MutationActor
    ) async throws -> JournalEntry
    /// Variant tier only; a human add over a tombstoned pair un-rejects it.
    @discardableResult
    func addRequirementScene(
        requirementID: UUID,
        sceneID: UUID,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func removeRequirementScene(linkID: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func excludeReferenceFromScene(
        sceneID: UUID,
        requirementID: UUID,
        actor: MutationActor
    ) async throws -> JournalEntry
    /// Removes a reference bundle atomically, with one undo step.
    @discardableResult
    func excludeReferencesFromScene(
        sceneID: UUID,
        requirementIDs: [UUID],
        actor: MutationActor
    ) async throws -> JournalEntry
    /// The full-graph cycle and self-edge walk runs before any write (§3.5).
    @discardableResult
    func addDependency(
        requirementID: UUID,
        dependsOnID: UUID,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func removeDependency(id: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func combineRequirements(
        sourceIDs: [UUID],
        into targetID: UUID,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func splitRequirement(
        id: UUID,
        sceneIDs: [UUID],
        newName: String,
        actor: MutationActor
    ) async throws -> (entry: JournalEntry, requirementID: UUID)
    @discardableResult
    func setManifestInclusion(
        entityID: UUID,
        inclusion: ManifestInclusion,
        actor: MutationActor
    ) async throws -> JournalEntry

    @discardableResult
    func setTemplateEntryEnabled(
        typeID: UUID,
        isEnabled: Bool,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func renameTemplateEntry(
        typeID: UUID,
        displayName: String,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func setTemplateEntryOrder(
        typeID: UUID,
        sortOrder: Int,
        actor: MutationActor
    ) async throws -> JournalEntry
    @discardableResult
    func addTemplateEntry(
        kind: EntityKind,
        code: String,
        displayName: String,
        sortOrder: Int,
        actor: MutationActor
    ) async throws -> (entry: JournalEntry, typeID: UUID)
    /// Refused while any requirement references the entry, tombstoned rows included.
    @discardableResult
    func removeTemplateEntry(typeID: UUID, actor: MutationActor) async throws -> JournalEntry

    // The asset and version operations (PHASE2_DESIGN §7.3). Every one is human-only
    // (§7.1), every status change goes through §6.3's one recompute, and the two
    // destroyers of media are stated non-invertible before they run.

    /// §4.1's staged import: sniff, measure, stage, then one transaction whose group is the
    /// implicit accept of a proposed requirement, `createAsset` when the slot is empty, and
    /// the version insert — one undo step. Any throw removes the staged file.
    @discardableResult
    func importAssetVersion(
        requirementID: UUID,
        from sourceURL: URL,
        actor: MutationActor,
        /// §7.3's lineage stamp — the current prompt's id from the workshop (Plan 015);
        /// `nil` everywhere else.
        promptID: UUID?
    ) async throws -> MediaImportSummary
    /// Imports and makes the new version approved/current as one controlled journal step.
    @discardableResult
    func importAndApproveAssetVersion(
        requirementID: UUID,
        from sourceURL: URL,
        actor: MutationActor,
        promptID: UUID?
    ) async throws -> MediaImportSummary
    /// Validates and stages every candidate before committing the complete set as one
    /// journal entry. The selected candidate becomes current; the others remain archived.
    @discardableResult
    func importGeneratedCandidates(
        requirementID: UUID,
        from sourceURLs: [URL],
        selectedIndex: Int,
        context: ReferenceImageGenerationContext,
        metadata: ImageGenerationCommitMetadata,
        actor: MutationActor
    ) async throws -> GeneratedCandidateImportSummary
    /// Provider-neutral generation lineage for one generated version; `nil` for manual or
    /// legacy imports.
    func imageGenerationProvenance(versionID: UUID) async throws
        -> ImageGenerationProvenance?
    /// **Non-invertible.** Allowed only on a `rejected` version; the row goes in the
    /// transaction and the file after commit.
    @discardableResult
    func deleteVersion(versionID: UUID, actor: MutationActor) async throws -> JournalEntry
    /// **Non-invertible.** Deletes a `needs_review` archived version rows-first/files-second.
    @discardableResult
    func deleteArchivedVersion(versionID: UUID, actor: MutationActor) async throws -> JournalEntry
    /// **Non-invertible.** The asset row, its version rows, and — after commit — their files.
    @discardableResult
    func deleteAsset(assetID: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func rejectVersion(versionID: UUID, actor: MutationActor) async throws -> JournalEntry
    /// The user gesture: always lands `needs_review` (§6.3's stated asymmetry).
    @discardableResult
    func unrejectVersion(versionID: UUID, actor: MutationActor) async throws -> JournalEntry
    /// §7.3's approval, in one transaction: demote the previously approved version first,
    /// approve the target, recompute, clear the asset's **own** staleness, and mark every
    /// dependent requirement's asset stale when the approved version *changed* (§3.5).
    /// Approving the version that already holds the approval is refused.
    @discardableResult
    func approveVersion(
        assetID: UUID,
        versionID: UUID,
        actor: MutationActor
    ) async throws -> JournalEntry
    /// Archives the requirement's current approved version. Undo restores every touched
    /// version/status/staleness byte-identically.
    @discardableResult
    func archiveCurrentVersion(
        requirementID: UUID,
        actor: MutationActor
    ) async throws -> JournalEntry
    /// §3.5's explicit "Mark Current": clears `is_stale`/`stale_since`/`stale_reason` and
    /// nothing else. Refused when the asset is not stale.
    @discardableResult
    func clearAssetStale(assetID: UUID, actor: MutationActor) async throws -> JournalEntry
    /// Precondition: no approved version.
    @discardableResult
    func rejectAsset(assetID: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func unrejectAsset(assetID: UUID, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func setAssetNotes(id: UUID, text: String, actor: MutationActor) async throws -> JournalEntry
    @discardableResult
    func setVersionNotes(id: UUID, text: String, actor: MutationActor) async throws -> JournalEntry

    /// §5.2's **Build Asset Manifest**: idempotent, and journaling nothing when there is
    /// nothing to create (`entry: nil`). Name collisions are counted skips, never throws.
    func refreshCanonicalRequirements(actor: MutationActor) async throws -> ManifestBuildResult

    /// Applies the inverse of one journal entry and journals it with `inverts_seq` set
    /// (§3.8). Throws `.inverseNoLongerApplicable(reason:)` before writing anything when a
    /// precondition fails. There is no generic "apply this operation" door.
    @discardableResult
    func applyInverse(entryID: Int64, actor: MutationActor) async throws -> JournalEntry

    /// §3.8's "Revert last run": **selective**, one transaction, one non-invertible journal
    /// row, and a `RevertReport` of what it undid and what your own edits kept.
    ///
    /// Throws `.newerRunExists(jobID:)` when a completed run's entries are newer than this
    /// one's — only the newest run is revertible. A revert is not itself undoable.
    ///
    /// **Task-agnostic** (PHASE2_DESIGN §7.5): the newest completed run of *either*
    /// `extractScreenplay` or `inferAssetManifest` resolves through the one widened gate,
    /// and both route through this one API.
    @discardableResult
    func revertRun(jobID: UUID, actor: MutationActor) async throws -> RevertReport
    /// The extraction-named door this replaced. Deprecated alias; it calls `revertRun`.
    @available(*, deprecated, renamed: "revertRun(jobID:actor:)")
    @discardableResult
    func revertExtractionRun(jobID: UUID, actor: MutationActor) async throws -> RevertReport
}

public extension ScreenplayEditing {
    /// The alias, defined once: Plan 007's name kept working while the Jobs section moves
    /// to the task-agnostic door.
    @available(*, deprecated, renamed: "revertRun(jobID:actor:)")
    @discardableResult
    func revertExtractionRun(jobID: UUID, actor: MutationActor) async throws -> RevertReport {
        try await revertRun(jobID: jobID, actor: actor)
    }
}

/// What one merge did, for the caller that has to tell the operator about it (§3.5).
///
/// A source name whose normalized form already belonged to an unrelated third entity is
/// **skipped and reported** — never thrown, and never a raw SQLite uniqueness error.
public struct MergeResult: Equatable, Sendable {
    public let entry: JournalEntry
    public let skippedAliases: [String]

    public init(entry: JournalEntry, skippedAliases: [String]) {
        self.entry = entry
        self.skippedAliases = skippedAliases
    }
}

public protocol ExtractionApplying: Sendable {
    /// Applies canonical changes, the report, aggregate usage, and parent completion in
    /// one transaction under the fixed `.ai(runJobID)` actor (§8.5).
    func applyExtractionRun(
        _ proposal: ExtractionProposal,
        runJobID: UUID,
        usage: JobUsage
    ) async throws -> ApplyReport
}

/// The manifest run's one write surface (PHASE2_DESIGN §7.1, §8.4).
public protocol ManifestApplying: Sendable {
    /// Applies §8.4's steps 0–6, the report, aggregate usage, and parent completion in one
    /// transaction under the fixed `.ai(runJobID)` actor.
    ///
    /// Throws `.manifestInputChangedDuringRun` when the rendered input rebuilt inside the
    /// transaction no longer digests to the run's `jobs.input_sha256` — nothing is applied,
    /// the run fails cleanly, and run-once gating permits the retry (§8.4 step 0).
    func applyManifestRun(
        _ proposal: ManifestProposal,
        runJobID: UUID,
        usage: JobUsage
    ) async throws -> ManifestApplyReport
}

/// The prompt run's one write surface (PHASE3_DESIGN §3.7, §8.4; Plan 016 contract C) —
/// the **eighth** `ProjectTools` role, never a widened one (§4.4).
public protocol PromptApplying: Sendable {
    /// Applies §8.4's steps 0–4 in **one transaction** under the fixed `.ai(runJobID)`
    /// actor: the step-0 digest re-verification against `jobs.input_sha256`, the cheap
    /// precondition re-check through `attachGeneratedPrompt` itself, one invertible
    /// journal entry via Plan 014's pinned engine signature, then report + usage + parent
    /// completion inside the same transaction — and returns `AssetPromptApplyOutcome` so
    /// the workshop can register undo ("Undo Generate Prompt", §13.11).
    ///
    /// Throws `.assetPromptInputChangedDuringRun` when the rendered input rebuilt inside
    /// this transaction no longer digests to the run's recorded value — nothing is
    /// applied, and re-running is always available (§3.1).
    func applyAssetPromptRun(
        _ proposal: AssetPromptProposal,
        runJobID: UUID,
        usage: JobUsage
    ) async throws -> AssetPromptApplyOutcome
}

/// The scene-prompt run's one write surface (PHASE5_DESIGN §3.9, §8.4; Plan 021
/// contract C) — the **ninth** `ProjectTools` role, never a widened one (§4.4's rule,
/// Phase 3's precedent repeated).
public protocol ScenePromptApplying: Sendable {
    /// Applies §8.4's steps 0–4 in **one transaction** under the fixed `.ai(runJobID)`
    /// actor: the step-0 digest re-verification against `jobs.input_sha256`, the cheap
    /// precondition re-check through `attachGeneratedScenePrompt` itself, one invertible
    /// journal entry, one-time direction consumption, then report + usage + parent
    /// completion inside the same transaction
    /// — and returns `ScenePromptApplyOutcome` so the Generation section can register
    /// undo ("Undo Generate Scene Prompt").
    ///
    /// Throws `.scenePromptInputChangedDuringRun` when the rendered input rebuilt inside
    /// this transaction no longer digests to the run's recorded value — nothing is
    /// applied, and re-running is always available (§8.1's no-run-once rule).
    func applyScenePromptRun(
        _ proposal: ScenePromptProposal,
        runJobID: UUID,
        usage: JobUsage
    ) async throws -> ScenePromptApplyOutcome

    /// Version-two atomic apply: all cards and all local citations commit together.
    func applyScenePromptSetRun(
        _ proposal: ScenePromptSetProposal,
        runJobID: UUID,
        usage: JobUsage
    ) async throws -> ScenePromptSetApplyOutcome
}

public typealias ProjectTools = ProjectReading & JobManaging & ScreenplayImporting
                              & ScreenplayEditing & ExtractionApplying & ManifestApplying
                              & PromptApplying & ScenePromptApplying & ProjectObserving

/// The workspace a **run** shares with its children (§4.1: `cache/jobs/<run-id>/workspace/`).
public struct ProjectRunWorkspace: Equatable, Sendable {
    public let workspaceURL: URL
    public let workspaceRelativePath: RelativeProjectPath

    public init(workspaceURL: URL, workspaceRelativePath: RelativeProjectPath) {
        self.workspaceURL = workspaceURL
        self.workspaceRelativePath = workspaceRelativePath
    }
}

/// One job's own files (§4.1). A childless task passes `runID == jobID`.
public struct ProjectJobPaths: Equatable, Sendable {
    public let inputURL: URL
    public let resultURL: URL
    public let logURL: URL
    public let inputRelativePath: RelativeProjectPath
    public let resultRelativePath: RelativeProjectPath
    public let logRelativePath: RelativeProjectPath

    public init(
        inputURL: URL,
        resultURL: URL,
        logURL: URL,
        inputRelativePath: RelativeProjectPath,
        resultRelativePath: RelativeProjectPath,
        logRelativePath: RelativeProjectPath
    ) {
        self.inputURL = inputURL
        self.resultURL = resultURL
        self.logURL = logURL
        self.inputRelativePath = inputRelativePath
        self.resultRelativePath = resultRelativePath
        self.logRelativePath = logRelativePath
    }
}
