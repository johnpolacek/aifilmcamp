# Plan 021: Scene prompt generation (Phase 5b)

> **Executor instructions**: Read `docs/PHASE5_DESIGN.md` in full first. This plan
> implements its §3.7 (the inherited skill seam, the instructions and routing, the
> linter posture), §8 (the `generateScenePrompt` task, schema, validator with the
> per-reference declaration rule, the invertible apply, the report, run mechanics and
> regeneration, the atomic imported-skill verification at the materialiser boundary),
> §9 (the disclosures, verbatim), and — **evidence-gated, §14.1** — the batch driver.
> Also read `docs/REFERENCE_PROJECTS.md` before touching the runner or adapters, and
> `PromptSkills/README.md` before touching anything under `PromptSkills/` (vendored
> payload — never edited in place, never imported from Swift). Follow the steps in
> order, run every verification command, honor every STOP condition and the live-gate
> policy. Requires Plans 018–020 `DONE`. When complete, set this plan's row in
> `docs/plans/README.md` per the Done criteria.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   bd477ef76dbb98c2f7dbffdae5310b8f824e309e904bcd91f03cca2004eb7ee1 docs/PHASE5_DESIGN.md \
>   90dc7842e286b2bbf556a02384096448694d4a698fd24f64a3cdc5ebd4fcb3d7 docs/PHASE3_DESIGN.md \
>   330c79f1905f51f2fd82413cd03cef68a336f630678d757143f8b524bbbc0e3c PromptSkills/README.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   282b1ae714029b96e932bff1eba236df0e05b76abc1fe6b434f90f11ca418d46 docs/REFERENCE_PROJECTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all five print `OK`. `docs/OVERVIEW.md` is deliberately unpinned (Plan 020
> edits it before this plan runs). Plan 020's Step 4 sweep does not touch these five;
> on a PHASE5 mismatch, diff the design and stop only if §3.7, §8, §9, or §14.1 changed.
>
> **Live gates: two** — see the live-gate policy. Nothing else calls Codex.

## Status

- **Status**: DONE — every contract landed and the full unfiltered `verify.sh` gate is
  **ALL GREEN**, all ten UI suites included: the task, schema, and prompt on the recorded
  branch; the profile-carried declaration-line validator; the invertible apply, report,
  and replay branch; the materialiser-boundary race test; disclosures verbatim;
  Generate/Regenerate live behind `ScenePromptRunGate`. Execution also found and fixed
  the Phase 5 UI walk's standing failure (combined-row text rides `value`, not `label`),
  its first recorded clean pass. Both live gates are **deferred** (unspent, honestly
  recorded in IMPLEMENTATION_NOTES — the schema probe on the recorded fallback, the §10
  acceptance run with the endpoint consequence stated), and **Step 6 skipped whole**
  while §14.1's evidence gate is unmet; nothing batch-shaped renders
- **Priority**: P1
- **Effort**: L, approximately 8–11 focused engineering days
- **Risk**: MED-HIGH; the pipeline is Plan 016's shape at scene scale and the seam is
  built, but the declaration-line validator is new checking machinery with real
  false-positive risk, the acceptance evidence is an operator activity on a tiered
  bar, and the batch driver is evidence-gated behind that bar plus a spend approval
- **Depends on**: 018, 019, 020
- **Category**: feature / ai / tests
- **Planned at**: commit `dce8971`, 2026-08-23; design hashes in the drift check

## Current state

- Plans 018–020 ship the model, operations, exporter, and section; Generate/Regenerate
  identifiers are reserved, unrendered.
