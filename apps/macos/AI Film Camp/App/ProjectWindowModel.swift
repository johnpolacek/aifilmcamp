import FilmBrain
import FilmCore
import Foundation
import Observation

/// The sidebar sections of PHASE1_DESIGN §3.11, in ⌘1…⌘9 order, plus PHASE2_DESIGN §5.1's
/// **Manifest** section and PHASE4_DESIGN §5.1's **Dashboard** section, which come after
/// them and therefore carry no ⌘-digit.
enum ProjectSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case scenes
    case characters
    case locations
    case props
    case vehicles
    case creatures
    case objects
    case continuity
    case jobs
    case manifest
    case generation
    case dashboard

    var id: String { rawValue }

    /// The entity kind this section lists, or `nil` for the non-entity sections.
    var entityKind: EntityKind? {
        switch self {
        case .characters: .character
        case .locations: .location
        case .props: .prop
        case .vehicles: .vehicle
        case .creatures: .creature
        case .objects: .object
        case .scenes, .continuity, .jobs, .manifest, .generation, .dashboard: nil
        }
    }

    /// The sidebar label — also the plural noun the entity empty state substitutes.
    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .scenes: "Scenes"
        case .characters: "Characters"
        case .locations: "Locations"
        case .props: "Props"
        case .vehicles: "Vehicles"
        case .creatures: "Creatures"
        case .objects: "Objects"
        case .continuity: "Continuity"
        case .jobs: "Jobs"
        case .manifest: "Manifest"
        case .generation: "Generation"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge"
        case .scenes: "film"
        case .characters: "person.2"
        case .locations: "mappin.and.ellipse"
        case .props: "hammer"
        case .vehicles: "car"
        case .creatures: "pawprint"
        case .objects: "cube"
        case .continuity: "clock.arrow.circlepath"
        case .jobs: "list.bullet.rectangle"
        case .manifest: "square.grid.2x2"
        case .generation: "film.stack"
        }
    }

    /// §3.11's empty states, verbatim; the entity string substitutes the plural noun.
    var emptyStateText: String {
        switch self {
        // PHASE4_DESIGN §5.1: the dashboard is a read; an empty project shows the standard
        // section empty state and nothing to act on.
        case .dashboard: "Import a screenplay and build the asset manifest to see readiness."
        case .scenes: "Import a screenplay to see its scenes."
        case .continuity: "No continuity events yet."
        case .jobs: "No analysis runs yet."
        // PHASE2_DESIGN §5.1: with no AI at all, Build is what fills this section.
        case .manifest: "Build the asset manifest to see what needs a reference image."
        // PHASE5_DESIGN §5.1: packages exist once scenes are counted; a prompt makes one
        // Generation Ready, and that needs approved assets behind it (§3.3).
        case .generation:
            "Build the asset manifest and approve assets to prepare scene packages."
        case .characters, .locations, .props, .vehicles, .creatures, .objects:
            "\(title) appear after you analyze the screenplay, or add one with +."
        }
    }

    /// `.searchable` is scoped per section (§3.11): scenes and entities only.
    var supportsSearch: Bool { self == .scenes || entityKind != nil }

    /// Nine Phase 1 sections in four groups (§3.11), PHASE2_DESIGN §5's Manifest, and
    /// PHASE4_DESIGN §5.1's Dashboard, first in the sidebar (§14.4's decision).
    static let groups: [[ProjectSection]] = [
        [.dashboard],
        [.scenes],
        [.characters, .locations, .props, .vehicles, .creatures, .objects],
        [.continuity],
        [.manifest],
        [.generation],
        [.jobs],
    ]

    /// 1-based position, i.e. the ⌘-digit that switches to this section. Only 1…9 are real
    /// shortcuts; a section past the ninth is reached from the sidebar and the View menu
    /// item, which is why `AppCommands` checks the range before making a key equivalent.
    var shortcutNumber: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/// One open project: one window, one `ProjectSession`, one `UndoManager` (§3.11).
///
/// Every command is an awaitable `async` method — nothing here starts fire-and-forget work.
/// The single long-lived task is the `changes()` consumer, which is lifecycle rather than
/// a command.
@MainActor
@Observable
final class ProjectWindowModel {
    let session: ProjectSession
    /// The window's undo stack. `UndoBridge.swift` registers every human edit's inverse on
    /// it and `ProjectWindowDelegate.windowWillReturnUndoManager(_:)` hands it to AppKit,
    /// which is what makes Edit ▸ Undo / Redo and ⌘Z / ⇧⌘Z work (§3.8).
    let undoManager: UndoManager

    private(set) var project: Project?
    private(set) var script: Script?
    private(set) var scenes: [Scene] = []
    /// The script's sequences — read on the refresh beat; the Generation section's
    /// Export Sequence menu lists them (§5.3).
    private(set) var sequences: [ScriptSequence] = []
    private(set) var entitySummaries: [EntityKind: [EntitySummary]] = [:]
    /// Every `locks` row in the project (§3.7), so the list's lock icon and the inspector's
    /// per-field state read synchronously off the model.
    private(set) var locks: [Lock] = []
    private(set) var continuityEvents: [ContinuityEvent] = []
    private(set) var runs: [RunSummary] = []
    private(set) var jobs: [Job] = []
    private(set) var pendingReviewCount = 0
    var extractionProgress: ExtractionRunProgress?
    /// The manifest run's progress line (§8.6), and the two §9 sheets plus the §8.5 report.
    /// Their only writer is `ProjectWindowModel+ManifestRun.swift`, a different file, which
    /// is why they carry no `private(set)` — nothing else in the app writes them.
    var manifestProgress: ManifestRunProgress?
    var pendingManifestDisclosure: ManifestDisclosurePresentation?
    var pendingManifestConfirmation: ManifestConfirmationPresentation?
    var presentedManifestReport: ManifestReportPresentation?

