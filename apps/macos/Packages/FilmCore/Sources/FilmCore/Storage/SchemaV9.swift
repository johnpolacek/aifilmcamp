import Foundation

/// Bundle schema v9 replaces singular scene prompts with versioned prompt sets.
enum SchemaV9 {
    static let prov = SchemaV2.prov

    static var promptTables: String {
        """
        CREATE TABLE scene_prompt_sets (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
            target_profile TEXT NOT NULL,
            set_number INTEGER NOT NULL CHECK (set_number >= 1),
            skill_id TEXT NOT NULL DEFAULT '',
            skill_entry_path TEXT NOT NULL DEFAULT '',
            skill_entry_sha256 TEXT NOT NULL DEFAULT '',
            input_digest TEXT NOT NULL,
            input_format_version INTEGER NOT NULL CHECK (input_format_version >= 1),
            human_edited INTEGER NOT NULL DEFAULT 0 CHECK (human_edited IN (0, 1)),
            \(prov),
            UNIQUE(scene_id, target_profile, set_number),
            CHECK ((created_source = 'ai') = (skill_id <> '')),
            CHECK ((skill_id <> '') = (skill_entry_path <> '')),
            CHECK ((skill_id <> '') = (skill_entry_sha256 <> ''))
        );
        CREATE TABLE scene_prompt_cards (
            id TEXT PRIMARY KEY NOT NULL,
            set_id TEXT NOT NULL REFERENCES scene_prompt_sets(id) ON DELETE CASCADE,
            card_order INTEGER NOT NULL CHECK (card_order >= 1),
            title TEXT NOT NULL DEFAULT '',
            body TEXT NOT NULL,
            guidance TEXT NOT NULL DEFAULT '',
            duration_seconds INTEGER,
            aspect_ratio TEXT NOT NULL DEFAULT '',
            resolution TEXT NOT NULL DEFAULT '',
            UNIQUE(set_id, card_order)
        );
        CREATE TABLE scene_prompt_card_references (
            id TEXT PRIMARY KEY NOT NULL,
            card_id TEXT NOT NULL REFERENCES scene_prompt_cards(id) ON DELETE CASCADE,
            position INTEGER NOT NULL CHECK (position >= 1),
            requirement_id TEXT REFERENCES asset_requirements(id) ON DELETE SET NULL,
            version_id TEXT REFERENCES asset_versions(id) ON DELETE SET NULL,
            class TEXT NOT NULL CHECK (class IN ('identity','look','location','prop')),
            role TEXT NOT NULL,
            exclusion TEXT NOT NULL DEFAULT '',
            fidelity TEXT NOT NULL CHECK (fidelity IN
                ('full_preserve','partial_preserve','attribute_transfer','loose_guide')),
            sha256 TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            pixel_width INTEGER,
            pixel_height INTEGER,
            display_name TEXT NOT NULL,
            source TEXT NOT NULL CHECK (source IN ('parser','ai','human')),
            job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL,
            UNIQUE(card_id, position)
        );
        CREATE INDEX index_scene_prompt_card_references_on_requirement_id
            ON scene_prompt_card_references(requirement_id);
        CREATE INDEX index_scene_prompt_card_references_on_version_id
            ON scene_prompt_card_references(version_id);
        """
    }

