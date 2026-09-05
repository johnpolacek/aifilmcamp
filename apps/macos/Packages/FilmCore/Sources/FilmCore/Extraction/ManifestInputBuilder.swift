import Foundation
import GRDB

// The manifest-inference input (PHASE2_DESIGN §3.3, §3.4, §3.6, §8.2; Plan 012 contract A).
//
// This is a **FilmCore** type, and deliberately so: §8.4 step 0 rebuilds the rendered input
// *inside* the apply transaction and compares its digest with `jobs.input_sha256`, which
// forecloses a FilmBrain home. FilmBrain calls it through the session when launching the
// job (`ProjectReading.manifestInput()`); apply calls the same builder with the
// transaction's own `Database` handle.
//
// The job never sees screenplay text (§3.6): everything below is canonical structured data.

// MARK: - The §8.2 shape

/// The whole §8.2 input, in the order and with the fields the design lists.
///
/// `schemaVersion` rides along for the same reason `ReconcileInput` carries one — the
/// rendered text is a wire format read by a model and digested by apply, so its shape is
/// versioned rather than implicit. It is not one of §8.2's four collections.
public struct ManifestInput: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    /// Every eligible entity that qualifies for a canonical set (§3.3), **plus every
    /// eligible prop-kind entity whatever its scene count** (§3.4), with the same full
    /// record.
    public let entities: [ManifestInputEntity]
    public let scenes: [ManifestInputScene]
    public let template: [ManifestInputTemplateEntry]
    /// Non-qualifying **non-prop** eligible entities, compact. Props never appear here.
    public let borderline: [ManifestInputBorderlineEntity]

    public init(
        schemaVersion: Int = ManifestInputBuilder.schemaVersion,
        entities: [ManifestInputEntity],
        scenes: [ManifestInputScene],
        template: [ManifestInputTemplateEntry],
        borderline: [ManifestInputBorderlineEntity]
    ) {
        self.schemaVersion = schemaVersion
        self.entities = entities
        self.scenes = scenes
        self.template = template
        self.borderline = borderline
    }
}

/// One full entity record (§8.2).
public struct ManifestInputEntity: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: EntityKind
    public let name: String
    public let aliases: [String]
    public let description: String
    public let manifestInclusion: ManifestInclusion
    /// **Visible roles only** (§3.3): a `mentioned` appearance is not a scene a proposal
    /// may claim, so it is not in the input at all.
    public let appearances: [ManifestInputAppearance]
    public let states: [ManifestInputState]
    public let events: [ManifestInputEvent]
    public let existingRequirements: [ManifestInputRequirement]

    public init(
        id: UUID,
        kind: EntityKind,
        name: String,
        aliases: [String],
        description: String,
        manifestInclusion: ManifestInclusion,
        appearances: [ManifestInputAppearance],
        states: [ManifestInputState],
        events: [ManifestInputEvent],
        existingRequirements: [ManifestInputRequirement]
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.description = description
        self.manifestInclusion = manifestInclusion
        self.appearances = appearances
        self.states = states
        self.events = events
        self.existingRequirements = existingRequirements
    }
}

/// The compact borderline record (§8.2): the pool inclusion suggestions draw from.
public struct ManifestInputBorderlineEntity: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: EntityKind
    public let name: String
    public let appearances: [ManifestInputAppearance]

    public init(id: UUID, kind: EntityKind, name: String, appearances: [ManifestInputAppearance]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.appearances = appearances
    }
}

/// One appearance, carrying its id so a proposal can cite it as basis (§8.2, §8.3).
public struct ManifestInputAppearance: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sceneOrdinal: Int
    public let role: SceneEntityRole

    public init(id: UUID, sceneOrdinal: Int, role: SceneEntityRole) {
        self.id = id
        self.sceneOrdinal = sceneOrdinal
        self.role = role
    }
}

