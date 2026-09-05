# Plan 020: The Generation section (Phase 5a)

> **Executor instructions**: Read `docs/PHASE5_DESIGN.md` in full first. This plan
> implements its §5 (the `.generation` section, the scene list, the package view, the
> deep links, the enablement/refusal table, the accessibility identifiers with mandatory
> headless twins), §6.1 (the package states rendered in OVERVIEW's pinned vocabulary,
> including the Dashboard's Generation Packages block that Phase 4 left deliberately
> absent), the §14.6 chooser surface (calling Plan 019's ops), and §13 delta 8 (the
> one-line OVERVIEW Stage 11 wording edit with its **full pinned-hash sweep**). **After
> this plan, Phase 5a is complete**: a filmmaker reaches Generation Ready and exports a
> package with no model in the loop. Generate/Regenerate do **not** render — they are
> Plan 021's. **The carried workshop suite binds here**:
> `Phase3WorkshopUITests` is written by Plan 017 (which carries the Plan
> 015 debt) and exists by the time this plan starts; verify it, run it
> before any Generation-section UI work, and treat a failure as plausibly
> environmental (the recorded runner-wedge posture,
> `docs/IMPLEMENTATION_NOTES.md`). Follow the steps in order, run every verification
> command, honor every STOP condition. Requires Plan 019 `DONE`. When complete, set this
> plan's row in `docs/plans/README.md` per the Done criteria.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   bd477ef76dbb98c2f7dbffdae5310b8f824e309e904bcd91f03cca2004eb7ee1 docs/PHASE5_DESIGN.md \
>   6ad9e22a555729b238c942d6036e8d901dfe76071c78819bf8e3cbc1a972d801 docs/PHASE4_DESIGN.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all three print `OK`. The PHASE4 hash changes legitimately at Plan 017's
> Step 4 (re-pin on a Status-only diff; stop only if `RevealTarget` or the Dashboard
> section contract changed). `docs/OVERVIEW.md` is deliberately unpinned — **this plan
> edits it** (Step 4) and sweeps every pinned copy.
>
> **Live gates: none.** Nothing in this plan calls Codex.

## Status

- **Status**: DONE — every contract landed (section, package view, Dashboard block,
  delta-8 OVERVIEW edit with its full hash sweep) with every deterministic gate green;
  `Phase3WorkshopUITests` was verified present and observed passing in this session's
  first full run. The clean `verify.sh` UI leg — the new walk's pass and one rerun of
  Phase 4's drill-down case — remains under the recorded runner-wedge posture
  (`docs/IMPLEMENTATION_NOTES.md`); the headless twins carry the assertions of record.
- **Priority**: P1
- **Effort**: M–L, approximately 6–8 focused engineering days
- **Risk**: MED; the section is the shipped master–detail shape over Plan 018's reads
  and Plan 019's operations, but it lands the phase's whole UI contract and the
  cross-repo hash sweep, and the UI-walk environment is the known flake surface
- **Depends on**: 019 (and, for the Dashboard block and deep-link reuse, 017 `DONE` —
  already required transitively)
- **Category**: feature / ui / docs / tests
- **Planned at**: commit `dce8971`, 2026-08-23; design hashes in the drift check

## Current state

- Plans 018–019 ship the model, derivations, reads, operations, and exporter; nothing
  renders them.
- The shell is the shipped two-column window; Phase 4 (Plan 017) adds `.dashboard` to
  `ProjectSection` and the `RevealTarget.requirement` deep link this plan reuses.
- Phase 4 §5.3 left the Dashboard's Generation Packages block deliberately absent —
  "wait for Phase 5 rather than rendering empty." This plan renders it.
- `Phase3WorkshopUITests` is written by Plan 017, which carries the standing Plan 015
  debt — and 020 depends on 019 → 018 → 017, so the suite exists before this plan
  starts. This plan verifies and runs it; it does not write it.

## Owner gates (design §13/§14)

- **§14.2's picker** (project-wide active profile), **§14.6's chooser surface**, and
  **§14.7's stale-export confirm** — all ACCEPTED 2026-08-23 as recommended; this plan
  renders them over Plan 019's operations.
- **§13 delta 8** (OVERVIEW Stage 11 wording) is accepted; Step 4 performs the edit and
  the sweep. §13's acceptance is already recorded in the design's Status paragraph, so
  no further owner action gates this plan.

## Contracts (normative)

### A. The section (design §5.1, §5.3, §5.4)

- `.generation` joins `ProjectSection`; the enumerated ripple (sidebar, split-view
  switch, window-restoration coding, section-picker identifiers) is handled in one
  step, no arm discovered later.
- The list: scenes in ordinal order, package-state badges, state filter, counts
  naming the active profile (`Seedance 2.5 — N generation ready · M stale · K needs
  preparation`), byte-consistent with the Dashboard's figures. Excluded scenes render
  under their existing labels with no package state.
- Toolbar: Export All Generation Ready; Export Sequence with a sequence selected.
- Deep links both ways: scene surfaces → package view (the new route case beside the
  shipped one); unsatisfied reference rows → Asset Workshop via
  `RevealTarget.requirement`, reused not re-minted.

