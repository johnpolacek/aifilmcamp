import Foundation

enum SchemaV10 {
    static let imageGenerationTables = """
        CREATE TABLE image_generation_runs (
            id TEXT PRIMARY KEY NOT NULL,
            requirement_id TEXT REFERENCES asset_requirements(id) ON DELETE SET NULL,
            prompt_id TEXT REFERENCES asset_prompts(id) ON DELETE SET NULL,
            provider_id TEXT NOT NULL,
            model_id TEXT NOT NULL,
            helper_protocol_version INTEGER NOT NULL CHECK (helper_protocol_version >= 1),
            prompt_body_sha256 TEXT NOT NULL CHECK (length(prompt_body_sha256) = 64),
            aspect_ratio TEXT NOT NULL CHECK (aspect_ratio IN ('2:3','16:9','1:1')),
            requested_width INTEGER NOT NULL CHECK (requested_width > 0),
            requested_height INTEGER NOT NULL CHECK (requested_height > 0),
            resolution_label TEXT NOT NULL CHECK (resolution_label = '1K'),
            candidate_count INTEGER NOT NULL CHECK (candidate_count BETWEEN 1 AND 4),
            selected_candidate_index INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            CHECK (selected_candidate_index >= 0 AND selected_candidate_index < candidate_count)
        );
        CREATE TABLE image_generation_references (
            run_id TEXT NOT NULL REFERENCES image_generation_runs(id) ON DELETE CASCADE,
            position INTEGER NOT NULL CHECK (position >= 1),
            requirement_id TEXT REFERENCES asset_requirements(id) ON DELETE SET NULL,
            version_id TEXT REFERENCES asset_versions(id) ON DELETE SET NULL,
            sha256 TEXT NOT NULL CHECK (length(sha256) = 64),
            byte_count INTEGER NOT NULL CHECK (byte_count > 0),
            entity_kind TEXT NOT NULL CHECK (entity_kind IN
                ('character','location','prop','vehicle','creature','object')),
            PRIMARY KEY(run_id, position)
        );
        CREATE INDEX index_image_generation_runs_on_requirement_id
            ON image_generation_runs(requirement_id);
        CREATE INDEX index_image_generation_runs_on_prompt_id
            ON image_generation_runs(prompt_id);
        CREATE INDEX index_image_generation_references_on_version_id
            ON image_generation_references(version_id);
        ALTER TABLE asset_versions ADD COLUMN image_generation_run_id TEXT
            REFERENCES image_generation_runs(id) ON DELETE SET NULL;
        ALTER TABLE asset_versions ADD COLUMN generation_candidate_index INTEGER
            CHECK (generation_candidate_index IS NULL OR generation_candidate_index >= 0);
        CREATE UNIQUE INDEX index_asset_versions_on_image_generation_candidate
            ON asset_versions(image_generation_run_id, generation_candidate_index)
            WHERE image_generation_run_id IS NOT NULL;
        """

    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 10),
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
