import CryptoKit
import Foundation
import GRDB

// The asset-prompt input (PHASE3_DESIGN §8.2, §3.4; Plan 013 contract D).
//
// A **FilmCore** type for the same reason `ManifestInputBuilder` is: §8.4 step 0 rebuilds
// the rendered input *inside* the apply transaction and compares its digest with the run's
// recorded value. FilmBrain reaches it through the session; apply calls it with the
// transaction's own `Database` handle.
//
// **§8.2's field list below is the single normative definition of the digest input set**;
// no field is optional and absent values render as `''` / `0` / empty arrays, never as
// omitted keys. Screenplay body text is never included (§9); scene headings and synopses
// always are.

// MARK: - The §8.2 shape

/// The whole §8.2 input for one requirement. Every collection is an ordered array — the
/// encoded shape contains no dictionary (determinism rule 2).
public struct AssetPromptInput: Codable, Equatable, Sendable {
    /// Determinism rule 4: the rendered input carries its own version, recorded on each
    /// prompt row as `input_format_version` (§4.3). Any rendered-shape change bumps
    /// `AssetPromptInputBuilder.schemaVersion` — there is no digest re-stamp migration.
    public let schemaVersion: Int
    public let requirement: AssetPromptInputRequirement
    public let scenes: [AssetPromptInputScene]
    public let entity: AssetPromptInputEntity
    public let dependencies: [AssetPromptInputDependency]
    public let references: [AssetPromptInputReference]

    public init(
        schemaVersion: Int = AssetPromptInputBuilder.schemaVersion,
        requirement: AssetPromptInputRequirement,
        scenes: [AssetPromptInputScene],
        entity: AssetPromptInputEntity,
        dependencies: [AssetPromptInputDependency],
        references: [AssetPromptInputReference]
    ) {
        self.schemaVersion = schemaVersion
        self.requirement = requirement
        self.scenes = scenes
        self.entity = entity
        self.dependencies = dependencies
        self.references = references
    }
}

/// One requirement record (§8.2): `id`, tier, name, entityName, entityKind, templateCode
/// (`''` for variants), reason, necessity, sceneOrdinals.
public struct AssetPromptInputRequirement: Codable, Equatable, Sendable {
    public let id: UUID
    public let tier: AssetRequirementTier
    public let name: String
    public let entityName: String
    public let entityKind: EntityKind
    public let templateCode: String
    public let reason: String
    public let necessity: RequirementNecessity
    public let sceneOrdinals: [Int]

    public init(
        id: UUID,
        tier: AssetRequirementTier,
        name: String,
        entityName: String,
        entityKind: EntityKind,
        templateCode: String,
        reason: String,
        necessity: RequirementNecessity,
        sceneOrdinals: [Int]
    ) {
        self.id = id
        self.tier = tier
        self.name = name
        self.entityName = entityName
        self.entityKind = entityKind
        self.templateCode = templateCode
        self.reason = reason
        self.necessity = necessity
        self.sceneOrdinals = sceneOrdinals
    }
}

/// One scene overlapping the requirement (§8.2), one entry per `sceneOrdinals` element.
public struct AssetPromptInputScene: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let heading: String
    /// `''` when none.
    public let synopsis: String

    public init(ordinal: Int, heading: String, synopsis: String) {
        self.ordinal = ordinal
        self.heading = heading
        self.synopsis = synopsis
    }
}

/// The owning entity's record (§8.2).
public struct AssetPromptInputEntity: Codable, Equatable, Sendable {
    public let name: String
    public let aliases: [String]
    public let description: String
    /// States whose range overlaps the requirement's scenes — all of them for a canonical
    /// requirement.
    public let states: [AssetPromptInputState]
    public let events: [AssetPromptInputEvent]

    public init(
        name: String,
        aliases: [String],
        description: String,
        states: [AssetPromptInputState],
        events: [AssetPromptInputEvent]
    ) {
        self.name = name
        self.aliases = aliases
        self.description = description
        self.states = states
        self.events = events
    }
}

/// One state (§8.2): category, description, and the ordinals its range overlaps.
public struct AssetPromptInputState: Codable, Equatable, Sendable {
    public let category: StateCategory
    public let description: String
    public let sceneOrdinals: [Int]

    public init(category: StateCategory, description: String, sceneOrdinals: [Int]) {
        self.category = category
        self.description = description
        self.sceneOrdinals = sceneOrdinals
    }
}

