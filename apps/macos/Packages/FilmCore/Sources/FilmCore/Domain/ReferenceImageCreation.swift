import Foundation

/// One validated, run-scoped image selected outside the project bundle.
///
/// FilmCore is the only producer. Keeping the frozen bytes with their measured facts
/// prevents the source file from drifting between provider execution and candidate commit.
public struct ReferenceImageGenerationAttachment: Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let originalFileName: String
    public let data: Data
    public let sha256: String
    public let byteCount: Int
    public let entityKind: EntityKind

    public var fileExtension: String {
        (originalFileName as NSString).pathExtension.lowercased()
    }

    init(
        id: UUID = UUID(),
        originalFileName: String,
        data: Data,
        entityKind: EntityKind
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.data = data
        sha256 = data.sha256Hex
        byteCount = data.count
        self.entityKind = entityKind
    }
}

/// One canonical input image in a reference-image generation run.
public struct ReferenceImageGenerationDependency: Equatable, Hashable, Sendable, Identifiable {
    public let requirementID: UUID
    public let requirementName: String
    public let entityKind: EntityKind
    public let versionID: UUID
    public let sha256: String
    public let byteCount: Int
    public let relativePath: RelativeProjectPath
    /// The current reusable prompt for this canonical input, when one exists. Including
    /// it in the context makes prompt edits part of the same generation drift token as
    /// the approved image bytes.
    public let promptBody: String?

    public var id: UUID { requirementID }

    public init(
        requirementID: UUID,
        requirementName: String,
        entityKind: EntityKind,
        versionID: UUID,
        sha256: String,
        byteCount: Int,
        relativePath: RelativeProjectPath,
        promptBody: String? = nil
    ) {
        self.requirementID = requirementID
        self.requirementName = requirementName
        self.entityKind = entityKind
        self.versionID = versionID
        self.sha256 = sha256
        self.byteCount = byteCount
        self.relativePath = relativePath
        self.promptBody = promptBody
    }
}

/// How a successful human image edit participates in later image generation.
public enum VisualAmendmentScope: String, Codable, Equatable, Hashable, Sendable {
    case requirement
    case characterBundle = "character_bundle"
}

/// One human-authored edit in the active lineage of a currently approved image.
/// The generation run is immutable; deriving through current-version lineage keeps an
/// archived or undone branch from silently influencing new work.
public struct ReferenceVisualAmendment: Equatable, Hashable, Sendable, Identifiable {
    public let runID: UUID
    public let requirementID: UUID
    public let versionID: UUID
    public let instruction: String
    public let scope: VisualAmendmentScope
    public let createdAt: Date

    public var id: UUID { runID }

    public init(
        runID: UUID,
        requirementID: UUID,
        versionID: UUID,
        instruction: String,
        scope: VisualAmendmentScope,
        createdAt: Date
    ) {
        self.runID = runID
        self.requirementID = requirementID
        self.versionID = versionID
        self.instruction = instruction
        self.scope = scope
        self.createdAt = createdAt
    }
}

/// The amendment a successful generated edit will attach to its selected version's run.
public struct ImageGenerationVisualAmendment: Equatable, Hashable, Sendable {
    public let instruction: String
    public let scope: VisualAmendmentScope

    public init(instruction: String, scope: VisualAmendmentScope) {
        self.instruction = instruction
        self.scope = scope
    }
}

/// Provider-neutral, non-secret facts captured when a generated candidate set starts.
/// FilmCore validates and persists these alongside the existing prompt/dependency token.
public struct ImageGenerationCommitMetadata: Equatable, Hashable, Sendable {
    public let runID: UUID
    public let providerID: String
    public let modelID: String
    public let helperProtocolVersion: Int
    public let aspectRatio: String
    public let requestedWidth: Int
    public let requestedHeight: Int
    public let candidateCount: Int
    public let selectedCandidateIndex: Int
    public let attachments: [ReferenceImageGenerationAttachment]
    public let visualAmendment: ImageGenerationVisualAmendment?

    public init(
        runID: UUID = UUID(),
        providerID: String,
        modelID: String,
        helperProtocolVersion: Int,
        aspectRatio: String,
        requestedWidth: Int,
        requestedHeight: Int,
        candidateCount: Int,
        selectedCandidateIndex: Int,
        attachments: [ReferenceImageGenerationAttachment] = [],
        visualAmendment: ImageGenerationVisualAmendment? = nil
    ) {
        self.runID = runID
        self.providerID = providerID
        self.modelID = modelID
        self.helperProtocolVersion = helperProtocolVersion
        self.aspectRatio = aspectRatio
        self.requestedWidth = requestedWidth
        self.requestedHeight = requestedHeight
        self.candidateCount = candidateCount
        self.selectedCandidateIndex = selectedCandidateIndex
        self.attachments = attachments
        self.visualAmendment = visualAmendment
    }
}

public struct ImageGenerationReferenceProvenance: Equatable, Hashable, Sendable,
    Identifiable
{
    public let position: Int
    public let requirementID: UUID?
    public let versionID: UUID?
    public let sha256: String
    public let byteCount: Int
    public let entityKind: EntityKind

    public var id: Int { position }
}

public struct ImageGenerationProvenance: Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let requirementID: UUID
    public let promptID: UUID?
    public let providerID: String
    public let modelID: String
    public let helperProtocolVersion: Int
    public let promptBodySHA256: String
    public let aspectRatio: String
    public let requestedWidth: Int
    public let requestedHeight: Int
    public let candidateCount: Int
    public let selectedCandidateIndex: Int
    public let candidateIndex: Int
    public let createdAt: Date
    public let references: [ImageGenerationReferenceProvenance]
    public let visualAmendment: ImageGenerationVisualAmendment?
    public let appliedVisualAmendments: [ReferenceVisualAmendment]
}

