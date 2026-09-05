import CryptoKit
import Foundation
import GRDB

// The scene-prompt input (PHASE5_DESIGN §8.2; Plan 018 contract E).
//
// A **FilmCore** type for the same reason `AssetPromptInputBuilder` is: §8.4 step 0
// rebuilds the rendered input *inside* the apply transaction and compares its digest with
// the run's recorded value, and §3.3/§3.4 derive package staleness from the same rebuild.
//
// **§8.2's field list below is the single normative definition of the digest input set**;
// no field is optional and absent values render as `''` / `0` / empty arrays, never as
// omitted keys. Screenplay body text **is** included (§14.4, accepted) — the scene's own
// UTF-16 slice of `scripts.source_text`, disclosed at §9. Unsatisfied rows and derived
// reference attributes render on purpose: approving an unsatisfied requirement changes the
// digest, and a rules change is a digest change by construction.

// MARK: - The §8.2 shape

/// The whole §8.2 input for one scene. Every collection is an ordered array — the encoded
/// shape contains no dictionary (determinism rule 2).
public struct ScenePromptInput: Codable, Equatable, Sendable {
    /// Determinism rule 4: the rendered input carries its own version, recorded on each
    /// prompt row as `input_format_version` (§4.3). Any rendered-shape change bumps
    /// `ScenePromptInputBuilder.schemaVersion` — there is no digest re-stamp migration.
    public let schemaVersion: Int
    public let targetProfile: ScenePromptInputProfile
    public let scene: ScenePromptInputScene
    /// The scene's resolved screenplay body: its human override when present, otherwise
    /// the imported `[start_utf16, end_utf16)` slice (§14.4).
    public let sceneText: String
    /// Optional filmmaker-authored performance, blocking, eyeline, and camera intent for
    /// this scene. This is creative direction, not screenplay replacement.
    public let creativeDirection: String
    /// The project document, verbatim (`''` when empty — never an omitted key, §3.6).
    public let styleBible: String
    public let continuity: [ScenePromptInputContinuity]
    public let entities: [ScenePromptInputEntity]
    public let references: [ScenePromptInputReference]
    public let unsatisfied: [ScenePromptInputUnsatisfied]

    public init(
        schemaVersion: Int = ScenePromptInputBuilder.schemaVersion,
        targetProfile: ScenePromptInputProfile,
        scene: ScenePromptInputScene,
        sceneText: String,
        creativeDirection: String = "",
        styleBible: String,
        continuity: [ScenePromptInputContinuity],
        entities: [ScenePromptInputEntity],
        references: [ScenePromptInputReference],
        unsatisfied: [ScenePromptInputUnsatisfied]
    ) {
        self.schemaVersion = schemaVersion
        self.targetProfile = targetProfile
        self.scene = scene
        self.sceneText = sceneText
        self.creativeDirection = creativeDirection
        self.styleBible = styleBible
        self.continuity = continuity
        self.entities = entities
        self.references = references
        self.unsatisfied = unsatisfied
    }
}

/// The active profile's record (§8.2): id, displayName, constraints, budget.
public struct ScenePromptInputProfile: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// Inclusive seconds bounds; both `0` when the profile carries no range (§14.2's
    /// `generic`) — never omitted keys.
    public let durationMin: Int
    public let durationMax: Int
    public let aspectRatios: [String]
    public let resolutions: [String]
    public let imageReferenceLimit: Int

    public init(
        id: String,
        displayName: String,
        durationMin: Int,
        durationMax: Int,
        aspectRatios: [String],
        resolutions: [String],
        imageReferenceLimit: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.durationMin = durationMin
        self.durationMax = durationMax
        self.aspectRatios = aspectRatios
        self.resolutions = resolutions
        self.imageReferenceLimit = imageReferenceLimit
    }
}

/// The scene's own record (§8.2): ordinal, heading, synopsis, intExt, timeOfDay.
public struct ScenePromptInputScene: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let heading: String
    /// `''` when none.
    public let synopsis: String
    public let intExt: String
    /// `''` when none.
    public let timeOfDay: String

    public init(
        ordinal: Int, heading: String, synopsis: String, intExt: String, timeOfDay: String
    ) {
        self.ordinal = ordinal
        self.heading = heading
        self.synopsis = synopsis
        self.intExt = intExt
        self.timeOfDay = timeOfDay
    }
}

