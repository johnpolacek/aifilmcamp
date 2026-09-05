# Plan 031 — Scene Reference Exclusions

## Status

- **Status**: DONE — character/location extension and atomic bundle removal built 2026-09-03

## Goal

Let a filmmaker remove individual references or whole reference bundles from
the references required for one scene without deleting the entity, its requirements,
its approved images, or its use in any other scene.

Owner amendment, 2026-09-03: extend removal to character and location references,
including News Anchor/Pundit identity bundles and a Porch already covered by an
apartment image. Remove whole bundles atomically and retain individual removal
in the focused image detail. The scene-link check supports canonical references
of every entity kind and explicitly linked variant references. No schema change
is needed. Update main; skip automated tests under prototype mode.

## Contracts

1. Every reference bundle in the scene workspace and every focused image detail
   offer **Remove from Scene**, including when images are still missing. Bundle
   removal excludes all its current references in one transaction and undo step.
2. Removal is a human-only, undoable FilmCore mutation, not a presentation-only
   filter and not a screenplay/entity edit.
3. Bundle schema v13 stores the excluded `(scene, requirement)` pair. Foreign-key
   cascades keep the row valid when its owning scene or requirement is deleted.
4. The shared readiness graph subtracts exclusions after deriving canonical and
   variant links. Scene readiness, required-reference cards, generated prompt
   context, and exported packages therefore agree.
5. Only references linked to the selected scene can be excluded: canonical
   requirements through non-rejected visible appearances, and variants through
   non-rejected explicit scene links. Unrelated requirements are rejected at the
   controlled mutation boundary; human-only and lock guards remain enforced.

## Steps

- Add `scene_reference_exclusions` and migrate existing bundles losslessly to v13.
- Add inverse-safe exclude/include edit operations and row-graph snapshot support.
- Subtract excluded requirement IDs in the shared readiness graph.
- Add the scene-workspace action and refresh/close stale detail state after success.

## Done criteria

- Controlled mutations, shared derivation, bundle/detail actions, undo, and
  affected package/readiness behavior use the same persisted exclusions.
- `scripts/build.sh` passes before the plan is marked `DONE` or committed.

## Verification

Original prop-only implementation deferred verification at the owner's request.
The 2026-09-03 extension passed `scripts/build.sh` (documentation checks,
FilmCore, FilmBrain, and the macOS app). Automated tests were skipped as requested.

## STOP conditions

- The request expands beyond scene-local reference exclusions.
- Any implementation filters only presentation while canonical readiness,
  prompt context, or export still includes the requirement.
- Verification exposes a schema, undo, or shared-derivation regression.
