import Foundation

/// The built-in per-project requirement template (PHASE2_DESIGN §3.2).
///
/// `ProjectRepository.initialize` seeds this current policy immediately after inserting a
/// fresh project row. Schema v11 migrates the frozen v4 seed to the same result for older
/// projects.
///
/// The `code` values are **frozen identifiers**: seeding, tests, and §8.4's
/// prop-proposal mapping name entries by code, never by display name. Renaming one is a
/// design change, not a refactor.
///
/// `AssetRequirementType` below is the stored row; this constant deliberately carries only
/// what seeding needs — the template's *content* — so `SchemaV4`'s seeding does not depend
/// on ids, a project, or timestamps.
public enum DefaultRequirementTemplate {
    /// One default template row, before it is given an id, a project, or timestamps.
    public struct Entry: Equatable, Hashable, Sendable {
        public let entityKind: EntityKind
        /// The frozen slug (`[a-z0-9_]+`) stored in `asset_requirement_types.code`.
        public let code: String
        public let displayName: String
        /// Position within this entry's `entityKind`, 0-based, in §3.2's table order.
        public let sortOrder: Int
        /// Disabled legacy codes remain stored so existing projects and references retain
        /// their frozen identifiers without creating active canonical slots.
        public let isEnabled: Bool

        public init(
            entityKind: EntityKind,
            code: String,
            displayName: String,
            sortOrder: Int,
            isEnabled: Bool = true
        ) {
            self.entityKind = entityKind
            self.code = code
            self.displayName = displayName
            self.sortOrder = sortOrder
            self.isEnabled = isEnabled
        }
    }

    /// Plan 029's current table. Frozen legacy codes seed disabled.
    ///
    /// | entity kind | entries |
    /// |---|---|
    /// | character | `face_closeup`, disabled `profile_side`, disabled `waist_up`, `full_body` |
    /// | location | `establishing` |
    /// | prop, vehicle, creature, object | `reference` |
    public static let entries: [Entry] = [
        Entry(entityKind: .character, code: "face_closeup", displayName: "Face Closeup", sortOrder: 0),
        Entry(
            entityKind: .character, code: "profile_side", displayName: "Profile / Side",
            sortOrder: 1, isEnabled: false
        ),
        Entry(
            entityKind: .character, code: "waist_up", displayName: "Waist Up",
            sortOrder: 2, isEnabled: false
        ),
        Entry(
            entityKind: .character, code: "full_body",
            displayName: "Headless Full Body — Front + Back", sortOrder: 3
        ),
        Entry(entityKind: .location, code: "establishing", displayName: "Establishing View", sortOrder: 0),
        Entry(entityKind: .prop, code: "reference", displayName: "Reference View", sortOrder: 0),
        Entry(entityKind: .vehicle, code: "reference", displayName: "Reference View", sortOrder: 0),
        Entry(entityKind: .creature, code: "reference", displayName: "Reference View", sortOrder: 0),
        Entry(entityKind: .object, code: "reference", displayName: "Reference View", sortOrder: 0),
    ]
}

/// One `asset_requirement_types` row: the per-project template entry a canonical
/// requirement fills (PHASE2_DESIGN §3.2, §4.3, §4.4).
///
/// Template rows are **settings**, like `locks`: no PROV block, human-edited only,
/// journaled through §7.2's template operations (Plan 010). `code` is a frozen
/// `[a-z0-9_]+` slug; display names are normalized-unique per `(project, entityKind)` so
/// the requirement names generated from them cannot collide.
public struct AssetRequirementType: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let entityKind: EntityKind
    /// The stable slug — `face_closeup`, `establishing`, … — never the display name.
    public let code: String
    public let displayName: String
    /// Position within this entry's `entityKind`, 0-based.
    public let sortOrder: Int
    /// A disabled entry stops seeding new canonical requirements; existing rows stay and
    /// are badged instead (§5.3).
    public let isEnabled: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        projectID: UUID,
        entityKind: EntityKind,
        code: String,
        displayName: String,
        sortOrder: Int,
        isEnabled: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.entityKind = entityKind
        self.code = code
        self.displayName = displayName
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
