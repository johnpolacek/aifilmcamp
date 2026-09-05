import Foundation

// The Phase 5a package-model types (PHASE5_DESIGN §3.1–§3.5, §4.4; Plan 018 contract B).
//
// Names here are contracts: §4.4 freezes them for Plans 019–021. Everything is a value —
// a package is **never stored** (§3.1): it assembles at read time from one prompt row,
// the derived reference plan, and the derived continuity context, and its state derives
// against the project's active target profile (§3.3).

// MARK: - Target profiles (§3.5)

/// One generation target profile (§3.5) — a value in the FilmCore catalog, not a type,
/// not a protocol, not a provider. It parameterizes the §3.2 reference budget, the
/// §8.3 validator's enum checks, and one line of the §8.2 input. `nil` duration range or
/// empty ratio/resolution sets mean "no constraint" — `generic`'s whole personality
/// (§14.2), and exactly what lets the validator skip its profile checks.
public struct TargetProfile: Equatable, Hashable, Sendable {
    /// The catalog id persisted on `scene_prompts.target_profile` and in
    /// `projects.generation_target_profile` — an opaque string by contract.
    public let id: String
    public let displayName: String
    /// The image-reference budget the §3.2 plan refuses past (`sceneReferencesExceedProfileLimit`),
    /// never truncates past.
    public let imageReferenceLimit: Int
    /// Inclusive seconds range; `nil` carries no duration constraint.
    public let durationRange: ClosedRange<Int>?
    /// Empty carries no aspect-ratio constraint.
    public let aspectRatios: [String]
    /// Empty carries no resolution constraint.
    public let resolutions: [String]
    /// §8.3's sixth-revision grammar scope: whether this profile declares the
    /// per-reference **declaration-line grammar** (a solo `@Image k` line per satisfied
    /// designator carrying one of the four fidelity terms and a `do not` exclusion).
    /// `seedance_2_5` declares it — the fidelity vocabulary and exclusion phrasing are
    /// the Seedance reference discipline; `generic` declares **coverage-only**, so an
    /// imported skill writing another model's syntax under it is not rejected for
    /// lacking Seedance's grammar. The universal coverage contract never varies.
    public let declaresReferenceGrammar: Bool

    public init(
        id: String,
        displayName: String,
        imageReferenceLimit: Int,
        durationRange: ClosedRange<Int>?,
        aspectRatios: [String],
        resolutions: [String],
        declaresReferenceGrammar: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.imageReferenceLimit = imageReferenceLimit
        self.durationRange = durationRange
        self.aspectRatios = aspectRatios
        self.resolutions = resolutions
        self.declaresReferenceGrammar = declaresReferenceGrammar
    }

    /// Whether the settings triple passes this profile's constraints (§8.3's checks,
    /// parameterized here; a `nil` range or empty set admits everything). An **unset**
    /// value — `nil` duration, `''` ratio or resolution, §4.3's column defaults — passes:
    /// "'' allowed" is §8.3's own rule, and a missing optional setting is the filmmaker's
    /// choice, not an invalid one. Only a value outside a declared set refuses.
    public func accepts(
        durationSeconds: Int?, aspectRatio: String, resolution: String
    ) -> Bool {
        if let seconds = durationSeconds,
           let range = durationRange, !range.contains(seconds) {
            return false
        }
        if !aspectRatio.isEmpty, !aspectRatios.isEmpty, !aspectRatios.contains(aspectRatio) {
            return false
        }
        if !resolution.isEmpty, !resolutions.isEmpty, !resolutions.contains(resolution) {
            return false
        }
        return true
    }
}

/// The Film-Camp-authored profile catalog (§3.5). v1 ships two entries — `seedance_2_5`
/// done well plus `generic`, the constraint-free escape hatch (§14.2). Kling, Veo, and
/// Runway are future **data**, not future code.
///
/// The Seedance entry mirrors the vendored snapshot of 2026-08-07. The vendored
/// `specs/model-specs.json` is never read by app code at runtime; catalog changes require
/// an explicit profile update.
public enum TargetProfileCatalog {
    /// §14.2's default: Seedance 2.5 — 30 images, 4–30 s, the seven aspect ratios,
    /// 480p/720p (§12).
    public static let seedance2_5 = TargetProfile(
        id: "seedance_2_5",
        displayName: "Seedance 2.5",
        imageReferenceLimit: 30,
        durationRange: 4...30,
        aspectRatios: ["auto", "21:9", "16:9", "4:3", "1:1", "3:4", "9:16"],
        resolutions: ["480p", "720p"],
        declaresReferenceGrammar: true
    )

