# Plan 010: Requirement editing, review, and the deterministic manifest (Phase 2a)

> **Executor instructions**: Read `docs/PHASE2_DESIGN.md` in full first. This plan implements its
> §5, §6.3's requirement-side transitions, §7.1–§7.2, §7.4, and §7.5's review-side plumbing — the
> filmmaker can Build the canonical manifest and edit every requirement, with a Manifest section
> in the app. Media stays out (Plan 011): the asset-touching halves of `combineRequirements`,
> `rejectRequirement`, and `setRequirementNecessity` are built against SQL-seeded asset rows and
> the `AssetStatusRecompute` function defined here; no operation in this plan creates an asset.
> Follow the steps in order, run every verification command, honor every STOP condition. Requires
> Plan 009 `DONE`. When complete, set this plan's row in `docs/plans/README.md` to `DONE`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   84c3599561dac60fd02d00d8a3d6a564558bac340fb5988d8bcc83868748ff68 docs/PHASE2_DESIGN.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all three print `OK`. If the PHASE2 hash differs, stop for reconciliation when §5,
> §6.3, §7, §13.9, or §13.11–§13.12 changed.
>
> **Live gates: none.** Nothing here calls Codex; every command must pass with no network. A
> step that appears to need a live call is a STOP condition, not a deferral.

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: XL, approximately 12–15 focused engineering days
- **Risk**: HIGH; this is the Plan 005 of Phase 2 — many operations, each needing an inverse that
  round-trips byte-identically, plus the entity-operation interactions (§7.4) that modify Plan
  005's merge/delete capture lists
- **Depends on**: 009
- **Category**: feature / architecture / tests
- **Planned at**: commit `e8645e5`, 2026-08-21; design hash in the drift check

## Current state

- Plan 009 shipped schema v4, the domain types, the engine maps, `ManifestQualification`, and the
  reads. Requirement rows exist only via test SQL; no operation writes them.
- Plan 005's operation files are the templates: every new operation family follows
  `EntityOperations`' shape — a `MutationEffect`-returning static func plus `precheck*` helpers,
  no transaction opened (the reentrancy test globs `Editing/*.swift` and covers new files
  automatically).
- The app has the Plan 004/005 shell; entity review, locks, and undo work. The Manifest section
  does not exist.

## Contracts (normative)

### A. Operations (design §7.2, verbatim — the table there is the contract)

- Every §7.2 operation exists as an `EditOperation` case with the inverse, validation, and notes
  written there, dispatched through `EditPrimitives.mutate`'s exhaustive switch, named in
  `displayName`, carried through `isInvertible` / `compoundChildren` (all new cases `nil`) /
  `batchName` / `InverseApplication.precheck`. New files: `Editing/RequirementOperations.swift`,
  `Editing/TemplateOperations.swift`, plus `Editing/AssetStatusRecompute.swift` holding §6.3's
  five-rule recompute as a pure function over rows (its full operation set arrives in Plan 011;
  here it backs `rejectRequirement`, `unrejectRequirement`, and `setRequirementNecessity`, whose
  groups recompute any existing asset row to/from `deprecated`, preserving `rejected_explicitly`).
- `combineRequirements` and `splitRequirement` per §7.2's full specifications: variant-tier only,
  cross-entity sources permitted (combined requirement lives on the target's entity), assets
  merge with deterministic version renumbering and the approved-survivor rule, filenames stay
  historical, sources tombstoned with their emptied graphs snapshotted, locks block both, and
  the payload-driven inverses round-trip byte-identically (table-snapshot digests before and
  after apply→inverse).
- `refreshCanonicalRequirements` per §5.2: a `performGroup` of `createCanonicalRequirement` +
  seeded-dependency children built at the call site, `parser`-sourced, idempotent. Its engine
  entry returns §5.2's typed **`ManifestBuildResult`** (`created`, `collisions` pairs naming the
  blocked template entry and the existing row, `entry: JournalEntry?`) and **guards before
  `performGroup`** — the group primitive always journals when invoked, so the empty-children
  case skips it and returns `entry: nil` (test: two consecutive Builds, second adds no journal
  row). §3.5's two-direction dependency seeding with tombstone respect (including the
  late-canonical mirror rows); a name collision is a counted skip, never a throw, per §5.2.
