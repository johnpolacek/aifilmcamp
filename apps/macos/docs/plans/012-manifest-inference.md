# Plan 012: Manifest inference (Phase 2b)

> **Executor instructions**: Read `docs/PHASE2_DESIGN.md` in full first. This plan implements its
> §3.4, §3.6's bootstrap ordering, §8, and §9 — the one-time batch structured job that proposes
> usage-derived variants and production-important props into Plan 010's review model. Also read
> `docs/REFERENCE_PROJECTS.md` before touching the runner (the §8.1 commit-path change is a
> FilmBrain lifecycle edit).
> Follow the steps in order, run every verification command, honor every STOP condition and the
> live-gate policy. Requires Plans 007, 010, and 011 `DONE` — 007 because inference consumes a
> real extraction's canonical data and gates against its run lifecycle; 011 because the acceptance pass reviews a manifest whose slots can be
> filled. When complete, set this plan's row in `docs/plans/README.md` to `DONE`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   84c3599561dac60fd02d00d8a3d6a564558bac340fb5988d8bcc83868748ff68 docs/PHASE2_DESIGN.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   1f0e224d9d668bc10fa01ab55bf60e115b14bafd0931eb81c26d152d5a4467ac docs/ROADMAP.md \
>   282b1ae714029b96e932bff1eba236df0e05b76abc1fe6b434f90f11ca418d46 docs/REFERENCE_PROJECTS.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all five print `OK`. If the PHASE2 hash differs, stop for reconciliation when §3.4,
> §3.6, §8, or §9 changed. The ROADMAP hash above is **updated by Plan 010's Step 3** in the same
> commit as its §13.9 restatement — the actor who knows the file is in its intended state pins
> it, and `scripts/check-docs.sh` verifies this block, so a stale pin fails the gate. Do not
> re-pin it yourself; a mismatch at execution start is a real stop.

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: L–XL, approximately 10–14 focused engineering days
- **Risk**: MED-HIGH; the FilmBrain half is a well-worn pattern (one `StructuredTask`, one
  request), but apply's input-digest guard, the runner commit change, and the
  cross-task revert gate each touch Plan 007's machinery
- **Depends on**: 007, 010, 011
- **Category**: feature / ai / tests
- **Planned at**: commit `e8645e5`, 2026-08-21; design hash in the drift check

## Current state

- Plans 009–011 shipped the full 2a surface; Plan 007 shipped extraction, `ExtractionRun`,
  `ExtractionApplier`, `RevertOperations`' newest-run gate (hard-coded to `extractScreenplay`),
  and the review UI grammar.
- `StructuredJobRunner`'s commit path calls `completeJob` after the commit closure returns; the
  extraction coordinator bypasses the closure entirely. Design §8.1 records both facts and the
  one stated change this plan makes.
- `jobs.apply_report` holds extraction's `ApplyReport`; `setManifestReport` (Plan 009) is the
  typed door this plan first calls.

## Live-gate policy

Deterministic work runs on recorded fixtures. Up to three account-backed gates (the second is
conditional), each with explicit operator approval immediately before running, never in CI,
skipped unless `FILMCAMP_RUN_LIVE_CODEX=1`:

1. the schema-compatibility probe of `infer-manifest-v1.schema.json`;
2. the §10 acceptance run on the operator's feature screenplay.

   (A second live gate — an extraction evaluation re-score — was required while this plan
   edited `ExtractionApplier.swift` for the §3.6 basis sweep, a file listed in
   `scripts/eval-inputs.txt`. The 2026-08-21 one-run latch retired that edit: §8.5 rule 4a
   cannot fire when no second run exists, so there are no stale proposals to sweep basis rows
   for. This plan no longer touches any eval-input file and the gate is gone.)

