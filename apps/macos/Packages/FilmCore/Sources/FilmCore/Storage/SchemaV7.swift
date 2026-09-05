import Foundation

/// Bundle schema v7 repairs the evidence ownership invariant for scene-wide events.
///
/// `continuity_events.entity_id` and extraction's `events[].entityName` have always been
/// nullable, but v2's evidence CHECK admitted a NULL owner only for synopsis rows. The
/// mismatch made an otherwise-valid entity-less AI event fail the entire apply transaction.
/// Existing migrations stay immutable; v7 rebuilds `evidence` and pins `projects` to 7.
enum SchemaV7 {
    static func evidence(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            subject_kind TEXT NOT NULL CHECK (subject_kind IN ('entity','alias','appearance','state','event','relationship','synopsis')),
            subject_id TEXT NOT NULL,
            owner_entity_id TEXT REFERENCES entities(id) ON DELETE CASCADE
                CHECK (
                    (subject_kind = 'synopsis' AND owner_entity_id IS NULL)
                    OR subject_kind = 'event'
                    OR (subject_kind NOT IN ('synopsis','event') AND owner_entity_id IS NOT NULL)
                ),
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
        """
    }

    static let evidenceIndexes = """
        CREATE INDEX index_evidence_on_subject ON evidence(subject_kind, subject_id);
        CREATE INDEX index_evidence_on_scene_id ON evidence(scene_id);
        CREATE INDEX index_evidence_on_owner_entity_id ON evidence(owner_entity_id);
        """

    static func projects(table: String) -> String {
        """
        CREATE TABLE \(table) (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 7),
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
