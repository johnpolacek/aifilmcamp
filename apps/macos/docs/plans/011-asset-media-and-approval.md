# Plan 011: Asset media, versions, and approval (Phase 2a)

> **Executor instructions**: Read `docs/PHASE2_DESIGN.md` in full first. This plan implements its
> §4.1 (media on disk), §6.1–§6.3 in full, §7.3, and the staleness fan-out of §3.5 — the
> filmmaker fills slots with real images, approves one version as canonical, and the manifest
> answers "what is still missing". No AI is involved anywhere in this plan.
> Follow the steps in order, run every verification command, honor every STOP condition. Requires
> Plan 010 `DONE`. When complete, set this plan's row in `docs/plans/README.md` to `DONE`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   84c3599561dac60fd02d00d8a3d6a564558bac340fb5988d8bcc83868748ff68 docs/PHASE2_DESIGN.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   8660b7114aa507a98ec2cf621176355cb912b749ff3b84395e6f4af6fb927691 docs/OVERVIEW.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all four print `OK`. If the PHASE2 hash differs, stop for reconciliation when §4.1,
> §6, or §7.3 changed; the OVERVIEW pin guards the §6 asset-state vocabulary this plan stores.
>
> **Live gates: none.** Nothing here calls Codex; every command must pass with no network. A
> step that appears to need a live call is a STOP condition, not a deferral.

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: L–XL, approximately 10–13 focused engineering days
- **Risk**: HIGH; media operations mix filesystem and database state, and the design's answers —
  staged copies, rows-first deletion, orphan files, the hand-ordered `approveVersion` inverse —
  each carry a test the plan must not soften
- **Depends on**: 010
- **Category**: feature / architecture / tests
- **Planned at**: commit `e8645e5`, 2026-08-21; design hash in the drift check

## Current state

- Plans 009–010 shipped the schema, reads, requirement operations, `AssetStatusRecompute`, and
  `BundleContainment`. `assets/` is still empty in every real bundle; asset rows exist only where
  tests seeded them.
- The screenplay import path (`ProjectSession.importScreenplay`) is the pattern for staged
  atomic copies and the `-2`/`-3` collision rule; reuse its shape, not new machinery.

## Contracts (normative)

### A. Media on disk (design §4.1, verbatim — every bullet there is a contract)

- `AssetPathing` implements the slug and destination rules; paths flow through
  `RelativeProjectPath` **and** `BundleContainment` (realpath rule) on every write, read-for-UI,
  and deletion. Import sniffs magic bytes for the five image types and refuses mismatches;
  pixel dimensions read at import; `version_number` = max + 1 in-transaction; on-disk collisions
  take the stem rule. **Import limits** (`MediaImportLimits`, FilmCore constants, typed
  refusals naming the measured value): file size ≤ 256 MB, each pixel dimension ≤ 16,384, and
  decoded size ≤ 128 megapixels — the dimensions come from the image header
  (`CGImageSourceCopyPropertiesAtIndex`, no full decode), so a decompression bomb is refused
  before any pixel is decoded; previews render through a capped
  `CGImageSourceCreateThumbnailAtIndex`, never a full-size decode. Tested with an over-budget
  header fixture (a small file whose header declares huge dimensions).
- Rows-first deletion: `deleteVersion` / `deleteAsset` remove rows in the transaction and files
  after commit; a file-removal failure logs and orphans, never dangles a row. **Clear Orphaned
  Media** lists and deletes unreferenced files after confirmation, serialized through the
  session, journaling nothing.

### B. Operations and the state machine (design §7.3's table and prose, §6.1–§6.3, §3.5)

- Every §7.3 operation exists with its stated inverse, preconditions, and recompute call —
  including: `createAsset` composed into the first import's group with the implicit accept of a
  proposed requirement (via `acceptFacts` in the same group); `importAssetVersion` refused while
  the requirement is inactive, clearing `rejected_explicitly`; the **hand-ordered
  `approveVersion` inverse** (demote first, then restore, staleness snapshots included) with a
  test that a generic snapshot-order restore would fail (assert the partial-index violation is
  avoided by construction); `rejectAsset`/`unrejectAsset` over `rejected_explicitly`;
  `deleteVersion` allowed only on rejected versions, clearing the explicit rejection when it
  removes the last row; `clearAssetStale`; notes setters.
- Staleness fan-out per §3.5: only an approved-version *change* marks dependents, with
  `stale_since`/`stale_reason` set and the affected set naming every touched asset; first
  approval marks nothing; no transitive cascade; and `approveVersion` **clears the target
  asset's own** `is_stale`/`stale_since`/`stale_reason` (§6.3's row as revised — approving a
  new version is one of §3.5's two clearing gestures; test: stale asset, approve a new
  version, flag gone, dependents marked).
