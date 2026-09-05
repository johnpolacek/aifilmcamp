import FilmCore
import Foundation

public struct ExtractChunkValidator: Sendable {
    public static let version = 1
    private let allowedScenes: Set<ChunkScene>
    private let structural = StructuredResultValidator()

    public init(chunk: ExtractionChunk) {
        self.allowedScenes = Set(chunk.scenes)
    }

    public init(scenes: [ChunkScene]) {
        self.allowedScenes = Set(scenes)
    }

    public func validate(resultFileAt url: URL) throws -> ExtractChunkResult {
        let data = try structural.validatedData(resultFileAt: url, schemaURL: ExtractChunkSchema.url)
        return try validate(data: data)
    }

    public func validate(data: Data) throws -> ExtractChunkResult {
        try structural.validate(data: data, schemaURL: ExtractChunkSchema.url)
        let result = try JSONDecoder().decode(ExtractChunkResult.self, from: data)
        guard result.schemaVersion == ExtractChunkSchema.version else {
            throw ExtractionSemanticValidation.reject(.wrongSchemaVersion)
        }
        var seenScenes = Set<ChunkScene>()
        for scene in result.scenes {
            let identity = ChunkScene(id: scene.sceneId, ordinal: scene.sceneOrdinal)
            guard allowedScenes.contains(identity) else {
                throw ExtractionSemanticValidation.reject(.sceneOutsideChunk)
            }
            guard seenScenes.insert(identity).inserted else {
                throw ExtractionSemanticValidation.reject(.duplicateFact)
            }
            try validate(scene)
        }
        return result
    }

    private func validate(_ scene: ExtractedScene) throws {
        try ExtractionSemanticValidation.validateText(scene.synopsis.text)
        try ExtractionSemanticValidation.validateQuote(scene.synopsis.evidenceQuote)
        try ExtractionSemanticValidation.validateConfidence(scene.synopsis.confidence)

        var entityKeys = Set<String>()
        var entityNames: [String: Int] = [:]
        for entity in scene.entities {
            try ExtractionSemanticValidation.validateText(entity.name, entity.description)
            try entity.aliasesInScene.forEach { try ExtractionSemanticValidation.validateText($0) }
            try ExtractionSemanticValidation.validateQuote(entity.evidenceQuote)
            try ExtractionSemanticValidation.validateConfidence(entity.confidence)
            let normalized = ExtractionSemanticValidation.normalized(entity.name)
            let key = "\(entity.kind.rawValue):\(normalized)"
            guard !normalized.isEmpty, entityKeys.insert(key).inserted else {
                throw ExtractionSemanticValidation.reject(.duplicateFact)
            }
            entityNames[normalized, default: 0] += 1
        }

        func requireEntity(_ name: String) throws {
            let normalized = ExtractionSemanticValidation.normalized(name)
            guard entityNames[normalized] == 1 else {
                throw ExtractionSemanticValidation.reject(.danglingEntityReference)
            }
        }

        var factKeys = Set<String>()
        for state in scene.states {
            try ExtractionSemanticValidation.validateText(state.entityName, state.description)
            try ExtractionSemanticValidation.validateQuote(state.evidenceQuote)
            try ExtractionSemanticValidation.validateConfidence(state.confidence)
            try requireEntity(state.entityName)
            let key = "state:\(ExtractionSemanticValidation.normalized(state.entityName)):\(state.category.rawValue):\(ExtractionSemanticValidation.normalized(state.description))"
            guard factKeys.insert(key).inserted else { throw ExtractionSemanticValidation.reject(.duplicateFact) }
        }
        for event in scene.events {
            try ExtractionSemanticValidation.validateText(event.description)
            try ExtractionSemanticValidation.validateQuote(event.evidenceQuote)
            try ExtractionSemanticValidation.validateConfidence(event.confidence)
            if let name = event.entityName {
                try ExtractionSemanticValidation.validateText(name)
                try requireEntity(name)
            }
            let key = "event:\(ExtractionSemanticValidation.normalized(event.entityName ?? "")):\(ExtractionSemanticValidation.normalized(event.description))"
            guard factKeys.insert(key).inserted else { throw ExtractionSemanticValidation.reject(.duplicateFact) }
        }
        for relationship in scene.relationships {
            try ExtractionSemanticValidation.validateText(
                relationship.fromEntityName,
                relationship.toEntityName,
                relationship.description
            )
            try ExtractionSemanticValidation.validateQuote(relationship.evidenceQuote)
            try ExtractionSemanticValidation.validateConfidence(relationship.confidence)
            try requireEntity(relationship.fromEntityName)
            try requireEntity(relationship.toEntityName)
            let key = "relationship:\(ExtractionSemanticValidation.normalized(relationship.fromEntityName)):\(ExtractionSemanticValidation.normalized(relationship.toEntityName)):\(relationship.kind.rawValue)"
            guard factKeys.insert(key).inserted else { throw ExtractionSemanticValidation.reject(.duplicateFact) }
        }
    }
}