    // MARK: Plan 016 — the prompt run's §9 sheets (same beats as the manifest's)
    /// §9's first-run acknowledgement, shared with extraction and manifest; a project can
    /// reach its first prompt run without either bootstrap acknowledged.
    var pendingPromptDisclosure: PromptDisclosurePresentation?
    /// The compact per-run confirm sheet (§9), shown when the acknowledgement stands.
    var pendingPromptConfirmation: PromptConfirmationPresentation?
    /// §8.7's regenerate-over-human-prompt confirm — raised between the button and the
    /// §9 flow whenever the current prompt was written or last edited by a human.
    var pendingPromptRegenerateConfirm: PromptRegenerateConfirmPresentation?
    /// The apply outcome's report, presented on completion.
    var presentedPromptReport: PromptReportPresentation?
    /// One presentation owns analysis confirmation, live progress, its safe activity log,
    /// and the terminal result. Keeping one sheet alive across those phases avoids the
    /// disclosure → confirmation → tiny-toolbar-status chain that obscured what was sent
    /// and why a run stopped.
    var analysisWorkflow: AnalysisWorkflowPresentation?
    var presentedRevertReport: RevertReportPresentation?
    var presentedCacheSummary: CacheSummaryPresentation?
    var isAppendingScenes = false
    /// `true` between the start and the end of an import.
    private(set) var isImporting = false
    private(set) var isClosed = false
    /// What the last import wrote.
    private(set) var importSummary: ImportSummary?
    /// The import summary sheet's presentation state (contract D): set on every successful
    /// import, cleared on dismiss — which is when the window reveals the first scene.
    var presentedImportSummary: ImportSummaryPresentation?
    /// The upgrade sheet's state: non-nil exactly when **this** session's open migrated a
    /// v1 bundle (§4.2). It is not the import sheet — `open` yields no `ImportSummary`.
    var presentedUpgradeSummary: UpgradeSummaryPresentation?
    /// §5.5's Replace confirmation, awaiting Replace or Cancel.
    var pendingReplace: PendingReplace?
    /// File ▸ Delete Project…'s confirm, awaiting Delete or Cancel. The window that
    /// arms it hosts the dialog, so the destructive action names the project it closes.
    var pendingProjectDeletion = false

    func requestDeleteProject() {
        pendingProjectDeletion = true
    }

    var section: ProjectSection = .scenes
    /// Each section keeps its own last selection (§3.11).
    var selection: [ProjectSection: Set<UUID>] = [:]
    /// `.searchable` is scoped per section, so each keeps its own query.
    var searchTexts: [ProjectSection: String] = [:]
    var isInspectorPresented = true
    var error: UserFacingError?

    // MARK: Editing surface state (§3.11)

    /// The entity list's review filter (§3.6). It drives the `entitySummaries` read
    /// itself — `.rejected` is the only way to see a tombstone — rather than filtering
    /// rows the store already excluded. Plan 007 extends the same control.
    private(set) var entityReviewFilter: EntityReviewFilter = .all
    /// The one sheet this window is showing, hosted by `ProjectSplitView` so the Entity
    /// menu can raise one without reaching into a view.
    var presentedSheet: ProjectSheet?
    /// The Reject/Delete confirmation (§3.11: "Delete deletes with confirmation").
    var pendingEntityDeletion: PendingEntityDeletion?
    /// The entity whose name the inspector is editing in place; Entity ▸ Rename sets it.
    var renamingEntityID: UUID?
    /// How many text controls **outside a sheet** currently hold focus.
    ///
    /// The Entity menu's Return and ⌫ shortcuts are real AppKit key equivalents, and a
    /// key equivalent is matched before the field editor sees the key — so a plain-key
    /// menu item that stayed enabled while a text field had focus would eat every
    /// Return and every backspace typed into it. A **disabled** menu item does not
    /// consume its key equivalent, so the two commands gate on this instead.
    private(set) var textEditingDepth = 0
    // MARK: Manifest state (PHASE2_DESIGN §5, §6.4 — the actions are in
    // `ProjectWindowModel+Manifest.swift`, never in a view)

    // These five are declared without `private(set)` for one reason: their only writer is
    // `ProjectWindowModel+Manifest.swift`, which is a different file, and `private(set)`
    // is file-scoped. Nothing else in the app writes them, and no view writes any of them.

    /// The Manifest list's rows, as the current review filter reads them (§7.6).
    var requirementSummaries: [RequirementSummary] = []
    /// §6.4's counts plus §5.3's "qualifies but has no canonical set" entities.
    var manifestSummary: ManifestSummary?
    /// The selected requirement's inspector shape (§7.6).
    var requirementDetail: RequirementDetail?
    /// The Manifest list's review filter (§8.6's grammar). Like the entity filter it is a
    /// store query — a rejected requirement is excluded from every default read — so
    /// changing it re-reads rather than filtering rows in the view.
    var requirementReviewFilter: RequirementReviewFilter = .all
    /// What the last **Build Asset Manifest** did (§5.2), so the section can report the
    /// created count and §5.3's collision badges. Replaced by the next Build.
    var lastBuildResult: ManifestBuildResult?
    /// The requirement whose name the inspector is editing in place.
    var renamingRequirementID: UUID?
    /// Proposed **requirement** rows, for §8.6's pending-review banner. `pendingReviewCount()`
    /// is Phase 1's entity-side tally and does not count requirements, so the Manifest
    /// section's banner needs its own number — read on the same beat as the list.
    var proposedRequirementCount = 0

    // MARK: Readiness state (PHASE4_DESIGN §5 — the actions are in
    // `ProjectWindowModel+Readiness.swift`, never in a view)

    /// §7.5's readiness snapshot, read on the standard refresh beat. Every readiness
    /// number on any surface comes from this one read (§3.3).
    var _readinessSnapshot: ReadinessSnapshot?
    /// The Scenes list's readiness filter (§5.3 panel 1's drill-down target). A view-model
    /// filter over derived rows; no new read stands behind it.
    var _sceneReadinessFilter: SceneReadinessFilter = .all

    // MARK: Asset state (PHASE2_DESIGN §4.1, §6.1–§6.4 — the actions are in
    // `ProjectWindowModel+Assets.swift`, never in a view)

    /// §6.4's Missing list, read on the same beat as the counts so the scope filter and the
    /// summary line can never disagree.
    var missingAssets: [MissingAsset] = []
    /// The Manifest list's scope beside the review filters: everything, or §6.4's Missing.
    var manifestScope: ManifestScopeFilter = .all
    /// §7.3's two confirmed destructions — `deleteVersion` and `deleteAsset` — armed by the
    /// inspector and performed on confirm. One value, and therefore one dialog: two
    /// `confirmationDialog`s on one view compete for the same presentation slot.
    var pendingMediaDeletion: PendingMediaDeletion?
    /// §4.1's Clear Orphaned Media, awaiting confirmation over the listed files.
    var pendingOrphanSweep: PendingOrphanSweep?
    /// What the last Clear Orphaned Media freed — its own presentation, because the Clear
    /// Job Cache sheet says "Results and logs were kept", which is not this operation.
    var presentedOrphanSummary: CacheSummaryPresentation?
    /// The journal, newest first, as `refresh()` last read it — the Edit Journal sheet's
    /// only source, and already fetched for §3.8's stack-clearing rule.
    private(set) var journalEntries: [JournalEntry] = []
    /// Every `entity_states` row in the project, for the Continuity section. Loaded
    /// lazily (there is no project-wide states read; they hang off `EntityDetail`), so a
    /// window that never opens Continuity never pays for them.
    private(set) var continuityStates: [EntityState] = []
    /// Bumped at the end of every `refresh()`, so a view whose data is loaded lazily can
    /// hang a `.task(id:)` off it and reload when anything changed.
    private(set) var refreshToken = 0
    /// Plan 015's history-disclosure cache (§3.2), reloaded by the workshop's tasks.
    var workshopPromptHistory: [AssetPrompt] = []
    /// What Edit ▸ Undo / Redo show and whether they are enabled.
    ///
    /// `UndoManager` is not `@Observable`, so a `Commands` body that read
    /// `undoManager.undoMenuItemTitle` directly would render once and never update. The
    /// bridge mirrors the manager into this value at every point that can change it —
    /// `UndoBridge.syncUndoMenu()` is the only writer, which is why it is not `private`
    /// to this file.
    var undoMenu = UndoMenuState()

