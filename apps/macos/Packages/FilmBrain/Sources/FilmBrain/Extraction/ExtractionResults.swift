import FilmCore
import Foundation

public struct ExtractChunkResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let scenes: [ExtractedScene]

    public init(schemaVersion: Int = 1, scenes: [ExtractedScene]) {
        self.schemaVersion = schemaVersion
        self.scenes = scenes
    }
}

public struct ExtractedScene: Codable, Equatable, Sendable {
    public let sceneId: UUID
    public let sceneOrdinal: Int
    public let synopsis: ExtractedSynopsis
    public let entities: [ExtractedEntity]
    public let states: [ExtractedState]
    public let events: [ExtractedEvent]
    public let relationships: [ExtractedRelationship]

    public init(
        sceneId: UUID,
        sceneOrdinal: Int,
        synopsis: ExtractedSynopsis,
        entities: [ExtractedEntity],
        states: [ExtractedState],
        events: [ExtractedEvent],
        relationships: [ExtractedRelationship]
    ) {
        self.sceneId = sceneId
        self.sceneOrdinal = sceneOrdinal
        self.synopsis = synopsis
        self.entities = entities
        self.states = states
        self.events = events
        self.relationships = relationships
    }
}

public struct ExtractedSynopsis: Codable, Equatable, Sendable {
    public let text: String
    public let evidenceQuote: String
    public let confidence: Double

    public init(text: String, evidenceQuote: String, confidence: Double) {
        self.text = text
        self.evidenceQuote = evidenceQuote
        self.confidence = confidence
    }
}

public struct ExtractedEntity: Codable, Equatable, Sendable {
    public let kind: EntityKind
    public let name: String
    public let aliasesInScene: [String]
    public let role: SceneEntityRole
    public let description: String
    public let evidenceQuote: String
    public let confidence: Double

    public init(
        kind: EntityKind,
        name: String,
        aliasesInScene: [String],
        role: SceneEntityRole,
        description: String,
        evidenceQuote: String,
        confidence: Double
    ) {
        self.kind = kind
        self.name = name
        self.aliasesInScene = aliasesInScene
        self.role = role
        self.description = description
        self.evidenceQuote = evidenceQuote
        self.confidence = confidence
    }
}

public struct ExtractedState: Codable, Equatable, Sendable {
    public let entityName: String
    public let category: StateCategory
    public let description: String
    public let evidenceQuote: String
    public let confidence: Double

    public init(entityName: String, category: StateCategory, description: String, evidenceQuote: String, confidence: Double) {
        self.entityName = entityName
        self.category = category
        self.description = description
        self.evidenceQuote = evidenceQuote
        self.confidence = confidence
    }
}

public struct ExtractedEvent: Codable, Equatable, Sendable {
    public let entityName: String?
    public let description: String
    public let evidenceQuote: String
    public let confidence: Double

    public init(entityName: String?, description: String, evidenceQuote: String, confidence: Double) {
        self.entityName = entityName
        self.description = description
        self.evidenceQuote = evidenceQuote
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case entityName, description, evidenceQuote, confidence
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let entityName {
            try container.encode(entityName, forKey: .entityName)
        } else {
            try container.encodeNil(forKey: .entityName)
        }
        try container.encode(description, forKey: .description)
        try container.encode(evidenceQuote, forKey: .evidenceQuote)
        try container.encode(confidence, forKey: .confidence)
    }
}

public struct ExtractedRelationship: Codable, Equatable, Sendable {
    public let fromEntityName: String
    public let toEntityName: String
    public let kind: RelationshipKind
    public let description: String
    public let evidenceQuote: String
    public let confidence: Double

    public init(
        fromEntityName: String,
        toEntityName: String,
        kind: RelationshipKind,
        description: String,
        evidenceQuote: String,
        confidence: Double
    ) {
        self.fromEntityName = fromEntityName
        self.toEntityName = toEntityName
        self.kind = kind
        self.description = description
        self.evidenceQuote = evidenceQuote
        self.confidence = confidence
    }
}

public struct ReconcileResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let canonicalEntities: [ReconciledEntity]
    public let proposedMerges: [ProposedExistingMerge]

    public init(
        schemaVersion: Int = 1,
        canonicalEntities: [ReconciledEntity],
        proposedMerges: [ProposedExistingMerge]
    ) {
        self.schemaVersion = schemaVersion
        self.canonicalEntities = canonicalEntities
        self.proposedMerges = proposedMerges
    }
}

public struct ReconciledEntity: Codable, Equatable, Sendable {
    public let existingId: UUID?
    public let kind: EntityKind
    public let name: String
    public let aliases: [String]
    public let description: String
    public let mergedFrom: [String]

    public init(
        existingId: UUID?,
        kind: EntityKind,
        name: String,
        aliases: [String],
        description: String,
        mergedFrom: [String]
    ) {
        self.existingId = existingId
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.description = description
        self.mergedFrom = mergedFrom
    }

    private enum CodingKeys: String, CodingKey {
        case existingId, kind, name, aliases, description, mergedFrom
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let existingId {
            try container.encode(existingId, forKey: .existingId)
        } else {
            try container.encodeNil(forKey: .existingId)
        }
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(description, forKey: .description)
        try container.encode(mergedFrom, forKey: .mergedFrom)
    }
}

public struct ProposedExistingMerge: Codable, Equatable, Sendable {
    public let sourceId: UUID
    public let targetId: UUID
    public let reason: String

    public init(sourceId: UUID, targetId: UUID, reason: String) {
        self.sourceId = sourceId
        self.targetId = targetId
        self.reason = reason
    }
}
