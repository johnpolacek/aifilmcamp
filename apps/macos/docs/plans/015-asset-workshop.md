# Plan 015: The asset workshop (Phase 3a)

> **Executor instructions**: Read `docs/PHASE3_DESIGN.md` in full first. This plan implements
> its §5 — the per-requirement workspace as a first-class place, over Plan 014's operations —
> and the §13.3 OVERVIEW delta. **No AI is involved anywhere in this plan**; after it, every
> §6 state is reachable in the app with a hand-written prompt and no model in the loop (§2).
> Generate and Regenerate render disabled with their enablement plumbing in place; Plan 016
> wires them.
> Follow the steps in order, run every verification command, honor every STOP condition.
> Requires Plan 014 `DONE`. When complete, set this plan's row in `docs/plans/README.md` to
> `DONE`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   90dc7842e286b2bbf556a02384096448694d4a698fd24f64a3cdc5ebd4fcb3d7 docs/PHASE3_DESIGN.md \
>   84c3599561dac60fd02d00d8a3d6a564558bac340fb5988d8bcc83868748ff68 docs/PHASE2_DESIGN.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all four print `OK`. If the PHASE3 hash differs, stop for reconciliation when §5,
> §6.2, §13.3, §13.9–§13.10, §14.2, §14.5, or §14.7 changed; §13/§14 acceptance recorded in
> the status prose alone is re-pinned, not a stop. This plan deliberately does **not** pin
> `docs/OVERVIEW.md`, because its Step 3 edits it (the Plan 010 ROADMAP precedent); the
> pinning plans — 002–009, 011, 013, 014, and 001 by hand — are swept in that same commit.
>
> **Live gates: none.** Nothing here calls Codex; every command must pass with no network. A
> step that appears to need a live call is a STOP condition, not a deferral.

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: L–XL, approximately 10–13 focused engineering days
- **Risk**: HIGH; a master–detail restructuring of the shipped Manifest section, a wholesale
  re-host of exercised UI with an absolute no-identifier-live-twice rule, roughly twenty new
  identifiers with mandatory headless twins, and the documented environmental UI-runner
  flake standing over all of it
- **Depends on**: 014
- **Category**: feature / ui / tests
- **Planned at**: commit `a861a00`, 2026-08-22; design hash in the drift check

## Current state

- Plans 013–014 shipped the storage, reads, and the full operation surface: the six prompt
  operations, the amended recompute, `promptID:` on import (every call site passing `nil`),
  and the §5.8 refusal strings. The app compiles unchanged; no workshop exists.
- The built shell is two columns plus an inspector: the Manifest section's detail is
  `ManifestListView` (the requirement list), its inspector `RequirementInspectorView`
  hosting `AssetSlotView`. The shipped slot identifiers are exercised by
  `Phase2AssetUITests`; `addVariantRequirementButton` lives in `ManifestListView` and is
  clicked at three `Phase2ManifestUITests` sites and one `Phase2AssetUITests` site;
  `requirementBlockedBadge` and `requirementStaleBadge` live in `RequirementInspectorView`
  and are exercised by no UI test directly.
- `docs/IMPLEMENTATION_NOTES.md` records the environmental UI-test flakiness and that
  Plan 012's UI suites landed unexercised — §5.9's headless twins are the assertions that
  must carry this plan.

## Owner gates (design §14 — accepted 2026-08-22, recorded in the design)

- **§14.2 (Empty Slot vs prompt history) — accepted as recommended**: the operation behavior
  is Plan 014's; this plan owns the confirm string, and §5.8's decided copy — "Prompts are
  kept." — is the one contract C ships.
- **§14.5 (human prompt authoring/editing) — accepted as recommended**: the Write Prompt
  sheet and body editing are this plan's surfaces for Plan 014's operations.
- **§14.7 (what sets In Progress) — accepted as recommended**: Copy Prompt is a pure read,
  Mark In Progress an explicit gesture — contract B's Copy Prompt bullet and its twin tests
  are what hold that line.

