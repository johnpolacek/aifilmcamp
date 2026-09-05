import Foundation
import GRDB

/// The DDL of bundle schema v4 (PHASE2_DESIGN §4.3; Plan 009 contract A).
///
/// v4 is the asset-manifest schema: seven new tables, one `ALTER TABLE` on `entities`,
/// and two small rebuilds (`locks` widens its `subject_kind` CHECK, `projects` pins
/// `bundle_schema_version = 4`). The spelling here is §4.3's, statement for statement,
/// so the file can be diffed against the design.
///
/// `SchemaV2` and `SchemaV3` are deliberately **not** edited, for the recorded Phase 1
/// reason: bundles at those versions exist and GRDB records migrations by name.
enum SchemaV4 {
    /// The provenance columns every fact row carries (§4.3's `PROV`) — the shared block
    /// reused **verbatim** from `SchemaV2`, not a second spelling of it.
    static let prov = SchemaV2.prov

    // MARK: - §4.2 step 1: `entities.manifest_inclusion`

    /// Legal SQLite: constant default, column-level CHECK, so no `entities` rebuild.
    static let addManifestInclusion = """
        ALTER TABLE entities ADD COLUMN manifest_inclusion TEXT NOT NULL DEFAULT 'automatic'
            CHECK (manifest_inclusion IN ('automatic','always','never'));
        """

    // MARK: - §4.2 step 2: the new tables and their indexes

    /// The seven new tables, in FK dependency order: a table is created only after every
    /// table it references exists.
    static var newTables: String {
        """
        CREATE TABLE asset_requirement_types (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            entity_kind TEXT NOT NULL CHECK (entity_kind IN
                ('character','location','prop','vehicle','creature','object')),
            code TEXT NOT NULL,
            display_name TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(project_id, entity_kind, code)
        );
        CREATE TABLE asset_requirements (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            tier TEXT NOT NULL CHECK (tier IN ('canonical','variant')),
            type_id TEXT REFERENCES asset_requirement_types(id) ON DELETE RESTRICT
                CHECK ((tier = 'canonical') = (type_id IS NOT NULL)),
            name TEXT NOT NULL,
            name_normalized TEXT NOT NULL,
            reason TEXT NOT NULL DEFAULT '',
            necessity TEXT NOT NULL DEFAULT 'required'
                CHECK (necessity IN ('required','optional','not_needed')),
            \(prov),
            UNIQUE(entity_id, type_id),
            UNIQUE(entity_id, name_normalized)
        );
        CREATE TABLE asset_requirement_scenes (
            id TEXT PRIMARY KEY NOT NULL,
            requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE,
            scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
            \(prov),
            UNIQUE(requirement_id, scene_id)
        );
        CREATE TABLE asset_requirement_basis (
            id TEXT PRIMARY KEY NOT NULL,
            requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE,
            subject_kind TEXT NOT NULL CHECK (subject_kind IN ('state','event','appearance')),
            subject_id TEXT NOT NULL,
            source TEXT NOT NULL CHECK (source IN ('parser','ai','human')),
            job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL,
            UNIQUE(requirement_id, subject_kind, subject_id)
        );
        CREATE TABLE asset_dependencies (
            id TEXT PRIMARY KEY NOT NULL,
            requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE,
            depends_on_requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE
                CHECK (depends_on_requirement_id <> requirement_id),
            \(prov),
            UNIQUE(requirement_id, depends_on_requirement_id)
        );
        CREATE TABLE assets (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            requirement_id TEXT NOT NULL UNIQUE REFERENCES asset_requirements(id) ON DELETE RESTRICT,
            status TEXT NOT NULL CHECK (status IN
                ('needed','prompt_ready','in_progress','needs_review','approved',
                 'rejected','deprecated')),
            is_stale INTEGER NOT NULL DEFAULT 0 CHECK (is_stale IN (0, 1)),
            stale_since TEXT,
            stale_reason TEXT,
            rejected_explicitly INTEGER NOT NULL DEFAULT 0
                CHECK (rejected_explicitly IN (0, 1)),
            notes TEXT NOT NULL DEFAULT '',
            \(prov),
            CHECK ((is_stale = 1) = (stale_since IS NOT NULL)),
            CHECK ((is_stale = 1) = (stale_reason IS NOT NULL))
        );
        CREATE TABLE asset_versions (
            id TEXT PRIMARY KEY NOT NULL,
            asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
            version_number INTEGER NOT NULL CHECK (version_number >= 1),
            status TEXT NOT NULL CHECK (status IN ('needs_review','approved','rejected')),
            relative_path TEXT NOT NULL,
            sha256 TEXT NOT NULL,
            byte_count INTEGER NOT NULL CHECK (byte_count > 0),
            original_file_name TEXT NOT NULL,
            media_kind TEXT NOT NULL CHECK (media_kind IN ('image')),
            pixel_width INTEGER CHECK (pixel_width IS NULL OR pixel_width > 0),
            pixel_height INTEGER CHECK (pixel_height IS NULL OR pixel_height > 0),
            notes TEXT NOT NULL DEFAULT '',
            \(prov),
            UNIQUE(asset_id, version_number),
            UNIQUE(relative_path)
        );
        """
    }