    /// The "Generate Anywhere" target: same image limit, deliberately no other
    /// constraint (§14.2).
    public static let generic = TargetProfile(
        id: "generic",
        displayName: "Generic",
        imageReferenceLimit: 30,
        durationRange: nil,
        aspectRatios: [],
        resolutions: []
    )

    /// Every cataloged entry.
    public static let all: [TargetProfile] = [seedance2_5, generic]

    /// The column default of `projects.generation_target_profile` (§3.5).
    public static let defaultProfileID = seedance2_5.id

    /// The entry for `id`, or `nil` when the catalog no longer carries it — such an id
    /// reads `needsPreparation` with the refusal naming the missing profile, never a
    /// crash (§3.5).
    public static func profile(id: String) -> TargetProfile? {
        all.first { $0.id == id }
    }
}

// MARK: - Package states (§3.3)

/// OVERVIEW `#asset-states`' generation-package vocabulary, activated as derived values.
/// Raw values are stable strings later phases cite (§11).
public enum ScenePackageState: String, Codable, Equatable, Sendable {
    case needsPreparation = "needs_preparation"
    case generationReady = "generation_ready"
    case stale
}

// MARK: - Row types (§4.3)

/// One versioned generation result for a scene/profile. The highest `setNumber` is
/// current; prior sets remain immutable history. Card edits mark `humanEdited` while
/// creation provenance remains intact.
public struct ScenePromptSet: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let sceneID: UUID
    public let targetProfile: String
    public let setNumber: Int
    public let skillID: String
    public let skillEntryPath: String
    public let skillEntrySHA256: String
    public let inputDigest: String
    public let inputFormatVersion: Int
    public let humanEdited: Bool
    public let provenance: Provenance

    public init(
        id: UUID, projectID: UUID, sceneID: UUID, targetProfile: String,
        setNumber: Int, skillID: String, skillEntryPath: String,
        skillEntrySHA256: String, inputDigest: String, inputFormatVersion: Int,
        humanEdited: Bool, provenance: Provenance
    ) {
        self.id = id
        self.projectID = projectID
        self.sceneID = sceneID
        self.targetProfile = targetProfile
        self.setNumber = setNumber
        self.skillID = skillID
        self.skillEntryPath = skillEntryPath
        self.skillEntrySHA256 = skillEntrySHA256
        self.inputDigest = inputDigest
        self.inputFormatVersion = inputFormatVersion
        self.humanEdited = humanEdited
        self.provenance = provenance
    }
}

/// One ordered external-generation handoff inside a set. It is deliberately not a shot.
public struct ScenePromptCard: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let setID: UUID
    public let order: Int
    public let title: String
    public let body: String
    public let guidance: String
    public let durationSeconds: Int?
    public let aspectRatio: String
    public let resolution: String

    public init(
        id: UUID, setID: UUID, order: Int, title: String, body: String,
        guidance: String, durationSeconds: Int?, aspectRatio: String, resolution: String
    ) {
        self.id = id
        self.setID = setID
        self.order = order
        self.title = title
        self.body = body
        self.guidance = guidance
        self.durationSeconds = durationSeconds
        self.aspectRatio = aspectRatio
        self.resolution = resolution
    }
}

/// One card-local dense `@Image N` binding to immutable approved-version facts.
public struct ScenePromptCardReference: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let cardID: UUID
    public let position: Int
    public let requirementID: UUID?
    public let versionID: UUID?
    public let `class`: ReferenceClass
    public let role: String
    public let exclusion: String
    public let fidelity: ReferenceFidelity
    public let sha256: String
    /// Bundle-relative path captured at set creation so stale/history cards never join
    /// the current scene plan to find their bytes.
    public let relativePath: String
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let displayName: String
    public let source: FactSource
    public let jobID: UUID?
    public let createdAt: Date

    public init(
        id: UUID, cardID: UUID, position: Int, requirementID: UUID?, versionID: UUID?,
        class: ReferenceClass, role: String, exclusion: String,
        fidelity: ReferenceFidelity, sha256: String, relativePath: String,
        pixelWidth: Int?, pixelHeight: Int?, displayName: String,
        source: FactSource, jobID: UUID?, createdAt: Date
    ) {
        self.id = id
        self.cardID = cardID
        self.position = position
        self.requirementID = requirementID
        self.versionID = versionID
        self.class = `class`
        self.role = role
        self.exclusion = exclusion
        self.fidelity = fidelity
        self.sha256 = sha256
        self.relativePath = relativePath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.displayName = displayName
        self.source = source
        self.jobID = jobID
        self.createdAt = createdAt
    }
}

