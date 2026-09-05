# Plan 013: Storage v5 and the prompt model (Phase 3a)

> **Executor instructions**: Read `docs/PHASE3_DESIGN.md` in full first. This plan implements its
> §4 (the whole v5 migration, the 3b-shaped columns included, defaulted empty), §4.4's
> storage-side types, §7.4's engine plumbing, §7.5's reads with §3.3's new
> `generationBlockedBy` pair, §3.4's derived staleness read, and §8.2's
> `AssetPromptInputBuilder` with its golden fixture — everything Phase 3 stores, reads, and
> derives, with **no new user-facing operations** (Plan 014), **no UI** (Plan 015), and **no AI**
> (Plan 016). Prompt
> rows exist after this plan only when tests seed them. This plan also carries the Phase 2
> record-keeping debts and the §3.3 Phase 2 defect repair the design assigns to "the first
> Phase 3 plan" (§2, §13's gate list).
> Follow the steps in order, run every verification command, honor every STOP condition.
> Requires Plans 009–012 `DONE` (they are, on `main` at `a861a00`). When complete, set this
> plan's row in `docs/plans/README.md` to `DONE`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   90dc7842e286b2bbf556a02384096448694d4a698fd24f64a3cdc5ebd4fcb3d7 docs/PHASE3_DESIGN.md \
>   84c3599561dac60fd02d00d8a3d6a564558bac340fb5988d8bcc83868748ff68 docs/PHASE2_DESIGN.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   8660b7114aa507a98ec2cf621176355cb912b749ff3b84395e6f4af6fb927691 docs/OVERVIEW.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all five print `OK`, and `git rev-parse HEAD` is descended from `a861a00`. If the
> PHASE3 hash differs, stop for reconciliation when §3.3, §3.4, §4, §7.4, §7.5, §8.2, or
> §8.5 changed; a hash change that is only §13/§14 acceptance being recorded in the status prose is
> re-pinned in this block, not a stop. (The OVERVIEW pin guards the `#asset-states` vocabulary
> the v5 rows feed; Plan 015 edits OVERVIEW and sweeps this pin in the same commit.)
>
> **Live gates: none.** Nothing here calls Codex; every command must pass with no network. A
> step that appears to need a live call is a STOP condition, not a deferral.

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: M–L, approximately 6–8 focused engineering days
- **Risk**: MED; the v5 migration is additive plus one `projects` rebuild, but §7.4's ripple
  edits **shipped Plan 009 code** — the `RowGraph.tableOrder` insertion and the
  `InverseApplication.deleteOrder` renumber — where a wrong value fails at restore time, not
  compile time, and the §8.2 digest is persisted on customer rows forever
- **Depends on**: 012 (transitively 009–011; all `DONE` at `a861a00`) — Phase 3 gates on
  nothing outside this phase (design §2)
- **Category**: architecture / feature / tests
- **Planned at**: commit `a861a00`, 2026-08-22; design hash in the drift check

## Current state

- Bundle schema is 4 (`SchemaV4`, Plan 009); the full Phase 2 surface is shipped: requirement
  model and operations, media import and approval, staleness fan-out, manifest inference.
- `ManifestGraph`'s dependency load (`ProjectRepository+ManifestReads.swift`) fetches
  `asset_dependencies` with **no review-state filter**, unlike the sibling scene-link load and
  `RequirementOperations.activeEdges` — the shipped `dependsOn`, `dependents`,
  `unsatisfiedDependencies`, and Phase 2's Blocked all count tombstoned edges. Design §3.3
  classifies this as a Phase 2 defect and assigns the repair here.
- Plans 009 and 010's in-file `## Status` blocks read `TODO` while README lists them
  `DONE` (they were flipped to `DONE` on 2026-08-22 ahead of this plan — see contract E),
  and `docs/IMPLEMENTATION_NOTES.md` has no Plan 009/010 sections (design §2, §13's
  gate list — this plan settles both).
- The mutation engine is Plan 005's as extended by 009/010: every switch point §7.4 names is
  built and shipped; this plan extends each, and two of them are edits to shipped values, not
  appends.
- Pins unchanged: Xcode 26.6, Swift 6, macOS 15 floor, GRDB 7.11.1, swift-json-schema 0.13.1.

## Owner gates (design §14 — all seven accepted; none binds this plan)

