import Foundation

public enum ProjectStoreError: Error, Equatable, LocalizedError, Sendable {
    case targetAlreadyExists
    case invalidBundle
    case invalidDatabaseFile
    case invalidRelativePath(String)
    case newerProjectVersion(found: Int, supported: Int)
    case missingProject
    case sessionClosed
    case mutationInProgress
    case jobNotFound
    case sceneNotFound
    case invalidSceneText
    case entityNotFound
    /// No `asset_requirements` row with that id (PHASE2_DESIGN §7.6's inspector read).
    case requirementNotFound
    case illegalJobTransition(from: Job.State, to: Job.State)
    case cancellationTooLate
    case invalidUsage
    case databaseCommit(String)
    /// The normalized alias already belongs to another entity of the same kind (§3.5).
    case aliasConflict(existingEntityID: UUID)
    /// Import and replace are refused while any run is non-terminal or paused (§5.5).
    case importRefusedDuringRun
    /// Replace is refused while any protected fact or lock exists (§5.5); the reason is
    /// the design's wording, shown verbatim.
    case replaceRefused(reason: String)
    /// Analysis runs **once per project** (§3.6): a second `extractScreenplay` parent is
    /// refused once one has applied. A failed or cancelled attempt applied nothing and may
    /// retry; a paused run resumes as itself; reverting does not reopen eligibility.
    case extractionAlreadyApplied
    /// Manifest inference runs **once per screenplay** (PHASE2_DESIGN §3.6, §8.1): a second
    /// `inferAssetManifest` parent is refused once one has completed for the current
    /// script. A failed or cancelled attempt applied nothing and may retry.
    case manifestAlreadyApplied
    /// §3.6: a manifest run is refused while any extraction run for the current script is
    /// **non-terminal or paused** — Phase 1's one-active-run rule alone does not cover a
    /// paused run, which may otherwise resume and apply after the manifest exists.
    case manifestRefusedDuringExtraction
    /// §3.6: a completed manifest run **permanently closes extraction for that screenplay**,
    /// because spending the analysis afterwards would change canonical facts underneath
    /// requirements, basis citations, and approvals already built on them.
    case extractionClosedByManifest
    /// §8.4 step 0: the rendered manifest input rebuilt inside the apply transaction no
    /// longer digests to the run's `jobs.input_sha256` — the filmmaker edited the project
    /// while the model was thinking. Nothing is applied and the run may be retried.
    case manifestInputChangedDuringRun
    /// A run report was aimed at a job of the wrong task (PHASE2_DESIGN §7.5, §8.5). One
    /// nullable JSON column carries both report types, and each has exactly one task.
    case wrongJobTask(expected: String, found: String)

    // MARK: - Editing (Plan 005, §3.5–§3.8)

    /// The subject, or that field of it, is locked (§3.7). Both actors hit this; the human
    /// path clears it with an explicit `unlock`.
    case locked(subject: SubjectRef, field: LockField)
    /// AI may neither modify nor delete a protected row — `human`, or `ai` + `accepted` (§3.6).
    case protectedFact(subject: SubjectRef)
    /// The parser owns that field of that row; AI may not change it (§3.6).
    case parserOwned(subject: SubjectRef, field: LockField)
    /// `entities(project_id, kind, name_normalized)` is taken by another entity.
    case nameConflict(existingEntityID: UUID)
    /// §6's "names non-empty after trim".
    case invalidName(reason: String)
    /// `LockPolicy.fields(for:)` does not admit that `(subjectKind, field)` pair (§3.7).
    case invalidLockField(subjectKind: SubjectKind, field: LockField)
    /// `setLocationParent` refused a non-location, itself, or a cycle (§6).
    case invalidParent(reason: String)
    /// A state, event, or relationship the operation names is not valid: a scene outside
    /// the current script, an end scene before its start, a resulting state belonging to
    /// another entity, a self-relationship, or a `(from, to, kind)` that already exists
    /// ("Scenes, states, events, relationships", §4.3).
    case invalidFact(reason: String)
    /// Kind mismatch, the target among the sources, or an empty source list (§3.5).
    case mergeRefused(reason: String)
    /// No alias listed, none left on the source, or a locked alias (§3.5).
    case splitRefused(reason: String)
    /// Delete of an `ai`- or `parser`-sourced row that is not already rejected: the
    /// tombstone is what stops resurrection, so the UI's Delete rejects instead (§3.6).
    case rejectInsteadOfDelete(entityID: UUID)
    /// A proposal resolved to a `rejected` tombstone; nothing is written (§8.5 rule 2).
    case rejected(subject: SubjectRef)

    // MARK: - Requirements and the template (Plan 010, PHASE2_DESIGN §7.2)