/// One state, with its scene range resolved to ordinals (§8.2). `endOrdinal` is absent when
/// the state is still active at the end of the script.
public struct ManifestInputState: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let category: StateCategory
    public let description: String
    public let startOrdinal: Int
    public let endOrdinal: Int?

    public init(id: UUID, category: StateCategory, description: String, startOrdinal: Int, endOrdinal: Int?) {
        self.id = id
        self.category = category
        self.description = description
        self.startOrdinal = startOrdinal
        self.endOrdinal = endOrdinal
    }
}

/// One continuity event of this entity (§8.2). Scene-wide events — `entity_id IS NULL` —
/// belong to no entity and are not in the input.
public struct ManifestInputEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sceneOrdinal: Int
    public let description: String

    public init(id: UUID, sceneOrdinal: Int, description: String) {
        self.id = id
        self.sceneOrdinal = sceneOrdinal
        self.description = description
    }
}

/// An existing requirement of the entity, with the flags the model must propose around and
/// apply enforces regardless (§8.2).
public struct ManifestInputRequirement: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let tier: AssetRequirementTier
    public let name: String
    public let necessity: RequirementNecessity
    /// PROV: `human`, or `ai` + `accepted` (§3.7).
    public let protected: Bool
    /// Any `locks` row naming this requirement.
    public let locked: Bool
    public let rejected: Bool
    /// The scenes this requirement is required by — stored links for a variant, the
    /// entity's visible-role scenes for a canonical row (§5.2).
    public let sceneOrdinals: [Int]

    public init(
        id: UUID,
        tier: AssetRequirementTier,
        name: String,
        necessity: RequirementNecessity,
        protected: Bool,
        locked: Bool,
        rejected: Bool,
        sceneOrdinals: [Int]
    ) {
        self.id = id
        self.tier = tier
        self.name = name
        self.necessity = necessity
        self.protected = protected
        self.locked = locked
        self.rejected = rejected
        self.sceneOrdinals = sceneOrdinals
    }
}

/// One scene, as context (§8.2). Synopses are context only — never a citable basis kind,
/// since a synopsis is itself derived prose rather than an anchored fact.
public struct ManifestInputScene: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let heading: String
    public let intExt: SceneIntExt
    public let locationText: String
    public let timeOfDay: String
    public let synopsis: String

    public init(
        ordinal: Int,
        heading: String,
        intExt: SceneIntExt,
        locationText: String,
        timeOfDay: String,
        synopsis: String
    ) {
        self.ordinal = ordinal
        self.heading = heading
        self.intExt = intExt
        self.locationText = locationText
        self.timeOfDay = timeOfDay
        self.synopsis = synopsis
    }
}

/// One template entry (§8.2): context for the model, and digest coverage for apply — a
/// template entry disabled mid-run changes the rendered input, so §8.4 step 0 catches it.
public struct ManifestInputTemplateEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let entityKind: EntityKind
    public let code: String
    public let displayName: String
    public let isEnabled: Bool

    public init(id: UUID, entityKind: EntityKind, code: String, displayName: String, isEnabled: Bool) {
        self.id = id
        self.entityKind = entityKind
        self.code = code
        self.displayName = displayName
        self.isEnabled = isEnabled
    }
}

/// The built input together with the exact text whose digest the run records (§8.1, §8.4).
///
/// The two travel as one value because they must never be built from different reads: the
/// validator checks its predicates against `input`, and `jobs.input_sha256` is the runner's
/// digest of `text`.
public struct ManifestInputSnapshot: Equatable, Sendable {
    public let input: ManifestInput
    /// The rendered JSON — what the prompt wraps in `<manifest-input>` and what apply
    /// re-renders inside its transaction.
    public let text: String

    public init(input: ManifestInput, text: String) {
        self.input = input
        self.text = text
    }

    /// The §8.1 budget's unit: UTF-16 code units, the extraction chunker's own unit.
    public var utf16Count: Int { text.utf16.count }
}

// MARK: - The builder

