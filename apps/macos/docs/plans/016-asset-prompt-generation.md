# Plan 016: Asset prompt generation (Phase 3b)

> **Executor instructions**: Read `docs/PHASE3_DESIGN.md` in full first. This plan implements
> its §3.5 (the skill seam and materialisation, with §3.5's probe deciding between two
> contract-complete designs), §3.7 (the AI actor's write surface, through the apply), §8 (the
> structured job, schema, validator, apply, regeneration, and batch driver), and §9 (the
> disclosures) — prompt generation becomes one click, applying into Plan 014's model through
> `attachGeneratedPrompt` and nothing else, surfaced in Plan 015's workshop. Also read
> `docs/REFERENCE_PROJECTS.md` before touching the runner or adapters, and
> `PromptSkills/README.md` before touching anything under `PromptSkills/` — that tree is
> vendored payload, never edited in place and never imported from Swift; this plan copies it
> at runtime and bundles it as a resource, nothing more.
> Follow the steps in order, run every verification command, honor every STOP condition and
> the live-gate policy. Requires Plans 013, 014, and 015 `DONE`. When complete, set this
> plan's row in `docs/plans/README.md` to `DONE` (or `BLOCKED` per the acceptance tiers
> below).
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   90dc7842e286b2bbf556a02384096448694d4a698fd24f64a3cdc5ebd4fcb3d7 docs/PHASE3_DESIGN.md \
>   84c3599561dac60fd02d00d8a3d6a564558bac340fb5988d8bcc83868748ff68 docs/PHASE2_DESIGN.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   282b1ae714029b96e932bff1eba236df0e05b76abc1fe6b434f90f11ca418d46 docs/REFERENCE_PROJECTS.md \
>   330c79f1905f51f2fd82413cd03cef68a336f630678d757143f8b524bbbc0e3c PromptSkills/README.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all six print `OK`. If the PHASE3 hash differs, stop for reconciliation when
> §3.5–§3.7, §8, §9, §13.4–§13.7, or §14.1, §14.3–§14.4, §14.6 changed; §13/§14 acceptance
> recorded in the status prose alone is re-pinned, not a stop. The `PromptSkills/README.md`
> pin guards the vendored tree this plan's descriptor, routing paths, and knowledge-file
> citations depend on — a re-vendoring between planning and execution changes the instruction
> text and the tree digest, and is a reconciliation, not a surprise. `docs/OVERVIEW.md` is
> **deliberately unpinned**: Plan 015 edits it before this plan runs, so no hash is stable at
> planning time, and this plan does not depend on its text.
>
> **Live gates: three** — see the live-gate policy. Nothing else calls Codex.

## Status

- **Status**: DONE — all three live gates deferred with recorded consent (2026-08-23);
  Step 6 skipped whole (§14.1's evidence gate unmet); Phase 3 closed by owner decision
  the same day with the §10 acceptance run waived (recorded in IMPLEMENTATION_NOTES)
- **Priority**: P1
- **Effort**: L–XL, approximately 10–14 focused engineering days
- **Risk**: MED-HIGH; the job itself is the shipped manifest shape at single-requirement
  scale, but the materialiser rests on a probed assumption about the external harness with a
  design branch either way, the apply deviates from precedent by being invertible (§13.11),
  and the exit evidence is an operator activity with a pass bar (§14.6)
- **Depends on**: 013, 014, 015
- **Category**: feature / ai / tests
- **Planned at**: commit `a861a00`, 2026-08-22; design hash in the drift check

## Current state

- Plans 013–015 shipped the full 3a surface: prompt rows, reads, digests and the golden
  fixture, the six operations, `attachGeneratedPrompt` with its **pinned signature**
  (Plan 014 contract B — this plan consumes it and must not alter it), the amended
  recompute, and the workshop with Generate/Regenerate present but disabled.
- The runner's commit path ships `CommitOutcome` (Plan 012) — a closure returning
  `.completedByClosure` suppresses the runner's own `completeJob`. **Nothing new is needed
  from the runner** (design §8.1); a change to `StructuredJobRunner`'s lifecycle would be a
  design divergence, not an implementation detail.
- Plan 013 shipped both report doors: the public typed `setAssetPromptReport` (tests and
  tooling) and the internal `ProjectRepository.writeAssetPromptReport(_:jobID:in:)` primitive
  — the `writeManifestReport` shape, whose doc comment records why the public setter can
  never be the in-apply write (it opens its own transaction and refuses completed jobs).
- `CodexInvocationBuilder` disables every ambient-context channel; a skill reaches a session
  only as files the prompt names. The built `clearJobCache` walks `cache/jobs` **and filters
  every entry** to `workspace` components and `input.txt` — that predicate is the "result
  JSON survives" rule, and it would pass over a skill cache untouched (contract A states the
  consequence). `prepareRunWorkspace` creates an empty directory — no materialisation
  mechanism exists.
