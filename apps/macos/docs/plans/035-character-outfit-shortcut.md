# Plan 035: Scene-specific, reusable character outfits

## Status

- **Status**: DONE — title-only creation, completion feedback, and build verified 2026-09-04
- **Depends on**: Plans 027–031 and the current reference-image queue
- **Category**: FilmCore storage/mutations and SwiftUI presentation

## Contracts

- Owner amendment, 2026-09-04: the outfit title alone is sufficient. Details are
  optional; generation always uses the title and appends any supplied details.
  The details editor stays separate from the composed generation instruction.
- Owner amendment, 2026-09-04: close the edit sheet after successful import and
  card refresh. Completion follows the saved version in the requirement's job
  state, rather than changes to the editor's preview. Failures remain visible
  at the top of the sheet and on cards that already have an image. Discarding
  candidates does not count as a successful import. Outfit edits retain the
  canonical face closeup; wardrobe comes from the new body sheet.

- Change Outfit creates a named variant body reference for the selected scene,
  paired with the character's existing canonical face. It never edits the source
  body or changes other scenes. The original and every outfit remain reusable.
- Schema 16 adds nullable source-version provenance to variant requirements.
  This identifies outfit body sheets without overloading names or template IDs.
  Existing records and immutable media remain intact.
- Creation copies validated source body bytes, creates a prompt and scene-linked
  variant, and replaces only this scene's selected body in one undoable transaction.
  Failure rolls back rows and removes staged bytes. Cancellation or provider failure
  leaves a reusable named variant with its starting image; no paid request is implicit.
- Outfit variants depend on the canonical face, not the original wardrobe. They use
  the existing headless front/back edit constraints and requirement-scoped amendments.
- A bundle picker lists the original and named outfits. Use in Scene atomically
  restores the face and selected body and excludes alternative body references in
  this scene. Shared readiness, prompt context, and export consume those links.
- Changing an outfit again always creates another variant. Plain Edit Image remains
  an intentional edit to an existing reference; its shared scope is made visible.

## Steps

1. Add lossless schema/provenance support and controlled clone/select operations.
2. Preserve full-body prompt semantics for outfit variants.
3. Change the outfit sheet to name, create, and edit a scene-specific variant.
4. Add the reusable bundle picker and show the selected outfit name.
5. Run `scripts/build.sh`; no automated tests or paid requests.

## Done criteria

- [x] Original media and other scenes survive an outfit change unchanged.
- [x] New outfits have durable names, source provenance, and body-sheet semantics.
- [x] Original and saved outfits can be selected in other scenes atomically.
- [x] Existing image queue, validation, archive, and undo behavior is retained.
- [x] `scripts/build.sh` passes.

## Verification

- The owner confirmed outfit generation worked. The completion/error follow-up
  passed `scripts/build.sh`; no tests or live provider requests were run. Reviewed
  successful import, discarded candidates, retry errors, and filled-card feedback.
- The 2026-09-04 title-only amendment passed `scripts/build.sh`. No tests were
  added or run, per owner request.

- `scripts/build.sh` passed: documentation checks, FilmCore, FilmBrain, and the
  macOS app. The FilmBrain build cache was cleaned after its stale package graph
  omitted the newly added schema source.
- Reviewed scene selection against the shared readiness graph, transactional
  exclusion/link operations, and existing grouped inverses.
- No automated tests or live provider requests were run. Visual generation
  quality has not been exercised in this implementation pass.

## STOP conditions

1. A scene outfit action would mutate the original bundle's media.
2. Scene membership would be implemented only as a presentation filter.
3. Provider requests would bypass validation, explicit submission, or provenance.