    // MARK: Detail state

    private(set) var sceneDetail: SceneDetail?
    /// `sceneText(id:)` for the selected scene, including a human screenplay override.
    private(set) var sceneDetailText: String = ""
    private(set) var entityDetail: EntityDetail?
    /// The evidence span `reveal(_:)` last pointed at, in `Script.sourceText` offsets.
    private(set) var highlightedRange: UTF16Range?
    /// `true` for the flash that follows a reveal, then the highlight settles.
    private(set) var isHighlightFlashing = false

    /// Resolved scene text, including human screenplay overrides, for scoped search.
    private(set) var sceneTexts: [UUID: String] = [:]
    /// Display names for every entity, for continuity rows and relationship lines.
    private(set) var entityNames: [UUID: String] = [:]
    /// Aliases per entity, built lazily the first time an entity search runs.
    private(set) var aliasIndex: [UUID: [String]] = [:]

    @ObservationIgnored private var aliasIndexIsCurrent = false
    @ObservationIgnored private var continuityStatesAreCurrent = false
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored let extractionAdapterFactory: (@MainActor () throws -> any HarnessAdapter)?
    @ObservationIgnored let extractionSettingsProvider: @MainActor () -> ExtractionSettings
    /// Evaluated when a queued job begins, using the provider captured by its Generate
    /// gesture. Credential lookup remains inside the generator's execution boundary.
    @ObservationIgnored let imageGeneratorFactory:
        @MainActor (ImageProviderDescriptor) -> any ImageGenerating
    /// The reference-image chooser (`NSOpenPanel`, or the automation root's next PNG). It
    /// is injected rather than reached for, so the panel never lives in a view and the
    /// headless twins can import without one.
    @ObservationIgnored let imageChooser: @MainActor () async -> URL?
    /// §14.6's folder chooser for importing a custom skill tree — injected for the same
    /// reason as `imageChooser`.
    @ObservationIgnored let skillChooser: @MainActor () async -> URL?
    /// Finder reveal, injected for the same reason: no view touches `NSWorkspace`.
    @ObservationIgnored let finderRevealer: @MainActor (URL) -> Void
    @ObservationIgnored var preparedExtraction: PreparedExtraction?
    @ObservationIgnored var activeExtractionRun: ExtractionRun?
    @ObservationIgnored var extractionProgressTask: Task<Void, Never>?
    /// The armed manifest run — constructed by `prepareManifestRun()` and **not started**
    /// until Continue, which is what "nothing is sent until you choose Continue" means here.
    @ObservationIgnored var preparedManifestRun: ManifestRun?
    @ObservationIgnored var activeManifestRun: ManifestRun?
    @ObservationIgnored var manifestProgressTask: Task<Void, Never>?

    // MARK: Plan 016 — the armed prompt run (same beats as the manifest run above)
    /// The armed prompt run. The workshop starts it after Continue; reference-image
    /// creation starts it from Generate Prompt, after the one-time disclosure when needed.
    @ObservationIgnored var preparedPromptRun: AssetPromptRun?
    @ObservationIgnored var activePromptRun: AssetPromptRun?
    @ObservationIgnored var promptProgressTask: Task<Void, Never>?
    /// The observable progress line the workshop renders while a run is live.
    var promptProgress: PromptProgressPresentation?

    // MARK: Plan 021 — the armed scene-prompt run (the +PromptRun beats at scene scale)
    /// The scene-prompt run prepared by the Generate gesture. It starts immediately after
    /// preflight, except while the project's one-time disclosure awaits acknowledgement.
    @ObservationIgnored var preparedScenePromptRun: ScenePromptRun?
    @ObservationIgnored var activeScenePromptRun: ScenePromptRun?
    @ObservationIgnored var scenePromptProgressTask: Task<Void, Never>?
    @ObservationIgnored var inlinePromptEditors: [UUID: ScenePromptCardInlineEditor] = [:]
    /// The observable progress line the package view renders while a run is live.
    var scenePromptProgress: ScenePromptRunProgressPresentation?
    /// Presentation-only wall-clock anchor for a live elapsed counter. Durable request
    /// timings remain on the parent and child jobs.
    var scenePromptRunStartedAt: Date?
    /// Standard performs one self-reviewed request; High Quality adds an independent
    /// second reviewer. This is captured into the run's persisted settings at launch.
    var scenePromptQualityMode: ScenePromptQualityMode = .standard
    /// Presentation-only replacement state. The committed prompt stays in FilmCore until
    /// its successor is validated, while the workspace immediately clears the old cards.
    var isReplacingScenePrompt = false
    var pendingScenePromptDisclosure: ScenePromptDisclosurePresentation?
    var presentedScenePromptReport: ScenePromptReportPresentation?

