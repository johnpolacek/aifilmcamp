# Plan 022: Ordered scene prompt sets and per-card export (Phase 5c)

> Read `docs/PHASE5_DESIGN.md`, `docs/PHASE1_DESIGN.md`, and
> `docs/REFERENCE_PROJECTS.md` in full before execution. This plan implements the
> accepted 2026-08-26 scene-first amendment without changing Film Camp's generation-
> readiness endpoint or the vendored skill. Run changed-path lanes throughout and the
> full gate before marking this plan done.

## Status

- **Status**: DONE
- **Depends on**: Plan 021 `DONE`, bundle schema v8 shipped
- **Category**: domain / storage / AI / export / tests

## Contracts

### A. Schema v9 and lossless migration

- Add `scene_prompt_sets`, `scene_prompt_cards`, and
  `scene_prompt_card_references`. A set owns the shared scene/profile digest, format
  version, skill identity, provenance, creation ordering, and human-edited marker. Cards
  own dense order, title, body, guidance, duration, aspect ratio, and resolution. Card
  references own a dense local `@Image N` and immutable asset-version citation.
- Migrate every v8 `scene_prompts` row and its citations into a one-card set, byte for
  byte and in the same history/current order. Existing bundle history, staleness,
  provenance, and undo semantics remain observable after migration.

### B. Domain, reads, mutations, and readiness

- Replace singular package APIs with `ScenePromptSet`, `ScenePromptCard`,
  `ScenePromptCardReference`, plus set detail/proposal/apply types. Package detail exposes
  the current set and ordered history.
- Controlled mutations create a hand-written set; edit, add, delete, and reorder cards;
  and delete/restore a complete set. Manual adjustment marks the set human-edited while
  preserving creation provenance. A complete generation commit and each manual action is
  one undoable journal entry.
- Generation Ready derives from one fresh, valid current set for the active profile.

### C. Structured generation contract

- `GenerateScenePromptTask` schema version 2 returns 1–32 ordered cards with at most
  64 KiB of combined prompt body. One card is the default; split only when a scene cannot
  fit the target's 30-second limit or contains incompatible generation jobs.
- Each card returns its ordered mapping to approved input references. The mapping defines
  local dense `@Image 1...N`. Validation rejects gaps, duplicates, unknown sources,
  unused attached images, absent declarations, invalid settings, or missing role,
  exclusion, and fidelity language where the active profile requires it.
- The applier rebuilds the input digest and validates/commits the whole set atomically.
  One invalid card or changed digest rejects everything. Regeneration preserves the prior
  set in history and commits the replacement as one undoable entry.

### D. Deterministic export

- Export one directory per card containing exact prompt bytes and only that card's locally
  numbered reference files. Verify bytes against immutable citations and omit unrelated
  scene references.

## Steps

1. Land schema v9, row types, migration, and lossless migration tests.
2. Land set reads, controlled mutations, journal/undo behavior, staleness, and readiness.
3. Upgrade builder/schema/validator/applier and recorded replay to atomic multi-card sets.
4. Upgrade deterministic export and golden fixtures.
5. Run package/app-unit changed-path lanes, the full verification gate, and record status.

## Done criteria

- [x] Every legacy prompt migrates to one byte-equivalent card with current/history order.
- [x] Manual and generated set operations are atomic, journaled, undoable, and tested.
- [x] 1–32 cards, combined 64 KiB, local numbering, declarations, and settings validate.
- [x] Export golden fixtures prove exact bytes, names, hashes, and unrelated-ref omission.
- [x] Changed-path and full verification gates pass.

## STOP conditions

1. Work requires a `Shot`, take, clip, timeline, or generated-video model.
2. Work requires changing `PromptSkills/` or storing provider credentials.
3. The structured runner lifecycle itself must change rather than its task payload/commit.
4. A migration cannot preserve prompt bytes, history order, provenance, or current choice.
5. A generation result cannot be validated and committed as one transaction.
