# Plan 017: Scene readiness, the dashboard, and the deep link (Phase 4a)

> **Executor instructions**: Read `docs/PHASE4_DESIGN.md` in full first. This plan implements
> its §3.1–§3.5 and §3.8 (the derivation, the impact ranking, and the no-mutation posture),
> §4.4's 4a types, §5 (the Dashboard section, the scene surfaces, the deep link, the
> identifiers), §6 (the derived scene states and the gesture-consequence table as a test
> spec), and §7.5 (the reads and the pinned observation set) — **no AI anywhere in this
> plan**, and no migration: bundle schema stays 5, and the plan adds no `EditOperation`, no
> `SubjectKind`, and no table. It also carries the §13 gate-list debts assigned to the first
> Phase 4 plan: the deferred `Phase3WorkshopUITests` walk is written **first** (the Plan 015
> standing instruction — this plan touches the Manifest UI as a deep-link target), the
> in-file `## Status` blocks of Plans 013–015 are flipped to match the README, and delta 10's
> one-line OVERVIEW Stage 9 reconciliation lands with its full hash sweep, gated on §13's
> recorded acceptance. Follow the steps in order, run every verification command, honor every
> STOP condition. Requires Plan 015 `DONE`; **independent of Plan 016** (design §1.2 — no
> Phase 3b surface is consumed, and nothing here may assume the evidence-gated batch driver
> exists). When complete, set this plan's row in `docs/plans/README.md` per the Done
> criteria.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   6ad9e22a555729b238c942d6036e8d901dfe76071c78819bf8e3cbc1a972d801 docs/PHASE4_DESIGN.md \
>   90dc7842e286b2bbf556a02384096448694d4a698fd24f64a3cdc5ebd4fcb3d7 docs/PHASE3_DESIGN.md \
>   84c3599561dac60fd02d00d8a3d6a564558bac340fb5988d8bcc83868748ff68 docs/PHASE2_DESIGN.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all four print `OK`. If the PHASE4 hash differs, stop for reconciliation when
> §3.1–§3.5, §5, §6, or §7.5 changed; **§13 acceptance recorded in the Status paragraph
> alone is re-pinned, not a stop** — and Step 4 requires exactly that recording, so expect
> one legitimate re-pin during this plan's life. `docs/OVERVIEW.md` is **deliberately
> unpinned**: Step 4 edits it (delta 10), so no hash is stable across this plan.
> `docs/ROADMAP.md` is unpinned because this plan depends on the design's restatement of
> Phase 4, not on ROADMAP's own text.
>
> **Live gates: none.** Nothing in this plan calls Codex; the phase's only live surface is
> the rejected 4b plan's.

## Status

- **Status**: DONE — Steps 1–3 landed with every deterministic gate green and §14/§13
  accepted; delta 10 and its full hash sweep landed with the acceptance recording
  (2026-08-24). The clean `./scripts/verify.sh` UI leg remains under the recorded
  Plan 012/015 runner-wedge posture (see `docs/IMPLEMENTATION_NOTES.md`).
- **Priority**: P1
- **Effort**: L, approximately 7–9 focused engineering days
- **Risk**: LOW-MED; there is no migration and no mutation, but the derivation's edge-case
  matrix is wide (§3.4), the exhaustive §6.2 table test is the plan's largest single item,
  and the UI work lands under the recorded environmental UI-runner wedge with headless twins
  as the assertions of record
- **Depends on**: 015 (016 explicitly not required — design §1.2)
- **Category**: feature / reads / ui / tests
- **Planned at**: commit `416fe0f`, 2026-08-23; design hash in the drift check

## Current state

- Plans 013–015 shipped everything this plan stands on (verified at the design's base
  `1bbe7f2` and restated in design §12): the seven-rule `AssetStatusRecompute` (the only
  writer of `assets.status`), `manifestGraph(in:)` with the repaired
  `review_state <> 'rejected'` dependency load, `ManifestGraph.isActive` / `isMissing` /
  `isBlocked` / `isSatisfied(dependsOn:)` as Swift derivations, `missingAssets()` with the
  canonical-first dependency-rank sort, `manifestSummary()` / `ManifestCounts`, and
  `RequirementDetail` with both blocked reads.
- **The scene→requirements read does not exist** — every shipped manifest read is
  requirement-led. The forward SQL to invert is `requiredByScenes(_:in:)`
  (`ProjectRepository+ManifestReads.swift`): canonical via `scene_entities` on
  `ManifestQualification.visibleRoleSQLList` with the tombstone filter, variant via
  `asset_requirement_scenes` with the same filter.
  `index_asset_requirement_scenes_on_scene_id` already ships.