/// A current/history set with ordered cards, each carrying only its own citations.
public struct ScenePromptSetDetail: Equatable, Hashable, Sendable {
    public struct Card: Equatable, Hashable, Sendable, Identifiable {
        public let card: ScenePromptCard
        public let references: [ScenePromptCardReference]
        public var id: UUID { card.id }

        public init(card: ScenePromptCard, references: [ScenePromptCardReference]) {
            self.card = card
            self.references = references
        }
    }

    public let set: ScenePromptSet
    public let cards: [Card]
    public let staleReason: ScenePromptStaleReason?
    public var isStale: Bool { staleReason != nil }

    public init(set: ScenePromptSet, cards: [Card], staleReason: ScenePromptStaleReason?) {
        self.set = set
        self.cards = cards
        self.staleReason = staleReason
    }
}

/// The scene-prompt record (§4.3) — the Phase 3 prompt shape at scene scope, current per
/// `(sceneID, targetProfile)` pair: the current row is the highest `promptNumber` for the
/// pair, history by number, delete-the-newest as restore, no `is_current` flag (§3.1).
public struct ScenePrompt: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let sceneID: UUID
    /// The profile catalog id this prompt was rendered under (§3.5).
    public let targetProfile: String
    /// 1-based, assigned max + 1 in-transaction; gaps are legal after deletes.
    public let promptNumber: Int
    public let body: String
    /// Operator notes; `''` when none.
    public let guidance: String
    /// Profile-validated settings (§8.3); unconstrained profiles admit anything.
    public let durationSeconds: Int?
    public let aspectRatio: String
    public let resolution: String
    /// Skill identity triple; all three `''` for a human-authored prompt (the v6 CHECKs
    /// bind the triple to `created_source`).
    public let skillID: String
    /// Descriptor-relative; never an absolute path (the Plan 016 provenance rule).
    public let skillEntryPath: String
    public let skillEntrySHA256: String
    /// SHA-256 of the §8.2 rendered JSON — the freshness anchor (§3.4).
    public let inputDigest: String
    /// `ScenePromptInputBuilder.schemaVersion` at attach; a mismatch reads stale.
    public let inputFormatVersion: Int
    public let provenance: Provenance

    public init(
        id: UUID,
        projectID: UUID,
        sceneID: UUID,
        targetProfile: String,
        promptNumber: Int,
        body: String,
        guidance: String,
        durationSeconds: Int?,
        aspectRatio: String,
        resolution: String,
        skillID: String,
        skillEntryPath: String,
        skillEntrySHA256: String,
        inputDigest: String,
        inputFormatVersion: Int,
        provenance: Provenance
    ) {
        self.id = id
        self.projectID = projectID
        self.sceneID = sceneID
        self.targetProfile = targetProfile
        self.promptNumber = promptNumber
        self.body = body
        self.guidance = guidance
        self.durationSeconds = durationSeconds
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.skillID = skillID
        self.skillEntryPath = skillEntryPath
        self.skillEntrySHA256 = skillEntrySHA256
        self.inputDigest = inputDigest
        self.inputFormatVersion = inputFormatVersion
        self.provenance = provenance
    }
}

