# Plan 027: Reference image iteration and bounded cards (Phase 5c)

> Read `docs/plans/README.md`, `docs/PHASE1_DESIGN.md`,
> `docs/PHASE5_DESIGN.md`, and Plans 024–026 in full before execution. This
> plan records the product-owner request of 2026-08-28. It supersedes Plan
> 026 contract B's filled-detail action limit and Plan 025 STOP condition 7
> only for still-reference-image regeneration and editing. Generated video,
> takes, clips, timelines, rendering, and review queues remain excluded.

> **2026-08-29 forward amendment:** Plan 028 restores the blank run-only edit
> instruction and presents it inline. Regenerate from Prompt remains the
> separate saved-prompt workflow.

## Status

- **Status**: DONE — bounded cards and both deterministic image-iteration paths
  landed 2026-08-28
- **Depends on**: Plan 024 `DONE`; Plan 025's deterministic implementation;
  Plan 026 `DONE`
- **Category**: FilmCore generation context / app presentation / tests / docs

## Contracts

### A. Card media never escapes its well

- A loaded card image receives the image well's exact proposed width and
  height before `scaledToFill` clipping. The rounded well is the final clip
  boundary, including while the adaptive grid is between its 220–280 point
  card limits.
- The card keeps separate image, archive, text-navigation, Add Image, and
  Create hit regions. The fix introduces no nested controls or unbounded image
  decode.

### B. Two iteration workflows

- A filled reference detail exposes **Regenerate…** and **Edit Image…** beside
  Archive Image.
- Regenerate opens the existing creation workflow with the saved original
  prompt editable and auto-saving as before. It adds an **Include current
  image as reference** toggle, off by default. When on, the current image is
  the first provider reference, followed by the existing deterministic
  canonical dependencies.
- Edit Image opens the same generation/candidate workflow with the current
  image always first and a blank, run-only edit instruction. The instruction
  is not written over the saved original prompt. Copy/removal actions that
  operate on the saved prompt are absent in this mode.
- Both workflows retain app-wide provider selection, Keychain-only credential
  handling, 1–4 explicit provider requests, progress/cancellation, output
  validation, candidate choice, archive behavior, and inline failures.

### C. Provider-neutral drift and provenance

- FilmCore's generation context distinguishes the saved source-prompt digest
  from the exact run-prompt digest and records whether the target's current
  image participates. It remains provider-neutral and stores no prompt body,
  credential, or provider object.
- Context construction places the verified current image first when requested,
  then the existing ordered canonical dependencies. An edit refuses if no
  current image exists. Provider capability evaluation sees the complete list
  and never silently drops an input.
- Generation input materialization and candidate import rebuild the context
  from canonical state. A saved-prompt edit, current-version change,
  dependency change, or run-prompt mismatch refuses before any row lands.
  Successful import retains the shipped atomic current/archive swap and
  records the exact ordered reference hashes plus run-prompt digest in schema
  v10 provenance; no migration is needed.

## Steps

1. Add this plan, its index entry, and forward-amend the filled-detail action
   contract.
2. Fix the card's proposed-size/clipping boundary and add a UI regression.
3. Extend FilmCore's generation-context read/revalidation for a distinct run
   prompt and optional current-image reference, with focused Swift Testing.
4. Add create/regenerate/edit presentation modes, detail actions, ephemeral
   edit instructions, and headless/UI coverage over request composition and
   successful refresh.
5. Run `scripts/test-changes.sh` lanes covering docs, FilmCore, FilmBrain,
   app/headless, build, and the scene-workspace journey. Make no live provider
   request. Commit only after the selected gates pass.

## Done criteria

- [x] Card images remain inside their rounded wells across adaptive widths.
- [x] Regenerate edits the saved prompt and optionally includes the current
      image without changing provider/candidate behavior.
- [x] Edit Image sends a run-only instruction with the current image and does
      not overwrite the saved prompt.
- [x] Context drift, reference ordering, provider limits, provenance, and
      atomic current/archive replacement remain enforced by FilmCore.
- [x] Focused deterministic tests pass without a live or paid request.

## Verification

- `scripts/test-changes.sh 8c2061d` passed the selected change lanes: all 799
  FilmCore tests, all 140 FilmBrain tests, build-for-testing, 105 XCTest app
  tests plus 14 Swift Testing app cases, and the complete
  `SceneWorkspaceSmokeUITests` UI suite.
- Focused reference-image coverage passed for run-only prompt provenance,
  current-image-first ordering, optional-current refusal, exact provider
  request composition, prompt preservation, prompt-run routing, generation
  failure, and the then-current single-flight cancellation. Plan 033 supersedes
  that runtime behavior with requirement-keyed FIFO execution.
- The UI journey asserts the loaded image button remains within its adaptive
  card frame and exercises both filled-detail iteration entry points. No live
  Codex or image-provider request was enabled.

## STOP conditions

1. Direct edit would require overwriting the saved original prompt or losing
   the exact run-prompt digest from generation provenance.
2. The current image or a canonical dependency could be sent without the
   shipped containment, byte-count, SHA-256, and media validation.
3. SwiftUI would need to read project files, build provider requests, handle
   credentials, validate output, or write storage.
4. A provider limitation would require silently dropping the current image or
   another reference.
5. Work expands beyond still-reference-image iteration into video, takes,
   clips, timelines, rendering, or a generated-media review queue.
