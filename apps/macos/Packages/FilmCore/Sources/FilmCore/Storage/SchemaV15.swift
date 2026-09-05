import Foundation

/// Bundle schema v15 adds filmmaker-authored creative direction for scene prompt
/// generation. It is distinct from screenplay text: performance, blocking, eyelines,
/// and camera intent can change without rewriting the imported scene.
enum SchemaV15 {
    static let scenePromptDirection = """
        ALTER TABLE scenes ADD COLUMN prompt_direction TEXT NOT NULL DEFAULT '';
        """

    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 15),
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
