import Foundation
import FilmCore

public actor LocalImageGenerator: ImageGenerating {
    private static let maximumPromptBytes = 65_536
    private static let maximumOutputBytes: Int64 = 64 * 1_024 * 1_024
    private static let candidateRange = 1...4

    private let provider: ImageProviderDescriptor
    private let credentialSource: any ImageProviderCredentialSource
    private let locator: ImageGeneratorLocator
    private let processRunner: any ProcessRunning
    private var continuation: AsyncStream<ImageGenerationProgress>.Continuation?
    private var activeRun: Task<ImageGenerationResult, any Error>?

    public init(
        provider: ImageProviderDescriptor,
        helperURL: URL,
        credentialSource: any ImageProviderCredentialSource,
        processRunner: any ProcessRunning = FoundationProcessRunner()
    ) {
        self.provider = provider
        self.credentialSource = credentialSource
        self.processRunner = processRunner
        self.locator = ImageGeneratorLocator(
            provider: provider,
            helperURL: helperURL,
            credentialSource: credentialSource,
            processRunner: processRunner
        )
    }

    init(
        provider: ImageProviderDescriptor,
        credentialSource: any ImageProviderCredentialSource,
        locator: ImageGeneratorLocator,
        processRunner: any ProcessRunning
    ) {
        self.provider = provider
        self.credentialSource = credentialSource
        self.locator = locator
        self.processRunner = processRunner
    }

    public func progress() -> AsyncStream<ImageGenerationProgress> {
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            self.continuation = continuation
        }
    }

    public func status() async -> ImageGeneratorStatus {
        await locator.locate()
    }

    public func generate(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        guard activeRun == nil else { throw ImageGenerationError.runAlreadyActive }
        let continuation = continuation
        let provider = provider
        let credentialSource = credentialSource
        let locator = locator
        let processRunner = processRunner
        let task = Task {
            try await Self.perform(
                request,
                provider: provider,
                credentialSource: credentialSource,
                locator: locator,
                processRunner: processRunner,
                progress: { continuation?.yield($0) }
            )
        }
        activeRun = task
        defer { activeRun = nil }
        do {
            return try await task.value
        } catch is CancellationError {
            throw ImageGenerationError.cancelled
        }
    }

    public func cancel() {
        activeRun?.cancel()
    }

    private static func perform(
        _ request: ImageGenerationRequest,
        provider: ImageProviderDescriptor,
        credentialSource: any ImageProviderCredentialSource,
        locator: ImageGeneratorLocator,
        processRunner: any ProcessRunning,
        progress: @escaping @Sendable (ImageGenerationProgress) -> Void
    ) async throws -> ImageGenerationResult {
        let fileManager = FileManager.default
        let requestedSize = try validate(request, provider: provider, fileManager: fileManager)
        progress(.init(stage: .preparing))
        let located = await locator.locate()
        guard case let .ready(context) = located else {
            throw ImageGenerationError.generatorUnavailable(located)
        }
        let credential: Data
        do {
            credential = try await credentialSource.credential(providerID: provider.id)
        } catch let reason as ImageProviderCredentialError {
            throw ImageGenerationError.credentialReadFailed(
                providerName: provider.displayName, reason: reason
            )
        } catch {
            throw ImageGenerationError.credentialUnavailable(providerName: provider.displayName)
        }
        guard !credential.isEmpty, credential.count <= 16_384,
              let authorization = String(data: credential, encoding: .utf8),
              !authorization.contains("\n"), !authorization.contains("\r")
        else {
            throw ImageGenerationError.credentialReadFailed(
                providerName: provider.displayName, reason: .invalidStoredCredential
            )
        }
        try Task.checkCancellation()
        do {
            try fileManager.createDirectory(
                at: request.outputDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ImageGenerationError.outputDirectoryInvalid
        }

        var workspaces: [URL] = []
        var candidates: [ImageGenerationCandidate] = []
        do {
            for index in 1...request.candidateCount {
                try Task.checkCancellation()
                let workspace = request.outputDirectoryURL.appending(
                    path: "candidate-\(index)-\(UUID().uuidString.lowercased())",
                    directoryHint: .isDirectory
                )
                try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
                workspaces.append(workspace)
                let outputURL = workspace.appending(path: "candidate.png")
                let helperRequest = ImageHelperRequest(
                    protocolVersion: context.helperProtocolVersion,
                    providerID: provider.id,
                    modelID: provider.modelID,
                    authorization: authorization,
                    prompt: request.prompt,
                    references: request.references.map {
                        .init(path: $0.imageURL.path, entityKind: $0.entityKind.rawValue)
                    },
                    outputPath: outputURL.path,
                    aspectRatio: request.settings.aspectRatio.rawValue,
                    width: requestedSize.width,
                    height: requestedSize.height,
                    outputFormat: "png"
                )
                let input = try framed(helperRequest)
                progress(.init(stage: .generating(candidate: index, total: request.candidateCount)))
                let result: ProcessResult
                do {
                    result = try await processRunner.run(ProcessRequest(
                        executableURL: context.helperURL,
                        arguments: ["--stdio"],
                        environment: context.environment,
                        currentDirectoryURL: workspace,
                        standardInput: input,
                        timeout: .seconds(180),
                        stdoutLimit: 32_768,
                        stderrLimit: 8_192
                    ))
                } catch is CancellationError {
                    throw ImageGenerationError.cancelled
                } catch {
                    throw ImageGenerationError.couldNotLaunch(candidate: index)
                }
                try Task.checkCancellation()
                if result.timedOut { throw ImageGenerationError.processTimedOut(candidate: index) }
                if result.outputExceeded {
                    throw ImageGenerationError.processOutputExceeded(candidate: index)
                }
                let terminal = terminalEvent(from: result.stdout)
                guard result.exitCode == 0 else {
                    throw ImageGenerationError.processFailed(
                        candidate: index,
                        code: sanitizedErrorCode(terminal?.code)
                    )
                }
                guard let terminal,
                      let reportedMediaType = terminal.mediaType,
                      let resultURL = terminalOutputURL(
                          terminal,
                          workspace: workspace,
                          requestedURL: outputURL
                      )
                else {
                    throw ImageGenerationError.missingOutput(candidate: index)
                }
                progress(.init(stage: .validating(candidate: index, total: request.candidateCount)))
                candidates.append(try validateOutput(
                    at: resultURL,
                    candidate: index,
                    provider: provider,
                    reportedMediaType: reportedMediaType,
                    requestedSize: requestedSize,
                    fileManager: fileManager
                ))
            }
        } catch is CancellationError {
            workspaces.forEach { try? fileManager.removeItem(at: $0) }
            throw ImageGenerationError.cancelled
        } catch {
            workspaces.forEach { try? fileManager.removeItem(at: $0) }
            throw error
        }
        progress(.init(stage: .completed(total: candidates.count)))
        return ImageGenerationResult(
            candidates: candidates,
            providerID: provider.id,
            modelID: provider.modelID,
            helperProtocolVersion: context.helperProtocolVersion,
            requestedSize: requestedSize
        )
    }

    private static func validate(
        _ request: ImageGenerationRequest,
        provider: ImageProviderDescriptor,
        fileManager: FileManager
    ) throws -> ImagePixelSize {
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImageGenerationError.promptIsEmpty
        }
        guard request.prompt.utf8.count <= maximumPromptBytes else {
            throw ImageGenerationError.promptTooLarge(maximumBytes: maximumPromptBytes)
        }
        guard candidateRange.contains(request.candidateCount) else {
            throw ImageGenerationError.invalidCandidateCount(allowed: candidateRange)
        }
        guard request.references.count <= provider.maximumReferenceImages else {
            throw ImageGenerationError.unsupportedReferenceCount(
                providerName: provider.displayName,
                count: request.references.count,
                maximum: provider.maximumReferenceImages
            )
        }
        if let maximum = provider.maximumCharacterReferences {
            let count = request.references.filter {
                $0.entityKind == .character || $0.entityKind == .creature
            }.count
            guard count <= maximum else {
                throw ImageGenerationError.unsupportedCharacterReferenceCount(
                    providerName: provider.displayName, count: count, maximum: maximum
                )
            }
        }
        if let maximum = provider.maximumNonCharacterReferences {
            let count = request.references.filter {
                $0.entityKind != .character && $0.entityKind != .creature
            }.count
            guard count <= maximum else {
                throw ImageGenerationError.unsupportedReferenceCount(
                    providerName: provider.displayName, count: count, maximum: maximum
                )
            }
        }
        guard let size = provider.outputSizes[request.settings.aspectRatio] else {
            throw ImageGenerationError.unsupportedAspectRatio(
                providerName: provider.displayName, ratio: request.settings.aspectRatio
            )
        }
        guard request.outputDirectoryURL.isFileURL,
              request.outputDirectoryURL.path.hasPrefix("/")
        else { throw ImageGenerationError.outputDirectoryInvalid }
        for (offset, reference) in request.references.enumerated() {
            guard isRegularFile(reference.imageURL, fileManager: fileManager) else {
                throw ImageGenerationError.invalidReference(index: offset + 1)
            }
        }
        return size
    }

    private static func validateOutput(
        at url: URL,
        candidate: Int,
        provider: ImageProviderDescriptor,
        reportedMediaType: String,
        requestedSize: ImagePixelSize,
        fileManager: FileManager
    ) throws -> ImageGenerationCandidate {
        guard isRegularFile(url, fileManager: fileManager),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              size > 0
        else { throw ImageGenerationError.invalidOutput(candidate: candidate) }
        guard size <= maximumOutputBytes else {
            throw ImageGenerationError.outputTooLarge(
                candidate: candidate, maximumBytes: maximumOutputBytes
            )
        }
        guard let expectedFormat = expectedFormat(
            reportedMediaType: reportedMediaType,
            provider: provider
        ),
              let data = try? Data(contentsOf: url),
              AssetPathing.sniff(data) == expectedFormat,
              let facts = try? AssetPathing.inspectForImport(
                  data,
                  fileName: url.lastPathComponent
              ),
              facts.format == expectedFormat
        else { throw ImageGenerationError.invalidOutput(candidate: candidate) }
        if provider.id == ImageProviderDescriptor.openAIGPTImage2.id {
            guard facts.pixelWidth == requestedSize.width,
                  facts.pixelHeight == requestedSize.height
            else { throw ImageGenerationError.invalidOutput(candidate: candidate) }
        } else {
            let requestedRatio = Double(requestedSize.width) / Double(requestedSize.height)
            let actualRatio = Double(facts.pixelWidth) / Double(facts.pixelHeight)
            let longEdge = max(facts.pixelWidth, facts.pixelHeight)
            guard abs(actualRatio - requestedRatio) / requestedRatio <= 0.03,
                  (700...1_600).contains(longEdge)
            else { throw ImageGenerationError.invalidOutput(candidate: candidate) }
        }
        return ImageGenerationCandidate(fileURL: url, byteCount: size)
    }

    private static func expectedFormat(
        reportedMediaType: String,
        provider: ImageProviderDescriptor
    ) -> ImageFormat? {
        switch reportedMediaType.lowercased() {
        case "image/png":
            .png
        case "image/jpeg" where provider.id == ImageProviderDescriptor.googleNanoBanana2.id:
            .jpeg
        default:
            nil
        }
    }

    private static func terminalOutputURL(
        _ terminal: ImageHelperTerminalEvent,
        workspace: URL,
        requestedURL: URL
    ) -> URL? {
        guard terminal.type == "result",
              let path = terminal.path,
              let mediaType = terminal.mediaType,
              mediaType == "image/png" || mediaType == "image/jpeg"
        else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let workspace = workspace.standardizedFileURL
        guard url.deletingLastPathComponent() == workspace,
              url.deletingPathExtension().lastPathComponent
                == requestedURL.deletingPathExtension().lastPathComponent,
              (mediaType == "image/png" && url.pathExtension.lowercased() == "png")
                || (mediaType == "image/jpeg" && url.pathExtension.lowercased() == "jpg")
        else { return nil }
        return url
    }

    private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard url.isFileURL, url.path.hasPrefix("/"),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType
        else { return false }
        return type == .typeRegular
    }

    private static func framed(_ request: ImageHelperRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(request)
        guard payload.count <= 16 * 1_024 * 1_024 else {
            throw ImageGenerationError.promptTooLarge(maximumBytes: maximumPromptBytes)
        }
        var length = UInt32(payload.count).bigEndian
        var data = withUnsafeBytes(of: &length) { Data($0) }
        data.append(payload)
        return data
    }

    private static func terminalEvent(from data: Data) -> ImageHelperTerminalEvent? {
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        guard lines.count == 1 else { return nil }
        return try? JSONDecoder().decode(ImageHelperTerminalEvent.self, from: Data(lines[0]))
    }

    private static func sanitizedErrorCode(_ code: String?) -> String {
        let allowed = [
            "authentication", "billing", "quota", "rate_limit", "moderation",
            "invalid_request", "provider_unavailable", "timeout", "network", "unknown",
        ]
        guard let code, allowed.contains(code) else { return "provider_error" }
        return code
    }
}

private struct ImageHelperRequest: Encodable {
    struct Reference: Encodable {
        let path: String
        let entityKind: String
    }

    let protocolVersion: Int
    let providerID: String
    let modelID: String
    let authorization: String
    let prompt: String
    let references: [Reference]
    let outputPath: String
    let aspectRatio: String
    let width: Int
    let height: Int
    let outputFormat: String
}

private struct ImageHelperTerminalEvent: Decodable {
    let type: String
    let path: String?
    let mediaType: String?
    let code: String?
}