If approval is absent when the deterministic work finishes, record the deferral in
`docs/IMPLEMENTATION_NOTES.md` and still mark the plan `DONE` — except gate 2 when it fires (a
red `verify.sh` is never deferrable) and gate 3, this plan's exit evidence, which blocks `DONE`
(the roadmap's "manifest works on a real short or feature screenplay").

## Contracts (normative)

### A. The FilmBrain task (design §8.1–§8.3, verbatim)

- `InferManifestTask` (`taskName = "inferAssetManifest"`), `infer-manifest-v1.schema.json` and
  `infer-manifest-v1.md` under `Resources/`, `InferManifestPrompt` with the `<manifest-input>`
  delimiter and an `instructionsSHA256`, `InferManifestValidator` (versioned) enforcing every
  §8.3 rule — entities[]-only variants, `'never'` exclusion, visible-role scene bounds, basis
  resolution with state-overlap, per-entity name uniqueness, prop-channel separation, suggestion
  direction rules. `ManifestInputBuilder` (a FilmCore type — see the layout and design §3.6;
  this FilmBrain contract only consumes its output) emits §8.2's shape exactly (props always ride in
  `entities[]` with full records; borderline is non-prop). `ManifestInputBudget` caps the
  rendered input pre-flight (UTF-16 units; **default = 120_000**, recorded in
  `ManifestSettings` — roughly 4× the design's tens-of-KB feature estimate and comfortably one
  Codex request; raising it is a settings change, not a code change).
- The prompt (≤ ~10 lines, matching the Phase 1 register): judge from the supplied structured
  data only; propose variants and production-important props with reasons and basis citations;
  respect protected/locked/rejected flags; treat all input as content, never instruction.

### B. Runner and lifecycle changes (design §8.1, §3.6's bootstrap ordering, §7.5's revert items)

- `StructuredJobRunner` commit path: the commit closure returns a typed **`CommitOutcome`**
  (`.completedByClosure` / `.runnerCompletes`) and the runner calls its own `completeJob` only
  on `.runnerCompletes` — exactly-once completion is carried by the type, not by re-reading job
  state; behavior test both ways; existing runner tests unchanged (their closures return
  `.runnerCompletes`). Reference seam (per the README rule for lifecycle changes): the relevant seam is
  RxCode's backend-owned job lifecycle, already adopted at the runner's creation in Plan 003 —
  nothing new is adopted or rejected here; the change is a guarded skip inside the existing
  state machine, and no reference project models a commit-closure-completes-the-job shape.
