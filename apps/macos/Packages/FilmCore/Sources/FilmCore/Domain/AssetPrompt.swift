import Foundation

/// The prompt record of one requirement (PHASE3_DESIGN §4.3, §4.4; Plan 013).
///
/// A prompt is **derived, disposable output** (§3.1): it never writes back into the
/// canonical facts it was computed from, and regeneration supersedes by history — a new
/// row at the next `prompt_number`, the previous rows untouched (§3.2). The current
/// prompt of a requirement is the row with the highest `prompt_number`; there is no
/// `is_current` flag to flip.
public struct AssetPrompt: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let requirementID: UUID
    /// 1-based, assigned max + 1 in-transaction; gaps are legal after deletes.
    public let promptNumber: Int
    public let body: String
    /// The skill's routing choice, opaque to the app (§3.5); `''` for a human-written
    /// prompt.
    public let targetModel: String
    /// Generation-settings prose from the skill (§8.3); `''` when none.
    public let guidance: String
    /// Descriptor id; `''` for a human-written prompt (the §4.3 CHECKs bind the triple).
    public let skillID: String
    /// Descriptor-relative; never an absolute cache path (§3.5).
    public let skillEntryPath: String
    public let skillEntrySHA256: String
    /// `AssetPromptInput.digest` (§3.4): SHA-256 of the §8.2 rendered JSON.
    public let inputDigest: String
    /// `AssetPromptInputBuilder.schemaVersion` at attach; a mismatch reads stale (§3.4).
    public let inputFormatVersion: Int
    public let provenance: Provenance

    public init(
        id: UUID,
        projectID: UUID,
        requirementID: UUID,
        promptNumber: Int,
        body: String,
        targetModel: String,
        guidance: String,
        skillID: String,
        skillEntryPath: String,
        skillEntrySHA256: String,
        inputDigest: String,
        inputFormatVersion: Int,
        provenance: Provenance
    ) {
        self.id = id
        self.projectID = projectID
        self.requirementID = requirementID
        self.promptNumber = promptNumber
        self.body = body
        self.targetModel = targetModel
        self.guidance = guidance
        self.skillID = skillID
        self.skillEntryPath = skillEntryPath
        self.skillEntrySHA256 = skillEntrySHA256
        self.inputDigest = inputDigest
        self.inputFormatVersion = inputFormatVersion
        self.provenance = provenance
    }
}

/// One immutable citation of what a prompt was built from (PHASE3_DESIGN §3.3, §4.3) —
/// basis-row style: created with its prompt, never edited, removed with it, excluded from
/// review. The planned dependencies keep evolving; citations are the historical record.
public struct AssetPromptReference: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let promptID: UUID
    /// The `@Image` number, 1-based and dense over the satisfied subset (§3.3).
    public let position: Int
    /// SET NULL on delete; `sha256`/`displayName` are the record when the referent is gone.
    public let requirementID: UUID?
    public let versionID: UUID?
    public let `class`: ReferenceClass
    /// §3.3's derived role/exclusion/fidelity as sent — recorded history, stored nowhere else.
    public let role: String
    public let exclusion: String
    public let fidelity: ReferenceFidelity
    /// The referenced version's bytes at build time.
    public let sha256: String
    /// "Sarah Morgan — Face Closeup" at build time.
    public let displayName: String
    public let source: FactSource
    public let jobID: UUID?
    public let createdAt: Date

    public init(
        id: UUID,
        promptID: UUID,
        position: Int,
        requirementID: UUID?,
        versionID: UUID?,
        class: ReferenceClass,
        role: String,
        exclusion: String,
        fidelity: ReferenceFidelity,
        sha256: String,
        displayName: String,
        source: FactSource,
        jobID: UUID?,
        createdAt: Date
    ) {
        self.id = id
        self.promptID = promptID
        self.position = position
        self.requirementID = requirementID
        self.versionID = versionID
        self.class = `class`
        self.role = role
        self.exclusion = exclusion
        self.fidelity = fidelity
        self.sha256 = sha256
        self.displayName = displayName
        self.source = source
        self.jobID = jobID
        self.createdAt = createdAt
    }
}

/// What kind of reference a dependency's target is (PHASE3_DESIGN §3.3) — derived from
/// the target requirement, never stored.
public enum ReferenceClass: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case identity
    case look
    case location
    case prop

    /// §3.3's fixed ordering convention: class rank first, for both named collections and
    /// Phase 5's scene packages.
    public var rank: Int {
        switch self {
        case .identity: 0
        case .look: 1
        case .location: 2
        case .prop: 3
        }
    }
}

