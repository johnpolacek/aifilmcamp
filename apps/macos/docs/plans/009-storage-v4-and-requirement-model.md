# Plan 009: Storage v4 and the requirement model (Phase 2a)

> **Executor instructions**: Read `docs/PHASE2_DESIGN.md` in full first. This plan implements its
> §4.1's containment groundwork, §4.2–§4.4, §6.4's reads, and §7.5's storage-side plumbing —
> everything Phase 2 stores and reads, with **no new mutation operations** (Plan 010) and **no
> media on disk** (Plan 011). Requirement rows exist after this plan only when tests seed them;
> the app gains read-only manifest data, not a manifest feature.
> Follow the steps in order, run every verification command, honor every STOP condition. Requires
> Plans 005 and 008 `DONE`. When complete, set this plan's row in `docs/plans/README.md` to `DONE`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   84c3599561dac60fd02d00d8a3d6a564558bac340fb5988d8bcc83868748ff68 docs/PHASE2_DESIGN.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   1f0e224d9d668bc10fa01ab55bf60e115b14bafd0931eb81c26d152d5a4467ac docs/ROADMAP.md \
>   8660b7114aa507a98ec2cf621176355cb912b749ff3b84395e6f4af6fb927691 docs/OVERVIEW.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all five print `OK`, and `git rev-parse HEAD` is descended from `e8645e5`. If the
> PHASE2 hash differs, stop for reconciliation when §3.3, §3.4, §4, §6.4, §7.5, or §7.6 changed.
>
> **Live gates: none.** Nothing here calls Codex; every command must pass with no network. A
> step that appears to need a live call is a STOP condition, not a deferral.

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: M–L, approximately 6–8 focused engineering days
- **Risk**: MED; the v4 migration is additive plus two small rebuilds (`locks`, `projects`), but
  the §7.5 plumbing touches every engine map, and a missed map entry fails at runtime, not compile
  time
- **Depends on**: 005 and 008 (`DONE`); 007 may run in parallel — this plan touches no extraction
  file (see "Coexistence with Plan 007")
- **Category**: architecture / feature / tests
- **Planned at**: commit `e8645e5`, 2026-08-21; design hash in the drift check

## Current state

- Bundle schema is 3 (`SchemaV3`, Plan 008); `assets/` and `exports/` exist in every bundle and
  nothing writes to them. `project_assets` records screenplay source files only.
- The mutation engine is Plan 005's as built: `EditPrimitives` three levels, `RowSnapshotStore`
  table/key maps, `RowGraph.tableOrder`, `LockPolicy`/`ProtectionPolicy`, `ReviewOperations`
  target map, `InverseApplication.deleteOrder` — §7.5 of the design names every switch point this
  plan must extend, drawn from those files.
- `RelativeProjectPath`'s containment checks are lexical (design §4.1's realpath rule is new).
- Pins unchanged: Xcode 26.6, Swift 6, macOS 15 floor, GRDB 7.11.1, swift-json-schema 0.13.1.

## Coexistence with Plan 007

Plan 007 (in progress or done) owns `Extraction/` in both packages, the review UI, and the run
coordinator. This plan touches none of those files. The one shared surface is `ProjectMigrator`
plus the schema constants — additive here — the FilmCore test support files, and two files 007's
execution also touched: `Domain/Job.swift` (this plan task-gates `applyReport` and adds
`manifestReport`) and `ProjectRepository.swift` (beside `setApplyReport`); coordinate merges
there and nowhere else. Nothing in this plan changes extraction behavior, and `scripts/eval-inputs.txt`
is untouched (no schema, prompt, or validator this plan adds is an evaluation input).

## Contracts (normative)

### A. Migration v4 and `SchemaV4` (design §4.2, §4.3 — build them as written there)

- `FilmCoreVersion.bundleSchema = 4`; `ProjectMigrator` registers `"v4"` (default
  `foreignKeyChecks: .deferred`) running design §4.2's six steps **in that order**; DDL lives in
  a new `Storage/SchemaV4.swift` of raw SQL constants whose spelling is §4.3's, byte for byte
  where §4.3 gives SQL — including the PROV block reused verbatim, every `CHECK` (booleans
  included), every `ON DELETE`, the two `assets` staleness CHECKs and `rejected_explicitly`,
  the `asset_versions` partial unique index, and the §4.2 step-2 index list with
  `index_asset_requirements_on_entity_id` leading on `entity_id`.
- Template seeding (§4.2 step 3): `DefaultRequirementTemplate` is a FilmCore constant carrying
  the §3.2 table **with its frozen `code` values** (`face_closeup`, `profile_side`, `waist_up`,
  `full_body`, `establishing`, `reference`); the migration seeds it for an existing project row;
  `ProjectBundle.create` seeds it immediately after inserting the project row. One constant, two
  call sites, identical content — tested by comparing a migrated and a fresh bundle's template
  rows minus ids and timestamps.
