import Foundation

/// Bundle schema v13 adds human-authored, scene-specific reference exclusions. The
/// requirement, entity appearance, media, and every other scene remain untouched.
enum SchemaV13 {
    static let sceneReferenceExclusions = """
        CREATE TABLE scene_reference_exclusions (
            id TEXT PRIMARY KEY NOT NULL,
            scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
            requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE,
            created_at TEXT NOT NULL,
            UNIQUE(scene_id, requirement_id)
        );
        CREATE INDEX index_scene_reference_exclusions_on_scene_id
            ON scene_reference_exclusions(scene_id);
        """

    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 13),
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
