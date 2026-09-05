import Foundation

public enum AuthenticationMode: String, Codable, Equatable, Sendable {
    case chatGPT
    case apiKey
    case signedIn
}

public struct CodexLaunchContext: Equatable, Sendable {
    public let executableURL: URL
    public let environment: [String: String]

    public init(executableURL: URL, environment: [String: String]) {
        self.executableURL = executableURL
        self.environment = environment
    }
}

public enum HarnessStatus: Equatable, Sendable {
    case notInstalled
    case installedButUnauthenticated(path: String, version: String)
    case installedButIncompatible(path: String, version: String, missingCapabilities: [String])
    case ready(
        context: CodexLaunchContext,
        version: String,
        authenticationMode: AuthenticationMode,
        capabilities: HarnessCapabilities
    )
    case detectionFailed(actionableMessage: String)
}