- `ProjectWindowModel.revealRequirement(id:)` ships and already performs the deep link's
  section-plus-selection navigation; `RevealTarget` has `scene`/`entity` cases and no
  `requirement` case. `ProjectSection` is a ten-case enum with `groups` driving the sidebar
  and a per-section `selection` map. `SceneTableView` has no readiness column;
  `SceneDetailView` has no requirement panel.
- `scenes.is_omitted` is parser-set with one badge as its only consumer; ordinal 0 is the
  preamble. Neither has ever entered a count — §3.4's exclusions are new rules, not
  inherited ones.
- The `ProjectObservationHub` table→area map covers every input table; the pinned
  observation set is design §7.5's `[.scenes, .entities, .requirements, .assets]`.
- Record-keeping debts standing at planning time: Plans 013–015's in-file `## Status`
  blocks still read `TODO` against README `DONE` rows, and `Phase3WorkshopUITests` is
  deferred with the environmental-wedge posture recorded (`docs/IMPLEMENTATION_NOTES.md`,
  Plan 015 section).

## Owner gates (design §13/§14)

- **§14.1, §14.2, §14.4, §14.5 — DECIDED 2026-08-23, accepted as recommended** (recorded in
  design §14, §14.1 with the sole-unsatisfied correction applied): the dependency reading of
  scene Blocked, the omitted/preamble counter exclusion, the `.dashboard` section, and
  optional rows shown-never-counted. This plan implements all four; confirm the design still
  reads that way before flipping the README row.
- **§13's deltas await formal acceptance at planning time.** Step 4 (the OVERVIEW Stage 9
  edit, delta 10) **requires** that acceptance recorded in the design's Status paragraph
  before it runs, and the Done criteria gate the README `DONE` flip on the same recording —
  the Phase 3 rule ("a plan does not pass its implementation gate until the decisions it
  implements are accepted"), applied to the delta set this plan builds (deltas 1–5, 7,
  10–12).

## Contracts (normative)

### A. The derivation and the reads (design §3.2–§3.4, §7.5)

- An internal `readinessGraph(in:)` builds on the shipped `manifestGraph(in:)` plus two
  scene-side loads: the current script's `scenes` rows, and the (sceneID, requirementID)
  link pairs — canonical via `scene_entities` restricted to
  `ManifestQualification.visibleRoleSQLList` with `review_state <> 'rejected'`, variant via
  `asset_requirement_scenes` with the same filter — **reusing the shipped predicates by
  name, never re-spelling the role list or the tombstone filter**. One load, one read
  transaction, everything §5 shows derived from it.
