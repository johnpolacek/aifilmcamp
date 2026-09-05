# Plan 026: Larger reference cards and in-place detail (Phase 5c)

> Read `docs/plans/README.md`, `docs/PHASE1_DESIGN.md`,
> `docs/PHASE5_DESIGN.md`, and Plans 024–025 in full before execution. This
> plan records the product-owner UI reversal of 2026-08-28. It changes no
> FilmCore schema or mutation and no FilmBrain provider behavior.

## Status

- **Status**: DONE — implemented and deterministically verified 2026-08-28
- **Depends on**: Plan 024 `DONE`; Plan 025's deterministic implementation
- **Category**: app presentation / validated previews / tests / docs

> **2026-08-28 forward amendment:** Plan 027 supersedes contract B's
> filled-detail “Archive Image only” limit. Filled references now also expose
> saved-prompt regeneration and run-only image editing through the existing
> validated generation workflow.

> **2026-08-28 second forward amendment:** Plan 028 supersedes card quick
> actions and hover/context archive actions. Cards now navigate only; Upload,
> Generate, and archive operations live in focused detail.

## Contracts

### A. Adaptive scene-reference cards

- Replace the 112-point horizontal strip with a non-scrolling adaptive grid in
  the existing deterministic plan order. Cards are 220–280 points wide with an
  approximately 160-point image well and wrap into additional rows.
- Missing image wells and Add Image keep importing locally; Create keeps the
  existing sheet; a filled card's hover X keeps archiving immediately. Filled
  images and every other non-action card region open the in-workspace detail.
- Quick actions and navigation are separate SwiftUI buttons/hit regions. No
  nested buttons, web event-target logic, storage write, or provider logic
  enters the view.

### B. In-place reference detail

- Store the selected required-reference id as window presentation state. Load
  its existing `RequirementDetail`; keep the scene rail visible; Back restores
  the same scene overview. Scene changes, missing membership, or an invalid id
  clear detail and lightbox state safely.
- Wide layouts place a large aspect-fit preview beside a compact information
  column; narrow layouts stack the same content. Show entity/requirement names,
  Current or Missing plus `@Image N`, class, role, fidelity, applicable
  guidance, saved prompt with selectable text and icon-only Copy, and only that
  requirement's archived versions.
- Missing exposes Add Image and Create. Filled exposes Archive Image only.
  Import, generation completion, archive, restore, and confirmed permanent
  deletion refresh both requirement detail and scene package without closing
  the detail. The scene-wide archive disclosure is removed.
- Restore uses the shipped transactional approval swap; permanent deletion
  keeps the shipped confirmation and rows-first/files-second contract.
  Necessity controls remain out of scope.

### C. Root lightbox and bounded decode tiers

- Current and archived detail images open one root-level dark lightbox covering
  both the scene rail and workspace. It has an accessible focused close button,
  Escape dismissal, and no zoom, pan, gallery, Quick Look, reveal, or editing.
- `AssetPreviewLoader` exposes fixed internal tiers: thumbnail 256, card 512,
  expanded 2048 pixels. Thumbnail remains the default. Every tier uses the
  existing descriptor-relative containment, byte count, SHA-256, damage
  warning, and capped ImageIO thumbnail decode; no viewer reads project files
  directly or performs an unbounded full decode.

## Steps

1. Add this plan, forward-amend Plan 024's card/archive placement contract,
   extend the plan index, and widen `check-docs.sh` through Plan 026.
2. Add preview tiers and window-model presentation actions for reference
   selection, detail/back, lightbox, and saved-prompt copy.
3. Build the adaptive cards, responsive detail, per-reference archives, and
   root lightbox while reusing all existing import/create/archive operations.
4. Add Swift Testing headless/loader coverage and extend the consolidated
   scene-workspace XCUITest journey.
5. Run documentation, affected package/app tests, build-for-testing, and the
   scene-workspace UI lane. Make no live Codex or paid provider request.

## Done criteria

- [x] Reference cards are materially larger, adaptive, ordered, and preserve
      quick actions without accidental navigation.
- [x] Required references open a responsive in-place detail; Back and scene
      changes have safe deterministic presentation state.
- [x] Current/prompt/guidance/actions and requirement-filtered archives render,
      refresh in place, restore transactionally, and delete only after confirm.
- [x] Current and archived images open the root lightbox and Escape closes it.
- [x] All three preview tiers are capped and expanded previews retain every
      integrity, containment, and damage refusal.
- [x] Documentation, app/headless, build-for-testing, and scene-workspace UI
      lanes pass without a live or paid request.

## Verification

- `scripts/check-docs.sh` passed after the Plan 024 amendment, Plan 026 index,
  and coverage-range update.
- The warm full gate passed all 797 FilmCore tests, all 140 FilmBrain tests, and
  build-for-testing. Focused app runs passed the new preview-loader suite, the
  reference-detail window-model suite, and generation refresh regression.
- The final build-for-testing passed, and the complete new
  `testReferenceCardsDetailArchivesAndLightboxStayInTheSceneWorkspace` XCUITest
  passed in 72.814 seconds. The two pre-existing methods in that consolidated
  UI class also passed during the full-gate attempt.
- A later unfiltered app-bundle rerun encountered the repository's known macOS
  test-host connection hang before assertions; no failed app assertion was
  reported. No live Codex or provider request was enabled.

## STOP conditions

1. SwiftUI would need to read project files directly, write storage, validate
   media, launch a process, build provider arguments, or parse provider output.
2. Expanded viewing would bypass containment, size/hash verification, damage
   handling, or the 2048-pixel ImageIO cap.
3. A quick action and card navigation cannot be represented as distinct native
   SwiftUI hit regions without nested controls.
4. Refreshing an open detail would require a new schema, migration, provider
   request, or non-transactional media swap.
5. Work expands into necessity editing, generated video, takes, clips, review,
   editing, rendering, zoom/pan, gallery navigation, or Quick Look.
