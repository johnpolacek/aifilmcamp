import Foundation
import GRDB

/// Bundle schema v11 keeps the stable requirement-table shape and migrates the default
/// character identity policy to Plan 029's face + headless front/back bundle.
enum SchemaV11 {
    static let insertRequirementType = """
        INSERT INTO asset_requirement_types (
            id, project_id, entity_kind, code, display_name, sort_order, is_enabled,
            created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    /// Fresh-project seeding uses the current template. Historical v4 seeding remains
    /// byte-for-byte unchanged and converges through the v11 data migration.
    static func seedRequirementTemplate(
        projectID: String,
        now: String,
        in db: Database
    ) throws {
        for entry in DefaultRequirementTemplate.entries {
            try db.execute(
                sql: insertRequirementType,
                arguments: [
                    UUID().uuidString, projectID, entry.entityKind.rawValue, entry.code,
                    entry.displayName, entry.sortOrder, entry.isEnabled ? 1 : 0, now, now,
                ]
            )
        }
    }

    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 11),
            current_script_id TEXT REFERENCES scripts(id) ON DELETE SET NULL,
            disclosure_acknowledged_at TEXT,
            style_bible TEXT NOT NULL DEFAULT '',
            generation_target_profile TEXT NOT NULL DEFAULT 'seedance_2_5',
            scene_skill_id TEXT REFERENCES imported_skills(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """
    }
}