- The predicates, §3.3 verbatim: counted(S) = linked, active, `required`; ready =
  `displayStatus == .approved`; **Asset Ready** = missing empty; **Blocked** = ∃ missing
  member with `graph.isBlocked` (the **Missing-qualified** predicate — never
  `isGenerationBlocked`, the trap §3.3's table names); **Partial** otherwise. §3.4's rules
  each hold: optional shown-never-counted; proposed counted with `hasUnreviewedFacts`
  propagated to the scene row and the summary; zero-requirement scenes Asset Ready at a
  visible `0 / 0`; omitted and preamble rows excluded from the counters into a separate
  `excluded` figure while still listed (and still showing any checklist rows they have);
  `manifest_inclusion = 'never'` never excluding; entity-level inactivity excluding through
  the predicate at read time.
- `ProjectReading` gains **`readinessSnapshot() -> ReadinessSnapshot`** (§4.4's types
  verbatim): `SceneReadiness`; `SceneMissingRequirement` — the `MissingAsset` shape at
  scene scope **with `blockedBy: [RequirementReference]`, not bare UUIDs** (owner-review
  finding, 2026-08-23): the snapshot is the UI's only source, so §5.2's blocked badge must
  name its first entry with no per-row query — `RequirementReference` carries
  `requirementID`/`entityName`/`requirementName`, and the list is **ordered by the
  dependency edge's `created_at` then edge id** (the Phase 3 §3.3 key, reused), total and
  stable; `SceneOptionalRequirement` with its §4.4-frozen fields (`requirementID`,
  `entityName`, `requirementName`, `tier`, `displayStatus`, `hasUnreviewedFacts` — enough
  to render and deep-link the greyed row without a second query); `ReadinessSummary`;
  `UnblockerImpact`; `SceneReadinessState` with raw values
  `blocked`/`partial`/`asset_ready`, derived only, never stored. **The fold identity is an
  invariant**: the summary is a fold of the per-scene rows,
  `assetReady + partial + blocked + excluded == scenes.count`, asserted on every fixture
  state.
- The readiness surfaces observe **`[.scenes, .entities, .requirements, .assets]`** — the
  design-pinned set (§7.5, verified against the built map; `.entities` is load-bearing
  three ways and its omission was an owner-review finding). No new hub entry exists to add.

### B. The impact ranking (design §3.5 — the owner-corrected metric, verbatim)

- Per Missing requirement M: `unfinishedScenes(M)` = M's own linked scenes that are neither
  Asset Ready nor excluded; **`unblocks(M)` = Missing dependents whose unsatisfied set is
  exactly `{M}`** — the sole-unsatisfied rule, owner-decided 2026-08-23; a dependent waiting
  on two blockers counts for neither and appears in **no impact figure** until one blocker
  remains (a blocker's scene reach covers its *own* linked scenes, never its dependents' —
  the corrected explanation, stated in code comments where the figures are computed).
- **The five-key order, owner-specified**: `unfinishedSceneCount` descending,
  `unblocksRequirementCount` descending, canonical tier first, the shipped dependency rank,
  requirement id — total and stable.
- §3.5's three stated bounds ship as dashboard help text, not discoveries: per-asset
  figures (no set-cover), advances ≠ completes, multi-blocked dependents count for no
  single blocker.

### C. The Dashboard section and the scene surfaces (design §5.1–§5.3, §6.1)

- `ProjectSection` gains `.dashboard`, first sidebar group; the full enum ripple lands as
  §5.1 enumerates it (title "Dashboard", `systemImage`, empty-state copy,
  `supportsSearch = false`, no `entityKind`, `section_dashboard`, a selection-map entry).
  No other section moves.
- The dashboard renders §5.3's panels 1–3 in order — scenes (three pinned states + the
  small `excluded` figure + the project-level unreviewed badge, each state click presetting
  a Scenes-section readiness filter, a view-model filter in the shipped
  `ManifestScopeFilter` style), Top Unblockers (head of the contract-B ranking, full list
  one disclosure away), and the assets line (**Approved / all active requirements** — the
  `ManifestCounts` frame, definition stated on the surface, `manifestSummary()`'s numbers
  reused unchanged). **Panel 4 (Suggestions) belonged to the rejected 4b plan and does not render** —
  the section ships without it, hidden-not-broken. No Generation Packages row renders
  (Phase 5; design §5.3).
- `SceneTableView` gains the Readiness column (state + `readyCount / requiredCount`, the
  `0 / 0` form verbatim, Omitted/Preamble labels in place of a state on excluded rows, the
  unreviewed badge); `SceneDetailView` gains the Required Assets panel (checklist rows in
  the contract-B order restricted to the scene, ✓/status, the entity — requirement display
  convention, the requirement-Blocked badge naming the first `blockedBy` entry's display
  name, optional rows greyed below). Both read the one snapshot from the window model's
  refresh beat; no view-side derivation (`AGENTS.md`).
- §5.6's identifier list ships verbatim (minus the four Suggestions identifiers of the rejected 4b plan),
  every named container with `.accessibilityElement(children: .contain)`.

### D. The deep link (design §5.4)

- `RevealTarget` gains `case requirement(id: UUID)`; `ProjectWindowModel.reveal(_:)` routes
  it to the shipped `revealRequirement(id:)` — no new navigation machinery. Call sites: the
  scene checklist rows, the Top Unblocker rows, and the dashboard drill-downs. The reverse
  leg (workshop Used In → scene) already ships and is untouched.

### E. Record-keeping, the OVERVIEW reconciliation, and the gates (design §13's gate list)

- **`Phase3WorkshopUITests` is written first** (Step 1) — the Plan 015 standing instruction
  lands on this plan by name; a failure there is compared against the recorded
  environmental wedge before any code is blamed. This plan's deep-link UI walk then extends
  that suite rather than starting a parallel one.
- Plans 013–015's in-file `## Status` blocks flip to match the README (016's flips when 016
  lands — not this plan's row to touch).
