import Foundation
import FilmCore

public struct ImagePixelSize: Codable, Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum ImageGenerationAspectRatio: String, Codable, CaseIterable, Sendable {
    case portrait2x3 = "2:3"
    case landscape16x9 = "16:9"
    case square1x1 = "1:1"
}

public struct ImageProviderDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let modelID: String
    public let credentialLabel: String
    public let credentialStatusLabel: String
    public let credentialHelpURL: URL
    public let maximumReferenceImages: Int
    public let maximumCharacterReferences: Int?
    public let maximumNonCharacterReferences: Int?
    public let outputSizes: [ImageGenerationAspectRatio: ImagePixelSize]

    public init(
        id: String,
        displayName: String,
        modelID: String,
        credentialLabel: String,
        credentialStatusLabel: String,
        credentialHelpURL: URL,
        maximumReferenceImages: Int,
        maximumCharacterReferences: Int?,
        maximumNonCharacterReferences: Int?,
        outputSizes: [ImageGenerationAspectRatio: ImagePixelSize]
    ) {
        self.id = id
        self.displayName = displayName
        self.modelID = modelID
        self.credentialLabel = credentialLabel
        self.credentialStatusLabel = credentialStatusLabel
        self.credentialHelpURL = credentialHelpURL
        self.maximumReferenceImages = maximumReferenceImages
        self.maximumCharacterReferences = maximumCharacterReferences
        self.maximumNonCharacterReferences = maximumNonCharacterReferences
        self.outputSizes = outputSizes
    }

    public static let googleNanoBanana2 = ImageProviderDescriptor(
        id: "google-nano-banana-2",
        displayName: "Nano Banana 2",
        modelID: "gemini-3.1-flash-image",
        credentialLabel: "Google Gemini API key",
        credentialStatusLabel: "Nano Banana API Key",
        credentialHelpURL: URL(string: "https://aistudio.google.com/app/apikey")!,
        maximumReferenceImages: 14,
        maximumCharacterReferences: 4,
        maximumNonCharacterReferences: 10,
        outputSizes: [
            .portrait2x3: .init(width: 768, height: 1_152),
            .landscape16x9: .init(width: 1_280, height: 720),
            .square1x1: .init(width: 1_024, height: 1_024),
        ]
    )

    public static let openAIGPTImage2 = ImageProviderDescriptor(
        id: "openai-gpt-image-2",
        displayName: "GPT Image 2",
        modelID: "gpt-image-2-2026-04-21",
        credentialLabel: "OpenAI API key",
        credentialStatusLabel: "GPT Image 2 API Key",
        credentialHelpURL: URL(string: "https://platform.openai.com/api-keys")!,
        maximumReferenceImages: 14,
        maximumCharacterReferences: nil,
        maximumNonCharacterReferences: nil,
        outputSizes: [
            .portrait2x3: .init(width: 768, height: 1_152),
            .landscape16x9: .init(width: 1_280, height: 720),
            .square1x1: .init(width: 1_024, height: 1_024),
        ]
    )
}

public enum ImageProviderCatalog {
    public static let builtIn: [ImageProviderDescriptor] = [
        .googleNanoBanana2,
        .openAIGPTImage2,
    ]

    public static func provider(id: String) -> ImageProviderDescriptor? {
        builtIn.first { $0.id == id }
    }
}

public struct ImageGenerationSettings: Equatable, Sendable {
    public let aspectRatio: ImageGenerationAspectRatio

    public init(aspectRatio: ImageGenerationAspectRatio) {
        self.aspectRatio = aspectRatio
    }

    public static func smartDefault(for kind: EntityKind) -> Self {
        switch kind {
        case .character, .creature:
            Self(aspectRatio: .portrait2x3)
        case .location, .vehicle:
            Self(aspectRatio: .landscape16x9)
        case .prop, .object:
            Self(aspectRatio: .square1x1)
        }
    }
}

public struct ImageGenerationReference: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let imageURL: URL
    public let entityKind: EntityKind

    public init(id: UUID = UUID(), imageURL: URL, entityKind: EntityKind) {
        self.id = id
        self.imageURL = imageURL
        self.entityKind = entityKind
    }
}

public struct ImageGenerationRequest: Equatable, Sendable {
    public let prompt: String
    public let references: [ImageGenerationReference]
    public let outputDirectoryURL: URL
    public let candidateCount: Int
    public let settings: ImageGenerationSettings

    public init(
        prompt: String,
        references: [ImageGenerationReference],
        outputDirectoryURL: URL,
        candidateCount: Int = 1,
        settings: ImageGenerationSettings
    ) {
        self.prompt = prompt
        self.references = references
        self.outputDirectoryURL = outputDirectoryURL
        self.candidateCount = candidateCount
        self.settings = settings
    }
}

public struct ImageGenerationCandidate: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let fileURL: URL
    public let byteCount: Int64

    public init(id: UUID = UUID(), fileURL: URL, byteCount: Int64) {
        self.id = id
        self.fileURL = fileURL
        self.byteCount = byteCount
    }
}

public struct ImageGenerationResult: Equatable, Sendable {
    public let candidates: [ImageGenerationCandidate]
    public let providerID: String
    public let modelID: String
    public let helperProtocolVersion: Int
    public let requestedSize: ImagePixelSize

    public init(
        candidates: [ImageGenerationCandidate],
        providerID: String,
        modelID: String,
        helperProtocolVersion: Int,
        requestedSize: ImagePixelSize
    ) {
        self.candidates = candidates
        self.providerID = providerID
        self.modelID = modelID
        self.helperProtocolVersion = helperProtocolVersion
        self.requestedSize = requestedSize
    }
}