    /// `UNIQUE(entity_id, name_normalized)` is taken by another requirement of the same
    /// entity, of either tier (§4.3).
    case requirementNameConflict(existingRequirementID: UUID)
    /// §7.2: a requirement with an `assets` row cannot be hard-deleted — the FK RESTRICT
    /// would otherwise surface as a raw constraint failure. Delete the asset first.
    case requirementHasAsset(requirementID: UUID)
    /// §7.4: `deleteEntity` is refused while any of the entity's requirements has an
    /// `assets` row — the same `RESTRICT` seen one level up, turned into a sentence.
    case entityHasAssets(entityID: UUID)
    /// §7.2: `removeTemplateEntry` is refused while any requirement references the entry,
    /// tombstoned rows included. Disable it instead.
    case templateEntryInUse(typeID: UUID)
    /// A template edit the §4.3 rules refuse: an empty or duplicate display name, a `code`
    /// that is not `[a-z0-9_]+`, or one already taken for that kind.
    case invalidTemplateEntry(reason: String)
    /// `combineRequirements` or `splitRequirement` refused before writing anything (§7.2).
    case requirementOperationRefused(reason: String)

    // MARK: - Assets, versions, and media (Plan 011, PHASE2_DESIGN §7.3, §4.1)

    /// No `assets` row with that id.
    case assetNotFound
    /// No `asset_versions` row with that id.
    case assetVersionNotFound
    /// A §7.3 precondition refused before anything was written: a second asset on one
    /// requirement, a delete of a version that is not `rejected`, or a slot-level rejection
    /// over an approved version.
    case assetOperationRefused(reason: String)
    /// §6.3: media cannot resurrect a deprecated slot — `importAssetVersion` (and
    /// `createAsset`) are refused while the requirement is inactive under §6.4's predicate.
    case requirementInactive(requirementID: UUID)
    // MARK: - Prompts (PHASE3_DESIGN §5.8; Plan 014 contract B)

    /// No `asset_prompts` row with that id.
    case promptNotFound
    /// §7.2: prompt work requires an **accepted** requirement — review first, then work
    /// (§13.10's asymmetry with import, which implicitly accepts).
    case promptRequiresAcceptedRequirement
    /// §7.2: `markAssetInProgress` is refused once media has arrived — the slot is in
    /// review, not in generation.
    case inProgressRequiresNoVersions
    /// §3.3's generation gate: refused while an active dependency is unsatisfied,
    /// naming it (`attachGeneratedPrompt` only — `createPrompt` is not blockage-gated).
    case promptRequirementBlocked(dependencyName: String)
    /// §8.4 step 0: the rendered asset-prompt input rebuilt inside the apply transaction
    /// no longer digests to the run's `jobs.input_sha256`. Nothing is applied; re-running
    /// is always available (§3.1).
    case assetPromptInputChangedDuringRun
    /// Plan 024's candidate commit token no longer matches the canonical project state.
    case referenceImageGenerationContextChanged
    /// §8.4 step 0 at scene scale: the rendered scene-prompt input rebuilt inside the
    /// apply transaction no longer digests to the run's `jobs.input_sha256`. Nothing is
    /// applied; re-running is always available.
    case scenePromptInputChangedDuringRun
    /// §8.1's pre-flight: the rendered input exceeds `AssetPromptInputBudget` — refused
    /// naming the size, never truncated (§11 defers chunked prompt inputs deliberately).
    case assetPromptInputOverBudget(measuredUTF16: Int, limitUTF16: Int)
    // MARK: - Phase 5a (PHASE5_DESIGN §3.2, §3.5, §8.2; Plan 018 contracts C–E)

    /// §3.2's profile budget: the scene plans more satisfied references than the active
    /// target profile accepts — refused naming both numbers, never truncated; the remedy
    /// is the filmmaker's (mark requirements optional or not-needed).
    case sceneReferencesExceedProfileLimit(count: Int, limit: Int)
    /// §3.5's removed-catalog-id edge: `projects.generation_target_profile` names a
    /// profile the catalog no longer carries. Reads show `Needs Preparation` naming the
    /// missing profile; generation refuses — never a crash.
    case generationTargetProfileMissing(id: String)
    /// §8.1's pre-flight at scene scale: the rendered input exceeds
    /// `ScenePromptInputBudget` — refused naming the size, never truncated.
    case scenePromptInputOverBudget(measuredUTF16: Int, limitUTF16: Int)
    /// §8.1's paused-run gate, Phase 2 §3.6's own gate adopted for prompt runs: a prompt
    /// run is refused while any extraction or manifest run is non-terminal **or paused**.
    case promptRunRequiresIdleBootstraps
    /// §4.1: the file a version row names is not in the bundle. Reached by a redo of an
    /// import whose orphaned file Clear Orphaned Media removed (§7.3's pinned walk).
    case mediaFileMissing(path: String)
    /// §4.1's damaged-asset warning: the file is there but its size or SHA-256 no longer
    /// matches what the row recorded. Never a crash, never a silent substitution.
    case mediaFileDamaged(path: String, reason: String)
    // MARK: - Phase 5a operations and export (PHASE5_DESIGN §5.5, §7.1, §14.6–§14.7; Plan 019)

