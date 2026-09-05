import Foundation

/// The DDL of bundle schema v2 (PHASE1_DESIGN §4.3), split so the `"v2"` migration and a
/// fresh `create` execute exactly the same statements in exactly the §4.2 order.
///
/// Kept as SQL rather than GRDB table builders because the migration mixes `CREATE`,
/// `INSERT … SELECT`, `DROP`, and `ALTER … RENAME` on the same tables, and one spelling
/// of the schema is easier to audit against §4.3 than two.
enum SchemaV2 {
    /// The provenance columns every fact row carries (§4.3's `PROV`).
    static let prov = """
        source TEXT NOT NULL CHECK (source IN ('parser','ai','human')),
        confidence REAL CHECK (confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0)),
        review_state TEXT NOT NULL CHECK (review_state IN ('proposed','accepted','rejected')),
        reviewed_at TEXT,
        job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL,
        created_source TEXT NOT NULL CHECK (created_source IN ('parser','ai','human')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
        """

    // MARK: - §4.2 step 1: the new tables and their indexes

    static var newTables: String {
        """
        CREATE TABLE sequences (
            id TEXT PRIMARY KEY NOT NULL,
            script_id TEXT NOT NULL REFERENCES scripts(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL,
            depth INTEGER NOT NULL,
            title TEXT NOT NULL,
            start_utf16 INTEGER NOT NULL,
            end_utf16 INTEGER NOT NULL,
            \(prov),
            UNIQUE(script_id, ordinal)
        );
        CREATE TABLE entities (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK (kind IN ('character','location','prop','vehicle','creature','object')),
            name TEXT NOT NULL,
            name_normalized TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            parent_id TEXT REFERENCES entities(id) ON DELETE SET NULL
                CHECK (parent_id IS NULL OR parent_id <> id),
            is_relevant INTEGER NOT NULL DEFAULT 1,
            \(prov),
            UNIQUE(project_id, kind, name_normalized)
        );
        CREATE TABLE entity_aliases (
            id TEXT PRIMARY KEY NOT NULL,
            entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK (kind IN ('character','location','prop','vehicle','creature','object')),
            alias TEXT NOT NULL,
            normalized TEXT NOT NULL,
            alias_kind TEXT NOT NULL CHECK (alias_kind IN ('cue','heading','mention','human')),
            \(prov),
            UNIQUE(project_id, kind, normalized)
        );
        CREATE TABLE scene_exclusions (
            id TEXT PRIMARY KEY NOT NULL,
            scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK (kind IN ('note','boneyard')),
            start_utf16 INTEGER NOT NULL,
            end_utf16 INTEGER NOT NULL
        );
        CREATE TABLE scene_entities (
            id TEXT PRIMARY KEY NOT NULL,
            scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
            entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            role TEXT NOT NULL CHECK (role IN ('speaking','present','mentioned','setting','used')),
            matched_alias_id TEXT REFERENCES entity_aliases(id) ON DELETE SET NULL,
            \(prov),
            UNIQUE(scene_id, entity_id, role)
        );
        CREATE TABLE entity_states (
            id TEXT PRIMARY KEY NOT NULL,
            entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            category TEXT NOT NULL CHECK (category IN ('wardrobe','hair','makeup','injury','age',
                'condition','possession','time_of_day','weather','lighting','damage','other')),
            description TEXT NOT NULL,
            start_scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
            end_scene_id TEXT REFERENCES scenes(id) ON DELETE SET NULL,
            \(prov)
        );
        CREATE TABLE continuity_events (
            id TEXT PRIMARY KEY NOT NULL,
            scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
            entity_id TEXT REFERENCES entities(id) ON DELETE CASCADE,
            description TEXT NOT NULL,
            resulting_state_id TEXT REFERENCES entity_states(id) ON DELETE SET NULL,
            \(prov)
        );
        CREATE TABLE entity_relationships (
            id TEXT PRIMARY KEY NOT NULL,
            from_entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            to_entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK (kind IN ('family','romantic','professional','adversarial','possession','other')),
            description TEXT NOT NULL,
            \(prov),
            UNIQUE(from_entity_id, to_entity_id, kind)
        );
        CREATE TABLE evidence (
            id TEXT PRIMARY KEY NOT NULL,
            subject_kind TEXT NOT NULL CHECK (subject_kind IN ('entity','alias','appearance','state','event','relationship','synopsis')),
            subject_id TEXT NOT NULL,
            owner_entity_id TEXT REFERENCES entities(id) ON DELETE CASCADE
                CHECK ((subject_kind = 'synopsis') = (owner_entity_id IS NULL)),
            scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
            matched_alias_id TEXT REFERENCES entity_aliases(id) ON DELETE SET NULL,
            start_utf16 INTEGER,
            end_utf16 INTEGER,
            anchored INTEGER NOT NULL
                CHECK ((anchored = 1) = (start_utf16 IS NOT NULL AND end_utf16 IS NOT NULL)),
            quote TEXT NOT NULL,
            source TEXT NOT NULL CHECK (source IN ('parser','ai','human')),
            job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL
        );
        CREATE TABLE locks (
            subject_kind TEXT NOT NULL CHECK (subject_kind IN ('entity','alias','scene','state','event','relationship')),
            subject_id TEXT NOT NULL,
            field TEXT NOT NULL,
            locked_at TEXT NOT NULL,
            PRIMARY KEY(subject_kind, subject_id, field)
        );
        CREATE TABLE edit_journal (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            at TEXT NOT NULL,
            actor TEXT NOT NULL CHECK (actor IN ('human','ai')),
            job_id TEXT,
            inverts_seq INTEGER REFERENCES edit_journal(seq) ON DELETE SET NULL,
            op TEXT NOT NULL,
            payload TEXT NOT NULL
        );
        CREATE TABLE edit_journal_affected (
            seq INTEGER NOT NULL REFERENCES edit_journal(seq) ON DELETE CASCADE,
            subject_kind TEXT NOT NULL,
            subject_id TEXT NOT NULL,
            PRIMARY KEY(seq, subject_kind, subject_id)
        );
        """
    }