- Plan 016 is `DONE` (Step 5 landed at `a620187`; Phase 3 closed at `00ee68e` with the
  acceptance run waived): the app-side recorded-replay switch
  (`RecordedExtractionHarnessAdapter.replay`, schema-prefix branches including
  `asset-prompt-`), `PromptDisclosureText`, the `+PromptRun` window-model twin, and the
  default-descriptor construction site all exist — **this plan extends those sites, it
  does not build parallels** (design §1.2, fourth revision's current-state note).
- The materialiser carries `expectedTreeSHA256` and `treeDigestMismatch` from Plan 018
  (contract F there); this plan's run coordinator is the first live caller.
- `seedance_lint.py` is not adopted as a gate (§14.3, accepted): it is the operator's
  acceptance-time preflight, invoked read-only with
  `--preflight --model seedance_2_5 --regime block` (the regime flag is load-bearing —
  design §12).

## Owner gates (design §13/§14)

- **§14.1 (batch generation evidence-gated) — ACCEPTED 2026-08-23 as recommended**:
  the driver ships only after the §10 acceptance run scores 5/6 or better *and* the
  owner approves the counted spend. Until both, nothing batch-shaped renders; Step 6
  is skipped whole if the gate is unmet, the Plan 016 posture.
- **§14.3 (the Film-Camp validator is the commit gate; the linter is operator-side) —
  ACCEPTED 2026-08-23 as recommended.**
- **§14.4 (scene body text in the payload and digest, with its own disclosure) —
  ACCEPTED 2026-08-23 as recommended.**
- Confirm the design still reads ACCEPTED on all three before flipping the README row.

## Live-gate policy

Deterministic work runs on the recorded replay branch. Two account-backed gates, each
with explicit operator approval immediately before running, never in CI, skipped unless
`FILMCAMP_RUN_LIVE_CODEX=1`:

1. **Schema-compatibility probe** of `scene-prompt-v1.schema.json` — 1 request, the
   shipped opt-in pattern. Deferrable with a recorded fallback (the schema follows
   `asset-prompt-v1` exactly: `additionalProperties: false`, `const` version, no
   arrays, no `maxLength`).
2. **The §10 acceptance run** on the operator's feature project — **exactly 6
   requests**: five scenes spanning density (a two-hander dialogue scene; a dense
   multi-reference scene near the 30-image line; an exterior establishing-heavy scene;
   a props-forward scene; a minimal scene) plus exactly one regeneration after a
   canonical-asset replacement. No answer key — the operator's external generation
   tool is the judge; the operator also runs the vendored linter over the six prompts
   (read-only, `--regime block`) and records its findings beside their own, noting
   that the `stale-specs-snapshot` INFO fires after 2026-09-06 by design. **Tiers
   (§14.6 of Phase 3, adopted by §10)**: 5/6 or 6/6 usable without hand-editing passes
   cleanly and makes Step 6 eligible; 4/6 lets the plan land with quality recorded as
   explicitly unresolved and batch deferred; 3/6 or below marks this plan `BLOCKED`.
   Deferral is for unspent gates, never failed ones — but note **Phase 5 is the
   product's primary endpoint**: a deferral here leaves the roadmap's after-Phase-5
   partner-validation gate without its evidence, and the record must say so.

## Contracts (normative)

### A. Task, schema, prompt (design §8.1–§8.2)

- `GenerateScenePromptTask` — drafting child task name `generateScenePrompt` — and
  `RefineScenePromptTask` — review child task name `refineScenePrompt` — share schema
  version 2 (`scene-prompt-v2.schema.json`). Both run through the existing
  `StructuredJobRunner` in child mode; `ScenePromptRun` owns the parent and one atomic
  apply. Any needed generic-runner lifecycle change remains a STOP.
- `prompt(for:)` prepends the instructions and wraps the §8.2 payload in
  `<scene-prompt-input>`, wrapper outside the digest; `jobs.input_sha256` equals the
  builder snapshot's digest, one digest always.
- **Instructions route through the selected descriptor, never a hardcoded
  tree** (design §3.7, fifth revision — the swappability §14.6 cashes): they
  name the selected descriptor's materialised entry, and its routing file
  when the descriptor carries one; pre-answer the skill's intake questions
  (mode, duration, aspect ratio, **resolution** — never silently defaulted
  for Seedance); carry the override clause (JSON output contract wins);
  and end with the standard prompt-injection clause verbatim. Three
  routing branches, one fixture each: **bundled default +
  `seedance_2_5`** additionally pins the Seedance 2.5 sub-skill and its
  omni-reference template (the Plan 016 posture that keeps the session
  off excluded sub-skills); **imported skill** names its own entry and
  optional routing file with no assumption that the higgsfield tree
  exists; **`generic`** routes to the descriptor's entry alone, passing
  the profile id and its absent constraints — the skill decides the
  form, and the result is never labeled or validated as
  Seedance-specific (`targetModel` stays opaque).
- Pre-flight (FilmCore-enforced, mirrored by `ScenePromptRunGate`): Asset Ready,
  counted scene, active profile P, custom-skill `tree_sha256` early check, reference
  plan within limit, input within budget. Refused while an extraction or manifest
  bootstrap is non-terminal or paused. No run-once gate; never joins
  `requireNewestRun` (test-asserted).

### B. Validator (design §8.3)

- `ScenePromptValidator` (`version = 1`), codes in order: `wrong_schema_version`,
  `empty_prompt_body`, `oversized_prompt_body` (64 KB), `control_characters`,
  `missing_reference_designator` / `unknown_reference_designator` — the
  **coverage contract, universal under every profile** (references stay
  traceable whatever the syntax) — then **the declaration-line rule,
  applied only under a profile that declares the declaration grammar**
  (design §8.3, sixth revision; `seedance_2_5` does, `generic` declares
  coverage-only): for every satisfied designator k, at least one line
  whose designator set is exactly `{@Image k}` carrying one of the four
  fidelity terms and a `do not` exclusion; `bulk_reference_statement`,
  `missing_reference_fidelity`, `missing_reference_exclusion` — then
  `age_written` (the three shipped numeric patterns, universal), and
  `invalid_duration`, `invalid_aspect_ratio`, `invalid_resolution`
  (profile-checked; `generic` skips all three). Fixture pairs both
  directions for every code, including a bulk statement naming every
  designator on one line **and one non-Seedance-syntax prompt that
  passes coverage-only under `generic` and fails the grammar under
  `seedance_2_5`**.
- The shipped `AssetPromptValidator` stays at coverage-only; lifting the declaration
  rules to asset scale is a recorded follow-up decision, not this plan's edit.

### C. Apply, report, runs (design §8.4–§8.6, §3.9)

- `ScenePromptApplier`, one transaction: step-0 in-transaction input rebuild and
  digest guard (`.scenePromptInputChangedDuringRun`); precondition re-check; **one
  invertible entry** via `attachGeneratedScenePrompt` with citations from the plan the
  digest was computed over; the task-gated `ScenePromptApplyReport` through the
  internal report primitive; in-transaction parent completion with usage. ⌘Z reads
  "Undo Generate Scene Prompt". The §3.9 write surface is test-asserted (journal
  holds exactly the attach).
- Report key-disjointness extends across all report types on `jobs.apply_report`.
- **The atomic imported-skill check**: for a custom skill the coordinator passes the
  stored digest as `expectedTreeSHA256`; the materialiser's staging walk is the
  authority, refusing via `treeDigestMismatch` before any copy or clone. The §10 race
  test mutates the tree after the gate passes and before materialisation.
- Recorded replay: a `scene-prompt-` branch joins the shipped schema-prefix switch,
  materialising the result from the request's own payload, never a canned file.
- Regeneration: same pipeline, new run, new row at max+1. Generate/Update/Regenerate
  activate Plan 020's reserved identifiers and start immediately after preflight.

### D. Disclosure (design §9)

- The one-time §9 disclosure ships verbatim in the disclosure-text pattern: scene
  text, style bible, and production context are sent; images never leave the bundle.
  Continue starts the already-requested run. There is no per-run confirmation.
- Run feedback exposes Context, Connect, Generate, Validate, and Save stages with the
  current operation and cancellation. Seedance fidelity values are rendered as exact
  hyphenated terms; semantic validation tolerates stored underscore or natural-space
  punctuation but still checks each reference's specific derived grade.
- Regenerate/Update immediately replaces the visible current cards with that progress UI
  and scrolls the prompt panel into view. The prior set remains committed until its validated
  successor is saved, and returns if preparation, cancellation, or generation fails.
- Each generated reference declaration uses one explicit line containing the local
  designator, verbatim role, and exact fidelity. A nonempty exclusion adds its complete
  verbatim `do not…` clause; an empty exclusion requires neither a clause nor a placeholder.
  Raw role/fidelity/exclusion failures are translated to actionable UI messages.
- Bundled Seedance runs explicitly name Higgsfield's root, prompt-writing, Seedance core,
  Seedance 2.5, omni-reference, and shared-constraint resources. `sceneText` is transformed
  into a single paste-ready Seedance prompt: complete action and event order become staged
  beats, dialogue stays verbatim in its timed stage, and raw screenplay/wrapper blocks are omitted.
- Scene-only reference semantics keep paired character materials non-overlapping: Face
  Closeup owns the face/head at full preserve, while Headless Full Body owns only
  below-neck build, proportions, wardrobe, and rear hairstyle at partial preserve.
  Sheet layout, duplicate turnaround figures, source crops/backgrounds, and incidental
  location content are explicit exclusions. This renderer amendment bumps
  `ScenePromptInputBuilder.schemaVersion` to 2 and leaves asset-prompt history untouched.
- The generation contract requires the fewest useful stages, one visible change and
  observable end state per stage, Stage-1 spatial anchoring, one exact named camera
  control, dialogue exactly once in its timed stage, foreground-dialogue mixing, positive
  prevention phrasing, and a silent Higgsfield/Seedance preflight before output.

#### 2026-08-31 quality-refinement amendment

- One Generate/Update/Regenerate gesture owns one parent `generateScenePrompt` run and
  one atomic apply. Standard mode, the default, executes one recorded child request whose
  instructions require draft, silent review, repair, and strict final validation. High
  Quality executes that child plus an independent `refineScenePrompt` child, which receives
  canonical input and draft in distinct fields and rewrites the complete result against the
  same materialized Higgsfield resources.
- Only the selected mode's strict final output is eligible for atomic apply. In High Quality,
  a failed or cancelled second pass fails closed; the draft is never a fallback.
- The parent remains the filmmaker-facing run. Every child remains auditable in Jobs; the
  parent records the selected mode, effective model, per-request usage, and timings. The
  progress surface matches the selected one- or two-request path.
- `scene-prompt-refinement-v1.md` is an app-owned task rubric, not a competing skill. It
  detects source inventions, authority overlap, unnecessary stages, camera/framing
  contradictions, infeasible dialogue timing, audio-only visual end states, repetition,
  and profile-setting violations. The selected staged skill remains authoritative, so an
  imported replacement still governs every selected pass without an app change.
- The one-time disclosure states that Standard makes one account-backed request and High
  Quality makes two. Images still never leave the project bundle.

#### 2026-09-02 one-time creative-direction amendment

- Add Direction is a pending instruction for the next generated prompt, not durable scene
  canon. Opening Add Direction always starts blank; saving replaces any unsent direction.
- The run request and step-0 guard include the pending direction. A successful atomic apply
  consumes it, while a failed or cancelled run leaves it available for retry.
- The completed job report retains the exact request digest for audit. The generated prompt
  set records the direction-free post-consumption input digest, so consuming the instruction
  does not make its own result stale. Undo removes the generated result without resurrecting
  an instruction that was already used successfully.

#### 2026-09-03 direction-and-regeneration gesture amendment

- The direction sheet's primary action is **Add Direction and Regenerate** when
  a current set exists, or **Add Direction and Generate** before the first set.
  It saves through the existing journaled direction operation, dismisses the sheet,
  then starts the existing generation flow without another Generate gesture.
- Opening or cancelling the sheet starts nothing. A failed save keeps the editor
  open and starts nothing; saving disables duplicate submission and dismissal.
  The action shares generation's availability checks and does not start a run for
  another selected scene after dismissal.
- First-run disclosure, run checks, quality mode, prior-set history, atomic apply,
  and consumption of direction only after successful generation remain unchanged.
  No harness, approval, schema, or prompt-authoring contract changes are required.
- Verification uses `scripts/build.sh`; no automated test infrastructure or live
  account-backed generation is added.

#### 2026-09-03 stage-local prompt-quality amendment

The owner approved these changes after manually improving a generated scene prompt.
This amendment supersedes the older Audio-only dialogue and fixed opening-time rules;
it changes app-owned task guidance and final validation, not the vendored skill tree.

- Place each source dialogue occurrence once in its timed stage with canonical speaker,
  delivery, addressee, and accompanying action. Localized sound cues belong once beside
  their action; Audio retains ongoing ambience, language, mixing, and music.
- Choose opening time from scene complexity rather than reserving 3–4 seconds. Budget
  speech per stage, reading, physical actions, camera travel, and an explicit final hold
  within the final numbered range. Natural simultaneous speech/motion is not counted twice.
- FilmCore derives ordered dialogue occurrences through the existing FilmScript parser,
  including human screenplay overrides, wrapped lines, cue extensions, and parentheticals.
  FilmBrain validates the complete ordered sequence across cards, correct speaker, brace
  formatting, and stage membership. Missing, invented, altered, reordered, and duplicated
  dialogue fail final validation; deliberate source repetitions remain distinct occurrences.
- A conservative whitespace-word density estimate above 3.5 words/second adds a pacing
  warning to existing card guidance, not a hard failure or a claim of exact timing.
- Camera defines the overall movement; stage-local reveals/reframing specify timing and
  must agree with it. The existing drafting preflight and optional refinement pass review
  camera feasibility, goal/action agreement, physical-object count versus reference count,
  reachable interactions, and the actual closing state. No extra AI request is introduced.
- Remove repetitive setup and optional micro-actions without weakening exact reference
  declarations, identity ownership, or source-required story action. Source changes still
  require a human screenplay override, not a prompt optimizer's decision.
- Schema-2 cards, input encoding/digest, persistence, provider transports, approvals, and
  run lifecycle remain unchanged. FilmBrain's validator version advances to 3. No external
  reference implementation is adopted; the existing parser and validation seams suffice.
- Verify with `scripts/build.sh` only. No automated tests or live generation requests are
  added or run, per the owner's instruction and the repository's prototype-mode policy.

#### 2026-09-03 off-screen speaker-attribution repair

- Final validation accepts canonical speaker names followed by a bounded allowlist
  of parenthesized delivery/source annotations (O.S., O.C., V.O., CONT'D,
  continued, off-screen/off-camera/on-screen, voice-over, broadcast, radio, TV,
  phone/telephone, filtered), case-insensitively. It never accepts a mere name
  substring, arbitrary parenthetical, pronoun, or another speaker's name. Ordered
  verbatim dialogue, stage placement, and atomic apply remain unchanged.
- Draft and refinement instructions keep location/delivery prose after `says`,
  treat role-based screenplay cues as valid names, and preserve source-required
  unseen and broadcast speakers instead of forcing every speaking mouth into view.
- Attribution failures retain the semantic identifier in Jobs and report the card,
  stage, ordered dialogue occurrence, expected speaker, and actual attribution.
  Diagnostic labels are bounded and stripped of invisible controls; dialogue text
  is not copied into the diagnostic.
- Validator version advances to 4. No input/schema/storage, harness lifecycle,
  approval, or vendored-skill changes; verify with `scripts/build.sh`, with no
  automated test infrastructure or account-backed generation added.

#### 2026-09-03 fractional timing and dialogue-line formatting repair

- One shared timing parser accepts finite whole or decimal stage boundaries in
  both timeline validation and dialogue pacing. Stage numbers stay integers;
  consecutive endpoints compare directly without summing or rounding durations.
  Gaps, overlaps, nonpositive ranges, malformed stage headings, repeated totals,
  and duration mismatches still fail. Profile duration settings remain integers.
- Inside a timed stage, a complete staging sentence followed on the same line
  by a canonical speaker attribution is separated with a newline before final
  dialogue validation. No story prose, name, or spoken text is rewritten. The
  attribution must exactly match a source speaker with only the existing allowed
  annotations; title/initial abbreviations are not sentence boundaries.
- Ordered source comparison still rejects wrong speakers, altered, missing,
  invented, or duplicated dialogue, and dialogue outside a timed stage. The
  normalized body is what reaches atomic apply, not just what validation sees.
- Draft and refinement guidance explicitly require standalone attribution lines,
  allow decimal boundaries, and preserve source action subjects and visibility.
  Validator version advances to 5. No schema, storage, harness, approval, or
  vendored-skill changes; use `scripts/build.sh` and no live generation requests.
- Verified with a successful `scripts/build.sh` and 23 temporary, repository-external
  checks linked against the built FilmBrain validator: formatting preservation and
  idempotence, decimal/whole timing, annotations, Unicode, and rejection boundaries.
  No test target, suite, fixture, or user screenplay was added to the repository.

### E. The batch driver (design §8.1, §14.1 — evidence-gated)

- **The eligible set is frozen here** — the design's "eligible set under
  the active profile P" means exactly: counted, Asset Ready scenes where
  P is cataloged **and whose current prompt under P is absent or
  stale**. A fresh current prompt skips the scene (`skippedFresh`) —
  Generation Ready work is never silently regenerated, and Asset Ready
  scenes that actually need preparation are exactly what remains.
  Per-scene thinning before any request: `skippedFresh`,
  `skippedOverLimit` (reference plan over P's limit),
  `skippedOverBudget` (rendered input over budget). Scenes failing the
  base predicate (excluded, or not Asset Ready) never enter the set at
  all. With a custom skill selected, the §8.6 integrity gate is checked
  **once, up front** — failure refuses the whole batch before any
  request, never mid-run.
- One request per eligible scene, sequential; the shared cached skill
  tree is resolved **once per batch** (asserted in unique bytes, Plan
  016's arm-B phrasing) while **a per-run workspace clone is staged for
  every job** — the shipped materialiser returns paths inside each run's
  clone, so one materialisation cannot feed later workspaces and the
  per-job clone is the contract, not an inefficiency;
  cancellation stops after the in-flight job; partial failure fails that
  scene and continues, each applied prompt staying applied in its own
  transaction; the driver owns no transaction; one confirm sheet names
  the **exact post-thinning count**, never the raw set size. **Skipped
  whole while the §14.1 gate is unmet, and nothing batch-shaped
  renders.**

## Steps

1. **Task, schema, prompt, gate.** Contract A on the recorded branch, with the gate
   battery (every pre-flight refusal, the bootstrap-idle refusal, the
   `requireNewestRun` exclusion).
2. **Validator.** Contract B with the full fixture matrix.
3. **Apply, report, runs.** Contract C: the step-0 guard determinism test, the write-
   surface assertion, the key-disjointness extension, the replay branch, the
   **race test at the materialiser boundary**, regeneration.
4. **Disclosure and wiring.** Contract D; Generate/Regenerate come alive behind
   `ScenePromptRunGate`; headless twins for the run states; the Jobs surface gains the
   scene-prompt arm through the existing `+PromptRun`-pattern coordination.
5. **Live gates.** The schema probe, then the §10 acceptance run, each with operator
   approval — or the recorded deferral, honestly stated (see the live-gate policy's
   endpoint note).
6. **The batch driver (evidence-gated).** Contract E, only if the acceptance run
   scored ≥ 5/6 *and* the owner approved the counted spend; otherwise skipped whole
   with the skip recorded. Tests: one per exclusion (`skippedFresh`,
   `skippedOverLimit`, `skippedOverBudget`, base-predicate non-entry,
   the up-front integrity refusal) plus a mixed-project count test — a
   fixture spanning fresh, stale, promptless, over-limit, excluded, and
   not-Asset-Ready scenes whose confirm-sheet count is asserted exactly.
7. **Record-keeping.** The acceptance (or deferral) record in
   `docs/IMPLEMENTATION_NOTES.md`; flip the README row; update in-file `## Status`
   blocks for Plans 018–021.

## Verification

- `./scripts/verify.sh` passes (environmental-flake posture).
- `./scripts/check-docs.sh` passes.

## Done criteria

- [ ] An Asset Ready scene generates a validated, cited, digest-stamped prompt through
      the skill on the recorded branch; regeneration supersedes by history.
- [ ] The declaration-line rule demonstrably fails the bulk statement and passes the
      compliant block.
- [ ] The imported-skill race test refuses at the materialiser boundary.
- [ ] Disclosures render verbatim; every run is confirmed and gated.
- [ ] The acceptance run is performed and recorded, or its deferral is recorded with
      the endpoint consequence stated; the batch driver's state matches the §14.1
      gate honestly.
- [ ] §14.1, §14.3, §14.4 still read ACCEPTED; the README row is flipped per the tier
      outcome.

## STOP conditions

1. The PHASE5 hash differs *and* §3.7, §8, §9, or §14.1 changed.
2. Any change to `StructuredJobRunner`'s lifecycle appears necessary.
3. `attachGeneratedScenePrompt` (Plan 019's signature) proves insufficient — report,
   do not widen silently.
4. A recorded run's apply cannot make the step-0 guard deterministic, or the
   one-digest identity fails.
5. The declaration-line rule cannot distinguish the bulk statement from compliant
   prose without false-failing the skill's real output — report with the failing
   fixture; do not weaken the rule silently or hand-tune the skill payload.
6. A real scene's rendered input exceeds the budget — §11 defers chunked inputs
   deliberately; stop rather than inventing a split.
7. Acceptance ≤ 3/6 (4/6 is explicitly not a STOP).
8. Work expands into a provider, credential storage, shot planning, or Phase 6
   surfaces.
9. A verification command fails twice after one reasonable scoped correction.

## Maintenance notes

- The generation workspace accepts two explicit input corrections before a run: a
  journaled scene-local screenplay override (without mutating the imported script) and
  Add Image Reference, which links an approved project image into the scene plan. Both
  flow through `ScenePromptInputBuilder` and change its digest.
- Seedance 2.5 final-output validation requires a Higgsfield pacing plan: one declared
  total matching `settings.durationSeconds`, consecutive stage ranges from zero through
  that total, and explicit canonical-name attribution for every screenplay dialogue line.
  Timing remains a pacing budget rather than a promise of frame-accurate edits.
- Widening `age_written` or the fidelity-term list is a validator version bump, never
  a schema change.
- The linter stays operator-side; if a future pass wants it app-adjacent, that is a
  reopened §14.3, not a quiet addition.
- When the vendored skill tree is updated, re-run the Plan 018 catalog agreement test
  and this plan's declaration-line fixtures against the new templates before bumping
  the pinned commit in `PromptSkills/README.md`.