/// How strongly a reference constrains the generated image (PHASE3_DESIGN §3.3). Raw
/// values are §4.3's citation-row CHECK encodings — frozen snake_case spellings that
/// appear nowhere in the vendored payload (the skill's prose hyphenates them).
public enum ReferenceFidelity: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case fullPreserve = "full_preserve"
    case partialPreserve = "partial_preserve"
    case attributeTransfer = "attribute_transfer"
    case looseGuide = "loose_guide"
}

/// The derived role/exclusion/fidelity triple (PHASE3_DESIGN §3.3) — computed at render
/// time by `ReferenceAttributeRules`, recorded immutably on citation rows, stored nowhere
/// else, editable nowhere (owner-decided 2026-08-22).
public struct ReferenceAttributes: Codable, Equatable, Hashable, Sendable {
    public var role: String
    public var exclusion: String
    public var fidelity: ReferenceFidelity

    public init(role: String, exclusion: String, fidelity: ReferenceFidelity) {
        self.role = role
        self.exclusion = exclusion
        self.fidelity = fidelity
    }
}

/// PHASE3_DESIGN §3.3's derivation tables as one pure function — the single source for
/// the builder (§8.2), the reads (§7.5), and Phase 5.
///
/// The function takes every input its tables consume and nothing else:
/// `AssetRequirement` carries `entityID` alone, so the entity *kinds* the class derivation
/// reads and the display *names* the role templates interpolates are passed in, never
/// re-read here. The outputs are digest input through §8.2's `dependencies[]` and
/// `references[]`, so a wording change in these tables is a renderer change and bumps
/// `AssetPromptInputBuilder.schemaVersion`.
public enum ReferenceAttributeRules {
    /// The class a requirement would carry as a reference target (§3.3): character and
    /// creature canonicals are identities, their variants are looks, and location and
    /// prop-family requirements carry their own class at either tier.
    public static func referenceClass(
        tier: AssetRequirementTier,
        entityKind: EntityKind
    ) -> ReferenceClass {
        switch entityKind {
        case .character, .creature:
            tier == .canonical ? .identity : .look
        case .location:
            .location
        case .prop, .vehicle, .object:
            .prop
        }
    }

    /// §3.3's three tables, byte for byte.
    ///
    /// - Parameters:
    ///   - owningTier / owningEntityKind / owningEntityName: the requirement the prompt is
    ///     being built for, and its entity.
    ///   - targetTier / targetEntityKind / targetEntityName: the referenced requirement's
    ///     side.
    ///   - targetRequirementName: the target requirement's name (`<requirement>`).
    ///   - targetTemplateCode: the target's template code (`''` for variants).
    public static func attributes(
        owningTier: AssetRequirementTier,
        owningEntityKind: EntityKind,
        owningEntityName: String,
        targetTier: AssetRequirementTier,
        targetEntityKind: EntityKind,
        targetEntityName: String,
        targetRequirementName: String,
        targetTemplateCode: String
    ) -> ReferenceAttributes {
        let ownerClass = referenceClass(tier: owningTier, entityKind: owningEntityKind)
        let targetClass = referenceClass(tier: targetTier, entityKind: targetEntityKind)

        // Fidelity first: the attribute-transfer rows override the role line, so the
        // matrix has to be consulted before the role table speaks.
        let fidelity: ReferenceFidelity
        switch targetClass {
        case .identity:
            // An establishing plate or prop sheet citing a character sheet borrows the
            // look, never the face.
            fidelity = ownerClass == .identity || ownerClass == .look
                ? .fullPreserve : .looseGuide
        case .look:
            fidelity = ownerClass == .look ? .attributeTransfer : .partialPreserve
        case .location:
            fidelity = ownerClass == .location ? .partialPreserve : .looseGuide
        case .prop:
            fidelity = ownerClass == .look ? .attributeTransfer : .fullPreserve
        }

        let role: String
        if fidelity == .attributeTransfer {
            // The attribute-transfer target rule: the transfer target is always the
            // owning requirement's entity, named in the role line.
            role = "transfers the \(targetRequirementName) onto \(owningEntityName)"
        } else {
            switch targetClass {
            case .identity:
                role = "defines \(targetEntityName)'s \(identityRoleNoun(templateCode: targetTemplateCode))"
            case .look:
                role = "defines the \(targetRequirementName) look"
            case .location:
                role = "defines the \(targetRequirementName) location"
            case .prop:
                role = "defines the \(targetRequirementName) prop"
            }
        }

        // Exclusion boilerplate follows the vendored sheet-construction law: plain grey
        // background sheets, the background never signal — except locations, which *are*
        // their background.
        let exclusion = targetClass == .location ? "" : "do not reuse the background"

        return ReferenceAttributes(role: role, exclusion: exclusion, fidelity: fidelity)
    }

