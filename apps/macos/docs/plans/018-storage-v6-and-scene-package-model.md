# Plan 018: Storage v6 and the scene-package model (Phase 5a)

> **Executor instructions**: Read `docs/PHASE5_DESIGN.md` in full first. This plan
> implements its §3.1–§3.5 (the package model, the scene reference plan and continuity
> context, the three derived package states, the target-profile catalog with the persisted
> active profile), §3.7's boundary refactor (`SkillTreeOperations` moves down to FilmCore),
> §4 (bundle schema v6, on-disk conventions, domain types), §7.5 (the reads and the frozen
> observation contract), and §8.2's FilmCore half (the input builder, budget, digest, and
> golden fixture). **No operation, no exporter, no UI, no AI**: after this plan every new
> row is reachable only from tests — the operations are Plan 019's, the section is Plan
> 020's, the job is Plan 021's. Also read `docs/REFERENCE_PROJECTS.md` before touching the
> materialiser refactor, and `PromptSkills/README.md` before touching anything under
> `PromptSkills/` (vendored payload — never edited, never imported). Follow the steps in
> order, run every verification command, honor every STOP condition. Requires Plans
> 013–016 `DONE` (they are) and **Plan 017 `DONE`** — §3.3's derivation reads
> `ReadinessSnapshot` and must not re-derive scene readiness. When complete, set this
> plan's row in `docs/plans/README.md` per the Done criteria.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   bd477ef76dbb98c2f7dbffdae5310b8f824e309e904bcd91f03cca2004eb7ee1 docs/PHASE5_DESIGN.md \
>   6ad9e22a555729b238c942d6036e8d901dfe76071c78819bf8e3cbc1a972d801 docs/PHASE4_DESIGN.md \
>   90dc7842e286b2bbf556a02384096448694d4a698fd24f64a3cdc5ebd4fcb3d7 docs/PHASE3_DESIGN.md \
>   330c79f1905f51f2fd82413cd03cef68a336f630678d757143f8b524bbbc0e3c PromptSkills/README.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all five print `OK`. The PHASE4 hash is the planning-time value and Plan 017's
> Step 4 legitimately changes it (its §13-acceptance recording) — on a mismatch, diff the
> design: a Status-paragraph change alone is re-pinned here, not a stop; stop for
> reconciliation only when the readiness derivation, `ReadinessSnapshot`, or the deep-link
> route changed. `docs/OVERVIEW.md` is deliberately unpinned (Plan 020 edits its Stage 11
> line before this phase closes).
>
> **Live gates: none.** Nothing in this plan calls Codex.

## Status

- **Status**: DONE — all six contracts landed with their tests; no operation, exporter,
  UI, or AI surface exists (Plans 019–021 own those). The AGENTS.md drift-block pin was
  swept to `0081ad82…` (its post-planning one-line iteration-guidance addition, commit
  `5749d35`); the scene-scale attribute derivation records its self-citation reading in
  IMPLEMENTATION_NOTES
- **Priority**: P1
- **Effort**: M–L, approximately 7–9 focused engineering days
- **Risk**: MED; the migration is additive and follows the shipped v5 pattern, but this
  plan carries the phase's two structural hazards — the scene→requirements inversion is
  the first read of its kind (nothing scene-led exists, design §12), and the
  `SkillTreeOperations` move-down refactors a shipped, security-sensitive FilmBrain type
- **Depends on**: 013–016 (`DONE`), **017 (`DONE` required — `ReadinessSnapshot` is
  consumed, never re-derived)**
- **Category**: feature / storage / tests
- **Planned at**: commit `dce8971`, 2026-08-23; design hashes in the drift check

## Current state

- Bundle schema is 5 (`FilmCoreVersion.bundleSchema`, `ProjectMigrator.currentVersion`);
  the v6 pattern to copy is `SchemaV5.swift` + `registerV5` + `rebuildProjectsV5`
  (design §4, §12). Older SchemaVN files are never edited.
- **No scene-centric read exists.** Every shipped manifest read is requirement-led;
  the two SQL branches to invert live in `requiredByScenes(_:in:)`
  (`ProjectRepository+ManifestReads.swift`): canonical via
  `ManifestQualification.visibleRoleSQLList`, variant via `asset_requirement_scenes`
  (design §3.2, §12).
- `ReadinessSnapshot` ships with Plan 017; this plan reads it (design §3.3).
- `AssetPromptInputBuilder.plannedDependencies` and `build` are `internal` —
  `ScenePromptInputBuilder` lives beside them in FilmCore, no access widening
  (design §12). `ReferenceAttributeRules` is `public` and is the derivation authority.
- `PromptSkillMaterializer` lives in FilmBrain
  (`Prompting/PromptSkillMaterializer.swift`) with the tree-manifest walk, digest, and
  copy logic this plan moves down (design §3.7, §12); its staging machinery
  (cache layout, `clonefile`, prefix lengthening) stays.
- No style-bible, export, or profile concept exists anywhere in code (design §12).
- `ProjectObservationHub.areas` is the table→area map; `projects` sits in `.script`,
  asset prompt tables sit in `.assets` (design §7.5, §12).

