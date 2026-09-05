import Foundation

// The composite values the §7.6 manifest reads return (PHASE2_DESIGN §4.4, §6.1, §6.4).
//
// Every derived field here — `isActive`, `isMissing`, `isBlocked`, `displayStatus`, the
// drift badges — is computed at read time from `ManifestQualification` plus the stored rows.
// None of it is a column, and nothing but the read layer produces these values.

/// The drift between §3.3's rule (and the template) and the rows that exist (§5.3).
///
/// Read-layer facts, never stored: the rule proposes, the filmmaker disposes, so **neither
/// the rule nor the template ever deletes a requirement row** — the reads badge them
/// instead. The entity-level "qualifies but has no canonical set" badge is *not* here
/// because it names an entity with no requirement row to hang a flag on; it rides on
/// `ManifestSummary.entitiesMissingCanonicalSet`.
public struct RequirementDrift: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    /// A canonical row whose entity no longer qualifies under §3.3 — "no longer qualifies
    /// (appears in 1 scene)". Never set when the cause is a `never` override; that is
    /// `suppressed`.
    public static let noLongerQualifies = RequirementDrift(rawValue: 1 << 0)
    /// A canonical row whose entity carries `manifest_inclusion = 'never'` — "suppressed".
    public static let suppressed = RequirementDrift(rawValue: 1 << 1)
    /// A canonical row whose template entry is disabled — "template entry disabled".
    public static let templateEntryDisabled = RequirementDrift(rawValue: 1 << 2)
}

/// An entity that qualifies under §3.3 but is missing at least one canonical slot its
/// kind's enabled template entries call for — §5.3's "qualifies but has no canonical set —
/// Build to add".
///
/// A slot already filled by *any* row, tombstone included, is not missing: Build respects a
/// rejected row and skips it (§5.2), so badging it would ask for a Build that does nothing.
public struct QualifyingEntity: Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let kind: EntityKind
    public let name: String
    /// The `asset_requirement_types.code` values with no requirement row for this entity.
    public let missingTemplateCodes: [String]

    public init(id: UUID, kind: EntityKind, name: String, missingTemplateCodes: [String]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.missingTemplateCodes = missingTemplateCodes
    }
}

/// The requirement-list row shape (§4.4): what the manifest list renders without a second
/// query.
public struct RequirementSummary: Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let entityID: UUID
    public let entityKind: EntityKind
    /// The entity's display name; the UI renders "Sarah — Office Outfit" by joining it with
    /// `name`, which never embeds the entity (§4.3).
    public let entityName: String
    public let tier: AssetRequirementTier
    /// The template entry this canonical slot fills; `nil` for a variant.
    public let typeID: UUID?
    /// That entry's frozen `code`; `nil` for a variant.
    public let typeCode: String?
    public let name: String
    public let necessity: RequirementNecessity
    /// The requirement's own review lifecycle (§6.1: orthogonal to the asset state).
    public let reviewState: ReviewState
    /// §6.4's single predicate.
    public let isActive: Bool
    /// §6.1's display state: the asset's `status`, or `needed` when there is no asset row.
    public let displayStatus: AssetStatus
    /// §6.2's orthogonal flag: an Approved asset that is stale is still Approved.
    public let isStale: Bool
    /// §6.4's Missing: active, `required`, and the asset is absent or not Approved.
    public let isMissing: Bool
    /// §6.4's Blocked — a subset of Missing.
    public let isBlocked: Bool
    /// `true` when any `locks` row names this requirement.
    public let isLocked: Bool
    /// §3.7's "based on unreviewed AI facts": the entity, or any basis row's underlying
    /// fact, is still `proposed`.
    public let hasUnreviewedFacts: Bool
    /// How many scenes this requirement is required by — derived from `scene_entities` for
    /// a canonical row, the stored links for a variant (§5.2).
    public let requiredBySceneCount: Int
    /// §5.3's badges, as read-layer facts.
    public let drift: RequirementDrift

    public init(
        id: UUID,
        entityID: UUID,
        entityKind: EntityKind,
        entityName: String,
        tier: AssetRequirementTier,
        typeID: UUID?,
        typeCode: String?,
        name: String,
        necessity: RequirementNecessity,
        reviewState: ReviewState,
        isActive: Bool,
        displayStatus: AssetStatus,
        isStale: Bool,
        isMissing: Bool,
        isBlocked: Bool,
        isLocked: Bool,
        hasUnreviewedFacts: Bool,
        requiredBySceneCount: Int,
        drift: RequirementDrift
    ) {
        self.id = id
        self.entityID = entityID
        self.entityKind = entityKind
        self.entityName = entityName
        self.tier = tier
        self.typeID = typeID
        self.typeCode = typeCode
        self.name = name
        self.necessity = necessity
        self.reviewState = reviewState
        self.isActive = isActive
        self.displayStatus = displayStatus
        self.isStale = isStale
        self.isMissing = isMissing
        self.isBlocked = isBlocked
        self.isLocked = isLocked
        self.hasUnreviewedFacts = hasUnreviewedFacts
        self.requiredBySceneCount = requiredBySceneCount
        self.drift = drift
    }
}