/// One continuity entry (§8.2): entity, category, description — the §3.2 context.
public struct ScenePromptInputContinuity: Codable, Equatable, Sendable {
    public let entity: String
    public let category: String
    public let description: String

    public init(entity: String, category: String, description: String) {
        self.entity = entity
        self.category = category
        self.description = description
    }
}

/// One appearing entity's record (§8.2): name, aliases, description, and the reference
/// material available for it — its satisfied plan rows, each carrying its dense designator,
/// so the skill can bind `@Image k` handles to characters without guessing.
public struct ScenePromptInputEntity: Codable, Equatable, Sendable {
    public struct Material: Codable, Equatable, Sendable {
        public let designator: String
        public let `class`: ReferenceClass
        public let name: String

        public init(designator: String, class: ReferenceClass, name: String) {
            self.designator = designator
            self.class = `class`
            self.name = name
        }
    }

    public let name: String
    /// Sorted; `[]` when none.
    public let aliases: [String]
    public let description: String
    public let materials: [Material]

    public init(
        name: String, aliases: [String], description: String, materials: [Material]
    ) {
        self.name = name
        self.aliases = aliases
        self.description = description
        self.materials = materials
    }
}

/// One rendered reference (§8.2) — the satisfied subset, densely numbered, in §3.2 order,
/// carrying the derived attributes on purpose.
public struct ScenePromptInputReference: Codable, Equatable, Sendable {
    /// `'@Image 1' …`, over the satisfied rows alone (§3.2).
    public let designator: String
    public let `class`: ReferenceClass
    public let name: String
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
        self.role = role
        self.exclusion = exclusion
        self.fidelity = fidelity
        self.sha256 = sha256
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// One planned-but-unapproved row (§8.2), name + class — rendered on purpose so approving
/// one changes the digest and stales the prompt (§3.4's promise).
public struct ScenePromptInputUnsatisfied: Codable, Equatable, Sendable {
    public let name: String
    public let `class`: ReferenceClass

    public init(name: String, class: ReferenceClass) {
        self.name = name
        self.class = `class`
    }
}

/// The built input together with the exact text and its digest (§3.4).
///
/// `digest` is SHA-256 of the rendered JSON text — the value a run records as
/// `jobs.input_sha256` (the runner digests `input.text`; the `<scene-prompt-input>`
/// delimiter lives only in the prompt file, outside the digest). A generated prompt row
/// normally records the same value; when a one-time creative direction is present, the
/// row records the direction-free post-consumption snapshot so it remains fresh, while
/// the job and apply report retain this exact request digest for audit.
public struct ScenePromptInputSnapshot: Equatable, Sendable {
    public let input: ScenePromptInput
    public let text: String
    /// SHA-256 of `text`'s UTF-8 bytes, lowercase hex.
    public let digest: String

    public init(input: ScenePromptInput, text: String, digest: String) {
        self.input = input
        self.text = text
        self.digest = digest
    }

