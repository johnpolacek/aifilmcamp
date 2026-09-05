# Plan 034 — Append screenplay scenes

## Status

DONE — implemented and built on 2026-09-03 following the product owner request.

Owner amendment, 2026-09-04: replace the separate preview step with one
Add Scenes action that validates and saves the pasted text immediately.
The model prepares the FilmCore preview internally and commits it through
the existing guarded transaction. The sheet keeps the undo disclosure visible
before adding and preserves the draft with an inline error on failure.
This supersedes the heading/warning preview UI requirements below.
Verification: `scripts/build.sh` passed for the amendment on 2026-09-04
(documentation checks, both packages, and the signed Debug macOS app).

## Contracts

Add File → Add Scenes… and a scene-rail action for pasting screenplay text,
previewing the detected scene headings and their new ordinals, and appending
them to the current screenplay. This narrowly extends Phase 1's import-only
contract; revised-draft replacement and automatic re-analysis remain separate.

FilmCore parses and validates the pasted Fountain/plain text. Require explicit
scene headings, reject empty text, title pages, and unheaded preambles, and
surface parser warnings before committing. Preview and commit must agree on
the current script identity and digest. Refuse append during active or paused
jobs. The operation is human-only and uses one transaction and journal entry.

Append normalized text to the canonical script, updating its digest. Shift only
the new scene, sequence, cue, element, and warning UTF-16 ranges and ordinals.
Keep all existing scene IDs, bounds, overrides, entities, requirements, media,
and prompt cards. Preserve the original imported file. Resolve parser entities
against existing names and aliases, including renamed/merged characters; never
resurrect rejected entities. Refresh missing canonical requirements in the same
transaction so new scenes enter the existing reference and prompt workflow.

Like screenplay import, append is non-invertible; disclose this in the preview
and clear the session undo stack on success. The journal records the pasted
text, prior script snapshot and affected rows. Clear search
and select the first appended scene after success. Failure keeps the draft.
No AI calls, paid requests, new dependencies, migrations, or automated testing
infrastructure are part of this change.

## Steps

1. Add a FilmCore preview DTO and controlled append operation, reusing the
   screenplay parser, writer, journal, and canonical requirement derivation.
2. Add the paste/preview sheet and menu/rail entry points in the app.
3. Run `scripts/build.sh`, inspect the diff, and record verification here.

## STOP conditions

Stop if appending requires destructive replacement of existing scene work.
Do not expand the request into incremental AI extraction or draft reconciliation.

## Done criteria

- `scripts/build.sh` passed: documentation consistency, FilmCore, FilmBrain,
  and the signed Debug macOS app all build.
- A disposable project exercise through the public FilmCore API passed: two
  scenes append in order; original scene identity, bounds, human text override,
  character provenance, and imported file remain unchanged; renamed characters and multiple
  cue aliases share one appearance; rejected characters stay hidden; Unicode
  exclusion offsets resolve; stale previews, empty/unheaded input, and AI
  actors are refused; reopening preserves the appended scenes.
- No automated suite or testing infrastructure was added. Native UI inspection
  was attempted but the computer-use service timed out; the sheet and rail were
  compile-checked and inspected in source.
- Existing in-progress reference-image changes were left outside this commit.