- `entities.manifest_inclusion` via `ALTER TABLE` (§4.2 step 1); `locks` rebuilt with
  `'requirement'` admitted (step 4); `projects` rebuilt last with `CHECK
  (bundle_schema_version = 4)` (step 5).
- Migration test per design §4.2's closing paragraph: v3 fixture synthesized in-test by SQL
  (never checked in — there is no frozen v3 artifact requirement; Plan 003's v1 sample stays as
  is), unchanged row counts for every carried table, seeded template rows, a `requirement` lock
  row accepted by the rebuilt CHECK, clean `PRAGMA foreign_key_check`, `user_version = 4`.

### B. Domain types and engine plumbing (design §4.4, §7.5 — storage side only)

- Every §4.4 type exists with the names and raw values written there. `Job.applyReport` and the
  new `Job.manifestReport` both **gate on `task`**, and a test asserts `ApplyReport` and
  `ManifestApplyReport` stay key-disjoint. The **writers gate on `task` too**: `setApplyReport`
  refuses a non-extraction parent and `setManifestReport` a non-`inferAssetManifest` one with a
  typed error, so a wrong-task report can never land in the shared column (today's
  `setApplyReport` checks parent-and-not-completed only — widen it here, with a test each way).
  `JobManaging` gains `setManifestReport(jobID:_:)` (§7.5) — implemented and tested here against
  a hand-created parent job; Plan 012 is its real caller.
- `SubjectKind` gains `requirement`, `requirementScene`, `basis`, `dependency`, `asset`,
  `version`, `templateEntry`; `LockField` gains `reason` and `necessity` with `displayName`
  strings. Carry every case through the §7.5 list: `lockable` (+`requirement` only),
  `evidenceable` unchanged, `LockPolicy.fields(for:)`,
  `ProtectionPolicy.parserOwnedFields(of:)` (`requirement` → `name`), the snapshot store's
  `table(for:)`/`subjectKind(of:)`/`primaryKey(of:)`/`uniqueColumns(of:)` maps (with
  `asset_versions` = `[[asset_id, version_number], [relative_path]]` and a source comment that
  the partial approved index is invisible to `wouldCollide`), `RowGraph.tableOrder` (new tables
  appended in FK dependency order: types, requirements, scenes-links, basis, dependencies,
  assets, versions), `InverseApplication.deleteOrder`, and `ReviewOperations.target(for:)` —
  the three reviewable kinds mapped, and **explicit exclusions** for `basis`, `templateEntry`,
  `asset`, `version` that throw a typed error rather than issuing SQL. `expand` and
  `proposedRefs` changes are Plan 010's.
- `ProjectObservationHub` maps the new tables to `ProjectChange.requirements` / `.assets`.
- `canReplaceScreenplay` widens per §7.5: the PROV-table enumeration gains the v4 fact tables,
  and any `assets` or `asset_versions` row refuses Replace outright. Tested by SQL-seeding each
  row kind.
- **Containment groundwork (§4.1, complete here, not split with Plan 011)**: a FilmCore
  `BundleContainment` that is **descriptor-relative, not check-then-operate on a path** — a
  path-based `realpath` validation followed by a separate path-based operation leaves a window
  in which an intermediate directory is swapped for a symlink. It opens the bundle root once as
  a directory descriptor, walks every component with `openat(O_NOFOLLOW | O_DIRECTORY)` (the
  leaf with `O_NOFOLLOW`; a not-yet-created leaf is created descriptor-relative under its
  already-walked parent), and hands the caller a descriptor (or performs the
  `openat`/`renameat`/`unlinkat`-form operation itself) so nothing re-traverses the path.
  Unit-tested here against a planted symlinked component, a planted symlinked **leaf**, and
  swap-after-validation for both the leaf and an **intermediate** component (validate, swap
  `assets/` for a symlink, operate — the descriptor walk must refuse). Adopted by the
  screenplay import path in the same change. Plan 011's media operations are its main
  consumers and add no containment logic of their own.

### C. Reads and the deterministic computations (design §3.3, §5.2's derivation, §6.4, §7.6)

- `ManifestQualification` (FilmCore, pure functions): the 2+ rule with §3.3's role filter and
  entity-eligibility pool, prop exception (§3.4 — props qualify only under `'always'`), and the
  §6.4 `active(requirement)` predicate. One implementation; every read below calls it.
- `ProjectReading` gains §7.6's members. Canonical requirements' `requiredBy` derives from
  `scene_entities` at read time; variant links read their stored rows. `RequirementDetail`
  carries basis rows joined to their underlying facts' evidence, dependencies both directions,
  the derived `isBlocked` (dependency satisfied = Approved asset **or** target inactive under
  the full §6.4 predicate, §3.5), `isActive`, and the unreviewed-facts flag (§3.7).
  `manifestSummary()` and `missingAssets()` implement §6.4's Missing/Blocked/Stale/optional
  definitions; `requirementTemplate()` and `orphanedMedia()` exist (the latter returns files
  under `assets/` no version row references — empty until Plan 011 writes any).