## Owner gates (design §13/§14)

- **§14.2 (profiles: `seedance_2_5` + `generic`, one persisted project-wide active
  profile) — ACCEPTED 2026-08-23 as recommended.** This plan builds the catalog, the
  column, and the qualified derivation; confirm the design still reads that way before
  flipping the README row.
- **§14.6's storage half (`imported_skills`, `projects.scene_skill_id`,
  `SkillTreeOperations`) — ACCEPTED 2026-08-23 as recommended** (the fourth revision's
  atomic-verification clause included). The import *operations* are Plan 019's; this
  plan lands the table, the type, and the primitives.
- §13's deltas are accepted (2026-08-23, recorded in the design's Status paragraph);
  no separate acceptance blocks this plan.

## Contracts (normative)

### A. Bundle schema v6 and migration (design §4.2, §4.3)

- `SchemaV6.swift` + `registerV6` + `PRAGMA user_version = 6`;
  `FilmCoreVersion.bundleSchema = 6`; `projects` CHECK rebuilt via the v5 pattern.
- New tables exactly as §4.3 draws them: `scene_prompts` (with the
  `UNIQUE(scene_id, target_profile, prompt_number)` key, the `duration_seconds` /
  `aspect_ratio` / `resolution` settings columns, the skill triple, `input_digest`,
  `input_format_version`, the shared PROV block, and the `created_source = 'ai'` ⟺
  skill-triple CHECK), `scene_prompt_references` (immutable citations,
  `UNIQUE(prompt_id, position)`, `requirement_id`/`version_id` SET NULL), and
  `imported_skills` (bundle-relative `relative_root` under `skills/`, descriptor-relative
  entry/routing paths, `tree_sha256`).
- New `projects` columns: `style_bible TEXT NOT NULL DEFAULT ''`,
  `generation_target_profile TEXT NOT NULL DEFAULT 'seedance_2_5'`,
  `scene_skill_id` (nullable, referencing `imported_skills`).
- **Not changed** (design §4.3): `locks.subject_kind` stays at seven values;
  `asset_versions.media_kind` stays image-only; `jobs` gains no column.
- Migration is additive only: a v5 bundle opens, migrates, and every Phase 1–4 read
  returns byte-identical results before and after; newer-bundle refusal unchanged.

### B. Domain types and the target-profile catalog (design §3.5, §4.4)

- The §4.4 names, frozen: `ScenePrompt`, `ScenePromptReference`, `ScenePackageState`
  (raw values `needs_preparation` / `generation_ready` / `stale`), `TargetProfile`,
  `TargetProfileCatalog`, `ScenePlannedReference`, `ContinuityContext`,
  `ScenePackageSummary`, `ScenePackageDetail`, `ImportedSkill`, `SkillTreeOperations`,
  plus §8.2's builder family (contract E).
- The catalog ships two entries: `seedance_2_5` (30 images, 4–30 s, the seven aspect
  ratios, 480p/720p) and `generic` (same image limit, no enum constraints). The catalog
  is Film-Camp-authored; **the vendored `specs/model-specs.json` is never read by app
  code at runtime** — a test reads it and asserts agreement so drift fails a test
  (design §3.5, §10).
- The active profile is `projects.generation_target_profile`; an id the catalog no
  longer carries reads `needsPreparation` with the refusal naming the missing profile,
  never a crash (design §3.5).

### C. The derivations (design §3.2, §3.3, §3.4)

- **references(S)**: the two-branch inversion, thinned to active, non-rejected,
  `necessity = 'required'` rows, joined to approved versions; class and
  role/exclusion/fidelity from `ReferenceAttributeRules`; ordered by class rank →
  requirement name → id; dense `@Image N` designators over the approved subset only.
  Optional requirements are excluded from the plan, greyed in reads, never counted
  against the limit. Over the profile's limit refuses via
  `.sceneReferencesExceedProfileLimit(count:limit:)`, never truncates.
- **continuity(S)**: `entity_states` intervals covering S for entities appearing in S,
  ordered entity name → category → id; empty is a valid context.
- **Package states**, always against the active profile P (design §3.3's predicate
  verbatim): `generationReady(S)` := assetReady(S) ∧ currentPrompt(S, P) exists ∧
  ¬stale(currentPrompt(S, P)); staleness is the derived digest/format-version comparison
  (§3.4), never stored. `assetReady(S)` comes from `ReadinessSnapshot` — re-deriving it
  is a STOP.

### D. Reads and observation (design §7.5)

- `ProjectReading` gains `scenePackages()`, `scenePackageDetail(sceneID:)`,
  `scenePromptHistory(sceneID:targetProfile:)`, `styleBible()`.
- Observation, frozen: `scene_prompts`, `scene_prompt_references`, and
  `imported_skills` join **`.assets`** in `ProjectObservationHub.areas`; no new
  `ProjectChange` flag; `setStyleBible` arrives through `.script` because `projects`
  is a `.script` table. A test asserts the map entries and the §7.5 observed sets
  against the built hub.

