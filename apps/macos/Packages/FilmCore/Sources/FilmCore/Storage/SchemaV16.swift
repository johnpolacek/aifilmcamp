import Foundation

/// Named outfit variants retain the immutable version they were copied from.
enum SchemaV16 {
    static let characterOutfits = """
        ALTER TABLE asset_requirements ADD COLUMN outfit_source_version_id TEXT
            CHECK (outfit_source_version_id IS NULL OR
                   (tier = 'variant' AND length(outfit_source_version_id) = 36));
        """

    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 16),
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
