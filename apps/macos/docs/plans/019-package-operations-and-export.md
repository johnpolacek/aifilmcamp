# Plan 019: Package operations, skill import, and export (Phase 5a)

> **Executor instructions**: Read `docs/PHASE5_DESIGN.md` in full first. This plan
> implements its §7.1 (every new operation), §3.6 (the style bible as a mutable
> document), §14.6's operation half (`importSceneSkill` / `selectSceneSkill` with the
> stated undo posture and the FilmCore integrity gate), §3.8 + §4.1 (the staged,
> verified, atomic exporter — the first consumer of `exports/`), and §6.2's
> operation-level gesture consequences. **No UI and no AI**: every operation and the
> exporter are reachable from tests and (for the exporter) a temporary debug entry
> point only — the Generation section is Plan 020's, the job is Plan 021's. Follow the
> steps in order, run every verification command, honor every STOP condition. Requires
> Plan 018 `DONE`. When complete, set this plan's row in `docs/plans/README.md` per the
> Done criteria.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   bd477ef76dbb98c2f7dbffdae5310b8f824e309e904bcd91f03cca2004eb7ee1 docs/PHASE5_DESIGN.md \
>   90dc7842e286b2bbf556a02384096448694d4a698fd24f64a3cdc5ebd4fcb3d7 docs/PHASE3_DESIGN.md \
>   330c79f1905f51f2fd82413cd03cef68a336f630678d757143f8b524bbbc0e3c PromptSkills/README.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all four print `OK`. `docs/OVERVIEW.md` is deliberately unpinned (Plan 020
> edits it). Plan 018 legitimately re-pins nothing here; on a PHASE5 mismatch, diff the
> design and stop only if §3.6, §3.8, §4.1, §6.2, §7.1, or §14.6–§14.7 changed.
>
> **Live gates: none.** Nothing in this plan calls Codex.

## Status

- **Status**: DONE — every §7.1 operation, the §14.6 import flow with its undo posture,
  and the staged/verified/atomic exporter landed with tests; the byte-exact expected
  package is committed; no UI and no AI surface exists (Plans 020–021 own those). The
  recorded interpretations are in IMPLEMENTATION_NOTES (the parity seam, `''`-allowed
  settings, the replace-dance rationale)
- **Priority**: P1
- **Effort**: L, approximately 8–10 focused engineering days
- **Risk**: MED-HIGH; the exporter is the first code to write outside the canonical
  store's tables since media import, and its staged-atomic discipline plus the
  byte-for-byte expected-package tests are new test machinery; `createScenePrompt`'s
  provenance parity duplicates the AI attach's capture path and must not fork it
- **Depends on**: 018
- **Category**: feature / storage / tests
- **Planned at**: commit `dce8971`, 2026-08-23; design hashes in the drift check

## Current state

- Plan 018 ships schema v6, the domain types, the derivations, the reads, the input
  builder, and `SkillTreeOperations`; nothing writes the new tables yet.
- `exports/` is created at bundle creation and referenced by nothing (design §12);
  `BundleContainment` and `RelativeProjectPath` are the write discipline;
  `ScreenplayWriter` is the file-emitting precedent.
- The shipped op families to mirror: `importAssetVersion` (file-and-row import),
  `createPrompt`/`setPromptBody`/`deletePrompt` (prompt history), the `batch` grouping
  op (one ⌘Z step), and the `clearOrphanedMedia` pair, whose read/confirm/clear shape
  the new typed skill-tree orphan surface mirrors at tree scale.

## Owner gates (design §13/§14)

- **§14.5 (style bible: one free-text document, journaled, digested) — ACCEPTED
  2026-08-23 as recommended.**
- **§14.6's operation half (import-into-bundle, the undo posture, the runtime
  integrity gate) — ACCEPTED 2026-08-23 as recommended**, including the fourth
  revision's atomic-verification clause (the authoritative check is Plan 021's
  coordinator + the materialiser; this plan lands the FilmCore gate and the ops).
- **§14.7 (batch export fresh-only; single stale export behind a named confirm) —
  ACCEPTED 2026-08-23 as recommended.** The confirm *copy* ships here as refusal/
  confirm text; the sheet itself renders in Plan 020.

## Contracts (normative)

### A. The prompt and project operations (design §7.1)

- `createScenePrompt` — **the human counterpart of the AI attach**: enforces §8.1's
  pre-flight (Asset Ready via the snapshot, counted scene, cataloged profile, within
  the profile limit) and, in its own transaction, rebuilds the §8.2 input and captures
  digest, `input_format_version`, citation rows from that same plan, and profile
  settings. Provenance `human`/`human`, skill triple empty. 64 KB UTF-8 body cap.
- `setScenePromptBody` — body and provenance `source` only; citations and digest
  untouched.
- `deleteScenePrompt` / `restoreDeletedScenePrompt` — the Phase 3 history gestures at
  scene scope; delete-the-newest restores the prior row to current.
- `setStyleBible` — the §3.6 document; digest input, so it stales every scene prompt
  (that consequence is a §10 assertion, not a bug).
- `setGenerationTargetProfile` — the §3.3 headline flip; trivially invertible; stales
  nothing.
- All are journaled, invertible `EditOperation` cases entering through
  `EditPrimitives.perform`, with `displayName` copy for ⌘Z.

### B. Skill import (design §7.1, §14.6)