    /// The indexes over the new tables. `entity_aliases(project_id, kind, normalized)` and
    /// `locks(subject_kind, subject_id)` are materialized by their `UNIQUE` / `PRIMARY KEY`
    /// constraints and are deliberately not created again.
    static let newTableIndexes = """
        CREATE INDEX index_entities_on_project_id_kind ON entities(project_id, kind);
        CREATE INDEX index_scene_entities_on_entity_id ON scene_entities(entity_id);
        CREATE INDEX index_scene_entities_on_scene_id ON scene_entities(scene_id);
        CREATE INDEX index_evidence_on_subject ON evidence(subject_kind, subject_id);
        CREATE INDEX index_evidence_on_scene_id ON evidence(scene_id);
        CREATE INDEX index_evidence_on_owner_entity_id ON evidence(owner_entity_id);
        CREATE INDEX index_entity_states_on_entity_id ON entity_states(entity_id);
        CREATE INDEX index_entity_states_on_start_scene_id ON entity_states(start_scene_id);
        CREATE INDEX index_entity_states_on_end_scene_id ON entity_states(end_scene_id);
        CREATE INDEX index_continuity_events_on_scene_id ON continuity_events(scene_id);
        CREATE INDEX index_continuity_events_on_entity_id ON continuity_events(entity_id);
        CREATE INDEX index_entity_relationships_on_to_entity_id ON entity_relationships(to_entity_id);
        CREATE INDEX index_edit_journal_on_job_id ON edit_journal(job_id);
        CREATE INDEX index_edit_journal_on_inverts_seq ON edit_journal(inverts_seq);
        CREATE INDEX index_scene_exclusions_on_scene_id ON scene_exclusions(scene_id);
        CREATE INDEX index_edit_journal_affected_on_subject ON edit_journal_affected(subject_kind, subject_id);
        """

    // MARK: - Rebuilt tables

