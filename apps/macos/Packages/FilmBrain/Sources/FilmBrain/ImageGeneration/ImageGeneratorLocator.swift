import Foundation

struct ImageHelperCapabilities: Codable, Equatable, Sendable {
    struct Provider: Codable, Equatable, Sendable {
        let id: String
        let modelIDs: [String]
        let aspectRatios: [String]
        let outputFormats: [String]
        let maximumReferenceImages: Int
        let maximumCharacterReferences: Int?
        let maximumNonCharacterReferences: Int?
    }

    let protocolVersion: Int
    let helperVersion: String
    let providers: [Provider]
}

public struct ImageGeneratorLocator: Sendable {
    public static let protocolVersion = 2

    private let provider: ImageProviderDescriptor
    private let helperURL: URL
    private let inheritedEnvironment: [String: String]
    private let credentialSource: any ImageProviderCredentialSource
    private let processRunner: any ProcessRunning
    private let fileSystem: any FileSystemChecking

    public init(
        provider: ImageProviderDescriptor,
        helperURL: URL,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        credentialSource: any ImageProviderCredentialSource,
        processRunner: any ProcessRunning = FoundationProcessRunner(),
        fileSystem: any FileSystemChecking = LocalFileSystem()
    ) {
        self.provider = provider
        self.helperURL = helperURL
        self.inheritedEnvironment = inheritedEnvironment
        self.credentialSource = credentialSource
        self.processRunner = processRunner
        self.fileSystem = fileSystem
    }

    public func locate() async -> ImageGeneratorStatus {
        let resolved = helperURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard resolved == helperURL.standardizedFileURL,
              resolved.isFileURL, resolved.path.hasPrefix("/"),
              fileSystem.fileExists(atPath: resolved.path),
              fileSystem.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileSystem.isExecutableFile(atPath: resolved.path)
        else { return .helperUnavailable }

        let environment = MinimalLaunchEnvironment.credentialFreeBuild(
            inherited: inheritedEnvironment,
            capturedPath: "/usr/bin:/bin",
            fileSystem: fileSystem
        )
        let result: ProcessResult
        do {
            result = try await processRunner.run(ProcessRequest(
                executableURL: resolved,
                arguments: ["--capabilities"],
                environment: environment,
                timeout: .seconds(5),
                stdoutLimit: 32_768,
                stderrLimit: 4_096
            ))
        } catch {
            return .helperIncompatible(reason: "The bundled helper could not launch.")
        }
        guard result.exitCode == 0, !result.timedOut, !result.outputExceeded else {
            return .helperIncompatible(reason: "The bundled helper did not complete its capability check.")
        }
        let capabilities: ImageHelperCapabilities
        do {
            capabilities = try JSONDecoder().decode(
                ImageHelperCapabilities.self, from: result.stdout
            )
        } catch {
            return .helperIncompatible(reason: "The bundled helper returned an invalid capability document.")
        }
        guard capabilities.protocolVersion == Self.protocolVersion else {
            return .helperIncompatible(reason: "The bundled helper uses an incompatible protocol version.")
        }
        let requiredOutputFormats = provider.id == ImageProviderDescriptor.googleNanoBanana2.id
            ? Set(["png", "jpeg"])
            : Set(["png"])
        guard let helperProvider = capabilities.providers.first(where: { $0.id == provider.id }),
              helperProvider.modelIDs.contains(provider.modelID),
              requiredOutputFormats.isSubset(of: Set(helperProvider.outputFormats)),
              Set(provider.outputSizes.keys.map(\.rawValue)).isSubset(
                of: Set(helperProvider.aspectRatios)
              ),
              helperProvider.maximumReferenceImages >= provider.maximumReferenceImages,
              helperProvider.maximumCharacterReferences == provider.maximumCharacterReferences,
              helperProvider.maximumNonCharacterReferences == provider.maximumNonCharacterReferences
        else {
            return .helperIncompatible(reason: "The bundled helper does not support \(provider.displayName).")
        }
        guard await credentialSource.isConfigured(providerID: provider.id) else {
            return .providerNotConfigured(providerName: provider.displayName)
        }
        return .ready(ImageGeneratorLaunchContext(
            provider: provider,
            helperURL: resolved,
            environment: environment,
            helperProtocolVersion: capabilities.protocolVersion
        ))
    }
}
