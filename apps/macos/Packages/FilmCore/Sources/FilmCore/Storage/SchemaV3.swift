import Foundation

/// The DDL of bundle schema v3 (PHASE1_DESIGN §4.2a; Plan 008 contract E1).
///
/// v3 exists for one reason: `scripts.format` gains `'pdf'`, and SQLite cannot widen a
/// `CHECK` in place. Only two tables are rebuilt, and each differs from its `SchemaV2`
/// twin in **exactly one `CHECK`** — everything else, down to column order, is copied so
/// the diff against `SchemaV2` reads as the whole change.
///
/// `SchemaV2` is deliberately **not** edited: v2 bundles exist in the wild, GRDB records
/// migrations by name, and retroactively changing the `"v2"` DDL would leave old and new
/// databases carrying different constraints under the same migration identifier.
enum SchemaV3 {
    /// `scripts` in its v3 shape: `format`'s `CHECK` gains `'pdf'`.
    static func scripts(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            display_name TEXT NOT NULL,
            source_asset_id TEXT NOT NULL REFERENCES project_assets(id),
            format TEXT NOT NULL CHECK (format IN ('fountain','fdx','text','pdf')),
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

    /// `projects` in its v3 shape: `bundle_schema_version`'s `CHECK` pins `3`.
    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 3),
            current_script_id TEXT REFERENCES scripts(id) ON DELETE SET NULL,
            disclosure_acknowledged_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """
    }

    /// §4.2a step 3: every index the v2 schema declares over the two rebuilt tables, and
    /// no others. `projects` declares none — its `id` index is materialized by the primary
    /// key — so `scripts(project_id)` (§4.2 step 8) is the whole list. They are recreated
    /// **after** both rebuilds because a `DROP TABLE` takes its indexes with it.
    static let rebuiltTableIndexes = """
        CREATE INDEX index_scripts_on_project_id ON scripts(project_id);
        """
}