/// One immutable citation of what a scene prompt was prepared against (§4.3) — mirroring
/// `asset_prompt_references`: created with its prompt, never edited, removed with it.
public struct ScenePromptReference: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let promptID: UUID
    /// The `@Image` number, 1-based and dense over the satisfied subset (§3.2).
    public let position: Int
    /// SET NULL on delete; `sha256`/`displayName` are the record when the referent is gone.
    public let requirementID: UUID?
    public let versionID: UUID?
    public let `class`: ReferenceClass
    /// §3.2's derived role/exclusion/fidelity as sent — recorded history, stored nowhere else.
    public let role: String
    public let exclusion: String
    public let fidelity: ReferenceFidelity
    /// The referenced version's bytes at build time.
    public let sha256: String
    public let displayName: String
    public let source: FactSource
    public let jobID: UUID?
    public let createdAt: Date

    public init(
        id: UUID,
        promptID: UUID,
        position: Int,
        requirementID: UUID?,
        versionID: UUID?,
        class: ReferenceClass,
        role: String,
        exclusion: String,
        fidelity: ReferenceFidelity,
        sha256: String,
        displayName: String,
        source: FactSource,
        jobID: UUID?,
        createdAt: Date
    ) {
        self.id = id
        self.promptID = promptID
        self.position = position
        self.requirementID = requirementID
        self.versionID = versionID
        self.class = `class`
        self.role = role
        self.exclusion = exclusion
        self.fidelity = fidelity
        self.sha256 = sha256
        self.displayName = displayName
        self.source = source
        self.jobID = jobID
        self.createdAt = createdAt
    }
}

// MARK: - Derived shapes (§3.2)

/// One row of the §3.2 **reference plan**: a linked requirement thinned to active,
/// non-rejected, `necessity = 'required'`, carrying its derived class, attributes,
/// satisfaction, approved-version triple, and designator. Ordered by class rank →
/// requirement name → requirement id — a total key ending in id, the house rule;
/// dense `@Image N` designators over the approved subset alone.
public struct ScenePlannedReference: Equatable, Hashable, Sendable, Identifiable {
    /// The approved version that satisfies this row — present exactly when `isSatisfied`.
    public typealias ApprovedVersion = PlannedDependency.ApprovedVersion

    public let id: UUID
    /// The referenced requirement.
    public let requirementID: UUID
    public let requirementName: String
    /// Stable grouping key for Plan 029's derived entity bundles.
    public let entityID: UUID
    public let entityName: String
    public let entityKind: EntityKind
    /// Canonical template code, or `full_body` for a named outfit; empty for other variants.
    public let templateCode: String
    public let `class`: ReferenceClass
    /// §3.2's derived role/exclusion/fidelity through `ReferenceAttributeRules`.
    public let attributes: ReferenceAttributes
    public let isSatisfied: Bool
    /// Approved remains satisfied while this orthogonal flag asks for synchronization.
    public let isStale: Bool
    public let approvedVersion: ApprovedVersion?
    /// Non-nil only on satisfied rows; dense over the approved subset. No surface may
    /// re-derive it (the Phase 3 doc comment's rule, inherited).
    public let designator: Int?

    public init(
        id: UUID,
        requirementID: UUID,
        requirementName: String,
        entityID: UUID,
        entityName: String,
        entityKind: EntityKind,
        templateCode: String,
        class: ReferenceClass,
        attributes: ReferenceAttributes,
        isSatisfied: Bool,
        isStale: Bool = false,
        approvedVersion: ApprovedVersion?,
        designator: Int?
    ) {
        self.id = id
        self.requirementID = requirementID
        self.requirementName = requirementName
        self.entityID = entityID
        self.entityName = entityName
        self.entityKind = entityKind
        self.templateCode = templateCode
        self.class = `class`
        self.attributes = attributes
        self.isSatisfied = isSatisfied
        self.isStale = isStale
        self.approvedVersion = approvedVersion
        self.designator = designator
    }
}

/// §3.2's continuity context — the `entity_states` intervals covering the scene for every
/// entity appearing in it, ordered entity name → category → id. An empty context is a
/// true fact about the scene, never a missing input (§3.3).
public struct ContinuityContext: Equatable, Hashable, Sendable {
    public struct Entry: Equatable, Hashable, Sendable, Identifiable {
        public let entityID: UUID
        public let entityName: String
        public let category: StateCategory
        public let description: String
        /// The state row's id — the ordering key's final element.
        public let stateID: UUID

        public var id: UUID { stateID }