- The recorded per-task branching is a **schema-name prefix switch inside
  `RecordedExtractionHarnessAdapter.replay`** (app target, keyed on
  `request.schemaURL.lastPathComponent`), which `AppServices.makeAdapter(status:)` returns
  whole in recorded mode; FilmBrain's `RecordedHarnessAdapter` is a caller-scripted type
  that never reads the schema URL and is **not** the seam this plan extends.
- `project.yml` has no `PromptSkills` entry in any target — an installed build has no skill
  to materialise (§3.5's work item, carried here). The vendored tree sums to ≈1.5 MB.
- The shipped Jobs model is task-aware on the window model (Plan 012's record).

## Owner gates (design §14 — all seven accepted 2026-08-22, recorded in the design)

- **§14.1 (batch generation) — DECIDED 2026-08-22: evidence-gated.** The driver ships only
  after the acceptance run (Step 5, live gate 3) scores **≥ 5/6** on §10's tiers **and** the
  owner then approves the spend with the request-count estimate in hand — one request per
  non-skipped requirement, order of 100–200 on a feature manifest after the skip rules thin
  the non-Approved set. **Step 6 is conditional on both**; a 4/6 run, a deferred run, or a
  withheld approval each leave Step 6 skipped whole with the deferral recorded, and the plan
  is still completable — single-requirement generation, regeneration, and every other
  contract stand, and the acceptance record notes §1's at-risk exit criterion.
- **§14.3 (integrated provider) — DECIDED 2026-08-22: no, as recommended.** Not built; only
  §3.6's seam constraints are honored structurally (no table, type, or operation knows
  providers exist). Building one is out of scope for this plan.
- **§14.4 (custom skill chooser) — DECIDED 2026-08-22: defer, as recommended.** Not built —
  the `PromptSkillDescriptor` plumbing ships so a swapped skill is a data change; the chooser
  UI waits for Phase 5.
- **§14.6 (acceptance bar) — DECIDED 2026-08-22: tiered.** The live-gate policy below
  carries §10's tiers verbatim: 5/6 or 6/6 usable without hand-editing (no edit to the
  prompt body) passes cleanly and gives §14.1 its evidence; 4/6 lets this plan land with
  prompt-generation quality recorded as explicitly unresolved (failing class named) and
  batch deferred; ≤ 3/6 is a STOP — the plan goes `BLOCKED`.

## Live-gate policy

Deterministic work runs on recorded fixtures. Three account-backed gates, each with explicit
operator approval immediately before running, never in CI, skipped unless
`FILMCAMP_RUN_LIVE_CODEX=1`:

1. **The Step 1 sandbox probe — 1 Codex request.** One live run that asks the session to read
   an absolute path outside `-C` and report (§3.5). Its result selects the materialiser arm
   (contract A). If approval is absent when materialiser work must proceed, implement
   **arm B** (the clone fallback — correct under either probe outcome, since a cloned skill
   is read from inside the workspace) and record the deferred probe in
   `docs/IMPLEMENTATION_NOTES.md`; a later passing probe makes arm A a cache-layout change,
   not a contract change.
2. **The schema-compatibility probe** of `asset-prompt-v1.schema.json` — 1 request (the
   shipped opt-in pattern, §8.3).
3. **The §10 acceptance run — exactly 6 requests**: prompts generated for exactly five
   requirements on the operator's feature project (two character canonicals, one look
   variant, one location, one prop) plus exactly one regeneration after a canonical
   replacement — six prompts, the denominator §10's tiers are stated in;
   results imported, one canonical replaced, review burden recorded in
   `docs/IMPLEMENTATION_NOTES.md`. There is no prompt answer key; the operator's generator is
   the judge, and §10's tiers grade the outcome.

