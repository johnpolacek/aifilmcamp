import FilmCore
import Foundation

public struct ReconcileValidator: Sendable {
    public static let version = 1
    private let existingIDs: Set<UUID>
    private let chunkEntityNames: Set<String>
    private let structural = StructuredResultValidator()

    public init(existingIDs: Set<UUID>, chunkEntityNames: Set<String>) {
        self.existingIDs = existingIDs
        self.chunkEntityNames = Set(chunkEntityNames.map(ExtractionSemanticValidation.normalized))
    }

    public func validate(resultFileAt url: URL) throws -> ReconcileResult {
        let data = try structural.validatedData(resultFileAt: url, schemaURL: ReconcileEntitiesSchema.url)
        return try validate(data: data)
    }

    public func validate(data: Data) throws -> ReconcileResult {
        try structural.validate(data: data, schemaURL: ReconcileEntitiesSchema.url)
        let result = try JSONDecoder().decode(ReconcileResult.self, from: data)
        guard result.schemaVersion == ReconcileEntitiesSchema.version else {
            throw ExtractionSemanticValidation.reject(.wrongSchemaVersion)
        }
        var canonical = Set<String>()
        for entity in result.canonicalEntities {
            try ExtractionSemanticValidation.validateText(entity.name, entity.description)
            try entity.aliases.forEach { try ExtractionSemanticValidation.validateText($0) }
            try entity.mergedFrom.forEach { try ExtractionSemanticValidation.validateText($0) }
            if let existingId = entity.existingId, !existingIDs.contains(existingId) {
                throw ExtractionSemanticValidation.reject(.danglingExistingID)
            }
            guard entity.mergedFrom.allSatisfy({ chunkEntityNames.contains(ExtractionSemanticValidation.normalized($0)) }) else {
                throw ExtractionSemanticValidation.reject(.danglingMergedFrom)
            }
            let key = "\(entity.kind.rawValue):\(ExtractionSemanticValidation.normalized(entity.name))"
            guard canonical.insert(key).inserted else {
                throw ExtractionSemanticValidation.reject(.duplicateFact)
            }
        }
        var merges = Set<String>()
        for merge in result.proposedMerges {
            try ExtractionSemanticValidation.validateText(merge.reason)
            guard merge.sourceId != merge.targetId,
                  existingIDs.contains(merge.sourceId),
                  existingIDs.contains(merge.targetId)
            else { throw ExtractionSemanticValidation.reject(.invalidMerge) }
            let key = "\(merge.sourceId.uuidString):\(merge.targetId.uuidString)"
            guard merges.insert(key).inserted else {
                throw ExtractionSemanticValidation.reject(.duplicateFact)
            }
        }
        return result
    }
}