    /// The §8.1 budget's unit: UTF-16 code units.
    public var utf16Count: Int { text.utf16.count }
}

// MARK: - The builder

/// Builds §8.2's input for one scene from canonical data alone (PHASE5_DESIGN §8.2).
///
/// ## Determinism contract (the shipped five rules, adopted in full)
///
/// 1. **No SQL ordering is trusted.** Every collection is fetched and then ordered in
///    Swift by a total key ending in the row's `id` (references by the §3.2 key;
///    continuity by entity name, category, id; entities by name, id).
/// 2. **Key order is `sortedKeys`**, and every collection in the encoded shape is an array.
/// 3. **No clock, no locale, no floats, no environment**: no timestamps, every number an
///    `Int`, every string stored text, nothing from the run.
/// 4. **The rendered input carries `schemaVersion`.**
/// 5. **Every rendered-shape change bumps `schemaVersion`** so existing customer prompts
///    become explicitly stale. `ReferenceAttributeRules`'s tables are part of the output.
public enum ScenePromptInputBuilder {
    /// The rendered input's own version (see `ScenePromptInput.schemaVersion`). Bump on
    /// any rendered-shape change — including a `ReferenceAttributeRules` wording change;
    /// never re-stamp digests. Older rows read stale with the format reason.
    public static let schemaVersion = 4

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Renders and digests in one step. The override is used only when committing a
    /// generated result: the request is first verified against the pending direction,
    /// then the saved prompt is stamped against the clean post-consumption scene state.
    public static func snapshot(
        sceneID: UUID,
        creativeDirectionOverride: String? = nil,
        in db: Database
    ) throws -> ScenePromptInputSnapshot {
        let input = try build(
            sceneID: sceneID,
            creativeDirectionOverride: creativeDirectionOverride,
            in: db
        )
        let text = try render(input)
        let digest = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return ScenePromptInputSnapshot(input: input, text: text, digest: digest)
    }

    /// Renders the input to the exact text whose SHA-256 is the digest (§3.4).
    public static func render(_ input: ScenePromptInput) throws -> String {
        let data = try encoder.encode(input)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProjectStoreError.invalidBundle
        }
        return text
    }

