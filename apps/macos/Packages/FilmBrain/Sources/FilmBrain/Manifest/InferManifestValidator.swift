import FilmCore
import Foundation

/// Why a manifest-inference result was rejected (PHASE2_DESIGN §8.3).
///
/// The vocabulary is extraction's, extended: `dangling_entity_reference` keeps its Phase 1
/// spelling because it means the same thing, and every manifest-specific rule gets its own
/// code so a rejection names the predicate that failed rather than a generic "invalid".
public enum ManifestSemanticCode: String, Equatable, Sendable {
    case wrongSchemaVersion = "wrong_schema_version"
    case controlCharacter = "control_character"
    case invalidConfidence = "invalid_confidence"
    /// An id that resolves to no input record at all — including an unparseable one.
    case danglingEntityReference = "dangling_entity_reference"
    /// A basis id that is not one of *that entity's* input rows.
    case danglingBasisReference = "dangling_basis_reference"
    /// A proposal against an entity the input carries only in `borderline[]`.
    case borderlineEntityReference = "borderline_entity_reference"
    /// A proposal against an entity whose input record carries `manifestInclusion = 'never'`.
    case suppressedEntityReference = "suppressed_entity_reference"
    /// A claimed scene the entity does not appear in *in a visible role*.
    case sceneNotVisible = "scene_not_visible"
    /// A cited state whose range misses every claimed scene, or a cited appearance outside
    /// them.
    case basisSceneMismatch = "basis_scene_mismatch"
    case emptyName = "empty_name"
    case duplicateVariantName = "duplicate_variant_name"
    case duplicateImportantProp = "duplicate_important_prop"
    case nonPropImportantProp = "non_prop_important_prop"
    /// A prop whose kind has no **enabled** `reference` template entry in the input; apply
    /// never resurrects a disabled entry.
    case missingReferenceTemplateEntry = "missing_reference_template_entry"
    /// `promote` on a qualifying entity, or `suppress` on a borderline one.
    case invalidSuggestionDirection = "invalid_suggestion_direction"
    /// A suggestion about a prop — props have their own channel (§3.4).
    case propInclusionSuggestion = "prop_inclusion_suggestion"
}

enum ManifestSemanticValidation {
    static func reject(_ code: ManifestSemanticCode) -> StructuredValidationFailure {
        StructuredResultValidator.semanticViolation(code.rawValue)
    }

    /// Control characters are refused with extraction's own predicate and spelling.
    static func validateText(_ values: String...) throws {
        for value in values where value.unicodeScalars.contains(where: { $0.value < 0x20 }) {
            throw reject(.controlCharacter)
        }
    }

    static func validateConfidence(_ confidence: Double) throws {
        guard confidence.isFinite, (0 ... 1).contains(confidence) else {
            throw reject(.invalidConfidence)
        }
    }

    static func normalized(_ value: String) -> String {
        EntityNormalization.normalize(value)
    }
}

/// Every §8.3 semantic rule, checked against the §8.2 input the run was launched from
/// (PHASE2_DESIGN §8.3; Plan 012 contract A).
///
/// Versioned like its Phase 1 peers. The rules exist because the model's output is
/// untrusted *structurally and semantically*: the schema can say "a string", only this type
/// can say "an id of an entity that is actually in the input, in a scene it is actually
/// visible in, citing a state that actually overlaps that scene".
///
/// What is deliberately **not** here: collisions with rows already in the project. Those
/// are apply's business (§8.4), because the project can change while the model thinks —
/// which §8.4 step 0's digest guard, not this validator, is the answer to.
public struct InferManifestValidator: Sendable {
    public static let version = 1

    private let structural = StructuredResultValidator()
    /// Full records, by id — the only pool a variant or prop proposal may name.
    private let entities: [UUID: ManifestInputEntity]
    /// The compact pool, by id — the only pool `promote` may name.
    private let borderline: [UUID: ManifestInputBorderlineEntity]
    /// Per entity: its own state ids, event ids, and appearances by id.
    private let stateRanges: [UUID: [UUID: ClosedRange<Int>]]
    private let eventIDs: [UUID: Set<UUID>]
    private let appearanceOrdinals: [UUID: [UUID: Int]]
    /// Per entity: the scene ordinals it appears in, in a **visible** role (§3.3).
    private let visibleOrdinals: [UUID: Set<Int>]
    /// Entity kinds whose template holds an **enabled** `reference` entry.
    private let kindsWithEnabledReference: Set<EntityKind>

