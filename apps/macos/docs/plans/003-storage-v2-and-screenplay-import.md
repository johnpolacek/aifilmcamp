# Plan 003: Storage v2 and screenplay import (Phase 1a)

> **Executor instructions**: Read `docs/PHASE1_DESIGN.md` in full first. This plan implements
> its §3.9, §3.9a, §3.10, §4.1–§4.4, §5.3, §5.5, and §8.4's failure classification. It consumes
> Plan 002's `FilmScript` and `ScreenplaySamples` targets and re-specifies nothing in them. The
> app shell (§3.11), `project.yml`, and the real automation are **Plan 004's**; this plan only
> keeps the reduced Phase 0 app, its unit test, and `scripts/finder-smoke.sh` green against v2
> (see "App target during this plan").
> Follow the steps in order, run every verification command, honor every STOP condition and the
> live-gate policy. Requires Plans 001 and 002 `DONE`. When complete, set this plan's row in
> `docs/plans/README.md` to `DONE`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   1f0e224d9d668bc10fa01ab55bf60e115b14bafd0931eb81c26d152d5a4467ac docs/ROADMAP.md \
>   8660b7114aa507a98ec2cf621176355cb912b749ff3b84395e6f4af6fb927691 docs/OVERVIEW.md \
>   282b1ae714029b96e932bff1eba236df0e05b76abc1fe6b434f90f11ca418d46 docs/REFERENCE_PROJECTS.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all five print `OK`, and `git rev-parse --short HEAD` is descended from `02cf45c`.
> If a hash differs, stop for reconciliation when storage, jobs, or the harness boundary changed.

## Status

- **Status**: DONE (2026-08-19)
- **Priority**: P1
- **Effort**: L, approximately 7–9 focused engineering days
- **Risk**: MED-HIGH; the v1→v2 migration rebuilds `projects`, `scripts`, `jobs`, and `scenes`
  under `PRAGMA foreign_keys = OFF`, and Phase 0's only job surface is replaced at once
- **Depends on**: 002 (which depends on 001)
- **Category**: architecture / feature / tests
- **Planned at**: commit `02cf45c`, 2026-08-18; design hash in the drift check

## Current state

- Plan 001 `DONE` at `02cf45c`; Plan 002 added `FilmScript` and `ScreenplaySamples` (including
  `camp-signal.fountain`) inside the FilmCore package — read those sources instead of re-deriving.
- Phase 0's **seven** job behaviors live in `FilmBrainTests/AnalyzeScreenplayJobTests.swift`;
  they are the regression suite this plan must carry over intact.
- Phase 0 computed `scripts.sha256` over the **file bytes**, not `source_text`; the migration
  must recompute it.
- `UTCDate` is a `private enum` at the bottom of `ProjectRepository.swift` using a default
  `ISO8601DateFormatter` (no fractional seconds).
- Pins unchanged, nothing new added: Xcode 26.6, Swift 6 with complete strict concurrency, macOS
  15 floor, XcodeGen 2.46.0, GRDB 7.11.1, swift-json-schema 0.13.1, `macos-26` CI runner.

## App target during this plan

**A plan deletes the callers of what it deletes**, so this plan does the minimum app cleanup needed
to stay green and nothing more:

- Remove `AnalysisJobView`, `AnalysisResultsView`, `AppModel`'s analysis members, and the
  `ProjectView` section that used them. Reduce `AppModel` to create / open / **import** / close /
  reveal plus Codex status — `import` is one `AppModel` method calling
  `importScreenplay(from:actor: .human)` on the open session; it has **no** UI control, panel, or
  drop target (those are Plan 004's `importScreenplayButton` and `ProjectPanelService`).
- `AI Film Camp/Tests/AppModelTests.swift` is rewritten (not deleted): create → open →
  `AppModel.importBundledSample()` → counts `2 / 2 / 2` → close → reopen; Codex status as today;
  and it **keeps** the two Finder-URL tests unchanged (`testDuplicateFinderOpenForSameProjectIsIdempotent`,
  `testAppDelegateDeliversFinderURLsReceivedBeforeViewAppears` — neither touches analysis).
  `AI Film Camp/UITests/Phase0FlowUITests.swift` is **reduced, not deleted**, to one launch test
  (`Phase0LaunchUITests`: the app launches with persistence disabled and shows `createProjectButton`)
  — it clicked `analyzeScreenplayButton` and read `scenesCount`/`charactersCount`/`locationsCount`,
  all removed here, and the no-AI UI flow needs Plan 004's import UI; but the directory must stay
  non-empty and tracked because `project.yml:71` declares it as the `AI Film CampUITests` source
  path and `verify.sh` runs `xcodegen generate` first. Plan 004 replaces it with `Phase1ImportUITests`.
- `scripts/finder-smoke.sh` is retargeted: `AppCoordinator.runFinderSmoke` does not exist yet, so
  the existing `AppModel` smoke path gains the import step, and the script's `snapshot_database()`
  replaces `characters` / `locations` / `scene_characters` / `scene_locations` with `entities`
  (`kind, name, name_normalized`), `entity_aliases` (`kind, alias, normalized`), and
  `scene_entities` (`scene ordinal, entity name, role`); asserts `PRAGMA user_version = 2` and
  `SELECT count(*) FROM jobs` = `0`; drops the job assertion (lines 85–86 today) and the log /
  result assertions (lines 98–101), **replaces** the scene/character/location count assertions
  (lines 87–92) with the parser counts, keeps the `project_assets.relative_path` check (lines
  94–96), and keeps the create-vs-reopen byte comparison. `FinderSmokeReport` in
  `AppServices.swift` keeps `projectID`, `projectName`, `scriptID`, `scriptSHA256`, `scenes`
  (now `"<ordinal> <heading>"` strings from `ProjectReading.scenes()`), and `jobs` (from
  `jobHistory()`, empty), loses its `characters`/`locations` fields (sourced from the deleted
  `AnalysisResults`), and gains `sceneCount`, `characterNames`, `locationNames` from
  `ProjectReading` — this full field list is the "v2 shape" Plan 004 keeps.
  `--film-camp-recorded` keeps its Phase 0 value argument until Plan 004 makes it a flag.
- `AppServices.makeAdapter`, the `Resources/Samples` phase, and `project.yml` are **kept** — Plan
  004 owns them, along with the real shell (coordinator, windows, sections, menus, import UI,
  `Settings`), the app-side `camp-signal.fountain` deletion, and the UTI declarations.

Consequence: `./scripts/verify.sh` and `./scripts/finder-smoke.sh` pass at the end of this plan and
003 merges on its own. Do not build the Plan 004 shell here.

## Reference seams

Read `docs/REFERENCE_PROJECTS.md` ▸ *Phase 1 specifics* before contract C. Two
seams apply here; adopt the separation, not the products, and record the
upstream commit in `docs/IMPLEMENTATION_NOTES.md` if any code is adapted.

- Generic runner and capabilities the caller requires rather than assumes:
  `rxcode/Packages/Sources/RxCodeCore/Backend/AgentBackend.swift` and
  `.../BackendCapability.swift`; the replayable double is
  `rxcode/RxCodeTests/MockAgentBackend.swift`.
- Normalized failure envelopes across providers, for `HarnessFailureKind`:
  `Calyx/Calyx/Features/AgentMonitor/AgentEvent.swift`.
- Abandoned-job reaping mirrors Calyx's rule — persist job metadata, never live
  process objects, and verify identity before offering resume:
  `Calyx/Calyx/Features/Persistence/SessionPersistenceActor.swift`.

Reject: RxCode's coding-agent capability list and request envelope, Calyx's
terminal and configuration-mutation scope.

## Live-gate policy

Only `CodexSchemaCompatibilityTests` (re-pointed at the probe schema) touches the operator's Codex
account: explicit approval immediately before it runs, never in CI, skipped unless
`FILMCAMP_RUN_LIVE_CODEX=1`. If the deterministic work finishes while approval is absent, record
the deferral in `docs/IMPLEMENTATION_NOTES.md` and still mark the plan `DONE`.

## Contracts (normative)

### Schema and API deltas added by review (design §3.6, §4.3, §5.5)

- **PROV gains `reviewed_at`** (nullable) and **`created_source`** (`CHECK IN ('parser','ai','human')`,
  `NOT NULL`, = `source` at insert, never overwritten) on every fact row. `reviewed_at` is set *only*
  by an explicit human action — never by import, parser creation, or an AI apply. `job_id` records
  the job that **created** the row and is never overwritten by a later human edit. Plan 006's
  exporter keys on all three (design §7.2): `source` says who owns the row now, `created_source` +
  `job_id` say who found it. The public `Provenance` value exposes `source`, `createdSource`,
  `reviewedAt`, `jobID`, `confidence`, `reviewState`, `createdAt`, `updatedAt`, and `Entity`,
  `EntityAlias`, `SceneEntity`, `EntityState`, `ContinuityEvent`, `EntityRelationship` each carry
  one.
- **`edit_journal.inverts_seq`** (`INTEGER nullable REFERENCES edit_journal(seq) ON DELETE SET
  NULL`, indexed) is created here, written by nothing until Plan 005's `applyInverse` (design §3.8
  cancellation rule).