    /// Scene generation narrows canonical sheets to the visual attributes that may enter
    /// a moving shot. This is deliberately separate from `attributes`, whose dependency
    /// semantics also serve asset-to-asset generation. Every scene material receives a
    /// concrete exclusion so the Seedance declaration is complete and sheet/plate
    /// contamination cannot masquerade as creative direction.
    public static func sceneAttributes(
        targetTier: AssetRequirementTier,
        targetEntityKind: EntityKind,
        targetEntityName: String,
        targetRequirementName: String,
        targetTemplateCode: String
    ) -> ReferenceAttributes {
        let targetClass = referenceClass(tier: targetTier, entityKind: targetEntityKind)

        switch (targetClass, targetTemplateCode) {
        case (.identity, "face_closeup"):
            return ReferenceAttributes(
                role: "defines \(targetEntityName)'s face, head, and hairstyle",
                exclusion: "do not reuse the portrait crop or background",
                fidelity: .fullPreserve
            )
        case (.identity, "full_body"), (.look, "full_body"):
            return ReferenceAttributes(
                role: "defines \(targetEntityName)'s clothed physique, wardrobe, and rear hairstyle",
                exclusion: "do not reproduce the reference-sheet layout, extra turnaround figure, crop, or background",
                fidelity: .partialPreserve
            )
        case (.location, _):
            return ReferenceAttributes(
                role: "defines the \(targetRequirementName) location",
                exclusion: "do not reuse people, readable text, logos, or transient screen content",
                fidelity: .partialPreserve
            )
        case (.prop, _) where isScreenContentReference(targetRequirementName):
            return ReferenceAttributes(
                role: "defines the live screen content for \(targetRequirementName)",
                exclusion: "do not reuse the source as the room background or reproduce its broadcast logo, ticker, headline text, or other interface graphics",
                fidelity: .partialPreserve
            )
        case (.prop, _):
            return ReferenceAttributes(
                role: "defines the \(targetRequirementName) prop",
                exclusion: "do not reuse the reference-sheet layout or background",
                fidelity: .fullPreserve
            )
        default:
            let base = attributes(
                owningTier: targetTier,
                owningEntityKind: targetEntityKind,
                owningEntityName: targetEntityName,
                targetTier: targetTier,
                targetEntityKind: targetEntityKind,
                targetEntityName: targetEntityName,
                targetRequirementName: targetRequirementName,
                targetTemplateCode: targetTemplateCode
            )
            return ReferenceAttributes(
                role: base.role,
                exclusion: base.exclusion.isEmpty
                    ? "do not reuse incidental subjects, readable text, logos, or transient screen content"
                    : base.exclusion,
                fidelity: base.fidelity
            )
        }
    }

    /// A human-authored scene-reference name is the semantic contract for direct uploads.
    /// Requiring both a display noun and a content noun avoids treating an ordinary prop
    /// whose name merely happens to contain "screen" as replacement screen imagery.
    private static func isScreenContentReference(_ requirementName: String) -> Bool {
        let words = Set(
            requirementName
                .lowercased()
                .split(whereSeparator: { $0.isLetter == false })
                .map(String.init)
        )
        let displayWords: Set<String> = ["screen", "display", "monitor"]
        let contentWords: Set<String> = ["feed", "footage", "content", "image", "video"]
        return words.isDisjoint(with: displayWords) == false
            && words.isDisjoint(with: contentWords) == false
    }

    /// The identity role's noun: the three template codes with dedicated lines, then any
    /// other code (including `waist_up`, `reference`, and `''`) falling to plain identity.
    private static func identityRoleNoun(templateCode: String) -> String {
        switch templateCode {
        case "face_closeup": "facial identity"
        case "profile_side": "profile"
        case "full_body": "full-body identity"
        default: "identity"
        }
    }
}

/// The read shape of one prompt with its citations and derived staleness
/// (PHASE3_DESIGN §3.4, §4.4). `isStale` is a **derived digest comparison**, never a
/// stored flag: the builder re-renders the requirement's input now, and the prompt is
/// stale when the digest differs or the recorded input format is older than the
/// builder's.
public struct AssetPromptDetail: Equatable, Hashable, Sendable {
    /// One immutable citation row, as history (§3.3).
    public struct Citation: Equatable, Hashable, Sendable {
        public let id: UUID
        /// The `@Image` number, 1-based (§3.3).
        public let position: Int
        /// SET NULL columns — `nil` after the referent is gone; the sha/name are the record.
        public let requirementID: UUID?
        public let versionID: UUID?
        public let `class`: ReferenceClass
        public let role: String
        public let exclusion: String
        public let fidelity: ReferenceFidelity
        public let sha256: String
        public let displayName: String