    /// Transitional SQL views keep already-journaled v8 operations invertible. They are
    /// not canonical storage: reads and new writes use the three v9 tables. Existing
    /// `RowSnapshot` payloads can still INSERT/UPDATE/DELETE their old table names, with
    /// triggers translating the one-card shape losslessly.
    static var legacyPromptViews: String {
        """
        CREATE VIEW scene_prompts AS
        SELECT s.id, s.project_id, s.scene_id, s.target_profile,
               s.set_number AS prompt_number,
               c.body, c.guidance, c.duration_seconds, c.aspect_ratio, c.resolution,
               s.skill_id, s.skill_entry_path, s.skill_entry_sha256,
               s.input_digest, s.input_format_version,
               s.source, s.confidence, s.review_state, s.reviewed_at, s.job_id,
               s.created_source, s.created_at, s.updated_at
        FROM scene_prompt_sets s
        JOIN scene_prompt_cards c ON c.set_id = s.id AND c.card_order = 1;

        CREATE VIEW scene_prompt_references AS
        SELECT r.id, r.card_id AS prompt_id, r.position, r.requirement_id, r.version_id,
                r.class, r.role, r.exclusion, r.fidelity, r.sha256, r.display_name,
               r.source, r.job_id, r.created_at
        FROM scene_prompt_card_references r;

        CREATE TRIGGER legacy_scene_prompts_insert INSTEAD OF INSERT ON scene_prompts
        BEGIN
            INSERT INTO scene_prompt_sets (
                id, project_id, scene_id, target_profile, set_number,
                skill_id, skill_entry_path, skill_entry_sha256,
                input_digest, input_format_version, human_edited,
                source, confidence, review_state, reviewed_at, job_id,
                created_source, created_at, updated_at
            ) VALUES (
                NEW.id, NEW.project_id, NEW.scene_id, NEW.target_profile, NEW.prompt_number,
                NEW.skill_id, NEW.skill_entry_path, NEW.skill_entry_sha256,
                NEW.input_digest, NEW.input_format_version,
                CASE WHEN NEW.source = 'human' THEN 1 ELSE 0 END,
                NEW.source, NEW.confidence, NEW.review_state, NEW.reviewed_at, NEW.job_id,
                NEW.created_source, NEW.created_at, NEW.updated_at
            );
            INSERT INTO scene_prompt_cards (
                id, set_id, card_order, title, body, guidance,
                duration_seconds, aspect_ratio, resolution
            ) VALUES (
                NEW.id, NEW.id, 1, '', NEW.body, NEW.guidance,
                NEW.duration_seconds, NEW.aspect_ratio, NEW.resolution
            );
        END;
        CREATE TRIGGER legacy_scene_prompts_update INSTEAD OF UPDATE ON scene_prompts
        BEGIN
            UPDATE scene_prompt_sets SET
                target_profile = NEW.target_profile,
                set_number = NEW.prompt_number,
                skill_id = NEW.skill_id,
                skill_entry_path = NEW.skill_entry_path,
                skill_entry_sha256 = NEW.skill_entry_sha256,
                input_digest = NEW.input_digest,
                input_format_version = NEW.input_format_version,
                source = NEW.source, confidence = NEW.confidence,
                review_state = NEW.review_state, reviewed_at = NEW.reviewed_at,
                job_id = NEW.job_id, created_source = NEW.created_source,
                updated_at = NEW.updated_at,
                human_edited = CASE WHEN NEW.source = 'human' THEN 1 ELSE 0 END
            WHERE id = OLD.id;
            UPDATE scene_prompt_cards SET
                body = NEW.body, guidance = NEW.guidance,
                duration_seconds = NEW.duration_seconds,
                aspect_ratio = NEW.aspect_ratio, resolution = NEW.resolution
            WHERE id = OLD.id;
        END;
        CREATE TRIGGER legacy_scene_prompts_delete INSTEAD OF DELETE ON scene_prompts
        BEGIN
            DELETE FROM scene_prompt_sets WHERE id = OLD.id;
        END;

        CREATE TRIGGER legacy_scene_prompt_references_insert
        INSTEAD OF INSERT ON scene_prompt_references
        BEGIN
            INSERT INTO scene_prompt_card_references (
                id, card_id, position, requirement_id, version_id,
                class, role, exclusion, fidelity, sha256, relative_path,
                pixel_width, pixel_height, display_name,
                source, job_id, created_at
            ) VALUES (
                NEW.id, NEW.prompt_id, NEW.position, NEW.requirement_id, NEW.version_id,
                NEW.class, NEW.role, NEW.exclusion, NEW.fidelity, NEW.sha256,
                COALESCE((SELECT relative_path FROM asset_versions WHERE id = NEW.version_id), ''),
                (SELECT pixel_width FROM asset_versions WHERE id = NEW.version_id),
                (SELECT pixel_height FROM asset_versions WHERE id = NEW.version_id),
                NEW.display_name, NEW.source, NEW.job_id, NEW.created_at
            );
        END;
        CREATE TRIGGER legacy_scene_prompt_references_delete
        INSTEAD OF DELETE ON scene_prompt_references
        BEGIN
            DELETE FROM scene_prompt_card_references WHERE id = OLD.id;
        END;
        """
    }

    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 9),
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