**Posture, per the design's stated policy (§10; tiers owner-decided 2026-08-22)**: gates 1
and 2 are deferrable with a recorded deferral (gate 1 via the arm-B route above), and this
plan may be marked `DONE` with the acceptance run deferred and recorded (the Plans 003/004
posture) — but **Phase 3 itself is not finished** until the acceptance record is committed,
and a deferred run also defers the batch driver, whose evidence gate is then unmet. **The
acceptance has a tiered quality bar** — "usable without hand-editing" means usable in the
operator's generator with no edit to the prompt body. Of the run's six prompts: **5/6 or
6/6 usable → pass** — the plan completes cleanly and Step 6's evidence gate is met;
**4/6 → the plan may still complete**, with prompt-generation quality recorded as
**explicitly unresolved** in `docs/IMPLEMENTATION_NOTES.md` (failing requirement class
named — the DONE-with-recorded-deferral house pattern) and **batch generation staying
deferred**; **≤ 3/6 → this plan goes `BLOCKED`** naming the failing requirement class —
deferral is for unspent gates, never failed ones.

## Contracts (normative)

### A. Skill materialisation and the seam (design §3.5, §4.1 — both arms specified; Step 1 selects)

- FilmBrain gains `PromptSkillDescriptor` (`id`, `displayName`, `rootURL`,
  `entryRelativePath`, `stillImageRoutingRelativePath?`; default = the bundled
  `higgsfield` tree, entry `SKILL.md`, routing `image-models.md` — carried separately because
  the entry never references it) and `PromptSkillMaterializer`, keyed on the **tree digest**
  (SHA-256 over the sorted relative-path/file-SHA manifest), copying the directory layout
  verbatim, idempotent, testable against a fixture skill directory (FilmBrain never resolves
  the app bundle; the descriptor's URL is a parameter).
  - **Arm A (probe passes — reads outside `-C` are permitted)**: one shared copy per
    (descriptor, tree digest) at `cache/skills/<skill_id>/<tree-digest-prefix-12>/`; the
    rendered instructions name the entry (and routing file, if present) by absolute path into
    that copy; a batch of N writes exactly one copy.
  - **Arm B (probe fails or is deferred)**: the shared copy plus an APFS `clonefile(2)` clone
    into each run's `workspace/skill/`; the instructions name the cloned entry; the growth
    bound and the "one copy" assertions are restated in **bytes of unique data** (§3.5,
    §4.1). **Arm B degrades, it never dead-ends**: when `clonefile(2)` returns
    `ENOTSUP`/`EXDEV` (a bundle on a non-APFS volume — a runtime fact no build-time check
    can settle), the materialiser falls back to a plain per-run copy under the same
    `workspace/skill/` path, swept by the same Clear Job Cache walk; the growth bound
    degrades to one tree per live run, the assertion becomes "unique bytes ≤ one tree per
    concurrent run", and the degradation is recorded in `docs/IMPLEMENTATION_NOTES.md` when
    first observed in testing.
- **Containment and durable identity — §3.5's four rules, on either arm, each with a
  test.** (1) `skill_id`, the entry and routing relative paths, and every relative path in
  the copied tree are validated by **`RelativeProjectPath`'s rules, reused by name** — no
  empty string, no leading `/`, no NUL, no backslash, no empty/`.`/`..` component; a
  violation refuses materialisation and the run, never sanitises. (2) **Symlinks are
  rejected, never followed**: the source walk and the destination path use Phase 2's
  no-follow containment posture (`BundleContainment`'s `openat(O_NOFOLLOW | O_DIRECTORY)`
  discipline) and a planted symlink — component or leaf — fails with the containment
  refusal, asserted against a fixture tree carrying one. (3) **A 12-character digest-prefix
  collision never silently reuses a tree**: before reusing a resident directory the
  materialiser compares the **full** tree digest, and on disagreement lengthens the prefix
  until the paths are distinct or errs — the test drives two distinct trees onto a forced
  prefix collision and asserts no cross-reuse. (4) **Only descriptor-relative provenance is
  persisted**: rows carry `skill_id`, the **descriptor-relative** entry path, and the SHAs;
  the absolute cache path exists only in the live invocation's rendered instructions and is
  asserted absent from every persisted row — so Clear Job Cache and a project move leave
  "which skill wrote this" answerable (§3.5, §4.1, §4.3's column comment).
- Either arm: **Clear Job Cache extends to `cache/skills/` as a second root walk, and the
  second root is swept unfiltered — the whole subtree.** The shipped walk's
  `isWorkspace || isInput` predicate is what makes result JSON survive under `cache/jobs`,
  and it must stay **scoped to the `cache/jobs` root only**: nothing under
  `cache/skills/<skill_id>/<tree-digest-prefix>/` has a `workspace` component or an
  `input.txt`, so reusing the filtered loop would provably remove zero files.
  `ensureJobCacheCanBeCleared`'s no-active-run scope covers both roots; `clearOrphanedMedia`
  is not touched. Every prompt row records `skill_id`, the **descriptor-relative**
  `skill_entry_path`, and `skill_entry_sha256` (the entry file's digest at
  materialisation) — never an absolute cache path.
- **Materialising a changed skill tree does not stale a prompt** (§3.4's promise, §10's
  test): a re-materialisation with a new tree digest and new `skill_entry_sha256` leaves
  every existing prompt's derived `isStale` unchanged, asserted in the same walk as the
  entry-SHA recording — the skill payload is outside the digest by design.
- **The app-bundling work item**: `project.yml` adds `PromptSkills` to the app target as a
  folder resource (`type: folder`, `buildPhase: resources` — the `.aifilm` sample mechanism),
  and the default descriptor's `rootURL` resolves through the app bundle. A build-product
  test asserts the folder is present in the built app with `SKILL.md` at its recorded path;
  Step 2 also checks the built product directly so a bundling failure cannot hide until
  Step 5.
- The rendered instructions carry §3.5's override clause (the JSON output contract wins over
  any response-format or word-cap rule in the skill; the vendored spec snapshots are
  authoritative, no live verification), point at the image-model routing table and the named
  §3.5 knowledge files including the seven-slot character formula — never the
  character-design sheet's age-asking header — and end with §8.2's prompt-injection clause.
  `seedance_lint.py` is not adopted (§3.5, §13.7).
- Prop and object prompt bodies are deliberately terse: one or two sentences, at most
  45 words, limited to the object, a few defining visible traits, and the clean
  front/side/back grey-background sheet. The Film Camp instruction's cap overrides
  expansive skill prose so a simple production prop does not receive a cinematic essay.

### B. Task, schema, prompt, validator (design §8.1–§8.3, verbatim)

- `GenerateAssetPromptTask` (`taskName = "generateAssetPrompt"`, `schemaVersion = 1`),
  `asset-prompt-v1.schema.json` and `asset-prompt-v1.md` under `Resources/`, run through the
  existing `StructuredJobRunner` with a commit closure — the Plan 012 manifest shape at
  single-requirement scale, no `ExtractionRun`, no chunking. `prompt(for:)` prepends the
  instructions and wraps the payload in `<asset-prompt-input>` following the shipped
  `InferManifestPrompt.render` — **the wrapper is outside the digest**, so `jobs.input_sha256`
  equals `AssetPromptInput.digest`, the one digest of §3.4.
- The schema is §8.3's exactly: Structured-Outputs-safe, `additionalProperties: false`,
  `schemaVersion: const 1`, `prompt.body`/`targetModel`/`guidance`, no arrays in v1;
  `targetModel` is opaque — the app validates shape, never membership in any model list.
- `AssetPromptValidator` (FilmBrain, versioned, Film-Camp-authored) enforces every §8.3
  semantic code — `empty_prompt_body`, `oversized_prompt_body`, `control_characters`,
  `missing_reference_designator`, `unknown_reference_designator`, `missing_target_model`,
  and `age_written` with §8.3's three numeric patterns and its deliberate numeric-only scope.
  Fixtures pinned both ways per §10 ("12 years old", "age: 34", "34 y.o." fail; "Stone Age",
  "middle-aged", digit-free "teenager" pass). Structural failures keep the shared pipeline
  and the 16 MB cap. `AssetPromptProposal` (FilmCore) is the validated payload type with a
  throwing init re-checking lengths, the `ExtractionProposal` pattern.

### C. Gates, apply, and runs (design §8.1, §8.4–§8.7, §3.7, §7.4's prohibitions)

- **Pre-flight** (FilmCore-enforced, FilmBrain-mirrored): requirement accepted and active,
  not `isGenerationBlocked`, not whole-locked; rendered input within `AssetPromptInputBudget`
  (over budget refuses naming the size via the new `.assetPromptInputOverBudget`, never
  truncates). **No run-once gate, nothing closes** (§3.1); the one-active-run rule
  serializes; a prompt run is additionally **refused while any extraction or manifest run is
  non-terminal or paused** — the new `.promptRunRequiresIdleBootstraps` with §5.8's copy,
  thrown beside the shipped bootstrap gates in FilmCore; FilmBrain's `AssetPromptRunGate`
  (the `ManifestRunGate` pattern) asks the same questions so the UI greys out with the
  store's own sentence. Model and effort come from the shared Advanced surface, captured at
  start into `AssetPromptSettings` with the skill identity.
- **`applyAssetPromptRun(_:runJobID:usage:)`** joins `ProjectSession` through the new
  `PromptApplying` role protocol — the **eighth** `ProjectTools` role, never a widened one —
  as the commit closure's target, one transaction, returning `.completedByClosure`, §8.4's
  steps 0–4 verbatim: the in-transaction digest re-verification against `jobs.input_sha256`
  (mismatch throws the new `.assetPromptInputChangedDuringRun`, nothing applied, re-run
  always available); the cheap precondition re-check (the enforcement point for locks and
  review state, which are outside the digest); **one invertible entry** via Plan 014's
  `attachGeneratedPrompt` — **consuming 014's pinned signature exactly**: the applier
  supplies the step-0 rebuilt digest and the builder's format version, the operation derives
  the citations (§3.7 is the AI actor's entire write surface); then step 3 **through
  Plan 013's internal `writeAssetPromptReport(_:jobID:in:)` primitive plus the shipped
  in-transaction parent completion carrying `usage`** — never the public
  `setAssetPromptReport`, which opens its own transaction and refuses completed jobs (the
  recorded Phase 2 lesson; the public door has no production caller and serves tests and
  tooling); finally `AssetPromptApplyOutcome` (report + journal entry) so the workshop
  routes the entry through `didApply` and ⌘Z reads "Undo Generate Prompt" (§13.11's stated
  deviation — the apply is invertible; the undo stack survives generation).
- **Prompt runs stay outside the revert machinery** (§7.4, §8.4): `generateAssetPrompt` is
  **never added** to `requireNewestRun`'s closed task list (test-asserted), prompt runs have
  no summary op, and a prompt run never offers Revert; recovery is undo while on the stack,
  `deletePrompt` forever after. A completed prompt run blocks neither an extraction nor a
  manifest revert (test). The Jobs section's task-aware window-model arm (label, report line
  from `assetPromptReport`, childless, no Revert) is contract E's surface, exercised with it
  at Step 5.
- **Regeneration (§8.7)** is the same pipeline: new run, new row at max + 1, prior prompts
  untouched, the human-current-prompt confirm ("your edited prompt stays in history" —
  appended to Plan 015's `WorkshopConfirmText`); undo of a regenerate re-exposes the
  previous prompt. Execution mechanics are §8.6's standard paths. **The recorded-run seam is
  the app-target replay switch**: a new `asset-prompt-` schema-name branch in the prefix
  switch inside `RecordedExtractionHarnessAdapter.replay` (keyed on
  `request.schemaURL.lastPathComponent`, beside the shipped `reconcile-` and
  `infer-manifest-` branches), materialising the result from `request.prompt`'s
  `<asset-prompt-input>` payload — echoing designators back into a valid body, never a
  checked-in canned file. FilmBrain's caller-scripted `RecordedHarnessAdapter` is not
  touched; FilmBrain-side tests script it with valid result payloads as they do today.

### D. The batch driver (design §8.1, §14.1 — evidence-gated on ≥ 5/6 plus the spend approval)

- `AssetPromptBatch` (FilmBrain actor): input set = every requirement whose asset is not
  Approved, **active or not**, in the derived generation order (§7.5 — a sort here, not a
  filter); the skip taxonomy thins it, which is what makes each counter reachable and each
  counter test honest. Skip rules before any request — `skippedFresh` (current prompt's
  `input_digest` matches a fresh render), `skippedUnreviewed` (`proposed`),
  `skippedInactive` (**reachable exactly because inactive rows enter the set**),
  `skippedBlocked`, `skippedLocked`; "Regenerate All"
  is the same set with `skippedFresh` off. Sequential single-requirement jobs; the skill
  materialised once (one copy — or the arm-B unique-bytes bound — asserted after a batch of
  N); cancellation stops after the in-flight job; partial failure fails that requirement and
  continues, every applied prompt staying applied in its own transaction; the driver owns no
  transaction and writes nothing itself; counters live in the driver's summary, not any
  job's report (§8.5). One confirm sheet names the exact request count — **the count of
  non-skipped requirements after the taxonomy thins the non-Approved set**, never the raw
  set size. The batch confirm and §9's batch disclosure variant ship with this contract and
  inherit its evidence gate; nothing batch-shaped renders while the gate is unmet.

### E. Disclosure and the workshop wiring (design §9 verbatim, §5.4, §5.8's run rows)

- The two §9 copy blocks ship **verbatim** (a `PromptDisclosureText` support type beside the
  shipped extraction/manifest ones, asserted character for character in headless tests): the
  first-run acknowledgement when `disclosure_acknowledged_at` is nil — reachable without
  either bootstrap acknowledged — and the compact per-run confirm (§9's batch variant
  ships with contract D and inherits its evidence gate). Media never leaves the bundle;
  no provider ships (§3.6).
- Generate/Regenerate come alive: Plan 015's enablement plumbing gains the run-gate
  condition from `AssetPromptRunGate`; refusals surface FilmCore's strings verbatim,
  including this plan's three. The Jobs section renders prompt runs per contract C's rule.
  UI tests against the recorded replay branch with **mandatory headless twins** (§5.9):
  generate → `prompt_ready` with citations and skill identity recorded; regenerate over a
  human-edited prompt leaving it in history; the stale badge driving Regenerate; the Jobs
  row with no Revert (the batch confirm and counters are Step 6's, when its gate is met).
  Extend `Phase3WorkshopUITests`'
  pattern; the headless twins are the assertions of record under the documented UI-runner
  flake.

## Target file layout (additions, changes)

```text
Packages/FilmBrain/
  Prompting/ GenerateAssetPromptTask.swift, AssetPromptPrompt.swift, AssetPromptValidator.swift,
    PromptSkillDescriptor.swift, PromptSkillMaterializer.swift, AssetPromptRunGate.swift,
    AssetPromptBatch.swift (§14.1)
  Resources/Schemas/asset-prompt-v1.schema.json, Resources/Prompts/asset-prompt-v1.md
  Tests/ AssetPromptValidatorTests, PromptSkillMaterializerTests (fixture skill tree),
    AssetPromptRunTests, AssetPromptBatchTests, PromptSchemaCompatibilityTests (gated)
Packages/FilmCore/
  Domain/AssetPromptProposal.swift (new; + AssetPromptApplyOutcome),
  Extraction/AssetPromptApplier.swift (new — applyAssetPromptRun, using Plan 013's
    writeAssetPromptReport and the shipped in-transaction parent completion),
  Storage/ProjectRepository.swift + ProjectSession.swift (run gates; the three new
    ProjectStoreError cases; clearJobCache second root, unfiltered, with the shipped
    filter scoped to cache/jobs), ProjectTools.swift (+PromptApplying, the eighth role)
  Tests/ AssetPromptApplyTests, PromptRunGateTests, PromptRevertExclusionTests,
    JobCacheSweepTests, SkillUpdateStalenessTests
AI Film Camp/ App/ProjectWindowModel+PromptRun.swift (new), Jobs views (prompt-run arm),
  Support/PromptDisclosureText.swift (new), Support/RecordedExtractionHarnessAdapter.swift
  (new "asset-prompt-" schema-name branch in replay, materialised from request.prompt),
  Support/WorkshopConfirmText.swift (+two 016-owned confirm strings),
  Views/Manifest/ (Generate/Regenerate wiring, batch confirm);
  UITests/Phase3GenerationUITests.swift; a build-product test for the bundled PromptSkills
  folder
project.yml (+PromptSkills folder resource — the one Phase 3 project.yml change)
```

`scripts/eval-inputs.txt` is untouched, and no file it lists is edited by this plan
(design §10 — nothing here changes the extraction score).

## Steps

### Step 1: The sandbox probe (live gate 1) and arm selection

With operator approval, run the one-request probe of §3.5 under
`FILMCAMP_RUN_LIVE_CODEX=1`; record the result and the selected arm (A or B) in
`docs/IMPLEMENTATION_NOTES.md`. Without approval, select arm B and record the deferral per
the live-gate policy.

```bash
grep -nE 'sandbox probe.*(arm A|arm B|deferred)' docs/IMPLEMENTATION_NOTES.md
```

Expected: exactly one matching line, in a Plan 016 section, naming the probe outcome (or
deferral) and the arm — written before any materialiser code. An ambiguous probe result
(reads partially permitted, environment-dependent) is a STOP, not a judgment call.

### Step 2: Materialiser, cache sweep, bundling

Contract A on the selected arm.

```bash
swift test --package-path Packages/FilmBrain --filter PromptSkillMaterializerTests
swift test --package-path Packages/FilmCore --filter JobCacheSweepTests
xcodegen generate --spec project.yml
xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" -configuration Debug \
  -derivedDataPath .build/DerivedData -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
ls ".build/DerivedData/Build/Products/Debug/AI Film Camp.app/Contents/Resources/PromptSkills/higgsfield/SKILL.md"
```

Expected: fixture tree copied intact with relative cross-references resolving; the four
containment rules asserted (an unsafe `skill_id` or entry path refused by
`RelativeProjectPath`'s rules, a planted symlink refused by the no-follow walk, a forced
digest-prefix collision resolved against the full tree digest rather than reused, and no
absolute cache path on any persisted row); idempotence keyed on the tree digest (a changed
non-entry file forces a fresh copy); one copy — or the
arm-B unique-bytes bound, including the `ENOTSUP` plain-copy degradation — after N simulated
runs; the sweep test materialises a fixture skill and asserts **non-zero
`filesRemoved`/`bytesFreed`** from the `cache/skills` root with `cache/jobs` result JSON
surviving; the changed-tree re-materialisation leaves existing prompts' `isStale` unchanged;
the built product contains the bundled `SKILL.md` at the listed path.

### Step 3: Task, schema, prompt, validator

Contract B; then, with approval, live gate 2.

```bash
swift test --package-path Packages/FilmBrain
swift test --package-path Packages/FilmCore
FILMCAMP_RUN_LIVE_CODEX=1 swift test --package-path Packages/FilmBrain --filter PromptSchemaCompatibilityTests
```

Expected: every §8.3 code has a passing fixture, the age lint both ways;
`AssetPromptProposal`'s throwing init is exercised in the FilmCore suite; the rendered
instructions carry the override, routing, formula, and injection clauses; the probe accepts
the schema (or its deferral is recorded).

### Step 4: Gates, apply, runs

Contract C (the Jobs surface lands with contract E at Step 5).

```bash
swift test --package-path Packages/FilmCore
swift test --package-path Packages/FilmBrain
```

Expected: recorded runs complete exactly once through the shipped commit path, report and
usage landing via the in-db primitive inside the apply transaction; the step-0 guard fails
whole on each §10 mid-run drift case (a state deleted, a reference's approved version
changed, a rename, a dependency removed, an unsatisfied dependency added) and applies
cleanly on a byte-identical rebuild; un-accepting mid-run is caught by step 1; the
paused-bootstrap refusal fires from FilmCore with `AssetPromptRunGate` matching; undo of a
generate restores byte-identical digests; the revert exclusions hold in both directions.

### Step 5: Disclosure, UI, verification, acceptance (live gate 3)

Contract E, including the Jobs prompt-run arm; then the acceptance run per the live-gate
policy, with the operator. (The acceptance runs **ahead of the batch driver** deliberately:
Step 6's evidence gate consumes this step's recorded outcome.)

```bash
./scripts/verify.sh
```

Expected: all suites exit 0 (headless twins are the assertions of record under the
documented UI flake); the disclosure copy asserted verbatim; the Jobs arm's window-model
twins pass; then the acceptance record — prompts generated, results imported, one canonical
replaced, review burden and the §10 tier outcome — committed to
`docs/IMPLEMENTATION_NOTES.md`, or its deferral recorded. Then, by tier: **5/6 or 6/6** —
record the outcome; Step 6 becomes eligible, conditional on the owner's spend approval.
**4/6** — record prompt-generation quality as explicitly unresolved with the failing class
named, skip Step 6 whole with its deferral recorded; the plan is
completable. **≤ 3/6** — stop; mark the plan `BLOCKED` naming the failing class. **Run
deferred** — skip Step 6 (its evidence gate is unmet) and record both deferrals. Update
`docs/plans/README.md` accordingly.

### Step 6: The batch driver (§14.1 — evidence-gated)

Contract D — built only when Step 5's recorded acceptance outcome is **≥ 5/6** and the
owner approves the spend with the request count in hand; otherwise skipped whole with the
deferral (and the tier that caused it) recorded.

```bash
swift test --package-path Packages/FilmBrain --filter AssetPromptBatchTests
./scripts/verify.sh
```

Expected: the defined input set and skip taxonomy, ordering, cancellation, partial-failure
continuation, counters, the one-materialisation assertion, and the batch confirm naming the
exact request count; `verify.sh` green with the batch surfaces in place. Update
`docs/plans/README.md` per the posture (`DONE`; `DONE` with recorded deferrals; `BLOCKED`
only from Step 5's ≤ 3/6 tier).

## Done criteria

- [ ] `./scripts/verify.sh` exits 0; the probe (or its recorded deferral) selected the
  materialiser arm, and contract A holds on that arm including the unfiltered second-root
  sweep (non-zero counts asserted), the `ENOTSUP` degradation path, the
  skill-update-does-not-stale assertion, and the bundled-resource build-product check.
- [ ] The task, schema, prompt, and validator implement §8.1–§8.3 as written; the one-digest
  identity (`AssetPromptInput.digest` = `jobs.input_sha256`, wrapper outside) is
  test-asserted.
- [ ] The apply is §8.4's steps 0–4 through `attachGeneratedPrompt`'s pinned signature
  alone, invertible, with report and usage written through the in-db primitive and the run
  completed exactly once in-transaction; prompt runs are excluded from every revert path and
  the Jobs section renders them without Revert; regeneration inserts above and never touches
  prior prompts.
- [ ] The batch driver meets contract D with its counters and single materialisation **if
  and only if** Step 5 recorded ≥ 5/6 and the owner approved the spend; otherwise its
  deferral, and the tier that caused it, is recorded and nothing batch-shaped renders.
- [ ] The §9 copy ships verbatim on both surfaces; the recorded flow runs through the
  `asset-prompt-` replay branch; no provider, no credential, no media leaving the bundle
  anywhere in the diff.
- [ ] The acceptance run is performed and graded on §10's tiers — or its deferral
  recorded — with the 4/6 tier's unresolved-quality note where it applies, and
  `docs/plans/README.md` marks Plan 016 accordingly.
- [ ] **The §14 decision this plan implements carries the owner's recorded acceptance**:
  §14.4 (custom skill selection — the descriptor plumbing ships, the chooser is deferred to
  Phase 5) is **accepted 2026-08-22, as recommended**, recorded in design §14; confirm the
  design still reads that way before flipping this plan's README row to `DONE`. §14.1 and
  §14.6 were decided the same day and are already recorded; **§14.3 gates no plan** —
  nothing here builds an integrated provider under any outcome.

## STOP conditions

- The `docs/PHASE3_DESIGN.md` hash differs and §3.5–§3.7, §8, or §9 changed.
- The Step 1 probe returns an ambiguous result (reads partially permitted or
  environment-dependent) — reconcile with the design before choosing an arm.
- Any change to `StructuredJobRunner`'s lifecycle appears necessary — the design verified the
  shipped commit path suffices (§8.1); a needed edit is a design divergence.
- Plan 014's pinned `attachGeneratedPrompt` signature proves insufficient for §8.4's apply —
  report the missing parameter; do not widen the operation silently.
- A recorded run's apply cannot make the step-0 guard deterministic, or the one-digest
  identity fails (the §3.4 contract is broken; report, do not add a second digest).
- The rendered input for a real requirement exceeds `AssetPromptInputBudget` (§11 defers
  chunked prompt inputs deliberately — stop and reconcile rather than inventing a split).
- The acceptance run scores **≤ 3/6** on §10's tiers — mark `BLOCKED` naming the failing
  requirement class; do not defer a failed gate. (A 4/6 run is **not** a STOP: the plan
  completes on §10's middle tier with quality recorded as unresolved and batch deferred.)
- A verification command fails twice after one reasonable scoped correction (UI suites:
  compare against the recorded environmental flake first).
- Work expands into an integrated provider, credential storage, a skill-chooser UI, scene
  prompts, generation packages, or export (§3.6, §14.3–§14.4, Phase 5), or into Phase 4
  readiness dashboards.

## Maintenance notes

- The descriptor is the swappability seam (§3.5): a Phase 5 skill change is a data change;
  never hardcode the higgsfield path outside the default descriptor.
- If review shows models leaking trigger-word ages past the instructions, widening the
  `age_written` lint is a validator version bump, not a schema change (§8.3).
- After this plan, Phase 3's remaining work is evidence, not code: the §10 acceptance record
  is what finishes the phase. Phase 4 lands on §6's states and §7.5's reads; Phase 5 inherits
  §3.3's ordering and this plan's descriptor seam. Keep both seams as the design left them.
