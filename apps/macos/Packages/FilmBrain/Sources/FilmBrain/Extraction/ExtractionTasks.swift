import Foundation

public struct ExtractChunkTask: StructuredTask {
    public typealias Output = ExtractChunkResult
    public let taskName = "extractChunk"
    public let schemaVersion = ExtractChunkSchema.version
    public let schemaURL = ExtractChunkSchema.url
    private let validator: ExtractChunkValidator

    public init(chunk: ExtractionChunk) {
        self.validator = ExtractChunkValidator(chunk: chunk)
    }

    public func prompt(for input: StructuredTaskInput) throws -> String {
        ExtractChunkPrompt.render(payload: input.text)
    }

    public func validate(resultFileAt url: URL) throws -> ExtractChunkResult {
        try validator.validate(resultFileAt: url)
    }
}

public struct ReconcileEntitiesTask: StructuredTask {
    public typealias Output = ReconcileResult
    public let taskName = "reconcileEntities"
    public let schemaVersion = ReconcileEntitiesSchema.version
    public let schemaURL = ReconcileEntitiesSchema.url
    private let validator: ReconcileValidator

    public init(existingIDs: Set<UUID>, chunkEntityNames: Set<String>) {
        self.validator = ReconcileValidator(
            existingIDs: existingIDs,
            chunkEntityNames: chunkEntityNames
        )
    }

    public func prompt(for input: StructuredTaskInput) throws -> String {
        ReconcilePrompt.render(payload: input.text)
    }

    public func validate(resultFileAt url: URL) throws -> ReconcileResult {
        try validator.validate(resultFileAt: url)
    }
}
