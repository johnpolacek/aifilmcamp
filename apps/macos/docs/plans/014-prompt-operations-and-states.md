# Plan 014: Prompt operations, states, and interactions (Phase 3a)

> **Executor instructions**: Read `docs/PHASE3_DESIGN.md` in full first. This plan implements
> its §6 (the amended recompute activating `prompt_ready` and `in_progress`), §7.1–§7.3 (the
> six operations, their inverses, and the Phase 2 interactions), and the §7.4 guard wiring —
> the engine half of the workshop, with **no UI** (Plan 015 builds the workshop over these
> operations) and **no AI** (Plan 016). `attachGeneratedPrompt` is built and tested at engine
> level here; Plan 016's `applyAssetPromptRun` is its only production emitter, and nothing in
> the app emits it after this plan.
> Follow the steps in order, run every verification command, honor every STOP condition.
> Requires Plan 013 `DONE`. When complete, set this plan's row in `docs/plans/README.md` to
> `DONE`.
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
> Expected: all five print `OK`. If the PHASE3 hash differs, stop for reconciliation when §6,
> §7, §13.1–§13.2, §13.10, §14.2, §14.5, or §14.7 changed; §13/§14 acceptance recorded in the
> status prose alone is re-pinned, not a stop. The OVERVIEW pin guards the `#asset-states`
> vocabulary this plan's recompute stores (the Plan 011 precedent); **Plan 015 edits OVERVIEW
> and sweeps this pin in the same commit**, so after 015 lands this block carries the new
> value.
>
> **Live gates: none.** Nothing here calls Codex; every command must pass with no network. A
> step that appears to need a live call is a STOP condition, not a deferral.

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: L–XL, approximately 10–13 focused engineering days
- **Risk**: HIGH; six operations each needing a byte-identical inverse round-trip, a
  source-breaking recompute widening touching every caller, and capture-list growth inside
  five shipped operation families under §4.3's symmetric SET-NULL rule
- **Depends on**: 013
- **Category**: feature / architecture / tests
- **Planned at**: commit `a861a00`, 2026-08-22; design hash in the drift check

## Current state

- Plan 013 shipped schema v5, the domain types, the engine maps and orders,
  `requireRequirementUnlocked`, the reads (`generationBlockedBy`, `plannedDependencies`,
  `currentPrompt` with derived staleness), the report doors, and `AssetPromptInputBuilder`
  with its golden fixture. Prompt rows exist only via test SQL; no operation writes them.
- `AssetStatusRecompute.Inputs` is a five-field public struct with a public memberwise init —
  §6.1's two new inputs are a source-breaking API change for every caller, budgeted here.
- Plan 010's operation files are the templates: `MutationEffect`-returning statics, no
  transaction opened; the reentrancy test's `Editing/*.swift` glob covers the new file
  automatically (§3.8).

## Owner gates (design §14 — accepted 2026-08-22, recorded in the design)