Audited against all seven §14 decisions so silence is not mistaken for oversight: none
changes this plan's work. **All seven were owner-decided 2026-08-22** — §14.1
(evidence-gated batch) and §14.6 (the tiered bar) first, the other five accepted as
recommended — and they land elsewhere: §14.1, §14.3, §14.4, and §14.6 in Plan 016;
§14.2, §14.5, and §14.7 in Plans 014–015 (operations and workshop
surfaces). The schema, engine plumbing, reads, and input builder are identical under every
one of those decisions, so this plan proceeds regardless — and, uniquely
among the Phase 3 plans, **no §14 decision gates this plan's flip to `DONE`**
(`docs/plans/README.md`'s Phase 3 rule binds 014, 015, and 016 only).

## Contracts (normative)

### A. Migration v5 and `SchemaV5` (design §4.2, §4.3 — build them as written there)

- `FilmCoreVersion.bundleSchema = 5`; `ProjectMigrator` registers `"v5"` (default
  `foreignKeyChecks: .deferred`) running §4.2's five steps **in that order** (new tables before
  the `asset_versions` ALTER, `projects` rebuilt last, **no `locks` rebuild** — the new kinds
  are not lockable, §7.4); DDL lives in a new `Storage/SchemaV5.swift` of raw SQL constants
  whose spelling is §4.3's byte for byte where §4.3 gives SQL — the PROV block verbatim on
  `asset_prompts`, the reduced-provenance citation shape on `asset_prompt_references`, every
  CHECK (the three skill-provenance equivalences on `created_source`/`skill_id`/paths/SHA
  included), every ON DELETE, the two SET-NULL scan-path indexes **plus §4.2
  step 3's `index_asset_versions_on_prompt_id`** — three new indexes in all — and **no**
  separate `asset_prompts` index (§4.2 step 2's stated deviation — the UNIQUE pair
  materializes it).
- The 3b-shaped columns (`target_model`, `guidance`, `skill_id`, `skill_entry_path`,
  `skill_entry_sha256`) are created **now**, defaulted `''`, so Plan 016 needs no second
  migration (§2's assignment).
- Migration test per §4.2's closing paragraph: v4 fixture synthesized in-test by SQL (the
  Plan 011 pattern), unchanged row counts for every carried table, new columns `NULL` (or the
  stated `''` defaults) on carried rows, the `asset_versions.prompt_id` FK enforced, clean
  `PRAGMA foreign_key_check`, `user_version = 5`, round-trip through open; the fresh-create
  path lands at 5 directly; v4 shows no one-way upgrade modal (that gate stays
  `schemaVersion == 1` only). `"v2"`–`"v4"` migrations untouched.

### B. Domain types and engine plumbing (design §4.4, §7.4 — storage side only)

