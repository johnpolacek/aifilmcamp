# Plan 030: Durable visual amendments and bundle synchronization (Phase 5c)

> Read `docs/plans/README.md`, `docs/PHASE1_DESIGN.md`,
> `docs/PHASE2_DESIGN.md`, and Plans 027–029 before execution. This plan records
> the product-owner amendment of 2026-08-29 and supersedes Plan 027's rule that
> an edit instruction is retained only as a digest.

## Status

- **Status**: IN PROGRESS — implementation complete; verification deferred by
  owner request
- **Depends on**: Plans 027–029
- **Category**: FilmCore migration/provenance / reference-generation workflow / UI

## Contracts

### A. Successful edits become durable visual amendments

- Edit Image remains a blank textarea plus Submit Edit. A successful edit stores
  the exact human instruction on the immutable generation run that produced the
  selected current version. Failed and unselected candidates create no active
  amendment.
- Character canonical edits default to `character_bundle` scope. Other edits
  remain requirement-scoped. Generated image edits do not silently rewrite the
  reusable prompt; a filmmaker may still correct that prompt explicitly.
- Active amendments derive only through the generation lineage of currently
  approved images. Archiving, replacing, undoing, or restoring an image changes
  the active set through canonical reads rather than destructive cleanup.

### B. Effective generation guidance has deterministic precedence

- Non-edit generation composes the saved prompt with active human amendments.
  The amendment block is last and explicitly wins over conflicting older text.
- Character-bundle amendments travel across canonical slots. Providers are told
  to preserve applicable identity, physical appearance, hair, and wardrobe while
  ignoring source-slot framing, pose, crop, and background.
- Edit generation continues to send only the new delta instruction with the
  current image first. Its existing lineage retains prior amendments. For the
  full-body sheet, the provider prompt also carries non-negotiable structural
  invariants: only the requested detail changes, the front remains headless,
  and the rear retains the complete back of the head. Only the filmmaker's delta,
  not those internal constraints, is persisted as the visual amendment.
- FilmCore includes the ordered amendment lineage in the generation commit token;
  every successful run snapshots the exact amendment set it applied, and an
  approved-version or amendment-lineage change refuses the candidate import.

### C. Dependents synchronize explicitly

- Approving an edited canonical image marks dependents and approved canonical
  bundle siblings stale in the same atomic, undoable media transaction.
- A stale Headless Full Body slot offers `Update Body from Face`. It uses the same
  in-place 16:9 one-candidate pipeline as initial body generation. No paid request
  starts automatically.
- Missing-body generation and stale-body synchronization both use the approved
  face image plus its active visual amendments. The current face prompt is also
  frozen into the body-generation context and supplies higher-priority applicable
  appearance and wardrobe direction, allowing legacy prompt/image conflicts to
  be corrected before Update Body from Face.
- Body continuation does not send the legacy body prompt alongside the corrected
  face prompt. It uses a fixed headless front/back layout instruction plus the
  current canonical face description, eliminating contradictory wardrobe prose
  instead of asking the provider to choose between it. Only the front figure is
  headless; the rear figure retains the complete back of the head and hairstyle.

### D. Existing projects and edits remain safe

- Schema 12 adds nullable amendment provenance to image-generation runs without
  deleting or rewriting media, prompts, run history, or journal entries.
- Historical edit text cannot be reconstructed from its digest. Existing current
  images remain authoritative visual references; only edits committed after this
  migration gain durable text.
- The reference detail exposes the reusable base prompt as an editable, undoable
  human correction. Update Body from Face and Regenerate from Prompt save a dirty
  valid draft before starting generation.

## Steps

1. Record the amendment and add the lossless schema-12 migration.
2. Add amendment domain values, lineage derivation, context drift validation,
   and atomic edit-run persistence in FilmCore.
3. Compose effective provider prompts in the app without changing edit UI.
4. Surface stale bundle children and one-click body synchronization.
5. Update product documentation.
6. When testing is authorized, add migration/domain/model/UI coverage and run
   changed-path lanes before committing.

## Done criteria

- [x] Successful edits persist exact human amendment text on their generation run.
- [x] Current-image lineage deterministically derives active amendments.
- [x] Non-edit generation sends a higher-priority amendment block.
- [x] Candidate commit refuses amendment-lineage drift.
- [x] Stale body slots offer in-place Update Body from Face.
- [x] Existing bundles migrate to schema 12 without creative-data loss.
- [ ] Verification passes after testing is authorized.

## Verification

Deferred by explicit product-owner request. Do not modify or run tests during
this implementation pass.

## STOP conditions

1. Migration would delete or rewrite existing creative history.
2. An unselected or failed edit would become active visual direction.
3. SwiftUI would derive lineage, compose storage reads, or write provenance.
4. Synchronization would silently trigger a paid provider request.
5. A provider credential or edit instruction would enter logs or diagnostics.
