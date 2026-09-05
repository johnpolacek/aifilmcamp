# Plan 028: Detail-first reference generation (Phase 5c)

> Read `docs/plans/README.md`, `docs/PHASE1_DESIGN.md`, and Plans 024–027
> before execution. This plan records the product-owner amendment of
> 2026-08-28. It supersedes the card quick-action contracts in Plans 024 and
> 026 and Plan 027's run-only edit-prompt behavior. Still-image generation
> remains the boundary; video, takes, clips, editing, and rendering stay out.

> **2026-09-03 product-owner amendment:** Filled-reference **Regenerate from
> Prompt** is now a direct one-candidate action. The visible saved prompt and
> nearby provider/request disclosure are the complete preflight surface; the
> former regeneration sheet and its second Generate gesture are removed.
> Progress, cancellation, and failures remain inline in reference detail, and
> the validated result replaces the current image through the existing atomic
> current/archive transaction.

> **2026-09-03 Plan 033 amendment:** Regenerate now retains its generated
> candidate for selection when the reference is reopened. Closing detail no
> longer cancels queued or active image work; project close remains the teardown
> boundary.

## Status

- **Status**: DONE (2026-08-28)
- **Depends on**: Plans 024, 026, and 027 `DONE`; Plan 025's deterministic
  implementation
- **Category**: FilmCore media validation/provenance / app presentation /
  deterministic tests / docs

## Contracts

### A. Cards navigate; detail owns actions

- Clicking any part of a required-reference card opens that reference's
  in-workspace detail. Satisfied and missing image wells, metadata, and the
  card background all share this navigation outcome.
- Cards expose no Upload, Generate, Archive, hover, context-menu, or custom
  accessibility actions. The image remains bounded and draggable when a
  current file exists; detail remains the mutation surface.
- Missing detail renames **Add Image** to **Upload** and **Create…** to
  **Generate**. Filled detail retains Regenerate, Edit Image, and Archive.

### B. Edit and regenerate are distinct

- Regenerate from Prompt uses the saved reusable prompt and remains available
  directly beneath that prompt's textarea, trailing-aligned.
- Edit Image opens inline in filled-reference detail with a blank, one-off
  edit instruction, replacing the saved-prompt section in place. Cancel
  restores the prompt section. The current image is always the first provider
  reference; the instruction is sent for that run and never overwrites the
  saved prompt.
- Before submission, the inline edit surface contains only the instruction
  textarea and a trailing `Submit Edit` action. The current image and any
  retained external reference remain automatic inputs without another visible
  control row. Candidate output, live progress, and actual submission failures
  may appear after that action; regeneration-only settings and provider
  summaries do not appear in edit mode.
- Existing exact-run/source prompt hashes preserve the distinction in
  provenance. A successful edit still replaces the current image atomically.

### C. Optional uploaded generation reference

- Create, Regenerate, and Edit Image may attach at most one run-scoped image.
  FilmCore reads it through the existing import limits and image inspection,
  freezes its bytes, filename, byte count, SHA-256, and target entity kind,
  and returns an immutable attachment value. Cancel/remove writes nothing to
  the project.
- The project-window model retains that validated attachment ephemerally for
  the requirement. A subsequent Edit Image or Regenerate action in the same
  window restores it alongside the current image; removing it clears the
  retained selection. The bytes are still never copied into the bundle.
- The provider receives project references in their existing deterministic
  order followed by the optional uploaded attachment. Provider capability
  evaluation counts the complete list and refuses over-limit input rather
  than dropping an image.
- Single- and multi-candidate commits carry the frozen attachment. FilmCore
  revalidates its bytes and records it after project references in schema-v10
  generation provenance with null requirement/version identity. No schema
  migration is needed.

### D. Missing detail is the creation workspace

- Opening a missing reference begins prompt preparation automatically. The
  existing one-time disclosure remains the only pause before the outbound
  Codex request; after it has been acknowledged there is no second
  Generate Prompt gesture.
- The editable prompt renders inline beneath the missing preview. Candidate
  count, the run-scoped reference-image attachment, provider readiness,
  progress/errors, and Generate live with it instead of behind a second
  creation sheet. A selected `Generate from Prompt` tab labels this workspace;
  `Upload Image` is a neighboring tab-bar action rather than a second tab.
- Generated candidates render immediately below the still-visible prompt
  editor. A one-image run uses the same explicit `Use This Image` commit step
  as a multi-image run instead of moving the result to the preview first.
- The preview and compact metadata card share one height. Missing-reference
  metadata is limited to status, reference class, and role so generation
  guidance is not duplicated above the prompt workspace.
- Filled-reference Regenerate is a direct one-candidate action beneath the
  visible saved prompt; it has no intermediate sheet or second Generate
  gesture. Progress, cancellation, and failures stay inline, and the validated
  candidate replaces the current image atomically. Edit Image remains inline.
  Both share the same window-model/FilmCore validation, retained attachment,
  provider, candidate, and commit paths; only regeneration autosaves the
  reusable prompt.

## Steps

1. Add this plan, its index entry, and forward amendments to Plans 026–027.
2. Make cards navigation-only and revise missing-detail action labels.
3. Keep Edit Image on the run-only instruction path and add the optional
   attachment picker, validation, request composition, frozen candidate
   handoff, and provenance insertion.
4. Update FilmCore Swift Testing, app-model coverage, and the consolidated
   scene-workspace XCUITest journey.
5. Run `scripts/test-changes.sh` for every selected lane without a live or paid
   provider request. Mark done and commit only after those lanes pass.

## Done criteria

- [x] Every card surface opens detail and cards expose no mutation controls.
- [x] Missing detail says Upload and Generate.
- [x] Edit Image sends a run-only instruction inline, preserves the saved
      prompt, and includes current first; regeneration remains prompt-based.
- [x] Regenerate from Prompt starts its one-candidate run immediately without
      an intermediate modal and keeps progress/failure feedback in detail.
- [x] One optional uploaded reference is validated, counted, sent, frozen
      through candidate choice, and recorded in exact provider order.
- [x] Missing detail automatically prepares and shows the prompt inline with
      attachment and Generate controls beneath a selected Generate from Prompt
      tab, with Upload Image available from the same tab bar.
- [x] Documentation and selected deterministic lanes pass without live calls.

## Verification

- `swift test --package-path Packages/FilmCore --filter ReferenceImageCreationTests`
  — 19 tests passed.
- Focused `GenerationWindowModelTests` edit/attachment test passed.
- Focused scene-reference detail XCUITest passed after adding refresh-race
  coverage to `ReferenceDetailWindowModelTests`.
- `scripts/test-changes.sh 5bc06f8` selected FilmCore, FilmBrain, app-unit,
  and `SceneWorkspaceSmokeUITests` lanes. FilmCore (801 tests), app units, and
  all three UI smoke tests passed. FilmBrain's first concurrent run hit a
  Swift Testing runtime/compiler index crash; a clean constrained retry with
  `SWT_MAXIMUM_PARALLEL_TESTS=1 swift test --package-path Packages/FilmBrain`
  passed all 140 tests.
- `scripts/check-docs.sh` and `git diff --check` passed.

## STOP conditions

1. An uploaded reference would bypass FilmCore byte limits, image inspection,
   hashing, or exact provenance.
2. Attachment state could change between provider execution and candidate
   commit, or be silently omitted to satisfy a provider limit.
3. Editing would send text that was not saved as the visible reusable prompt.
4. SwiftUI would read image bytes, construct provenance rows, access provider
   credentials, or write project storage.
5. Work expands beyond still-reference generation and current/archive swap.