        public init(
            entityID: UUID,
            entityName: String,
            category: StateCategory,
            description: String,
            stateID: UUID
        ) {
            self.entityID = entityID
            self.entityName = entityName
            self.category = category
            self.description = description
            self.stateID = stateID
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }
}

// MARK: - Read shapes (§7.5)

/// Why a scene prompt reads stale (§3.4): the recorded format version differs from the
/// builder's, or a fresh render's digest differs. Staleness informs and never blocks.
public enum ScenePromptStaleReason: Equatable, Sendable {
    case olderInputFormat
    case inputsChanged
}

/// One current scene prompt with its citations and derived staleness — the package view's
/// prompt panel payload (§5.2), mirroring `AssetPromptDetail`.
public struct ScenePromptDetail: Equatable, Hashable, Sendable {
    /// One immutable citation row, as history (§3.2).
    public struct Citation: Equatable, Hashable, Sendable {
        public let id: UUID
        public let position: Int
        /// SET NULL columns — `nil` after the referent is gone; sha/name are the record.
        public let requirementID: UUID?
        public let versionID: UUID?
        public let `class`: ReferenceClass
        public let role: String
        public let exclusion: String
        public let fidelity: ReferenceFidelity
        public let sha256: String
        public let displayName: String

        public init(
            id: UUID,
            position: Int,
            requirementID: UUID?,
            versionID: UUID?,
            class: ReferenceClass,
            role: String,
            exclusion: String,
            fidelity: ReferenceFidelity,
            sha256: String,
            displayName: String
        ) {
            self.id = id
            self.position = position
            self.requirementID = requirementID
            self.versionID = versionID
            self.class = `class`
            self.role = role
            self.exclusion = exclusion
            self.fidelity = fidelity
            self.sha256 = sha256
            self.displayName = displayName
        }
    }

    public let id: UUID
    public let sceneID: UUID
    public let targetProfile: String
    public let promptNumber: Int
    public let body: String
    public let guidance: String
    public let durationSeconds: Int?
    public let aspectRatio: String
    public let resolution: String
    /// Descriptor-relative skill identity; all three `''` for a hand-authored prompt.
    public let skillID: String
    public let skillEntryPath: String
    public let skillEntrySHA256: String
    /// PROV `source` — converted to `human` by a body edit on an `ai` row (§7.1).
    public let source: FactSource
    /// `created_source` — skill provenance survives that conversion.
    public let createdSource: FactSource
    public let createdAt: Date
    public let citations: [Citation]
    /// Derived per §3.4; `nil` when fresh.
    public let staleReason: ScenePromptStaleReason?

    /// Convenience over `staleReason`.
    public var isStale: Bool { staleReason != nil }

    public init(
        id: UUID,
        sceneID: UUID,
        targetProfile: String,
        promptNumber: Int,
        body: String,
        guidance: String,
        durationSeconds: Int?,
        aspectRatio: String,
        resolution: String,
        skillID: String,
        skillEntryPath: String,
        skillEntrySHA256: String,
        source: FactSource,
        createdSource: FactSource,
        createdAt: Date,
        citations: [Citation],
        staleReason: ScenePromptStaleReason?
    ) {
        self.id = id
        self.sceneID = sceneID
        self.targetProfile = targetProfile
        self.promptNumber = promptNumber
        self.body = body
        self.guidance = guidance
        self.durationSeconds = durationSeconds
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.skillID = skillID
        self.skillEntryPath = skillEntryPath
        self.skillEntrySHA256 = skillEntrySHA256
        self.source = source
        self.createdSource = createdSource
        self.createdAt = createdAt
        self.citations = citations
        self.staleReason = staleReason
    }
}

/// One counted scene's package row (§7.5). Excluded scenes carry no summary — they join
/// no package state by rule (§3.3); surfaces that list them take them from the readiness
/// snapshot.
public struct ScenePackageSummary: Equatable, Identifiable, Sendable {
    public let sceneID: UUID
    public let ordinal: Int
    public let heading: String
    /// Plan 017's derived asset-ready state, read from the snapshot — never re-derived.
    public let assetReadyState: SceneReadinessState
    /// The §3.3 predicate, always evaluated against the active profile P.
    public let packageState: ScenePackageState
    public let activeProfileID: String
    /// Satisfied planned references (approved versions behind them).
    public let satisfiedCount: Int
    /// All planned references (satisfied and unsatisfied).
    public let plannedCount: Int
    /// The active profile's image budget.
    public let referenceLimit: Int
    /// Highest `prompt_number` under P, when any history exists there.
    public let currentPromptNumber: Int?

    public var id: UUID { sceneID }