/// Builds §8.2's input from canonical data alone (PHASE2_DESIGN §3.6, §8.2).
///
/// ## Determinism contract
///
/// §8.4 step 0 compares a **byte** digest of `render(_:)`'s output against the digest the
/// run recorded, so two builds over an unchanged canonical state must produce identical
/// bytes. Every source of non-determinism is closed deliberately:
///
/// 1. **No SQL ordering is trusted.** Rows are fetched and then ordered in Swift by a total
///    key that ends in the row's `id`, so no two elements can ever compare equal.
/// 2. **Key order is fixed by `JSONEncoder.OutputFormatting.sortedKeys`**, so a dictionary
///    is never at the mercy of Swift's hash seed. No collection here is a dictionary in the
///    encoded shape — every one is an ordered array.
/// 3. **No clock, no locale, no environment.** The input carries no timestamps, no formatted
///    dates, and no floating-point values; every string is stored text and every number is
///    an `Int` ordinal.
/// 4. **Nothing depends on the run.** No job id, no actor, no random id is generated here.
///
/// The ordering keys, in full:
///
/// | collection | key |
/// |---|---|
/// | `entities`, `borderline` | kind raw value, normalized name, id |
/// | `aliases` | the alias text |
/// | `appearances` | scene ordinal, role raw value, id |
/// | `states` | start ordinal, end ordinal (open-ended last), category, id |
/// | `events` | scene ordinal, id |
/// | `existingRequirements` | tier (canonical first), normalized name, id |
/// | `sceneOrdinals` | ascending, de-duplicated |
/// | `scenes` | ordinal |
/// | `template` | entity kind raw value, sort order, code, id |
///
/// ## What is in the pool
///
/// Eligibility is §3.3's — `review_state != 'rejected'` and `is_relevant = 1` — asked of
/// `ManifestQualification`, never re-spelled here. Rejected **fact** rows (appearances,
/// states, events, aliases) are excluded too: a tombstone says the fact is not real, and a
/// proposal may not cite one. Rejected **requirement** rows are included, flagged
/// `rejected`, because the model must propose around them (§8.2).
public enum ManifestInputBuilder {
    /// The rendered input's own version (see `ManifestInput.schemaVersion`).
    public static let schemaVersion = 1