/// One basis citation with the fact it cites (§3.6, §3.7, §7.6).
///
/// A basis row is an immutable citation, not a reviewable fact — but the fact it names
/// **is** reviewable, and its review state is what §3.7's unreviewed-facts flag reads.
public struct RequirementBasisDetail: Equatable, Sendable, Identifiable {
    public let basis: AssetRequirementBasis
    /// The cited fact's own `review_state`; `nil` when the fact row is gone (basis rows
    /// carry no foreign key — §4.3).
    public let factReviewState: ReviewState?
    /// The cited fact's evidence rows, joined on `(subject_kind, subject_id)`.
    public let evidence: [Evidence]

    public var id: UUID { basis.id }

    public init(
        basis: AssetRequirementBasis,
        factReviewState: ReviewState?,
        evidence: [Evidence]
    ) {
        self.basis = basis
        self.factReviewState = factReviewState
        self.evidence = evidence
    }
}

/// One edge of the dependency graph, from the inspected requirement's point of view (§3.5).
public struct RequirementDependencyEdge: Equatable, Sendable, Identifiable {
    public let dependency: AssetDependency
    /// The requirement at the *other* end: the target for a `dependsOn` edge, the dependent
    /// for a `dependents` edge.
    public let otherRequirementID: UUID
    public let otherRequirementName: String
    public let otherEntityName: String
    /// §6.4's predicate over the other end.
    public let isOtherActive: Bool
    /// §3.5: satisfied when the **target** has an Approved asset version or is inactive.
    /// On a `dependents` edge this reports the inspected requirement's own satisfaction of
    /// that edge, so the field means the same thing in both directions.
    public let isSatisfied: Bool

    public var id: UUID { dependency.id }

    public init(
        dependency: AssetDependency,
        otherRequirementID: UUID,
        otherRequirementName: String,
        otherEntityName: String,
        isOtherActive: Bool,
        isSatisfied: Bool
    ) {
        self.dependency = dependency
        self.otherRequirementID = otherRequirementID
        self.otherRequirementName = otherRequirementName
        self.otherEntityName = otherEntityName
        self.isOtherActive = isOtherActive
        self.isSatisfied = isSatisfied
    }
}

/// One requirement with everything the inspector shows (§4.4, §7.6).
public struct RequirementDetail: Equatable, Sendable, Identifiable {
    public var referenceTypeCode: String? {
        requirement.outfitSourceVersionID == nil ? type?.code : "full_body"
    }

    public let requirement: AssetRequirement
    public let entity: Entity
    /// The template entry a canonical row fills; `nil` for a variant.
    public let type: AssetRequirementType?
    /// The scenes this requirement is required by, in scene order — **derived** from
    /// `scene_entities` for a canonical row, the stored `asset_requirement_scenes` rows for
    /// a variant (§5.2).
    public let requiredBy: [Scene]
    public let basis: [RequirementBasisDetail]
    /// Edges this requirement depends on.
    public let dependsOn: [RequirementDependencyEdge]
    /// Edges that depend on this requirement.
    public let dependents: [RequirementDependencyEdge]
    /// The media slot, when one exists; `nil` reads as Needed (§6.1).
    public let asset: Asset?
    /// The slot's versions, by `version_number`.
    public let versions: [AssetVersion]
    /// The locks pinning this requirement or one of its fields (§7.5).
    public let locks: [Lock]
    public let isActive: Bool
    public let isMissing: Bool
    public let isBlocked: Bool
    public let displayStatus: AssetStatus
    public let isStale: Bool
    public let hasUnreviewedFacts: Bool
    public let drift: RequirementDrift

    // MARK: PHASE3_DESIGN §3.3, §3.4, §4.4 (Plan 013 contract C)

    /// The unsatisfied **active** dependencies, in §3.3's order — the generation gate.
    /// Deliberately not the Missing-qualified `isBlocked` above (§3.3 records why).
    public let generationBlockedBy: [UUID]
    /// §3.3's planned dependencies whole — every active edge, satisfied or not, each with
    /// its derived class/attributes; the satisfied rows' non-nil designators are the
    /// rendered references' dense `@Image 1…N`.
    public let plannedDependencies: [PlannedDependency]
    /// The current prompt (§3.2: highest `prompt_number`), derived, with its citations
    /// and derived `isStale`; `nil` when the requirement has no prompts.
    public let currentPrompt: AssetPromptDetail?
    /// How many prompt rows exist, current and history alike.
    public let promptCount: Int
    /// The §6.1 marker, when set (`markAssetInProgress`, Plan 014).
    public let inProgressSince: Date?
    /// Human edits active through current approved image lineage. Character-bundle
    /// amendments from canonical siblings are included; archived branches are not.
    public let visualAmendments: [ReferenceVisualAmendment]

    /// Derived from `generationBlockedBy` — never stored.
    public var isGenerationBlocked: Bool { !generationBlockedBy.isEmpty }

    public var id: UUID { requirement.id }

