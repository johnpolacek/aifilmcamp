import FilmCore
import Foundation

/// What one `inferAssetManifest` run proposed (PHASE2_DESIGN §8.3).
///
/// The three channels are deliberately separate: variants are the model's grouping
/// judgment, `importantProps` is §3.4's prop judgment (a direct canonical-tier proposal),
/// and `inclusionSuggestions` are advisory overrides the run never applies.
public struct InferManifestResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let variants: [ProposedVariant]
    public let importantProps: [ProposedImportantProp]
    public let inclusionSuggestions: [ProposedInclusionSuggestion]

    public init(
        schemaVersion: Int = 1,
        variants: [ProposedVariant],
        importantProps: [ProposedImportantProp],
        inclusionSuggestions: [ProposedInclusionSuggestion]
    ) {
        self.schemaVersion = schemaVersion
        self.variants = variants
        self.importantProps = importantProps
        self.inclusionSuggestions = inclusionSuggestions
    }
}

/// One proposed variant requirement (§8.3).
///
/// Ids are **ours**, echoed from the §8.2 input — unlike extraction, where the model
/// returns surface-form names — so every reference is resolvable or the result is rejected.
public struct ProposedVariant: Codable, Equatable, Sendable {
    public let entityId: UUID
    /// The look alone — 'Office Outfit' — never entity-prefixed (§4.3).
    public let name: String
    public let reason: String
    /// Scenes the entity appears in **in a visible role** (§3.3).
    public let sceneOrdinals: [Int]
    public let basisStateIds: [UUID]
    public let basisEventIds: [UUID]
    public let basisAppearanceIds: [UUID]
    public let confidence: Double

    public init(
        entityId: UUID,
        name: String,
        reason: String,
        sceneOrdinals: [Int],
        basisStateIds: [UUID] = [],
        basisEventIds: [UUID] = [],
        basisAppearanceIds: [UUID] = [],
        confidence: Double
    ) {
        self.entityId = entityId
        self.name = name
        self.reason = reason
        self.sceneOrdinals = sceneOrdinals
        self.basisStateIds = basisStateIds
        self.basisEventIds = basisEventIds
        self.basisAppearanceIds = basisAppearanceIds
        self.confidence = confidence
    }
}

/// One prop the model deems production-important (§3.4, §8.3): apply turns it into the
/// prop's canonical reference-view requirement, `ai`/`proposed`, with its basis rows.
public struct ProposedImportantProp: Codable, Equatable, Sendable {
    public let entityId: UUID
    public let reason: String
    public let basisStateIds: [UUID]
    public let basisEventIds: [UUID]
    public let basisAppearanceIds: [UUID]
    public let confidence: Double

    public init(
        entityId: UUID,
        reason: String,
        basisStateIds: [UUID] = [],
        basisEventIds: [UUID] = [],
        basisAppearanceIds: [UUID] = [],
        confidence: Double
    ) {
        self.entityId = entityId
        self.reason = reason
        self.basisStateIds = basisStateIds
        self.basisEventIds = basisEventIds
        self.basisAppearanceIds = basisAppearanceIds
        self.confidence = confidence
    }
}

/// One advisory `manifest_inclusion` suggestion (§8.3, §8.5) — non-prop kinds only, since
/// props have the direct-proposal channel above.
public struct ProposedInclusionSuggestion: Codable, Equatable, Sendable {
    public enum Suggestion: String, Codable, Equatable, Sendable, CaseIterable {
        case promote
        case suppress
    }

    public let entityId: UUID
    public let suggestion: Suggestion
    public let reason: String
    public let confidence: Double

    public init(entityId: UUID, suggestion: Suggestion, reason: String, confidence: Double) {
        self.entityId = entityId
        self.suggestion = suggestion
        self.reason = reason
        self.confidence = confidence
    }

    /// The FilmCore shape §8.5 persists in the report. Plan 012 step 2's apply is its caller.
    public var inclusionSuggestion: ManifestInclusionSuggestion {
        ManifestInclusionSuggestion(
            entityID: entityId,
            direction: suggestion == .promote ? .promote : .suppress,
            reason: reason,
            confidence: confidence
        )
    }
}