- **§14.2 (Empty Slot vs prompt history) — accepted as recommended**: `deleteAsset` spares
  prompts and composes a fresh anchor (contract C), with the §6.3 re-anchor test rows in
  Step 3 (the confirm string is Plan 015's).
- **§14.5 (human prompt authoring/editing) — accepted as recommended**: this plan **is**
  that decision (`createPrompt`/`setPromptBody` are what make 3a self-sufficient); without
  it §6's states would be unreachable without Plan 016.
- **§14.7 (what sets In Progress) — accepted as recommended**: an explicit journaled gesture
  (`markAssetInProgress`), refused once versions exist, with Copy Prompt left a pure read
  (contract B's row for it, and Plan 015's Copy Prompt purity).

## Contracts (normative)

### A. The amended recompute (design §6.1, §6.3 — §13.1's owner delta, built as specified, and built first)

- `AssetStatusRecompute` becomes §6.1's seven rules — the two new rows strictly below
  Phase 2's four, still the only writer of `assets.status`, still a pure function of stored
  rows (never the derived prompt staleness), still run at the end of every
  asset/version/prompt operation and agreed-with by construction on the inverse path. The
  `Inputs` struct gains the marker and the prompt count — the budgeted source-breaking
  change: both `status(...)` overloads, every caller, and the db-backed
  `recompute(requirementID:)` gain the two inputs. Built **ahead of the operations** against
  SQL-seeded prompt and marker rows, the Plan 010 precedent — which is also what lets Step 2's
  operations verify against the amended function rather than the five-rule one.
- The marker/version mutual exclusion has all three legs (§6.1): `importAssetVersion` clears
  `in_progress_since` in its transaction; `markAssetInProgress` is refused while any version
  row exists; `combineRequirements` clears a surviving asset's marker whenever the combine
  moves version rows under it (snapshotted for the hand-ordered inverse). Legs one and three
  land with contract C; the refusal with contract B.
- **§6.3's table is the test spec, whole** — its rows join Phase 2's as an exhaustive table
  test extending Plan 011's, cross-products included per §10's state-machine list, **plus the
  three §6.3 rows §10's list does not restate**: `deletePrompt` (last prompt, no versions, no
  marker) → `needed`; `deletePrompt` (last prompt, marker standing) → `in_progress`; and
  `clearAssetInProgress` → rules 1–4 if they govern, else rules 6–7. The renumbered Phase 2
  fall-through rows are re-asserted, and the approved-version invariant after every new op.
  (The rule-level cases run in Step 1 over seeded rows; the operation-driven walk completes
  in Steps 2–3 once the operations exist.)

### B. Operations (design §7.2, verbatim — the table there is the contract)

- Every §7.2 operation exists as an `EditOperation` case with the inverse, preconditions, and
  notes written there, dispatched through `EditPrimitives.mutate`'s exhaustive switch, named
  in `displayName` (so the Edit menu reads "Undo Generate Prompt", "Undo Write Prompt" —
  §5.9), `isInvertible = true` for all six, `compoundChildren = nil` (composition at the
  `performGroup` call site, §7.4). New file `Editing/PromptOperations.swift`.
- **Composition shape (§7.1)**: `createPrompt` and `markAssetInProgress` perform as a
  `performGroup` of `[createAsset (when no asset row exists), <op>]`; the group inverse is
  the children's inverses in reverse order, `removeAssetRow` last — undo of a first gesture
  on a bare requirement leaves **no asset row** (displays Needed).
- **`attachGeneratedPrompt`'s signature is pinned here**, because Plan 016's applier consumes
  it and the design deliberately leaves the parameter list to the plans:
  `attachGeneratedPrompt(promptID:requirementID:body:targetModel:guidance:inputDigest:inputFormatVersion:skillIdentity:)`
  — `inputDigest` and `inputFormatVersion` are **supplied by the caller** (§8.4 step 2: the
  digest is the applier's step-0 rebuilt value, never re-rendered by the op — `createPrompt`,
  by contrast, computes its own in-transaction); `skillIdentity` carries the
  `AssetPromptSettings` skill triple (id, entry path, entry SHA); the **citation rows are
  derived in-op** from the §3.3 shared ordering function over the **rendered references** —
  the satisfied subset of the planned dependencies, densely numbered `@Image 1…N`, never the
  unsatisfied rows — capturing `sha256` and `display_name` at build time; ordering,
  numbering, and capture live in the operation, not the applier. It is the engine-internal
  case with §3.7's fixed `ai` provenance on both its own asset-row and prompt-row inserts
  plus the citation rows in one mutate, born `accepted` through its own insert (never the
  shared `insertProvenance`); the shipped `createAsset` stays human-only and is not composed
  on this path. Engine-tested here
  (correct fixed provenance on both rows, no `requireHuman` throw, citations in §3.3 order,
  snapshot inverse removing all its inserts together); no production emitter exists until
  Plan 016.