    /// `scripts` in its v2 shape, under the name the rebuild creates it with.
    static func scripts(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            display_name TEXT NOT NULL,
            source_asset_id TEXT NOT NULL REFERENCES project_assets(id),
            format TEXT NOT NULL CHECK (format IN ('fountain','fdx','text')),
            original_asset_id TEXT NOT NULL REFERENCES project_assets(id) ON DELETE RESTRICT,
            source_text TEXT NOT NULL,
            sha256 TEXT NOT NULL,
            title_page_json TEXT NOT NULL DEFAULT '{}',
            parser_version TEXT NOT NULL,
            parse_warnings_json TEXT NOT NULL DEFAULT '[]',
            created_at TEXT NOT NULL
        );
        """
    }

    /// `jobs` in its v2 shape, under the name the rebuild creates it with.
    static func jobs(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            task TEXT NOT NULL,
            engine TEXT NOT NULL,
            engine_version TEXT NOT NULL,
            requested_model TEXT,
            effective_model TEXT,
            schema_version INTEGER NOT NULL,
            input_sha256 TEXT NOT NULL,
            state TEXT NOT NULL CHECK (state IN ('queued','discoveringHarness','running','validating','committing','paused','completed','failed','cancelled')),
            progress_stage TEXT NOT NULL,
            input_tokens INTEGER CHECK (input_tokens IS NULL OR input_tokens >= 0),
            cached_input_tokens INTEGER CHECK (cached_input_tokens IS NULL OR cached_input_tokens >= 0),
            cache_write_input_tokens INTEGER CHECK (cache_write_input_tokens IS NULL OR cache_write_input_tokens >= 0),
            output_tokens INTEGER CHECK (output_tokens IS NULL OR output_tokens >= 0),
            reasoning_output_tokens INTEGER CHECK (reasoning_output_tokens IS NULL OR reasoning_output_tokens >= 0),
            log_relative_path TEXT NOT NULL,
            result_relative_path TEXT NOT NULL,
            started_at TEXT,
            ended_at TEXT,
            failure_code TEXT,
            failure_message TEXT,
            parent_job_id TEXT REFERENCES jobs(id) ON DELETE RESTRICT,
            chunk_index INTEGER,
            chunk_count INTEGER,
            attempt_index INTEGER,
            supersedes_job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL,
            script_id TEXT REFERENCES scripts(id) ON DELETE SET NULL,
            script_sha256 TEXT,
            apply_report TEXT
        );
        """
    }

    /// `projects` in its v2 shape, under the name the rebuild creates it with.
    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 2),
            current_script_id TEXT REFERENCES scripts(id) ON DELETE SET NULL,
            disclosure_acknowledged_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """
    }

    /// `scenes` in its v2 shape. Recreated with no row copy: Phase 0's `CHECK (ordinal > 0)`
    /// forbids the preamble and its model-produced rows are replaced by the parser's.
    static let scenes = """
        CREATE TABLE scenes (
            id TEXT PRIMARY KEY NOT NULL,
            script_id TEXT NOT NULL REFERENCES scripts(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
            sequence_id TEXT REFERENCES sequences(id) ON DELETE SET NULL,
            heading TEXT NOT NULL,
            int_ext TEXT NOT NULL CHECK (int_ext IN ('int','ext','int_ext','unknown')),
            location_text TEXT NOT NULL,
            time_of_day TEXT NOT NULL,
            scene_number TEXT,
            start_utf16 INTEGER NOT NULL,
            end_utf16 INTEGER NOT NULL,
            synopsis TEXT NOT NULL DEFAULT '',
            synopsis_source TEXT CHECK (synopsis_source IS NULL OR synopsis_source IN ('parser','ai','human')),
            synopsis_created_source TEXT CHECK (synopsis_created_source IS NULL OR synopsis_created_source IN ('parser','ai','human')),
            synopsis_confidence REAL CHECK (synopsis_confidence IS NULL OR (synopsis_confidence >= 0.0 AND synopsis_confidence <= 1.0)),
            synopsis_review_state TEXT CHECK (synopsis_review_state IS NULL OR synopsis_review_state IN ('proposed','accepted','rejected')),
            synopsis_reviewed_at TEXT,
            synopsis_job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL,
            synopsis_updated_at TEXT,
            is_omitted INTEGER NOT NULL DEFAULT 0,
            UNIQUE(script_id, ordinal),
            UNIQUE(script_id, start_utf16)
        );
        """

    /// §4.2 step 8: the indexes over the rebuilt tables. They are created **after** the
    /// rebuilds — an index on a column the rebuild has not added yet fails with
    /// `no such column`, and one created before a `DROP TABLE` is dropped with it.
    static let rebuiltTableIndexes = """
        CREATE INDEX index_jobs_on_project_id ON jobs(project_id);
        CREATE INDEX index_jobs_on_parent_job_id ON jobs(parent_job_id);
        CREATE INDEX index_jobs_on_script_id ON jobs(script_id);
        CREATE INDEX index_jobs_on_supersedes_job_id ON jobs(supersedes_job_id);
        CREATE INDEX index_scripts_on_project_id ON scripts(project_id);
        CREATE INDEX index_scenes_on_script_id_ordinal ON scenes(script_id, ordinal);
        """

}