    /// The encoder every render uses. `sortedKeys` is the determinism contract's rule 2.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Renders the input to the exact text the run digests.
    public static func render(_ input: ManifestInput) throws -> String {
        let data = try encoder.encode(input)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProjectStoreError.invalidBundle
        }
        return text
    }

    /// Builds and renders in one step — the value both the launch path and §8.4 step 0 use.
    static func snapshot(in db: Database) throws -> ManifestInputSnapshot {
        let input = try build(in: db)
        return ManifestInputSnapshot(input: input, text: try render(input))
    }

    /// The §8.2 build, inside the caller's transaction.
    ///
    /// Internal because `Database` is GRDB's: FilmBrain reaches this through
    /// `ProjectReading.manifestInput()`, and apply reaches it with its own handle.
    static func build(in db: Database) throws -> ManifestInput {
        // Scenes are pinned to the project's current script, the same script §8.4 step 5
        // resolves ordinals against.
        let sceneRows = try Row.fetchAll(
            db,
            sql: """
                SELECT scenes.* FROM scenes
                JOIN projects ON projects.current_script_id = scenes.script_id
                """
        )
        let scenes = try sceneRows.map(decodeScene).sorted { $0.ordinal < $1.ordinal }
        var ordinalOfScene: [UUID: Int] = [:]
        for scene in scenes { ordinalOfScene[scene.id] = scene.ordinal }

        var entities: [UUID: Entity] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT * FROM entities") {
            let entity = try decodeEntity(row)
            entities[entity.id] = entity
        }

        // Visible roles only, tombstones excluded — the same filter §3.3's scene count uses,
        // generated from `ManifestQualification.visibleRoles` so the two cannot drift.
        var appearances: [UUID: [ManifestInputAppearance]] = [:]
        var visibleScenes: [UUID: Set<UUID>] = [:]
        var appearanceSceneIDs: [UUID: [UUID: UUID]] = [:]
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM scene_entities
                WHERE role IN (\(ManifestQualification.visibleRoleSQLList))
                  AND review_state <> 'rejected'
                """
        ) {
            let appearance = try decodeSceneEntity(row)
            guard let ordinal = ordinalOfScene[appearance.sceneID] else { continue }
            appearances[appearance.entityID, default: []].append(
                ManifestInputAppearance(
                    id: appearance.id,
                    sceneOrdinal: ordinal,
                    role: appearance.role
                )
            )
            visibleScenes[appearance.entityID, default: []].insert(appearance.sceneID)
            appearanceSceneIDs[appearance.entityID, default: [:]][appearance.id] = appearance.sceneID
        }

        var aliases: [UUID: [String]] = [:]
        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM entity_aliases WHERE review_state <> 'rejected'"
        ) {
            let alias = try decodeEntityAlias(row)
            aliases[alias.entityID, default: []].append(alias.alias)
        }

        var states: [UUID: [ManifestInputState]] = [:]
        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM entity_states WHERE review_state <> 'rejected'"
        ) {
            let state = try decodeEntityState(row)
            guard let start = ordinalOfScene[state.startSceneID] else { continue }
            states[state.entityID, default: []].append(
                ManifestInputState(
                    id: state.id,
                    category: state.category,
                    description: state.description,
                    startOrdinal: start,
                    endOrdinal: state.endSceneID.flatMap { ordinalOfScene[$0] }
                )
            )
        }

        var events: [UUID: [ManifestInputEvent]] = [:]
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM continuity_events
                WHERE entity_id IS NOT NULL AND review_state <> 'rejected'
                """
        ) {
            let event = try decodeContinuityEvent(row)
            guard let entityID = event.entityID, let ordinal = ordinalOfScene[event.sceneID] else {
                continue
            }
            events[entityID, default: []].append(
                ManifestInputEvent(id: event.id, sceneOrdinal: ordinal, description: event.description)
            )
        }

        var lockedRequirements: Set<UUID> = []
        for raw in try String.fetchAll(
            db,
            sql: "SELECT DISTINCT subject_id FROM locks WHERE subject_kind = 'requirement'"
        ) {
            lockedRequirements.insert(try UUID.required(raw))
        }

        var variantSceneOrdinals: [UUID: [Int]] = [:]
        for row in try Row.fetchAll(
            db,
            sql: "SELECT * FROM asset_requirement_scenes WHERE review_state <> 'rejected'"
        ) {
            let link = try decodeAssetRequirementScene(row)
            guard let ordinal = ordinalOfScene[link.sceneID] else { continue }
            variantSceneOrdinals[link.requirementID, default: []].append(ordinal)
        }

        var requirements: [UUID: [AssetRequirement]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT * FROM asset_requirements") {
            let requirement = try decodeAssetRequirement(row)
            requirements[requirement.entityID, default: []].append(requirement)
        }

        let template = try Row
            .fetchAll(db, sql: "SELECT * FROM asset_requirement_types")
            .map(decodeAssetRequirementType)
            .map {
                ManifestInputTemplateEntry(
                    id: $0.id,
                    entityKind: $0.entityKind,
                    code: $0.code,
                    displayName: $0.displayName,
                    isEnabled: $0.isEnabled
                )
            }
            .sorted(by: templateOrder)

        // Canonical rows are required-by their entity's visible scenes; variants carry
        // stored links (§5.2).
        func sceneOrdinals(of requirement: AssetRequirement) -> [Int] {
            switch requirement.tier {
            case .canonical:
                let sceneIDs = visibleScenes[requirement.entityID] ?? []
                return ordered(sceneIDs.compactMap { ordinalOfScene[$0] })
            case .variant:
                return ordered(variantSceneOrdinals[requirement.id] ?? [])
            }
        }

        func record(_ entity: Entity) -> ManifestInputEntity {
            ManifestInputEntity(
                id: entity.id,
                kind: entity.kind,
                name: entity.name,
                aliases: (aliases[entity.id] ?? []).sorted(),
                description: entity.description,
                manifestInclusion: entity.manifestInclusion,
                appearances: (appearances[entity.id] ?? []).sorted(by: appearanceOrder),
                states: (states[entity.id] ?? []).sorted(by: stateOrder),
                events: (events[entity.id] ?? []).sorted(by: eventOrder),
                existingRequirements: (requirements[entity.id] ?? [])
                    .map {
                        ManifestInputRequirement(
                            id: $0.id,
                            tier: $0.tier,
                            name: $0.name,
                            necessity: $0.necessity,
                            protected: $0.provenance.isProtected,
                            locked: lockedRequirements.contains($0.id),
                            rejected: $0.provenance.reviewState == .rejected,
                            sceneOrdinals: sceneOrdinals(of: $0)
                        )
                    }
                    .sorted(by: requirementOrder)
            )
        }

        var full: [ManifestInputEntity] = []
        var borderline: [ManifestInputBorderlineEntity] = []
        for entity in entities.values {
            let facts = ManifestQualification.EntityFacts(
                entity: entity,
                visibleSceneCount: visibleScenes[entity.id]?.count ?? 0
            )
            guard ManifestQualification.isEligible(facts) else { continue }
            // §3.4: every eligible prop rides in `entities[]` with the same full record,
            // whatever its scene count, because prop importance is the model's judgment.
            if entity.kind == .prop || ManifestQualification.qualifies(facts) {
                full.append(record(entity))
            } else {
                borderline.append(
                    ManifestInputBorderlineEntity(
                        id: entity.id,
                        kind: entity.kind,
                        name: entity.name,
                        appearances: (appearances[entity.id] ?? []).sorted(by: appearanceOrder)
                    )
                )
            }
        }

        return ManifestInput(
            entities: full.sorted { entityOrder($0.kind, $0.name, $0.id, $1.kind, $1.name, $1.id) },
            scenes: scenes.map {
                ManifestInputScene(
                    ordinal: $0.ordinal,
                    heading: $0.heading,
                    intExt: $0.intExt,
                    locationText: $0.locationText,
                    timeOfDay: $0.timeOfDay,
                    synopsis: $0.synopsis
                )
            },
            template: template,
            borderline: borderline.sorted {
                entityOrder($0.kind, $0.name, $0.id, $1.kind, $1.name, $1.id)
            }
        )
    }

    // MARK: - The ordering keys of the determinism contract

    private static func ordered(_ ordinals: [Int]) -> [Int] {
        Array(Set(ordinals)).sorted()
    }

    private static func entityOrder(
        _ leftKind: EntityKind, _ leftName: String, _ leftID: UUID,
        _ rightKind: EntityKind, _ rightName: String, _ rightID: UUID
    ) -> Bool {
        if leftKind.rawValue != rightKind.rawValue { return leftKind.rawValue < rightKind.rawValue }
        let left = EntityNormalization.normalize(leftName)
        let right = EntityNormalization.normalize(rightName)
        if left != right { return left < right }
        return leftID.uuidString < rightID.uuidString
    }

    private static func appearanceOrder(
        _ left: ManifestInputAppearance,
        _ right: ManifestInputAppearance
    ) -> Bool {
        if left.sceneOrdinal != right.sceneOrdinal { return left.sceneOrdinal < right.sceneOrdinal }
        if left.role.rawValue != right.role.rawValue { return left.role.rawValue < right.role.rawValue }
        return left.id.uuidString < right.id.uuidString
    }

    private static func stateOrder(_ left: ManifestInputState, _ right: ManifestInputState) -> Bool {
        if left.startOrdinal != right.startOrdinal { return left.startOrdinal < right.startOrdinal }
        // An open-ended state sorts after every bounded one that starts with it.
        let leftEnd = left.endOrdinal ?? Int.max
        let rightEnd = right.endOrdinal ?? Int.max
        if leftEnd != rightEnd { return leftEnd < rightEnd }
        if left.category.rawValue != right.category.rawValue {
            return left.category.rawValue < right.category.rawValue
        }
        return left.id.uuidString < right.id.uuidString
    }

    private static func eventOrder(_ left: ManifestInputEvent, _ right: ManifestInputEvent) -> Bool {
        if left.sceneOrdinal != right.sceneOrdinal { return left.sceneOrdinal < right.sceneOrdinal }
        return left.id.uuidString < right.id.uuidString
    }

    private static func requirementOrder(
        _ left: ManifestInputRequirement,
        _ right: ManifestInputRequirement
    ) -> Bool {
        // `canonical` < `variant` alphabetically, which is also the tier order every
        // manifest read uses.
        if left.tier.rawValue != right.tier.rawValue { return left.tier.rawValue < right.tier.rawValue }
        let leftName = EntityNormalization.normalize(left.name)
        let rightName = EntityNormalization.normalize(right.name)
        if leftName != rightName { return leftName < rightName }
        return left.id.uuidString < right.id.uuidString
    }

    private static func templateOrder(
        _ left: ManifestInputTemplateEntry,
        _ right: ManifestInputTemplateEntry
    ) -> Bool {
        if left.entityKind.rawValue != right.entityKind.rawValue {
            return left.entityKind.rawValue < right.entityKind.rawValue
        }
        if left.code != right.code { return left.code < right.code }
        return left.id.uuidString < right.id.uuidString
    }
}

