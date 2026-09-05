import Foundation

/// Bundle schema v12 persists a successful image edit's human-authored visual amendment
/// on its immutable generation run. Existing runs remain valid with no amendment text.
enum SchemaV12 {
    static let visualAmendmentColumns = """
        ALTER TABLE image_generation_runs ADD COLUMN visual_amendment TEXT
            CHECK (visual_amendment IS NULL OR
                   (length(trim(visual_amendment)) > 0 AND length(CAST(visual_amendment AS BLOB)) <= 65536));
        ALTER TABLE image_generation_runs ADD COLUMN visual_amendment_scope TEXT
            CHECK (visual_amendment_scope IS NULL OR
                   visual_amendment_scope IN ('requirement','character_bundle'));
        CREATE TABLE image_generation_amendments (
            run_id TEXT NOT NULL REFERENCES image_generation_runs(id) ON DELETE CASCADE,
            position INTEGER NOT NULL CHECK (position >= 1),
            amendment_run_id TEXT NOT NULL,
            requirement_id TEXT NOT NULL,
            version_id TEXT NOT NULL,
            instruction TEXT NOT NULL
                CHECK (length(trim(instruction)) > 0 AND length(CAST(instruction AS BLOB)) <= 65536),
            scope TEXT NOT NULL CHECK (scope IN ('requirement','character_bundle')),
            created_at TEXT NOT NULL,
            PRIMARY KEY(run_id, position),
            UNIQUE(run_id, amendment_run_id)
        );
        """

    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 12),
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
