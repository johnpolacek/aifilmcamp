import CryptoKit
import Foundation
import FilmScript
import GRDB
import Synchronization

/// What a migration did, for `UpgradeSummary` (Plan 003 contract B).
///
/// The `"v2"` closure writes its counters into a `Mutex`-guarded box because GRDB's
/// migration closures return `Void`; `ProjectMigrator.migrate` hands the box's contents back.
struct MigrationOutcome: Equatable, Sendable {
    var sceneCount: Int = 0
    var entityCount: Int = 0
    var sequenceCount: Int = 0
    /// Non-empty Phase 0 synopses the parser's scene count could not accommodate (§4.2 step 5).
    var synopsesDropped: Int = 0
    var parseWarnings: [ParseWarning] = []
}

/// The `Mutex`-guarded box the `"v2"` closure writes its counters into.
///
/// A `Mutex` is noncopyable, so it cannot be captured by GRDB's escaping migration
/// closure directly; a `Sendable` reference type holding one can.
final class MigrationOutcomeBox: Sendable {
    private let storage = Mutex<MigrationOutcome?>(nil)

    var value: MigrationOutcome? { storage.withLock { $0 } }

    func set(_ outcome: MigrationOutcome) { storage.withLock { $0 = outcome } }
}

enum ProjectMigrator {
    static let currentVersion = FilmCoreVersion.bundleSchema

    /// Runs every pending migration. Returns the `"v2"` outcome when that migration ran,
    /// `nil` when it did not (a bundle already at v2 or later). `"v3"` reports nothing.
    @discardableResult
    static func migrate(_ queue: DatabaseQueue) throws -> MigrationOutcome? {
        let box = MigrationOutcomeBox()
        try makeMigrator(outcome: box).migrate(queue)
        return box.value
    }

