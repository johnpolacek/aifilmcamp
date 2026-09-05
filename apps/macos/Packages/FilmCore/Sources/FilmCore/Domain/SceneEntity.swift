import Foundation

/// How an entity appears in a scene (PHASE1_DESIGN §4.3). The parser produces
/// `speaking` and `setting` authoritatively; the rest are AI/human work.
public enum SceneEntityRole: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case speaking
    case present
    case mentioned
    case setting
    case used
}

/// One appearance of an entity in a scene.
public struct SceneEntity: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let sceneID: UUID
    public let entityID: UUID
    public let role: SceneEntityRole
    /// The alias that produced this appearance — the lookup a later split uses (§3.5).
    public let matchedAliasID: UUID?
    public let provenance: Provenance

    public init(
        id: UUID,
        sceneID: UUID,
        entityID: UUID,
        role: SceneEntityRole,
        matchedAliasID: UUID?,
        provenance: Provenance
    ) {
        self.id = id
        self.sceneID = sceneID
        self.entityID = entityID
        self.role = role
        self.matchedAliasID = matchedAliasID
        self.provenance = provenance
    }
}
