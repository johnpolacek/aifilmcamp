# Plan 029: Face + headless front/back character identity bundle (Phase 5c)

> Read `docs/plans/README.md`, `docs/PHASE1_DESIGN.md`, and
> `docs/PHASE2_DESIGN.md` before execution. This plan records the product-owner
> amendment of 2026-08-29 and narrowly supersedes Phase 2's four-view default
> character template. The stable template codes remain unchanged so existing
> project references and history stay valid.

## Status

- **Status**: IN PROGRESS — implementation complete; verification deferred by
  owner request
- **Depends on**: Plans 009–016 and 024–028
- **Category**: FilmCore migration/domain / reference-generation workflow / docs

## Contracts

### A. Character identity is a two-slot bundle

- The default character template exposes Face Closeup (`face_closeup`) and
  Headless Full Body — Front + Back (`full_body`). The full-body deliverable is
  one neutral reference sheet containing both front and rear full-length views;
  only the front figure is headless so facial identity comes only from Face
  Closeup. The rear figure includes the complete back of the head, ears, neck,
  and hairstyle, without exposing a second facial view.
- Profile / Side (`profile_side`) and Waist Up (`waist_up`) remain frozen stored
  codes but are disabled legacy entries. They no longer create active canonical
  slots.
- The Full Body slot depends on the same character's Face Closeup slot. An
  approved face is therefore included automatically as the full-body generation
  reference and readiness blocks full-body generation until the face is ready.
- Canonical-to-canonical seeding is deterministic in both creation orders and
  respects an existing rejected dependency tombstone.

### B. Existing projects migrate without losing work

- Bundle schema 11 updates every existing project. It disables the two legacy
  template entries, retires their existing requirements with `not_needed`, and
  recomputes any corresponding asset to `deprecated` without deleting assets,
  versions, prompts, media, or provenance. Dependency edges targeting those
  retired slots are tombstoned so old approved images are no longer sent as
  active generation references.
- An untouched default `Full Body` template/requirement is renamed to Headless
  Full Body — Front + Back. Customized labels remain unchanged; a requirement
  rename is skipped when it would collide with another normalized name.
- An existing approved Full Body asset remains approved and visible but is
  marked stale so the former single-view deliverable is not silently treated
  as satisfying the new sheet contract.
- Existing Face Closeup and Full Body requirements gain the bundle dependency
  unless any dependency row for that pair already exists. Rejected tombstones
  are never resurrected.
- Fresh projects seed the same four frozen character codes, with only the two
  bundle entries enabled.

### C. Prompt/reference semantics match the bundle

- The stable `full_body` code now means a headless front/back body sheet, and
  its displayed name supplies that intent to prompt generation.
- A Face Closeup dependency is described as facial identity and is sent in the
  existing deterministic reference order. No SwiftUI layer reads files or
  manufactures provider provenance.
- Existing saved full-body prompts remain history. Renaming the default
  requirement changes its deterministic input digest, so old current prompts
  surface as stale rather than being silently rewritten.

### D. Scene references present entity bundles

- Required References groups planned references by stable entity id and renders
  one large bundle card per character, location, prop, vehicle, creature, or
  object. The card header names the entity and summarizes completion; its child
  slots remain individually navigable to the existing focused detail workflow.
- A character bundle orders Face Closeup before Headless Full Body — Front +
  Back. When Face Closeup is approved and Full Body is missing, the bundle shows
  `Generate Body from Face`; that action runs the Full Body creation workflow in
  the bundle, whose stored dependency supplies the approved face automatically.
- Location bundles group the location's existing canonical and variant
  requirements. This refactor does not invent mandatory reverse-angle, detail,
  exterior, or interior slots.
- Bundles are a derived read/presentation pattern over existing entity and
  requirement identities, not another persisted table or mutation surface.

### E. Generate Body from Face completes in place

- `Generate Body from Face` does not navigate away. The Full Body child slot
  immediately becomes a progress surface while the existing prompt and provider
  workflows run. A first-use disclosure may overlay the workspace, but after
  Continue the same in-place pipeline resumes.
- Full Body generation always requests one 16:9 candidate. The approved Face
  Closeup dependency is sent automatically, the sole candidate is validated and
  committed through the existing FilmCore provenance transaction, and the child
  slot fills from the refreshed canonical read when that commit completes.
- This shortcut intentionally skips candidate selection because it requests one
  result. Failures restore the action and render the provider/validation error in
  the bundle; they never leave a phantom approved image.

## Steps

1. Record the design amendment and add bundle schema 11.
2. Migrate existing template entries, canonical requirements, asset state, and
   Face Closeup → Full Body dependency without deleting history.
3. Seed fresh projects with the new enabled defaults and extend deterministic
   canonical creation to maintain the bundle dependency.
4. Update product/design language and prompt/reference semantics.
5. Group scene references into large derived entity bundle cards and add the
   Face Closeup → Generate Body from Face continuation action.
6. Make that continuation a one-candidate 16:9 in-place pipeline with progress,
   automatic validated commit, and disclosure/failure handling.
7. Later, when the owner lifts the no-testing constraint, add/update migration,
   domain, app-model, and UI coverage; run the changed-path lanes before commit.

## Done criteria

- [x] Existing projects upgrade to schema 11 without losing media or history.
- [x] Only Face Closeup and Headless Full Body — Front + Back are enabled for
      default character identity generation.
- [x] Full Body depends on Face Closeup in migrated and newly built manifests.
- [x] Generated full-body prompts receive the approved face automatically.
- [x] Required References presents large entity bundle cards, including location
      bundles, with individually navigable child slots.
- [x] An approved face enables `Generate Body from Face` for a missing body.
- [x] Body generation stays in the bundle, shows progress in its 16:9 slot, and
      fills automatically after the validated one-candidate commit.
- [x] Documentation reflects the two-slot bundle.
- [ ] Deterministic verification passes after testing is authorized.

## Verification

Deferred by explicit product-owner request. Do not modify or run tests during
this implementation pass.

## STOP conditions

1. Migration would delete an asset, version, prompt, media file, or provenance.
2. A legacy dependency tombstone would be replaced or reactivated.
3. A customized template or requirement label would be overwritten.
4. The stable `full_body`, `profile_side`, or `waist_up` code would change.
5. Work expands into video, takes, editing, rendering, or provider-specific
   credential behavior.