- Dependency operations enforce §3.5's full-graph cycle/self-edge walk; `removeDependency` and
  `removeRequirementScene` tombstone `ai`/`parser` rows per Phase 1 §3.6.
- `deleteRequirement` refuses while an asset row exists; hard delete only for human/tombstoned
  rows, tombstone otherwise (the engine routes, as entity delete does).

### B. Review integration (design §7.1's write-surface paragraph, §7.2's review paragraph, §7.5)

- `ReviewOperations.expand(refs:)` gains the requirement case (scene links + dependencies; basis
  excluded); `proposedRefs` gains the three reviewable tables; `acceptFacts` /
  `acceptAllProposed` then work on requirement refs with no further change. The human-only
  guards (`requireHuman`) cover template, inclusion, necessity, and review operations; AI-actor
  behavior over the new rows is exercised by a lock/protection/rejection matrix test
  (actor × lock × op) mirroring Plan 005's, including the parser-owned `name` on canonical
  requirements and the ordinary lifecycle on `ai`-sourced ones.

### C. Entity-operation interactions (design §7.4, verbatim)

- Extend Plan 005's `EntityOperations` delete capture and `MergeSplitOperations` move lists per
  §7.4: hard-delete refusal with assets, requirement-graph snapshots in `restoreEntity`,
  merge collision-survivor over `(entity_id, type_id)` and `(entity_id, name_normalized)` with
  the both-assets refusal and tier-dependent remedy wording, single-asset re-point, dependency
  retarget + re-check, split leaves requirements, reclassify refused with canonical
  requirements, and basis-row sweeps on every direct **and cascaded** fact deletion (the
  orphaned-basis-row query runs after every merge/split/delete test, both paths). Basis tests
  assert exact §7.2 placement, not only orphan absence: after a split, a basis row whose fact's
  scene footprint moved entirely sits on the new requirement, an overlapping one exists on
  **both** (the copy carries the same subject), and a non-overlapping one stayed; after a
  combine, moved basis rows cite the surviving requirement with subjects unchanged.

### D. The Manifest UI (design §5.1–§5.3, §6.1's display rule, §8.6's grammar without inference)

- A **Manifest** sidebar section: requirement list grouped by entity (tier badges, necessity,
  review state, lock icon, asset display state — Needed for slot-without-asset), a requirement
  inspector (name, reason, necessity, derived or stored `requiredBy` with jump-to-scene,
  dependencies, basis with evidence jump links, provenance line, locks), the **Build Asset
  Manifest** action, the §5.3 drift badges, the §3.7 **"based on unreviewed AI facts"** badge
  (rendered from `RequirementDetail`'s derived flag; clears when the underlying fact is
  accepted), and `ManifestSummary` counts in the section header.
  Filters: Proposed / Accepted / Rejected, per the entity sections' grammar. Every action routes
  through contract A's operations via the window model; batch actions are one undo step; the
  Entity menu gains the requirement commands mirroring the context menu. Accessibility per Plan
  004's rules (identifiers + labels, `.accessibilityElement(children: .contain)` on named
  containers).
- UI tests (`Phase2ManifestUITests`) plus headless window-model twins: Build populates the list;
  rename/necessity/reject/undo via the Edit menu; combine two seeded variants; a locked
  requirement's fields read-only; drift badge appears after an appearance edit drops an entity
  below 2 scenes; a Build name collision (§5.2) skips with its badge rather than erroring.

## Target file layout (additions, changes)