- **Delta 10** (OVERVIEW Stage 9's film-level "Partially Ready" → the pinned `Partial`) is
  a one-line edit landing **only after §13's acceptance is recorded** in the design's
  Status paragraph, and **in the same commit as the full hash sweep**: every gate-checked
  drift block pinning `docs/OVERVIEW.md` (Plans 002–009, 011, 013, 014) plus Plan 001's
  hand-maintained copy. `scripts/check-docs.sh` check 5 is the enforcement.
- The `PHASE4` glob, the `ALLDOCS` addition, and the README rows landed with the planning
  commit that created this file; this plan does not re-edit them except as the Done
  criteria require (its own row's status).

## Target file layout (additions, changes)

```text
Packages/FilmCore/
  Domain/SceneReadiness.swift (new — SceneReadinessState, SceneReadiness,
    SceneMissingRequirement, SceneOptionalRequirement, ReadinessSummary,
    UnblockerImpact, ReadinessSnapshot)
  Storage/ProjectRepository+ReadinessReads.swift (new — readinessGraph(in:),
    readinessSnapshot(), the contract-B figures and ordering)
  ProjectTools.swift (+readinessSnapshot() on ProjectReading)
  Tests/ SceneReadinessDerivationTests (the §6.2 exhaustive table + §3.4 matrix +
    the fold identity), ReadinessImpactTests (the M₁/M₂ regression fixture and the
    five-key order), ReadinessConsistencyTests (byte-equality with manifestSummary)
AI Film Camp/
  App/ProjectWindowModel.swift (+.dashboard case and ripple; snapshot on the refresh
    beat; observation set per contract A), App/ProjectWindowModel+Readiness.swift (new),
  Support/RevealTarget.swift (+case requirement(id:)),
  Views/Dashboard/DashboardView.swift (new; panels 1–3),
  Views/Scenes/SceneTableView.swift (+Readiness column),
  Views/Scenes/SceneDetailView.swift (+Required Assets panel),
  UITests/Phase3WorkshopUITests.swift (new — the carried debt, written first),
  UITests/Phase4ReadinessUITests.swift (new)
docs/OVERVIEW.md (Step 4 — the delta 10 one-liner), docs/plans/00*/01* drift blocks
  (Step 4 — the OVERVIEW sweep), docs/plans/013|014|015 `## Status` blocks (Step 1),
  docs/IMPLEMENTATION_NOTES.md (Plan 017 section)
```

`scripts/eval-inputs.txt` is untouched, and no file it lists is edited by this plan
(design §10 — nothing here changes the extraction score).

## Steps

### Step 1: The carried debts

Write `Phase3WorkshopUITests` (the deferred Plan 015 walk, per its recorded outline) and
run it once, comparing any failure against the recorded environmental wedge; flip
Plans 013–015's in-file `## Status` blocks; open the Plan 017 implementation-notes section.

```bash
grep -n '^- \*\*Status\*\*' docs/plans/013-*.md docs/plans/014-*.md docs/plans/015-*.md
./scripts/check-docs.sh
```

Expected: the three status lines read `DONE`, matching the README; check-docs green; the
UI walk's outcome (pass, or environmental failure with the wedge comparison) recorded in
`docs/IMPLEMENTATION_NOTES.md` before any Phase 4 code exists.

### Step 2: The derivation, the reads, the ranking

Contracts A and B.

```bash
swift test --package-path Packages/FilmCore
```

Expected: the §6.2 gesture table exhaustively driven through the real operations with the
derived state re-read after each (including undo legs); every §3.4 rule asserted both ways
(the design §10 derivation bullet is the checklist — tombstones from the scene side,
optional at both tiers, proposed with the flag lifecycle, `0 / 0`, excluded-with-links,
never-does-not-exclude, satisfied-when-inactive reaching the scene state); the fold
identity on every fixture state; the **M₁/M₂ two-blocker fixture** with both transition
assertions; the five-key order exercised on every key including the
seven-scene/ten-unblocks vs eight-scene/zero-unblocks pair; `blockedBy` rows carrying
resolvable display names in the pinned edge order (a renamed blocker shows its current
name on the next snapshot — derived, never cached); the optional rows carrying every
frozen field; snapshot asset figures byte-equal `manifestSummary()`; the shipped-read pin
tests unchanged.

### Step 3: The Dashboard section, the scene surfaces, the deep link

Contracts C and D, headless twins for every assertion, the UI walk extending Step 1's
suite.

```bash
./scripts/verify.sh
```

Expected: all suites exit 0 (headless twins are the assertions of record under the
documented UI flake); the deep-link twin asserts section, selection, and loaded detail
from all three call-site families; the dashboard twins assert counts, badges, filter
navigation, `0 / 0`, excluded labels, and the three help-text bounds present; no
Suggestions panel and no Generation Packages row anywhere.

### Step 4: The OVERVIEW reconciliation (gated on §13 acceptance)

Confirm §13's acceptance is recorded in `docs/PHASE4_DESIGN.md`'s Status paragraph; then
land the delta 10 one-liner and the full OVERVIEW hash sweep in one commit; re-pin this
plan's PHASE4 hash for the Status-paragraph change.

```bash
grep -n 'Partially Ready' docs/OVERVIEW.md
./scripts/check-docs.sh
```

Expected: no match (the mockup line now reads `Partial`); check-docs green — check 5
proves every pinned OVERVIEW copy moved together, including Plan 001's hand-maintained
block (verify it by eye; no gate covers it). If §13's acceptance is not yet recorded,
**stop at this step** and complete it later — Steps 1–3 stand, but the README row does
not flip `DONE` (Done criteria).

## Done criteria

- [ ] `./scripts/verify.sh` exits 0; the derivation, ranking, reads, dashboard, scene
  surfaces, and deep link implement contracts A–D as written, with the §6.2 table test,
  the §3.4 matrix, the fold identity, and the M₁/M₂ regression fixture all present and
  green.
- [ ] No migration, no `EditOperation`, no `SubjectKind`, no new table, no new hub entry
  anywhere in the diff; `git diff` shows no change under `Packages/FilmCore/Sources/
  FilmCore/Storage/SchemaV*.swift` or `Editing/` operation files.
- [ ] The window model observes exactly `[.scenes, .entities, .requirements, .assets]`
  for the readiness surfaces, test-asserted.
- [ ] Step 1's debts are done: `Phase3WorkshopUITests` exists with its outcome recorded,
  and Plans 013–015's in-file status blocks match the README.
- [ ] Delta 10's OVERVIEW edit and full sweep landed (Step 4), **and §13's acceptance is
  recorded in the design's Status paragraph** — the deltas this plan implements (1–5, 7,
  10–12) are accepted before this row flips `DONE`; §14's four relevant decisions
  (§14.1/§14.2/§14.4/§14.5) still read accepted-as-recommended in design §14.
- [ ] `docs/plans/README.md` marks Plan 017 accordingly, and the Plan 017
  implementation-notes section records the Step 1 UI-walk outcome and any deviations.

## STOP conditions

- The `docs/PHASE4_DESIGN.md` hash differs and §3.1–§3.5, §5, §6, or §7.5 changed (a
  Status-paragraph-only change recording §13 acceptance is a re-pin, not a stop).
- Any step appears to need a stored readiness column, a new mutation, a migration, or a
  `ProjectObservationHub` entry — each is a design divergence (§3.1, §3.8); report, do not
  build it.
- The scene-side derivation cannot reuse the shipped predicates by name (the visible-role
  list, the tombstone filters, `isBlocked`) and a re-spelling appears necessary — report
  the mismatch; a second spelling is the defect class the design exists to prevent.
- `readinessSnapshot()` proves measurably too slow on a feature-scale project during
  Step 3 — stop and report with numbers; the derived-only posture is §14-adjacent and a
  cache is an owner conversation, not an implementation detail.
- Step 4 is reached and §13's acceptance is not recorded — complete Steps 1–3, record the
  deferral, and leave the row un-flipped rather than editing OVERVIEW under an unaccepted
  delta.
- A verification command fails twice after one reasonable scoped correction (UI suites:
  compare against the recorded environmental flake first).
- Work expands into the Suggestions panel, any Codex call, generation packages, batch
  prompt generation, or an apply-suggestion mutation (the rejected 4b plan, Phase 5, and Phase 6
  territory; design §11).

## Maintenance notes

- The one derivation function and the fold identity are the contract's heart: any future
  surface (Phase 5's package worklist included) reads `ReadinessSnapshot`, never a second
  query — the §3.3 consistency rule outlives this plan.
- `SceneReadinessState`'s raw values are frozen strings (design §4.4); the rejected 4b plan would have rendered its
  input and any Phase 5 record cite them, so a rename is a design change.
- If real-scale performance ever motivates caching the snapshot, the derivation stays
  normative and the cache is an optimization with an owner decision behind it (§11).
