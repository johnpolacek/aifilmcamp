# Plan 033: Queued reference-image generation (Phase 5c)

> Read `docs/plans/README.md`, `docs/PHASE1_DESIGN.md`, and Plans 024–030
> before execution. This product-owner amendment of 2026-09-03 supersedes the
> earlier window-wide single-flight and close-cancels behavior. It does not
> change `ImageGenerating`, the helper protocol, FilmCore provenance, or the
> project-bundle schema.

## Status

- **Status**: IN PROGRESS — implementation complete; verification explicitly
  deferred by product-owner request
- **Depends on**: Plans 024–030
- **Category**: app orchestration / still-image generation / in-memory queue
- **Priority**: P1
- **Estimated effort**: M

## Contracts

### A. Requirement-keyed FIFO state

- Generate, Regenerate, Edit Image, and Update Body from Face may coexist for
  different requirements in one project window. One in-memory FIFO owns the
  image pipeline and executes exactly one item at a time.
- Queued, running, awaiting-selection, importing, failed, and completed
  presentation state is keyed by requirement ID. A duplicate gesture for the
  same requirement is refused; unrelated reference actions remain available.
- The queue has no list, persistence, schema, or individual pending-item
  cancellation UI. Existing cards, detail, chooser, error, and toolbar surfaces
  present the state.

### B. Frozen launch intent and paid boundary

- The Generate gesture captures mode, candidate count, settings, attachment,
  prompt context, provider, and model. The generator for that captured provider
  is constructed only when the item reaches the head of the queue, so its API
  key is read only when execution begins.
- Prompt preparation, input validation, provider generation, output validation,
  and automatic import are serial. Canonical state is rebuilt immediately
  before the paid request, and FilmCore revalidates the same token inside its
  existing atomic import transaction.
- Provider fallback and automatic retries remain disabled. Existing 1–4
  candidate requests remain sequential inside the one active queue item.

### C. Candidates, failure, cancellation, and teardown

- One-image Create and Edit jobs import automatically. Regenerate and every
  2–4-image job retain disposable candidates by requirement and release the
  provider queue; reopening that reference presents the existing chooser.
- Closing reference detail or a creation sheet detaches presentation and leaves
  its queued/running job alive. Closing the project cancels the active item,
  removes pending items, and deletes every uncommitted candidate directory.
- The existing Cancel action targets only the active item and immediately
  advances the FIFO. Failures remain attached to their reference, do not stop
  later work, and allow a new explicit retry.

## Steps

1. Replace window-wide image presentation state with requirement-keyed states,
   a FIFO, and one active item.
2. Freeze interactive launch inputs and add queued prompt preparation for the
   one-click reference actions.
3. Preserve FilmBrain generation and FilmCore validation/import boundaries,
   including the pre-spend canonical-state check.
4. Route existing card, detail, chooser, error, toolbar Cancel, sheet-close,
   and project-close behavior through the queue.
5. Register this plan and widen the Phase 5 documentation range.

## Done criteria

- [x] Different requirements can be queued while one image pipeline runs.
- [x] The same requirement cannot be duplicated while queued, running,
      importing, or awaiting candidate selection.
- [x] Provider/model/settings/prompt inputs are captured per gesture, with the
      generator and credential read deferred until execution.
- [x] Regenerate and multi-image candidates survive navigation and do not block
      the next provider item.
- [x] Sheet/detail close detaches; project close clears all ephemeral work; the
      existing Cancel action advances past only the active item.
- [x] Failure is per reference and the next FIFO item still runs.
- [x] No schema, persistent job, queue-management UI, helper protocol, or
      `ImageGenerating` change was introduced.
- [ ] Verification is intentionally deferred by product-owner request.

## Verification

- No tests were added or edited.
- No package tests, app tests, UI tests, `scripts/test-changes.sh`,
  `scripts/verify.sh`, build, or live provider request was run.
- Verification is explicitly deferred by product-owner request.

## STOP conditions

1. Queueing would require a persistent job or project-bundle schema migration.
2. A provider credential would be captured in queue state, logged, persisted,
   or read before its item begins execution.
3. A queued request could bypass FilmCore's pre-spend context validation or
   atomic import-time revalidation.
4. Implementing the queue would require provider fallback, automatic retry,
   parallel provider execution, or new queue-management UI.