    // MARK: Plan 024 — local reference-image generation and scene archives
    /// Plan 026's in-workspace navigation. This is presentation state only; the selected
    /// requirement is still loaded through the existing `RequirementDetail` read.
    var selectedReferenceRequirementID: UUID?
    /// Root-level presentation so the expanded viewer covers both workspace columns.
    var referenceImageLightbox: ReferenceImageLightboxPresentation?
    /// Archived (`needs_review`) versions for the selected scene's planned references.
    var workspaceReferenceArchives: [SceneReferenceArchive] = []
    /// FilmCore-derived create refusals keyed by scene reference requirement.
    var workspaceReferenceCreationRefusals: [UUID: String] = [:]
    /// The progress line shown inside the Create Image sheet.
    var imageGenerationProgress: ImageGenerationProgress?
    /// A provider or candidate-import failure shown without dismissing the creation sheet.
    var referenceImageGenerationErrorMessage: String?
    /// Finder-safe discovery/capability result for the selected app-wide preset.
    var imageGeneratorStatus: ImageGeneratorStatus?
    /// Routes the existing prompt-run sheets to the Create Image workflow while it is open.
    var referenceCreationRequirementID: UUID?
    /// The requirement snapshot owned by the active creation workflow. This must not share
    /// `requirementDetail` with workspace browsing: navigating to another reference while a
    /// prompt or provider run is in flight may replace the browsed detail, but it must never
    /// retarget or strand the active run.
    var referenceImageCreationDetail: RequirementDetail?
    /// The active FIFO item, retained for the existing toolbar and disclosure routing.
    /// Card presentation is keyed by `referenceImageJobStates`, never by this singleton.
    var inPlaceReferenceGenerationRequirementID: UUID?
    var inPlaceReferenceGenerationFailedRequirementID: UUID?
    var inPlaceReferenceGenerationErrorMessage: String?
    var inPlaceReferenceGenerationKind: InPlaceReferenceGenerationKind?
    var referenceImageCreationMode: ReferenceImageCreationMode = .create
    var referenceIncludesCurrentImage = false
    var referenceImageGenerationAttachment: ReferenceImageGenerationAttachment?
    /// Validated external references remain available for later edit/regenerate runs in
    /// this project window. They stay ephemeral and are never copied into the bundle.
    @ObservationIgnored var retainedReferenceImageGenerationAttachments: [
        UUID: ReferenceImageGenerationAttachment
    ] = [:]
    /// FilmCore's complete launch/commit token: prompt digest, target current, and ordered
    /// canonical dependency versions. The exact value travels back with the candidates.
    var referenceImageGenerationContext: ReferenceImageGenerationContext?
    var referencePromptDraft = ""
    var referencePromptDraftID: UUID?
    var referencePromptValidationMessage: String?
    var isSavingReferencePrompt = false
    var isRemovingReferencePrompt = false
    @ObservationIgnored var referencePromptDraftRevision = 0
    @ObservationIgnored var referencePromptSavedRevision = 0
    @ObservationIgnored var referencePromptSaveTask: Task<Void, Never>?
    /// Queued/running/selection/import/error presentation belongs to the requirement, so
    /// reopening a reference restores its chooser without blocking the next queued job.
    var referenceImageJobStates: [UUID: ReferenceImageJobState] = [:]
    var generatedCandidateSelections: [UUID: GeneratedCandidateSelectionPresentation] = [:]
    @ObservationIgnored var referenceImageQueue: [ReferenceImageQueueItem] = []
    @ObservationIgnored var activeReferenceImageQueueItem: ReferenceImageQueueItem?
    @ObservationIgnored var referenceImageDisclosureGate: ReferenceImageDisclosureGate?
    @ObservationIgnored var activeImageGenerator: (any ImageGenerating)?
    @ObservationIgnored var imageGenerationProgressTask: Task<Void, Never>?
    /// Owns the complete launch → validation → import/choice handoff, not only `Process`.
    @ObservationIgnored var referenceImageGenerationRunID: UUID?
    @ObservationIgnored var referenceImageGenerationTask: Task<Void, Never>?
    var isImportingGeneratedCandidate = false
    /// Dedicated commit phase; provider progress can never overwrite this gate.
    var isReferenceImageCommitInProgress = false
    @ObservationIgnored var generatedCandidateImportRunID: UUID?
    @ObservationIgnored var generatedCandidateImportTask: Task<Void, Never>?

    // MARK: Generation state (PHASE5_DESIGN §5 — the actions are in
    // `ProjectWindowModel+Generation.swift`, never in a view)

    /// §7.5's package summaries — one read per refresh beat, shared by the Generation
    /// section's list and the Dashboard's Generation Packages block (§3.3).
    var _scenePackages: [ScenePackageSummary] = []
    /// The list's package-state filter; a view-model filter over the derived rows.
    var _generationFilter: GenerationPackageFilter = .all
    /// The selected scene's §7.5 detail payload.
    var _scenePackageDetail: ScenePackageDetail?
    /// The prompt history under the active profile, loaded by the package view's tasks.
    var generationPromptHistory: [ScenePrompt] = []
    /// Canonical ordered set history, current included.
    var generationPromptSetHistory: [ScenePromptSetDetail] = []
    /// §14.6's chooser data: every imported skill and the current selection.
    var importedSkillRows: [ImportedSkill] = []
    var selectedSkillRow: ImportedSkill?
    /// Project-scoped prose loaded through the model so SwiftUI never queries storage.
    var workspaceStyleBible = ""
    /// What the last export wrote (§3.8) — its own report sheet.
    var presentedExportSummary: GenerationExportPresentation?
    /// §14.7's stale-export confirm, armed by a refused single-scene export.
    var pendingStaleExport: PendingStaleExport?

    // MARK: Undo state (the bridge itself is `UndoBridge.swift`)

    /// `true` while exactly one inverse is in flight (§3.8). Undo and redo are serialized:
    /// the model's `canUndo` / `canRedo` report `false` while it is set, and the window's
    /// `ProjectUndoManager` answers `false` too, so the **system** Edit ▸ Undo / Redo items
    /// grey out and a second ⌘Z cannot race the first.
    var isApplyingInverse: Bool {
        get { inverseInFlight }
        set {
            inverseInFlight = newValue
            (undoManager as? ProjectUndoManager)?.isApplyingInverse = newValue
        }
    }

    /// The observable storage behind `isApplyingInverse`; written only through it, so the
    /// `ProjectUndoManager` mirror can never fall out of step.
    private var inverseInFlight = false

    /// The newest `edit_journal.seq` this model has already accounted for, and whether it
    /// has read the journal at all. `noteJournal(_:)` uses the pair to spot an entry no
    /// command of this window made — an AI run's — and clear the stack (§3.8).
    @ObservationIgnored var lastSeenJournalSeq: Int64 = 0
    @ObservationIgnored var hasReadJournal = false

    init(
        session: ProjectSession,
        undoManager: UndoManager,
        extractionAdapterFactory: (@MainActor () throws -> any HarnessAdapter)? = nil,
        extractionSettingsProvider: @escaping @MainActor () -> ExtractionSettings = {
            ExtractionPreferences.settings()
        },
        imageGeneratorFactory: (@MainActor () -> any ImageGenerating)? = nil,
        imageGeneratorForProvider: @escaping @MainActor (ImageProviderDescriptor) -> any ImageGenerating = { provider in
            return LocalImageGenerator(
                provider: provider,
                helperURL: ImageGeneratorPreferences.helperURL(),
                credentialSource: ImageProviderKeychain.shared
            )
        },
        imageChooser: @escaping @MainActor () async -> URL? = { nil },
        skillChooser: @escaping @MainActor () async -> URL? = { nil },
        finderRevealer: @escaping @MainActor (URL) -> Void = { _ in }
    ) {
        self.session = session
        self.undoManager = undoManager
        self.extractionAdapterFactory = extractionAdapterFactory
        self.extractionSettingsProvider = extractionSettingsProvider
        if let imageGeneratorFactory {
            // Preserve the existing injected-fake seam while production construction is
            // provider-aware. Test sources do not need to change for Plan 033.
            self.imageGeneratorFactory = { _ in imageGeneratorFactory() }
        } else {
            self.imageGeneratorFactory = imageGeneratorForProvider
        }
        self.imageChooser = imageChooser
        self.skillChooser = skillChooser
        self.finderRevealer = finderRevealer
    }

