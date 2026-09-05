import Foundation
import FilmScript

// The composite values `ProjectReading` returns (PHASE1_DESIGN §4.4, §6).
//
// `StructuredRunResult` is deliberately **not** here: it is FilmBrain's type.

/// One scene with everything the scene view shows (§6).
///
/// `evidence` holds every ownerless row: synopsis evidence and evidence for scene-wide
/// continuity events. Every entity-owned row lives in exactly one `EntityDetail.evidence`,
/// so the two partition the table (Plan 006's anchor rate sums them).
public struct SceneDetail: Equatable, Sendable, Identifiable {
    public let scene: Scene
    /// Every appearance row in the scene, in role then entity-name order.
    public let appearances: [SceneEntity]
    /// The appearing entities grouped by the role they appear in.
    public let entitiesByRole: [SceneEntityRole: [Entity]]
    /// States active anywhere in this scene's ordinal span.
    public let states: [EntityState]
    /// Ownerless evidence in this scene: synopsis and scene-wide event rows.
    public let evidence: [Evidence]

    public var id: UUID { scene.id }

    public init(
        scene: Scene,
        appearances: [SceneEntity],
        entitiesByRole: [SceneEntityRole: [Entity]],
        states: [EntityState],
        evidence: [Evidence]
    ) {
        self.scene = scene
        self.appearances = appearances
        self.entitiesByRole = entitiesByRole
        self.states = states
        self.evidence = evidence
    }

    public func entities(role: SceneEntityRole) -> [Entity] { entitiesByRole[role] ?? [] }
}

/// One entity with everything the entity inspector shows (§6).
public struct EntityDetail: Equatable, Sendable, Identifiable {
    public let entity: Entity
    public let aliases: [EntityAlias]
    public let appearances: [SceneEntity]
    public let states: [EntityState]
    public let events: [ContinuityEvent]
    public let relationships: [EntityRelationship]
    /// Every evidence row whose `owner_entity_id` is this entity.
    public let evidence: [Evidence]
    /// The locks pinning this entity or one of its fields (§3.7).
    public let locks: [Lock]
    /// This entity's `asset_requirements` rows, canonical before variant (PHASE2_DESIGN
    /// §4.4). Like this shape's other collections, the inspector's list includes rejected
    /// tombstones — §5.3 and §3.7 want them visible on the entity they belong to; the
    /// **list** read (`requirementSummaries`) is the one that excludes them by default.
    public let requirements: [AssetRequirement]

    public var id: UUID { entity.id }

    public init(
        entity: Entity,
        aliases: [EntityAlias],
        appearances: [SceneEntity],
        states: [EntityState],
        events: [ContinuityEvent],
        relationships: [EntityRelationship],
        evidence: [Evidence],
        locks: [Lock],
        requirements: [AssetRequirement] = []
    ) {
        self.entity = entity
        self.aliases = aliases
        self.appearances = appearances
        self.states = states
        self.events = events
        self.relationships = relationships
        self.evidence = evidence
        self.locks = locks
        self.requirements = requirements
    }
}

/// The entity-list row shape (§6): what Plan 004 renders without a second query.
public struct EntitySummary: Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let kind: EntityKind
    public let name: String
    public let reviewState: ReviewState
    public let confidence: Double?
    public let hasUnanchoredEvidence: Bool
    /// `true` when any `locks` row names this entity.
    public let isLocked: Bool
    /// `scene_entities` rows for this entity.
    public let appearanceCount: Int

    public init(
        id: UUID,
        kind: EntityKind,
        name: String,
        reviewState: ReviewState,
        confidence: Double? = nil,
        hasUnanchoredEvidence: Bool = false,
        isLocked: Bool,
        appearanceCount: Int
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.reviewState = reviewState
        self.confidence = confidence
        self.hasUnanchoredEvidence = hasUnanchoredEvidence
        self.isLocked = isLocked
        self.appearanceCount = appearanceCount
    }
}

public struct ExtractionProtectionSummary: Codable, Equatable, Sendable {
    public let acceptedFacts: Int
    public let lockedFacts: Int

    public init(acceptedFacts: Int, lockedFacts: Int) {
        self.acceptedFacts = max(0, acceptedFacts)
        self.lockedFacts = max(0, lockedFacts)
    }
}

/// One run: a parent job plus the usage of the whole run (§3.9).
public struct RunSummary: Equatable, Sendable, Identifiable {
    public let job: Job
    /// 1-based order among this project's parent jobs, as the Jobs section numbers runs.
    public let runNumber: Int
    public let childCount: Int
    /// The whole run's usage: the aggregate over its leaf attempts that apply stored on the
    /// parent row (§8.5). Never re-summed from children, so reused attempts contribute zero.
    public let usage: JobUsage

    public var id: UUID { job.id }

    public init(job: Job, runNumber: Int, childCount: Int, usage: JobUsage) {
        self.job = job
        self.runNumber = runNumber
        self.childCount = childCount
        self.usage = usage
    }
}

/// What one `importScreenplay` wrote (Plan 003 contract B).
public struct ImportSummary: Equatable, Sendable {
    public let scriptID: UUID
    public let displayName: String
    public let format: ScreenplayFormat
    /// Where the untouched original was staged, after collision suffixing.
    public let relativePath: RelativeProjectPath
    public let sceneCount: Int
    public let sequenceCount: Int
    public let characterNames: [String]
    public let locationNames: [String]
    /// Persisted in `scripts.parse_warnings_json`; nothing else can report them.
    public let warnings: [ParseWarning]
    /// `true` when this import performed §5.5's Replace over an existing script.
    public let replacedPreviousScript: Bool

    public var characterCount: Int { characterNames.count }
    public var locationCount: Int { locationNames.count }

    public init(
        scriptID: UUID,
        displayName: String,
        format: ScreenplayFormat,
        relativePath: RelativeProjectPath,
        sceneCount: Int,
        sequenceCount: Int,
        characterNames: [String],
        locationNames: [String],
        warnings: [ParseWarning],
        replacedPreviousScript: Bool
    ) {
        self.scriptID = scriptID
        self.displayName = displayName
        self.format = format
        self.relativePath = relativePath
        self.sceneCount = sceneCount
        self.sequenceCount = sequenceCount
        self.characterNames = characterNames
        self.locationNames = locationNames
        self.warnings = warnings
        self.replacedPreviousScript = replacedPreviousScript
    }
}

/// The areas one committed transaction touched (§3.9a).
///
/// The element of `ProjectObserving.changes()` is only this set — consumers always
/// refetch, so a coalesced duplicate is harmless.
public struct ProjectChange: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let script = ProjectChange(rawValue: 1 << 0)
    public static let scenes = ProjectChange(rawValue: 1 << 1)
    public static let entities = ProjectChange(rawValue: 1 << 2)
    public static let jobs = ProjectChange(rawValue: 1 << 3)
    public static let journal = ProjectChange(rawValue: 1 << 4)
    public static let locks = ProjectChange(rawValue: 1 << 5)
    /// The manifest's requirement graph: requirements, their scene links, basis rows,
    /// dependencies, and the template (PHASE2_DESIGN §7.5).
    public static let requirements = ProjectChange(rawValue: 1 << 6)
    /// Media slots and their versions (§7.5).
    public static let assets = ProjectChange(rawValue: 1 << 7)

    public static let all: ProjectChange = [
        .script, .scenes, .entities, .jobs, .journal, .locks, .requirements, .assets,
    ]
}
