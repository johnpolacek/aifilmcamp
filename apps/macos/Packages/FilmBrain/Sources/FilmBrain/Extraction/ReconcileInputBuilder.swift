import FilmCore
import Foundation

public struct ReconcileInput: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let chunkEntities: [ReconcileChunkEntity]
    public let canonicalEntities: [ReconcileCanonicalEntity]

    public init(
        schemaVersion: Int = 1,
        chunkEntities: [ReconcileChunkEntity],
        canonicalEntities: [ReconcileCanonicalEntity]
    ) {
        self.schemaVersion = schemaVersion
        self.chunkEntities = chunkEntities
        self.canonicalEntities = canonicalEntities
    }
}

public struct ReconcileChunkEntity: Codable, Equatable, Sendable {
    public let chunkIndex: Int
    public let kind: EntityKind
    public let name: String
    public let aliases: [String]
    public let description: String

    public init(chunkIndex: Int, kind: EntityKind, name: String, aliases: [String], description: String) {
        self.chunkIndex = chunkIndex
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.description = description
    }
}

public struct ReconcileCanonicalEntity: Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: EntityKind
    public let name: String
    public let aliases: [String]
    public let protected: Bool
    public let locked: Bool
    public let rejected: Bool

    public init(
        id: UUID,
        kind: EntityKind,
        name: String,
        aliases: [String],
        protected: Bool,
        locked: Bool,
        rejected: Bool
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.protected = protected
        self.locked = locked
        self.rejected = rejected
    }
}

public enum ReconcileInputBuilder {
    public static func build(
        chunks: [(index: Int, result: ExtractChunkResult)],
        project: any ProjectReading
    ) async throws -> ReconcileInput {
        let chunkEntities = chunks
            .sorted { $0.index < $1.index }
            .flatMap { chunk in
                chunk.result.scenes.flatMap { scene in
                    scene.entities.map { entity in
                        ReconcileChunkEntity(
                            chunkIndex: chunk.index,
                            kind: entity.kind,
                            name: entity.name,
                            aliases: entity.aliasesInScene,
                            description: entity.description
                        )
                    }
                }
            }
        let entities = try await project.entities(
            kind: nil,
            reviewState: nil,
            includeIrrelevant: true,
            includeRejected: true
        )
        var canonical: [ReconcileCanonicalEntity] = []
        for entity in entities {
            let detail = try await project.entity(id: entity.id)
            canonical.append(ReconcileCanonicalEntity(
                id: entity.id,
                kind: entity.kind,
                name: entity.name,
                aliases: detail.aliases.map(\.alias).sorted(),
                protected: entity.provenance.isProtected,
                locked: !detail.locks.isEmpty,
                rejected: entity.provenance.reviewState == .rejected
            ))
        }
        canonical.sort {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            let left = EntityNormalization.normalize($0.name)
            let right = EntityNormalization.normalize($1.name)
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
        return ReconcileInput(chunkEntities: chunkEntities, canonicalEntities: canonical)
    }
}