## Contracts (normative)

### A. Placement and the re-host (design §5.1, §5.9's re-host list — per-identifier disposition stated so no collision is discovered mid-build)

- The Manifest section's content area becomes an **in-content master–detail**: the
  requirement list narrows to a master pane and `AssetWorkshopView` renders beside it for
  the selected requirement. No new window, no new `ProjectSection` case, no third split
  column.
- **`AssetSlotView` moves out of the inspector into the workshop wholesale**, every shipped
  identifier riding with it verbatim — the full §5.9 re-host list, which after the design's
  reconciliation names all of: `assetSlot`, `assetImportButton`, `assetVersionRow`,
  `assetVersionThumbnail`, `approveVersionButton`, `rejectVersionButton`,
  `deleteVersionButton`, `assetNotesField`, `assetStaleBadge`, `markAssetCurrentButton`,
  `revealVersionButton`, `deleteAssetButton`, `rejectAssetButton`, `unrejectAssetButton`,
  `unrejectVersionButton`, `assetVersionDamagedBadge`, `assetVersionsEmptyText`,
  `saveAssetNotesButton`. Reused, not duplicated; no `_<n>` suffixes added to shipped names.
- The three re-host-list identifiers **not** inside `AssetSlotView`, dispositioned one by
  one: **`requirementBlockedBadge` and `requirementStaleBadge` move** from
  `RequirementInspectorView` into the workshop header (§5.2's badge row; no UI test targets
  them directly, so the move costs headless-twin updates only);
  **`addVariantRequirementButton` moves** from `ManifestListView` into the workshop header
  menu (§5.2's "New Variant Requirement…"), and the four UI-test call sites re-target —
  `Phase2ManifestUITests` (three sites, which now select a requirement so the workshop
  header is present before clicking) and `Phase2AssetUITests` (one site). Both suites are in
  this plan's file layout and Step 1's expected results.
- The manifest inspector retains only the requirement-review surface (Plan 010's), which
  does not overlap. **No shipped identifier is ever live in two places at once** — an
  absolute rule, checked by grepping the view code for each moved identifier's single
  remaining host before Step 1's verification runs.

### B. The workshop surfaces (design §5.2–§5.7, in the sketch's order)

- **Header and Used In (§5.2)**: "entity name — requirement name", tier and necessity
  badges, the OVERVIEW state (`workshopStatusBadge`; no asset row displays Needed), the
  asset stale badge with reason and Mark Current, **and the drift badges of Phase 2 §5.3**;
  the header menu offers New Variant Requirement… (the moved shipped flow) and Empty Slot;
  Used In lists scenes with jump-to-scene.
- **References (§5.3)**: one row per **planned dependency** in §3.3 order — satisfied or
  not — showing class and the derived role/exclusion/fidelity
  (`referenceAttributesLabel_<position>`), rendered **read-only as computed** from §3.3's
  rules tables — there is no per-edge editor (owner-decided 2026-08-22; §3.3's stated
  trade: a correction lives in the prompt body, and a regenerate reverts it behind the
  §5.8 confirm) — and remove via the shipped `removeDependency`. **The designator is shown
  on satisfied rows only** (`referenceDesignator_<position>`, the `@Image k` label of §3.3's
  **rendered references**, densely numbered across the unsatisfied rows and never re-derived
  in a view), beside the referenced approved image's thumbnail with Reveal; an unsatisfied
  row renders `referenceUnsatisfiedMarker_<position>` — the "no approved version yet" marker
  naming the dependency — **in the designator's place**, and carries no number.
  `<position>` is the row's index in the planned dependencies and is deliberately **not**
  the `@Image` number (§5.9). Add Reference opens the project-wide approved-requirement picker
  (`addDependency`, cycle check); Reveal All References selects every satisfied reference's
  file in one Finder window. Ordering is never hand-editable (§11).
- **The prompt panel (§5.4)**: current prompt body (selectable, editable via
  `setPromptBody`, current row only), target model and guidance lines, skill identity, the
  prompt-stale badge ("Prompt built from earlier inputs — Regenerate"), the history
  disclosure, per-row delete (current and history alike), Write Prompt (the `createPrompt`
  sheet — body, optional target-model line), and the empty state. **Generate and Regenerate
  render per §5.8's shown-when rules but disabled**, their enablement plumbing (accepted,
  active, not `isGenerationBlocked`, not whole-locked) in place on the window model with the
  run-gate condition left for Plan 016.
- **Copy Prompt and In Progress (§5.5)**: Copy Prompt writes the current body to
  `NSPasteboard.general` — a pure read, no mutation, no journal entry (§14.7); Copy Prompt
  with Guidance shown whenever a current prompt exists, enabled when `guidance` is
  non-empty, appending under a `---` separator; Mark In Progress / Clear In Progress through
  Plan 014's operations.
- **Versions (§5.6)**: Import Result through the shipped single import door **now passing
  the current prompt's id as `promptID:`** (the one non-nil call site; every other surface
  stays `nil`); the import clears the marker; the version grid with capped-decode
  thumbnails, status, approve/reject/delete, the lineage tag ("from prompt 3", resolved by
  id), **per-version notes** (`versionNotesField_<version_number>` — the control Plan 011
  deferred to this workshop), asset notes under the grid, the approved version called out
  last; drag/drop via `.dropDestination(for: URL.self)` filtered by the shipped
  `acceptsDroppedImage(_:)` (no new predicate) and asserted headlessly; Create Variation =
  more candidate versions of the same slot, a new look = New Variant Requirement (§13.9).
  Panels and fixtures are the shipped automation pattern — no fixture work item exists.
