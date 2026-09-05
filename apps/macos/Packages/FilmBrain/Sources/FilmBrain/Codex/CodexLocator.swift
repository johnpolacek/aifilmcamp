import Foundation

public struct LoginShellCapture: Equatable, Sendable {
    public let codexPath: String?
    public let path: String
    public let codexHome: String?

    public init(codexPath: String?, path: String, codexHome: String?) {
        self.codexPath = codexPath
        self.path = path
        self.codexHome = codexHome
    }
}

public struct CodexLocator: Sendable {
    public typealias LoginShellProvider = @Sendable () async -> LoginShellCapture

    private let overrideURL: URL?
    private let inheritedEnvironment: [String: String]
    private let homeDirectory: URL
    private let loginShellProvider: LoginShellProvider
    private let processRunner: any ProcessRunning
    private let fileSystem: any FileSystemChecking

    public init(
        overrideURL: URL? = nil,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        loginShellProvider: LoginShellProvider? = nil,
        processRunner: any ProcessRunning = FoundationProcessRunner(),
        fileSystem: any FileSystemChecking = LocalFileSystem()
    ) {
        self.overrideURL = overrideURL
        self.inheritedEnvironment = inheritedEnvironment
        self.homeDirectory = homeDirectory
        self.processRunner = processRunner
        self.fileSystem = fileSystem
        self.loginShellProvider = loginShellProvider ?? {
            await Self.captureLoginShell(
                inheritedEnvironment: inheritedEnvironment,
                runner: processRunner
            )
        }
    }