    /// A §7.1 operation refused before anything was written: body or settings guards.
    case sceneOperationRefused(reason: String)
    /// §8.1's pre-flight at scene scale: the scene is not Asset Ready per Plan 017's
    /// snapshot — every required asset must have an approved version first.
    case scenePromptRequiresAssetReady
    /// §3.8's export gate: no current prompt under the active profile.
    case scenePackageExportRequiresPrompt
    /// §3.8's verification gate: a reference file on disk no longer matches its approved
    /// version's stored SHA-256. Nothing is written rather than shipping bytes that
    /// disagree with their manifest.
    case packageReferenceVerificationFailed(path: String)
    /// §14.6: the selected skill's imported tree is missing or altered against its stored
    /// `tree_sha256`. Reached by import redo and by the FilmCore run gate's early feedback.
    case importedSkillTreeMissing
    /// §14.7's stale-export gate: a single stale scene exports only through the confirm,
    /// which names this reason. The refusal's copy **is** the confirm copy.
    case scenePackageStaleExportRequiresConfirm(reason: String)

    /// The rows an inverse needs moved since the entry was journaled (§3.8). Thrown
    /// **before any write** — an inverse is never partially applied.
    case inverseNoLongerApplicable(reason: String)
    /// Only the newest completed run is revertible (§3.8).
    case newerRunExists(jobID: UUID)
    /// The screenplay changed between run planning and the atomic apply (§8.5).
    case scriptChangedDuringRun

    /// §5.5's refusal wording, verbatim. It is a constant so FilmCore and the app cannot
    /// drift apart on the one sentence the design specifies word for word.
    public static let workedOnScreenplayReason = """
        This project already has a screenplay you've worked on. Start a new project for a \
        revised draft.
        """

    /// PHASE2_DESIGN §3.6's refusal copy for the extraction closure, verbatim. It is a
    /// constant so FilmCore, FilmBrain's `ManifestRunGate`, and the app cannot drift apart
    /// on the one clause the design specifies word for word.
    public static let manifestClosesExtractionReason =
        "the asset manifest is built on this project's canonical data"

    /// The refusal §5.5 names, ready to throw.
    public static var replaceRefusedAfterWork: ProjectStoreError {
        .replaceRefused(reason: workedOnScreenplayReason)
    }

