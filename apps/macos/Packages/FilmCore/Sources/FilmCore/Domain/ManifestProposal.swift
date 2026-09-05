import Foundation

/// The basis citations one manifest proposal rests on (PHASE2_DESIGN §8.3, §4.3).
///
/// Basis rows are **immutable citations** with reduced provenance (§3.7): they are created
/// with their requirement, never edited, and removed with it. The three id families are
/// carried apart rather than as one polymorphic list because that is how
/// `asset_requirement_basis.subject_kind` stores them, and because the validator resolves
/// each family against a different input collection.
public struct ProposedRequirementBasis: Codable, Equatable, Hashable, Sendable {
    public let stateIDs: [UUID]
    public let eventIDs: [UUID]
    public let appearanceIDs: [UUID]

    public init(stateIDs: [UUID] = [], eventIDs: [UUID] = [], appearanceIDs: [UUID] = []) {
        self.stateIDs = stateIDs
        self.eventIDs = eventIDs
        self.appearanceIDs = appearanceIDs
    }

    /// The `(subject_kind, subject_id)` pairs, in the stable order apply writes them.
    var subjects: [SubjectRef] {
        stateIDs.map { SubjectRef(kind: .state, id: $0) }
            + eventIDs.map { SubjectRef(kind: .event, id: $0) }
            + appearanceIDs.map { SubjectRef(kind: .appearance, id: $0) }
    }

    public var isEmpty: Bool {
        stateIDs.isEmpty && eventIDs.isEmpty && appearanceIDs.isEmpty
    }
}

/// One proposed **variant** requirement (§8.3): the model's grouping judgment.
public struct ProposedVariantRequirement: Codable, Equatable, Hashable, Sendable {
    public let entityID: UUID
    /// The look alone — 'Office Outfit' — never entity-prefixed (§4.3).
    public let name: String
    public let reason: String
    /// Scenes the entity appears in **in a visible role** (§3.3), as ordinals of the run's
    /// pinned script; apply resolves them to ids inside its transaction (§8.4 step 5).
    public let sceneOrdinals: [Int]
    public let basis: ProposedRequirementBasis
    public let confidence: Double

    public init(
        entityID: UUID,
        name: String,
        reason: String,
        sceneOrdinals: [Int],
        basis: ProposedRequirementBasis = ProposedRequirementBasis(),
        confidence: Double
    ) {
        self.entityID = entityID
        self.name = name
        self.reason = reason
        self.sceneOrdinals = sceneOrdinals
        self.basis = basis
        self.confidence = confidence
    }
}

/// One prop the model deems production-important (§3.4, §8.3).
///
/// Apply turns it into that prop's canonical reference-view requirement — `ai`/`proposed`,
/// canonical tier, named by the enabled `reference` template entry — with its basis rows.
/// Scene links stay derived, as for every canonical requirement (§5.2).
public struct ProposedPropRequirement: Codable, Equatable, Hashable, Sendable {
    public let entityID: UUID
    public let reason: String
    public let basis: ProposedRequirementBasis
    public let confidence: Double

    public init(
        entityID: UUID,
        reason: String,
        basis: ProposedRequirementBasis = ProposedRequirementBasis(),
        confidence: Double
    ) {
        self.entityID = entityID
        self.reason = reason
        self.basis = basis
        self.confidence = confidence
    }
}

public enum ManifestProposalError: Error, Equatable, Sendable {
    case invalidScriptHash
    case invalidName
    case invalidProposal
}

/// The validated payload FilmBrain hands FilmCore for §8.4's apply (Plan 012 contract C).
///
/// The peer of `ExtractionProposal`, and deliberately its twin: a FilmCore value type with
/// a **throwing** init that re-checks lengths and confidence, so an unvalidated result can
/// never reach the applier even if a future caller skips `InferManifestValidator`. What it
/// does *not* re-check is anything about the project — §8.4 step 0's digest guard is the
/// answer to a project that moved under the run, and it runs inside the apply transaction.
public struct ManifestProposal: Codable, Equatable, Sendable {
    /// The longest reason text apply will store, in UTF-16 units — the analogue of
    /// `ExtractionProposal`'s 240-unit quote bound.
    public static let maximumReasonUTF16 = 1_000
    /// The longest variant name apply will store, in UTF-16 units.
    public static let maximumNameUTF16 = 200

    public let scriptID: UUID
    public let scriptSHA256: String
    public let settings: ManifestSettings
    public let variants: [ProposedVariantRequirement]
    public let importantProps: [ProposedPropRequirement]
    /// Persisted in the report and **never applied** (§8.4 step 4).
    public let inclusionSuggestions: [ManifestInclusionSuggestion]

    public init(
        scriptID: UUID,
        scriptSHA256: String,
        settings: ManifestSettings = ManifestSettings(),
        variants: [ProposedVariantRequirement] = [],
        importantProps: [ProposedPropRequirement] = [],
        inclusionSuggestions: [ManifestInclusionSuggestion] = []
    ) throws {
        guard !scriptSHA256.isEmpty else { throw ManifestProposalError.invalidScriptHash }
        guard variants.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.name.utf16.count <= Self.maximumNameUTF16
        }) else { throw ManifestProposalError.invalidName }
        let confidences = variants.map(\.confidence) + importantProps.map(\.confidence)
            + inclusionSuggestions.compactMap(\.confidence)
        guard confidences.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else {
            throw ManifestProposalError.invalidProposal
        }
        let reasons = variants.map(\.reason) + importantProps.map(\.reason)
            + inclusionSuggestions.map(\.reason)
        guard reasons.allSatisfy({ $0.utf16.count <= Self.maximumReasonUTF16 }) else {
            throw ManifestProposalError.invalidProposal
        }
        self.scriptID = scriptID
        self.scriptSHA256 = scriptSHA256
        self.settings = settings
        self.variants = variants
        self.importantProps = importantProps
        self.inclusionSuggestions = inclusionSuggestions
    }
}
