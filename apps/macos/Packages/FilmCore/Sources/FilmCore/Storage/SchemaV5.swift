import Foundation
import GRDB

/// The DDL of bundle schema v5 (PHASE3_DESIGN §4.2, §4.3; Plan 013 contract A).
///
/// v5 is the prompt schema: two `ALTER TABLE` adds (`assets.in_progress_since`,
/// `asset_versions.prompt_id`), the two prompt tables with their citation rows, three
/// new indexes, and one small rebuild (`projects` pins `bundle_schema_version = 5`).
/// The spelling here is §4.3's, statement for statement, so the file can be diffed
/// against the design.
///
/// `SchemaV2`–`SchemaV4` are deliberately **not** edited, for the recorded Phase 1
/// reason: bundles at those versions exist and GRDB records migrations by name.
enum SchemaV5 {
    /// The provenance columns every fact row carries (§4.3's `PROV`) — the shared block
    /// reused **verbatim** from `SchemaV2`, not a second spelling of it.
    static let prov = SchemaV2.prov

    // MARK: - §4.2 step 1: `assets.in_progress_since`

    /// Nullable, no default: the marker is absent until `markAssetInProgress` sets it
    /// (§6.1/§7.2 — Plan 014's operations; Plan 013 creates only the column).
    static let addInProgressSince = """
        ALTER TABLE assets ADD COLUMN in_progress_since TEXT;
        """

    // MARK: - §4.2 step 2: the new tables and their indexes

    /// The two new tables, in FK dependency order: `asset_prompts` first, then its
    /// `asset_prompt_references` citations.
    static var newTables: String {
        """
        CREATE TABLE asset_prompts (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE,
            prompt_number INTEGER NOT NULL CHECK (prompt_number >= 1),
            body TEXT NOT NULL,
            target_model TEXT NOT NULL DEFAULT '',
            guidance TEXT NOT NULL DEFAULT '',
            skill_id TEXT NOT NULL DEFAULT '',
            skill_entry_path TEXT NOT NULL DEFAULT '',
            skill_entry_sha256 TEXT NOT NULL DEFAULT '',
            input_digest TEXT NOT NULL,
            input_format_version INTEGER NOT NULL CHECK (input_format_version >= 1),
            \(prov),
            UNIQUE(requirement_id, prompt_number),
            CHECK ((created_source = 'ai') = (skill_id <> '')),
            CHECK ((skill_id <> '') = (skill_entry_path <> '')),
            CHECK ((skill_id <> '') = (skill_entry_sha256 <> ''))
        );
        CREATE TABLE asset_prompt_references (
            id TEXT PRIMARY KEY NOT NULL,
            prompt_id TEXT NOT NULL REFERENCES asset_prompts(id) ON DELETE CASCADE,
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
        """
    }

    /// The two `ON DELETE SET NULL` scan-path indexes over the citation rows (§4.2
    /// step 2). `asset_prompts` gets **no** separate index: its
    /// `UNIQUE(requirement_id, prompt_number)` materializes the requirement-led index,
    /// per house rule (§4.2 step 2's stated deviation from Phase 2's `project_id`
    /// indexing — no read looks prompts up by project).
    static let newTableIndexes = """
        CREATE INDEX index_asset_prompt_references_on_requirement_id ON asset_prompt_references(requirement_id);
        CREATE INDEX index_asset_prompt_references_on_version_id ON asset_prompt_references(version_id);
        """

    // MARK: - §4.2 step 3: `asset_versions.prompt_id`

    /// Which prompt produced this version — an explicit `importAssetVersion` parameter
    /// (§7.3), `NULL` everywhere the caller does not pass one. SQLite admits a nullable
    /// added column carrying a `REFERENCES` clause, so no rebuild is needed; the scan
    /// path index lands beside it.
    static let addPromptID = """
        ALTER TABLE asset_versions ADD COLUMN prompt_id TEXT REFERENCES asset_prompts(id) ON DELETE SET NULL;
        """

    static let promptIDIndex = """
        CREATE INDEX index_asset_versions_on_prompt_id ON asset_versions(prompt_id);
        """

    // MARK: - Rebuilt tables

    /// `projects` in its v5 shape: `bundle_schema_version`'s `CHECK` pins `5`.
    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 5),
            current_script_id TEXT REFERENCES scripts(id) ON DELETE SET NULL,
            disclosure_acknowledged_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """
    }
}