// MARK: - The §8.1 pre-flight budget

/// The §8.1 input budget: the rendered input is capped **before any request is made**, in
/// UTF-16 code units (the extraction chunker's own unit).
///
/// An over-budget project fails pre-flight with a message naming the size, never by silent
/// truncation; a chunked fallback is deliberately not designed (design §11). Raising the
/// limit is a settings change — the value travels on `ManifestSettings.inputBudgetUTF16`,
/// captured at run start so a recorded run is reproducible against the settings it ran with.
public enum ManifestInputBudget {
    /// The pinned default (Plan 012 contract A): roughly 4× the design's tens-of-KB feature
    /// estimate, and comfortably one Codex request.
    public static let defaultUTF16Limit = 120_000

    /// Measures the rendered input in the budget's unit.
    public static func measure(_ text: String) -> Int { text.utf16.count }

    /// Refuses an over-budget input, naming the measured size.
    public static func check(text: String, limit: Int = defaultUTF16Limit) throws {
        let measured = measure(text)
        guard measured <= limit else {
            throw ManifestInputTooLarge(measuredUTF16: measured, limitUTF16: limit)
        }
    }

    /// The overload the launch path uses, so the measured text is always the digested one.
    public static func check(_ snapshot: ManifestInputSnapshot, limit: Int = defaultUTF16Limit) throws {
        try check(text: snapshot.text, limit: limit)
    }
}

/// The §8.1 pre-flight refusal, carrying both numbers so the message can name the size.
public struct ManifestInputTooLarge: Error, Equatable, LocalizedError, Sendable {
    public let measuredUTF16: Int
    public let limitUTF16: Int

    public init(measuredUTF16: Int, limitUTF16: Int) {
        self.measuredUTF16 = measuredUTF16
        self.limitUTF16 = limitUTF16
    }

    public var errorDescription: String? {
        """
        This project's manifest input is \(measuredUTF16) UTF-16 units, over the \
        \(limitUTF16)-unit limit for one request. Reduce the project's structured data or \
        raise the manifest input budget.
        """
    }
}

// MARK: - The read door

extension ProjectRepository {
    /// `ProjectReading.manifestInput()`: one read transaction, one deterministic render.
    func manifestInput() throws -> ManifestInputSnapshot {
        try database.queue.read { db in
            try ManifestInputBuilder.snapshot(in: db)
        }
    }
}