- §6.3's recompute rule and operation table become an exhaustive table test, including: the
  rejection-survives-deprecation walk; deprecated-with-approved restoring to Approved; the §7.3
  undo/redo/orphan walk verbatim (refused redo after re-import and after Clear Orphaned Media,
  SHA re-verification); the §6.1 approved-version invariant asserted after every asset op.
- A bundle close/move/reopen test asserts every version resolves and verifies size (the Phase 0
  Finder-move discipline extended to media).

### C. The fill-and-approve surface (design §1's missing-assets criterion; the workshop UX stays Phase 3)

- The requirement inspector gains the minimal slot surface: import (open panel + drop target),
  version list with status and approve/reject/delete actions, the stale badge with reason and
  Mark Current, and the asset display state. The Manifest section header surfaces
  `manifestSummary()` and a Missing filter backed by `missingAssets()`. Clear Orphaned Media
  lands next to Clear Job Cache. No prompt generation, no generation providers, no dedicated
  workshop window — Phase 3 builds those on this contract.
- UI tests plus headless twins: import → approve → summary counts change; approve a different
  version → dependent shows the stale badge → Mark Current clears it; delete refused/confirmed
  flows; a symlinked `assets/` subdirectory — and a symlinked final leaf — makes import,
  preview/hash reads, Reveal, and delete refuse per §4.1's no-follow rules (automation plants
  the symlink in a temp bundle).

## Target file layout (additions, changes)

```text
Packages/FilmCore/
  Domain/AssetPathing.swift (new), Editing/AssetOperations.swift (new),
  Editing/AssetStatusRecompute.swift (exercised, unchanged shape),
  Storage/ProjectSession+Media.swift (staged import, rows-first deletion, orphan sweep),
  ProjectTools.swift (+§7.3 wrappers, clearOrphanedMedia)
  Tests/ AssetOperationTests, ApproveInverseTests, StalenessTests, MediaImportTests,
  OrphanWalkTests, MediaContainmentTests, MediaMoveTests, StateMachineTableTests
AI Film Camp/ Views/Manifest/ (inspector slot surface), ProjectWindowModel+Assets.swift;
  UITests/Phase2AssetUITests.swift
```

## Steps

### Step 1: Media import and the operation family

Contracts A and B without staleness; the §7.3 walk tests.

```bash
swift test --package-path Packages/FilmCore
```

Expected: staged-import atomicity (throw-after-copy and throw-after-insert both leave zero
residue on the failing side), magic-byte refusal, numbering, collisions, rows-first deletion,
orphan sweep, containment refusals.

### Step 2: Approval, staleness, state machine

The rest of contract B.

```bash
swift test --package-path Packages/FilmCore
```

Expected: the hand-ordered inverse round-trips including dependent staleness; the state-machine
table test covers every §6.3 row; the invariant holds after every op; move/reopen resolves all
media.

### Step 3: Fill-and-approve surface, verification

Contract C.

```bash
./scripts/verify.sh
```

Expected: all suites exit 0. Update `docs/plans/README.md`. Record in
`docs/IMPLEMENTATION_NOTES.md` a manual check: one real image imported, approved, and surviving
a Finder move on a real bundle.

## Done criteria

- [ ] `./scripts/verify.sh` exits 0; every §4.1 bullet and §7.3 row is implemented and tested as
  written, including the hand-ordered `approveVersion` inverse, the undo/redo/orphan walk, and
  realpath containment on every media path.
- [ ] §6.3's recompute is the only writer of `assets.status`; the table test and the
  approved-version invariant pass; staleness fans out and clears per §3.5.
- [ ] The filmmaker can fill, approve, and audit missing assets in the app with no AI and no
  Phase 3 scope (no prompts, no providers, no workshop window); Clear Orphaned Media works.
- [ ] `docs/plans/README.md` marks Plan 011 `DONE`.

## STOP conditions

- The `docs/PHASE2_DESIGN.md` hash differs and §4.1, §6, or §7.3 changed.
- Any sequence leaves a database row referencing a missing file (report the sequence; the
  rows-first rule should make this impossible).
- The `approveVersion` inverse cannot avoid the partial-index violation without weakening the
  byte-identical restore.
- A verification command fails twice after one reasonable scoped correction.
- Work expands into prompt generation, providers, readiness dashboards, or inference (Phases 3–4,
  Plan 012).

## Maintenance notes

- The five image types and their magic signatures live in one place (`AssetPathing` or a sibling);
  Phase 3's generation import reuses them.
- `orphanedMedia()` (Plan 009's read) is now meaningful; keep its definition "file no version row
  references" — nothing else may count as orphaned.
