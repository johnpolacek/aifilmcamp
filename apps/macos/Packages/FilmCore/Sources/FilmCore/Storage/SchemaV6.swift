import Foundation
import GRDB

/// The DDL of bundle schema v6 (PHASE5_DESIGN §4.2, §4.3; Plan 018 contract A).
///
/// v6 is the scene-package schema: three new tables (`scene_prompts`,
/// `scene_prompt_references`, `imported_skills`), three `projects` columns, and one
/// small rebuild (`projects` pins `bundle_schema_version = 6`). The spelling here is
/// §4.3's, statement for statement, so the file can be diffed against the design.
///
/// `SchemaV2`–`SchemaV5` are deliberately **not** edited, for the recorded Phase 1
/// reason: bundles at those versions exist and GRDB records migrations by name.
enum SchemaV6 {
    /// The provenance columns every fact row carries (§4.3's `PROV`) — the shared block
    /// reused **verbatim** from `SchemaV2`, not a second spelling of it.
    static let prov = SchemaV2.prov

    // MARK: - §4.2 step 1: the new tables and their indexes

    /// The three new tables, in FK dependency order: `scene_prompts` first, then its
    /// `scene_prompt_references` citations, then `imported_skills` (which only the
    /// rebuilt `projects.scene_skill_id` references).
    ///
    /// `scene_prompts` is the Phase 3 prompt-table shape at scene scope (§4.3): the
    /// settings columns (`duration_seconds` / `aspect_ratio` / `resolution`) replace the
    /// asset table's single `target_model`, and the UNIQUE key spans
    /// `(scene_id, target_profile, prompt_number)` — prompts are current per
    /// `(scene, profile)` pair (§3.1). The `created_source = 'ai'` ⟺ skill-triple CHECKs
    /// carry over verbatim from `asset_prompts`.
    static var newTables: String {
        """
        CREATE TABLE scene_prompts (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
            target_profile TEXT NOT NULL,
            prompt_number INTEGER NOT NULL CHECK (prompt_number >= 1),
            body TEXT NOT NULL,
            guidance TEXT NOT NULL DEFAULT '',
            duration_seconds INTEGER,
            aspect_ratio TEXT NOT NULL DEFAULT '',
            resolution TEXT NOT NULL DEFAULT '',
            skill_id TEXT NOT NULL DEFAULT '',
            skill_entry_path TEXT NOT NULL DEFAULT '',
            skill_entry_sha256 TEXT NOT NULL DEFAULT '',
            input_digest TEXT NOT NULL,
            input_format_version INTEGER NOT NULL CHECK (input_format_version >= 1),
            \(prov),
            UNIQUE(scene_id, target_profile, prompt_number),
            CHECK ((created_source = 'ai') = (skill_id <> '')),
            CHECK ((skill_id <> '') = (skill_entry_path <> '')),
            CHECK ((skill_id <> '') = (skill_entry_sha256 <> ''))
        );
        CREATE TABLE scene_prompt_references (
            id TEXT PRIMARY KEY NOT NULL,
            prompt_id TEXT NOT NULL REFERENCES scene_prompts(id) ON DELETE CASCADE,
            position INTEGER NOT NULL CHECK (position >= 1),
            requirement_id TEXT REFERENCES asset_requirements(id) ON DELETE SET NULL,
            version_id TEXT REFERENCES asset_versions(id) ON DELETE SET NULL,
            class TEXT NOT NULL CHECK (class IN ('identity','look','location','prop')),
            role TEXT NOT NULL,
            exclusion TEXT NOT NULL DEFAULT '',
            fidelity TEXT NOT NULL CHECK (fidelity IN
                ('full_preserve','partial_preserve','attribute_transfer','loose_guide')),
            sha256 TEXT NOT NULL,
            display_name TEXT NOT NULL,
            source TEXT NOT NULL CHECK (source IN ('parser','ai','human')),
            job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL,
            UNIQUE(prompt_id, position)
        );
        CREATE TABLE imported_skills (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            display_name TEXT NOT NULL,
            relative_root TEXT NOT NULL UNIQUE,
            entry_relative_path TEXT NOT NULL,
            routing_relative_path TEXT NOT NULL DEFAULT '',
            tree_sha256 TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """
    }

    /// The two `ON DELETE SET NULL` scan-path indexes over the citation rows, mirroring
    /// the v5 pattern (§4.2 step 1). `scene_prompts` gets **no** separate index: its
    /// `UNIQUE(scene_id, target_profile, prompt_number)` materializes the scene-led index
    /// every package read takes. `imported_skills` gets none either: its UNIQUE
    /// `relative_root` materializes the only one nothing else needs.
    static let newTableIndexes = """
        CREATE INDEX index_scene_prompt_references_on_requirement_id ON scene_prompt_references(requirement_id);
        CREATE INDEX index_scene_prompt_references_on_version_id ON scene_prompt_references(version_id);
        """

    // MARK: - Rebuilt tables

    /// `projects` in its v6 shape: `bundle_schema_version`'s `CHECK` pins `6`, plus §4.3's
    /// three new columns — the style bible (§3.6), the persisted active target profile
    /// (§3.5, default `seedance_2_5` per §14.2), and the selected custom skill (§14.6,
    /// `NULL` meaning the bundled default; SET NULL so undoing an import clears it).
    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 6),
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
