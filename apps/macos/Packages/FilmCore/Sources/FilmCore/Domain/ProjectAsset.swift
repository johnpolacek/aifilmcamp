import Foundation

public struct ProjectAsset: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case screenplay
    }

    public let id: UUID
    public let projectID: UUID
    public let kind: Kind
    public let relativePath: RelativeProjectPath
    public let sha256: String
    public let createdAt: Date
}