/// One continuity event of the owning entity (§8.2).
public struct AssetPromptInputEvent: Codable, Equatable, Sendable {
    public let sceneOrdinal: Int
    public let description: String

    public init(sceneOrdinal: Int, description: String) {
        self.sceneOrdinal = sceneOrdinal
        self.description = description
    }
}

/// One planned dependency (§8.2) — the active set whole, satisfied or not, carrying the
/// §3.3-derived attributes. An unsatisfied edge rides here so that adding or removing one
/// stales the prompt (§3.4's promise).
public struct AssetPromptInputDependency: Codable, Equatable, Sendable {
    public let dependsOnRequirementId: UUID
    public let dependsOnName: String
    public let `class`: ReferenceClass
    public let satisfied: Bool
    public let role: String
    public let exclusion: String
    public let fidelity: ReferenceFidelity

    public init(
        dependsOnRequirementId: UUID,
        dependsOnName: String,
        class: ReferenceClass,
        satisfied: Bool,
        role: String,
        exclusion: String,
        fidelity: ReferenceFidelity
    ) {
        self.dependsOnRequirementId = dependsOnRequirementId
        self.dependsOnName = dependsOnName
        self.class = `class`
        self.satisfied = satisfied
        self.role = role
        self.exclusion = exclusion
        self.fidelity = fidelity
    }
}

/// One rendered reference (§8.2) — the satisfied subset, densely numbered.
public struct AssetPromptInputReference: Codable, Equatable, Sendable {
    /// `'@Image 1' …`, over the satisfied rows alone (§3.3).
    public let designator: String
    public let `class`: ReferenceClass
    public let name: String
    /// The referenced requirement's entity name + requirement name (§8.2).
    public let description: String
    public let role: String
    public let exclusion: String
    public let fidelity: ReferenceFidelity
    public let sha256: String
    /// `0` when unread.
    public let pixelWidth: Int
    /// `0` when unread.
    public let pixelHeight: Int