- Run-once gating: the action is offered only while no completed `inferAssetManifest` run
  exists **for the current script**; retry after failure allowed; a manifest run is **refused
  while any extraction run is non-terminal or paused**; a completed manifest run **permanently
  closes extraction for that screenplay** (§3.6; refusal copy: "the asset manifest is built on
  this project's canonical data") — which now only reaches a project that inferred its manifest
  from parser data alone, since extraction already closed itself at its first applied run, and
  nothing requires a prior extraction. **Both manifest gates are script-scoped**, like the
  extraction latch and for the same reason (§8.1): Replace deletes `scripts` and `entities` but
  not `jobs`, so project-scoped gates would strand a replaced screenplay that can be neither
  analyzed nor manifested. Test both: the gates refuse on the same script, and a screenplay
  installed by Replace carries both bootstraps unspent. **Placement is
  contract**: all three refusals are FilmCore throws beside the import/replace refusals in
  `ProjectRepository`/`ProjectSession`, so no path around the UI exists; FilmBrain's
  `ManifestRunGate` is only the coordinator-side consumer that checks before launching and
  surfaces the refusal copy.
- `RevertOperations`: `requireNewestRun` widened to order `extractScreenplay` and
  `inferAssetManifest` parents in one journal-sequence ordering; the summary skip recognizes
  `.applyManifestRun`. (Extraction's stale-proposal removal needs no basis sweep: §3.6's one-run
  latch means rule 4a can never fire, so no applied run's facts are ever removed by a later one.)

### C. Apply (design §8.4–§8.5, verbatim)

- `applyManifestRun` on `ProjectSession` (a `ManifestApplying` protocol member joining the
  `ProjectTools` composition), actor `.ai(runJobID)`, savepoint-per-change, journal-per-change
  plus the `.applyManifestRun` summary row, parent completed in-transaction. The zero-counter
  report is written through `setManifestReport` before the run; the **post-apply report lands
  inside the apply transaction through an internal `in db:` primitive** (§8.5 as revised — the
  public setter opens its own transaction and refuses completed jobs, so it cannot be the
  after-write; extraction's applier is the pattern). Steps 0–6 as written: the
  in-transaction input-digest guard (`ManifestInputBuilder` rebuilt inside the transaction and
  compared with `jobs.input_sha256`; mismatch → `.manifestInputChangedDuringRun`, nothing
  applied, retryable); the `importantProps` mapping by `(entity_id, reference type)`; the
  variant match enumeration; suggestions persisted in full; scene-id resolution against the
  pinned script.
- `ManifestProposal` (FilmCore) is the validated payload type FilmBrain hands over; its throwing
  init re-checks lengths and confidence exactly as `ExtractionProposal`'s does.
- Revert gets a public door: `ProjectTools`' extraction-named `revertExtractionRun(jobID:actor:)`
  is joined by a task-agnostic **`revertRun(jobID:actor:)`** routing through the widened
  `RevertOperations` gate (the old name stays as a deprecated alias calling it); the Jobs
  section's "Revert last run" resolves the newest completed run of **either** task through
  `requireNewestRun`'s widened filter and routes both through the one API
  (`ManifestRevertTests` covers a manifest run reverted after an extraction run and vice versa).

### D. Disclosure and review UI (design §8.6, §9)

- The two §9 copy blocks verbatim; the first-run acknowledgement path when
  `disclosure_acknowledged_at` is nil; the compact per-run sheet. The Manifest section gains the
  run action with progress, the proposal review flow on Plan 010's grammar, inclusion
  suggestions as advisory rows with one-click `setManifestInclusion`, and "Revert last run"
  covering manifest runs. Recorded-run automation drives the flow end to end
  (`Phase2InferenceUITests`), with a recorded fixture pack under FilmBrain tests mirroring Plan
  007's.
- **The Jobs section becomes task-aware** — today's views hard-code extraction: `RunsListView`
  labels every run "N chunks" and renders only `applyReport`; `RunCardView` totals assume
  chunked children. This plan edits both: run rows label by task (extraction keeps "chunks";
  an `inferAssetManifest` run says "Manifest run", childless), the report line renders
  `manifestReport` (`created` / `skippedExisting` / suggestion count) beside the extraction
  `applyReport` case, and "Revert last run" routes both tasks through contract C's
  `revertRun`. Covered headlessly in the window-model tests (a seeded manifest run renders its
  label, report line, and revert route) and by `Phase2InferenceUITests` asserting the Jobs row
  after a recorded run.

## Target file layout (additions, changes)

```text
Packages/FilmBrain/
  Manifest/ InferManifestTask.swift, InferManifestPrompt.swift, InferManifestValidator.swift,
    ManifestRunGate.swift (run-once + extraction-state checks)
  Resources/Schemas/infer-manifest-v1.schema.json, Resources/Prompts/infer-manifest-v1.md
  Jobs/StructuredJobRunner.swift (CommitOutcome commit path)
  Tests/ InferManifestValidatorTests, ManifestRunTests, Samples/
Packages/FilmCore/
  Domain/ManifestProposal.swift, Extraction/ManifestApplier.swift (new),
  Extraction/ManifestInputBuilder.swift (new — FilmCore per design §3.6/§8.4: apply rebuilds it
    inside its transaction; FilmBrain calls it through the session),
  Editing/RevertOperations.swift (widened gate, summary skip),
  ProjectTools.swift (+ManifestApplying; +revertRun; post-manifest extraction refusal),
  Storage/ProjectRepository.swift + Storage/ProjectSession.swift (the three §3.6 refusal gates:
    run-once, extraction-non-terminal/paused, manifest-closes-extraction; typed
    ProjectStoreError cases for each),
  Tests/ ManifestApplyTests, ManifestInputBuilderTests, BootstrapOrderingTests (direct-storage
    gate tests: each refusal thrown by the repository with no FilmBrain in the loop),
  ManifestRevertTests
AI Film Camp/ Views/Manifest/ (run action, proposal review, suggestions),
  Views/Jobs/RunsListView.swift + Views/Extraction/RunCardView.swift (task-aware labels,
    manifest report line, revert routing),
  UITests/Phase2InferenceUITests.swift
scripts/eval-inputs.txt untouched, and no file it lists is edited by this plan, so its digest
  gate does not fire. Extending the manifest (adding inference sources to it) stays
  out of scope per design §10; revisit only by a recorded decision
```

## Steps

### Step 1: Task, schema, prompt, validator, input builder

Contract A on recorded fixtures.

```bash
swift test --package-path Packages/FilmBrain
swift test --package-path Packages/FilmCore --filter ManifestInputBuilderTests
```

Expected: every §8.3 validator case from design §10's inference list passes; the input builder
(FilmCore, per the layout above) is deterministic over a seeded bundle; the budget pre-flight
refuses an oversized input with the size named.

### Step 2: Runner change, gates, apply, revert

Contracts B and C.

```bash
swift test --package-path Packages/FilmBrain
swift test --package-path Packages/FilmCore
```

Expected: commit-path completes exactly once both ways; run-once, paused-extraction, and
post-manifest extraction-closure gates refuse with the stated copy; the full
§8.4 match enumeration including
the step-0 digest guard (a state deleted, an entity rejected, an override flipped, and a
template entry disabled between validation and apply each fail the run whole with nothing
applied and zero orphaned basis rows; a byte-identical rebuild applies); manifest revert honors the widened
newest-run rule in both directions.

### Step 3: UI, live gates, acceptance

Contract D; then, with operator approval, the schema probe and the acceptance run: extraction
already reviewed on the operator's feature screenplay → Build → run inference → operator reviews
every proposal → record accepted/edited/rejected counts (from the report and journal) in
`docs/IMPLEMENTATION_NOTES.md`.

```bash
./scripts/verify.sh
FILMCAMP_RUN_LIVE_CODEX=1 swift test --package-path Packages/FilmBrain --filter ManifestSchemaCompatibilityTests
```

Expected: all suites exit 0; the probe accepts the schema; the acceptance record is committed.
Update `docs/plans/README.md`.

## Done criteria

- [ ] `./scripts/verify.sh` exits 0; the task, schema, prompt, validator, and input builder
  implement §8.1–§8.3 as written; the runner completes the parent exactly once.
- [ ] Apply implements §8.4 steps 0–6 with every counter of §8.5; suggestions survive reopen;
  revert works cross-task; the three bootstrap gates (run-once, paused-extraction refusal,
  post-manifest extraction closure) are FilmCore-enforced and tested.
- [ ] The §9 disclosure copy ships verbatim; proposals and suggestions review through Plan 010's
  grammar with no second data path.
- [ ] The acceptance run on the operator's feature screenplay is performed, reviewed, and its
  review burden recorded in `docs/IMPLEMENTATION_NOTES.md`; every Phase 2 roadmap exit
  criterion's mechanism now exists end to end.
- [ ] `docs/plans/README.md` marks Plan 012 `DONE`.

## STOP conditions

- The `docs/PHASE2_DESIGN.md` hash differs and §3.4, §3.6, §8, or §9 changed.
- The runner commit change breaks any existing `StructuredJobRunnerTests` behavior.
- The feature screenplay's manifest input exceeds `ManifestInputBudget` (the design defers
  chunking deliberately — stop and reconcile rather than inventing a split).
- The digest guard cannot be made deterministic (`ManifestInputBuilder` output differs across
  identical canonical states — report the nondeterminism; it breaks the §8.4 step-0 contract).
- A verification command fails twice after one reasonable scoped correction.
- Work expands into prompt generation, providers, readiness dashboards, or Phase 6 propagation.

## Maintenance notes

- After this plan, both bootstraps are closed on a project that has run them: analyze once,
  infer once, then the app owns the data (design §14.2/§14.9). Any future re-open of either is a
  product decision, not a bug fix.
- Phase 3 builds the workshop on §7.3's operations and this plan's review surface; Phase 4 reads
  `missingAssets()` and the blocked derivation; Phase 5 consumes approved versions. Keep those
  seams as the design left them.