    public func locate() async -> HarnessStatus {
        let shellCapture = await loginShellProvider()
        let environment = MinimalLaunchEnvironment.build(
            inherited: inheritedEnvironment,
            capturedPath: shellCapture.path,
            capturedCodexHome: shellCapture.codexHome,
            fileSystem: fileSystem
        )
        var candidates: [URL] = []
        if let overrideURL { candidates.append(overrideURL) }
        if let inherited = executable(named: "codex", path: inheritedEnvironment["PATH"]) {
            candidates.append(inherited)
        }
        if let shellPath = shellCapture.codexPath { candidates.append(URL(fileURLWithPath: shellPath)) }
        candidates += knownCandidates()

        var seen = Set<String>()
        var tried: [String] = []
        var fallbackStatus: HarnessStatus?
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            guard standardized.path.hasPrefix("/") else { continue }
            let resolved = standardized.resolvingSymlinksInPath()
            guard seen.insert(resolved.path).inserted else { continue }
            guard fileSystem.fileExists(atPath: resolved.path) else {
                tried.append("\(sanitizedPath(resolved.path)): missing")
                continue
            }
            guard fileSystem.isExecutableFile(atPath: resolved.path) else {
                tried.append("\(sanitizedPath(resolved.path)): not executable")
                continue
            }

            let context = CodexLaunchContext(executableURL: resolved, environment: environment)
            do {
                let versionResult = try await probe(context, arguments: ["--version"])
                guard !versionResult.timedOut else {
                    tried.append("\(sanitizedPath(resolved.path)): version timed out")
                    continue
                }
                guard versionResult.exitCode == 0,
                      !versionResult.outputExceeded,
                      let version = CodexCompatibilityPolicy.parseVersion(versionResult.stdoutString)
                else {
                    tried.append("\(sanitizedPath(resolved.path)): version probe failed")
                    continue
                }
                let rootHelp = try await probe(context, arguments: ["--help"])
                let execHelp = try await probe(context, arguments: ["exec", "--help"])
                let missing = CodexCompatibilityPolicy.missingCapabilities(
                    version: version,
                    rootHelp: rootHelp.stdoutString,
                    execHelp: execHelp.stdoutString
                )
                guard rootHelp.exitCode == 0, execHelp.exitCode == 0,
                      !rootHelp.timedOut, !execHelp.timedOut,
                      !rootHelp.outputExceeded, !execHelp.outputExceeded,
                      missing.isEmpty
                else {
                    fallbackStatus = .installedButIncompatible(
                        path: resolved.path,
                        version: version.description,
                        missingCapabilities: missing.isEmpty ? ["bounded help probe"] : missing
                    )
                    tried.append("\(sanitizedPath(resolved.path)): incompatible")
                    continue
                }
                let login = try await probe(context, arguments: ["login", "status"])
                guard login.exitCode == 0, !login.timedOut, !login.outputExceeded else {
                    fallbackStatus = .installedButUnauthenticated(
                        path: resolved.path,
                        version: version.description
                    )
                    tried.append("\(sanitizedPath(resolved.path)): signed out")
                    continue
                }
                return .ready(
                    context: context,
                    version: version.description,
                    authenticationMode: authenticationMode(login.stdoutString),
                    capabilities: .phase0Required
                )
            } catch {
                tried.append("\(sanitizedPath(resolved.path)): launch failed")
            }
        }
        if let fallbackStatus { return fallbackStatus }
        if tried.isEmpty { return .notInstalled }
        return .detectionFailed(
            actionableMessage: "Codex was not usable. Tried: \(tried.joined(separator: "; ")). Install Codex or run codex login, then refresh."
        )
    }

    public static func captureLoginShell(
        inheritedEnvironment: [String: String],
        runner: any ProcessRunning
    ) async -> LoginShellCapture {
        let shell = inheritedEnvironment["SHELL"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/bin/zsh"
        let command = """
            printf '__FILMCAMP_CODEX__%s\\n' "$(command -v -- codex 2>/dev/null || true)"
            printf '__FILMCAMP_PATH__%s\\n' "$PATH"
            printf '__FILMCAMP_HOME__%s\\n' "${CODEX_HOME:-}"
            """
        let request = ProcessRequest(
            executableURL: URL(fileURLWithPath: shell),
            arguments: ["-ilc", command],
            environment: MinimalLaunchEnvironment.shellLookupEnvironment(inheritedEnvironment),
            timeout: .seconds(5),
            stdoutLimit: 65_536,
            stderrLimit: 16_384
        )
        guard let result = try? await runner.run(request), result.exitCode == 0, !result.timedOut else {
            return LoginShellCapture(
                codexPath: nil,
                path: inheritedEnvironment["PATH"] ?? "/usr/bin:/bin",
                codexHome: nil
            )
        }
        var codexPath: String?
        var path = inheritedEnvironment["PATH"] ?? "/usr/bin:/bin"
        var codexHome: String?
        for line in result.stdoutString.split(separator: "\n", omittingEmptySubsequences: false) {
            let value = String(line)
            if value.hasPrefix("__FILMCAMP_CODEX__") {
                let captured = String(value.dropFirst("__FILMCAMP_CODEX__".count))
                codexPath = captured.hasPrefix("/") ? captured : nil
            } else if value.hasPrefix("__FILMCAMP_PATH__") {
                let captured = String(value.dropFirst("__FILMCAMP_PATH__".count))
                if !captured.isEmpty && captured.utf8.count <= 32_768 { path = captured }
            } else if value.hasPrefix("__FILMCAMP_HOME__") {
                let captured = String(value.dropFirst("__FILMCAMP_HOME__".count))
                if !captured.isEmpty && captured.utf8.count <= 4_096 { codexHome = captured }
            }
        }
        return LoginShellCapture(codexPath: codexPath, path: path, codexHome: codexHome)
    }

    private func probe(_ context: CodexLaunchContext, arguments: [String]) async throws -> ProcessResult {
        try await processRunner.run(ProcessRequest(
            executableURL: context.executableURL,
            arguments: arguments,
            environment: context.environment,
            timeout: .seconds(5),
            stdoutLimit: 65_536,
            stderrLimit: 65_536
        ))
    }

    private func executable(named name: String, path: String?) -> URL? {
        path?.split(separator: ":").lazy
            .map { URL(fileURLWithPath: String($0)).appending(path: name) }
            .first { fileSystem.isExecutableFile(atPath: $0.path) }
    }

    private func knownCandidates() -> [URL] {
        [
            ".local/bin/codex",
            ".local/share/fnm/aliases/default/bin/codex",
            ".volta/bin/codex",
            ".bun/bin/codex",
        ].map { homeDirectory.appending(path: $0) } + [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
    }

    private func authenticationMode(_ output: String) -> AuthenticationMode {
        let normalized = output.lowercased()
        if normalized.contains("chatgpt") { return .chatGPT }
        if normalized.contains("api key") { return .apiKey }
        return .signedIn
    }

    private func sanitizedPath(_ path: String) -> String {
        path.replacingOccurrences(of: homeDirectory.path, with: "~")
    }
}

enum MinimalLaunchEnvironment {
    static func shellLookupEnvironment(_ inherited: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for key in ["HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "TERM"] {
            if let value = inherited[key], isBoundedPlain(value, maximum: 4_096) { result[key] = value }
        }
        result["PATH"] = inherited["PATH"] ?? "/usr/bin:/bin"
        return result
    }

    static func build(
        inherited: [String: String],
        capturedPath: String,
        capturedCodexHome: String?,
        fileSystem: any FileSystemChecking
    ) -> [String: String] {
        var result = credentialFreeBuild(
            inherited: inherited,
            capturedPath: capturedPath,
            fileSystem: fileSystem
        )
        if let capturedCodexHome,
           capturedCodexHome.hasPrefix("/"),
           isBoundedPlain(capturedCodexHome, maximum: 4_096) {
            result["CODEX_HOME"] = capturedCodexHome
        }
        return result
    }

    static func credentialFreeBuild(
        inherited: [String: String],
        capturedPath: String,
        fileSystem: any FileSystemChecking
    ) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in inherited {
            if ["HOME", "TMPDIR", "USER", "LOGNAME", "LANG"].contains(key) || key.hasPrefix("LC_") {
                if isBoundedPlain(value, maximum: 4_096) { result[key] = value }
            }
        }
        result["PATH"] = isBoundedPlain(capturedPath, maximum: 32_768) && !capturedPath.isEmpty
            ? capturedPath : "/usr/bin:/bin"
        for key in ["SSL_CERT_FILE", "SSL_CERT_DIR"] {
            guard let value = inherited[key], value.hasPrefix("/"), isBoundedPlain(value, maximum: 4_096) else { continue }
            var isDirectory: ObjCBool = false
            guard fileSystem.fileExists(atPath: value, isDirectory: &isDirectory) else { continue }
            if key == "SSL_CERT_FILE" && !isDirectory.boolValue { result[key] = value }
            if key == "SSL_CERT_DIR" && isDirectory.boolValue { result[key] = value }
        }
        for key in ["NO_PROXY", "no_proxy"] {
            if let value = inherited[key], validNoProxy(value) { result[key] = value }
        }
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            if let value = inherited[key], validProxy(value) { result[key] = value }
        }
        return result
    }

    static func omittedProxyNetworkMessage() -> String {
        "Codex could not reach the network. Unsupported or credential-bearing proxy values were not forwarded."
    }

    private static func validProxy(_ value: String) -> Bool {
        guard isBoundedPlain(value, maximum: 2_048),
              let components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { return false }
        return true
    }

    private static func validNoProxy(_ value: String) -> Bool {
        guard isBoundedPlain(value, maximum: 2_048), !value.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._,*:[]")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func isBoundedPlain(_ value: String, maximum: Int) -> Bool {
        value.utf8.count <= maximum && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

public protocol FileSystemChecking: Sendable {
    func fileExists(atPath path: String) -> Bool
    func fileExists(atPath path: String, isDirectory: inout ObjCBool) -> Bool
    func isExecutableFile(atPath path: String) -> Bool
}

public struct LocalFileSystem: FileSystemChecking, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    public func fileExists(atPath path: String, isDirectory: inout ObjCBool) -> Bool {
        fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
    }

    public func isExecutableFile(atPath path: String) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }
}
