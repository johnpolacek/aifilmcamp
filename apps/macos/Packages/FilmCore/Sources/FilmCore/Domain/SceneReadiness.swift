import Foundation

/// PHASE4_DESIGN §4.4's Phase 4a types: the readiness snapshot and its rows.
///
/// Everything here is **derived only, never stored** (§3.1): one `readinessGraph` load,
/// one derivation function, and the summary is a fold of the per-scene rows — never a
/// second query (§3.3's consistency rule). `SceneReadinessState`'s raw values are frozen
/// strings; §8.2's rendered input cites them, so a rename is a design change.

/// §6.1's three pinned scene states (`docs/OVERVIEW.md#asset-states`), activated as
/// derived values. There is no fourth state: §3.4's edge cases resolve inside these three.
public enum SceneReadinessState: String, Codable, Equatable, Sendable {
    case blocked
    case partial
    case assetReady = "asset_ready"
}

/// The render-ready pointer minted because the snapshot is the UI's only source (§4.4):
/// a bare UUID cannot be a displayed value, and no surface may issue a per-row query.
public struct RequirementReference: Equatable, Hashable, Sendable, Identifiable {
    public let requirementID: UUID
    public let entityName: String
    public let requirementName: String

    /// The display convention joins the two names ("SARAH — BLUE SWEATER").
    public var displayName: String { "\(entityName) — \(requirementName)" }

    public var id: UUID { requirementID }

    public init(requirementID: UUID, entityName: String, requirementName: String) {
        self.requirementID = requirementID
        self.entityName = entityName
        self.requirementName = requirementName
    }
}

/// One counted-but-not-ready row of a scene checklist — the `MissingAsset` shape at scene
/// scope with `blockedBy` upgraded to references (owner-review finding, 2026-08-23), each
/// ordered by the dependency edge's `created_at` then edge id, total and stable.
public struct SceneMissingRequirement: Equatable, Identifiable, Sendable {
    public let requirementID: UUID
    public let entityName: String
    public let requirementName: String
    public let tier: AssetRequirementTier
    public let necessity: RequirementNecessity
    public let displayStatus: AssetStatus
    public let isBlocked: Bool
    public let blockedBy: [RequirementReference]

    public var id: UUID { requirementID }

    public init(
        requirementID: UUID,
        entityName: String,
        requirementName: String,
        tier: AssetRequirementTier,
        necessity: RequirementNecessity,
        displayStatus: AssetStatus,
        isBlocked: Bool,
        blockedBy: [RequirementReference]
    ) {
        self.requirementID = requirementID
        self.entityName = entityName
        self.requirementName = requirementName
        self.tier = tier
        self.necessity = necessity
        self.displayStatus = displayStatus
        self.isBlocked = isBlocked
        self.blockedBy = blockedBy
    }
}

/// The shown-never-counted row (§3.4, §14.5). Its fields are frozen (owner-review
/// finding, 2026-08-23) — enough to render and deep-link without a second query.
public struct SceneOptionalRequirement: Equatable, Identifiable, Sendable {
    public let requirementID: UUID
    public let entityName: String
    public let requirementName: String
    public let tier: AssetRequirementTier
    public let displayStatus: AssetStatus
    public let hasUnreviewedFacts: Bool

    public var id: UUID { requirementID }

    public init(
        requirementID: UUID,
        entityName: String,
        requirementName: String,
        tier: AssetRequirementTier,
        displayStatus: AssetStatus,
        hasUnreviewedFacts: Bool
    ) {
        self.requirementID = requirementID
        self.entityName = entityName
        self.requirementName = requirementName
        self.tier = tier
        self.displayStatus = displayStatus
        self.hasUnreviewedFacts = hasUnreviewedFacts
    }
}

/// One scene's readiness row (§4.4). `state` is reserved for scenes that can be produced;
/// an excluded scene (`isExcluded`: omitted or the preamble) still lists, still shows any
/// checklist rows it has, and joins no counter except the summary's `excluded` figure.
public struct SceneReadiness: Equatable, Identifiable, Sendable {
    public let sceneID: UUID
    public let ordinal: Int
    public let heading: String
    public let isOmitted: Bool
    public let isExcluded: Bool
    public let state: SceneReadinessState
    public let requiredCount: Int
    public let readyCount: Int
    public let missing: [SceneMissingRequirement]
    public let optionalRequirements: [SceneOptionalRequirement]
    public let hasUnreviewedFacts: Bool