- Default reads exclude rejected rows; `includeRejected:` filters mirror the entity reads.
- Read tests run over SQL-seeded fixtures (no operations exist yet): qualification matrices
  (roles × counts × inclusion × kind), blocked/missing/stale derivations including an inactive
  dependency target, the drift-badge predicates of §5.3 as read-layer facts (qualifies-but-no-set,
  no-longer-qualifies, suppressed, template-entry-disabled), and the §6.1 display rule that a
  requirement with no asset row reads as Needed.

## Target file layout (additions, changes)

```text
Packages/FilmCore/
  Storage/SchemaV4.swift (new), ProjectMigrator.swift (+"v4"), ProjectBundle.swift (create seeds
    template), ProjectRepository.swift (canReplaceScreenplay widened; setManifestReport),
    RowSnapshotCoding.swift (maps + tableOrder), ProjectObservation.swift (areas),
    BundleContainment.swift (new)
  Domain/ AssetRequirement.swift, Asset.swift, AssetVersion.swift, RequirementTemplate.swift
    (AssetRequirementType + DefaultRequirementTemplate), ManifestReads.swift (RequirementSummary,
    RequirementDetail, ManifestSummary, MissingAsset), ManifestApplyReport.swift (+
    ManifestSettings, ManifestInclusionSuggestion), SubjectRef.swift (+cases), LockField.swift
    (+cases), ProjectReads.swift (ProjectChange areas), Entity.swift (+manifestInclusion),
    Job.swift (manifestReport; applyReport task-gated)
  Editing/ LockPolicy.swift, ProtectionPolicy.swift, ReviewOperations.swift (target map only),
    InverseApplication.swift (deleteOrder), ManifestQualification.swift (new)
  ProjectTools.swift (+§7.6 reads, setManifestReport)
  Tests/ MigrationV4Tests, ManifestQualificationTests, ManifestReadTests, BundleContainmentTests,
    ReplaceGuardV4Tests, ReportTypeTests
```

App target: no change beyond compiling (new enum cases are additive). `project.yml` untouched.

## Steps

### Step 1: Schema v4, migration, seeding

Implement contract A.

```bash
swift test --package-path Packages/FilmCore --filter MigrationV4Tests
swift test --package-path Packages/FilmCore
```

Expected: the v3-fixture migration assertions and the migrated-vs-fresh template equivalence
hold; the full FilmCore suite passes; `Package.resolved` unchanged.

### Step 2: Domain types and engine plumbing

Implement contract B.

```bash
swift test --package-path Packages/FilmCore
grep -rn "case requirement" Packages/FilmCore/Sources/FilmCore/Editing | head
```

Expected: suite passes; a review accept aimed at a `basis`/`templateEntry`/`asset`/`version` ref
throws the typed exclusion, never SQL; Replace refuses over each seeded v4 row kind; the planted
symlink is refused by `BundleContainment` and by the screenplay import path.

### Step 3: Reads and computations

Implement contract C.

```bash
swift test --package-path Packages/FilmCore
./scripts/verify.sh
```

Expected: qualification and read tests pass over seeded fixtures; `verify.sh` exits 0 (the app
builds; no UI change exists to test). Update `docs/plans/README.md`.

## Done criteria

- [ ] `./scripts/verify.sh` exits 0; `PRAGMA user_version = 4`; every §4.3 table, column, CHECK,
  ON DELETE, index (partial unique included) exists exactly as written; template seeded
  identically on migrate and create; v2→v3 migrations untouched.
- [ ] Every §7.5 storage-side switch point carries the new kinds (compile-enforced where the
  engine's exhaustive switches allow, test-enforced elsewhere); `canReplaceScreenplay` and
  `BundleContainment` behave per design; report types are task-gated and key-disjoint.
- [ ] §7.6 reads exist and derive qualification, blocked, missing, stale, and active from
  `ManifestQualification` alone; no mutation operation, no media write, no FilmBrain change, no
  UI beyond compilation was added.
- [ ] `docs/plans/README.md` marks Plan 009 `DONE`.

## STOP conditions

- The `docs/PHASE2_DESIGN.md` hash differs and §3.3, §3.4, §4, §6.4, §7.5, or §7.6 changed.
- A §4.3 constraint is rejected by the shipped SQLite (report the exact statement and error —
  the design records these as verified; a divergence means the environment changed).
- The `locks` or `projects` rebuild loses rows, or `PRAGMA foreign_key_check` is dirty.
- Extending a §7.5 switch point requires modifying Plan 007's extraction files.
- A verification command fails twice after one reasonable scoped correction.
- Work expands into mutation operations, media import, UI, or inference (Plans 010–012).

## Maintenance notes

- Plan 010 fills the operations over this schema and extends `ReviewOperations` (`expand`,
  `proposedRefs`); Plan 011 writes into `assets/` through `BundleContainment` and implements the
  §6.3 recompute; Plan 012 calls `setManifestReport` and the reads. Keep those seams empty.
- `DefaultRequirementTemplate`'s `code` values are frozen identifiers (§3.2); renaming one is a
  design change, not a refactor.