    nonisolated var bundleURL: URL { session.bundleURL }

    /// The window title (§3.11).
    var title: String { project?.name ?? bundleURL.deletingPathExtension().lastPathComponent }

    /// The window subtitle (§3.11), verbatim when there is no screenplay.
    var subtitle: String { script?.displayName ?? "No screenplay" }

    /// The first refresh, the default scene selection, and the long-lived `changes()`
    /// consumer.
    func start() async {
        if presentedUpgradeSummary == nil, let summary = await session.upgradeSummary {
            presentedUpgradeSummary = UpgradeSummaryPresentation(summary: summary)
        }
        await refresh()
        // A project window opens on its first scene — never on an empty selection — so the
        // workspace never shows the "Select a scene" placeholder to a project with scenes.
        // Selection here (before the window presents, and after a restored window's first
        // refresh) closes the race where the views' one-shot `.task` ran before the scenes
        // had loaded.
        await selectFirstWorkspaceSceneIfNeeded()
        guard observationTask == nil, !isClosed else { return }
        let stream = await session.changes()
        observationTask = Task { [weak self] in
            for await _ in stream {
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func refresh() async {
        guard !isClosed else { return }
        do {
            project = try await session.projectSnapshot()
            script = try await session.script()
            scenes = try await session.scenes()
            sequences = try await session.sequences()
            var summaries: [EntityKind: [EntitySummary]] = [:]
            var names: [UUID: String] = [:]
            for kind in EntityKind.allCases {
                var rows = try await session.entitySummaries(
                    kind: kind,
                    reviewState: entityReviewFilter.reviewState,
                    includeRejected: entityReviewFilter.includesRejected
                )
                if entityReviewFilter == .unanchored {
                    rows = rows.filter(\.hasUnanchoredEvidence)
                }
                summaries[kind] = rows
                // Names are read unfiltered: a continuity row or a relationship line has
                // to be able to name an entity the current filter is hiding, including a
                // tombstone.
                for summary in try await session.entitySummaries(kind: kind, includeRejected: true) {
                    names[summary.id] = summary.name
                }
            }
            entitySummaries = summaries
            entityNames = names
            locks = try await session.locks()
            // The manifest reads (§7.6), on the same beat as the entity reads so a badge,
            // a count, and a row can never disagree.
            requirementSummaries = try await session.requirementSummaries(
                kind: nil,
                tier: nil,
                reviewState: requirementReviewFilter.reviewState,
                includeRejected: requirementReviewFilter.includesRejected
            )
            manifestSummary = try await session.manifestSummary()
            proposedRequirementCount = try await session.requirementSummaries(
                kind: nil, tier: nil, reviewState: .proposed, includeRejected: false
            ).count
            // §6.4's Missing list, read on the same beat as the counts: the scope filter is
            // backed by this read, never by a predicate restated in a view.
            missingAssets = try await session.missingAssets()
            // PHASE4_DESIGN §7.5: one readiness snapshot per beat — the Dashboard, the
            // Scenes column, and the scene panel all read it (§3.3's one-derivation rule).
            _readinessSnapshot = try await session.readinessSnapshot()
            // PHASE5_DESIGN §7.5/§3.3: one package read per beat — the Generation list
            // and the Dashboard's Generation Packages block both consume it, so their
            // figures are byte-consistent by construction (the plan's STOP 4).
            _scenePackages = try await session.scenePackages()
            continuityEvents = try await session.continuityEvents()
            runs = try await session.runs()
            jobs = try await session.jobHistory()
            pendingReviewCount = try await session.pendingReviewCount()
            journalEntries = try await session.journal(limit: 200)
            // §3.8's clearing rule: an entry this window did not make — an AI run's —
            // invalidates the undo stack, and the journal is the only signal for it.
            noteJournal(journalEntries)
            var resolvedSceneTexts: [UUID: String] = [:]
            for scene in scenes {
                resolvedSceneTexts[scene.id] = try await session.sceneText(id: scene.id)
            }
            sceneTexts = resolvedSceneTexts
            aliasIndexIsCurrent = false
            continuityStatesAreCurrent = false
            pruneSelections()
            await reloadDetails()
            syncUndoMenu()
            refreshToken &+= 1
        } catch {
            self.error = .project(error)
        }
    }

    /// Drops selected ids that no longer exist. §5.5's Replace wipes every scene and entity
    /// row, so without this the next detail load would ask for a scene that is gone and
    /// raise "That scene is not in this project." over a perfectly successful import.
    private func pruneSelections() {
        let sceneIDs = Set(scenes.map(\.id))
        for (section, ids) in selection {
            if section == .scenes {
                selection[.scenes] = ids.intersection(sceneIDs)
            } else if section == .manifest {
                selection[.manifest] = ids.intersection(Set(requirementSummaries.map(\.id)))
            } else if section == .generation {
                // Only counted scenes carry a package row (§3.3).
                selection[.generation] = ids.intersection(Set(_scenePackages.map(\.sceneID)))
            } else if let kind = section.entityKind {
                selection[section] = ids.intersection(Set((entitySummaries[kind] ?? []).map(\.id)))
            }
        }
        if selectedSceneID == nil { highlightedRange = nil }
        if let renamingRequirementID, renamingRequirementID != selectedRequirementID {
            self.renamingRequirementID = nil
        }
        // An in-place rename whose row the filter (or the edit itself) just removed has
        // nothing left to commit into.
        if let renamingEntityID, renamingEntityID != selectedEntityID { self.renamingEntityID = nil }
    }

    // MARK: - Selection

    func selection(in section: ProjectSection) -> Set<UUID> { selection[section] ?? [] }

    func setSelection(_ ids: Set<UUID>, in section: ProjectSection) {
        selection[section] = ids
    }

    func searchText(in section: ProjectSection) -> String { searchTexts[section] ?? "" }

    func setSearchText(_ text: String, in section: ProjectSection) {
        searchTexts[section] = text
    }

    // MARK: - The editing surface's own state

    /// Switching the review filter re-reads the entity lists, because the filter is a
    /// store query (`entitySummaries(reviewState:includeRejected:)`), not a view predicate.
    func setEntityReviewFilter(_ filter: EntityReviewFilter) async {
        guard filter != entityReviewFilter, !isClosed else { return }
        entityReviewFilter = filter
        renamingEntityID = nil
        await refresh()
    }

    /// Balanced by every text control outside a sheet as focus arrives and leaves; the
    /// count (rather than a flag) makes it order-independent when focus moves straight
    /// from one field to the next.
    func setTextEditing(_ isEditing: Bool) {
        textEditingDepth = max(0, textEditingDepth + (isEditing ? 1 : -1))
    }

    /// `true` while any text control outside a sheet has focus, which is when the Entity
    /// menu's plain-key shortcuts must stand down.
    var isEditingText: Bool { textEditingDepth > 0 }

    /// Every state row in the project, in Continuity order — `(start scene ordinal,
    /// entity name)`. There is no project-wide states read (§6 hangs them off
    /// `EntityDetail`), so this walks the entities once and caches until the next refresh.
    func loadContinuityStates() async {
        guard !isClosed, !continuityStatesAreCurrent else { return }
        do {
            var states: [EntityState] = []
            for (_, summaries) in entitySummaries {
                for summary in summaries {
                    states += try await session.entity(id: summary.id).states
                }
            }
            let ordinals = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0.ordinal) })
            continuityStates = states.sorted { left, right in
                let leftOrdinal = ordinals[left.startSceneID] ?? Int.max
                let rightOrdinal = ordinals[right.startSceneID] ?? Int.max
                if leftOrdinal != rightOrdinal { return leftOrdinal < rightOrdinal }
                let leftName = entityNames[left.entityID] ?? ""
                let rightName = entityNames[right.entityID] ?? ""
                if leftName != rightName { return leftName < rightName }
                return left.id.uuidString < right.id.uuidString
            }
            continuityStatesAreCurrent = true
        } catch {
            self.error = .project(error)
        }
    }