    public init(
        sceneID: UUID,
        ordinal: Int,
        heading: String,
        assetReadyState: SceneReadinessState,
        packageState: ScenePackageState,
        activeProfileID: String,
        satisfiedCount: Int,
        plannedCount: Int,
        referenceLimit: Int,
        currentPromptNumber: Int?
    ) {
        self.sceneID = sceneID
        self.ordinal = ordinal
        self.heading = heading
        self.assetReadyState = assetReadyState
        self.packageState = packageState
        self.activeProfileID = activeProfileID
        self.satisfiedCount = satisfiedCount
        self.plannedCount = plannedCount
        self.referenceLimit = referenceLimit
        self.currentPromptNumber = currentPromptNumber
    }
}

/// The §5.2 package-view payload (§7.5): plan, continuity, current prompt with citations
/// and derived staleness, history numbers, profile.
public struct ScenePackageDetail: Equatable, Sendable {
    public let sceneID: UUID
    public let ordinal: Int
    public let heading: String
    public let synopsis: String
    /// Optional filmmaker-authored direction for the next prompt generation.
    public let creativeDirection: String
    /// Plan 017's state, read — never re-derived (contract C's STOP).
    public let assetReadyState: SceneReadinessState
    public let packageState: ScenePackageState
    /// The project's active profile the states were derived against (§3.3).
    public let activeProfile: TargetProfile
    /// The §3.2 plan, ordered; optional requirements are excluded from it and carried
    /// beside it, greyed, un-designated, never counted (§3.2).
    public let plan: [ScenePlannedReference]
    public let optionalRequirements: [SceneOptionalRequirement]
    /// True when the satisfied count exceeds the active profile's limit — the §3.2 refusal
    /// renders inline; nothing truncates.
    public let referencesExceedProfileLimit: Bool
    public let continuity: ContinuityContext
    /// Current ordered prompt set. This is the canonical Phase 5c handoff surface.
    public let currentSet: ScenePromptSetDetail?
    /// Compatibility projection of `currentSet.cards.first` for the old Phase 5 view.
    public let currentPrompt: ScenePromptDetail?
    /// Every `prompt_number` under the active profile, ascending.
    public let historyNumbers: [Int]

    public init(
        sceneID: UUID,
        ordinal: Int,
        heading: String,
        synopsis: String,
        creativeDirection: String = "",
        assetReadyState: SceneReadinessState,
        packageState: ScenePackageState,
        activeProfile: TargetProfile,
        plan: [ScenePlannedReference],
        optionalRequirements: [SceneOptionalRequirement],
        referencesExceedProfileLimit: Bool,
        continuity: ContinuityContext,
        currentSet: ScenePromptSetDetail? = nil,
        currentPrompt: ScenePromptDetail?,
        historyNumbers: [Int]
    ) {
        self.sceneID = sceneID
        self.ordinal = ordinal
        self.heading = heading
        self.synopsis = synopsis
        self.creativeDirection = creativeDirection
        self.assetReadyState = assetReadyState
        self.packageState = packageState
        self.activeProfile = activeProfile
        self.plan = plan
        self.optionalRequirements = optionalRequirements
        self.referencesExceedProfileLimit = referencesExceedProfileLimit
        self.continuity = continuity
        self.currentSet = currentSet
        self.currentPrompt = currentPrompt
        self.historyNumbers = historyNumbers
    }
}

// MARK: - Imported skills (§4.3, §14.6)

/// One imported custom skill's row type (§4.3) — §14.6's persistence model. Every stored
/// path is bundle- or descriptor-relative; no absolute path is ever persisted, so the
/// bundle moves and the selection survives.
public struct ImportedSkill: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let displayName: String
    /// Bundle-relative root under `skills/`; UNIQUE.
    public let relativeRoot: String
    /// Descriptor-relative entry path.
    public let entryRelativePath: String
    /// Descriptor-relative routing path; `''` when none.
    public let routingRelativePath: String
    /// The materialiser's tree digest — re-verified before every run that would use the
    /// skill (§8.6).
    public let treeSHA256: String
    public let createdAt: Date

    public init(
        id: UUID,
        projectID: UUID,
        displayName: String,
        relativeRoot: String,
        entryRelativePath: String,
        routingRelativePath: String,
        treeSHA256: String,
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.displayName = displayName
        self.relativeRoot = relativeRoot
        self.entryRelativePath = entryRelativePath
        self.routingRelativePath = routingRelativePath
        self.treeSHA256 = treeSHA256
        self.createdAt = createdAt
    }
}