public struct ImageGenerationProgress: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case preparing
        case generating(candidate: Int, total: Int)
        case validating(candidate: Int, total: Int)
        case importing
        case completed(total: Int)
    }

    public let stage: Stage

    public init(stage: Stage) {
        self.stage = stage
    }
}

public protocol ImageProviderCredentialSource: Sendable {
    func isConfigured(providerID: String) async -> Bool
    func credential(providerID: String) async throws -> Data
}

public struct ImageGeneratorLaunchContext: Equatable, Sendable {
    public let provider: ImageProviderDescriptor
    public let helperURL: URL
    public let environment: [String: String]
    public let helperProtocolVersion: Int

    public init(
        provider: ImageProviderDescriptor,
        helperURL: URL,
        environment: [String: String],
        helperProtocolVersion: Int
    ) {
        self.provider = provider
        self.helperURL = helperURL
        self.environment = environment
        self.helperProtocolVersion = helperProtocolVersion
    }
}

public enum ImageGeneratorStatus: Equatable, Sendable {
    case helperUnavailable
    case helperIncompatible(reason: String)
    case providerNotConfigured(providerName: String)
    case ready(ImageGeneratorLaunchContext)
}

/// Safe credential diagnostics. The system message comes only from macOS's
/// status-code lookup, never from a credential value or provider response.
public enum ImageProviderCredentialError: Error, Equatable, Sendable {
    case notConfigured
    case keychainReadFailed(code: Int32, systemMessage: String)
    case invalidStoredCredential
}

public enum ImageGenerationError: Error, Equatable, Sendable {
    case generatorUnavailable(ImageGeneratorStatus)
    case credentialUnavailable(providerName: String)
    case credentialReadFailed(providerName: String, reason: ImageProviderCredentialError)
    case promptIsEmpty
    case promptTooLarge(maximumBytes: Int)
    case invalidCandidateCount(allowed: ClosedRange<Int>)
    case outputDirectoryInvalid
    case invalidReference(index: Int)
    case unsupportedReferenceCount(providerName: String, count: Int, maximum: Int)
    case unsupportedCharacterReferenceCount(providerName: String, count: Int, maximum: Int)
    case unsupportedAspectRatio(providerName: String, ratio: ImageGenerationAspectRatio)
    case processTimedOut(candidate: Int)
    case processOutputExceeded(candidate: Int)
    case couldNotLaunch(candidate: Int)
    case processFailed(candidate: Int, code: String)
    case missingOutput(candidate: Int)
    case invalidOutput(candidate: Int)
    case outputTooLarge(candidate: Int, maximumBytes: Int64)
    case cancelled
    case runAlreadyActive
}

extension ImageGenerationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .generatorUnavailable:
            "The selected image provider is not ready. Open Settings → Images for details."
        case let .credentialUnavailable(providerName):
            "Film Camp could not read the saved API key for \(providerName). The credential store returned an unexpected error. Try again or replace the key in Settings → Images."
        case let .credentialReadFailed(providerName, reason):
            switch reason {
            case .notConfigured:
                "No saved API key was found for \(providerName). Configure one in Settings → Images."
            case let .keychainReadFailed(code, systemMessage):
                "Film Camp could not read the saved API key for \(providerName) from Keychain (OSStatus \(code)): \(systemMessage)"
            case .invalidStoredCredential:
                "The saved API key for \(providerName) is empty or has an invalid format. Replace it in Settings → Images."
            }
        case .promptIsEmpty:
            "Enter an image prompt before generating."
        case let .promptTooLarge(maximumBytes):
            "The image prompt is larger than the supported \(maximumBytes)-byte limit."
        case let .invalidCandidateCount(allowed):
            "Choose between \(allowed.lowerBound) and \(allowed.upperBound) images."
        case .outputDirectoryInvalid:
            "The image generator cache directory is unavailable."
        case let .invalidReference(index):
            "Reference image \(index) is unavailable."
        case let .unsupportedReferenceCount(providerName, count, maximum):
            "\(providerName) accepts at most \(maximum) canonical references; this image requires \(count). Choose another provider in Settings."
        case let .unsupportedCharacterReferenceCount(providerName, count, maximum):
            "\(providerName) accepts at most \(maximum) character references; this image requires \(count). Choose another provider in Settings."
        case let .unsupportedAspectRatio(providerName, ratio):
            "\(providerName) does not support the required \(ratio.rawValue) composition. Choose another provider in Settings."
        case let .processTimedOut(candidate):
            "Image \(candidate) took too long to generate."
        case let .processOutputExceeded(candidate):
            "Image generator output exceeded the diagnostic limit while creating image \(candidate)."
        case let .couldNotLaunch(candidate):
            "The bundled image helper could not launch while creating image \(candidate)."
        case let .processFailed(candidate, code):
            "The provider could not create image \(candidate) (\(code)). Check the API key, billing, quota, and prompt, then try again."
        case let .missingOutput(candidate):
            "The image provider did not create image \(candidate)."
        case let .invalidOutput(candidate):
            "The image provider returned an invalid file for image \(candidate)."
        case let .outputTooLarge(candidate, maximumBytes):
            "Image \(candidate) exceeds the \(maximumBytes)-byte safety limit."
        case .cancelled:
            "Image generation was cancelled."
        case .runAlreadyActive:
            "An image generation run is already active."
        }
    }
}

public protocol ImageGenerating: Sendable {
    func progress() async -> AsyncStream<ImageGenerationProgress>
    func status() async -> ImageGeneratorStatus
    func generate(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult
    func cancel() async
}