        public init(
            id: UUID,
            position: Int,
            requirementID: UUID?,
            versionID: UUID?,
            class: ReferenceClass,
            role: String,
            exclusion: String,
            fidelity: ReferenceFidelity,
            sha256: String,
            displayName: String
        ) {
            self.id = id
            self.position = position
            self.requirementID = requirementID
            self.versionID = versionID
            self.class = `class`
            self.role = role
            self.exclusion = exclusion
            self.fidelity = fidelity
            self.sha256 = sha256
            self.displayName = displayName
        }
    }

    public let id: UUID
    public let requirementID: UUID
    public let promptNumber: Int
    public let body: String
    public let targetModel: String
    public let guidance: String
    /// Descriptor-relative skill identity (§3.5); all three `''` for a human-written prompt.
    public let skillID: String
    public let skillEntryPath: String
    public let skillEntrySHA256: String
    /// PROV `source` — converted to `human` by a body edit on an `ai` row (§7.2).
    public let source: FactSource
    /// `created_source` — skill provenance survives that conversion.
    public let createdSource: FactSource
    public let createdAt: Date
    public let citations: [Citation]
    /// Derived per §3.4: digest mismatch, or an older `input_format_version`.
    public let isStale: Bool

    public init(
        id: UUID,
        requirementID: UUID,
        promptNumber: Int,
        body: String,
        targetModel: String,
        guidance: String,
        skillID: String,
        skillEntryPath: String,
        skillEntrySHA256: String,
        source: FactSource,
        createdSource: FactSource,
        createdAt: Date,
        citations: [Citation],
        isStale: Bool
    ) {
        self.id = id
        self.requirementID = requirementID
        self.promptNumber = promptNumber
        self.body = body
        self.targetModel = targetModel
        self.guidance = guidance
        self.skillID = skillID
        self.skillEntryPath = skillEntryPath
        self.skillEntrySHA256 = skillEntrySHA256
        self.source = source
        self.createdSource = createdSource
        self.createdAt = createdAt
        self.citations = citations
        self.isStale = isStale
    }
}

/// One row of §3.3's **planned dependencies** — every active dependency of a requirement,
/// satisfied or not, in §3.3's order (class rank, edge `created_at`, edge id). One list
/// carries both named collections: the satisfied rows' non-nil designators, in order, are
/// the rendered references' dense `@Image 1…N`.
public struct PlannedDependency: Equatable, Hashable, Sendable, Identifiable {
    /// The approved version that satisfies this edge — present exactly when
    /// `isSatisfied` (§3.3: a rendered reference contributes its approved version).
    public struct ApprovedVersion: Equatable, Hashable, Sendable {
        public let versionID: UUID
        public let sha256: String
        public let relativePath: String
        /// `nil` when unread or not an image dimension pair.
        public let pixelWidth: Int?
        public let pixelHeight: Int?

        public init(
            versionID: UUID,
            sha256: String,
            relativePath: String,
            pixelWidth: Int?,
            pixelHeight: Int?
        ) {
            self.versionID = versionID
            self.sha256 = sha256
            self.relativePath = relativePath
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }
    }

    public let id: UUID
    /// The dependency **edge's** id — the ordering pins to the edge, not the target
    /// requirement or its approved version (§3.3).
    public let dependencyID: UUID
    /// The requirement this edge points at.
    public let requirementID: UUID
    public let requirementName: String
    public let entityName: String
    public let `class`: ReferenceClass
    public let attributes: ReferenceAttributes
    public let isSatisfied: Bool
    public let approvedVersion: ApprovedVersion?
    /// Non-nil only on satisfied rows; the non-nil subset, in order, numbers the rendered
    /// references `@Image 1…N`. No surface may re-derive it.
    public let designator: Int?

    public init(
        id: UUID,
        dependencyID: UUID,
        requirementID: UUID,
        requirementName: String,
        entityName: String,
        class: ReferenceClass,
        attributes: ReferenceAttributes,
        isSatisfied: Bool,
        approvedVersion: ApprovedVersion?,
        designator: Int?
    ) {
        self.id = id
        self.dependencyID = dependencyID
        self.requirementID = requirementID
        self.requirementName = requirementName
        self.entityName = entityName
        self.class = `class`
        self.attributes = attributes
        self.isSatisfied = isSatisfied
        self.approvedVersion = approvedVersion
        self.designator = designator
    }
}