```text
Packages/FilmCore/
  Domain/EditOperation.swift (+cases), Editing/ RequirementOperations.swift,
  TemplateOperations.swift, AssetStatusRecompute.swift (new), ReviewOperations.swift (expand,
  proposedRefs), EntityOperations.swift + MergeSplitOperations.swift (§7.4),
  ProjectTools.swift + ProjectTools+Editing.swift (+§7.2 wrappers)
  Tests/ RequirementOperationTests, CombineSplitRequirementTests, TemplateOperationTests,
  RequirementReviewTests, EntityRequirementInteractionTests, RecomputeTests
AI Film Camp/ Views/Manifest/ (new section + inspector), ProjectWindowModel+Manifest.swift,
  Commands additions; Tests/ + UITests/Phase2ManifestUITests.swift
project.yml unchanged (new sources under existing targets' paths)
```

## Steps

### Step 1: Operation families and recompute

Contract A without combine/split; then combine/split with their inverses.

```bash
swift test --package-path Packages/FilmCore
```

Expected: every op's apply + inverse round-trip on table snapshots; refresh idempotence and
no-op-journals-nothing; tombstone-respecting dependency seeding both directions; the recompute
walk `rejectAsset`-analog cases seeded by SQL (deprecation preserves `rejected_explicitly`).

### Step 2: Review integration and entity-op interactions

Contracts B and C.

```bash
swift test --package-path Packages/FilmCore
```

Expected: the actor × lock × op matrix; accept of a proposed requirement sweeps its proposed
links/dependencies; merge/delete/reclassify/split behave per §7.4 with byte-identical restores
and zero orphaned basis rows on both deletion paths.

### Step 3: Manifest section

Contract D, then full verification.

```bash
swift test --package-path Packages/FilmCore
./scripts/verify.sh
```

Expected: both suites, app unit tests, and the UI suites exit 0. Update
`docs/plans/README.md`, and append the one-paragraph `docs/ROADMAP.md` Requirement Review
restatement of design §13.9. (Stated deviation: the design assigns that edit to "the first
Phase 2 plan", which is 009; it is deliberately carried here instead, where requirement review
becomes real — the README records the same routing.) **In the same commit as the ROADMAP edit,
update the ROADMAP hash in the drift block of every plan that pins it — Plans 002–009 and 012
all pin the same digest, not only Plan 012** (Plan 001 is exempt: `check-docs.sh` excludes it) —
because `scripts/check-docs.sh` executes every plan's drift block, so verify.sh-adjacent gates
fail until every pin and the file agree.

## Done criteria

- [ ] `./scripts/verify.sh` exits 0; every §7.2 operation exists with a round-tripping inverse;
  combine and split satisfy §7.2's variant-tier, cross-entity, asset-merge, and tombstone rules;
  refresh is idempotent and journals nothing when empty.
- [ ] Requirement review runs through `acceptFacts`/`acceptAllProposed` with the expand case; the
  AI-actor write surface of §7.1 is enforced and matrix-tested.
- [ ] §7.4's entity-operation interactions are implemented with requirement-graph snapshots and
  cascaded basis sweeps; no orphaned basis row survives any test.
- [ ] The Manifest section Builds, lists, edits, badges drift, and undoes per contract D;
  `docs/ROADMAP.md` carries the §13.9 restatement; `docs/plans/README.md` marks Plan 010 `DONE`.

## STOP conditions

- The `docs/PHASE2_DESIGN.md` hash differs and §5, §6.3, §7, or §13.11–§13.12 changed.
- A combine or split inverse cannot restore byte-identical tables (report the differing table and
  column rather than weakening the digest assertion).
- §7.4's changes to Plan 005's merge/delete break an existing Plan 005 test in a way one scoped
  correction does not fix.
- A verification command fails twice after one reasonable scoped correction.
- Work expands into media import, approval, staleness fan-out, or inference (Plans 011–012).

## Maintenance notes

- `AssetStatusRecompute` is deliberately ahead of its operations: Plan 011 adds the version
  operations that exercise rules 2–5 for real and must not redefine the function.
- The Manifest section's review grammar is reused by Plan 012's proposal review; keep filters and
  actions on the window model, not in views.
