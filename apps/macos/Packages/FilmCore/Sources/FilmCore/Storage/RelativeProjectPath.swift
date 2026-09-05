import Foundation

public struct RelativeProjectPath: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard !rawValue.isEmpty,
              !rawValue.hasPrefix("/"),
              !rawValue.contains("\0"),
              !rawValue.contains("\\")
        else { throw ProjectStoreError.invalidRelativePath(rawValue) }

        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProjectStoreError.invalidRelativePath(rawValue)
        }
        self.rawValue = components.joined(separator: "/")
    }

    public init(_ rawValue: String) throws {
        try self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }

    public func resolve(in bundleRoot: URL) throws -> URL {
        let root = bundleRoot.standardizedFileURL
        let candidate = root.appending(path: rawValue).standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(prefix) else {
            throw ProjectStoreError.invalidRelativePath(rawValue)
        }
        return candidate
    }
}