- **`scripts.parse_warnings_json`** (`TEXT NOT NULL DEFAULT '[]'`) persists `ParseWarning`
  codes/messages/ranges at import. Counts can be recomputed from `ProjectReading`; warnings cannot,
  so without this column no import or upgrade summary can report them.
- **`ProjectBundle.open` reports an upgrade.** Opening a v1 bundle migrates it, and the session
  exposes `upgradeSummary: UpgradeSummary?` — non-nil exactly when a migration ran — carrying
  `fromVersion`, `toVersion`, scene/entity/sequence counts, `synopsesDropped`, and the persisted
  parse warnings. Plan 004 renders it; it cannot reconstruct that from `ProjectReading` alone.


### A. Storage v2 — build §4.1–§4.3 as written there; below is only what this plan adds

- `FilmCoreVersion.bundleSchema = 2`; `ProjectDatabase` still refuses `user_version > 2` first.
  `ProjectMigrator` registers `"v2"` with GRDB's **default `foreignKeyChecks: .deferred`** (never
  `.immediate`) and runs the §4.2 steps in one transaction ending `PRAGMA user_version = 2`.
- `projects`, `scripts`, and `jobs` are **rebuilds**, not `ALTER TABLE`: create `<name>_v2`,
  `INSERT … SELECT` (`NULL` for new columns, literal `2` for `bundle_schema_version`),
  `DROP TABLE`, `ALTER TABLE … RENAME TO`. `scenes` is **dropped and recreated with no row copy**
  (Phase 0's `CHECK (ordinal > 0)` forbids the preamble and the old model-produced rows are
  replaced by the parser's). Reasons for the rebuilds: the `projects` `CHECK` pins the version;
  SQLite cannot `ADD COLUMN` a `NOT NULL` column carrying `REFERENCES`
  (`scripts.original_asset_id`); `jobs.state`'s `CHECK` gains `'paused'`. Execute the §4.2 steps
  **in the order written there** — new tables and their indexes first, `scripts`/`jobs` rebuilt
  before their backfills, `scenes` recreated from the parse, `projects` rebuilt **last** so
  `current_script_id` resolves, and the indexes over the rebuilt tables (`jobs(project_id)`,
  `jobs(parent_job_id)`, `jobs(script_id)`, `jobs(supersedes_job_id)`, `scripts(project_id)`,
  `scenes(script_id, ordinal)`) created in §4.2 step 8 — an index on a column the rebuild has not
  added yet fails with `no such column`, and one created before a `DROP TABLE` is dropped with it.
- Backfills: `source_text = TextNormalization.normalize(source_text)` **first** (Phase 0 stored raw
  bytes; every v2 span is an offset into the normalized text), then `format = 'fountain'`,
  `original_asset_id = source_asset_id`, `parser_version = FilmScriptVersion.parser`,
  `title_page_json` (the encoded `TitlePage` object) and `parse_warnings_json` (the parse's
  `ParseWarning`s, JSON-encoded — `noSceneHeadings` lands here) from the step-5 parse, `sha256`
  recomputed **in Swift** (CryptoKit over the
  UTF-8 bytes of the normalized `source_text`); `jobs.script_id` and
  `projects.current_script_id` from the single script (`NULL` only if the v1 bundle has none).
- §4.2 step 3 groups with `EntityNormalization.normalize`; each Phase 0 name becomes an
  `entity_aliases` row (`alias_kind = 'mention'`, `source = 'ai'`, `created_source = 'ai'`). Phase
  0 appearances are **not** carried over (§4.2 step 4): the parser regenerates them.
- §4.2 step 5 matches existing entities by `name_normalized` first: a match keeps its id, name,
  `source`, and `review_state` and only gains parser aliases, appearances, and evidence; a
  non-match is created `source = 'parser'`, `review_state = 'accepted'`. **Decision recorded**: a
  migrated Phase 0 entity therefore stays `ai/proposed` (replaceable, §3.6) and keeps its Phase 0
  casing (`MAYA` beside `Eli`) — acceptable for internal spike bundles. Add no re-anchor columns
  anywhere — re-import and re-parse are out of scope (§14.3).
- **Aliases (design §3.5)**: `entity_aliases.normalized` is **always**
  `EntityNormalization.normalize(…)` — applied to `CueNormalizer.normalize(alias).name` for
  `alias_kind = 'cue'` (cue extensions peeled, then the one case-folding function) and to the raw
  surface form otherwise — so one column has one key space and `UNIQUE(project_id, kind,
  normalized)` means what §3.5 says; one row per distinct normalized form per entity; location
  aliases are `ParsedScene.locationText` (never the heading line); every parser/migration alias
  insert is conditional — same `(project_id, kind, normalized)` on the same entity → skip, on
  another entity → `.aliasConflict(existingEntityID:)`. This is what lets the mandated v1 sample
  migrate: its Phase 0 `mention` aliases (`maya`, `camp cabin`, `camp dock`) meet the parser's cue
  and heading aliases normalized to the same strings at step 5 and are skipped.

§4.3 content that post-dates Phase 0 and is easy to miss — all of it is created by `"v2"`:

| Addition | Written by |
|---|---|
| `scene_exclusions` (`scene_id`, `kind IN ('note','boneyard')`, `start_utf16`, `end_utf16`) | import **and** the §4.2 step-5 re-parse, from `ParsedScene` note/boneyard elements — a migrated bundle and an imported one send the same model-facing text in Plan 007 |
| `scene_entities.matched_alias_id` and `evidence.matched_alias_id` (`REFERENCES entity_aliases(id) ON DELETE SET NULL`) | import and migration, so Plan 005's split moves exactly the right appearances and evidence |
| `edit_journal_affected` (`seq` FK `ON DELETE CASCADE`, `subject_kind`, `subject_id`, PK all three) | every journal write, including import's |
| `locks.subject_kind` admits `'alias'` (§3.7) | nothing here; the `CHECK` must allow it |
| `scenes.synopsis_reviewed_at` and `synopsis_created_source` (the synopsis field's full PROV, §4.3) | Plan 005's `setSynopsis`; migration leaves them NULL / `'ai'` for carried-over Phase 0 synopses |
| `jobs.attempt_index INT nullable`, `jobs.supersedes_job_id TEXT nullable REFERENCES jobs(id) ON DELETE SET NULL` | nothing here; Plan 007 retries |
| `evidence` CHECK is `(anchored = 1) = (start_utf16 IS NOT NULL AND end_utf16 IS NOT NULL)` | new table; an earlier draft admitted an anchored row with a null end offset — both offsets are required |

- Create **every** index §4.2 names — the new-table indexes in step 1 (including
  `scene_exclusions(scene_id)`, `edit_journal_affected(subject_kind, subject_id)`,
  `edit_journal(inverts_seq)`) and the rebuilt-table indexes in step 8 (including
  `jobs(supersedes_job_id)`). `entity_aliases(project_id, kind, normalized)` and
  `locks(subject_kind, subject_id)` are materialized by their `UNIQUE`/`PRIMARY KEY` constraints
  and are **not** created again; the migration test checks presence by querying
  `PRAGMA index_list` / `index_info`, not by `sql IS NOT NULL` in `sqlite_master`.
- Promote `UTCDate` into `Storage/UTCDate.swift`: `formatOptions = [.withInternetDateTime,
  .withFractionalSeconds]` for writing, parsing that also accepts v1 strings without them.
- Add **`public`** `EntityNormalization.normalize(_:) -> String` (`Domain/EntityNormalization.swift`:
  Unicode case-fold, NFC, whitespace-collapse, trim; Plan 006 calls it) behind both `entities.name_normalized` and
  `entity_aliases.normalized`; display names from `FilmScript.DisplayCase`.

**Migration sample (required)**: check in a v1 bundle at
`Packages/FilmCore/Tests/FilmCoreTests/Samples/v1-phase0.aifilm/`, generated from the Phase 0 code
path **before** deleting it, with this exact recipe so the frozen artifact is reproducible:
`git worktree add /tmp/filmcamp-v1 02cf45c`; in that tree, `ProjectBundle.create(at:name:
"Camp Signal", sampleURL:)` over `AI Film Camp/Resources/Samples/camp-signal.fountain`; one job
driven through `advanceToCommitting` then `applyAnalysis` with **verbatim**
`TestSupport.proposal(twoScenes: true)` (characters `MAYA`; locations `CAMP CABIN`, `CAMP DOCK`)
and `usage = .empty` — both helpers are free functions in that tree's `FilmCoreTests/TestSupport.swift`,
so drive them from a throwaway `@Test` in the `02cf45c` worktree that builds the bundle at a
fixed path and does **not** call `TemporaryProject.remove()`; `close()` the session; copy the
package in; record the recipe **and the resulting row count of every table** in
`Samples/README.md`. Add `resources: [.copy("Samples")]` to `FilmCoreTests` (Plan 002 already
added its `"ScreenplaySamples"` dependency) and these `.gitignore` lines, appended after the
current last line (later patterns win; Git cannot re-include files inside an excluded directory):

```gitignore
!Packages/FilmCore/Tests/**/v1-phase0.aifilm/
!Packages/FilmCore/Tests/**/v1-phase0.aifilm/**
```

The migration test copies the bundle to a temporary directory first (opening migrates) and
asserts: `scripts`, `jobs`, and `project_assets` row counts unchanged before and after (the guard
against the cascade failure mode); a clean `PRAGMA foreign_key_check`; `user_version = 2`;
`bundle_schema_version = 2`; `script() != nil` and `projects.current_script_id == scripts.id`;
`source_text` normalized and `sha256` equal to its digest; two rebuilt parser scenes with non-null
spans; four entities (`MAYA`, `CAMP CABIN`, `CAMP DOCK` kept as `ai/proposed`; `Eli` created as
`parser/accepted`) each with aliases and no duplicate normalized alias; no `scene_entities` row
from Phase 0; every §4.2 index present per the rule above; `upgradeSummary` non-nil with
`synopsesDropped == 0`; `scene_exclusions` populated from the re-parse where the text has notes.
Two further v1 fixtures are **synthesized in-test** (never checked in) by running the still-
registered `"v1"` migration alone (`DatabaseMigrator.migrate(queue, upTo: "v1")` on a bare
`DatabaseQueue`) and then raw `INSERT`s, to cover the branches the sample cannot: a three-scene
Phase 0 proposal with three non-empty synopses over the two-scene text (`synopsesDropped == 3`,
no synopsis carried over) and a headingless `source_text` (`noSceneHeadings` in
`parse_warnings_json`, one `UNTITLED` scene).

### B. Domain types and `ProjectTools` roles (design §3.9, §3.9a, §4.4, §5.3, §5.5, §6)

Public FilmCore types beyond §4.4's list: `AliasKind`, `SceneEntityRole`, `StateCategory`,
`RelationshipKind`, `FactSource`, `UTF16Range` (FilmCore's own; it deliberately shadows
`FilmScript.UTF16Range`, and the import mapper qualifies the FilmScript one), `SceneDetail`,
`EntityDetail` (aliases, appearances, states, events, relationships, evidence, **locks**),
`EntitySummary` (`id`, `kind`, `name`, `reviewState`, `isLocked`, `appearanceCount`), `Lock`,
`SceneExclusion` (`kind: SceneExclusionKind`, `range: UTF16Range`), `SceneExclusionKind`,
`RunSummary`, `ImportSummary`, `UpgradeSummary`, `BundleInspection`, `ConfidenceBand` (`< 0.5`
Low, `< 0.8` Medium, else High — one banding for UI and reports), `nil`-aware `JobUsage`
addition over Phase 0's existing `JobUsage.empty` (`nil` treated as absent; the sum is `nil` only
when every operand is `nil`), `Job` gaining `parentJobID`, `chunkIndex`, `chunkCount`,
`attemptIndex`, `supersedesJobID`, `scriptID`, `scriptSHA256`, and `applyReport: ApplyReport?`
(read back from the new columns; `ApplyReport` is Plan 005's FilmCore type — until then the
property decodes `NULL` only), `StructuredRunResult<Output> { job: Job, output: Output, usage:
JobUsage }` (FilmBrain), and `ProjectChange` (an `OptionSet` of areas: `.script`, `.scenes`, `.entities`, `.jobs`,
`.journal`, `.locks`). **`SubjectKind`** (`entity | alias | appearance | scene | state | event |
relationship | synopsis | script`) is the one subject vocabulary: `SubjectRef = { kind: SubjectKind;
id: UUID }`; `locks.subject_kind` accepts the `entity | alias | scene | state | event |
relationship` subset and `evidence.subject_kind` the `entity | alias | appearance | state | event |
relationship | synopsis` subset, both enforced by their `CHECK`s and by `LockPolicy` (Plan 005) —
there is no separate `LockSubject` type. `Script` gains `format`, `originalAssetID`, `titlePage`,
`parserVersion`, `parseWarnings`. This plan **owns the mutation and journal types in their final
shape** so import can use them and Plan 005 extends rather than rebuilds — in these files:
`Domain/EditOperation.swift` (`public enum EditOperation: Codable, Equatable, Sendable` with
`displayName`; here only the non-invertible `.importScreenplay` and `.replaceScreenplay` cases;
the inverse of an operation is **returned by `mutate` in `MutationEffect.inverse`, not a
property of the enum** — payload-driven inverses such as `unmerge` carry their snapshots as
associated values, Plan 005), `Domain/SubjectRef.swift` (`SubjectRef`, `SubjectKind`),
`Editing/RowSnapshot.swift` (`RowSnapshot` = table name + `[String: JSONValue]` encoded with
`.sortedKeys` — never a GRDB type; `JSONValue`; internal `MutationEffect`),
`Domain/JournalEntry.swift` (`seq`, `at`, `actor`, `jobID`, `invertsSeq`, `op`, `inverse`,
`affected: Set<SubjectRef>`, `snapshots`), `Editing/JournalStore.swift` (writes `edit_journal` +
`edit_journal_affected`), and `Editing/EditPrimitives.swift` holding the internal
`mutate(_:actor:in:)` and `perform(_:actor:jobID:in:)` of design §3.8 with the import case only.
Plan 005 adds the remaining `EditOperation` cases, their inverses, `performGroup`, and
`applyInverse` by **extending these files**; it does not redefine these types.

```swift
public protocol ProjectReading: Sendable {
  func projectSnapshot() async throws -> Project
  func script() async throws -> Script?               // by projects.current_script_id; nil until imported
  func scenes() async throws -> [Scene]
  func scene(id: UUID) async throws -> SceneDetail     // scene + entities by role + states active in the scene + SYNOPSIS-subject evidence only
  func sceneText(id: UUID) async throws -> String
  func sceneExclusions(id: UUID) async throws -> [SceneExclusion]
  func sequences() async throws -> [ScriptSequence]
  func continuityEvents() async throws -> [ContinuityEvent]   // scene-ordinal order; entity_id NULL rows included (Plan 004 Continuity, Plan 006)
  func entities(kind: EntityKind?, reviewState: ReviewState?,
                includeIrrelevant: Bool, includeRejected: Bool) async throws -> [Entity]
  func entitySummaries(kind: EntityKind?, reviewState: ReviewState?,
                includeIrrelevant: Bool, includeRejected: Bool) async throws -> [EntitySummary]
  func entity(id: UUID) async throws -> EntityDetail   // aliases, appearances, states, events, relationships, evidence, locks
  func locks() async throws -> [Lock]
  func journal(limit: Int) async throws -> [JournalEntry]
  func pendingReviewCount() async throws -> Int
  func runs() async throws -> [RunSummary]             // parent jobs with aggregated usage
  func jobHistory() async throws -> [Job]
  func disclosureAcknowledgedAt() async throws -> Date?
}
public protocol ScreenplayImporting: Sendable {
  func importScreenplay(from url: URL, actor: MutationActor) async throws -> ImportSummary
  func canReplaceScreenplay() async throws -> Bool
}
public protocol JobManaging: Sendable {
  func prepareRunWorkspace(runID: UUID) async throws -> ProjectRunWorkspace
  func prepareChildPaths(runID: UUID, jobID: UUID) async throws -> ProjectJobPaths
  func createJob(_ request: JobRequest) async throws -> Job
  func transitionJob(id: UUID, to state: Job.State, progress: String,
                     failureCode: String?, failureMessage: String?) async throws -> Job
  func completeJob(id: UUID, usage: JobUsage) async throws -> Job
  func setEffectiveModel(jobID: UUID, effectiveModel: String?) async throws
  func acknowledgeDisclosure() async throws            // writes projects.disclosure_acknowledged_at; Plan 007 calls it
}
public extension JobManaging {              // moved off ProjectTools: a composition cannot be extended
  func transitionJob(id: UUID, to state: Job.State, progress: String) async throws -> Job
}
public protocol ProjectObserving: Sendable { func changes() async -> AsyncStream<ProjectChange> }
public protocol ScreenplayEditing: Sendable {}          // declared empty; Plan 005
public protocol ExtractionApplying: Sendable {}         // declared empty; Plan 007
public typealias ProjectTools = ProjectReading & JobManaging & ScreenplayImporting
                              & ScreenplayEditing & ExtractionApplying & ProjectObserving
```

- `sceneExclusions(id:)` returns the §4.3 note/boneyard ranges so FilmBrain can build model-facing
  text and map offsets back **without importing `FilmScript`** (§3.1).
- `SceneDetail.evidence` holds **only** `subject_kind = 'synopsis'` rows and `EntityDetail.evidence`
  every row whose `owner_entity_id` is that entity, so the two partition the table (Plan 006's
  anchor rate sums them). `ProjectReadingTests` asserts the partition over a seeded table.
- `entitySummaries` is the list shape Plan 004 renders (lock icon, appearance count) and `locks()`
  / `EntityDetail.locks` are what Plans 004 (display), 005 (lock UI), and 007 (reconcile input)
  read; this plan creates the reads over the empty `locks` table.
- `ProjectJobWorkspace` is replaced by `ProjectRunWorkspace { workspaceURL,
  workspaceRelativePath }` and `ProjectJobPaths { inputURL, resultURL, logURL, inputRelativePath,
  resultRelativePath, logRelativePath }` over the §4.1 layout; a childless task passes
  `runID == jobID`.
- `completeJob(id:usage:)` records usage and transitions to `completed` in one transaction,
  replacing the usage-recording half of the deleted `applyAnalysis`.
- `JobRequest` gains `parentJobID: UUID?`, `chunkIndex: Int?`, `chunkCount: Int?`,
  `attemptIndex: Int?`, `supersedesJobID: UUID?`, `scriptID: UUID?`, `scriptSHA256: String?`, and
  `Job` exposes the same values read back; `Job.State` gains `paused`; `ProjectBundle.open` does
  the §3.9 reaping (`failure_code = 'abandoned'`) — on open, every non-terminal non-`paused` job
  is abandoned without further identity checks, which is correct for a single-writer bundle
  (Calyx's identity verification has no pid/host column here and is deliberately not adopted). `createJob` refuses a new **parent** while another parent is non-terminal **and
  not `paused`** (design §3.9 — a paused run may be superseded); import/replace are refused while
  any run is non-terminal **or** paused (§5.5). Both rules are tested.
- Errors thrown here: `ProjectStoreError.mutationInProgress` (a second non-terminal parent),
  `.importRefusedDuringRun`, `.replaceRefused(reason:)` — the reason is §5.5's wording verbatim —
  and `.aliasConflict(existingEntityID:)` (already needed by the conditional alias insert).
- `ProjectBundle.create(at:name:)` replaces the sample-taking creator and leaves the project empty.
  Add `ProjectBundle.inspect(at:) -> BundleInspection` (schema version only). It must not open the
  database through `ProjectDatabase`, which migrates unconditionally: it reads the 4-byte
  big-endian `user_version` at offset 60 of `project.db` (a missing or short file is
  `.invalidBundle`). Plan 004 shows the upgrade modal over it.
- **`UpgradeSummary` mechanism**: `ProjectDatabase.init` captures the pre-migration `user_version`;
  the `"v2"` migration closure writes its counters (scene, entity, sequence counts,
  `synopsesDropped`) into a `Mutex`-guarded `MigrationOutcome` box that `ProjectMigrator.migrate(_:)
  -> MigrationOutcome?` returns; `ProjectBundle.open` hands it to `ProjectSession.init`, which
  exposes `upgradeSummary` (non-nil exactly when the pre-migration `user_version` was 1 — a fresh
  `create` runs both migrations and yields `nil`) with the persisted `parse_warnings_json` decoded in.
- Observation lives in `Storage/ProjectObservation.swift` over `ValueObservation` scheduled
  `.async(onQueue:)` on the session's queue (`DatabaseRegionObservation` is acceptable where no
  payload is needed); no GRDB type in a public signature; `close()` finishes every stream first.

**Import atomicity is a staged copy plus one transaction, not one atomic act** — a filesystem copy
and a database write cannot share a transaction. The contract: (1) resolve the destination name in
`screenplay/` (collision → `-2`, `-3`) and copy the original there, **staged** — nothing
references it and the source is never touched; (2) write the asset row, script, sequences, scenes,
`scene_exclusions`, parser entities/aliases/appearances/evidence, `projects.current_script_id`,
and the journal entry in **one** `queue.write`; (3) on any throw from (2) delete the staged file
before rethrowing. Test by injecting a failure inside (2) and asserting **both** that `screenplay/`
holds no orphan and that no script, scene, entity, alias, appearance, evidence, exclusion, or
asset row exists. Keep an `internal func importScreenplay(_ document: ScreenplayDocument,
originalURL: URL, actor: MutationActor)` variant for FilmCore tests; the public path takes a URL.

**Journaling.** Import writes its one non-invertible `importScreenplay` entry through the §3.8
`perform` primitive — one `edit_journal` row plus its `edit_journal_affected` rows, `affected`
populated (`.script`, scenes, entities, aliases, appearances, evidence). Only that import-shaped
path is built here; `performGroup`, the remaining inverses, and `applyInverse` are Plan 005's, and
`ScreenplayEditing` stays empty.

**Replace guard.** `canReplaceScreenplay()` and the `.replaceRefused(reason:)` throw are
implemented **here** (Plan 004 needs them): refused when any row has `source = 'human'`, any
`ai`-sourced row is `accepted`, or any `locks` row exists. Plan 005 re-verifies the guard once
real protected rows can be produced; it does not re-implement it.

### C. Runner generalization, in place (design §3.9, §3.10, §8.4)

Move `Tasks/AnalyzeScreenplay/AnalyzeScreenplayJob.swift` to
`Sources/FilmBrain/Jobs/StructuredJobRunner.swift`; state machine, event handling, cancellation,
and failure mapping are copied, not redesigned.

```swift
public protocol StructuredTask: Sendable {
  associatedtype Output: Sendable
  var taskName: String { get }
  var schemaVersion: Int { get }
  var schemaURL: URL { get }
  func prompt(for input: StructuredTaskInput) throws -> String
  func validate(resultFileAt url: URL) throws -> Output
}
public struct StructuredTaskInput: Sendable { jobID, text, scriptID?, scriptSHA256?, chunkIndex?, chunkCount? }
public actor StructuredJobRunner<T: StructuredTask> {            // not `Task`: it would shadow Swift.Task
  public init(task: T, projectTools: any ProjectTools, adapter: any HarnessAdapter,
              progressHandler: @escaping @Sendable (String) -> Void = { _ in })
  public func run(input: StructuredTaskInput, engine: String, engineVersion: String,
                  parentJobID: UUID? = nil,
                  commit: (@Sendable (T.Output, UUID, JobUsage) async throws -> Void)? = nil
  ) async throws -> StructuredRunResult<T.Output>
  public func cancel() async throws
}
```

- Paths: `runID = parentJobID ?? input.jobID`; the runner calls `prepareRunWorkspace(runID:)` and
  `prepareChildPaths(runID:jobID: input.jobID)`. `JobRequest.inputSHA256` = SHA-256 of the UTF-8
  bytes of `input.text` (Plan 007 replaces it with the §8.2 reuse key for chunk attempts; parents
  and reconcile children store the digest of their own input text).

- With a `commit` closure: `validating → committing → commit → completeJob`; without one:
  `validating → completed`, which contract B allows only for children — so every no-commit
  `EchoTask` behavior in `StructuredJobRunnerTests` first creates a parent job and passes its id
  as `parentJobID`.
- `AnalyzeScreenplayJobFailure` becomes `StructuredJobFailure`, same `code`/`message` shape and
  job codes (`cancelled`, `missing_terminal_success`, `codex_error`, `process_exit`,
  `harness_failure`, `database_commit`). Validator codes are **renamed**, not preserved:
  `invalidJSON` → `malformedJSON`, and Phase 0's nine semantic codes collapse into
  `semanticViolation` — semantic coverage is absent between this plan and Plan 007, deliberately.
- Extract the reusable half of `AnalyzeScreenplayValidator` into
  `Jobs/StructuredResultValidator.swift` **before** deleting the task: regular-file and 16-MB
  checks, JSON parse, JSON Schema validation against a supplied schema URL, and the codes
  `missingResult`, `oversizedResult`, `malformedJSON`, `schemaViolation`, `semanticViolation`
  (`StructuredValidationFailure`).
- Keep `Sources/FilmBrain/Resources/Schemas/` **non-empty**: add `harness-probe-v1.schema.json`
  (`additionalProperties: false`; `schemaVersion` with both `type: integer` and `const: 1`; one
  bounded `echo` string) as `HarnessProbeSchema.url`. It replaces
  `AnalyzeScreenplayValidator.schemaURL` in `CodexSchemaCompatibilityTests` and
  `CodexHarnessAdapterTests`, where `AnalyzeScreenplayPrompt.make` becomes an inline probe prompt
  ("Return only the JSON object described by the schema, echoing the word `ready`").
- §8.4: `HarnessEvent.failed` gains `kind: HarnessFailureKind` — `.usageLimit(resetHint: String?)`,
  `.retryable`, `.unknownModel`, `.fatal`; `JSONLEventDecoder` emits `.fatal`, **every** other
  `.failed` producer (`RecordedHarnessAdapter` and the six non-decoder sites in
  `CodexHarnessAdapter`) supplies `.fatal`, and `CodexHarnessAdapter` re-maps the decoder's through
  a new `Codex/CodexFailureClassifier.swift`, the only place that string-matches `usage_limit`,
  `rate limit`, `429`, and model-not-found wording. This plan consumes no kind — failures stay
  terminal — and **leaves the `FoundationProcessRunner` cancellation change to Plan 007**: today's
  order is terminate → interrupt and stays so here; Plan 007 makes it interrupt → terminate → kill.

Delete exactly and only: `Tasks/AnalyzeScreenplay/{AnalyzeScreenplayDTO, AnalyzeScreenplayValidator,
AnalyzeScreenplayPrompt}.swift`, `Resources/Schemas/analyze-screenplay-v1.schema.json`,
`Tests/FilmBrainTests/AnalyzeScreenplayValidatorTests.swift`,
`Tests/FilmBrainTests/LiveCodexAnalyzeScreenplayTests.swift`,
`Tests/FilmBrainTests/Samples/analyze-{valid,malformed,bad-reference}.json`, and in FilmCore
`ProjectTools.applyAnalysis`, `analysisResults`, `Domain/ScreenplayAnalysisProposal.swift` (which
also holds `AnalysisResults`), `Domain/Character.swift`, `Domain/Location.swift`,
`ProjectRepository.applyAnalysis`/`fetchAnalysis`, and `ProjectSession.applyAnalysisForTesting`.
Job history rows whose `task` is `analyzeScreenplay` remain readable. In the app, delete only the
callers of the symbols above — `AnalysisJobView`, `AnalysisResultsView`, `AppModel`'s analysis
members, and the `ProjectView` section that used them — per "App target during this plan".
`AppServices.makeAdapter`, the `Resources/Samples` phase, and `project.yml` stay untouched; Plan
004 builds the real shell.

## Target file layout (additions, changes, deletions)

```text
Packages/FilmCore/  Package.swift (FilmCoreTests + resources: [.copy("Samples")] and the
  "ScreenplaySamples" dependency; Package.resolved unchanged), Domain/ (contract B types incl.
  EditOperation.swift, SubjectRef.swift, JournalEntry.swift, EntityNormalization.swift),
  Editing/ (+ RowSnapshot.swift, JournalStore.swift, EditPrimitives.swift), ProjectTools.swift
  (role protocols), Storage/ (ProjectMigrator +"v2" + MigrationOutcome, ProjectRepository,
  ProjectBundle (+ inspect), + ProjectObservation.swift, + UTCDate.swift), Tests/
  (+ ScreenplayImportTests, ProjectReadingTests, ProjectObservationTests, JobLifecycleTests,
  Samples/v1-phase0.aifilm/, Samples/README.md)
Packages/FilmBrain/  Package.swift UNCHANGED (no FilmBrain test imports a screenplay — see the
  rewrite table), Jobs/ (+ StructuredTask, StructuredJobRunner, StructuredResultValidator),
  Codex/ (+ CodexFailureClassifier.swift), Harness/HarnessEvent.swift (+ HarnessFailureKind),
  Resources/Schemas/harness-probe-v1.schema.json, Tests/ (+ StructuredJobRunnerTests, EchoTask,
  CodexFailureClassifierTests, Samples/echo-{valid,malformed}.json, Samples/README.md updated)
.gitignore   updated per contract A
AI Film Camp/App/AppModel.swift, AppServices.swift (FinderSmokeReport), Tests/AppModelTests.swift,
  UITests/Phase0FlowUITests.swift (reduced to a launch test), scripts/finder-smoke.sh   per "App target during this plan"
project.yml, AI Film Camp/Resources/Samples/, AppServices.makeAdapter   UNTOUCHED (Plan 004)
```

## Existing tests that break, and how each is rewritten

| File | Change |
|---|---|
| `FilmCoreTests/AnalysisTransactionTests.swift` | **Deleted**; atomicity intent moves to `ScreenplayImportTests` (one transaction; injected mid-import failure leaves no staged file and no row). |
| `FilmCoreTests/TestSupport.swift` | `proposal(twoScenes:)` deleted; `advanceToCommitting` keeps its shape for parents, gains `advanceToValidating` for children; `TemporaryProject.create` uses `ProjectBundle.create(at:name:)`, gains `createWithScript()` importing `ScreenplaySamples.url(named: "camp-signal.fountain")`. |
| `FilmCoreTests/ProjectBundleTests.swift` | `selectedScript()` → optional `script()`; `createsV1LayoutAndSampleRecords` → `createsEmptyV2Layout` (no `screenplay/camp-signal.fountain`, `script()` nil, `bundleSchemaVersion == 2`); close/move/reopen uses the imported sample. |
| `FilmCoreTests/ProjectRepositoryTests.swift` | `applyAnalysis` → `completeJob(id:usage:)`; one-active-mutation → one-active-**run** (second parent refused, child allowed); adds `validating → completed` refused for a parent and allowed for a child, `paused` transitions, abandoned reaping on reopen. |
| `FilmCoreTests/ProjectMigrationTests.swift` | Version assertions → `2`/`2`; newer-version test writes `user_version = 3`, expects `.newerProjectVersion(found: 3, supported: 2)`; adds contract A's v1-sample migration test. |
| `FilmBrainTests/AnalyzeScreenplayJobTests.swift` | Renamed `StructuredJobRunnerTests.swift`; all **seven** behaviors survive against the test-only `EchoTask` and the probe schema: recorded success validates and records usage (17,056 input / 0 cache-write); nested error item still follows the success path; malformed result fails `schemaViolation`, commits nothing; terminal failure fails `codex_error` without reading the result; cancellation records `cancelled`; throwing `commit` fails `database_commit` and preserves prior state (replacing `FailingCommitProjectTools`); unknown usage keys ignored, absent usage null. `BrainTemporaryProject.create` creates an **empty** bundle and imports nothing — `StructuredTaskInput` carries the text and `JobRequest.scriptID`/`scriptSHA256` are nullable, so no FilmBrain test needs a screenplay or a `ScreenplaySamples` dependency. |
| `FilmBrainTests/AnalyzeScreenplayValidatorTests.swift`, `LiveCodexAnalyzeScreenplayTests.swift` | Both **deleted**; the validator's structural cases become `StructuredResultValidator` coverage inside `StructuredJobRunnerTests` (missing, oversized, malformed, schema-violating result files), and no task remains to run live (the probe preflight does). |
| `FilmBrainTests/CodexHarnessAdapterTests.swift` | Line 120's `schemaURL: AnalyzeScreenplayValidator.schemaURL` → `HarnessProbeSchema.url`; scripted runner writes `echo-valid.json`; `.failed` matches gain `kind`. |
| `FilmBrainTests/CodexSchemaCompatibilityTests.swift` | Kept, re-pointed at `HarnessProbeSchema.url` with the inline probe prompt; still opt-in via `FILMCAMP_RUN_LIVE_CODEX`. |
| `FilmBrainTests/JSONLEventDecoderTests.swift`, `HarnessAdapterContractTests.swift` | Compile-only updates for `HarnessEvent.failed(code:message:kind:)`. |
| `AI Film Camp/Tests/AppModelTests.swift` | Rewritten per "App target during this plan": create → open → `AppModel.importBundledSample()` → `2 / 2 / 2` → close → reopen; Codex status; no analysis members. Plan 004 replaces it with `AppShellTests`. |
| `AI Film Camp/UITests/Phase0FlowUITests.swift` | **Reduced** to `Phase0LaunchUITests` (launch with persistence disabled → `createProjectButton` exists); every analysis element it drove is removed here, and the directory must stay tracked for `project.yml`. Plan 004 replaces it with `Phase1ImportUITests`. |
| `scripts/finder-smoke.sh` | Retargeted per "App target during this plan" (v2 snapshot SQL, `user_version = 2`, zero jobs, `FinderSmokeReport` v2 fields). Plan 004 adds the `project_assets.relative_path` assertion and the recorded-flag change. |

## Steps

### Step 1: Generate the v1 sample bundle, then schema v2 and domain types

Generate `Samples/v1-phase0.aifilm/` from a scratch worktree of `02cf45c` **before** touching
FilmCore (recipe in contract A), then implement contract A plus the new domain types (including
the journal types and `EditPrimitives` with the import case), `ProjectBundle.create(at:name:)`,
`ProjectBundle.inspect(at:)`, `MigrationOutcome`/`UpgradeSummary`, the `FilmCore/Package.swift`
test-target edits, and the FilmCore deletions. Update `TestSupport` and delete
`AnalysisTransactionTests` in the same step so the package compiles.

```bash
git status --short -- Packages/FilmCore/Tests/FilmCoreTests/Samples
swift test --package-path Packages/FilmCore --filter ProjectMigrationTests
swift test --package-path Packages/FilmCore
```

Expected: the sample bundle's files, `project.db` included, are listed as tracked additions rather
than ignored; every contract A migration assertion holds, including `script() != nil`, the
normalized `source_text`, the two synthesized-fixture branches, and `upgradeSummary`; a
`user_version = 3` bundle is refused without mutation and `inspect(at:)` reports it without
opening the database; `Package.resolved` is unchanged; the whole FilmCore suite passes.

### Step 2: Role protocols, import, observation, reads

Implement contract B: the six role protocols, v2 reads, import and replace, the job rules
(parent/child, `paused`, the `validating → completed` guard, reaping), and observation.

```bash
swift test --package-path Packages/FilmCore
grep -rn "import GRDB" Packages/FilmCore/Sources/FilmCore/Domain \
  Packages/FilmCore/Sources/FilmCore/ProjectTools.swift
```

Expected: import writes script, sequences, scenes, exclusions, parser entities, aliases (one row
per distinct normalized form, `matched_alias_id` set on every parser appearance and evidence
row), appearances, and evidence in one transaction plus one non-invertible journal entry with its
`edit_journal_affected` rows; an injected mid-import failure leaves zero rows and no file in
`screenplay/`; collisions get `-2`, `-3`; `sceneExclusions(id:)` returns the sample's note and
boneyard ranges; `SceneDetail.evidence` and `EntityDetail.evidence` partition the table;
`entitySummaries` reports appearance counts and `isLocked == false`; replace is refused with a
protected row or lock (seed one by SQL) and allowed otherwise; import is refused while a run is
non-terminal or paused; a second parent is refused unless the first is `paused`; `script()`
follows `current_script_id`; `changes()` emits a set containing `.script`, `.scenes`, `.entities`
after import; the `grep` prints nothing.

### Step 3: Generalize the runner and remove the Phase 0 task

Implement contract C, including the `EchoTask` double, the seven rewritten behaviors, and every
listed deletion.

```bash
swift test --package-path Packages/FilmBrain
grep -rn "AnalyzeScreenplay" Packages scripts | grep -v '\.build/'
ls Packages/FilmBrain/Sources/FilmBrain/Resources/Schemas
```

Expected: FilmBrain tests pass with no live call; the `grep` prints nothing (`AI Film Camp/` is
deliberately excluded — Plan 004 clears it); the schema directory contains exactly
`harness-probe-v1.schema.json`. With operator approval only:
`FILMCAMP_RUN_LIVE_CODEX=1 swift test --package-path Packages/FilmBrain --filter
CodexSchemaCompatibilityTests` accepts the probe schema and writes a schema-valid result.

### Step 4: Minimal app cleanup, then verification

Delete the Phase 0 analysis UI, reduce `AppModel`, rewrite `AppModelTests`, delete
`Phase0FlowUITests`, and retarget `scripts/finder-smoke.sh` per "App target during this plan",
with the sample's parser counts (2 scenes; `Maya`, `Eli`; `Camp Cabin`, `Camp Dock`) and
`PRAGMA user_version = 2`. Do not build the Plan 004 shell.

Record the live-gate outcome or deferral in `docs/IMPLEMENTATION_NOTES.md`, then:

```bash
swift test --package-path Packages/FilmCore
swift test --package-path Packages/FilmBrain
./scripts/verify.sh
./scripts/finder-smoke.sh
git status --short
```

Expected: both suites and both scripts exit 0 (the app builds, its unit test passes, the reduced
launch UI test passes, and the smoke creates, imports, closes, moves, reopens, and reports an
unchanged v2 snapshot); only intentional source, sample-bundle, `.gitignore`, and
doc changes are listed; no `.aifilm` package other than the checked-in v1 test sample, and no
screenplay, DerivedData, log, result, or secret, is staged.

## Done criteria

- [ ] `./scripts/verify.sh` and `./scripts/finder-smoke.sh` exit 0 — the reduced Phase 0 app
  still builds, creates, imports, closes, moves, and reopens (see "App target during this plan"),
  so 003 merges on its own.
- [ ] Schema v2 has every table, column, `CHECK`, `ON DELETE`, and index of §4.2/§4.3 — including
  `scene_exclusions`, `edit_journal_affected`, `edit_journal.inverts_seq`, PROV's `reviewed_at`
  and `created_source`, both `matched_alias_id` columns, `locks`' `alias` subject kind,
  `jobs.attempt_index`/`supersedes_job_id`, and the `evidence` anchored `CHECK` requiring both
  offsets — and `PRAGMA user_version = 2`; the checked-in v1 sample migrates under `.deferred`
  with unchanged `scripts`/`jobs`/`project_assets` counts, a clean `PRAGMA foreign_key_check`,
  `current_script_id` set, normalized `source_text`, parser-rebuilt scenes, Phase 0
  characters/locations kept as entities with aliases, and an `upgradeSummary`; the two
  synthesized v1 fixtures cover the dropped-synopses and `noSceneHeadings` branches.
- [ ] `ProjectTools` is the six-protocol composition, `ProjectSession` its only conformer,
  `transitionJob(id:to:progress:)` lives on `JobManaging`, and `sceneExclusions(id:)`,
  `entitySummaries(…)`, `locks()`, `EntityDetail.locks`, and the evidence partition are on
  `ProjectReading` with FilmBrain still not importing `FilmScript`; `SubjectKind` is the single
  subject vocabulary and the journal types/primitives live in the files contract B names.
- [ ] Projects are created empty; `importScreenplay(from:actor:)` takes a URL, leaves the original
  untouched, stages its copy into `screenplay/`, writes parser scenes with UTF-16 spans, parser
  entities, and exclusions in one transaction, deletes the staged file on failure, journals one
  non-invertible entry with a populated `affected` set, and returns a summary (format, scenes,
  characters, locations, sequences, warnings).
- [ ] Replace is refused when any protected fact or lock exists; any import is refused while a job
  is non-terminal or paused.
- [ ] `StructuredJobRunner` exists with all seven Phase 0 behaviors green against `EchoTask`;
  `Resources/Schemas/` is non-empty; no `AnalyzeScreenplay*` symbol, file, or sample remains in
  either package; `HarnessEvent.failed` carries `HarnessFailureKind`, classified inside
  `CodexHarnessAdapter`, and the process runner's cancellation order is unchanged.
- [ ] App changes are confined to deleting the Phase 0 analysis UI, reducing `AppModel` (plus one
  import method with no UI), rewriting `AppModelTests`, reducing `Phase0FlowUITests` to a launch
  test, and retargeting the smoke; `project.yml`, `AppServices.makeAdapter`, and the `Resources/Samples`
  phase are untouched, and no Plan 004 shell, editing operation, lock enforcement, extraction, or
  scorer was added; `docs/plans/README.md` marks Plan 003 `DONE`.

## STOP conditions

- The `docs/PHASE1_DESIGN.md` hash differs and §3.9, §3.9a, §3.10, §4, §5.5, or §6 changed.
- The migration cannot rebuild scenes deterministically from `source_text` (report the bundle and
  the parse result), or a rebuild loses rows despite `foreignKeyChecks: .deferred`.
- `ValueObservation` cannot be exposed as `AsyncStream<ProjectChange>` without a GRDB type
  appearing in a public FilmCore signature.
- The runner refactor cannot keep all seven Phase 0 behaviors green; report which behavior and why
  rather than deleting or weakening a test.
- A verification command fails twice after one reasonable scoped correction.
- Work expands into the app shell, automation, editing operations, locks, merge/split, provenance
  UI, chunking, or extraction (Plans 004, 005, and 007).

## Maintenance notes

- The v1 sample bundle is frozen evidence: never regenerate it once Phase 0's code is gone. If the
  migration changes, change the assertions. Note these bundles are **not** in WAL mode (GRDB's
  `DatabaseQueue` keeps SQLite's default journal), so `ProjectDatabase.checkpoint()` is a no-op
  safety net and a closed bundle is always a single `project.db` file.
- Plan 004 builds the app shell over these APIs (`entitySummaries`, `EntityDetail.locks`,
  `upgradeSummary`, `inspect`); Plan 005 fills `ScreenplayEditing`, the remaining
  `EditOperation` cases and inverses, `performGroup`, and `applyInverse` (writing `inverts_seq`),
  extending the files created here;
  Plan 007 fills `ExtractionApplying`,
  consumes `HarnessFailureKind` and `jobs.attempt_index`/`supersedes_job_id`, adds chunk tasks,
  and changes the process runner's cancellation order. Keep those seams empty, not half-built.
- `StructuredJobRunner` holds the only implementation of the Phase 0 job state machine left; treat
  its seven tests as the regression suite for every later task.
- Add new reads to `ProjectReading` rather than widening `ProjectSession` directly — test doubles
  decorate roles, not the whole store.
