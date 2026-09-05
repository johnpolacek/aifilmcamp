import Foundation

/// Which tier a requirement belongs to (PHASE2_DESIGN §3.2, §4.3).
///
/// `canonical` rows come from the per-project template (one slot per template entry,
/// `type_id` non-NULL); `variant` rows are scene-specific and carry no template entry.
/// The column is immutable after creation — no operation edits `tier` or `type_id`.
public enum AssetRequirementTier: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case canonical
    case variant
}

/// How much a requirement is needed (§4.3, §6.4).
///
/// `notNeeded` deactivates the requirement (§6.4's predicate) and deprecates its asset
/// (§6.3 rule 1); `optional` rows stay active but are reported separately.
public enum RequirementNecessity: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case required
    case optional
    case notNeeded = "not_needed"
}

/// One `asset_requirements` row (§4.3, §4.4).
///
/// `name` never embeds the entity — the UI renders "Sarah — Office Outfit" by joining the
/// entity's name with this one — and `nameNormalized` is
/// `EntityNormalization.normalize(name)`, unique per entity **across tiers**.
public struct AssetRequirement: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let entityID: UUID
    public let tier: AssetRequirementTier
    /// The template entry this canonical slot fills; `nil` exactly for a variant (§4.3's
    /// `CHECK ((tier = 'canonical') = (type_id IS NOT NULL))`).
    public let typeID: UUID?
    public let name: String
    public let nameNormalized: String
    /// Why the requirement exists, in prose; empty for a template-computed canonical row.
    public let reason: String
    public let necessity: RequirementNecessity
    public let provenance: Provenance
    /// Immutable source of a named character outfit; nil for ordinary requirements.
    public let outfitSourceVersionID: UUID?

    public init(
        id: UUID,
        projectID: UUID,
        entityID: UUID,
        tier: AssetRequirementTier,
        typeID: UUID?,
        name: String,
        nameNormalized: String,
        reason: String,
        necessity: RequirementNecessity,
        provenance: Provenance,
        outfitSourceVersionID: UUID? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.entityID = entityID
        self.tier = tier
        self.typeID = typeID
        self.name = name
        self.nameNormalized = nameNormalized
        self.reason = reason
        self.necessity = necessity
        self.provenance = provenance
        self.outfitSourceVersionID = outfitSourceVersionID
    }
}

/// One `asset_requirement_scenes` row: a **variant** requirement's stored scene link
/// (§4.3, §5.2 — a canonical requirement's scenes are derived from `scene_entities`, never
/// stored).
public struct AssetRequirementScene: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let requirementID: UUID
    public let sceneID: UUID
    public let provenance: Provenance

    public init(id: UUID, requirementID: UUID, sceneID: UUID, provenance: Provenance) {
        self.id = id
        self.requirementID = requirementID
        self.sceneID = sceneID
        self.provenance = provenance
    }
}

/// One `asset_requirement_basis` row: the fact that justifies a requirement (§3.6, §4.3).
///
/// An **immutable citation** with reduced provenance, like `evidence`: created with its
/// requirement, never edited, removed with it, and excluded from review (§3.7). Its
/// `subjectKind` is `state`, `event`, or `appearance` — enforced by the table's `CHECK` —
/// and `subjectID` carries no foreign key, so the operations that delete or merge facts
/// sweep matching rows themselves (§4.3's deleted-row policy).
public struct AssetRequirementBasis: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let requirementID: UUID
    public let subjectKind: SubjectKind
    public let subjectID: UUID
    public let source: FactSource
    public let jobID: UUID?
    public let createdAt: Date

    /// The three kinds `asset_requirement_basis.subject_kind`'s `CHECK` admits (§4.3).
    public static let citableKinds: Set<SubjectKind> = [.state, .event, .appearance]

    public init(
        id: UUID,
        requirementID: UUID,
        subjectKind: SubjectKind,
        subjectID: UUID,
        source: FactSource,
        jobID: UUID?,
        createdAt: Date
    ) {
        self.id = id
        self.requirementID = requirementID
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.source = source
        self.jobID = jobID
        self.createdAt = createdAt
    }
}

/// One `asset_dependencies` row: "this requirement's media derives from that one's"
/// (§3.5, §4.3).
///
/// A dependency is satisfied when its target has an Approved asset **or** the target is
/// inactive under §6.4's predicate; an unsatisfied dependency on a missing requirement is
/// what makes it Blocked.
public struct AssetDependency: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let requirementID: UUID
    public let dependsOnRequirementID: UUID
    public let provenance: Provenance

    public init(
        id: UUID,
        requirementID: UUID,
        dependsOnRequirementID: UUID,
        provenance: Provenance
    ) {
        self.id = id
        self.requirementID = requirementID
        self.dependsOnRequirementID = dependsOnRequirementID
        self.provenance = provenance
    }
}