- **Make Canonical (§5.7)**: `approveVersion` pointed at a non-approved version, no new
  operation, with the dependents confirm from contract C.

### C. Enablement, refusal surfacing, and confirm copy (design §5.8 — split by owner, because three refusal strings and two confirms are Plan 016's)

- §5.8's enablement table ships whole — every rule decided by reads on the window model,
  never a view guessing; accepted and active asserted independently; locks via
  `RequirementDetail.locks`; disabled controls carry the reason as help text; a `proposed`
  requirement renders the workshop read-only except **Accept, Reject, and Import Result /
  drop** — the import is §5.8's one intentional strong-acceptance exception and composes the
  implicit accept exactly as Phase 2's inspector import does, while every prompt operation
  still refuses until the requirement is explicitly accepted (§5.8, §13.10). The UI walk and
  its headless twin assert both halves. The Generate /
  Regenerate rows ship as plumbing with the run-live condition stubbed false-safe (greyed
  with Plan 016's gate reason once 016 lands).
- Refusals surface FilmCore's strings **verbatim** through `runEdit` (§3.8) — Plan 014's
  three new strings and every shipped one; the three 016-owned strings
  (`.assetPromptInputOverBudget`, `.assetPromptInputChangedDuringRun`,
  `.promptRunRequiresIdleBootstraps`) do not exist yet and no placeholder is invented.
- **This plan's confirm strings, shipped verbatim from §5.8's block and asserted character
  for character in a new `WorkshopCopyTests` headless suite** (the design calls these the
  workshop's highest-stakes strings, so they get the `ManifestDisclosureText` treatment — a
  support type, out of the views): Empty Slot ("… Prompts are kept.", the §14.2 string);
  Delete prompt, current and history variants; Delete version (Phase 2's copy, unchanged);
  Make Canonical with dependents ("N derived assets will be marked stale."). The
  **Regenerate-over-human-prompt and Batch confirms are Plan 016's** (§8.7, §9) and are not
  built here.

### D. Identifiers, mitigations, and twins (design §5.9, verbatim)

- The new identifiers exactly as §5.9 lists them (`assetWorkshop` through
  `versionNotesField_<version_number>`); every named container carries
  `.accessibilityElement(children: .contain)`; at most one `confirmationDialog` per view,
  each hung off a distinct anchor; every workshop dialog built with `presenting:`; every
  operation's `displayName` visible through the undo menu mirror.
- **Headless twins are mandatory**: every workshop UI assertion has a
  `ProjectWindowModelTests`-style twin driving the same window-model command; the
  drop-accept predicate and import are asserted headlessly; UI suites follow the shipped
  `Phase2AssetUITests` pattern (real PNGs written into the automation root in `setUp`,
  launch-argument order preserved, `--film-camp-recorded` last).
- UI walks per §10's App list, minus generation: write a prompt → `prompt_ready` → copy
  (pasteboard content asserted) → mark in progress → import result → `needs_review` → make
  canonical → `approved`; both stale badges rendered distinctly (§6.2); §5.8's enablement
  states including the blocked reason on the disabled Generate and the proposed workshop
  read-only except Accept, Reject, and Import Result / drop (the import's implicit accept
  asserted, §13.10); notes fields; the moved `addVariantRequirementButton` flow end to end.

### E. The OVERVIEW delta and the hash sweep (design §13.3, §13's gate rules)

- Make the one-line `docs/OVERVIEW.md` Stage 8 edit reconciling `Ready to Create` to the
  canonical `Prompt Ready` — scheduled to this plan because this is where `prompt_ready`
  becomes visible in the product (the Plan 010 §13.9 precedent).
- **In the same commit**, update the pinned OVERVIEW hash in every plan that pins it —
  Plans 002–009, 011, 013, and 014 — and fix Plan 001's OVERVIEW hash by hand (its pin is
  currently live, and no gate checks that file; §13's gate list). `scripts/check-docs.sh`
  executes every drift block, so a missed pin fails check 5 — run it before committing, and
  verify Plan 001 with the scoped check in Step 3 (running 001's whole block would fail on
  its already-stale ROADMAP and REFERENCE_PROJECTS pins, which stay as they are).

## Target file layout (additions, changes)

```text
AI Film Camp/
  Views/Manifest/ AssetWorkshopView.swift (new) + workshop subviews (references panel,
    prompt panel, version grid host), ManifestListView.swift (master pane;
    addVariantRequirementButton removed), RequirementInspectorView.swift (slot surface and
    the two requirement badges removed; review surface retained), AssetSlotView.swift
    (re-hosted, identifiers unchanged)
  App/ProjectWindowModel+Workshop.swift (new), ProjectWindowModel+Assets.swift (promptID
    pass-through from the workshop)
  Support/WorkshopConfirmText.swift (new — contract C's strings)
  Tests/ workshop window-model twins + WorkshopCopyTests
  UITests/ Phase3WorkshopUITests.swift (new), Phase2AssetUITests.swift (slot steps
    re-targeted, identifiers unchanged), Phase2ManifestUITests.swift (three
    addVariantRequirementButton sites re-targeted)
docs/OVERVIEW.md (Stage 8 line), docs/plans/ 001 (by hand), 002–009, 011, 013, 014
  (OVERVIEW pins, Step 3)
Packages/FilmCore, Packages/FilmBrain, project.yml: unchanged
```

`scripts/eval-inputs.txt` is untouched, and no file it lists is edited by this plan.

## Steps

### Step 1: Placement and the re-host

Contract A — move first, add nothing new yet, so identifier collisions surface before the
new surfaces exist.

```bash
grep -rn "addVariantRequirementButton\|requirementBlockedBadge\|requirementStaleBadge" "AI Film Camp/Views" | grep -c accessibilityIdentifier
./scripts/verify.sh
```

Expected: the grep counts exactly 3 (one host each — the workshop); `verify.sh` exits 0 with
`Phase2AssetUITests` and `Phase2ManifestUITests` passing re-targeted (headless twins are the
assertions of record under the documented flake; rerun idle and compare against
`docs/IMPLEMENTATION_NOTES.md` before blaming the change).

### Step 2: Surfaces, copy, and twins

Contracts B, C, D.

```bash
./scripts/verify.sh
```

Expected: all suites exit 0; `WorkshopCopyTests` asserts contract C's strings character for
character; the §10 walk runs in `Phase3WorkshopUITests` with every assertion twinned
headlessly; Generate/Regenerate render disabled with reasons; the pasteboard, drop, and
lineage-stamp assertions pass.

### Step 3: The OVERVIEW delta and README

Contract E.

```bash
NEWHASH=$(shasum -a 256 docs/OVERVIEW.md | cut -d' ' -f1)
grep -c "$NEWHASH  docs/OVERVIEW.md" docs/plans/001-*.md docs/plans/00[2-9]-*.md docs/plans/011-*.md docs/plans/013-*.md docs/plans/014-*.md
./scripts/check-docs.sh
```

Expected: every listed plan shows count 1 for the new hash (001 included, by hand);
`check-docs.sh` exits 0 in the same commit as the Stage 8 edit. Update
`docs/plans/README.md`.

## Done criteria

- [ ] `./scripts/verify.sh` exits 0; the Manifest section is the in-content master–detail of
  §5.1; the slot surface and the three named identifiers are re-hosted with every shipped
  identifier live in exactly one place; both Phase 2 suites pass re-targeted.
- [ ] Every §5.2–§5.7 surface ships as written, including the drift badges, the
  unsatisfied-dependency marker standing in for the designator on unsatisfied rows (§3.3's
  two collections), per-version notes, the lineage tag, drag/drop, and the
  workshop's `promptID:`-stamped import — the only non-nil call site.
- [ ] §5.8's enablement table and this plan's confirm strings ship verbatim and
  character-asserted; refusals surface FilmCore's copy through `runEdit`; the proposed
  workshop is read-only **except Accept, Reject, and Import Result / drop**, with the
  import's implicit accept asserted; Generate/Regenerate are present, disabled, and unwired.
- [ ] §5.9's identifiers, mitigations, and mandatory headless twins are in place; the §10
  no-AI walk passes in UI and twin form.
- [ ] **The §14 decisions this plan implements carry the owner's recorded acceptance**:
  §14.2 (Empty Slot's prompt history — the "Prompts are kept." confirm), §14.5 (human prompt
  authoring and editing — the Write Prompt sheet and body editing), and §14.7 (In Progress
  semantics — the gesture's placement and Copy Prompt's purity) are **accepted 2026-08-22,
  as recommended**, recorded in design §14; confirm the design still reads that way before
  flipping this plan's README row to `DONE`.
- [ ] OVERVIEW's Stage 8 line reads `Prompt Ready`, every pinning plan's hash (001 by hand)
  was updated in that commit, and `docs/plans/README.md` marks Plan 015 `DONE`.

## STOP conditions

- The `docs/PHASE3_DESIGN.md` hash differs and §5, §13.3, or the named §14 items changed.
- The product owner declines §14.5 — reconcile before building the prompt panel.
- A shipped identifier must change spelling, or ends up live in two places (§5.9's rule is
  absolute; report the collision rather than suffixing).
- Re-targeting `Phase2ManifestUITests` or `Phase2AssetUITests` proves non-mechanical — an
  assertion depends on the inspector hosting the moved surface in a way selection cannot
  satisfy (report it; the design says the cost is mechanical, so a divergence is a design
  question).
- A verification command fails twice after one reasonable scoped correction — for UI suites,
  first compare against the recorded environmental flake and rerun on an idle machine.
- Work expands into generation, run gates, disclosures, or batch (Plan 016), into Phase 4
  readiness dashboards or deep links, or into Phase 5 scene prompts, packages, or export.

## Maintenance notes

- Enablement rules live on the window model and reads, never in view bodies — Plan 016 adds
  only the run-gate condition and the two 016-owned confirms to this surface.
- `Phase3WorkshopUITests` and its twins are the template Plan 016 extends with the recorded
  generation flow; do not fork a second automation pattern.
- `WorkshopConfirmText` is the single home for workshop confirm strings; Plan 016 appends
  its two, and a §14.2 reversal swaps one string there.