    /// Arms the Reject/Delete confirmation over the current selection (§3.11).
    func confirmDeletion(of ids: [UUID]) {
        guard !ids.isEmpty else { return }
        pendingEntityDeletion = PendingEntityDeletion(ids: ids)
    }

    /// The confirmation's confirm action: §6 routes each row to a hard delete or a
    /// tombstone, which `deleteEntities(ids:)` already does per row.
    ///
    /// It takes the armed value rather than reading it back off the model, because a
    /// `confirmationDialog` clears its `isPresented` binding as it dismisses — which runs
    /// `cancelPendingDeletion()` — and that can land before the button's own action. The
    /// dialog is built with `presenting:`, so the value it hands back was captured when
    /// the dialog was built and is still there.
    func performDeletion(_ pending: PendingEntityDeletion) async {
        pendingEntityDeletion = nil
        await deleteEntities(ids: pending.ids)
    }

    /// The same action for any caller that has no captured dialog value.
    func confirmPendingDeletion() async {
        guard let pending = pendingEntityDeletion else { return }
        await performDeletion(pending)
    }

    func cancelPendingDeletion() {
        pendingEntityDeletion = nil
    }

    /// The one selected scene, or `nil` for an empty or multiple selection.
    var selectedSceneID: UUID? { singleSelection(in: .scenes) }

    /// The one selected entity in the **current** section, or `nil`.
    var selectedEntityID: UUID? {
        guard section.entityKind != nil else { return nil }
        return singleSelection(in: section)
    }

    func singleSelection(in section: ProjectSection) -> UUID? {
        let ids = selection(in: section)
        return ids.count == 1 ? ids.first : nil
    }

    // MARK: - Details

    /// Reloads whichever detail the current selection names.
    func reloadDetails() async {
        await loadSceneDetail()
        await loadEntityDetail()
        await loadScenePackageDetail()
        if let selectedReferenceRequirementID {
            await loadWorkspaceReference(requirementID: selectedReferenceRequirementID)
        } else {
            await loadRequirementDetail()
        }
    }

    func loadSceneDetail() async {
        guard !isClosed, let id = selectedSceneID else {
            sceneDetail = nil
            sceneDetailText = ""
            highlightedRange = nil
            return
        }
        do {
            sceneDetail = try await session.scene(id: id)
            sceneDetailText = try await session.sceneText(id: id)
        } catch {
            sceneDetail = nil
            sceneDetailText = ""
            self.error = .project(error)
        }
    }

    func loadEntityDetail() async {
        await loadEntityDetail(id: selectedEntityID)
    }

    /// Loads an entity independently of the retired entity-category navigation. The
    /// scene workspace uses this for its focused correction sheet while `section`
    /// remains `.scenes`.
    func loadEntityDetail(id: UUID?) async {
        guard !isClosed, let id else {
            entityDetail = nil
            return
        }
        do {
            entityDetail = try await session.entity(id: id)
        } catch {
            entityDetail = nil
            self.error = .project(error)
        }
    }

    /// Entity search matches name **and aliases** (§3.11), and aliases live only on
    /// `EntityDetail` — so the index is built once, on the first search after a refresh.
    func loadAliasIndex() async {
        guard !isClosed, !aliasIndexIsCurrent else { return }
        do {
            var index: [UUID: [String]] = [:]
            for (_, summaries) in entitySummaries {
                for summary in summaries {
                    index[summary.id] = try await session.entity(id: summary.id).aliases.map(\.alias)
                }
            }
            aliasIndex = index
            aliasIndexIsCurrent = true
        } catch {
            self.error = .project(error)
        }
    }

    /// The evidence span mapped into the selected scene's own text, clamped to it.
    var highlightInSceneText: Range<Int>? {
        guard let highlightedRange, let scene = sceneDetail?.scene else { return nil }
        let length = (sceneDetailText as NSString).length
        let start = max(0, min(highlightedRange.start - scene.range.start, length))
        let end = max(start, min(highlightedRange.end - scene.range.start, length))
        return start < end ? start ..< end : nil
    }

    // MARK: - Navigation