    /// The indexes over the new tables (§4.2 step 2). Constraints that already
    /// materialize an index (`UNIQUE`, `PRIMARY KEY`) are not indexed again — which is
    /// why `asset_requirement_basis` gets none: its `UNIQUE` leads on `requirement_id`.
    /// `index_asset_requirements_on_entity_id` leads on `entity_id`, the column every FK
    /// lookup and cascade actually uses; `project_id` is a constant in a one-project
    /// database.
    static let newTableIndexes = """
        CREATE INDEX index_asset_requirements_on_entity_id ON asset_requirements(entity_id);
        CREATE INDEX index_asset_requirements_on_type_id ON asset_requirements(type_id);
        CREATE INDEX index_asset_requirement_scenes_on_scene_id ON asset_requirement_scenes(scene_id);
        CREATE INDEX index_asset_dependencies_on_depends_on_requirement_id ON asset_dependencies(depends_on_requirement_id);
        CREATE INDEX index_assets_on_project_id ON assets(project_id);
        CREATE INDEX index_asset_versions_on_asset_id ON asset_versions(asset_id);
        CREATE UNIQUE INDEX index_asset_versions_approved
            ON asset_versions(asset_id) WHERE status = 'approved';
        """

    // MARK: - Rebuilt tables

    /// `locks` in its v4 shape: `subject_kind`'s `CHECK` gains `'requirement'`. Every
    /// other column is copied from the v2 spelling. `field` still carries no `CHECK`,
    /// which is why the new lock fields (§7.5) need no schema change.
    static func locks(table: String) -> String {
        """
        CREATE TABLE \(table) (
            subject_kind TEXT NOT NULL CHECK (subject_kind IN ('entity','alias','scene','state','event','relationship','requirement')),
            subject_id TEXT NOT NULL,
            field TEXT NOT NULL,
            locked_at TEXT NOT NULL,
            PRIMARY KEY(subject_kind, subject_id, field)
        );
        """
    }

    /// `projects` in its v4 shape: `bundle_schema_version`'s `CHECK` pins `4`.
    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 4),
            current_script_id TEXT REFERENCES scripts(id) ON DELETE SET NULL,
            disclosure_acknowledged_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """
    }

    // MARK: - §4.2 step 3: template seeding

    /// Inserts one historical-v4 `asset_requirement_types` row. Fresh projects use
    /// SchemaV11's current-policy seeder.
    static let insertRequirementType = """
        INSERT INTO asset_requirement_types (
            id, project_id, entity_kind, code, display_name, sort_order, is_enabled,
            created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
        """

    /// Seeds the frozen v4 default for one project. Later migrations own later policy.
    static func seedRequirementTemplate(
        projectID: String,
        now: String,
        in db: Database
    ) throws {
        // Historical v4 seed. Do not point this old migration at the current template:
        // schema v11 owns the forward policy change and fresh projects seed through it.
        let entries: [DefaultRequirementTemplate.Entry] = [
            .init(
                entityKind: .character, code: "face_closeup",
                displayName: "Face Closeup", sortOrder: 0
            ),
            .init(
                entityKind: .character, code: "profile_side",
                displayName: "Profile / Side", sortOrder: 1
            ),
            .init(
                entityKind: .character, code: "waist_up",
                displayName: "Waist Up", sortOrder: 2
            ),
            .init(
                entityKind: .character, code: "full_body",
                displayName: "Full Body", sortOrder: 3
            ),
            .init(
                entityKind: .location, code: "establishing",
                displayName: "Establishing View", sortOrder: 0
            ),
            .init(
                entityKind: .prop, code: "reference",
                displayName: "Reference View", sortOrder: 0
            ),
            .init(
                entityKind: .vehicle, code: "reference",
                displayName: "Reference View", sortOrder: 0
            ),
            .init(
                entityKind: .creature, code: "reference",
                displayName: "Reference View", sortOrder: 0
            ),
            .init(
                entityKind: .object, code: "reference",
                displayName: "Reference View", sortOrder: 0
            ),
        ]
        for entry in entries {
            try db.execute(
                sql: insertRequirementType,
                arguments: [
                    UUID().uuidString, projectID, entry.entityKind.rawValue, entry.code,
                    entry.displayName, entry.sortOrder, now, now,
                ]
            )
        }
    }
}