    /// The §8.2 build, inside the caller's transaction.
    static func build(
        sceneID: UUID,
        creativeDirectionOverride: String? = nil,
        in db: Database
    ) throws -> ScenePromptInput {
        let graph = try ProjectRepository.readinessGraph(in: db)
        guard let scene = graph.scenes.first(where: { $0.id == sceneID }) else {
            throw ProjectStoreError.sceneNotFound
        }

        // The project's persisted active profile (§3.5); an id the catalog no longer
        // carries refuses naming it — never a crash.
        let profileID = try String.fetchOne(
            db, sql: "SELECT generation_target_profile FROM projects"
        ) ?? TargetProfileCatalog.defaultProfileID
        guard let profile = TargetProfileCatalog.profile(id: profileID) else {
            throw ProjectStoreError.generationTargetProfileMissing(id: profileID)
        }
        let styleBible = try String.fetchOne(db, sql: "SELECT style_bible FROM projects") ?? ""

        // The §3.2 plan and continuity context, through the one derivations.
        let plan = try ProjectRepository.sceneReferencePlan(
            sceneID: scene.id, graph: graph, in: db
        )
        let continuity = try ProjectRepository.sceneContinuityContext(
            sceneID: scene.id, graph: graph, in: db
        )

        // Human scene edits override the immutable imported screenplay slice.
        guard let textRow = try Row.fetchOne(
            db,
            sql: """
                SELECT scripts.source_text AS source_text,
                       scenes.screenplay_override AS screenplay_override,
                       scenes.prompt_direction AS prompt_direction,
                       scenes.start_utf16 AS start_utf16, scenes.end_utf16 AS end_utf16
                FROM scenes JOIN scripts ON scripts.id = scenes.script_id
                WHERE scenes.id = ?
                """,
            arguments: [scene.id.uuidString]
        ) else {
            throw ProjectStoreError.sceneNotFound
        }
        let sceneText: String
        if let override: String = textRow["screenplay_override"] {
            sceneText = override
        } else {
            let sourceText: String = textRow["source_text"]
            let start: Int = textRow["start_utf16"]
            let end: Int = textRow["end_utf16"]
            sceneText = sourceText.utf16Slice(start: start, end: end)
        }

        // Entities appearing in S (any visible role), ordered by name, then id —
        // determinism rule 1.
        struct AppearingEntity {
            let entity: Entity
            let aliases: [String]
        }
        var appearing: [AppearingEntity] = []
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT DISTINCT entities.* FROM entities
                JOIN scene_entities ON scene_entities.entity_id = entities.id
                WHERE scene_entities.scene_id = ?
                  AND scene_entities.role IN (\(ManifestQualification.visibleRoleSQLList))
                  AND scene_entities.review_state <> 'rejected'
                ORDER BY entities.id
                """,
            arguments: [scene.id.uuidString]
        ) {
            let entity = try decodeEntity(row)
            var aliases: [String] = []
            for aliasRow in try Row.fetchAll(
                db,
                sql: """
                    SELECT alias FROM entity_aliases
                    WHERE entity_id = ? AND review_state <> 'rejected'
                    """,
                arguments: [entity.id.uuidString]
            ) {
                aliases.append(aliasRow["alias"])
            }
            appearing.append(
                AppearingEntity(entity: entity, aliases: aliases.sorted())
            )
        }
        appearing.sort {
            ($0.entity.name.lowercased(), $0.entity.id.uuidString)
                < ($1.entity.name.lowercased(), $1.entity.id.uuidString)
        }

        // Per-entity material pointers: the satisfied plan rows of that entity, by designator.
        func materials(for entityID: UUID) -> [ScenePromptInputEntity.Material] {
            plan.compactMap { row in
                guard let designator = row.designator,
                      graph.manifest.requirements[row.requirementID]?.entityID == entityID
                else { return nil }
                return ScenePromptInputEntity.Material(
                    designator: "@Image \(designator)", class: row.class,
                    name: "\(row.entityName) — \(row.requirementName)"
                )
            }
        }

        let input = ScenePromptInput(
            targetProfile: ScenePromptInputProfile(
                id: profile.id,
                displayName: profile.displayName,
                durationMin: profile.durationRange?.lowerBound ?? 0,
                durationMax: profile.durationRange?.upperBound ?? 0,
                aspectRatios: profile.aspectRatios,
                resolutions: profile.resolutions,
                imageReferenceLimit: profile.imageReferenceLimit
            ),
            scene: ScenePromptInputScene(
                ordinal: scene.ordinal,
                heading: scene.heading,
                synopsis: scene.synopsis,
                intExt: scene.intExt.rawValue,
                timeOfDay: scene.timeOfDay
            ),
            sceneText: sceneText,
            creativeDirection: creativeDirectionOverride
                ?? (textRow["prompt_direction"] as String? ?? ""),
            styleBible: styleBible,
            continuity: continuity.entries.map { entry in
                ScenePromptInputContinuity(
                    entity: entry.entityName,
                    category: entry.category.rawValue,
                    description: entry.description
                )
            },
            entities: appearing.map { appearing in
                ScenePromptInputEntity(
                    name: appearing.entity.name,
                    aliases: appearing.aliases,
                    description: appearing.entity.description,
                    materials: materials(for: appearing.entity.id)
                )
            },
            references: plan.compactMap { row -> ScenePromptInputReference? in
                guard let approved = row.approvedVersion, let designator = row.designator
                else { return nil }
                return ScenePromptInputReference(
                    designator: "@Image \(designator)",
                    class: row.class,
                    name: "\(row.entityName) — \(row.requirementName)",
                    role: row.attributes.role,
                    exclusion: row.attributes.exclusion,
                    fidelity: row.attributes.fidelity,
                    sha256: approved.sha256,
                    pixelWidth: approved.pixelWidth ?? 0,
                    pixelHeight: approved.pixelHeight ?? 0
                )
            },
            unsatisfied: plan.compactMap { row -> ScenePromptInputUnsatisfied? in
                guard !row.isSatisfied else { return nil }
                return ScenePromptInputUnsatisfied(
                    name: "\(row.entityName) — \(row.requirementName)", class: row.class
                )
            }
        )
        return input
    }
}

// MARK: - The §8.1 pre-flight budget

/// The §8.1 pre-flight cap for one scene's rendered input, in UTF-16 code units — the
/// house unit, defaulted at 120 000 like its asset-scale sibling. Over budget refuses
/// naming the size, never truncates.
public enum ScenePromptInputBudget {
    /// The pinned default (Plan 018 contract E).
    public static let defaultUTF16Limit = 120_000

    public static func measure(_ text: String) -> Int { text.utf16.count }

    public static func check(text: String, limit: Int = defaultUTF16Limit) throws {
        let measured = measure(text)
        guard measured <= limit else {
            throw ProjectStoreError.scenePromptInputOverBudget(
                measuredUTF16: measured, limitUTF16: limit
            )
        }
    }
}