    public init(
        requirement: AssetRequirement,
        entity: Entity,
        type: AssetRequirementType?,
        requiredBy: [Scene],
        basis: [RequirementBasisDetail],
        dependsOn: [RequirementDependencyEdge],
        dependents: [RequirementDependencyEdge],
        asset: Asset?,
        versions: [AssetVersion],
        locks: [Lock],
        isActive: Bool,
        isMissing: Bool,
        isBlocked: Bool,
        displayStatus: AssetStatus,
        isStale: Bool,
        hasUnreviewedFacts: Bool,
        drift: RequirementDrift,
        generationBlockedBy: [UUID] = [],
        plannedDependencies: [PlannedDependency] = [],
        currentPrompt: AssetPromptDetail? = nil,
        promptCount: Int = 0,
        inProgressSince: Date? = nil,
        visualAmendments: [ReferenceVisualAmendment] = []
    ) {
        self.requirement = requirement
        self.entity = entity
        self.type = type
        self.requiredBy = requiredBy
        self.basis = basis
        self.dependsOn = dependsOn
        self.dependents = dependents
        self.asset = asset
        self.versions = versions
        self.locks = locks
        self.isActive = isActive
        self.isMissing = isMissing
        self.isBlocked = isBlocked
        self.displayStatus = displayStatus
        self.isStale = isStale
        self.hasUnreviewedFacts = hasUnreviewedFacts
        self.drift = drift
        self.generationBlockedBy = generationBlockedBy
        self.plannedDependencies = plannedDependencies
        self.currentPrompt = currentPrompt
        self.promptCount = promptCount
        self.inProgressSince = inProgressSince
        self.visualAmendments = visualAmendments
    }
}

/// §6.4's counts, over the **active** requirements of one slice (a kind, or the project).
///
/// Every count here is a count of *requirements*, never of assets: a requirement with no
/// asset row is Needed, not absent (§6.1).
public struct ManifestCounts: Equatable, Hashable, Sendable {
    /// Active canonical requirements.
    public let canonical: Int
    /// Active variant requirements.
    public let variant: Int
    /// Active requirements whose asset is Approved.
    public let approved: Int
    /// Active requirements whose asset is Needs Review.
    public let needsReview: Int
    /// §6.4's Missing.
    public let missing: Int
    /// §6.4's Blocked — a subset of `missing`.
    public let blocked: Int
    /// §6.4's Stale: Approved and `is_stale = 1`.
    public let stale: Int
    /// Active requirements with `necessity = 'optional'` — reported separately, never
    /// counted as Missing.
    public let optional: Int

    /// Active requirements, both tiers.
    public var total: Int { canonical + variant }

    public init(
        canonical: Int = 0,
        variant: Int = 0,
        approved: Int = 0,
        needsReview: Int = 0,
        missing: Int = 0,
        blocked: Int = 0,
        stale: Int = 0,
        optional: Int = 0
    ) {
        self.canonical = canonical
        self.variant = variant
        self.approved = approved
        self.needsReview = needsReview
        self.missing = missing
        self.blocked = blocked
        self.stale = stale
        self.optional = optional
    }
}

/// The dashboard numbers of §6.4, per kind and overall, plus §5.3's entity-level badge.
public struct ManifestSummary: Equatable, Sendable {
    public let overall: ManifestCounts
    /// Only the kinds with at least one active requirement appear.
    public let byKind: [EntityKind: ManifestCounts]
    /// §5.3: entities that qualify under §3.3 but lack a canonical slot an enabled template
    /// entry calls for — "Build to add". In entity kind then name order.
    public let entitiesMissingCanonicalSet: [QualifyingEntity]

    public init(
        overall: ManifestCounts,
        byKind: [EntityKind: ManifestCounts],
        entitiesMissingCanonicalSet: [QualifyingEntity]
    ) {
        self.overall = overall
        self.byKind = byKind
        self.entitiesMissingCanonicalSet = entitiesMissingCanonicalSet
    }
}

/// One "what is still missing?" row (§4.4, §6.4).
///
/// `missingAssets()` returns these in the creation order §6.4 asks for: canonical
/// requirements first, then variants in dependency order.
public struct MissingAsset: Equatable, Hashable, Sendable, Identifiable {
    public let requirementID: UUID
    public let entityID: UUID
    public let entityKind: EntityKind
    public let entityName: String
    public let tier: AssetRequirementTier
    public let requirementName: String
    /// §6.1's display state — `needed`, `needs_review`, `rejected`, … never `approved`.
    public let displayStatus: AssetStatus
    public let isBlocked: Bool
    /// The requirement ids of the unsatisfied dependencies, when blocked.
    public let blockedBy: [UUID]

    public var id: UUID { requirementID }

    public init(
        requirementID: UUID,
        entityID: UUID,
        entityKind: EntityKind,
        entityName: String,
        tier: AssetRequirementTier,
        requirementName: String,
        displayStatus: AssetStatus,
        isBlocked: Bool,
        blockedBy: [UUID]
    ) {
        self.requirementID = requirementID
        self.entityID = entityID
        self.entityKind = entityKind
        self.entityName = entityName
        self.tier = tier
        self.requirementName = requirementName
        self.displayStatus = displayStatus
        self.isBlocked = isBlocked
        self.blockedBy = blockedBy
    }
}