### E. `ScenePromptInputBuilder` (design §8.2, FilmCore half)

- The full determinism contract, adopted from the shipped builders: Swift-side total
  ordering ending in ids, `sortedKeys`, no dictionaries, no clock/locale/floats/
  environment, `schemaVersion = 1` recorded per row as `input_format_version` and never
  re-stamped, **a committed golden fixture asserted byte for byte with its exact
  digest**. The §8.2 field list is the single normative digest input set; no field is
  optional; **scene body text is in the payload** (§14.4, accepted) via the stored
  UTF-16 slice; unsatisfied rows and derived attributes render on purpose.
- `ScenePromptInputBudget` (UTF-16, default 120 000, pinned here) refuses via
  `.scenePromptInputOverBudget(measured:limit:)`, never truncates.

### F. `SkillTreeOperations` — the boundary refactor (design §3.7, fourth revision)

- The pure primitives move down into FilmCore: the manifest walk (safe-relative-path
  validation by `RelativeProjectPath`'s rules, symlink refusal — refuse, never
  sanitise), the sorted-manifest tree digest, the contained tree copy through
  `BundleContainment`.
- FilmBrain's `PromptSkillMaterializer` consumes them for staging and keeps its
  staging machinery, **and gains the `expectedTreeSHA256` parameter**: for imported
  skills the exact staging manifest produces the actual digest, compared **before any
  copy or clone**, refusing via `treeDigestMismatch(expected:actual:)`. (The run
  coordinator that passes it is Plan 021's; the parameter and refusal ship now,
  exercised by unit tests.)
- **Behavior is byte-identical** for the existing asset-prompt staging path.
- Test suites split by layer (design §10): safe-path, symlink, manifest, full-digest,
  and copy fixtures move to FilmCore; the forced digest-prefix-collision and
  cache-directory-resolution fixtures stay in FilmBrain.

## Steps

1. **Schema v6 and migration.** Contract A complete, with the v5→v6 round-trip test
   (open, migrate, byte-identical Phase 1–4 reads, newer-bundle refusal) and CHECK
   assertions for every new constraint.
2. **Domain types and the profile catalog.** Contract B, including the
   vendored-snapshot agreement test (test-time read of
   `PromptSkills/higgsfield/specs/model-specs.json` only).
3. **`SkillTreeOperations` move-down.** Contract F. Run the full FilmBrain suite before
   and after; the staging path's behavior must not change. Record the refactor in
   `docs/IMPLEMENTATION_NOTES.md` (which files moved, which stayed).
4. **Derivations.** Contract C, with the §10 rows: plan ordering under shuffled
   insertion; dense designators; optional exclusion; limit and limit+1; continuity
   interval coverage; the package-state predicate at every boundary; the
   removed-catalog-id edge.
5. **Reads and observation.** Contract D, with the map/observed-set assertions.
6. **Input builder and golden fixture.** Contract E, with digest-stability tests, the
   one-flip-per-input-family battery (style bible included), and the format-version
   staleness read.
7. **Record-keeping.** Open the `docs/IMPLEMENTATION_NOTES.md` Phase 5 section that
   will hold the §10 acceptance record (design §13's gate edit); flip this plan's
   README row.

## Verification

- `./scripts/verify.sh` passes (UI phase: compare against the recorded environmental
  flake first — the Plans 012/015 posture).
- `./scripts/check-docs.sh` passes.
- The golden fixture's digest is committed and byte-asserted.

## Done criteria

- [ ] All six contracts land with their tests; no operation, exporter, UI, or AI
      surface exists.
- [ ] A v5 bundle migrates cleanly; Phase 1–4 reads are byte-identical.
- [ ] The FilmBrain staging path behaves identically before and after the refactor.
- [ ] The golden fixture and its digest are committed.
- [ ] §14.2 and §14.6 still read ACCEPTED in the design; the README row is flipped
      with any caveat recorded honestly.

## STOP conditions

1. The PHASE5 hash differs *and* §3.1–§3.5, §4, §7.5, or §8.2 changed.
2. `ReadinessSnapshot`'s shape cannot express `assetReady(S)` for this derivation —
   report; do not re-derive readiness here.
3. The materialiser refactor requires any behavior change on the shipped staging
   path — report; the design promises byte-identical behavior.
4. The golden fixture cannot be made byte-stable (an ordering or encoding gap in the
   determinism contract) — report the unstable field; do not loosen the assertion.
5. Work expands into operations, export, UI, the AI job, or anything Plan 019–021 owns.
6. A verification command fails twice after one reasonable scoped correction.

## Maintenance notes

- The catalog's Seedance entry mirrors the vendored snapshot of 2026-08-07; when the
  vendored tree is updated, the agreement test is the tripwire — update the catalog in
  the same change, and treat a widened enum as a validator concern (Plan 021), not a
  schema change.
- `ScenePromptInputBuilder.schemaVersion` bumps on any renderer change, including a
  `ReferenceAttributeRules` wording change; older rows read stale with the format
  reason, never migrated.