/// The exact FilmCore state a local image-generation run was launched against.
///
/// The complete value is passed back at import and rebuilt inside the write transaction.
/// Equality is therefore the commit token: prompt edits, dependency approval changes, or a
/// newly installed target current all refuse the candidate set before any row lands.
public struct ReferenceImageGenerationContext: Equatable, Hashable, Sendable {
    public let requirementID: UUID
    public let promptID: UUID
    /// Digest of the saved reusable prompt. This is the drift guard even when a run uses
    /// a one-off edit instruction.
    public let sourcePromptBodySHA256: String
    /// Digest of the exact text sent for this run and persisted in generation provenance.
    public let promptBodySHA256: String
    public let expectedCurrentVersionID: UUID?
    public let includesCurrentImage: Bool
    public let tier: AssetRequirementTier
    public let entityKind: EntityKind
    public let orderedDependencies: [ReferenceImageGenerationDependency]
    /// Human edits active through the currently approved character-bundle lineage, oldest
    /// to newest. Equality makes the entire ordered chain part of the commit token.
    public let activeVisualAmendments: [ReferenceVisualAmendment]
    /// FilmCore's exact generation-gate sentence, or `nil` when generation is allowed.
    public let refusalReason: String?

    public init(
        requirementID: UUID,
        promptID: UUID,
        sourcePromptBodySHA256: String,
        promptBodySHA256: String,
        expectedCurrentVersionID: UUID?,
        includesCurrentImage: Bool,
        tier: AssetRequirementTier,
        entityKind: EntityKind,
        orderedDependencies: [ReferenceImageGenerationDependency],
        activeVisualAmendments: [ReferenceVisualAmendment] = [],
        refusalReason: String?
    ) {
        self.requirementID = requirementID
        self.promptID = promptID
        self.sourcePromptBodySHA256 = sourcePromptBodySHA256
        self.promptBodySHA256 = promptBodySHA256
        self.expectedCurrentVersionID = expectedCurrentVersionID
        self.includesCurrentImage = includesCurrentImage
        self.tier = tier
        self.entityKind = entityKind
        self.orderedDependencies = orderedDependencies
        self.activeVisualAmendments = activeVisualAmendments
        self.refusalReason = refusalReason
    }

    /// Proves that presentation is about to send the exact run prompt represented by this
    /// commit token—saved base prompt plus visual direction, or a one-off edit delta.
    public func matchesPromptBody(_ body: String) -> Bool {
        Data(body.utf8).sha256Hex == promptBodySHA256
    }
}

/// One dependency's verified bytes, read once through FilmCore's no-follow containment
/// door. Presentation may copy these bytes into a disposable generator job directory;
/// the generator never opens canonical project media directly.
public struct ReferenceImageGenerationInput: Equatable, Sendable, Identifiable {
    public let requirementID: UUID
    public let entityKind: EntityKind
    public let fileExtension: String
    public let data: Data

    public var id: UUID { requirementID }

    public init(
        requirementID: UUID,
        entityKind: EntityKind,
        fileExtension: String,
        data: Data
    ) {
        self.requirementID = requirementID
        self.entityKind = entityKind
        self.fileExtension = fileExtension
        self.data = data
    }
}

/// One archived image group for a reference in a scene's deterministic reference plan.
///
/// `versions` contains only `needs_review` rows, newest first. Rejected versions remain
/// rejected history and approved versions remain on the primary reference card.
public struct SceneReferenceArchive: Equatable, Sendable, Identifiable {
    public let requirementID: UUID
    public let requirementName: String
    public let entityName: String
    public let `class`: ReferenceClass
    public let versions: [AssetVersion]

    public var id: UUID { requirementID }

    public init(
        requirementID: UUID,
        requirementName: String,
        entityName: String,
        class: ReferenceClass,
        versions: [AssetVersion]
    ) {
        self.requirementID = requirementID
        self.requirementName = requirementName
        self.entityName = entityName
        self.class = `class`
        self.versions = versions
    }
}

/// The canonical facts FilmCore accepted for one generated candidate.
public struct GeneratedCandidateImport: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let versionNumber: Int
    public let relativePath: RelativeProjectPath
    public let sha256: String
    public let byteCount: Int
    public let format: ImageFormat
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let isCurrent: Bool

    public init(
        id: UUID,
        versionNumber: Int,
        relativePath: RelativeProjectPath,
        sha256: String,
        byteCount: Int,
        format: ImageFormat,
        pixelWidth: Int,
        pixelHeight: Int,
        isCurrent: Bool
    ) {
        self.id = id
        self.versionNumber = versionNumber
        self.relativePath = relativePath
        self.sha256 = sha256
        self.byteCount = byteCount
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isCurrent = isCurrent
    }
}

/// One all-or-nothing import of a generated candidate set.
public struct GeneratedCandidateImportSummary: Equatable, Sendable {
    public let entry: JournalEntry
    public let assetID: UUID
    public let promptID: UUID
    public let selectedVersionID: UUID
    public let candidates: [GeneratedCandidateImport]

    public init(
        entry: JournalEntry,
        assetID: UUID,
        promptID: UUID,
        selectedVersionID: UUID,
        candidates: [GeneratedCandidateImport]
    ) {
        self.entry = entry
        self.assetID = assetID
        self.promptID = promptID
        self.selectedVersionID = selectedVersionID
        self.candidates = candidates
    }
}
