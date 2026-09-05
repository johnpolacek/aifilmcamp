import Foundation

/// The one polymorphic entity kind column (PHASE1_DESIGN §3.4).
public enum EntityKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case character
    case location
    case prop
    case vehicle
    case creature
    case object
}

/// Whether an entity takes part in the asset manifest (PHASE2_DESIGN §3.3, §3.4, §4.3).
///
/// `automatic` leaves §3.3's 2+ rule in charge; `always` forces the entity into the pool
/// (the only way a prop qualifies without an inference run, §3.4); `never` keeps it out.
/// Neither override deactivates existing requirement rows — they badge them (§5.3, §6.4).
public enum ManifestInclusion: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case automatic
    case always
    case never
}

/// A character, location, prop, … row (§3.4, §4.3).
public struct Entity: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let kind: EntityKind
    /// Display name (`FilmScript.DisplayCase` for parser rows).
    public let name: String
    /// `EntityNormalization.normalize(name)`.
    public let nameNormalized: String
    public let description: String
    /// Locations only; a cycle guard lives in Swift.
    public let parentID: UUID?
    public let isRelevant: Bool
    /// `entities.manifest_inclusion` (PHASE2_DESIGN §4.2 step 1). Defaulted here so Phase 1
    /// call sites that predate the column keep compiling; the column's own default is
    /// `'automatic'` too, so a row written without it round-trips.
    public let manifestInclusion: ManifestInclusion
    public let provenance: Provenance

    public init(
        id: UUID,
        projectID: UUID,
        kind: EntityKind,
        name: String,
        nameNormalized: String,
        description: String,
        parentID: UUID?,
        isRelevant: Bool,
        manifestInclusion: ManifestInclusion = .automatic,
        provenance: Provenance
    ) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.name = name
        self.nameNormalized = nameNormalized
        self.description = description
        self.parentID = parentID
        self.isRelevant = isRelevant
        self.manifestInclusion = manifestInclusion
        self.provenance = provenance
    }
}

/// Where an alias came from (§3.5). `cue` aliases are peeled by `CueNormalizer` first.
public enum AliasKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case cue
    case heading
    case mention
    case human
}

/// One surface form that maps to an entity (§3.5).
///
/// `normalized` is always `EntityNormalization.normalize(…)`, and
/// `UNIQUE(project_id, kind, normalized)` makes alias lookup a function.
public struct EntityAlias: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let entityID: UUID
    public let projectID: UUID
    /// Denormalized copy of the entity's kind, kept in sync by reclassify/merge.
    public let kind: EntityKind
    public let alias: String
    public let normalized: String
    public let aliasKind: AliasKind
    public let provenance: Provenance

    public init(
        id: UUID,
        entityID: UUID,
        projectID: UUID,
        kind: EntityKind,
        alias: String,
        normalized: String,
        aliasKind: AliasKind,
        provenance: Provenance
    ) {
        self.id = id
        self.entityID = entityID
        self.projectID = projectID
        self.kind = kind
        self.alias = alias
        self.normalized = normalized
        self.aliasKind = aliasKind
        self.provenance = provenance
    }
}