- Each operation calls `requireRequirementUnlocked` before mutating, resolving its
  requirement per §7.4 (`setPromptBody`/`deletePrompt` through the prompt row,
  `clearAssetInProgress` through the asset), and **the requirement joins each operation's
  affected set** — new work at each call site (§7.4). Accepted and active are separate checks
  with separate refusals (§5.8): new `ProjectStoreError` cases
  `.promptRequiresAcceptedRequirement`, `.inProgressRequiresNoVersions`, and
  `.promptRequirementBlocked` (thrown by `attachGeneratedPrompt` from `isGenerationBlocked`;
  `createPrompt` is deliberately not blockage-gated, §3.3) — **these three carry §5.8's copy
  verbatim, asserted character for character in a FilmCore test** (the other three §5.8
  strings are Plan 016's, per Plan 013's stated split); inactive and lock refusals reuse the
  shipped strings.
- **The pinned prompt-number walk (§7.2)**: `prompt_number` = max + 1 in-transaction; deleting
  the newest prompt frees its number; a refused inverse is `.inverseNoLongerApplicable` via
  the built `wouldCollide` (Plan 013 registered the pair). The test sets the collision up
  honestly — clear the undo stack with a non-invertible gesture, reclaim the number, then
  drive the journal-level inverse — and asserts the nulled lineage stamps stay gone and tags
  resolve by id throughout. The later-human-edit consequence is tested: `approveVersion` on a
  citing version blocks undoing a `deletePrompt` (`conflictsWithLaterHumanEdit`).
- Body validation on create/edit: non-empty, ≤ 32 KB UTF-8, control-character-free;
  `setPromptBody` is current-row-only, converts `source` to `human` (skill provenance
  survives on `created_source`), and leaves `input_digest` untouched; `deletePrompt` accepts
  any row, snapshots the prompt row, citations, and the citing `asset_versions.prompt_id`
  values it nulls. (There is no reference-attribute operation: role, exclusion, and
  fidelity are derived at render time, owner-decided 2026-08-22 — design §3.3.)

### C. Interactions with Phase 2's operations (design §7.3, verbatim — §4.3's symmetric SET-NULL snapshot rule binds every bullet)

- **`importAssetVersion` gains `promptID: UUID?` at all three shipped layers** (session door,
  engine case, static op), inserted before the trailing `restoring:`; a non-nil id must name
  a prompt of the same requirement; the workshop's Import Result and drop (Plan 015) will
  pass the current prompt's id, **every other call site passes `nil`** — after this plan,
  every existing call site passes `nil`, so behavior is unchanged until Plan 015 wires the
  workshop; `MediaImportSummary` carries the stamp; the op clears `in_progress_since`; the
  inverse restores the asset row's marker from snapshot.
- **`deleteAsset`** keeps its destructive scope, leaves prompt rows alone, and **composes a
  fresh anchor row when prompts remain** (§14.2's recommendation, delivered — the emptied
  slot honestly reads `prompt_ready`); with no prompts, nothing is composed. Still
  non-invertible.
- **`deleteVersion` gets no capture and no sweep — a normative prohibition** (§7.3): it
  destroys a row that may carry a `prompt_id` stamp, and the lineage record dying with the
  row is the operation's stated meaning. Do not add a citation capture here.
- **`approveVersion` needs no prompt-aware change** (§7.3), and the reciprocal fact is
  tested: approving a different version on D flips the derived staleness of every dependent's
  prompt by digest alone, with no fan-out write and no new code in `approveVersion`.