    /// Every registered migration, retained so projects can upgrade from any shipped schema.
    private static func makeMigrator(outcome box: MigrationOutcomeBox) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        registerV1(&migrator)
        registerV2(&migrator, outcome: box)
        registerV3(&migrator)
        registerV4(&migrator)
        registerV5(&migrator)
        registerV6(&migrator)
        registerV7(&migrator)
        registerV8(&migrator)
        registerV9(&migrator)
        registerV10(&migrator)
        registerV11(&migrator)
        registerV12(&migrator)
        registerV13(&migrator)
        registerV14(&migrator)
        registerV15(&migrator)
        registerV16(&migrator)
        return migrator
    }

    // MARK: - v1 (Phase 0)

    /// Still registered so an existing v1 bundle can replay it before `"v2"` runs.
    private static func registerV1(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE projects (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    bundle_schema_version INTEGER NOT NULL CHECK (bundle_schema_version = 1),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE project_assets (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    sha256 TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    UNIQUE(project_id, relative_path)
                );
                CREATE TABLE scripts (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    display_name TEXT NOT NULL,
                    source_asset_id TEXT NOT NULL REFERENCES project_assets(id),
                    source_text TEXT NOT NULL,
                    sha256 TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE scenes (
                    id TEXT PRIMARY KEY NOT NULL,
                    script_id TEXT NOT NULL REFERENCES scripts(id) ON DELETE CASCADE,
                    ordinal INTEGER NOT NULL CHECK (ordinal > 0),
                    heading TEXT NOT NULL,
                    synopsis TEXT NOT NULL,
                    UNIQUE(script_id, ordinal)
                );
                CREATE TABLE characters (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    payload_key TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    UNIQUE(project_id, payload_key)
                );
                CREATE TABLE locations (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    payload_key TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    UNIQUE(project_id, payload_key)
                );
                CREATE TABLE scene_characters (
                    scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
                    character_id TEXT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
                    PRIMARY KEY(scene_id, character_id)
                );
                CREATE TABLE scene_locations (
                    scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
                    location_id TEXT NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
                    PRIMARY KEY(scene_id, location_id),
                    UNIQUE(scene_id)
                );
                CREATE TABLE jobs (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    task TEXT NOT NULL,
                    engine TEXT NOT NULL,
                    engine_version TEXT NOT NULL,
                    requested_model TEXT,
                    effective_model TEXT,
                    schema_version INTEGER NOT NULL,
                    input_sha256 TEXT NOT NULL,
                    state TEXT NOT NULL CHECK (state IN ('queued','discoveringHarness','running','validating','committing','completed','failed','cancelled')),
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
                    failure_message TEXT
                );
                PRAGMA user_version = 1;
                """)
        }
    }

    // MARK: - v2

    /// Registered with GRDB's **default `foreignKeyChecks: .deferred`** — never
    /// `.immediate`: the `projects`, `scripts`, and `jobs` rebuilds rely on
    /// `PRAGMA foreign_keys = OFF`, and a `DROP TABLE` under enforcement would
    /// cascade-delete every child table. GRDB still runs `PRAGMA foreign_key_check`
    /// before committing, so nothing dangling survives.
    private static func registerV2(
        _ migrator: inout DatabaseMigrator,
        outcome box: MigrationOutcomeBox
    ) {
        migrator.registerMigration("v2") { db in
            var outcome = MigrationOutcome()
            let now = Date()

            // 1. New tables and the indexes on those new tables.
            try db.execute(sql: SchemaV2.newTables)
            try db.execute(sql: SchemaV2.newTableIndexes)

            // 2. Rebuild `scripts` and `jobs`, then backfill.
            try rebuildScripts(in: db)
            try rebuildJobs(in: db)
            let scripts = try Row.fetchAll(db, sql: "SELECT id, source_text FROM scripts ORDER BY created_at")
            let analysisJobID = try String.fetchOne(
                db,
                sql: """
                    SELECT id FROM jobs
                    WHERE task = 'analyzeScreenplay' AND state = 'completed'
                    ORDER BY COALESCE(ended_at, started_at, '') DESC, rowid DESC
                    LIMIT 1
                    """
            )
            // A fresh `create` runs both migrations over an empty database: there is no
            // project row yet, so every step below is a no-op on it.
            let projectID = try String.fetchOne(db, sql: "SELECT id FROM projects").map(UUID.required)

            var documents: [UUID: ScreenplayDocument] = [:]
            for row in scripts {
                let scriptID = try UUID.required(row["id"])
                let normalized = TextNormalization.normalize(row["source_text"])
                let document = FountainParser.parse(normalized, format: .fountain)
                documents[scriptID] = document
                let digest = SHA256.hash(data: Data(normalized.utf8))
                    .map { String(format: "%02x", $0) }.joined()
                try db.execute(
                    sql: """
                        UPDATE scripts
                        SET source_text = ?, sha256 = ?, format = 'fountain',
                            original_asset_id = source_asset_id, parser_version = ?,
                            title_page_json = ?, parse_warnings_json = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        normalized, digest, FilmScriptVersion.parser,
                        try encodedJSON(document.titlePage), try encodedJSON(document.warnings),
                        scriptID.uuidString,
                    ]
                )
                outcome.parseWarnings.append(contentsOf: document.warnings)
            }

            // 3. characters/locations → entities, grouped by EntityNormalization.normalize.
            if let projectID {
                try copyPhase0Entities(
                    kind: .character, table: "characters",
                    projectID: projectID, jobID: analysisJobID, now: now, in: db
                )
                try copyPhase0Entities(
                    kind: .location, table: "locations",
                    projectID: projectID, jobID: analysisJobID, now: now, in: db
                )
            }

            // 4. Phase 0 appearances are not carried over; step 5 regenerates them.
            try db.execute(sql: "DROP TABLE scene_characters; DROP TABLE scene_locations;")

            // 5. Rebuild `scenes` from the parse, with the §5.3 parser entity graph.
            let phase0Scenes = try Row.fetchAll(
                db, sql: "SELECT script_id, ordinal, synopsis FROM scenes ORDER BY script_id, ordinal"
            )
            var phase0Synopses: [UUID: [Int: String]] = [:]
            for row in phase0Scenes {
                let scriptID = try UUID.required(row["script_id"])
                phase0Synopses[scriptID, default: [:]][row["ordinal"]] = row["synopsis"]
            }
            try db.execute(sql: "DROP TABLE scenes;")
            try db.execute(sql: SchemaV2.scenes)

            for (scriptID, document) in documents.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                guard let projectID else { continue }
                let result = try ScreenplayWriter.write(
                    document: document,
                    projectID: projectID,
                    scriptID: scriptID,
                    jobID: analysisJobID.flatMap(UUID.init(uuidString:)),
                    now: now,
                    in: db
                )
                outcome.sceneCount += result.sceneCount
                outcome.sequenceCount += result.sequenceCount

                let old = phase0Synopses[scriptID] ?? [:]
                let nonEmpty = old.values.filter { !$0.isEmpty }.count
                // Phase 0 synopses carry over only when the parser's scene count equals the
                // old count (mapped by ordinal); otherwise every non-empty one is dropped.
                if old.count == result.sceneCount, let jobID = analysisJobID {
                    for (ordinal, synopsis) in old.sorted(by: { $0.key < $1.key })
                    where !synopsis.isEmpty {
                        guard let sceneID = result.sceneIDsByOrdinal[ordinal] else { continue }
                        try db.execute(
                            sql: """
                                UPDATE scenes
                                SET synopsis = ?, synopsis_source = 'ai', synopsis_created_source = 'ai',
                                    synopsis_review_state = 'proposed', synopsis_job_id = ?,
                                    synopsis_updated_at = ?
                                WHERE id = ?
                                """,
                            arguments: [synopsis, jobID, UTCDate.string(from: now), sceneID.uuidString]
                        )
                    }
                } else {
                    outcome.synopsesDropped += nonEmpty
                }
            }
            outcome.entityCount = try Int.fetchOne(db, sql: "SELECT count(*) FROM entities") ?? 0

            // 6. Backfill jobs.script_id from the single script.
            if let scriptID = try String.fetchOne(db, sql: "SELECT id FROM scripts ORDER BY created_at LIMIT 1") {
                try db.execute(sql: "UPDATE jobs SET script_id = ?", arguments: [scriptID])
            }

            // 7. Rebuild `projects` last, so current_script_id resolves.
            try rebuildProjects(in: db)
            try db.execute(sql: "DROP TABLE characters; DROP TABLE locations;")

            // 8. The indexes over the rebuilt tables.
            try db.execute(sql: SchemaV2.rebuiltTableIndexes)

            try db.execute(sql: "PRAGMA user_version = 2")
            box.set(outcome)
        }
    }

    // MARK: - v3 (Plan 008)

    /// Widens `scripts.format`'s `CHECK` to admit `'pdf'` (PHASE1_DESIGN §4.2a).
    ///
    /// Registered with the same **default `foreignKeyChecks: .deferred`** as `"v2"`, for
    /// the same reason: the two rebuilds need `PRAGMA foreign_keys = OFF` so a `DROP TABLE`
    /// does not cascade-delete every child row, and GRDB still runs `PRAGMA
    /// foreign_key_check` before committing.
    ///
    /// It deliberately takes **no** `MigrationOutcomeBox`. The box is single-slot and only
    /// `"v2"` has anything to report (scenes rebuilt, synopses dropped); v3 copies every row
    /// verbatim and reports nothing. On a v1 → v3 open `"v2"` fills the box and `"v3"` must
    /// leave it alone; on a v2 → v3 open it stays `nil`, which is what makes that upgrade
    /// invisible to the operator (§4.2a).
    private static func registerV3(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3") { db in
            // 1–2. Rebuild the two tables whose `CHECK`s changed. `scripts` goes first so
            // `projects.current_script_id`'s `REFERENCES scripts(id)` resolves against the
            // rebuilt table.
            try rebuildScriptsV3(in: db)
            try rebuildProjectsV3(in: db)
            // 3. The indexes over both rebuilt tables, after both rebuilds.
            try db.execute(sql: SchemaV3.rebuiltTableIndexes)
            try db.execute(sql: "PRAGMA user_version = 3")
        }
    }

    /// The v2 → v3 `scripts` rebuild. Every column, `NOT NULL`, default, and foreign key is
    /// unchanged; only `format`'s `CHECK` widens. The column list is explicit — never
    /// `SELECT *` — so a future column cannot be silently reordered into the wrong slot.
    ///
    /// The `_v3` suffix is not cosmetic: it keeps these table names distinct from the `"v2"`
    /// body's `scripts_v2`/`projects_v2`, which a v1 → v3 open runs minutes earlier.
    private static func rebuildScriptsV3(in db: Database) throws {
        try db.execute(sql: SchemaV3.scripts(table: "scripts_v3"))
        try db.execute(sql: """
            INSERT INTO scripts_v3 (
                id, project_id, display_name, source_asset_id, format, original_asset_id,
                source_text, sha256, title_page_json, parser_version, parse_warnings_json, created_at
            )
            SELECT id, project_id, display_name, source_asset_id, format, original_asset_id,
                   source_text, sha256, title_page_json, parser_version, parse_warnings_json, created_at
            FROM scripts;
            DROP TABLE scripts;
            ALTER TABLE scripts_v3 RENAME TO scripts;
            """)
    }

    /// The v2 → v3 `projects` rebuild: the `CHECK` pins `bundle_schema_version = 3`, so the
    /// `INSERT … SELECT` rewrites the stored value to the literal `3`.
    private static func rebuildProjectsV3(in db: Database) throws {
        try db.execute(sql: SchemaV3.projects(table: "projects_v3"))
        try db.execute(sql: """
            INSERT INTO projects_v3 (
                id, name, bundle_schema_version, current_script_id,
                disclosure_acknowledged_at, created_at, updated_at
            )
            SELECT id, name, 3, current_script_id,
                   disclosure_acknowledged_at, created_at, updated_at
            FROM projects;
            DROP TABLE projects;
            ALTER TABLE projects_v3 RENAME TO projects;
            """)
    }

    // MARK: - v4 (Plan 009)

    /// The asset-manifest schema (PHASE2_DESIGN §4.2): seven new tables, one `ALTER
    /// TABLE`, the seeded requirement template, and two small rebuilds.
    ///
    /// Registered with the same **default `foreignKeyChecks: .deferred`** as `"v2"` and
    /// `"v3"`: the `locks` and `projects` rebuilds need `PRAGMA foreign_keys = OFF` so a
    /// `DROP TABLE` does not cascade-delete every child row, and GRDB still runs
    /// `PRAGMA foreign_key_check` before committing.
    ///
    /// Like `"v3"` it takes **no** `MigrationOutcomeBox`: v3 → v4 is non-destructive —
    /// no re-parse, no row loss — so it reports nothing and shows no upgrade sheet.
    ///
    /// The step order is §4.2's and is load-bearing: the new tables come before the
    /// `locks` rebuild so nothing references them mid-flight, `projects` is rebuilt last
    /// so GRDB's terminal `PRAGMA foreign_key_check` sees the final graph, and indexes
    /// on rebuilt tables would be dropped with their table if created earlier (`locks`
    /// and `projects` have none to recreate — their `PRIMARY KEY`s materialize the only
    /// ones).
    private static func registerV4(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4") { db in
            // 1. `entities.manifest_inclusion`.
            try db.execute(sql: SchemaV4.addManifestInclusion)
            // 2. The new tables in dependency order, then their indexes.
            try db.execute(sql: SchemaV4.newTables)
            try db.execute(sql: SchemaV4.newTableIndexes)
            // 3. Seed the §3.2 template for the existing project row. A v3 bundle always
            // holds exactly one; a **fresh** bundle reaches v4 with zero project rows and
            // seeds nothing here — `ProjectRepository.initialize` seeds it instead, from
            // the same constant.
            if let projectID = try String.fetchOne(db, sql: "SELECT id FROM projects") {
                try SchemaV4.seedRequirementTemplate(
                    projectID: projectID, now: UTCDate.string(from: Date()), in: db
                )
            }
            // 4–5. The two rebuilds, `projects` last.
            try rebuildLocksV4(in: db)
            try rebuildProjectsV4(in: db)
            // 6.
            try db.execute(sql: "PRAGMA user_version = 4")
        }
    }

    /// The v3 → v4 `locks` rebuild: `subject_kind`'s `CHECK` gains `'requirement'`.
    /// Every row is copied with an explicit column list — never `SELECT *`. `locks` has
    /// no separate indexes to recreate and no foreign keys, so the rebuild is
    /// self-contained.
    private static func rebuildLocksV4(in db: Database) throws {
        try db.execute(sql: SchemaV4.locks(table: "locks_v4"))
        try db.execute(sql: """
            INSERT INTO locks_v4 (subject_kind, subject_id, field, locked_at)
            SELECT subject_kind, subject_id, field, locked_at
            FROM locks;
            DROP TABLE locks;
            ALTER TABLE locks_v4 RENAME TO locks;
            """)
    }

    /// The v3 → v4 `projects` rebuild: the `CHECK` pins `bundle_schema_version = 4`, so
    /// the `INSERT … SELECT` rewrites the stored value to the literal `4`. Every other
    /// column is copied unchanged.
    private static func rebuildProjectsV4(in db: Database) throws {
        try db.execute(sql: SchemaV4.projects(table: "projects_v4"))
        try db.execute(sql: """
            INSERT INTO projects_v4 (
                id, name, bundle_schema_version, current_script_id,
                disclosure_acknowledged_at, created_at, updated_at
            )
            SELECT id, name, 4, current_script_id,
                   disclosure_acknowledged_at, created_at, updated_at
            FROM projects;
            DROP TABLE projects;
            ALTER TABLE projects_v4 RENAME TO projects;
            """)
    }

    // MARK: - v5 (Plan 013)

    /// The prompt schema (PHASE3_DESIGN §4.2): two `ALTER TABLE` adds, the two prompt
    /// tables with their citation rows and three indexes, and one small rebuild.
    ///
    /// Registered with the same **default `foreignKeyChecks: .deferred`** as every
    /// predecessor: the `projects` rebuild needs `PRAGMA foreign_keys = OFF` so its
    /// `DROP TABLE` does not cascade-delete child rows, and GRDB still runs `PRAGMA
    /// foreign_key_check` before committing.
    ///
    /// Like `"v3"` and `"v4"` it takes no `MigrationOutcomeBox`: v4 → v5 is
    /// non-destructive — no re-parse, no row loss — so it reports nothing and shows no
    /// upgrade sheet (the §3.11 modal stays `schemaVersion == 1` only).
    ///
    /// The step order is §4.2's and is load-bearing: the new tables come before the
    /// `asset_versions` ALTER that references one of them; `projects` is rebuilt last so
    /// GRDB's terminal `PRAGMA foreign_key_check` sees the final graph; and there is
    /// deliberately **no `locks` rebuild** — the new subject kinds are not lockable
    /// (§7.4), so the v4 `locks` CHECK is already correct.
    private static func registerV5(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5") { db in
            // 1. `assets.in_progress_since`.
            try db.execute(sql: SchemaV5.addInProgressSince)
            // 2. The new tables in dependency order, then their SET-NULL scan-path
            //    indexes (`asset_prompts` gets none of its own — its UNIQUE pair
            //    materializes the requirement-led index).
            try db.execute(sql: SchemaV5.newTables)
            try db.execute(sql: SchemaV5.newTableIndexes)
            // 3. `asset_versions.prompt_id` and its scan-path index.
            try db.execute(sql: SchemaV5.addPromptID)
            try db.execute(sql: SchemaV5.promptIDIndex)
            // 4–5. The rebuild, `projects` last, then the version bump.
            try rebuildProjectsV5(in: db)
            try db.execute(sql: "PRAGMA user_version = 5")
        }
    }

    /// The v4 → v5 `projects` rebuild: the `CHECK` pins `bundle_schema_version = 5`, so
    /// the `INSERT … SELECT` rewrites the stored value to the literal `5`. Every other
    /// column is copied unchanged. No `projects` indexes exist to recreate.
    private static func rebuildProjectsV5(in db: Database) throws {
        try db.execute(sql: SchemaV5.projects(table: "projects_v5"))
        try db.execute(sql: """
            INSERT INTO projects_v5 (
                id, name, bundle_schema_version, current_script_id,
                disclosure_acknowledged_at, created_at, updated_at
            )
            SELECT id, name, 5, current_script_id,
                   disclosure_acknowledged_at, created_at, updated_at
            FROM projects;
            DROP TABLE projects;
            ALTER TABLE projects_v5 RENAME TO projects;
            """)
    }

    // MARK: - v6 (Plan 018)

    /// The scene-package schema (PHASE5_DESIGN §4.2): the three new tables with their
    /// citation-row indexes and one small rebuild.
    ///
    /// Registered with the same **default `foreignKeyChecks: .deferred`** as every
    /// predecessor: the `projects` rebuild needs `PRAGMA foreign_keys = OFF` so its
    /// `DROP TABLE` does not cascade-delete child rows, and GRDB still runs `PRAGMA
    /// foreign_key_check` before committing.
    ///
    /// Like `"v3"`–`"v5"` it takes no `MigrationOutcomeBox`: v5 → v6 is additive only —
    /// no row rewrites, no data transformation (§4.2) — so it reports nothing and shows no
    /// upgrade sheet.
    ///
    /// The step order is §4.2's and is load-bearing: the new tables come before the
    /// rebuild whose `scene_skill_id` references one of them; `projects` is rebuilt last
    /// so GRDB's terminal `PRAGMA foreign_key_check` sees the final graph. There is
    /// deliberately **no** `locks`, `asset_versions.media_kind`, or `jobs` change —
    /// scene prompts are not lockable, packages carry images only, and the scene run
    /// keys itself through the existing columns (§4.3).
    private static func registerV6(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v6") { db in
            // 1. The new tables in dependency order, then their SET-NULL scan-path
            //    indexes (`scene_prompts` and `imported_skills` get none of their own —
            //    their UNIQUE keys materialize the indexes every read takes).
            try db.execute(sql: SchemaV6.newTables)
            try db.execute(sql: SchemaV6.newTableIndexes)
            // 2–3. The rebuild, `projects` last, then the version bump.
            try rebuildProjectsV6(in: db)
            try db.execute(sql: "PRAGMA user_version = 6")
        }
    }

    /// The v5 → v6 `projects` rebuild: the `CHECK` pins `bundle_schema_version = 6`, so
    /// the `INSERT … SELECT` rewrites the stored value to the literal `6`. Every carried
    /// column is copied unchanged; the three new columns take their declared defaults
    /// (`''`, `'seedance_2_5'`) or `NULL` (`scene_skill_id`). No `projects` indexes exist
    /// to recreate.
    private static func rebuildProjectsV6(in db: Database) throws {
        try db.execute(sql: SchemaV6.projects(table: "projects_v6"))
        try db.execute(sql: """
            INSERT INTO projects_v6 (
                id, name, bundle_schema_version, current_script_id,
                disclosure_acknowledged_at, created_at, updated_at
            )
            SELECT id, name, 6, current_script_id,
                   disclosure_acknowledged_at, created_at, updated_at
            FROM projects;
            DROP TABLE projects;
            ALTER TABLE projects_v6 RENAME TO projects;
            """)
    }

    // MARK: - v7 (entity-less event evidence repair)

    private static func registerV7(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7") { db in
            try rebuildEvidenceV7(in: db)
            try rebuildProjectsV7(in: db)
            try db.execute(sql: "PRAGMA user_version = 7")
        }
    }

    private static func rebuildEvidenceV7(in db: Database) throws {
        try db.execute(sql: SchemaV7.evidence(table: "evidence_v7"))
        try db.execute(sql: """
            INSERT INTO evidence_v7 (
                id, subject_kind, subject_id, owner_entity_id, scene_id, matched_alias_id,
                start_utf16, end_utf16, anchored, quote, source, job_id, created_at
            )
            SELECT id, subject_kind, subject_id, owner_entity_id, scene_id, matched_alias_id,
                   start_utf16, end_utf16, anchored, quote, source, job_id, created_at
            FROM evidence;
            DROP TABLE evidence;
            ALTER TABLE evidence_v7 RENAME TO evidence;
            """)
        try db.execute(sql: SchemaV7.evidenceIndexes)
    }

    private static func rebuildProjectsV7(in db: Database) throws {
        try db.execute(sql: SchemaV7.projects(table: "projects_v7"))
        try db.execute(sql: """
            INSERT INTO projects_v7 (
                id, name, bundle_schema_version, current_script_id,
                disclosure_acknowledged_at, style_bible, generation_target_profile,
                scene_skill_id, created_at, updated_at
            )
            SELECT id, name, 7, current_script_id,
                   disclosure_acknowledged_at, style_bible, generation_target_profile,
                   scene_skill_id, created_at, updated_at
            FROM projects;
            DROP TABLE projects;
            ALTER TABLE projects_v7 RENAME TO projects;
            """)
    }

    // MARK: - v8 (validated AI output is active by default)

    private static func registerV8(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v8") { db in
            try ReviewOperations.activateAllProposedFacts(in: db)
            try rebuildProjectsV8(in: db)
            try db.execute(sql: "PRAGMA user_version = 8")
        }
    }

    private static func rebuildProjectsV8(in db: Database) throws {
        try db.execute(sql: SchemaV8.projects(table: "projects_v8"))
        try db.execute(sql: """
            INSERT INTO projects_v8 (
                id, name, bundle_schema_version, current_script_id,
                disclosure_acknowledged_at, style_bible, generation_target_profile,
                scene_skill_id, created_at, updated_at
            )
            SELECT id, name, 8, current_script_id,
                   disclosure_acknowledged_at, style_bible, generation_target_profile,
                   scene_skill_id, created_at, updated_at
            FROM projects;
            DROP TABLE projects;
            ALTER TABLE projects_v8 RENAME TO projects;
            """)
    }

    // MARK: - v9 (ordered scene prompt sets)

    private static func registerV9(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v9") { db in
            try db.execute(sql: SchemaV9.promptTables)

            // IDs may repeat across tables. Reusing the legacy prompt id for both the
            // set and its sole card keeps migration deterministic while preserving every
            // byte and the complete creation order/provenance history.
            try db.execute(sql: """
                INSERT INTO scene_prompt_sets (
                    id, project_id, scene_id, target_profile, set_number,
                    skill_id, skill_entry_path, skill_entry_sha256,
                    input_digest, input_format_version, human_edited,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                )
                SELECT id, project_id, scene_id, target_profile, prompt_number,
                       skill_id, skill_entry_path, skill_entry_sha256,
                       input_digest, input_format_version,
                       CASE WHEN source = 'human' THEN 1 ELSE 0 END,
                       source, confidence, review_state, reviewed_at, job_id,
                       created_source, created_at, updated_at
                FROM scene_prompts
                ORDER BY scene_id, target_profile, prompt_number;

                INSERT INTO scene_prompt_cards (
                    id, set_id, card_order, title, body, guidance,
                    duration_seconds, aspect_ratio, resolution
                )
                SELECT id, id, 1, '', body, guidance,
                       duration_seconds, aspect_ratio, resolution
                FROM scene_prompts
                ORDER BY scene_id, target_profile, prompt_number;

                INSERT INTO scene_prompt_card_references (
                    id, card_id, position, requirement_id, version_id,
                    class, role, exclusion, fidelity, sha256, relative_path,
                    pixel_width, pixel_height, display_name,
                    source, job_id, created_at
                )
                SELECT id, prompt_id, position, requirement_id, version_id,
                       class, role, exclusion, fidelity, sha256,
                       COALESCE((SELECT relative_path FROM asset_versions v WHERE v.id = version_id), ''),
                       (SELECT pixel_width FROM asset_versions v WHERE v.id = version_id),
                       (SELECT pixel_height FROM asset_versions v WHERE v.id = version_id),
                       display_name,
                       source, job_id, created_at
                FROM scene_prompt_references
                ORDER BY prompt_id, position;

                DROP TABLE scene_prompt_references;
                DROP TABLE scene_prompts;
                """)
            try db.execute(sql: SchemaV9.legacyPromptViews)
            try rebuildProjectsV9(in: db)
            try db.execute(sql: "PRAGMA user_version = 9")
        }
    }

    private static func rebuildProjectsV9(in db: Database) throws {
        try db.execute(sql: SchemaV9.projects(table: "projects_v9"))
        try db.execute(sql: """
            INSERT INTO projects_v9 (
                id, name, bundle_schema_version, current_script_id,
                disclosure_acknowledged_at, style_bible, generation_target_profile,
                scene_skill_id, created_at, updated_at
            )
            SELECT id, name, 9, current_script_id,
                   disclosure_acknowledged_at, style_bible, generation_target_profile,
                   scene_skill_id, created_at, updated_at
            FROM projects;
            DROP TABLE projects;
            ALTER TABLE projects_v9 RENAME TO projects;
            """)
    }

    // MARK: - v10 (direct-provider image-generation provenance)

    private static func registerV10(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v10") { db in
            try db.execute(sql: SchemaV10.imageGenerationTables)
            try db.execute(sql: SchemaV10.projects(table: "projects_v10"))
            try db.execute(sql: """
                INSERT INTO projects_v10 (
                    id, name, bundle_schema_version, current_script_id,
                    disclosure_acknowledged_at, style_bible, generation_target_profile,
                    scene_skill_id, created_at, updated_at
                )
                SELECT id, name, 10, current_script_id,
                       disclosure_acknowledged_at, style_bible, generation_target_profile,
                       scene_skill_id, created_at, updated_at
                FROM projects;
                DROP TABLE projects;
                ALTER TABLE projects_v10 RENAME TO projects;
                PRAGMA user_version = 10;
                """)
        }
    }

    // MARK: - v11 (character identity bundle)

    private static func registerV11(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v11") { db in
            let now = UTCDate.string(from: Date())
            try migrateCharacterIdentityBundle(now: now, in: db)
            try db.execute(sql: SchemaV11.projects(table: "projects_v11"))
            try db.execute(sql: """
                INSERT INTO projects_v11 (
                    id, name, bundle_schema_version, current_script_id,
                    disclosure_acknowledged_at, style_bible, generation_target_profile,
                    scene_skill_id, created_at, updated_at
                )
                SELECT id, name, 11, current_script_id,
                       disclosure_acknowledged_at, style_bible, generation_target_profile,
                       scene_skill_id, created_at, updated_at
                FROM projects;
                DROP TABLE projects;
                ALTER TABLE projects_v11 RENAME TO projects;
                PRAGMA user_version = 11;
                """)
        }
    }

    // MARK: - v12 (durable visual amendments)

    private static func registerV12(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v12") { db in
            try db.execute(sql: SchemaV12.visualAmendmentColumns)
            try db.execute(sql: SchemaV12.projects(table: "projects_v12"))
            try db.execute(sql: """
                INSERT INTO projects_v12 (
                    id, name, bundle_schema_version, current_script_id,
                    disclosure_acknowledged_at, style_bible, generation_target_profile,
                    scene_skill_id, created_at, updated_at
                )
                SELECT id, name, 12, current_script_id,
                       disclosure_acknowledged_at, style_bible, generation_target_profile,
                       scene_skill_id, created_at, updated_at
                FROM projects;
                DROP TABLE projects;
                ALTER TABLE projects_v12 RENAME TO projects;
                PRAGMA user_version = 12;
                """)
        }
    }

    // MARK: - v13 (scene-specific reference exclusions)

    private static func registerV13(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v13") { db in
            try db.execute(sql: SchemaV13.sceneReferenceExclusions)
            try db.execute(sql: SchemaV13.projects(table: "projects_v13"))
            try db.execute(sql: """
                INSERT INTO projects_v13 (
                    id, name, bundle_schema_version, current_script_id,
                    disclosure_acknowledged_at, style_bible, generation_target_profile,
                    scene_skill_id, created_at, updated_at
                )
                SELECT id, name, 13, current_script_id,
                       disclosure_acknowledged_at, style_bible, generation_target_profile,
                       scene_skill_id, created_at, updated_at
                FROM projects;
                DROP TABLE projects;
                ALTER TABLE projects_v13 RENAME TO projects;
                PRAGMA user_version = 13;
                """)
        }
    }

    // MARK: - v14 (scene screenplay overrides)

    private static func registerV14(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v14") { db in
            try db.execute(sql: SchemaV14.screenplayOverride)
            try db.execute(sql: SchemaV14.projects(table: "projects_v14"))
            try db.execute(sql: """
                INSERT INTO projects_v14 (
                    id, name, bundle_schema_version, current_script_id,
                    disclosure_acknowledged_at, style_bible, generation_target_profile,
                    scene_skill_id, created_at, updated_at
                )
                SELECT id, name, 14, current_script_id,
                       disclosure_acknowledged_at, style_bible, generation_target_profile,
                       scene_skill_id, created_at, updated_at
                FROM projects;
                DROP TABLE projects;
                ALTER TABLE projects_v14 RENAME TO projects;
                PRAGMA user_version = 14;
                """)
        }
    }

    // MARK: - v15 (scene prompt creative direction)

    private static func registerV15(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v15") { db in
            try db.execute(sql: SchemaV15.scenePromptDirection)
            try db.execute(sql: SchemaV15.projects(table: "projects_v15"))
            try db.execute(sql: """
                INSERT INTO projects_v15 (
                    id, name, bundle_schema_version, current_script_id,
                    disclosure_acknowledged_at, style_bible, generation_target_profile,
                    scene_skill_id, created_at, updated_at
                )
                SELECT id, name, 15, current_script_id,
                       disclosure_acknowledged_at, style_bible, generation_target_profile,
                       scene_skill_id, created_at, updated_at
                FROM projects;
                DROP TABLE projects;
                ALTER TABLE projects_v15 RENAME TO projects;
                PRAGMA user_version = 15;
                """)
        }
    }

    private static func registerV16(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v16") { db in
            try db.execute(sql: SchemaV16.characterOutfits)
            try db.execute(sql: SchemaV16.projects(table: "projects_v16"))
            try db.execute(sql: """
                INSERT INTO projects_v16 (
                    id, name, bundle_schema_version, current_script_id,
                    disclosure_acknowledged_at, style_bible, generation_target_profile,
                    scene_skill_id, created_at, updated_at
                )
                SELECT id, name, 16, current_script_id,
                       disclosure_acknowledged_at, style_bible, generation_target_profile,
                       scene_skill_id, created_at, updated_at
                FROM projects;
                DROP TABLE projects;
                ALTER TABLE projects_v16 RENAME TO projects;
                PRAGMA user_version = 16;
                """)
        }
    }

    /// Updates policy and derived state without deleting any creative record. Customized
    /// full-body labels are deliberately left alone; only the shipped default is renamed.
    private static func migrateCharacterIdentityBundle(now: String, in db: Database) throws {
        let newFullBodyName = "Headless Full Body — Front + Back"
        let newFullBodyNormalized = EntityNormalization.normalize(newFullBodyName)

        let defaultFullBodyTypeIDs = try String.fetchAll(
            db,
            sql: """
                SELECT id FROM asset_requirement_types
                WHERE entity_kind = 'character'
                  AND code = 'full_body'
                  AND display_name = 'Full Body'
                """
        )

        for typeID in defaultFullBodyTypeIDs {
            // Preserve a project-customized requirement name and avoid the cross-tier
            // normalized-name unique if a filmmaker already used the new label.
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT id, entity_id FROM asset_requirements
                    WHERE type_id = ? AND name = 'Full Body'
                    """,
                arguments: [typeID]
            ) {
                let requirementID: String = row["id"]
                let entityID: String = row["entity_id"]
                let collision = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT 1 FROM asset_requirements
                        WHERE entity_id = ? AND name_normalized = ? AND id <> ?
                        LIMIT 1
                        """,
                    arguments: [entityID, newFullBodyNormalized, requirementID]
                ) != nil
                guard !collision else { continue }
                try db.execute(
                    sql: """
                        UPDATE asset_requirements
                        SET name = ?, name_normalized = ?, updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [newFullBodyName, newFullBodyNormalized, now, requirementID]
                )
            }
            try db.execute(
                sql: """
                    UPDATE asset_requirement_types
                    SET display_name = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [newFullBodyName, now, typeID]
            )
        }

        // The stored legacy rows and their creative history remain. They simply stop
        // participating in the active manifest and readiness graph.
        try db.execute(
            sql: """
                UPDATE asset_requirement_types
                SET is_enabled = 0, updated_at = ?
                WHERE entity_kind = 'character'
                  AND code IN ('profile_side', 'waist_up')
                """,
            arguments: [now]
        )
        try db.execute(
            sql: """
                UPDATE asset_requirements
                SET necessity = 'not_needed', updated_at = ?
                WHERE type_id IN (
                    SELECT id FROM asset_requirement_types
                    WHERE entity_kind = 'character'
                      AND code IN ('profile_side', 'waist_up')
                )
                """,
            arguments: [now]
        )
        try db.execute(
            sql: """
                UPDATE asset_dependencies
                SET review_state = 'rejected', updated_at = ?
                WHERE review_state <> 'rejected'
                  AND depends_on_requirement_id IN (
                    SELECT requirement.id
                    FROM asset_requirements requirement
                    JOIN asset_requirement_types type ON type.id = requirement.type_id
                    WHERE type.entity_kind = 'character'
                      AND type.code IN ('profile_side', 'waist_up')
                  )
                """,
            arguments: [now]
        )
        try db.execute(
            sql: """
                UPDATE assets
                SET status = 'deprecated', updated_at = ?
                WHERE requirement_id IN (
                    SELECT requirement.id
                    FROM asset_requirements requirement
                    JOIN asset_requirement_types type ON type.id = requirement.type_id
                    WHERE type.entity_kind = 'character'
                      AND type.code IN ('profile_side', 'waist_up')
                )
                """,
            arguments: [now]
        )

        // An approved pre-v11 full-body image represents the former single-view contract.
        // Keep it approved and visible, but surface that it should be regenerated under
        // the new two-view sheet contract.
        try db.execute(
            sql: """
                UPDATE assets
                SET is_stale = 1,
                    stale_since = ?,
                    stale_reason = 'Character identity template changed to a headless front/back bundle.',
                    updated_at = ?
                WHERE requirement_id IN (
                    SELECT requirement.id
                    FROM asset_requirements requirement
                    JOIN asset_requirement_types type ON type.id = requirement.type_id
                    WHERE type.entity_kind = 'character' AND type.code = 'full_body'
                )
                  AND EXISTS (
                    SELECT 1 FROM asset_versions version
                    WHERE version.asset_id = assets.id AND version.status = 'approved'
                  )
                """,
            arguments: [now, now]
        )

        // INSERT OR IGNORE is intentional: the unique pair includes rejected dependency
        // tombstones, so a filmmaker's prior removal continues to win.
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT body.id AS body_id, face.id AS face_id
                FROM asset_requirements body
                JOIN asset_requirement_types body_type ON body_type.id = body.type_id
                JOIN asset_requirements face ON face.entity_id = body.entity_id
                JOIN asset_requirement_types face_type ON face_type.id = face.type_id
                WHERE body_type.entity_kind = 'character'
                  AND body_type.code = 'full_body'
                  AND face_type.entity_kind = 'character'
                  AND face_type.code = 'face_closeup'
                ORDER BY body.id
                """
        ) {
            let bodyID: String = row["body_id"]
            let faceID: String = row["face_id"]
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO asset_dependencies (
                        id, requirement_id, depends_on_requirement_id,
                        source, confidence, review_state, reviewed_at, job_id,
                        created_source, created_at, updated_at
                    ) VALUES (?, ?, ?, 'parser', NULL, 'accepted', NULL, NULL,
                              'parser', ?, ?)
                    """,
                arguments: [UUID().uuidString, bodyID, faceID, now, now]
            )
        }
    }

    // MARK: - Rebuilds

    /// `<name>_v2` → `INSERT … SELECT` → `DROP` → `RENAME`. SQLite cannot `ADD COLUMN` a
    /// `NOT NULL` column carrying `REFERENCES` (`scripts.original_asset_id`).
    private static func rebuildScripts(in db: Database) throws {
        try db.execute(sql: SchemaV2.scripts(table: "scripts_v2"))
        try db.execute(sql: """
            INSERT INTO scripts_v2 (
                id, project_id, display_name, source_asset_id, format, original_asset_id,
                source_text, sha256, title_page_json, parser_version, parse_warnings_json, created_at
            )
            SELECT id, project_id, display_name, source_asset_id, 'fountain', source_asset_id,
                   source_text, sha256, '{}', '', '[]', created_at
            FROM scripts;
            DROP TABLE scripts;
            ALTER TABLE scripts_v2 RENAME TO scripts;
            """)
    }

    /// Rebuilt because `jobs.state`'s `CHECK` gains `'paused'`.
    private static func rebuildJobs(in db: Database) throws {
        try db.execute(sql: SchemaV2.jobs(table: "jobs_v2"))
        try db.execute(sql: """
            INSERT INTO jobs_v2 (
                id, project_id, task, engine, engine_version, requested_model, effective_model,
                schema_version, input_sha256, state, progress_stage, input_tokens,
                cached_input_tokens, cache_write_input_tokens, output_tokens,
                reasoning_output_tokens, log_relative_path, result_relative_path,
                started_at, ended_at, failure_code, failure_message,
                parent_job_id, chunk_index, chunk_count, attempt_index, supersedes_job_id,
                script_id, script_sha256, apply_report
            )
            SELECT id, project_id, task, engine, engine_version, requested_model, effective_model,
                   schema_version, input_sha256, state, progress_stage, input_tokens,
                   cached_input_tokens, cache_write_input_tokens, output_tokens,
                   reasoning_output_tokens, log_relative_path, result_relative_path,
                   started_at, ended_at, failure_code, failure_message,
                   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
            FROM jobs;
            DROP TABLE jobs;
            ALTER TABLE jobs_v2 RENAME TO jobs;
            """)
    }

    /// Rebuilt because the Phase 0 `CHECK` pins `bundle_schema_version = 1`; the
    /// `INSERT … SELECT` rewrites the value to the literal `2`.
    private static func rebuildProjects(in db: Database) throws {
        try db.execute(sql: SchemaV2.projects(table: "projects_v2"))
        try db.execute(sql: """
            INSERT INTO projects_v2 (
                id, name, bundle_schema_version, current_script_id,
                disclosure_acknowledged_at, created_at, updated_at
            )
            SELECT id, name, 2,
                   (SELECT id FROM scripts WHERE scripts.project_id = projects.id
                    ORDER BY created_at LIMIT 1),
                   NULL, created_at, updated_at
            FROM projects;
            DROP TABLE projects;
            ALTER TABLE projects_v2 RENAME TO projects;
            """)
    }

    // MARK: - §4.2 step 3

    /// Copies one Phase 0 table into `entities`, grouped by `EntityNormalization.normalize`:
    /// the first row by `rowid` wins and later duplicates' names are retained as aliases on
    /// it. Every Phase 0 name becomes an `entity_aliases` row (`alias_kind = 'mention'`).
    private static func copyPhase0Entities(
        kind: EntityKind,
        table: String,
        projectID: UUID,
        jobID: String?,
        now: Date,
        in db: Database
    ) throws {
        let timestamp = UTCDate.string(from: now)
        var entityIDByNormalized: [String: UUID] = [:]
        let rows = try Row.fetchAll(db, sql: "SELECT name, description FROM \(table) ORDER BY rowid")

        for row in rows {
            let name: String = row["name"]
            let normalized = EntityNormalization.normalize(name)
            guard !normalized.isEmpty else { continue }

            let entityID: UUID
            if let existing = entityIDByNormalized[normalized] {
                entityID = existing
            } else {
                entityID = UUID()
                entityIDByNormalized[normalized] = entityID
                try db.execute(
                    sql: """
                        INSERT INTO entities (
                            id, project_id, kind, name, name_normalized, description, parent_id,
                            is_relevant, source, confidence, review_state, reviewed_at, job_id,
                            created_source, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, NULL, 1, 'ai', NULL, 'proposed', NULL, ?, 'ai', ?, ?)
                        """,
                    arguments: [
                        entityID.uuidString, projectID.uuidString, kind.rawValue, name, normalized,
                        row["description"] as String, jobID, timestamp, timestamp,
                    ]
                )
            }
            // Conditional per §3.5: one row per distinct normalized form per entity.
            let existingAlias = try Row.fetchOne(
                db,
                sql: "SELECT entity_id FROM entity_aliases WHERE project_id = ? AND kind = ? AND normalized = ?",
                arguments: [projectID.uuidString, kind.rawValue, normalized]
            )
            if let existingAlias {
                let owner = try UUID.required(existingAlias["entity_id"])
                guard owner == entityID else {
                    throw ProjectStoreError.aliasConflict(existingEntityID: owner)
                }
                continue
            }
            try db.execute(
                sql: """
                    INSERT INTO entity_aliases (
                        id, entity_id, project_id, kind, alias, normalized, alias_kind,
                        source, confidence, review_state, reviewed_at, job_id,
                        created_source, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, 'mention', 'ai', NULL, 'proposed', NULL, ?, 'ai', ?, ?)
                    """,
                arguments: [
                    UUID().uuidString, entityID.uuidString, projectID.uuidString, kind.rawValue,
                    name, normalized, jobID, timestamp, timestamp,
                ]
            )
        }
    }

    private static func encodedJSON(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