    public init(
        designator: String,
        class: ReferenceClass,
        name: String,
        description: String,
        role: String,
        exclusion: String,
        fidelity: ReferenceFidelity,
        sha256: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.designator = designator
        self.class = `class`
        self.name = name
        self.description = description
        self.role = role
        self.exclusion = exclusion
        self.fidelity = fidelity
        self.sha256 = sha256
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// The built input together with the exact text and its digest (§3.4).
///
/// `digest` is the **one prompt digest in this contract**: SHA-256 of the rendered JSON
/// text, the same value a run records as `jobs.input_sha256` (the runner digests
/// `input.text`; the `<asset-prompt-input>` delimiter lives only in the prompt file,
/// outside the digest).
public struct AssetPromptInputSnapshot: Equatable, Sendable {
    public let input: AssetPromptInput
    public let text: String
    /// SHA-256 of `text`'s UTF-8 bytes, lowercase hex.
    public let digest: String

    public init(input: AssetPromptInput, text: String, digest: String) {
        self.input = input
        self.text = text
        self.digest = digest
    }

    /// The §8.1 budget's unit: UTF-16 code units.
    public var utf16Count: Int { text.utf16.count }
}

// MARK: - The builder

/// Builds §8.2's input for one requirement from canonical data alone (PHASE3_DESIGN §8.2).
///
/// ## Determinism contract (§8.2's five rules, in full)
///
/// 1. **No SQL ordering is trusted.** Every collection is fetched and then ordered in
///    Swift by a total key ending in the row's `id`.
/// 2. **Key order is `sortedKeys`**, and every collection in the encoded shape is an array.
/// 3. **No clock, no locale, no floats, no environment**: no timestamps, every number an
///    `Int`, every string stored text, nothing from the run.
/// 4. **The rendered input carries `schemaVersion`.**
/// 5. **Every rendered-shape change bumps `schemaVersion`** so existing customer prompts
///    become explicitly stale. §3.3's derivation tables are part of the rendered output.
public enum AssetPromptInputBuilder {
    /// The rendered input's own version (see `AssetPromptInput.schemaVersion`). Bump on
    /// any rendered-shape change; never re-stamp digests (§8.2's versioning posture).
    public static let schemaVersion = 1

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Renders and digests in one step.
    public static func snapshot(requirementID: UUID, in db: Database) throws -> AssetPromptInputSnapshot {
        let input = try build(requirementID: requirementID, in: db)
        let text = try render(input)
        let digest = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return AssetPromptInputSnapshot(input: input, text: text, digest: digest)
    }

    /// Renders the input to the exact text whose SHA-256 is the digest (§3.4).
    public static func render(_ input: AssetPromptInput) throws -> String {
        let data = try encoder.encode(input)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProjectStoreError.invalidBundle
        }
        return text
    }

    /// The §8.2 build, inside the caller's transaction.
    static func build(requirementID: UUID, in db: Database) throws -> AssetPromptInput {
        let graph = try ProjectRepository.manifestGraph(in: db)
        guard let requirement = graph.requirements[requirementID],
              let entity = graph.entities[requirement.entityID]
        else { throw ProjectStoreError.requirementNotFound }

        // Scenes pinned to the project's current script, ordinals resolved against it.
        var ordinalOfScene: [UUID: Int] = [:]
        var sceneByOrdinal: [Int: Scene] = [:]
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT scenes.* FROM scenes
                JOIN projects ON projects.current_script_id = scenes.script_id
                ORDER BY scenes.ordinal
                """
        ) {
            let scene = try decodeScene(row)
            ordinalOfScene[scene.id] = scene.ordinal
            sceneByOrdinal[scene.ordinal] = scene
        }

        func requiredScenes(of requirement: AssetRequirement) throws -> [Scene] {
            switch requirement.tier {
            case .canonical:
                return try Row
                    .fetchAll(
                        db,
                        sql: """
                            SELECT DISTINCT scenes.* FROM scenes
                            JOIN scene_entities ON scene_entities.scene_id = scenes.id
                            WHERE scene_entities.entity_id = ?
                              AND scene_entities.role IN (\(ManifestQualification.visibleRoleSQLList))
                              AND scene_entities.review_state <> 'rejected'
                            ORDER BY scenes.ordinal
                            """,
                        arguments: [requirement.entityID.uuidString]
                    )
                    .map(decodeScene)
            case .variant:
                return try Row
                    .fetchAll(
                        db,
                        sql: """
                            SELECT scenes.* FROM scenes
                            JOIN asset_requirement_scenes AS links ON links.scene_id = scenes.id
                            WHERE links.requirement_id = ? AND links.review_state <> 'rejected'
                            ORDER BY scenes.ordinal
                            """,
                        arguments: [requirement.id.uuidString]
                    )
                    .map(decodeScene)
            }
        }

        let requirementScenes = try requiredScenes(of: requirement)
        let requirementOrdinals = requirementScenes.map(\.ordinal)
        let requirementOrdinalSet = Set(requirementOrdinals)
        let isCanonical = requirement.tier == .canonical

        // States: canonical requirements take every state (§8.2); a variant takes only
        // those whose range overlaps its own scenes. Rejected tombstones are not facts
        // and never enter the input. Ordered by start ordinal, end ordinal (open-ended
        // last), category, id — determinism rule 1.
        struct StateRow {
            let start: Int
            let end: Int?
            let category: StateCategory
            let description: String
            let id: UUID
        }
        var stateRows: [StateRow] = []
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM entity_states
                WHERE entity_id = ? AND review_state <> 'rejected'
                """,
            arguments: [entity.id.uuidString]
        ) {
            let state = try decodeEntityState(row)
            guard let start = ordinalOfScene[state.startSceneID] else { continue }
            let end = state.endSceneID.flatMap { ordinalOfScene[$0] }
            stateRows.append(
                StateRow(
                    start: start, end: end, category: state.category,
                    description: state.description, id: state.id
                )
            )
        }
        stateRows.sort { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            let leftEnd = lhs.end ?? Int.max
            let rightEnd = rhs.end ?? Int.max
            if leftEnd != rightEnd { return leftEnd < rightEnd }
            if lhs.category.rawValue != rhs.category.rawValue {
                return lhs.category.rawValue < rhs.category.rawValue
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let inputStates = stateRows.compactMap { row -> AssetPromptInputState? in
            let upper = row.end ?? row.start
            let range = Array(min(row.start, upper)...max(row.start, upper))
            let ordinals = isCanonical ? range : range.filter(requirementOrdinalSet.contains)
            guard !ordinals.isEmpty else { return nil }
            return AssetPromptInputState(
                category: row.category,
                description: row.description,
                sceneOrdinals: ordinals.sorted()
            )
        }

        // Events ordered by scene ordinal, then id.
        struct EventRow {
            let ordinal: Int
            let description: String
            let id: UUID
        }
        var eventRows: [EventRow] = []
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM continuity_events
                WHERE entity_id = ? AND review_state <> 'rejected'
                """,
            arguments: [entity.id.uuidString]
        ) {
            let event = try decodeContinuityEvent(row)
            guard let ordinal = ordinalOfScene[event.sceneID] else { continue }
            eventRows.append(
                EventRow(ordinal: ordinal, description: event.description, id: event.id)
            )
        }
        eventRows.sort { lhs, rhs in
            if lhs.ordinal != rhs.ordinal { return lhs.ordinal < rhs.ordinal }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let inputEvents = eventRows.map {
            AssetPromptInputEvent(sceneOrdinal: $0.ordinal, description: $0.description)
        }

        var aliases: [String] = []
        for row in try Row.fetchAll(
            db,
            sql: "SELECT alias FROM entity_aliases WHERE entity_id = ? AND review_state <> 'rejected'",
            arguments: [entity.id.uuidString]
        ) {
            aliases.append(row["alias"])
        }

        let templateCode = requirement.outfitSourceVersionID != nil ? "full_body" : requirement.typeID.flatMap { graph.types[$0]?.code } ?? ""

        // Planned dependencies: every active edge, satisfied or not, in §3.3's order.
        let planned = try Self.plannedDependencies(
            of: requirement, graph: graph, in: db
        )

        let input = AssetPromptInput(
            requirement: AssetPromptInputRequirement(
                id: requirement.id,
                tier: requirement.tier,
                name: requirement.name,
                entityName: entity.name,
                entityKind: entity.kind,
                templateCode: templateCode,
                reason: requirement.reason,
                necessity: requirement.necessity,
                sceneOrdinals: ordered(requirementOrdinals)
            ),
            scenes: requirementScenes.map { scene in
                AssetPromptInputScene(
                    ordinal: scene.ordinal,
                    heading: scene.heading,
                    synopsis: scene.synopsis
                )
            },
            entity: AssetPromptInputEntity(
                name: entity.name,
                aliases: aliases.sorted(),
                description: entity.description,
                states: inputStates,
                events: inputEvents
            ),
            dependencies: planned.map { dependency in
                AssetPromptInputDependency(
                    dependsOnRequirementId: dependency.requirementID,
                    dependsOnName: dependency.requirementName,
                    class: dependency.class,
                    satisfied: dependency.isSatisfied,
                    role: dependency.attributes.role,
                    exclusion: dependency.attributes.exclusion,
                    fidelity: dependency.attributes.fidelity
                )
            },
            references: planned.compactMap { dependency -> AssetPromptInputReference? in
                guard let approved = dependency.approvedVersion, let designator = dependency.designator
                else { return nil }
                return AssetPromptInputReference(
                    designator: "@Image \(designator)",
                    class: dependency.class,
                    name: "\(dependency.requirementName)",
                    description: "\(dependency.entityName) — \(dependency.requirementName)",
                    role: dependency.attributes.role,
                    exclusion: dependency.attributes.exclusion,
                    fidelity: dependency.attributes.fidelity,
                    sha256: approved.sha256,
                    pixelWidth: approved.pixelWidth ?? 0,
                    pixelHeight: approved.pixelHeight ?? 0
                )
            }
        )
        return input
    }

    /// §3.3's planned dependencies, whole and in order: class rank, edge `created_at`,
    /// edge id — with dense `@Image` numbering over the satisfied subset computed here.
    ///
    /// One shared function for Phase 5 to inherit; no surface may re-derive a designator.
    static func plannedDependencies(
        of requirement: AssetRequirement,
        graph: ProjectRepository.ManifestGraph,
        in db: Database
    ) throws -> [PlannedDependency] {
        let edges = graph.dependencies
            .filter { $0.requirementID == requirement.id }
        let owningEntity = graph.entities[requirement.entityID]

        var planned: [(edge: AssetDependency, row: PlannedDependency)] = []
        for edge in edges {
            guard let target = graph.requirements[edge.dependsOnRequirementID] else { continue }
            let targetEntity = graph.entities[target.entityID]
            let targetClass = ReferenceAttributeRules.referenceClass(
                tier: target.tier, entityKind: targetEntity?.kind ?? .object
            )
            let attributes = ReferenceAttributeRules.attributes(
                owningTier: requirement.tier,
                owningEntityKind: owningEntity?.kind ?? .object,
                owningEntityName: owningEntity?.name ?? "",
                targetTier: target.tier,
                targetEntityKind: targetEntity?.kind ?? .object,
                targetEntityName: targetEntity?.name ?? "",
                targetRequirementName: target.name,
                targetTemplateCode: target.typeID.flatMap { graph.types[$0]?.code } ?? ""
            )
            let satisfied = graph.isSatisfied(dependsOn: target.id)
            var approved: PlannedDependency.ApprovedVersion?
            if satisfied, let asset = graph.assetsByRequirement[target.id],
               let version = try Self.approvedVersion(of: asset.id, in: db) {
                approved = version
            }
            planned.append((
                edge,
                PlannedDependency(
                    id: edge.id,
                    dependencyID: edge.id,
                    requirementID: target.id,
                    requirementName: target.name,
                    entityName: targetEntity?.name ?? "",
                    class: targetClass,
                    attributes: attributes,
                    isSatisfied: satisfied,
                    approvedVersion: approved,
                    designator: nil
                )
            ))
        }

        // §3.3's order: class rank, then the edge's created_at, then the edge's id.
        planned.sort { (lhs: (edge: AssetDependency, row: PlannedDependency), rhs: (edge: AssetDependency, row: PlannedDependency)) in
            let leftClass = lhs.row.class.rank
            let rightClass = rhs.row.class.rank
            if leftClass != rightClass { return leftClass < rightClass }
            if lhs.edge.provenance.createdAt != rhs.edge.provenance.createdAt {
                return lhs.edge.provenance.createdAt < rhs.edge.provenance.createdAt
            }
            return lhs.edge.id.uuidString < rhs.edge.id.uuidString
        }

        // Dense @Image numbering over the satisfied subset alone.
        var designator = 0
        return planned.map { item in
            guard item.row.isSatisfied else { return item.row }
            designator += 1
            return PlannedDependency(
                id: item.row.id,
                dependencyID: item.row.dependencyID,
                requirementID: item.row.requirementID,
                requirementName: item.row.requirementName,
                entityName: item.row.entityName,
                class: item.row.class,
                attributes: item.row.attributes,
                isSatisfied: item.row.isSatisfied,
                approvedVersion: item.row.approvedVersion,
                designator: designator
            )
        }
    }

    /// The approved version of an asset, when one exists — with its stored dimensions.
    private static func approvedVersion(of assetID: UUID, in db: Database) throws
        -> PlannedDependency.ApprovedVersion? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM asset_versions WHERE asset_id = ? AND status = 'approved'",
            arguments: [assetID.uuidString]
        ) else { return nil }
        return PlannedDependency.ApprovedVersion(
            versionID: try UUID.required(row["id"]),
            sha256: row["sha256"],
            relativePath: row["relative_path"],
            pixelWidth: row["pixel_width"],
            pixelHeight: row["pixel_height"]
        )
    }

    private static func ordered(_ ordinals: [Int]) -> [Int] {
        Array(Set(ordinals)).sorted()
    }

}

// MARK: - The §8.1 pre-flight budget

/// The §8.1 pre-flight cap for one requirement's rendered input, in UTF-16 code units —
/// the extraction chunker's unit, and `ManifestInputBudget`'s value: orders of magnitude
/// of headroom at single-requirement scale. Over budget refuses naming the size, never
/// truncates; the value travels on `AssetPromptSettings.inputBudgetUTF16`.
public enum AssetPromptInputBudget {
    /// The pinned default (Plan 013 contract B).
    public static let defaultUTF16Limit = 120_000

    public static func measure(_ text: String) -> Int { text.utf16.count }

    public static func check(text: String, limit: Int = defaultUTF16Limit) throws {
        let measured = measure(text)
        guard measured <= limit else {
            throw AssetPromptInputTooLarge(measuredUTF16: measured, limitUTF16: limit)
        }
    }
}

/// The §8.1 pre-flight refusal, carrying both numbers so the message can name the size.
public struct AssetPromptInputTooLarge: Error, Equatable, LocalizedError, Sendable {
    public let measuredUTF16: Int
    public let limitUTF16: Int

    public init(measuredUTF16: Int, limitUTF16: Int) {
        self.measuredUTF16 = measuredUTF16
        self.limitUTF16 = limitUTF16
    }

    public var errorDescription: String? {
        """
        This requirement's context is \(measuredUTF16) units against a budget of \
        \(limitUTF16) and cannot be sent.
        """
    }
}
