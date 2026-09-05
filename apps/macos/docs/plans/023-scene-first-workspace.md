# Plan 023: Scene-first generation workspace (Phase 5c)

> Read `docs/PHASE5_DESIGN.md`, `docs/PHASE1_DESIGN.md`, and Plan 022 in full
> before execution. This plan is presentation over FilmCore operations and FilmBrain jobs;
> SwiftUI owns no persistence, parsing, process, or validation logic.

## Status

- **Status**: DONE
- **Depends on**: Plan 022 `DONE`
- **Category**: app / SwiftUI / handoff / tests

## Contracts

### 2026-09-03 inline editing amendment

Existing scene prompt cards are always editable in an inline text area. Changes
autosave after a brief typing pause through the existing FilmCore mutation, with
save failures shown inline and drafts retained while navigating. Title, guidance,
and settings are also editable in place; the modal remains only for adding a new
card. Pending edits are flushed before export, regeneration, and project close.
Verification uses `scripts/build.sh`; no automated tests are added in prototype mode.

### A. Primary scene workspace

- Replace section navigation and the inspector with one two-column
  `NavigationSplitView`: a searchable scene rail and the selected scene workspace.
- Scene rows show one presentation status derived from existing domain state: `Needs
  Images`, `Ready for Prompt`, `Ready`, or `Update Prompt`.
- The workspace order is heading/status; collapsed Scene Data; Required References;
  ordered prompt cards. Scene Data retains screenplay, synopsis, entity links,
  continuity, and correction entry points.

### B. References and prompt cards

- Required References includes actionable empty slots. A focused sheet shows identity,
  image-generation prompt, current image, Add/Replace Image, and collapsed history.
  Choosing or dropping an image makes it current through one controlled operation.
- Each card shows the exact locally numbered thumbnails above its paste-ready prompt,
  then settings, Copy Prompt, Reveal/Drag Images, and edit controls. Cards can be edited,
  added, deleted, and reordered; Regenerate replaces the complete set while history
  retains the previous set.
- Thumbnails are individually draggable. Reveal Images materializes and opens the exact
  per-card numbered files so external tools can receive a multi-file drag.
  The 2026-09-04 refinement reveals the first numbered image in Finder, opening inside
  the card folder with its images visible instead of selecting the folder in its parent.

### C. Project-level controls

- Put Import/Replace Screenplay, Analyze Screenplay, Build Reference List, and AI
  Reference Inference in a compact Project Actions toolbar menu. Only the relevant next
  action appears inline when a scene is blocked. Run progress/cancellation stays in the
  toolbar.
- Move target profile, style bible, and custom-skill selection to Project Settings.
- Remove Dashboard, entity-category, Continuity, Manifest, Generation, and Jobs from
  primary navigation; keep required correction sheets reachable from Scene Data.
- Do not add Higgsfield credentials or submission.

## Steps

1. Introduce the scene rail/status derivation and consolidated workspace shell.
2. Build Scene Data and Required References, including focused repair and drop-to-current.
3. Build multi-card display/edit/reorder/copy/reveal/drag/regenerate/history interactions.
4. Consolidate Project Actions, Project Settings, progress/cancellation, and remove old
   primary navigation paths.
5. Update headless and XCUITest coverage, run changed-path lanes and the full gate, then
   record status.

## Done criteria

- [x] A filmmaker can move from a blocked scene to repaired references and paste-ready
      locally numbered prompts without navigating to another primary section.
- [x] Copy and image handoff exactly match each card's local reference mapping.
- [x] Card editing/regeneration/history and drop-to-current are controlled and tested.
- [x] Only the scene rail remains primary navigation; preparation is manual and reachable.
- [x] Changed-path and full verification gates pass.

## STOP conditions

1. A UI interaction would need to write storage directly rather than call FilmCore.
2. Work expands into provider credentials, submission, generated clips, takes, or editing.
3. A removed primary surface has a necessary correction action that has not been made
   reachable from Scene Data or Project Actions.
4. Plan 022's model cannot provide exact card-local image mappings.