- **`combineRequirements`**: prompt rows do not move; the survivor's marker clears when
  version rows move (contract A's third leg, snapshotted); the moved versions' lineage stamps
  make §4.3's rule load-bearing on a later source hard delete.
- **`mergeEntities`' name-collision sub-rule, lifted out because it is the hardest capture in
  §7.3**: when the collision survivor is chosen, the losing requirement's prompt rows are
  captured in the merge payload and dropped with it, and the §4.3 rule snapshots the
  re-pointed asset's version stamps before the cascade nulls them — `unmerge` restores all of
  it byte-identically, test-asserted. The moved requirements' prompts all read stale
  immediately (the merge changes §8.2 inputs), which is correct and asserted.
- The capture lists of `deleteRequirement`/`restoreRequirement`,
  `deleteEntity`/`restoreEntity`, and `mergeEntities`/`unmerge` grow per §7.3: prompt graphs,
  citing `asset_versions.prompt_id` values (which may live under another requirement's asset
  after a combine), and every other prompt's citation rows the cascade would SET NULL
  (cross-entity references are first-class) — byte-identical restores asserted, including
  §10's cross-entity citation-capture walk. `splitRequirement` births promptless;
  **`splitEntity` leaves prompts untouched** (requirements stay on the source, Phase 2 §7.4);
  `reclassify` carries variant prompts riding `requirement_id`, and the digest makes them
  read stale (asserted, correct per §7.3).
- **`canReplaceScreenplay` is not widened** (§7.3's no-widening chain), with only the built
  gate's comment rationale touched up; both direction tests from §10 (a prompt on an accepted
  `ai` requirement refuses Replace with and without versions; rejected-requirement-only
  prompts permit it). The extraction-run and manifest-run reverts cannot strand a prompt —
  §7.3's two chains, each with its test.
- A bundle close/move/reopen keeps prompts, citations, and lineage tags intact (Plan 011's
  discipline re-asserted over the v5 graph).

## Target file layout (additions, changes)

```text
Packages/FilmCore/
  Domain/EditOperation.swift (+cases), Editing/ PromptOperations.swift (new),
  AssetStatusRecompute.swift (seven rules, Inputs change), AssetOperations.swift
  (importAssetVersion promptID + marker clear; deleteAsset re-anchor; Replace comment),
  RequirementOperations.swift (combine marker clear, capture growth),
  EntityOperations.swift + MergeSplitOperations.swift + EntityRequirementInteractions.swift
  (§7.3 capture growth), Storage/ProjectStoreError.swift (+three cases, §5.8 copy),
  Storage/ProjectSession+Media.swift (promptID at the session door),
  ProjectTools.swift + ProjectTools+Editing.swift (+§7.2 wrappers)
  Tests/ RecomputeV5TableTests, PromptOperationTests, PromptNumberWalkTests,
  PromptRefusalCopyTests, PromptInteractionTests, PromptCaptureTests,
  ReplacePromptGateTests, RevertStrandTests, PromptMoveTests
AI Film Camp/ compiles unchanged (the window model's importAssetVersion call site passes nil
  until Plan 015); no view is added or edited
project.yml unchanged
```

`scripts/eval-inputs.txt` is untouched, and no file it lists is edited by this plan.

## Steps

### Step 1: The amended recompute

Contract A's function, `Inputs` widening, and rule-level table cases over SQL-seeded rows.

```bash
swift test --package-path Packages/FilmCore
```

Expected: the seven-rule function passes its seeded table cases including the three
`deletePrompt`/`clearAssetInProgress` rows and the renumbered fall-throughs; every existing
`AssetStatusRecompute` caller compiles and passes against the widened `Inputs`; no Plan
010/011 state-machine assertion regresses.

### Step 2: The operation family and the guard wiring

Contract B.

```bash
swift test --package-path Packages/FilmCore
```

Expected: every §7.2 op's apply + inverse round-trips to byte-identical snapshot digests; the
actor × lock × op matrix (whole-locked requirement refuses all six for both actors); the
prompt-number walk and
later-edit conflict verbatim; first-gesture composition undone cleanly (no asset row,
displays Needed); `attachGeneratedPrompt`'s pinned signature, fixed provenance, and derived
citations at engine level; the three refusal strings asserted character for character.

### Step 3: Phase 2 interactions and verification

Contract C, completing contract A's operation-driven table test.

```bash
swift test --package-path Packages/FilmCore
./scripts/verify.sh
```

Expected: all suites exit 0 (the app compiles with no view change; a UI-suite failure here is
compared against the recorded environmental flake first); import stamps lineage and clears
the marker; capture growth restores byte-identically including the merge-collision and
cross-entity citation walks; Replace refuses/permits per §7.3 both ways; neither revert walk
strands a prompt; the move/reopen walk resolves everything. Update `docs/plans/README.md`,
and record the §14.2/§14.7 build-as-recommended posture in `docs/IMPLEMENTATION_NOTES.md` if
the owner has not yet recorded acceptance.

## Done criteria

- [ ] `./scripts/verify.sh` exits 0; the recompute is §6.1's seven rules, still the only
  writer of `assets.status`; the §6.3 table test passes exhaustively, its three
  non-§10-restated rows included; the marker/version exclusion holds on all three legs.
- [ ] Every §7.2 operation exists with its stated inverse, guard, refusal copy
  (character-asserted), and recompute call; the prompt-number walk and later-edit conflict
  behave per §7.2; `attachGeneratedPrompt` ships with the pinned signature, §3.7's
  provenance, in-op derived citations, and no production emitter.
- [ ] Every §7.3 interaction ships as written — `promptID:` at three layers with all existing
  call sites passing `nil`, the `deleteAsset` re-anchor, combine's marker clear and
  non-moving prompts, the merge-collision capture, the `deleteVersion` no-capture
  prohibition respected, the unwidened Replace gate, the two revert-strand chains — all
  tested.
- [ ] **The §14 decisions this plan implements carry the owner's recorded acceptance**:
  §14.5 (human prompt authoring and editing — `createPrompt`/`setPromptBody`) and §14.7 (In
  Progress semantics — the explicit journaled gesture) are **accepted 2026-08-22, as
  recommended**, recorded in design §14; confirm the design still reads that way before
  flipping this plan's README row to `DONE`. (§14.2's `deleteAsset` branch, accepted the
  same day, is built here; its confirm copy belongs to Plan 015.)
