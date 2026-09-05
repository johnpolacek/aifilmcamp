import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public enum CodexCompatibilityPolicy {
    public static let minimumVersion = SemanticVersion(major: 0, minor: 146, patch: 0)
    public static let requiredRootFlags = ["-C", "-c", "--sandbox", "--ask-for-approval"]
    public static let requiredExecFlags = [
        "--json", "--output-schema", "--output-last-message", "--ephemeral",
        "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules", "--color",
    ]

    public static func parseVersion(_ output: String) -> SemanticVersion? {
        let fields = output.split(whereSeparator: \.isWhitespace)
        guard let versionField = fields.first(where: { $0.first?.isNumber == true }) else { return nil }
        let components = versionField.split(separator: ".")
        guard components.count >= 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2].prefix(while: \.isNumber))
        else { return nil }
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }

    public static func missingCapabilities(
        version: SemanticVersion,
        rootHelp: String,
        execHelp: String
    ) -> [String] {
        var missing: [String] = []
        if version < minimumVersion { missing.append("codex >= \(minimumVersion)") }
        missing += requiredRootFlags.filter { !rootHelp.contains($0) }
        missing += requiredExecFlags.filter { !execHelp.contains($0) }
        return missing
    }
}