### B. The package view (design §5.2)

- Header with **both axes visibly distinct** — the package-state badge beside the
  Asset Ready state; never one collapsed badge (§3.3's rule; §10 asserts the copy).
- The profile picker performs `setGenerationTargetProfile` project-wide.
- The reference plan in §3.2 order — designator, thumbnail, name, class,
  satisfied/unsatisfied; optional rows greyed, tagged `optional`, un-designated;
  over-limit shows the §3.2 refusal inline.
- The continuity context, read-only. The prompt panel: current body, history,
  hand-authoring via `createScenePrompt`, editing via `setScenePromptBody`,
  delete-newest restore. Staleness badge with reason, informative never blocking.
- Actions: Copy Prompt (byte-exact), Reveal References, Export Scene Package, and the
  §14.6 chooser (import/select, calling Plan 019's ops). **No Generate/Regenerate.**

### C. Enablement, refusal, and identifiers (design §5.5, §5.6)

- The §5.5 table verbatim; refusal copy is FilmCore's strings verbatim, never a
  paraphrase; the §14.7 stale-export confirm names the stale reason.
- The §5.6 identifier list is the compile-target of the UI tests; `generation.package
  .generate` / `.regenerate` are reserved but not rendered (Plan 021 activates them).
- **Headless twins are mandatory** and carry the assertions of record.

### D. Dashboard block and OVERVIEW edit (design §6.1, §13 delta 8)

- The Dashboard's Generation Packages rows render from the same `scenePackages()`
  read: the three counts under the active profile, linking into the section.
- OVERVIEW Stage 11's sketch wording reconciles to the pinned vocabulary
  (`GENERATION READY` → `Generation Ready`), **one line** — and the sweep updates
  **every pinned OVERVIEW hash in the same commit**: Plans 001 (by hand), 002–009,
  011, 013, 014, and any Phase 5 plan that pins it by then. `check-docs.sh` check 5
  is the enforcement; it exits 0 in the same commit as the edit.

## Steps

1. **The carried workshop suite.** Verify `Phase3WorkshopUITests` exists (Plan 017's
   carried debt — its absence is a STOP, not a cue to write it here); run it before
   modifying the shell; compare any failure against the recorded environmental
   baseline; extend it only if Generation navigation changes a path it covers. Record
   the outcome in `docs/IMPLEMENTATION_NOTES.md`. Only then touch the shell.
2. **The section.** Contract A with headless twins for list, counts, filter, and both
   deep-link directions.
3. **The package view.** Contracts B and C: the full view, the enablement table walked
   headlessly, refusal copy asserted verbatim, the chooser flow against a fixture
   skill tree.
4. **Dashboard block and the OVERVIEW edit.** Contract D: render the block; make the
   one-line Stage 11 edit; sweep every pinned hash; `check-docs.sh` green in that
   commit.
5. **The UI walk.** The end-to-end 5a walk on a fixture project: import → readiness →
   hand-written prompt → Generation Ready → export; compare failures against the
   recorded environmental baseline before blaming code.
6. **Record-keeping.** Flip the README row; update the in-file `## Status`.

## Verification

- `./scripts/verify.sh` passes (environmental-flake posture; headless twins are the
  assertions of record).
- `./scripts/check-docs.sh` passes, including in the Step 4 sweep commit.

## Done criteria

- [ ] Phase 5a is usable end to end with no AI: hand-written prompt → Generation
      Ready → byte-exact export, walked in Step 5.
- [ ] Every §5.6 identifier exists with its headless twin; Generate/Regenerate are
      absent.
- [ ] Asset Ready and Generation Ready render as visibly distinct states everywhere
      both appear.
- [ ] OVERVIEW Stage 11 reads the pinned vocabulary and every pinning plan's hash is
      updated in the same commit.
- [ ] `Phase3WorkshopUITests` was verified present, run, and its outcome recorded
      (extended only if Generation navigation changed a covered path).
- [ ] The README row is flipped.

## STOP conditions

1. The PHASE5 hash differs *and* §5, §6.1, or §13 delta 8 changed.
2. `Phase3WorkshopUITests` is missing at start — Plan 017's Done criteria were not
   met; reconcile that plan's record rather than writing the suite here.
3. `RevealTarget.requirement` (Plan 017's route) proves insufficient for the reference
   rows — report; do not mint a parallel routing path.
4. The Dashboard figures and the section's counts cannot be made byte-consistent from
   one read — report; two derivations is a design violation (§3.3).
5. Work expands into Generate/Regenerate, run UI, batch generation, or a provider.
6. A UI suite fails twice with the recorded baseline ruling out the environment.

## Maintenance notes

- The reserved `.generate`/`.regenerate` identifiers keep Plan 021's diff to the
  wiring alone; do not repurpose them.
- The section deliberately owns no readiness rendering beyond the Asset Ready badge;
  readiness explanation lives in Plan 017's surfaces — link, don't duplicate.
