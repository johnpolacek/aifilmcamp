import Foundation

public struct ProcessRequest: Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let currentDirectoryURL: URL?
    public let standardInput: Data?
    public let timeout: Duration
    public let stdoutLimit: Int
    public let stderrLimit: Int

    public init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL? = nil,
        standardInput: Data? = nil,
        timeout: Duration = .seconds(5),
        stdoutLimit: Int = 65_536,
        stderrLimit: Int = 65_536
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
        self.standardInput = standardInput
        self.timeout = timeout
        self.stdoutLimit = stdoutLimit
        self.stderrLimit = stderrLimit
    }
}

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data
    public let timedOut: Bool
    public let outputExceeded: Bool

    public init(
        exitCode: Int32,
        stdout: Data = Data(),
        stderr: Data = Data(),
        timedOut: Bool = false,
        outputExceeded: Bool = false
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.outputExceeded = outputExceeded
    }

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

public protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessResult
    func run(
        _ request: ProcessRequest,
        onChunk: @escaping @Sendable (ProcessChunk) -> Void
    ) async throws -> ProcessResult
}

public extension ProcessRunning {
    func run(
        _ request: ProcessRequest,
        onChunk: @escaping @Sendable (ProcessChunk) -> Void
    ) async throws -> ProcessResult {
        let result = try await run(request)
        if !result.stdout.isEmpty { onChunk(.stdout(result.stdout)) }
        if !result.stderr.isEmpty { onChunk(.stderr(result.stderr)) }
        return result
    }
}

public enum ProcessChunk: Sendable {
    case stdout(Data)
    case stderr(Data)
}

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case couldNotLaunch
}
