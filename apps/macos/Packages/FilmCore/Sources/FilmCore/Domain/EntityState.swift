import Foundation

/// The continuity categories a state may fall in (PHASE1_DESIGN §4.3).
public enum StateCategory: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case wardrobe
    case hair
    case makeup
    case injury
    case age
    case condition
    case possession
    case timeOfDay = "time_of_day"
    case weather
    case lighting
    case damage
    case other
}

/// A state an entity holds over a span of scenes.
public struct EntityState: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let entityID: UUID
    public let category: StateCategory
    public let description: String
    public let startSceneID: UUID
    /// `nil` means the state is still active at the end of the script.
    public let endSceneID: UUID?
    public let provenance: Provenance

    public init(
        id: UUID,
        entityID: UUID,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID?,
        provenance: Provenance
    ) {
        self.id = id
        self.entityID = entityID
        self.category = category
        self.description = description
        self.startSceneID = startSceneID
        self.endSceneID = endSceneID
        self.provenance = provenance
    }
}

/// Something that happens in a scene and may result in a state (§4.3).
public struct ContinuityEvent: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let sceneID: UUID
    /// Nullable: a scene-wide event belongs to no single entity.
    public let entityID: UUID?
    public let description: String
    public let resultingStateID: UUID?
    public let provenance: Provenance

    public init(
        id: UUID,
        sceneID: UUID,
        entityID: UUID?,
        description: String,
        resultingStateID: UUID?,
        provenance: Provenance
    ) {
        self.id = id
        self.sceneID = sceneID
        self.entityID = entityID
        self.description = description
        self.resultingStateID = resultingStateID
        self.provenance = provenance
    }
}