- Every storage-side §4.4 type exists with the names and raw values written there:
  `AssetPrompt`, `AssetPromptReference`, `ReferenceClass`, `ReferenceFidelity` (raw values =
  the §4.3 CHECK's snake_case encodings — frozen identifiers), `ReferenceAttributes` (the
  derived triple) and `ReferenceAttributeRules` (§3.3's pinned derivation tables as **one pure
  function over the tuple §3.3 names** — owning requirement, the owning entity's kind and
  display name, target requirement, the target entity's kind and display name, the target's
  template code; role templates with the attribute-transfer target rule, exclusion
  boilerplate, the (owning, target) fidelity matrix including **both `identity` owner rows** —
  unit-tested against every table row; owner-decided 2026-08-22, no stored attribute column
  exists), `AssetPromptDetail` and `PlannedDependency` (contract C's read carriers),
  `AssetPromptApplyReport`, `AssetPromptSettings`, and the `AssetPromptInputBudget` constant
  (**pinned here: default = 120_000 UTF-16 units**, `ManifestInputBudget`'s value — orders of
  magnitude of headroom at single-requirement scale; it lives beside its builder in
  `Extraction/AssetPromptInputBuilder.swift`, the shipped `ManifestInputBudget` placement;
  the §8.1 pre-flight that consumes it is Plan 016's). Deliberately **not** here, stated so §4.4's list is fully assigned:
  `EditOperation` cases and the `LockPolicy` guard *wiring* are Plan 014's (with the
  operations); the six `ProjectStoreError` cases land with the plan that first throws each
  (three in Plan 014, three in Plan 016 — the plans name them); `AssetPromptProposal`, `AssetPromptApplyOutcome`,
  `PromptApplying`/`applyAssetPromptRun` (the eighth `ProjectTools` role),
  `PromptSkillDescriptor`, and `AssetPromptRunGate` are Plan 016's (with the job).
- `JobManaging` gains `setAssetPromptReport(jobID:_:)` and `Job` gains `assetPromptReport`,
  **task-gated both directions** like the two shipped siblings (writer refuses a
  non-`generateAssetPrompt` parent with a typed error; accessor decodes only for that task),
  implemented and tested here against a hand-created parent job (the Plan 009
  `setManifestReport` precedent). **Beside the public door, the internal in-transaction
  primitive** `ProjectRepository.writeAssetPromptReport(_:jobID:in:)` — the shipped
  `writeManifestReport` shape verbatim: takes the caller's `Database` handle and opens
  nothing, task-guarded `UPDATE … WHERE id = ? AND task = ?`, `changesCount == 1` — is built
  and tested here too, because §8.4 step 3 writes the report **inside** the apply
  transaction and the public setter, like its two siblings, opens its own transaction and
  refuses completed jobs (the recorded Phase 2 lesson in `writeManifestReport`'s doc
  comment; Phase 3 has no pre-apply zero-counter write). Plan 016's applier is the
  primitive's real caller; the public door serves tests and tooling.
  `AssetPromptApplyReport` carries **§8.5's seven fields, restated because §8.5 is the only
  field list in the design**: `requirementID`, `promptID`, `promptNumber`, `referenceCount`,
  `targetModel`, `durationMs`, `settings: AssetPromptSettings`. The three report types
  (`ApplyReport`, `ManifestApplyReport`, `AssetPromptApplyReport`) are asserted key-disjoint
  (Phase 2 §4.4's rule extended; they share one column, §8.5) — an assertion that needs all
  three types' keys, which is why the fields are pinned here.
- `SubjectKind` gains `prompt` and `promptReference`, carried through every §7.4 switch point:
  `lockable` and `evidenceable` **unchanged** (trailing empty arms); `RowSnapshotStore`
  `table(for:)`/`uniqueColumns(of:)` (with
  `asset_prompts: [[requirement_id, prompt_number]]` and
  `asset_prompt_references: [[prompt_id, position]]` — the pair is what makes `wouldCollide`
  fire on §7.2's prompt-number walk; `primaryKey(of:)` already answers `id` for both — a
  default-`id` expression, not a switch, so no edit); `RowGraph.subjectKind(of:)`;
  `precheckSnapshots`/`wouldCollide`; `LockPolicy.fields(for:)` empty for both (the
  `appearance` precedent); `ProtectionPolicy.parserOwnedFields(of:)` no new case;
  `ReviewOperations.unreviewableKinds` gains both; `ProjectObservationHub.areas` maps both
  tables to `.assets` (no new `ProjectChange` member — the workshop observes
  `.requirements ∪ .assets`).
- **`RowGraph.tableOrder` gains both tables with `asset_prompts` inserted before
  `asset_versions`** (the v5 FK graph of §7.4: `asset_versions → asset_prompts` via
  `prompt_id`), reading `… assets, asset_prompts, asset_versions, asset_prompt_references …`,
  both insertions before `locks`.
- **`InverseApplication.deleteOrder` is renumbered, not appended**, to §7.4's pinned values
  (`promptReference 0 … synopsis/script 16`), preserving the shipped kinds' relative order; a
  test asserts descending-`deleteOrder` restore order equals ascending `tableOrder` **for the
  new kinds only** (§7.4's stated scope — the shipped `requirementScene`/`basis` disagreement
  is harmless and out of the assertion).
- `LockPolicy.requireRequirementUnlocked` exists as the named thin wrapper over the shipped
  `checkUnlocked(subject:field:in:)` whole-lock idiom (§7.4), unit-tested here; Plan 014
  wires it into each of §7.2's operations.

### C. Reads and the Phase 2 repair (design §3.3, §3.4, §7.5)

- **The Phase 2 defect repair, first**: `ManifestGraph`'s dependency load gains the
  `review_state <> 'rejected'` filter its siblings already carry (§3.3). Tests assert the
  shipped reads change accordingly: a tombstoned (`removeDependency`-removed `ai`/`parser`)
  edge no longer appears in `dependsOn`/`dependents`, no longer blocks
  (`unsatisfiedDependencies`, `MissingAsset.isBlocked`/`blockedBy`), and Phase 2's dashboard
  Blocked count drops. Recorded in `docs/IMPLEMENTATION_NOTES.md` as a Phase 2 defect repair
  (contract E).
- `RequirementDetail` gains **`generationBlockedBy: [UUID]`** (unsatisfied active
  dependencies, §3.3 order) and derived **`isGenerationBlocked`**, sourced from
  `ManifestGraph.unsatisfiedDependencies` under the filter above, mirroring
  `MissingAsset.blockedBy`'s shape — deliberately not the shipped Missing-qualified
  `isBlocked`, which stays untouched (§3.3 records why: the two cases Phase 3 lives in return
  `false` from it).
- `RequirementDetail` gains `plannedDependencies: [PlannedDependency]` — §3.3's **planned
  dependencies** whole: every active dependency, satisfied or not, with derived class (§3.3's
  four-row table), effective role/exclusion/fidelity derived through
  `ReferenceAttributeRules` (§3.3's pinned tables — no stored attribute, no override),
  satisfaction, the referenced approved version where satisfied, and a **nullable
  `designator: Int?` populated only on satisfied rows** — that non-nil subset, in order, is
  §3.3's **rendered references**, densely numbered `@Image 1…N`, and the unsatisfied rows
  contribute no number. One list carries both collections; there is no second read, and no
  surface may re-derive a designator. The §3.3 ordering (class rank
  `identity → look → location → prop`, then edge `created_at`, then edge id) is **one shared
  FilmCore function** Phase 5 inherits, and the dense numbering is computed there too.
- `RequirementDetail` gains `currentPrompt: AssetPromptDetail?` (body, target model,
  guidance, number, skill identity, source, citations, and the **derived `isStale`** — §3.4's
  digest comparison via contract D, including the `input_format_version` mismatch reading
  stale with the "older input format" reason), `promptCount`, and `inProgressSince`;
  `ProjectReading` gains `promptHistory(requirementID:)`. Current prompt := highest
  `prompt_number` (§3.2), derived, no flag. Prompt reads exclude nothing (prompts have no
  rejected axis); requirement-level reads keep flowing through Phase 2 §6.4's single active
  predicate (§7.5).
- Read tests run over SQL-seeded fixtures (no prompt operations exist yet): derivation
  classes and §3.3's rules tables (role templates including the attribute-transfer
  target, exclusion boilerplate, the fidelity matrix with both `identity` owner rows),
  ordering stability (identical timestamps fall to edge id), the two collections asserted
  apart (an unsatisfied edge carries a nil designator while the satisfied rows stay densely
  numbered across it), blocked pair naming the first unsatisfied dependency,
  tombstone exclusion, cross-entity edges, current-by-number with gaps after simulated
  deletes.

### D. `AssetPromptInputBuilder` and the golden fixture (design §8.2, §3.4 — 3a by §2's assignment)

- `AssetPromptInputBuilder` (FilmCore, `Extraction/` beside `ManifestInputBuilder`) renders
  §8.2's field list **exactly** — that list is the single normative digest-input definition;
  no field optional, absent values as `''`/`0`/empty arrays; `dependencies[]` carries the
  full active set, `references[]` the satisfied subset with designators. `render(requirementID:)`
  returns `AssetPromptInput` whose `digest` is the SHA-256 of the rendered JSON text — the
  one prompt digest (§3.4), the same value a run will record as `jobs.input_sha256`
  (the delimiter wrapper is Plan 016's prompt file, outside the digest).
- The determinism contract is §8.2's five rules in full: Swift-side total ordering ending in
  row id for every collection (the keys as listed), `sortedKeys`, no
  clock/locale/floats/environment, `schemaVersion = 1` carried in the rendered input, and
  **a committed golden fixture** (which now also pins §3.3's derivation tables — the
  derived role/exclusion/fidelity are rendered output, so a rules-table wording change is
  a renderer change and bumps `schemaVersion`) — one canonical project state, its
  byte-exact rendered JSON, its exact digest — so a renderer change fails a test instead
  of silently staling every prompt in every customer project. Any shape change bumps
  `schemaVersion`; no digest re-stamp migration exists (§8.2's versioning posture).
- Staleness tests per §10's list: digest stability; each §8.2 input family flips it (entity
  description, state edit, requirement rename, scene-link change, synopsis edit, reference
  approved-version change, dependency add and remove **including an unsatisfied edge**,
  `reclassify`, and **renaming a referenced requirement or its entity** — the derived role
  is a rendered field, so the digest flips through `dependencies[]`/`references[]` with no
  separate staling path (§8.2, §10); the format-version mismatch reads
  stale with the format reason; asset `is_stale` and prompt staleness independent in one walk.
  (The skill-update-does-not-stale case is Plan 016's, where a skill first exists.)

### E. Phase 2 record-keeping (design §2, §13's gate list)

- The in-file `## Status` blocks of `docs/plans/009-*.md` and `docs/plans/010-*.md`
  already read `DONE`, matching README (flipped 2026-08-22 ahead of this plan); verify
  rather than edit.
- Open Plan 009 and Plan 010 sections in `docs/IMPLEMENTATION_NOTES.md` recording the two
  Phase 2 findings the design surfaced, each with the repairing/verifying test names from
  this plan: the tombstoned-dependency reads (contract C's repair) and the
  `tableOrder`/`deleteOrder` ordering mismatch on `requirementScene`/`basis` (documented as
  harmless — they do not FK each other — and left; contract B's scoped agreement test is the
  guard for the new kinds).

## Target file layout (additions, changes)

```text
Packages/FilmCore/
  Storage/SchemaV5.swift (new), ProjectMigrator.swift (+"v5"),
    ProjectRepository+ManifestReads.swift (dependency-load filter; prompt reads),
    RowSnapshotCoding.swift (maps, tableOrder insertion), ProjectObservation.swift (areas),
    ProjectRepository.swift (setAssetPromptReport)
  Domain/ AssetPrompt.swift (new: AssetPrompt, AssetPromptReference, ReferenceClass,
    ReferenceFidelity, ReferenceAttributes, ReferenceAttributeRules, AssetPromptDetail,
    PlannedDependency),
    AssetPromptApplyReport.swift (new: + AssetPromptSettings),
    ManifestReads.swift (RequirementDetail additions), SubjectRef.swift (+cases),
    Job.swift (assetPromptReport)
  Editing/ InverseApplication.swift (deleteOrder renumber), LockPolicy.swift
    (requireRequirementUnlocked), ReviewOperations.swift (unreviewableKinds)
  Extraction/AssetPromptInputBuilder.swift (new; + AssetPromptInputBudget beside its
    builder — the shipped ManifestInputBudget placement)
  ProjectTools.swift (+§7.5 reads, setAssetPromptReport)
  Tests/ MigrationV5Tests, PromptReadTests, PlannedDependencyTests,
    ReferenceAttributeRulesTests, GenerationBlockedTests,
    AssetPromptInputBuilderTests (+ the committed golden fixture), PromptStalenessTests,
    DeleteOrderAgreementTests, ReportTypeTests (extended), DependencyFilterRepairTests
docs/plans/009-*.md, docs/plans/010-*.md (Status blocks), docs/IMPLEMENTATION_NOTES.md
```

App target: no change beyond compiling (new enum cases and read fields are additive).
`project.yml` untouched (the `PromptSkills` resource item is Plan 016's).
`scripts/eval-inputs.txt` is untouched, and no file it lists is edited by this plan.

## Steps

### Step 1: Schema v5 and the migration

Implement contract A.

```bash
swift test --package-path Packages/FilmCore --filter MigrationV5Tests
swift test --package-path Packages/FilmCore
```

Expected: the v4-fixture assertions including the nullable-add-column-with-CHECK shape and
the enforced `prompt_id` FK hold; the full FilmCore suite passes; `Package.resolved`
unchanged.

### Step 2: Types and engine plumbing

Implement contract B.

```bash
swift test --package-path Packages/FilmCore
```

Expected: suite passes, every shipped Plan 005/009/010/011 inverse round-trip still
byte-identical under the renumbered `deleteOrder` and re-ordered `tableOrder` (SQL-seeded
prompt/citation rows restored in FK-safe order); a review accept aimed at a
`prompt`/`promptReference` ref throws the typed exclusion; the report writer and accessor
refuse wrong tasks; the three report types stay key-disjoint.

### Step 3: Reads, the Phase 2 repair, and the input builder

Implement contracts C and D.

```bash
swift test --package-path Packages/FilmCore
```

Expected: the tombstone filter changes the four shipped reads as specified; the blocked pair,
planned dependencies (designators on the satisfied rows only), and prompt reads derive per
§3.3/§3.2 over seeded fixtures; the golden
fixture asserts byte-exact JSON and digest; every §8.2 input family flips staleness and
nothing else does.

### Step 4: Record-keeping and full verification

Implement contract E, then verify.

```bash
grep -c '^- \*\*Status\*\*: DONE' docs/plans/009-*.md docs/plans/010-*.md
grep -n '^## Plan 009\|^## Plan 010' docs/IMPLEMENTATION_NOTES.md
./scripts/check-docs.sh
./scripts/verify.sh
```

Expected: the first grep prints 1 for each plan file and the second finds both new notes
sections — `check-docs.sh` cannot detect either edit (check 6 asserts only that a
`## Status` heading exists, not its value, and `IMPLEMENTATION_NOTES.md` is outside its doc
set), so these greps are the actual verification of contract E; both gates exit 0 (the app
builds; no UI change exists to test — if a UI suite fails,
compare against the `docs/IMPLEMENTATION_NOTES.md` Plan 012 record of the environmental
automation-mode flake before blaming this plan). Update `docs/plans/README.md`.

## Done criteria

- [ ] `./scripts/verify.sh` exits 0; `PRAGMA user_version = 5`; every §4.3 table, column,
  CHECK, ON DELETE, and index exists exactly as written, 3b-shaped columns included; the v4
  fixture migrates losslessly; `"v2"`–`"v4"` untouched.
- [ ] Every §7.4 storage-side switch point carries the new kinds; `tableOrder` and
  `deleteOrder` hold §7.4's pinned orders with the scoped agreement test; the report door is
  task-gated and key-disjoint; `requireRequirementUnlocked` exists and is tested.
- [ ] The §3.3 tombstone-filter repair is in with tests, and `generationBlockedBy`,
  `plannedDependencies` (nullable designators per §3.3's split), `currentPrompt` (derived
  `isStale` included), `promptCount`,
  `inProgressSince`, and `promptHistory` derive per design; the shipped `isBlocked` is
  unchanged.
- [ ] `AssetPromptInputBuilder` renders §8.2 exactly under all five determinism rules; the
  golden fixture is committed and byte-asserted; no mutation operation, no UI, no FilmBrain
  change, no AI was added.
- [ ] Plans 009/010's `## Status` blocks read `DONE`; `docs/IMPLEMENTATION_NOTES.md` carries
  the two new Phase 2 sections; `docs/plans/README.md` marks Plan 013 `DONE`.

## STOP conditions

- The `docs/PHASE3_DESIGN.md` hash differs and §3.3, §3.4, §4, §7.4, §7.5, §8.2, or §8.5
  changed.
- A §4.3 constraint is rejected by the shipped SQLite (report the exact statement and error —
  the design records the shape as legal; a divergence means the environment changed).
- The `projects` rebuild loses rows, or `PRAGMA foreign_key_check` is dirty.
- The `deleteOrder` renumber or `tableOrder` insertion breaks a shipped inverse test in a way
  one scoped correction does not fix (the pinned values are contract; report the disagreement
  rather than re-deriving an order).
- The golden fixture cannot be made byte-stable across runs (report the nondeterminism; it
  breaks §8.2's contract and would stale customer prompts).
- The tombstone-filter repair changes a Phase 2 read in a way §3.3 does not predict.
- A verification command fails twice after one reasonable scoped correction.
- Work expands into prompt operations, the workshop UI, the recompute amendment, skill
  materialisation, or generation (Plans 014–016), or into Phase 4 dashboards / Phase 5
  scene-prompt scope.

## Maintenance notes

- Plan 014 builds §7.2's operations over this schema, wires `requireRequirementUnlocked`,
  and amends the recompute; Plan 015 builds the workshop over them; Plan 016 attaches the AI
  job to `AssetPromptInputBuilder`'s digest and the report doors. Keep those seams empty.
- `AssetPromptInputBuilder`, `generateAssetPrompt`, and `asset-prompt-v1` are frozen
  identifiers with FROZEN rows in `scripts/check-docs.sh`. The snake_case fidelity encodings
  are frozen too (design §13), but by the §4.3 CHECK and the `ReferenceFidelity` raw values,
  **not** by check 1 — no FROZEN row is possible for them, because the obvious wrong
  spellings are legitimate elsewhere in the docs (`fullPreserve` is the Swift case name; the
  hyphenated forms are the vendored prose's). `AssetPromptInputBuilder.schemaVersion` bumps
  on any rendered-shape change — never re-stamp digests.
