import Foundation

public enum ExtractChunkSchema: Sendable {
    public static let version = 1
    public static var url: URL {
        Bundle.module.url(forResource: "extract-chunk-v1.schema", withExtension: "json")!
    }
}

public enum ReconcileEntitiesSchema: Sendable {
    public static let version = 1
    public static var url: URL {
        Bundle.module.url(forResource: "reconcile-entities-v1.schema", withExtension: "json")!
    }
}