    /// §3.11's navigation API: switch section, set selection, and flash the span.
    func reveal(_ target: RevealTarget) async {
        switch target {
        case let .scene(id, highlight):
            section = .scenes
            setSelection([id], in: .scenes)
            if scenePackage(forSceneID: id) != nil {
                setSelection([id], in: .generation)
            }
            highlightedRange = highlight
            await loadSceneDetail()
            await loadScenePackageDetail()
            if highlight != nil { await flashHighlight() }
        case let .entity(id):
            guard let kind = entityKind(of: id),
                  let destination = ProjectSection.allCases.first(where: { $0.entityKind == kind })
            else { return }
            section = destination
            setSelection([id], in: destination)
            await loadEntityDetail()
        case let .requirement(id):
            // PHASE4_DESIGN §5.4's deep link: the shipped section-plus-selection
            // navigation — no new machinery (the workshop keys off the single selection).
            await revealRequirement(id: id)
        case let .scenePackage(id):
            // Plan 023: a package deep link selects the same scene in both workspace reads;
            // Generation is no longer a primary section.
            section = .scenes
            setSelection([id], in: .scenes)
            setSelection([id], in: .generation)
            await loadSceneDetail()
            await loadScenePackageDetail()
        }
    }

    private func entityKind(of id: UUID) -> EntityKind? {
        for (kind, summaries) in entitySummaries where summaries.contains(where: { $0.id == id }) {
            return kind
        }
        return nil
    }

    /// Awaited rather than detached, so no command leaves work running behind it.
    private func flashHighlight() async {
        isHighlightFlashing = true
        try? await Task.sleep(for: .milliseconds(900))
        isHighlightFlashing = false
    }

    func toggleInspector() {
        isInspectorPresented.toggle()
    }

    // MARK: - Import (contract D, one code path)

    /// The single import code path: File ▸ Import Screenplay…, `importScreenplayButton`, and
    /// a drop on the Scenes empty state all land here.
    ///
    /// Replace (§5.5) has no separate entry point: when a script already exists and
    /// `canReplaceScreenplay()` is `true` this arms the confirmation sheet, and when it is
    /// `false` the import is attempted anyway so FilmCore's `.replaceRefused(reason:)` text
    /// is what the operator reads, verbatim.
    func importScreenplay(from url: URL) async {
        guard !isImporting, !isClosed else { return }
        if script != nil, (try? await session.canReplaceScreenplay()) == true {
            pendingReplace = PendingReplace(url: url)
            return
        }
        await performImport(from: url)
    }

    /// The Replace confirmation's confirm action; non-invertible, as the sheet says.
    ///
    /// It takes the armed value rather than reading it back off the model, for the same
    /// reason `performDeletion(_:)` does: a `confirmationDialog` clears its `isPresented`
    /// binding as it dismisses — which runs `cancelPendingReplace()` — and that can land
    /// before the button's own action, leaving the confirm to find nothing and silently
    /// import nothing. The dialog is built with `presenting:`, so the value handed back
    /// was captured when the dialog was built.
    func performReplace(_ pending: PendingReplace) async {
        pendingReplace = nil
        await performImport(from: pending.url)
    }

    /// The same action for a caller that has no captured value.
    func confirmPendingReplace() async {
        guard let pending = pendingReplace else { return }
        await performReplace(pending)
    }

    func cancelPendingReplace() {
        pendingReplace = nil
    }

    private func performImport(from url: URL) async {
        guard !isImporting, !isClosed else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let summary = try await session.importScreenplay(from: url, actor: .human)
            importSummary = summary
            // §3.8: import and Replace are **non-invertible**, so whatever was on the stack
            // describes rows this import may just have replaced. Cleared explicitly rather
            // than relying on `didApply`'s non-invertible branch, which an import — whose
            // `JournalEntry` never reaches a command — does not go through.
            clearUndoAfterNonInvertibleChange()
            await refresh()
            presentedImportSummary = ImportSummaryPresentation(summary: summary)
        } catch {
            // FilmCore's refusal wording (§5.5) is surfaced verbatim.
            self.error = .project(error)
        }
    }

    /// Dismissing the summary sheet is what reveals the first scene (contract D).
    func dismissImportSummary() async {
        presentedImportSummary = nil
        if let first = scenes.first {
            await reveal(.scene(id: first.id, highlight: nil))
        }
    }

    /// Whether a dropped file is one the importer accepts — the same extension predicate the
    /// open panel's delegate applies (§3.2: `.txt` goes through the Fountain parser).
    static func acceptsDroppedScreenplay(_ url: URL) -> Bool {
        ScreenplayOpenPanelDelegate.allowedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Where a job wrote its log, for Show Log in Finder.
    func logURL(for job: Job) async -> URL? {
        try? await session.resolve(job.logRelativePath)
    }

    func restoreNavigation(section: ProjectSection, selection: [ProjectSection: Set<UUID>]) {
        self.section = section
        self.selection = selection
    }

    /// Window teardown: stop observing, then release the session. The window bridge awaits
    /// this and the coordinator tracks it so quit cannot outrun the last database close.
    func close() async {
        guard !isClosed else { return }
        await flushInlinePromptEditors()
        await cancelAllReferenceImageGeneration()
        if referenceCreationRequirementID != nil {
            _ = await flushReferencePromptDraft()
        }
        isClosed = true
        observationTask?.cancel()
        observationTask = nil
        extractionProgressTask?.cancel()
        extractionProgressTask = nil
        if let activeExtractionRun { try? await activeExtractionRun.cancel() }
        activeExtractionRun = nil
        manifestProgressTask?.cancel()
        manifestProgressTask = nil
        if let activeManifestRun { try? await activeManifestRun.cancel() }
        activeManifestRun = nil
        promptProgressTask?.cancel()
        promptProgressTask = nil
        if let activePromptRun { try? await activePromptRun.cancel() }
        activePromptRun = nil
        scenePromptProgressTask?.cancel()
        scenePromptProgressTask = nil
        if let activeScenePromptRun { try? await activeScenePromptRun.cancel() }
        activeScenePromptRun = nil
        isReplacingScenePrompt = false
        referencePromptSaveTask?.cancel()
        referencePromptSaveTask = nil
        try? await session.close()
    }
}

/// `ImportSummary` and `UpgradeSummary` are value types with no identity, and
/// `.sheet(item:)` needs one — so each presentation carries its own.
struct ImportSummaryPresentation: Identifiable, Equatable {
    let id = UUID()
    let summary: ImportSummary
}

struct UpgradeSummaryPresentation: Identifiable, Equatable {
    let id = UUID()
    let summary: UpgradeSummary
}

/// One validated asset version selected for Plan 026's root-level expanded viewer.
struct ReferenceImageLightboxPresentation: Identifiable, Equatable {
    let version: AssetVersion
    let accessibilityLabel: String

    var id: UUID { version.id }
}

/// The Edit menu's view of the window's `UndoManager` (§3.8).
///
/// The titles are the manager's own `undoMenuItemTitle` / `redoMenuItemTitle`, which is
/// how "Undo Rename Character" reaches the menu: the only source of the action name is
/// `EditOperation.displayName`, handed to `setActionName` at registration.
struct UndoMenuState: Equatable, Sendable {
    var undoTitle: String = "Undo"
    var redoTitle: String = "Redo"
    var canUndo: Bool = false
    var canRedo: Bool = false
}