    /// The frozen template `code` an `importantProps` proposal fills (§3.2, §8.4 step 1).
    static let referenceTemplateCode = "reference"

    public init(input: ManifestInput) {
        var entities: [UUID: ManifestInputEntity] = [:]
        var stateRanges: [UUID: [UUID: ClosedRange<Int>]] = [:]
        var eventIDs: [UUID: Set<UUID>] = [:]
        var appearanceOrdinals: [UUID: [UUID: Int]] = [:]
        var visibleOrdinals: [UUID: Set<Int>] = [:]
        for entity in input.entities {
            entities[entity.id] = entity
            // An open-ended state runs to the end of the script (§8.2), so its range is
            // unbounded above rather than a point at its start.
            stateRanges[entity.id] = Dictionary(
                uniqueKeysWithValues: entity.states.map {
                    ($0.id, $0.startOrdinal ... max($0.startOrdinal, $0.endOrdinal ?? Int.max))
                }
            )
            eventIDs[entity.id] = Set(entity.events.map(\.id))
            appearanceOrdinals[entity.id] = Dictionary(
                entity.appearances.map { ($0.id, $0.sceneOrdinal) },
                uniquingKeysWith: { first, _ in first }
            )
            visibleOrdinals[entity.id] = Set(entity.appearances.map(\.sceneOrdinal))
        }
        self.entities = entities
        self.stateRanges = stateRanges
        self.eventIDs = eventIDs
        self.appearanceOrdinals = appearanceOrdinals
        self.visibleOrdinals = visibleOrdinals
        self.borderline = Dictionary(
            input.borderline.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.kindsWithEnabledReference = Set(
            input.template
                .filter { $0.isEnabled && $0.code == Self.referenceTemplateCode }
                .map(\.entityKind)
        )
    }

    public func validate(resultFileAt url: URL) throws -> InferManifestResult {
        let data = try structural.validatedData(resultFileAt: url, schemaURL: InferManifestSchema.url)
        return try validate(data: data)
    }

    public func validate(data: Data) throws -> InferManifestResult {
        try structural.validate(data: data, schemaURL: InferManifestSchema.url)
        let result: InferManifestResult
        do {
            result = try JSONDecoder().decode(InferManifestResult.self, from: data)
        } catch {
            // The schema already accepted the shape, so the only decode failure left is an
            // id that is not an identifier at all — a reference to nothing.
            throw ManifestSemanticValidation.reject(.danglingEntityReference)
        }
        guard result.schemaVersion == InferManifestSchema.version else {
            throw ManifestSemanticValidation.reject(.wrongSchemaVersion)
        }
        try validateVariants(result.variants)
        try validateImportantProps(result.importantProps)
        try validateSuggestions(result.inclusionSuggestions)
        return result
    }

    // MARK: - Variants

    private func validateVariants(_ variants: [ProposedVariant]) throws {
        // Uniqueness is **within the proposal**, per entity, after `EntityNormalization`;
        // collisions with existing rows are an apply concern (§8.4).
        var names: Set<String> = []
        for variant in variants {
            let entity = try resolveProposalTarget(variant.entityId)
            try ManifestSemanticValidation.validateText(variant.name, variant.reason)
            try ManifestSemanticValidation.validateConfidence(variant.confidence)
            let normalized = ManifestSemanticValidation.normalized(variant.name)
            guard !normalized.isEmpty else {
                throw ManifestSemanticValidation.reject(.emptyName)
            }
            guard names.insert("\(entity.id.uuidString):\(normalized)").inserted else {
                throw ManifestSemanticValidation.reject(.duplicateVariantName)
            }

            // §3.3's visible-role bound: a wardrobe variant cannot claim a scene where the
            // character is only discussed.
            let visible = visibleOrdinals[entity.id] ?? []
            let claimed = Set(variant.sceneOrdinals)
            guard claimed.isSubset(of: visible) else {
                throw ManifestSemanticValidation.reject(.sceneNotVisible)
            }

            try validateBasis(
                entityID: entity.id,
                stateIDs: variant.basisStateIds,
                eventIDs: variant.basisEventIds,
                appearanceIDs: variant.basisAppearanceIds,
                claimedScenes: claimed
            )
        }
    }

    // MARK: - Important props (§3.4)

    private func validateImportantProps(_ props: [ProposedImportantProp]) throws {
        var seen: Set<UUID> = []
        for prop in props {
            let entity = try resolveProposalTarget(prop.entityId)
            guard entity.kind == .prop else {
                throw ManifestSemanticValidation.reject(.nonPropImportantProp)
            }
            guard seen.insert(entity.id).inserted else {
                throw ManifestSemanticValidation.reject(.duplicateImportantProp)
            }
            guard kindsWithEnabledReference.contains(entity.kind) else {
                throw ManifestSemanticValidation.reject(.missingReferenceTemplateEntry)
            }
            try ManifestSemanticValidation.validateText(prop.reason)
            try ManifestSemanticValidation.validateConfidence(prop.confidence)
            // No scene bound: a prop proposal is the entity's canonical reference view, and
            // canonical scene links stay derived (§5.2).
            try validateBasis(
                entityID: entity.id,
                stateIDs: prop.basisStateIds,
                eventIDs: prop.basisEventIds,
                appearanceIDs: prop.basisAppearanceIds,
                claimedScenes: nil
            )
        }
    }

    // MARK: - Inclusion suggestions

    private func validateSuggestions(_ suggestions: [ProposedInclusionSuggestion]) throws {
        for suggestion in suggestions {
            try ManifestSemanticValidation.validateText(suggestion.reason)
            try ManifestSemanticValidation.validateConfidence(suggestion.confidence)
            let kind: EntityKind
            let isBorderline: Bool
            if let entity = entities[suggestion.entityId] {
                kind = entity.kind
                isBorderline = false
            } else if let entity = borderline[suggestion.entityId] {
                kind = entity.kind
                isBorderline = true
            } else {
                throw ManifestSemanticValidation.reject(.danglingEntityReference)
            }
            // Props have the direct-proposal channel; suggestions are for the kinds §3.3's
            // rule governs.
            guard kind != .prop else {
                throw ManifestSemanticValidation.reject(.propInclusionSuggestion)
            }
            switch suggestion.suggestion {
            case .promote where !isBorderline,
                 .suppress where isBorderline:
                throw ManifestSemanticValidation.reject(.invalidSuggestionDirection)
            case .promote, .suppress:
                continue
            }
        }
    }

    // MARK: - Shared rules

    /// The pool a variant or prop proposal may name: `entities[]`, never `borderline[]`,
    /// and never a `'never'` record (§8.3; apply re-checks the override in-transaction).
    private func resolveProposalTarget(_ id: UUID) throws -> ManifestInputEntity {
        guard let entity = entities[id] else {
            throw ManifestSemanticValidation.reject(
                borderline[id] == nil ? .danglingEntityReference : .borderlineEntityReference
            )
        }
        guard entity.manifestInclusion != .never else {
            throw ManifestSemanticValidation.reject(.suppressedEntityReference)
        }
        return entity
    }

    /// Basis resolution (§8.3): every id must be one of **that entity's** rows; a cited
    /// state's scene range must overlap at least one claimed scene, and a cited appearance
    /// must lie in them. Events are entity-scoped only — a scene-14 injury legitimately
    /// justifies a scenes-15-20 variant.
    private func validateBasis(
        entityID: UUID,
        stateIDs: [UUID],
        eventIDs proposedEventIDs: [UUID],
        appearanceIDs: [UUID],
        claimedScenes: Set<Int>?
    ) throws {
        let ranges = stateRanges[entityID] ?? [:]
        for stateID in stateIDs {
            guard let range = ranges[stateID] else {
                throw ManifestSemanticValidation.reject(.danglingBasisReference)
            }
            if let claimedScenes {
                guard claimedScenes.contains(where: range.contains) else {
                    throw ManifestSemanticValidation.reject(.basisSceneMismatch)
                }
            }
        }
        let events = eventIDs[entityID] ?? []
        for eventID in proposedEventIDs where !events.contains(eventID) {
            throw ManifestSemanticValidation.reject(.danglingBasisReference)
        }
        let ordinals = appearanceOrdinals[entityID] ?? [:]
        for appearanceID in appearanceIDs {
            guard let ordinal = ordinals[appearanceID] else {
                throw ManifestSemanticValidation.reject(.danglingBasisReference)
            }
            if let claimedScenes, !claimedScenes.contains(ordinal) {
                throw ManifestSemanticValidation.reject(.basisSceneMismatch)
            }
        }
    }
}