    public var id: UUID { sceneID }

    public init(
        sceneID: UUID,
        ordinal: Int,
        heading: String,
        isOmitted: Bool,
        isExcluded: Bool,
        state: SceneReadinessState,
        requiredCount: Int,
        readyCount: Int,
        missing: [SceneMissingRequirement],
        optionalRequirements: [SceneOptionalRequirement],
        hasUnreviewedFacts: Bool
    ) {
        self.sceneID = sceneID
        self.ordinal = ordinal
        self.heading = heading
        self.isOmitted = isOmitted
        self.isExcluded = isExcluded
        self.state = state
        self.requiredCount = requiredCount
        self.readyCount = readyCount
        self.missing = missing
        self.optionalRequirements = optionalRequirements
        self.hasUnreviewedFacts = hasUnreviewedFacts
    }
}

/// The fold of the per-scene rows (§3.3/§4.4). The invariant
/// `assetReady + partial + blocked + excluded == sceneTotal` holds on every read; the
/// asset figures ride the same graph in the `ManifestCounts` frame — active requirements,
/// all necessities — because this line is manifest completion, not scene gating (§5.3).
public struct ReadinessSummary: Equatable, Sendable {
    public let assetReady: Int
    public let partial: Int
    public let blocked: Int
    public let excluded: Int
    public let sceneTotal: Int
    public let requirementsApproved: Int
    public let requirementsTotal: Int
    public let hasUnreviewedFacts: Bool

    public init(
        assetReady: Int,
        partial: Int,
        blocked: Int,
        excluded: Int,
        sceneTotal: Int,
        requirementsApproved: Int,
        requirementsTotal: Int,
        hasUnreviewedFacts: Bool
    ) {
        self.assetReady = assetReady
        self.partial = partial
        self.blocked = blocked
        self.excluded = excluded
        self.sceneTotal = sceneTotal
        self.requirementsApproved = requirementsApproved
        self.requirementsTotal = requirementsTotal
        self.hasUnreviewedFacts = hasUnreviewedFacts
    }
}

/// §3.5's deterministic impact figures for one Missing requirement. The name of the
/// second figure is the claim, and under §14.1's sole-unsatisfied rule the claim is
/// literal: a dependent waiting on two blockers counts for neither until one remains.
public struct UnblockerImpact: Equatable, Identifiable, Sendable {
    public let requirementID: UUID
    public let entityName: String
    public let requirementName: String
    public let tier: AssetRequirementTier
    public let unfinishedSceneCount: Int
    public let unfinishedSceneIDs: [UUID]
    public let unblocksRequirementCount: Int

    public var id: UUID { requirementID }

    public init(
        requirementID: UUID,
        entityName: String,
        requirementName: String,
        tier: AssetRequirementTier,
        unfinishedSceneCount: Int,
        unfinishedSceneIDs: [UUID],
        unblocksRequirementCount: Int
    ) {
        self.requirementID = requirementID
        self.entityName = entityName
        self.requirementName = requirementName
        self.tier = tier
        self.unfinishedSceneCount = unfinishedSceneCount
        self.unfinishedSceneIDs = unfinishedSceneIDs
        self.unblocksRequirementCount = unblocksRequirementCount
    }
}

/// One read, one transaction, one derivation (§3.3's consistency rule made a type):
/// per-scene rows in ordinal order, the summary fold, and §3.5's full ranking — every
/// future surface reads this, never a second query.
public struct ReadinessSnapshot: Equatable, Sendable {
    public let scenes: [SceneReadiness]
    public let summary: ReadinessSummary
    public let impacts: [UnblockerImpact]

    public init(
        scenes: [SceneReadiness],
        summary: ReadinessSummary,
        impacts: [UnblockerImpact]
    ) {
        self.scenes = scenes
        self.summary = summary
        self.impacts = impacts
    }
}
