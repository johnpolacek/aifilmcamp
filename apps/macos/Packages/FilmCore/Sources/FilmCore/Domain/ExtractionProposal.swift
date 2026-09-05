import Foundation

public struct ProposedEvidence: Codable, Equatable, Hashable, Sendable {
    public let sceneID: UUID
    public let quote: String
    public let confidence: Double

    public init(sceneID: UUID, quote: String, confidence: Double) {
        self.sceneID = sceneID
        self.quote = quote
        self.confidence = confidence
    }
}

public struct ProposedAppearance: Codable, Equatable, Hashable, Sendable {
    public let sceneID: UUID
    public let role: SceneEntityRole
    public let evidence: ProposedEvidence

    public init(sceneID: UUID, role: SceneEntityRole, evidence: ProposedEvidence) {
        self.sceneID = sceneID
        self.role = role
        self.evidence = evidence
    }
}

public struct ProposedEntity: Codable, Equatable, Hashable, Sendable {
    public let kind: EntityKind
    public let name: String
    public let aliases: [String]
    public let description: String
    public let evidence: ProposedEvidence
    public let appearances: [ProposedAppearance]

    public init(
        kind: EntityKind,
        name: String,
        aliases: [String] = [],
        description: String = "",
        evidence: ProposedEvidence,
        appearances: [ProposedAppearance] = []
    ) {
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.description = description
        self.evidence = evidence
        self.appearances = appearances
    }
}

public struct ProposedSynopsis: Codable, Equatable, Hashable, Sendable {
    public let sceneID: UUID
    public let text: String
    public let evidence: ProposedEvidence

    public init(sceneID: UUID, text: String, evidence: ProposedEvidence) {
        self.sceneID = sceneID
        self.text = text
        self.evidence = evidence
    }
}

public struct ProposedState: Codable, Equatable, Hashable, Sendable {
    public let entityKind: EntityKind
    public let entityName: String
    public let category: StateCategory
    public let description: String
    public let startSceneID: UUID
    public let endSceneID: UUID?
    public let evidence: ProposedEvidence

    public init(
        entityKind: EntityKind,
        entityName: String,
        category: StateCategory,
        description: String,
        startSceneID: UUID,
        endSceneID: UUID? = nil,
        evidence: ProposedEvidence
    ) {
        self.entityKind = entityKind
        self.entityName = entityName
        self.category = category
        self.description = description
        self.startSceneID = startSceneID
        self.endSceneID = endSceneID
        self.evidence = evidence
    }
}

public struct ProposedEvent: Codable, Equatable, Hashable, Sendable {
    public let sceneID: UUID
    public let entityKind: EntityKind?
    public let entityName: String?
    public let description: String
    public let evidence: ProposedEvidence

    public init(
        sceneID: UUID,
        entityKind: EntityKind?,
        entityName: String?,
        description: String,
        evidence: ProposedEvidence
    ) {
        self.sceneID = sceneID
        self.entityKind = entityKind
        self.entityName = entityName
        self.description = description
        self.evidence = evidence
    }
}

public struct ProposedRelationship: Codable, Equatable, Hashable, Sendable {
    public let fromKind: EntityKind
    public let fromName: String
    public let toKind: EntityKind
    public let toName: String
    public let kind: RelationshipKind
    public let description: String
    public let evidence: ProposedEvidence

    public init(
        fromKind: EntityKind,
        fromName: String,
        toKind: EntityKind,
        toName: String,
        kind: RelationshipKind,
        description: String,
        evidence: ProposedEvidence
    ) {
        self.fromKind = fromKind
        self.fromName = fromName
        self.toKind = toKind
        self.toName = toName
        self.kind = kind
        self.description = description
        self.evidence = evidence
    }
}

public struct ExtractionMergeCandidate: Codable, Equatable, Hashable, Sendable {
    public let existingID: UUID?
    public let kind: EntityKind
    public let name: String
    public let aliases: [String]

    public init(existingID: UUID?, kind: EntityKind, name: String, aliases: [String]) {
        self.existingID = existingID
        self.kind = kind
        self.name = name
        self.aliases = aliases
    }
}

public struct ExtractionMergeSuggestion: Codable, Equatable, Hashable, Sendable {
    public let sourceID: UUID
    public let targetID: UUID
    public let reason: String

    public init(sourceID: UUID, targetID: UUID, reason: String) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.reason = reason
    }
}

public enum ExtractionProposalError: Error, Equatable, Sendable {
    case invalidScriptHash
    case invalidName
    case invalidEvidence
}

public struct ExtractionProposal: Codable, Equatable, Sendable {
    public let scriptID: UUID
    public let scriptSHA256: String
    public let settings: ExtractionSettings
    public let mergeCandidates: [ExtractionMergeCandidate]
    public let mergeSuggestions: [ExtractionMergeSuggestion]
    public let entities: [ProposedEntity]
    public let synopses: [ProposedSynopsis]
    public let states: [ProposedState]
    public let events: [ProposedEvent]
    public let relationships: [ProposedRelationship]
    public let chunksFailed: Int
    public let uncoveredSceneOrdinals: [Int]

    public init(
        scriptID: UUID,
        scriptSHA256: String,
        settings: ExtractionSettings = ExtractionSettings(),
        mergeCandidates: [ExtractionMergeCandidate] = [],
        mergeSuggestions: [ExtractionMergeSuggestion] = [],
        entities: [ProposedEntity] = [],
        synopses: [ProposedSynopsis] = [],
        states: [ProposedState] = [],
        events: [ProposedEvent] = [],
        relationships: [ProposedRelationship] = [],
        chunksFailed: Int = 0,
        uncoveredSceneOrdinals: [Int] = []
    ) throws {
        guard !scriptSHA256.isEmpty else { throw ExtractionProposalError.invalidScriptHash }
        guard entities.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              states.allSatisfy({ !$0.entityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              relationships.allSatisfy({ !$0.fromName.isEmpty && !$0.toName.isEmpty })
        else { throw ExtractionProposalError.invalidName }
        let evidence = entities.map(\.evidence)
            + entities.flatMap { $0.appearances.map(\.evidence) }
            + synopses.map(\.evidence) + states.map(\.evidence)
            + events.map(\.evidence) + relationships.map(\.evidence)
        guard evidence.allSatisfy({
            $0.confidence.isFinite && (0 ... 1).contains($0.confidence) && $0.quote.utf16.count <= 240
        }) else { throw ExtractionProposalError.invalidEvidence }
        self.scriptID = scriptID
        self.scriptSHA256 = scriptSHA256
        self.settings = settings
        self.mergeCandidates = mergeCandidates
        self.mergeSuggestions = mergeSuggestions
        self.entities = entities
        self.synopses = synopses
        self.states = states
        self.events = events
        self.relationships = relationships
        self.chunksFailed = max(0, chunksFailed)
        self.uncoveredSceneOrdinals = Array(Set(uncoveredSceneOrdinals)).sorted()
    }
}