/// A screenplay waiting on §5.5's Replace confirmation.
struct PendingReplace: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}

/// Media waiting on §7.3's Delete confirmation: either one **rejected** version, or the
/// whole slot. Both are non-invertible, and both remove rows in the transaction and files
/// after commit (§4.1) — which is what the confirmation is for.
struct PendingMediaDeletion: Identifiable, Equatable {
    enum Target: Equatable {
        /// `deleteVersion`: allowed only on a rejected version.
        case version(id: UUID, number: Int)
        /// `deleteAsset`: the row, every version row, and their files.
        case asset(id: UUID, versionCount: Int)
    }

    let id = UUID()
    let target: Target
    let requirementName: String

    var title: String {
        switch target {
        case let .version(_, number): "Delete version \(number)?"
        case .asset: "Delete every reference image for “\(requirementName)”?"
        }
    }

    var message: String {
        switch target {
        case .version:
            "The image file is removed from the project after the change is saved. This cannot be undone."
        case let .asset(_, count):
            "\(count) image\(count == 1 ? "" : "s") and the slot's record are removed; the files go after the change is saved. This cannot be undone."
        }
    }
}

/// §4.1's Clear Orphaned Media, listed and awaiting confirmation. It journals nothing and
/// touches no row, so there is nothing to undo — the confirmation is the only gate.
struct PendingOrphanSweep: Identifiable, Equatable {
    let id = UUID()
    let paths: [RelativeProjectPath]
}

/// Entities waiting on §3.11's Delete confirmation. Each row is routed by §6 when the
/// operator confirms — a `parser` or `ai` row is tombstoned, never hard-deleted.
struct PendingEntityDeletion: Identifiable, Equatable {
    let id = UUID()
    let ids: [UUID]
}

/// The entity list's minimal review filter (§3.6, §3.11).
///
/// `.all` is what every default list shows: everything except tombstones. The three
/// named states are the filter proper, and `.rejected` is the only way to see a rejected
/// row at all. Plan 007 extends this control with Unanchored and the review banner.
enum EntityReviewFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case proposed
    case accepted
    case rejected
    case unanchored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .proposed: "Proposed"
        case .accepted: "Accepted"
        case .rejected: "Rejected"
        case .unanchored: "Unanchored"
        }
    }

    /// What `entitySummaries(reviewState:)` is asked for.
    var reviewState: ReviewState? {
        switch self {
        case .all: nil
        case .proposed: .proposed
        case .accepted: .accepted
        case .rejected: .rejected
        case .unanchored: nil
        }
    }

    /// Only the Rejected filter opts into tombstones (§3.6: default reads exclude them).
    var includesRejected: Bool { self == .rejected }
}

struct AnalysisActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let at: Date
    let message: String
}

struct AnalysisFailureDetail: Identifiable, Equatable {
    let id: UUID
    let title: String
    let code: String?
    let message: String
}

struct AnalysisCompletionPresentation: Equatable {
    let report: ApplyReport
    let failureDetails: [AnalysisFailureDetail]
}

struct AnalysisFailurePresentation: Equatable {
    let message: String
    let details: [AnalysisFailureDetail]
}

enum AnalysisWorkflowPhase: Equatable {
    case confirmation
    case running
    case paused
    case completed(AnalysisCompletionPresentation)
    case failed(AnalysisFailurePresentation)
    case cancelled

    var isActive: Bool {
        switch self {
        case .running, .paused: true
        case .confirmation, .completed, .failed, .cancelled: false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .confirmation, .running, .paused: false
        }
    }
}

struct AnalysisWorkflowPresentation: Identifiable, Equatable {
    let id = UUID()
    let requestCount: Int
    let requiresDisclosure: Bool
    var phase: AnalysisWorkflowPhase = .confirmation
    var startedAt: Date?
    var runID: UUID?
    var activity: [AnalysisActivityEntry] = []
}

struct RevertReportPresentation: Identifiable, Equatable {
    let id = UUID()
    let report: RevertReport
}

struct CacheSummaryPresentation: Identifiable, Equatable {
    let id = UUID()
    let summary: ClearedCacheSummary
}

/// What an export wrote (§3.8) — the report sheet's payload. Exports are derived
/// artifacts, so this reports paths and sizes only; nothing is read back into the model.
struct GenerationExportPresentation: Identifiable, Equatable {
    let id = UUID()
    let exports: [ScenePackageExport]
}

/// §14.7's stale-export confirm: the refused export, carrying the store's own reason.
struct PendingStaleExport: Identifiable, Equatable {
    let sceneID: UUID
    let reason: String
    var id: UUID { sceneID }
}

struct PreparedExtraction {
    let run: ExtractionRun
    let settings: ExtractionSettings
    let requestCount: Int
    let requiresDisclosure: Bool
}

/// The sheets §3.11's editing surface presents. They are hosted once, by
/// `ProjectSplitView`, so the Entity menu can raise one through the window model instead
/// of reaching into a view.
enum ProjectSheet: Identifiable, Hashable {
    case addScenes
    case merge
    case split
    case moveInto
    case journal
    case addState(entityID: UUID)
    /// The row travels with the case rather than an id: the Continuity list and the
    /// entity inspector both raise this sheet, and only one of them has the row loaded.
    case editState(EntityState)
    case addEvent
    case editEvent(ContinuityEvent)
    case addRelationship(entityID: UUID)
    case sceneEntities(sceneID: UUID)
    /// PHASE2_DESIGN §7.2's combine over the Manifest list's multi-selection: the operator
    /// picks which variant survives, exactly as the entity merge sheet does.
    case combineRequirements

    var id: String {
        switch self {
        case .addScenes: "addScenes"
        case .merge: "merge"
        case .split: "split"
        case .moveInto: "moveInto"
        case .journal: "journal"
        case let .addState(entityID): "addState-\(entityID)"
        case let .editState(state): "editState-\(state.id)"
        case .addEvent: "addEvent"
        case let .editEvent(event): "editEvent-\(event.id)"
        case let .addRelationship(entityID): "addRelationship-\(entityID)"
        case let .sceneEntities(sceneID): "sceneEntities-\(sceneID)"
        case .combineRequirements: "combineRequirements"
        }
    }
}

extension ProjectWindowModel: Equatable {
    /// Identity equality, so the model can travel as a `FocusedValue`.
    nonisolated static func == (lhs: ProjectWindowModel, rhs: ProjectWindowModel) -> Bool {
        lhs === rhs
    }
}
