import Foundation

/// How two entities relate (PHASE1_DESIGN §4.3).
public enum RelationshipKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case family
    case romantic
    case professional
    case adversarial
    case possession
    case other
}

/// A directed relationship between two entities.
public struct EntityRelationship: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let fromEntityID: UUID
    public let toEntityID: UUID
    public let kind: RelationshipKind
    public let description: String
    public let provenance: Provenance

    public init(
        id: UUID,
        fromEntityID: UUID,
        toEntityID: UUID,
        kind: RelationshipKind,
        description: String,
        provenance: Provenance
    ) {
        self.id = id
        self.fromEntityID = fromEntityID
        self.toEntityID = toEntityID
        self.kind = kind
        self.description = description
        self.provenance = provenance
    }
}