    public var errorDescription: String? {
        switch self {
        case .targetAlreadyExists: "A project already exists at that location."
        case .invalidBundle: "The selected item is not a valid AI Film Camp project."
        case .invalidDatabaseFile: "The project database must be a regular, non-symlink file at the bundle root."
        case let .invalidRelativePath(path): "The project-relative path is invalid: \(path)"
        case let .newerProjectVersion(found, supported):
            "This project uses bundle schema \(found), newer than supported schema \(supported)."
        case .missingProject: "The project database does not contain exactly one project."
        case .sessionClosed: "The project session is closed."
        case .mutationInProgress: "Another project mutation is already active."
        case .jobNotFound: "The analysis job could not be found."
        case .sceneNotFound: "That scene is not in this project."
        case .invalidSceneText: "Scene screenplay text cannot be empty."
        case .entityNotFound: "That entity is not in this project."
        case .requirementNotFound: "That asset requirement is not in this project."
        case let .illegalJobTransition(from, to): "The job cannot transition from \(from.rawValue) to \(to.rawValue)."
        case .cancellationTooLate: "Finishing commit; cancellation is no longer available."
        case .invalidUsage: "Token usage values must be nonnegative."
        case let .databaseCommit(message): "The analysis could not be committed: \(message)"
        case let .aliasConflict(existingEntityID):
            "That name is already an alias of another entity (\(existingEntityID.uuidString))."
        case .importRefusedDuringRun: "Finish or cancel the current run before importing a screenplay."
        case let .replaceRefused(reason): reason
        case let .locked(_, field):
            field == .whole
                ? "That item is locked. Unlock it to make this change."
                : "That item's \(field.displayName.lowercased()) is locked. Unlock it to make this change."
        case .protectedFact:
            "The analysis cannot change a fact you have accepted or edited."
        case let .parserOwned(_, field):
            "The screenplay itself sets the \(field.displayName.lowercased()); the analysis cannot change it."
        case let .nameConflict(existingEntityID):
            "Another item of that kind already has that name (\(existingEntityID.uuidString))."
        case let .invalidName(reason): reason
        case let .invalidLockField(subjectKind, field):
            "A \(subjectKind.rawValue) has no \(field.displayName.lowercased()) to lock."
        case let .invalidParent(reason): reason
        case let .invalidFact(reason): reason
        case let .mergeRefused(reason): reason
        case let .splitRefused(reason): reason
        case .rejectInsteadOfDelete:
            "That item came from the screenplay or the analysis. Reject it instead of deleting it."
        case .rejected: "That item was rejected, so it was not added again."
        case let .requirementNameConflict(existingRequirementID):
            "This item already has a requirement with that name (\(existingRequirementID.uuidString))."
        case .requirementHasAsset:
            "This requirement has media. Delete its asset before deleting the requirement."
        case .entityHasAssets:
            "This item's requirements have media. Delete this entity's assets first."
        case .templateEntryInUse:
            "Requirements already use that template entry. Disable it instead of removing it."
        case let .invalidTemplateEntry(reason): reason
        case let .requirementOperationRefused(reason): reason
        case .assetNotFound: "That asset is not in this project."
        case .assetVersionNotFound: "That image version is not in this project."
        case let .assetOperationRefused(reason): reason
        case .requirementInactive:
            "This requirement is retired. Restore it before adding media."
        case .promptNotFound: "That prompt is not in this project."
        case .promptRequiresAcceptedRequirement:
            "Accept this requirement before working on its prompt."
        case .inProgressRequiresNoVersions:
            "This slot already has imported versions — review them instead of marking generation in progress."
        case let .promptRequirementBlocked(dependencyName):
            "This slot is waiting on '\(dependencyName)' — approve that asset first, or remove the dependency."
        case let .assetPromptInputOverBudget(measured, limit):
            "This requirement's context is \(measured) units against a budget of \(limit) and cannot be sent."
        case let .sceneReferencesExceedProfileLimit(count, limit):
            "This scene plans \(count) reference images; the active profile accepts \(limit). Mark requirements optional or not needed in the Asset Workshop to reduce the set."
        case let .generationTargetProfileMissing(id):
            "The project's generation profile \"\(id)\" is no longer available. Pick a profile in the Generation section."
        case let .scenePromptInputOverBudget(measured, limit):
            "This scene's context is \(measured) units against a budget of \(limit) and cannot be sent."
        case .promptRunRequiresIdleBootstraps:
            "Prompts can be generated once the screenplay analysis or manifest run finishes or is cancelled."
        case .assetPromptInputChangedDuringRun:
            "The project changed while the prompt was being written — run it again."
        case .referenceImageGenerationContextChanged:
            "The prompt or reference images changed while the image was being created — generate it again."
        case .scenePromptInputChangedDuringRun:
            "The project changed while the scene prompt was being written — run it again."
        case let .mediaFileMissing(path):
            "The image file at \(path) is missing from this project."
        case let .mediaFileDamaged(path, reason):
            "The image file at \(path) may be damaged: \(reason)."
        case let .sceneOperationRefused(reason): reason
        case .scenePromptRequiresAssetReady:
            "This scene is not Asset Ready. Every required asset must have an approved version before a prompt is prepared."
        case .scenePackageExportRequiresPrompt:
            "This scene has no prepared prompt. Write one or generate one before exporting."
        case .packageReferenceVerificationFailed:
            "A reference file on disk no longer matches its approved version. Re-approve the version in the Asset Workshop, then export again."
        case .importedSkillTreeMissing:
            "This skill's imported files are missing or changed. Import the skill again to reuse it."
        case let .scenePackageStaleExportRequiresConfirm(reason):
            "This package's inputs changed since its prompt was prepared (\(reason)). Export it anyway?"
        case let .inverseNoLongerApplicable(reason): reason
        case .newerRunExists: "A newer analysis run exists. Only the most recent run can be reverted."
        case .scriptChangedDuringRun: "The screenplay changed while analysis was running. Run the analysis again."
        case let .wrongJobTask(expected, found):
            "That report belongs to a \(expected) run, not to a \(found) one."
        case .manifestAlreadyApplied:
            """
            This project's asset manifest has already been inferred. Inference runs once \
            per screenplay — afterwards you edit the manifest here.
            """
        case .manifestRefusedDuringExtraction:
            "Finish or cancel the analysis run before inferring the asset manifest."
        case .extractionClosedByManifest:
            """
            This screenplay cannot be analyzed now: \
            \(Self.manifestClosesExtractionReason). Start \
            a new project to analyze a screenplay from scratch.
            """
        case .manifestInputChangedDuringRun:
            "The project changed while the manifest was being inferred — run it again."
        case .extractionAlreadyApplied:
            """
            This project's screenplay has already been analyzed. Analysis runs once per \
            project — afterwards AI Film Camp owns the breakdown and you edit it here. \
            Start a new project for another run.
            """
        }
    }
}