- [ ] No UI file was added or edited; no AI path exists; `docs/plans/README.md` marks
  Plan 014 `DONE`.

## STOP conditions

- The `docs/PHASE3_DESIGN.md` hash differs and §6, §7, or the named §13/§14 items changed.
- The product owner declines §14.5 (human prompt authoring) — reconcile the design before
  building anything; 3a's self-sufficiency claim collapses without it.
- Any §7.2 inverse cannot restore byte-identical tables (report the differing table and
  column rather than weakening the digest assertion).
- The `Inputs` widening breaks a Plan 010/011 recompute or state-machine test in a way one
  scoped correction does not fix.
- `attachGeneratedPrompt`'s pinned signature proves insufficient for §8.4's apply as
  designed (report the missing parameter; changing the signature after this plan is `DONE`
  is a recorded contract change, not a silent edit).
- A verification command fails twice after one reasonable scoped correction — for UI suites,
  first compare against the recorded environmental flake and rerun on an idle machine.
- Work expands into the workshop UI, identifiers, or confirm copy (Plan 015), into
  generation, materialisation, batch runs, or disclosures (Plan 016), into Phase 4 readiness
  dashboards or deep links, or into Phase 5 scene prompts, packages, or export.

## Maintenance notes

- The recompute is deliberately ahead of the workshop again (the Plan 010/011 seam): Plan 015
  surfaces these states and must not redefine the function; Plan 016 emits
  `attachGeneratedPrompt` and must not alter its signature.
- Keep the §14.2 and §14.7 reversal seams: the re-anchor is one `deleteAsset` branch; the In
  Progress semantics are one gesture. A reversal after `DONE` is a small follow-on, not a
  redesign.