- `importSceneSkill`: copy the chosen tree through `SkillTreeOperations` into
  `skills/<skill id>/`, verify the computed `tree_sha256` **before** the row lands,
  insert the `imported_skills` row, auto-select — import + selection journal as one
  grouped entry (the shipped `batch` op), one ⌘Z step.
- Undo posture, exactly as stated: undo removes row and selection, **leaves the tree
  as an orphan**; redo re-verifies the retained tree against `tree_sha256` and refuses
  via `.importedSkillTreeMissing` if gone or altered.
- `selectSceneSkill`: the `projects.scene_skill_id` flip; `NULL` restores the bundled
  default; stales nothing (skill payload is outside the digest).
- Orphan cleanup is a **typed, confirmed surface, not an implied walk**:
  `orphanedSkillTrees()` (a read listing unreferenced `skills/` subtrees
  with per-tree byte counts) and `clearOrphanedSkillTrees()` (removal
  through `BundleContainment`, refusing any path outside `skills/`,
  deleting only trees no `imported_skills` row references) — the shipped
  orphaned-media pair's shape at tree scale, never a widening of the
  file-oriented `clearOrphanedMedia`. The confirm copy names the tree
  count and total size before clearing, and the control rides the
  existing maintenance surface beside Clear Orphaned Media. Recursive
  directory deletion happens nowhere outside this operation's
  containment checks.
- The FilmCore run gate re-verifies `tree_sha256` for the selected skill (early
  feedback; the authoritative staging-walk comparison is exercised end to end in
  Plan 021).

### C. The exporter (design §3.8, §4.1)

- `ScenePackageExporter` writes `exports/scenes/scene-<ordinal>/` — `prompt.md` (the
  stored body, byte-exact), `scene.json` (the §4.1 field list, `sortedKeys`, no
  timestamps/job ids/locale), `references/NN-<requirement slug>.<ext>` in designator
  order.
- **Staged, verified, atomic**: build complete in `scene-<ordinal>.staging` (removed
  on entry if a prior attempt left one, never enumerated as a package); every copied
  reference re-hashed and equal to the approved version's stored SHA-256 **before**
  the hash is recorded (`.packageReferenceVerificationFailed(path:)` on mismatch,
  nothing written); only a fully verified staging directory replaces the destination.
- Deterministic to the byte given the same rows — the committed expected-package
  fixtures are compared byte for byte (the roadmap's own testing-strategy line).
- Grains: one scene; a sequence; all Generation Ready — the latter two loop over the
  Generation Ready set **under the active profile** and are pure file work, no
  generation, no spend.
- Export requires a current prompt (`.scenePackageExportRequiresPrompt`); a stale
  single-scene export is permitted only through the §14.7 confirm naming the reason;
  batch takes fresh Generation Ready scenes only.
- Export is **not** an `EditOperation`: no journal entry, no undo.

### D. Gesture consequences (design §6.2)

Every row of the §6.2 table is asserted at the operations level: approval flips,
necessity flips, scene-link and rename edits, `setStyleBible`'s project-wide staling,
`setScenePromptBody`'s freshness neutrality, `deleteScenePrompt`'s current-row shift,
readiness regression, `setGenerationTargetProfile`'s stale-nothing headline flip, and
undo across all of them.

## Steps

1. **Prompt and project operations.** Contract A with per-op inverse tests and the
   provenance-parity test (human capture ≡ AI attach capture over the same state).
2. **Skill import.** Contract B with the undo-posture battery: orphaned tree on undo;
   redo refusal on missing/altered tree; one-⌘Z grouped import; orphan sweep removing
   only unreferenced trees; symlink/unsafe-path refusal via the FilmCore fixtures.
3. **The exporter.** Contract C with the byte-for-byte expected packages, the staged
   atomicity fault-injection test (copy failure mid-package leaves the previous export
   byte-identical), the tamper test, and the three grains.
4. **Gesture walks.** Contract D, the full §6.2 table.
5. **Record-keeping.** Note in `docs/IMPLEMENTATION_NOTES.md` anything the exporter's
   determinism required that the design did not spell out; flip the README row.

## Verification

- `./scripts/verify.sh` passes (recorded environmental-flake posture for the UI phase).
- `./scripts/check-docs.sh` passes.
- The expected-package fixtures are committed and byte-asserted.

## Done criteria

- [ ] Every §7.1 operation lands, journaled and invertible, with the §6.2 walk green.
- [ ] `createScenePrompt` provenance parity is test-proven against the attach path.
- [ ] The import undo posture matches the design word for word, tests included.
- [ ] Export is staged/verified/atomic with committed byte-exact expected packages.
- [ ] §14.5–§14.7 still read ACCEPTED in the design; the README row is flipped.

## STOP conditions

1. The PHASE5 hash differs *and* §3.6, §3.8, §4.1, §6.2, §7.1, or §14.6–§14.7 changed.
2. `createScenePrompt` cannot reuse the attach path's capture without forking it —
   report; two capture paths is a design divergence.
3. The exporter cannot achieve byte-determinism (an encoder or filesystem-ordering
   gap) — report the field; do not drop the byte-for-byte assertion.
4. Atomic replacement cannot be made safe on the target filesystem — report; do not
   ship delete-then-write.
5. Work expands into UI surfaces, the AI job, batch generation, or a provider.
6. A verification command fails twice after one reasonable scoped correction.

## Maintenance notes

- The exporter owns `exports/scenes/` wholesale; anything else under `exports/` is
  future surface and must get its own subdirectory, never share this one.
- `scene.json`'s field list is part of the package identity; additions are a
  `schemaVersion` bump there and new expected-package fixtures, never silent.
