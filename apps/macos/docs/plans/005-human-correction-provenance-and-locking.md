# Plan 005: Human correction, provenance, and locking (Phase 1a, part 3)

> **Executor instructions**: Read `docs/PHASE1_DESIGN.md` in full first; this
> plan implements its §3.5–§3.8, the editing half of §3.11 (including the scene
> synopsis editor), and §6, re-verifies Plan 003's §5.5 replace guard, and
> populates the tables Plan 003 created. Follow the steps in order, run every
> verification command, and honor the STOP conditions.
> Requires Plan 004 `DONE`.
> When complete, set this plan's row in `docs/plans/README.md` to `DONE`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   1f0e224d9d668bc10fa01ab55bf60e115b14bafd0931eb81c26d152d5a4467ac docs/ROADMAP.md \
>   8660b7114aa507a98ec2cf621176355cb912b749ff3b84395e6f4af6fb927691 docs/OVERVIEW.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all print `OK`. If any differs, compare the change against this plan
> and stop for reconciliation when editing semantics, lock rules, provenance, the
> journal contract, or §5.5 replace rules changed.

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: XL, approximately 12–15 focused engineering days
- **Risk**: MED-HIGH; the risks are a generic reversible mutation engine (three journal levels over every operation), inverse completeness (an undo that loses rows), merge collisions under three uniqueness constraints, affected-set conflict detection, serialized undo over an async store, and the breadth of the editing UI
- **Depends on**: 004
- **Category**: feature / architecture / tests
- **Planned at**: commit `02cf45c` + Plans 002–004; design hash in the drift check
- **Live gates**: none. Nothing here calls Codex; every command must pass with no network and without `FILMCAMP_RUN_LIVE_CODEX`, and Plan 001's live tests must keep skipping when it is absent. A step that appears to need a live call is a STOP condition, not a deferral.

## Why this matters

Completes roadmap Phase 1a ("usable on its own, no AI involved"): every fact carries provenance, humans can correct the breakdown, every edit is journaled with a full-snapshot inverse, and the rules that stop AI from overwriting human decisions exist **before** any AI extraction runs (Plan 007). Re-import of a revised draft and re-parse stay out of scope (design §5.5, §14.3). No AI action in the app after this plan.

## Current state (after Plan 004)

- Bundle schema v2 (Plan 003) holds every Phase 1 table of design §4.3, including `edit_journal`, `edit_journal_affected`, and `locks`; only parser facts populate them (§5.3). `locks`, `entity_states`, `continuity_events`, `entity_relationships` are empty.
- `ScreenplayEditing` (design §3.9a) is declared and empty. `ProjectSession` (`public actor`) is the only `ProjectTools` conformer; `ProjectRepository` (internal `struct: Sendable` over `database.queue`, a `GRDB.DatabaseQueue`) is the only place SQL is written.
- `EditOperation`, `MutationEffect`, `SubjectRef`/`SubjectKind`, `RowSnapshot`/`JSONValue`,
  `JournalEntry` (with its `affected` set and `invertsSeq`), `JournalStore`, and the
  `mutate`/`perform` primitives **exist** from Plan 003 in their final shapes — in
  `Domain/EditOperation.swift`, `Domain/SubjectRef.swift`, `Domain/JournalEntry.swift`,
  `Editing/RowSnapshot.swift`, `Editing/JournalStore.swift`, `Editing/EditPrimitives.swift` —
  carrying only the non-invertible `.importScreenplay`/`.replaceScreenplay` cases. So do
  `ConfidenceBand`, `EntitySummary`, `EntityDetail.locks`, `locks()`, the PROV columns
  `reviewed_at` and `created_source`, and `edit_journal.inverts_seq` (written by nothing yet). This
  plan extends those files with every remaining case, its inverse, `performGroup`, and
  `applyInverse`; it does not redefine them. `ProjectStoreError` has the Phase 0 cases plus
  `mutationInProgress`, `importRefusedDuringRun`, `replaceRefused(reason:)`, and
  `aliasConflict(existingEntityID:)`; the §5.5 replace guard (`canReplaceScreenplay()` and the
  refusal) is **implemented in Plan 003** and only re-verified here.
- Read the `AI Film Camp/` sources for the shell (Plan 004): read-only `EntityListView` and `EntityInspectorView`, `RevealTarget` + `ProjectWindowModel.reveal(_:)`, refresh via `ProjectObserving.changes()`. No undo, no inspector editing, no lock UI.
- **Duplicate Project… ships in Plan 004's File menu and is not re-specified here.**
- Packages test with Swift Testing, app targets with XCTest; `TemporaryProject.create` builds real temporary bundles.

## Contracts (normative; §6 is the operation list, §3.5–§3.8 the rules)

### Three levels of mutation (§3.8)

```swift
// all internal to FilmCore; each assumes an open transaction and never opens one
extension ProjectRepository {
    func mutate(_ op: EditOperation, actor: MutationActor, in db: Database) throws -> MutationEffect
    func perform(_ op: EditOperation, actor: MutationActor, jobID: UUID?, in db: Database) throws -> JournalEntry
    func performGroup(_ ops: [EditOperation], as compound: EditOperation,
                      actor: MutationActor, jobID: UUID?, in db: Database) throws -> JournalEntry
}
struct MutationEffect {                 // internal; never crosses the package boundary
    let inverse: EditOperation?         // nil ⇒ non-invertible; computed here, never a property of the op
    let affected: Set<SubjectRef>
    let snapshots: [RowSnapshot]
    let skippedAliases: [String]        // merge: source names that collided with a third entity's alias
}
```

| level | journals | used by |
|---|---|---|
| `mutate` | nothing | `perform` and `performGroup` only |
| `perform` | exactly one row | every public `ScreenplayEditing` wrapper; Plan 007's `applyExtractionRun`, once per underlying change |
| `performGroup` | exactly one row whose `op` is the compound case and whose payload holds every child inverse **in order** | batch UI ops (`deleteEntities`, `rejectEntities`, `setRelevance(ids:)`), `acceptAllProposed`, `mergeEntities` with more than one source |

- Public wrapper shape, inside the `ProjectSession` actor exactly as Phase 0 writes:
  `try database.queue.write { db in try repository.perform(.renameEntity(id:name:), actor: actor, jobID: actor.jobID, in: db) }`
  — synchronous on the actor (no `await` inside the write, so the actor is not reentrant across a
  write), one transaction, one row, return the `JournalEntry`. `createEntity` and `splitEntity`
  return `(entry: JournalEntry, entityID: UUID)` because the UI must select the new row;
  `mergeEntities` returns `MergeResult { entry, skippedAliases }`; every other wrapper returns the
  `JournalEntry` alone.
- `performGroup` runs `mutate` per child in order, unions the children's `affected`, concatenates their snapshots, inverts as the group of child inverses **applied in reverse order**, and fails the whole transaction if any child throws.
- **No public operation is ever called from inside another**: `DatabaseQueue` is not reentrant and a nested `queue.write` deadlocks the session. Compound behavior comes from `mutate`, never from calling a wrapper.
- `applyExtractionRun` (Plan 007) is the deliberate exception: `perform` per underlying change inside its own transaction, so a run reverts change by change (§8.5).
- `jobID` is `nil` for `.human` and the actor's job for `.ai(jobID)`; `perform` asserts the pairing.
- `public enum EditOperation: Codable, Equatable, Sendable` — the **complete** case list, which
  `JournalInverseTests` switches over exhaustively:
  - one case per §6 operation: `createEntity`, `deleteEntity`, `rejectEntity`, `unrejectEntity`,
    `renameEntity`, `setDescription`, `reclassify`, `setRelevance`, `setLocationParent`,
    `addAlias`, `removeAlias`, `mergeEntities` (one source), `splitEntity`, `setSceneEntity`,
    `removeSceneEntity`, `setSynopsis`, `addState`, `editState`, `removeState`, `addEvent`,
    `editEvent`, `removeEvent`, `addRelationship`, `removeRelationship`, `lock`, `unlock`,
    `acceptFact(SubjectRef)` (the per-fact child that `acceptFacts`/`acceptAllProposed` group)
    and its inverse `unacceptFact(SubjectRef, priorState: ReviewState)`,
    `revertExtractionRun`;
  - the inverse-only cases from design §3.8's table, each carrying its payload as associated
    values: `restoreEntity(graph: [RowSnapshot])`, `unmerge(created: [SubjectRef], moved:
    [SubjectRef], snapshots: [RowSnapshot])`, `unsplit(created: [SubjectRef], moved: [SubjectRef], sourceSnapshot:
    [RowSnapshot])`, `rejectSubject(SubjectRef)` / `unrejectSubject(SubjectRef, priorState:
    ReviewState)` (the primitives behind tombstoning removes);
  - the compound cases `.batch([EditOperation])`, `.acceptAll([SubjectRef])` (used by both
    `acceptFacts(refs)` and `acceptAllProposed()`; its `displayName` is count-aware — "Accept 2
    Facts" / "Accept All Proposed" — and its inverse is `.batch` of `unacceptFact` in reverse
    order), and `.mergeEntities` with more than one source (a group of single-source merges);
  - Plan 003's `.importScreenplay`, `.replaceScreenplay`, and Plan 007's marker
    `.applyExtractionRun(ApplyReport)` — the case, the `ApplyReport` `Codable` struct with design
    §8.5's field list, **and the `ExtractionSettings` `Codable` value its `settings` field holds**
    (chunk/reconcile model and effort, chunk budget, concurrency — plain FilmCore data, because
    FilmCore may not import FilmBrain) are declared here (`Domain/ApplyReport.swift`) so
    `JournalSeed` can write the summary row Step 6 must skip; Plan 007 populates them.
  `public var displayName: String` ("Rename Character", "Merge Entities", "Lock Name", "Delete 4
  Entities") is the only source of undo action names.
- **The inverse is not a property of `EditOperation`.** `mutate` computes it while it has the
  rows in hand and returns it in `MutationEffect.inverse` (nil ⇒ non-invertible:
  `importScreenplay`, `replaceScreenplay`, `revertExtractionRun`, `applyExtractionRun`), and
  `perform` stores it in `JournalEntry.inverse`. Payload-driven inverses (`restoreEntity`,
  `unmerge`, `unsplit`) carry everything they need in their associated values, so `applyInverse`
  can hand `entry.inverse` straight back to `perform`. Inverses of inverses exist (`unmerge` →
  the original `mergeEntities`, `unsplit` → `splitEntity`, `restoreEntity` → `deleteEntity`),
  follow the §3.8 table, and are sampled in `JournalInverseTests` like any other case; a compound
  case inverts to the compound of its element inverses in reverse order.

### Journal entries and affected sets (§3.8)

```swift
public struct JournalEntry: Codable, Equatable, Sendable {
    public let seq: Int64                    // edit_journal.seq; the entry id
    public let at: Date; public let actor: MutationActor; public let jobID: UUID?
    public let invertsSeq: Int64?            // the entry this one inverted (design §3.8 cancellation)
    public let op: EditOperation
    public let inverse: EditOperation?       // nil ⇒ non-invertible
    public let affected: Set<SubjectRef>     // every row the entry touched
    public let snapshots: [RowSnapshot]
}
public struct RowSnapshot: Codable, Equatable, Sendable {
    public let table: String
    public let columns: [String: JSONValue]  // every column of the row, timestamps included; encoded with .sortedKeys
}
public enum JSONValue: Codable, Equatable, Sendable { case null, bool(Bool), int(Int64), double(Double), string(String) }
```

- `op`, `inverse`, and `snapshots` serialize into the `edit_journal` payload; `affected` persists one row per member into `edit_journal_affected(seq, subject_kind, subject_id)`.
- `affected` lists **every** row touched — the entity, its aliases, appearances, evidence, states, events, relationships, and lock rows (recorded under their subject's ref) — not one primary subject. `JournalEntry` has **no** single `subject` field.
- **Conflict rule (shared by undo and revert, design §3.8)**: an entry that applies an inverse
  records `inverts_seq`. An entry is **live** when no later live entry inverts it (walk `seq`
  descending: the newest entry is live; an entry is live iff no live entry has `inverts_seq` equal
  to its `seq`). Entry `E` may be inverted only if (a) `E` is live, and (b) `E.affected` is
  disjoint from the union of `affected` over every later live entry with `actor = 'human'` whose
  `inverts_seq` is NULL **or less than `E.seq`**, read from `edit_journal_affected`. Later inverses
  of entries newer than `E` restore states `E` already saw and never conflict; an inverse of an
  entry older than `E` does. Worked trace — rename (1), set-description (2): ⌘Z inverts 2 → entry
  3 (live: 1, 3); ⌘Z inverts 1 (live; 3 is a later inverse of a newer entry → excluded) → entry 4;
  ⇧⌘Z inverts 4 (live, nothing after it) → entry 5; ⇧⌘Z inverts 3 (live — 4 is no longer live, 5
  inverts an entry newer than 3 → excluded) → entry 6. Every step passes. The old "same single
  subject" rule missed later edits to dependent rows after a merge, split, or delete; the naive
  "cancel both" rule made redo impossible.
- **Inverses restore timestamps.** Every inverse writes back the snapshotted `updated_at`,
  `reviewed_at`, `review_state`, `source`, and `created_source` of each row it touches (it never
  stamps "now"), so an apply → inverse round trip is byte-identical across **all** columns and
  undoing an accept leaves `reviewed_at` NULL. `ProjectSnapshotDigest` therefore hashes every
  column of every table, timestamps included.
- Payloads hold **full row snapshots** — every column of every row deleted or overwritten, never only ids. BLOB columns encode base64 into `.string`.
- **No GRDB type appears in `EditOperation`, `JournalEntry`, `RowSnapshot`, or any payload**; `DatabaseValue ↔ JSONValue` conversion lives only in FilmCore's Storage layer. These types are `public Codable` and the app links them, so a `DatabaseValue` payload would put GRDB in the public API and violate AGENTS.md.
- `SubjectRef` is `{ kind: SubjectKind; id: UUID }` (`Codable, Hashable, Sendable`) and `SubjectKind` (`entity`, `alias`, `appearance`, `scene`, `state`, `event`, `relationship`, `synopsis`, `script`) are Plan 003's; `LockPolicy` and the `locks`/`evidence` `CHECK`s accept their documented subsets.

### Applying an inverse (§3.8)

```swift
// ScreenplayEditing — the only public door for applying an inverse
func applyInverse(entryID: Int64, actor: MutationActor) async throws -> JournalEntry
```

- One transaction: load the entry, refuse when `inverse == nil`, when the entry is not live, or when the affected-set conflict rule fails, re-check the inverse's own preconditions (snapshotted ids absent or present as the inverse requires, uniqueness still free, referenced scenes and entities still exist), then `perform`/`performGroup` the inverse and journal it as a new entry whose `inverts_seq = entryID`.
- Any failed precondition throws `.inverseNoLongerApplicable(reason:)` **before any write** — never a partial application.
- There is **no** public generic "apply this operation" door; the window model calls `applyInverse` and never constructs an `EditOperation`.

### New and changed operations (§6)

| Operation | Rule |
|---|---|
| `deleteEntity(id)` | hard delete only when `source = 'human'` **or** the row is already `rejected`; `source = 'ai'` **or** `'parser'` → `.rejectInsteadOfDelete(entityID:)` (the UI's Delete on such rows calls `rejectEntity`; a rejected parser entity keeps its cue/heading aliases so re-import/re-parse maps back to the tombstone and it stays rejected) |
| `rejectEntity(id)` / `unrejectEntity(id)` | set `review_state = 'rejected'` and stamp `reviewed_at` (a rejection is a verdict — Plan 006's `rejected` array depends on it), leaving `source`, `created_source`, and `job_id` untouched / restore the pre-rejection state (carried in the inverse's `priorState`; a directly invoked `unrejectEntity` reads it from the tombstone's journal snapshot, and with none restores `accepted` for `created_source = 'parser'` rows, `proposed` otherwise — a parser row is never left `proposed`) on the entity row; aliases and dependent rows are **retained** — they are the tombstone that stops resurrection. The same `.rejectSubject`/`.unrejectSubject` primitives back `removeState`/`removeEvent`/`removeRelationship` on `ai` rows, whose inverse is therefore `unrejectSubject`; on `human` rows those ops hard-delete and their inverse is the `add` of design §3.8 (payload-restored, original id). `JournalInverseTests` carries a sample of each branch |
| `renameEntity(id, name)` | records the previous name as an alias (`alias_kind = 'human'`, `source = 'human'`) unless that normalized alias already exists on the entity |
| `reclassify(id, kind)` | carries `entity_aliases.kind` along and re-checks `UNIQUE(project_id, kind, normalized)` in the target kind; conflict → `.aliasConflict(existingEntityID:)`; refused for a location with children |
| `setLocationParent(id, parentID?)` | locations only; refuses self and cycles by ancestor walk (`.invalidParent`); inverse carries the prior `parent_id`; UI action "Move into…" |
| `addAlias(entityID, alias)` | `.aliasConflict(existingEntityID:)` when the normalized alias belongs to another entity of the same kind; the UI offers Merge from the error |
| `acceptFacts` / `acceptAllProposed` / any human edit | additionally stamps `reviewed_at` (design §3.6) — the only signal Plan 006 accepts as operator review; `job_id` and `created_source` are never overwritten, so a corrected parser or AI fact stays distinguishable from one a human added (§7.2 `origin`); an `.ai` mutation never writes `reviewed_at` on any row |
| `acceptFacts(refs)` / `acceptAllProposed()` | `performGroup` of `acceptFact` children; payload lists **exactly** the `(subjectKind, id)` pairs flipped; the inverse is the group of `unacceptFact(ref, priorState:)` in reverse order and flips those and nothing else; accepting an entity accepts its alias **and appearance** rows (they are what Plan 006 exports as `aliases`/`appearsIn`) |
| `createEntity` under `.ai` (Plan 007) | a proposal whose normalized name or alias matches a `rejected` row of that kind resolves to the tombstone → `.rejected(subject:)`, nothing written (§8.5 rule 2) — the check lives in `EntityOperations`, here |
| `revertExtractionRun(jobID)` | **selective**; returns `RevertReport` |
| `replaceScreenplay` (Plan 003's) | §5.5 guard **re-verified** here against real protected rows and locks produced by these operations (`.replaceRefused(reason:)`); no second implementation |

New `ProjectStoreError` cases, all `Equatable` with `errorDescription`:
`locked(subject:field:)`, `protectedFact(subject:)`, `parserOwned(subject:field:)`,
`nameConflict(existingEntityID:)`,
`invalidLockField(subjectKind:field:)`, `invalidParent(reason:)`, `mergeRefused(reason:)`,
`splitRefused(reason:)`, `rejectInsteadOfDelete(entityID:)`, `rejected(subject:)`,
`inverseNoLongerApplicable(reason:)`, `newerRunExists(jobID:)`.

### Protection, parser-owned fields, and the AI merge exception (§3.5–§3.6)

Enforce design §3.6 inside FilmCore; its rules are not restated here. The matrix rows that carry the exception:

| actor × subject | allowed | refused |
|---|---|---|
| `.ai` on a **parser** entity | fill an empty `description`; add aliases (append-only); add appearances/states/events/relationships/evidence; **merge two parser entities, and merge an `ai` entity into a parser one** (§3.5) | rename, reclassify, delete, `is_relevant` → `.parserOwned(subject:field:)`; alias removal or edit → `.parserOwned`; merge whose source carries any lock → `.locked`; merge whose source a human has edited (`source = 'human'`) → `.protectedFact` |
| `.ai` on a **protected** row (`human`, or `ai`+`accepted`) | add evidence and appearance rows that reference it | modify or delete → `.protectedFact(subject:)` |
| `.human` on a locked field | — | `.locked(subject:field:)` until an explicit `unlock` |

- The AI merge exception exists because `SARAH` and `SARAH MORGAN` both arrive as parser cues; without it normalization is impossible. It is journaled with `actor = .ai(jobID)`, revertible by `revertExtractionRun`, and loses nothing: the source name survives on the target as an alias (`alias_kind = 'mention'`, `source = 'ai'`, `review_state = 'proposed'`, `job_id` set). A `.human` merge inserts it as `alias_kind = 'human'`, `source = 'human'`, `accepted`.
- Everything else in §3.6 is unchanged: human edits set `source = 'human'` / `review_state = 'accepted'` and stamp `reviewed_at`, leaving `created_source` and `job_id` as inserted; every insert sets `created_source = source`, and a `.human` insert (created entity, rename alias, human-merge alias, split entity, added state/event/relationship) is born with `reviewed_at` set while an `.ai` insert never is; `.ai` aliases are append-only; default reads exclude `rejected`; `entities(…includeRejected:)` opts in. `setSynopsis` writes the synopsis PROV set (`synopsis_source`, `synopsis_created_source`, `synopsis_review_state`, `synopsis_reviewed_at`, `synopsis_job_id`, `synopsis_updated_at`, §4.3) by the same rules.

### Locks (§3.7)

```swift
public enum LockField: String, Codable, Sendable {
    case name, description, kind, isRelevant = "is_relevant", synopsis, whole = "*"
}
public enum LockPolicy { public static func fields(for: SubjectKind) -> Set<LockField> }
// entity: name, description, kind, isRelevant, whole · scene: synopsis, whole
// alias: whole · state, event, relationship: whole · anything else → .invalidLockField
```

- A field lock blocks that field only. `.whole` on an entity blocks rename, reclassify, description, `is_relevant`, alias addition **and** removal, being a merge source, and delete.
- An **alias lock** (`alias`, field `*`) pins that surface form to its entity: it refuses `removeAlias`, refuses any merge or reclassify that would re-target it, and refuses a `splitEntity` that lists it in `aliasIDs` — for both actors.
- Locks never block adding evidence or appearance rows that reference the subject.
- `lock`/`unlock` are journaled and invertible; lock rows are snapshotted into the payload and removed when their subject row is deleted or loses a merge collision.

### Merge and split (§3.5)

`mergeEntities(sourceIDs:into:actor:)`:

- Sources and target share `kind`, target ∉ sources, sources non-empty — else `.mergeRefused(reason:)`. Any `locks` row over a source or over one of its aliases (whole or field), **or a whole-record lock on the target** (the merge adds an alias to it), refuses the merge for both actors with `.locked`; the human path must `unlock` first. A field lock on the target does not refuse. Locks on the source's dependent state/event/relationship rows survive, because those rows keep their ids.
- Moves `entity_aliases`, `scene_entities`, `entity_relationships` (both directions), `entity_states`, `continuity_events`, `evidence`, and child `entities.parent_id`. Moving alias rows **cannot** collide — `entity_aliases(project_id, kind, normalized)` does not contain `entity_id` — so two unique indexes collide: `scene_entities(scene_id, entity_id, role)` and `entity_relationships(from_entity_id, to_entity_id, kind)`.
- Per collision, **in this order**: select the colliding rows → choose the survivor by `ProtectionRank`, most protected wins: `human` (3) > `ai`+`accepted` (2) > `parser` (1) > `ai`+`proposed` (0), ties by earliest `created_at`, then by `id` for total determinism → snapshot the loser **in full** with its lock rows → retarget `evidence` whose `(subject_kind, subject_id)` points at the loser to the survivor and set `evidence.owner_entity_id` to the target → `DELETE` the loser → `UPDATE` the remaining source rows to the target. Every retargeted row is snapshotted and in `affected`. A collision-losing appearance was the only carrier of its `matched_alias_id`, and that link is **not** recoverable by a later split (one `scene_entities` row holds one alias link; aliases themselves never lose a collision); the split sheet therefore lets the user select such appearances by hand (`movedAppearanceIDs`).
- The source's `name` becomes an alias on the target per the provenance rule above unless its normalized form already exists **on the target**. If that normalized form belongs to an unrelated third entity of the same kind (uniqueness is project-and-kind-wide, not per entity), the insert is **skipped and recorded** in the effect (`MutationEffect.skippedAliases`). The channel out: `perform`/`performGroup` return `(entry: JournalEntry, effect: MutationEffect)` internally (both are internal), the public `mergeEntities` wrapper returns `MergeResult { entry: JournalEntry; skippedAliases: [String] }`, and Plan 007's applier reads `effect.skippedAliases` off the internal return to increment `aliasConflicts` — it never aborts the merge and never throws a raw SQLite error. Self-relationships are dropped and snapshotted; a source that is the target's parent (or vice versa) yields `parent_id = NULL` rather than a self-parent.
- Source rows are snapshotted and deleted; the inverse `unmerge` restores every snapshot with its **original id**, re-points the moved rows back, **and deletes every row the merge created (the source-name alias on the target included — `unmerge(created:…)`)**, so merge → undo is byte-identical. With more than one source the wrapper uses `performGroup` over one child merge per source.

`splitEntity(entityID:aliasIDs:newName:movedAppearanceIDs:actor:)`:

- Split is a **human-only** operation (design §8.5 never splits; `.ai` gets `.protectedFact` on the attempt). `aliasIDs` non-empty and ≥1 alias must remain on the source (`.splitRefused`); `newName` unique per kind on `name_normalized` (`.nameConflict`); a lock on the source or on any listed alias refuses the split.
- Creates the new entity (`source = 'human'`, `created_source = 'human'`, `review_state = 'accepted'`, `reviewed_at` set, same `kind`) and moves the listed aliases.
- Moves every `scene_entities` and `evidence` row whose **`matched_alias_id`** is one of the moved aliases (the column Plan 003 populates), every `evidence` row whose `(subject_kind, subject_id)` points at a moved alias or a moved appearance, and the rows the user selected in the split sheet (`movedAppearanceIDs`); `evidence.owner_entity_id` is re-pointed to the new entity.
- **Never compares an evidence `quote` against an alias**: quotes are sentences, so a case-folded match would effectively never fire.
- Inverse is **`unsplit`**, payload-driven — never a plain merge, which would preserve the new
  entity's name as an alias on the source and leave an alias that did not exist before the split.
  `unsplit` moves the recorded rows back by id, deletes the created entity and every row the split
  created (its name alias included), and restores the source's snapshot. `MergeSplitTests`
  asserts a byte-identical table snapshot after split → undo and after merge → split-back.

### Scenes, states, events, relationships

Design §4.3 shapes. `EntityState` requires `start_scene_id`; both scenes must belong to `projects.current_script_id` and `start.ordinal ≤ end.ordinal`. `ContinuityEvent.resulting_state_id` must belong to the same entity. `entity_relationships` is unique per `(from, to, kind)`. `setSceneEntity` upserts on `(scene_id, entity_id, role)`; `setSynopsis` writes the scene's synopsis PROV columns only.

### Selective revert (§3.8)

```swift
public struct RevertReport: Codable, Equatable, Sendable {
    public let jobID: UUID; public let reverted: Int
    public let skipped: Int; public let skippedSubjects: [SubjectRef]
}
```

- Refused with `.newerRunExists` when any completed `extractScreenplay` parent with a higher `seq`
  of journal entries exists — only the newest run is revertible (design §3.8), which is what the
  Jobs section's "Revert last run" means.
- One transaction; walk `SELECT … FROM edit_journal WHERE job_id = ? ORDER BY seq DESC`.
- Apply each `entry.inverse` **only if `entry.affected` is disjoint from the union of `affected` over every uncancelled journal entry with a higher `seq` and `actor = 'human'`**; otherwise count it skipped and add its affected members to `skippedSubjects` (deduplicated, ordered by `(kind, id)` for determinism). **Skips are transitive backward**: once an entry is skipped, every earlier entry of the run whose `affected` intersects the skipped entry's `affected` is skipped too — otherwise inverting the run's `createEntity` would cascade-delete the human-edited alias the first skip just preserved.
- Skip, never invert, the trailing `applyExtractionRun` summary row (payload = `ApplyReport`).
- Journal one non-invertible entry; return the report ("Reverted 412 changes; 3 skipped because you edited them").
- Implemented and tested **here** against entries seeded by `JournalSeed` through the internal levels with `actor = .ai(jobID)`; no real run exists until Plan 007.

### Undo bridge (§3.8, §3.11)

`ProjectWindowModel` owns the `UndoManager`, is constructible as `ProjectWindowModel(session:undoManager:)`, and exposes every command as an awaitable `async` method. The manager reaches AppKit through Plan 004's per-window `ProjectWindowDelegate` (the `NSWindowDelegate` bridge `AppCoordinator` already installs at window creation), which gains `windowWillReturnUndoManager(_:)` here — no second delegate — so **Edit ▸ Undo / Redo validate and show the action name**; it also reaches SwiftUI via `.environment(\.undoManager, model.undoManager)`.

```swift
@MainActor private func register(entryID: Int64, name: String) {
    let flip = InverseSlot()                                  // filled with the flip's entry id on success
    undoManager.registerUndo(withTarget: self) { model in     // handler is not actor-isolated under strict concurrency:
        MainActor.assumeIsolated {                            // UndoManager calls it on the main thread; assert, don't hop
            guard !model.isApplyingInverse else {             // serialized: commands are disabled while one applies, so this
                model.register(entryID: entryID, name: name)  // only guards a race — re-register the same entry so the
                return                                        // action survives the drop, and leave the stack unchanged
            }
            model.isApplyingInverse = true
            model.register(slot: flip, name: name)            // synchronous, inside the closure → the other stack
            Task { await model.applyInverse(entryID: entryID, filling: flip) }
        }
    }
    undoManager.setActionName(name)
}
@MainActor private func register(slot: InverseSlot, name: String) { /* same shape over the slot's id once filled */ }
@MainActor func didApply(_ entry: JournalEntry) {            // called after every human edit
    guard entry.inverse != nil else { undoManager.removeAllActions(); return }
    register(entryID: entry.seq, name: entry.op.displayName)
}
```

- `InverseSlot` is a `@MainActor final class` box holding the entry id its closure will invert; `applyInverse(entryID:filling:)` awaits `session.applyInverse(entryID:actor:.human)`, writes the returned entry's `seq` into the slot, reloads, and clears `isApplyingInverse` in a `defer`. A slot whose id is still `nil` refuses to run.
- Registration is synchronous, inside the undo closure, before any `await` — never from a `Task` completion. The closure starts the `Task` and returns immediately.
- **Undo is serialized**: exactly one inverse is in flight, and Edit ▸ Undo / Redo, ⌘Z, and ⇧⌘Z are disabled while `isApplyingInverse` is true, so a second ⌘Z cannot race the first.
- Batch UI actions wrap `beginUndoGrouping()` / `endUndoGrouping()` around the matching FilmCore `performGroup` op: one undo step, one journal row.
- `applyInverse` surfaces `.inverseNoLongerApplicable(reason:)` by calling `undoManager.removeAllActions()`, reloading from the store, and presenting the error; a successful `revertExtractionRun` also clears the stack, and revert is not itself undoable.

### UI (§3.11 table)

- Plan 004's **one** `EntityListView` (name, review badge, lock icon, appearance count) and **one** `EntityInspectorView` serve all six kinds and are extended in place; no parallel detail view is added.
- Multi-select shows a count and only the actions valid for the whole selection (Merge: ≥2 of one kind, no locked source; Split: exactly 1; Accept: ≥1 proposed; Move into…: locations only).
- Every context-menu action is mirrored in an **Entity menu**: Rename (Return), Merge… (⌃⌘M), Split… (⌃⌘S), Move into…, Lock/Unlock (⌃⌘L), Mark Irrelevant, Accept (⌘⏎), Reject/Delete (⌫, confirmed).
- The split sheet lists the entity's aliases and its appearances with the alias that produced each, preselecting the appearances whose `matched_alias_id` is a selected alias; the returned selection is `movedAppearanceIDs`.
- The inspector shows name, kind, relevance, description, aliases, appearances by role, states, events, relationships, evidence (each row calls `ProjectWindowModel.reveal(.scene(id, highlight:))`), a provenance line, and a per-field lock button (aliases included); locked fields render read-only with an Unlock control.
- `ProvenanceLabel` renders "Parser", "AI · Run 3 · High", "You · 2 min ago"; confidence is banded by Plan 003's `ConfidenceBand` (`< 0.5` Low, `< 0.8` Medium, else High) so every surface bands identically, and the raw float is never shown.
- Continuity lists events chronologically by `(scene.ordinal, entity.name)` — scene · entity · description · resulting state — editable in place.
- The Scenes detail's synopsis (static text in Plan 004) becomes editable here through `setSynopsis` (design §3.11 as revised); the edit journal is a sheet reached from **Edit ▸ Show Edit Journal…** (`EditJournalView`), not a sidebar section.
- `ProjectObserving.changes()` must emit `.locks`, `.journal`, `.entities`, and `.scenes` for the tables this plan starts writing (`locks`, `entity_states`, `continuity_events`, `entity_relationships`, `edit_journal`, `scene_entities`, `scenes.synopsis*`), so Continuity, the scene detail, and the inspector refresh after an edit; `ProjectObservationTests` (Plan 003's suite) gains those cases here.
- The entity list gains a minimal **review filter** — Proposed / Accepted / Rejected (`ReviewFilters`, `Views/Entities/`) — because UI test (e) and the Rejected tombstone need a way to see rejected rows; Plan 007 extends the same control with the Unanchored filter and the review banner, it does not create a second one.
- Every actionable control carries an accessibility **identifier and label**; icon-only controls (lock, review badge) carry labels.

## Target file layout (additions)

```text
Packages/FilmCore/Sources/FilmCore/
  Domain/  EditOperation.swift (EXTENDED: all cases, displayName) · SubjectRef.swift (Plan 003's) ·
           LockField.swift (new) · RevertReport.swift (new) · ApplyReport.swift (new: ApplyReport + ExtractionSettings, §8.5 shape) ·
           ConfidenceBand.swift (Plan 003's) ·
           JournalEntry.swift (Plan 003's; unchanged shape)
  Editing/ EditPrimitives.swift (EXTENDED: performGroup beside Plan 003's mutate / perform) ·
           RowSnapshot.swift (Plan 003's; MutationEffect gains skippedAliases) · JournalStore (Plan
           003's; writes inverts_seq) · new: EntityOperations · AliasOperations ·
           MergeSplitOperations · SceneOperations · ContinuityOperations · LockPolicy ·
           ProtectionPolicy · InverseApplication
  ProjectTools+Editing.swift          ScreenplayEditing members on ProjectSession
Packages/FilmCore/Tests/FilmCoreTests/
  Support/ ProjectSnapshotDigest.swift (deterministic table snapshot; TEST-ONLY) ·
           ProjectIntegrityChecks.swift (orphan-evidence query + PRAGMA foreign_key_check) ·
           JournalSeed.swift (seeds ai/proposed rows, the parent `jobs` rows — task
           `extractScreenplay`, `completed` — each run's entries reference, and journal entries)
  JournalPrimitivesTests · AffectedSetTests · RowSnapshotCodingTests · ApplyInverseTests ·
  EditingReentrancyTests · EntityEditingTests · AliasEditingTests · MergeSplitTests ·
  LockPolicyTests · ProtectionMatrixTests · RejectionTombstoneTests · SceneEditingTests ·
  StatesEventsRelationshipsTests · ReviewAcceptTests · RevertRunTests ·
  JournalInverseTests                                       (one .swift file each)
AI Film Camp/
  App/     UndoBridge.swift (ProjectWindowDelegate+Undo extension + InverseSlot + registration;
           its detached Task is the second permitted site beside 004's windowWillClose, tracked
           by the model as the in-flight inverse) ·
           AppCoordinator.swift (unchanged unless the delegate hookup needs the model reference) ·
           AppCommands.swift (EXTENDED: Edit ▸ Show Edit Journal…) ·
           ProjectWindowModel+Editing.swift · Commands/EntityCommands.swift (Entity menu)
  Views/Entities/    EntityInspectorView.swift + EntityListView.swift + ProvenanceLabel.swift
           (Plan 004's, extended) · ReviewFilters (new; Plan 007 extends) ·
           AliasEditor · MergeSheet · SplitSheet · MoveIntoSheet · LockButton
  Views/Continuity/  ContinuityListView · StateEditorSheet · EventEditorSheet ·
           RelationshipEditorSheet
  Views/Scenes/SceneEntitiesEditor.swift · Views/Scenes/SceneSynopsisEditor.swift ·
  Views/Journal/EditJournalView.swift (sheet from Edit ▸ Show Edit Journal…)
  Tests/ProjectWindowModelTests.swift · UITests/Phase1EditingUITests.swift
```

- No new SwiftPM target or product and no `Package.swift` change. No `.gitignore` change. No file is deleted.
- No `project.yml` edit is required — the app target globs `AI Film Camp/App`, `/Views`, `/Support`, and the test targets glob `/Tests` and `/UITests` — but `xcodegen generate --spec project.yml` must be re-run and the regenerated `AI Film Camp.xcodeproj` committed.
- `ProjectSnapshotDigest` lives under `Tests/`, never under `Sources/`.

## Steps

### Step 1: The mutation engine, journal, affected sets, and `applyInverse`

Extend Plan 003's `EditOperation` (all cases above), `MutationEffect` (`skippedAliases`), `JournalStore` (`inverts_seq`), and `EditPrimitives` (`performGroup`), and add the public `applyInverse(entryID:actor:)`. Add `ProjectSnapshotDigest` (every column of every table, timestamps included) and `ProjectIntegrityChecks` under `Tests/FilmCoreTests/Support/`. Exercise the engine with one scalar op (`renameEntity`) until Step 2 fills in the rest.

**Verify**:

```bash
swift test --package-path Packages/FilmCore --filter JournalPrimitivesTests
swift test --package-path Packages/FilmCore --filter AffectedSetTests
swift test --package-path Packages/FilmCore --filter RowSnapshotCodingTests
swift test --package-path Packages/FilmCore --filter ApplyInverseTests
swift test --package-path Packages/FilmCore --filter EditingReentrancyTests
```

Expected: `mutate` writes no journal row; `perform` writes exactly one; `performGroup` writes exactly one whose `op` is the compound case and whose payload holds the child inverses in order and inverts them in reverse; `affected` for a rename contains the entity and the alias it inserted and round-trips through `edit_journal_affected` (full coverage of every row kind is `JournalInverseTests`' job in Step 5); a `RowSnapshot` encodes with sorted keys, carries every column, round-trips each `JSONValue` case, and no GRDB type appears in any payload or public signature; `applyInverse` refuses a non-invertible entry, refuses an entry that is not live, refuses one whose `affected` intersects a later live non-inverse `.human` entry's, writes `inverts_seq`, and throws `.inverseNoLongerApplicable(reason:)` **without writing** when a precondition fails; **two edits to one entity undo twice and redo twice with the digest matching at every step**; `EditingReentrancyTests` asserts `db.isInsideTransaction` at the top of `perform`/`performGroup` and that no file under `Sources/FilmCore/Editing/` contains `queue.write` (a grep, since a nested `DatabaseQueue.write` deadlocks rather than fails).

### Step 2: Scalar entity ops, aliases, rejection

Add the public wrappers for `createEntity`, `deleteEntity`, `rejectEntity`, `unrejectEntity`, `renameEntity`, `setDescription`, `reclassify`, `setRelevance`, `setLocationParent`, `addAlias`, `removeAlias`, and the batch wrappers over `performGroup`.

**Verify**:

```bash
swift test --package-path Packages/FilmCore --filter EntityEditingTests
swift test --package-path Packages/FilmCore --filter AliasEditingTests
swift test --package-path Packages/FilmCore --filter RejectionTombstoneTests
```

Expected: each op journals exactly one entry and its inverse restores a byte-identical `ProjectSnapshotDigest`; delete → restore returns aliases, appearances, states, events, relationships, evidence, and lock rows with **original ids**; the refusal rules of "New and changed operations" hold (`.rejectInsteadOfDelete`, `.parserOwned`, `.invalidParent`, `.nameConflict`, `.aliasConflict`); renaming `Sarah` → `Sarah Morgan` leaves a `human` alias `SARAH` and renaming back does not duplicate it; a rejected entity leaves `entities()`, returns with `includeRejected: true`, and keeps its aliases; **a proposal seeded through the internal levels whose normalized name matches a rejected alias resolves to the rejected entity, is reported skipped, and creates no row**; a batch delete journals one row and one undo step.

### Step 3: Merge and split with the collision rule

Implement `mergeEntities`, `splitEntity`, `ProtectionRank`, and `unmerge`.

**Verify**:

```bash
swift test --package-path Packages/FilmCore --filter MergeSplitTests
```

Expected: `scene_entities` and `entity_relationships` collisions resolve by `ProtectionRank` with the documented tie-breaks; losers are snapshotted in full and their evidence retargeted, leaving `ProjectIntegrityChecks.orphanEvidence` empty and `PRAGMA foreign_key_check` clean after every merge, split, and delete test; a source name colliding with a third entity's alias is skipped and reported, never thrown; child locations move without creating a self-parent; a lock on a source, on one of its aliases, or a whole lock on the target refuses the merge for both actors while a field lock on the target does not; kind mismatch and target-in-sources are refused; **split moves the appearances and evidence whose `matched_alias_id` is a moved alias plus the rows listed in `movedAppearanceIDs`, and an evidence row whose quote merely contains the alias text is not moved**; **merge then split-back of the merged alias round-trips the appearances that did not collide plus the rows listed in `movedAppearanceIDs`**; merge→undo (the created alias deleted) and split→undo restore original ids and a byte-identical digest.

### Step 4: Locks, protection, parser-owned fields, and accept

Implement `LockField`/`LockPolicy` (including `alias`/`*`), `ProtectionPolicy`, `lock`, `unlock`, `acceptFacts`, `acceptAllProposed`, the §5.5 replace guard, and thread `MutationActor` through every op.

**Verify**:

```bash
swift test --package-path Packages/FilmCore --filter LockPolicyTests
swift test --package-path Packages/FilmCore --filter ProtectionMatrixTests
swift test --package-path Packages/FilmCore --filter ReviewAcceptTests
```

Expected: the matrix (actor × none/field/`*` lock × every op) matches design §3.6–§3.7 exactly — `.parserOwned` on parser-owned fields while filling an empty parser description succeeds; **an `.ai` merge of two parser entities succeeds, is journaled and revertible, and leaves the source name as an alias on the target, while `.ai` rename, reclassify, delete, and `is_relevant` on a parser entity throw `.parserOwned`, an `.ai` merge whose source is locked throws `.locked`, and one whose source a human edited throws `.protectedFact`**; `.ai` alias removal always throws and addition throws only under a whole lock; an alias lock refuses `removeAlias` and refuses a split listing that alias, for both actors; `.protectedFact` on `human`/`ai+accepted` rows; evidence and appearance additions still succeed against a locked entity; `.human` edits to a locked field throw `.locked` until `unlock`; an invalid `(subjectKind, field)` pair throws `.invalidLockField`; human edits set `source = 'human'`, `review_state = 'accepted'`, stamp `reviewed_at`, and leave `created_source`/`job_id` untouched; `acceptFacts` changes **only** `review_state` and `reviewed_at` (never `source` or `job_id`) and accepts the entity's alias **and appearance** rows; `rejectEntity` stamps `reviewed_at` and leaves `source` unchanged; a `.human` insert is born with `reviewed_at` set and an `.ai` insert is not; **accept → undo leaves `reviewed_at` NULL; no `.ai` mutation ever writes `reviewed_at`**; `acceptAllProposed` journals one `performGroup` entry whose payload lists exactly the flipped pairs and whose inverse flips exactly those back; lock/unlock are journaled and invertible; Plan 003's `replaceScreenplay` guard throws `.replaceRefused` once a real protected fact or a lock exists.

### Step 5: Scenes, states, events, and relationships

Implement `setSceneEntity`, `removeSceneEntity`, `setSynopsis`, `addState`/`editState`/`removeState`, `addEvent`/`editEvent`/`removeEvent`, `addRelationship`/`removeRelationship`.

**Verify**:

```bash
swift test --package-path Packages/FilmCore --filter SceneEditingTests
swift test --package-path Packages/FilmCore --filter StatesEventsRelationshipsTests
swift test --package-path Packages/FilmCore --filter JournalInverseTests
```

Expected: the validation rules of "Scenes, states, events, relationships" hold; synopsis PROV columns are the only scene columns written; `removeState`/`removeEvent`/`removeRelationship` tombstone `ai` rows (inverse `unrejectSubject`) and hard-delete `human` rows (inverse `add` with the original id), one sample each; `JournalInverseTests` covers **every** `EditOperation` case — the inverse-only and compound cases included — with apply → inverse → identical digest, asserts each case's `affected` set, and fails when a case has no sample (exhaustive switch over the operation list).

### Step 6: Selective revert of a run

Implement `revertExtractionRun(jobID:)`, `RevertReport`, and `JournalSeed`.

**Verify**:

```bash
swift test --package-path Packages/FilmCore --filter RevertRunTests
```

Expected: a seeded run of N `.ai(jobID)` entries reverts to the pre-run digest; where a later `.human` entry's `affected` set intersects an entry's, that inverse is skipped, counted in `RevertReport.skipped`, listed in `skippedSubjects`, and the human edit survives — **including a human edit to a dependent row (an alias, appearance, or evidence row) rather than the entity itself, which also transitively skips the run's `createEntity` of that entity so the cascade cannot delete the edited row**; a human undo that cancelled a later human edit no longer blocks; a second seeded run makes reverting the first throw `.newerRunExists`; the `applyExtractionRun` summary row is skipped; the revert is one transaction and journals one non-invertible entry.

### Step 7: Window model and undo bridge

Extend Plan 004's `ProjectWindowModel(session:undoManager:)` with the awaitable editing commands, add `UndoBridge`/`InverseSlot` and the `windowWillReturnUndoManager(_:)` extension on Plan 004's `ProjectWindowDelegate` (the same `NSWindowDelegate` bridge 004 uses for window identifiers and ⌘W teardown), and `ProjectWindowModelTests`.

**Verify**:

```bash
xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -only-testing:"AI Film CampTests" test
```

Expected (design §10): rename → undo → redo → undo lands on the original value with the right action name at each step, **and rename then set-description undo twice / redo twice**; the model calls `applyInverse(entryID:)` and never a generic apply; **two undo requests issued back to back apply exactly one inverse — the second is dropped while `isApplyingInverse` is true, re-registered so the undo stack is unchanged, and both commands report disabled**; a batch delete is one undo step; a failing apply (`.inverseNoLongerApplicable`, forced by mutating the store behind the model) clears both stacks, reloads, and surfaces the error; `changes()` refreshes the model's entity list and lock state after an edit made behind it (the `pendingReviewCount` variant of this test needs `proposed` rows and is Plan 007's); a simulated AI apply (a seeded `.ai` journal entry through a test hook on the session) clears undo; selection survives a reload.

### Step 8: Editing UI, menus, UI tests, and documentation

Extend the entity list and inspector, and add the alias editor, merge/split/move sheets, lock controls, continuity editors, scene entity editor, journal view, Entity menu, and accessibility identifiers and labels. Re-run XcodeGen. Update the `README.md` feature list, record divergences in `docs/IMPLEMENTATION_NOTES.md`, and set this plan's row in `docs/plans/README.md` to `DONE`.

**Verify**:

```bash
xcodegen generate --spec project.yml
./scripts/verify.sh
./scripts/finder-smoke.sh
git status --short
```

Expected: both scripts exit 0, which includes `Phase1EditingUITests` (persistence disabled, window-scoped queries) importing the bundled sample and then (a) renaming a character and undoing/redoing it **via the Edit menu**, asserting the menu item title contains "Rename Character"; (b) merging two characters and undoing the merge; (c) locking a character's name and observing the field read-only with an Unlock control; (d) adding a wardrobe state and seeing it in the inspector and in Continuity; (e) deleting a **parser** character (Delete on a parser row is `rejectEntity`, design §3.6 — Phase 1a has no `proposed` rows and no seeding launch argument), confirming it leaves the default list, finding it under this plan's Rejected filter, and unrejecting it back to `accepted`; (f) editing a scene synopsis and undoing it. The working tree holds no `.aifilm` bundle, database, log, DerivedData, or screenplay text.

## Done criteria

- [ ] `./scripts/verify.sh` and `./scripts/finder-smoke.sh` exit 0.
- [ ] Every mutation goes through `mutate` / `perform` / `performGroup`: `mutate` journals nothing, `perform` writes exactly one row, `performGroup` writes exactly one compound row holding its child inverses in order; no public op calls another.
- [ ] Every `EditOperation` case in the contract's list has a `displayName`, an inverse returned by `mutate` (or is explicitly non-invertible), and a round-trip test; payloads carry full row snapshots, inverses restore timestamps and review columns, and delete → restore returns original ids.
- [ ] `RowSnapshot` is a table name plus `[String: JSONValue]`; no GRDB type appears in `EditOperation`, `JournalEntry`, or any payload.
- [ ] Every journal entry records an `affected` set covering every touched row in `edit_journal_affected`; undo and revert both refuse when it intersects a later **uncancelled** `.human` entry's, inverse entries write `inverts_seq`, and two consecutive undos on one entity succeed.
- [ ] `applyInverse(entryID:actor:)` is the only public door for an inverse; it re-checks preconditions and throws `.inverseNoLongerApplicable(reason:)` before writing anything.
- [ ] Merge resolves `scene_entities`/`entity_relationships` collisions by `ProtectionRank`, retargets evidence, skips-and-reports a third-entity alias collision through `MergeResult`, refuses on any lock over a source or its aliases or a whole lock on the target, and is undoable with original ids; split is human-only, moves rows by `matched_alias_id` plus the user's selection and never by quote text.
- [ ] `.ai` may merge parser entities (journaled, revertible, source name kept as an alias) but cannot rename, reclassify, delete, or change `is_relevant` on one, nor merge a locked or human-edited one; `.ai` cannot modify locked or protected rows; `.human` cannot modify a locked field without `unlock`; the matrix is proven by tests.
- [ ] Locks cover entity fields, scene synopsis, and `alias`/`*`; an alias lock refuses removal, re-targeting, and split.
- [ ] **Rejected tombstones prevent resurrection**: a proposal matching a rejected alias, applied through the internal levels, is skipped and creates no row.
- [ ] `acceptAllProposed` flips exactly the pairs in its payload and inverts exactly those; `acceptFacts` writes only `review_state` and `reviewed_at`; `revertExtractionRun` is selective with transitive skips, refuses when a newer run exists, returns a `RevertReport`, and preserves later human edits to dependent rows.
- [ ] Undo/redo work from the Edit menu and ⌘Z / ⇧⌘Z with per-operation action names; batch actions are one undo step; only one inverse is ever in flight and both commands are disabled while it applies; a non-applicable inverse clears the stack, reloads, and reports.
- [ ] Wardrobe/state ranges, continuity events, relationships with evidence quotes, scene entity roles, and scene synopses are editable; Continuity reads chronologically; `changes()` covers locks, journal, states, events, and relationships; the edit journal is readable from Edit ▸ Show Edit Journal….
- [ ] One shared list and one shared inspector serve all six kinds; every context action is mirrored in the Entity menu; every control has an accessibility identifier and label; provenance is visible for every fact and confidence renders Low/Medium/High.
- [ ] No view imports GRDB or `FilmScript` or executes SQL; `ProjectSnapshotDigest` lives under `Tests/`; no AI extraction, asset ontology, prompt generation, readiness, or Phase 2+ concept was added; Duplicate Project remains Plan 004's.
- [ ] `docs/plans/README.md` marks Plan 005 `DONE`.

## STOP conditions

Stop and report instead of improvising if:

- The design-doc hash differs and the change touches §3.5–§3.8, §5.5, or §6.
- An inverse cannot be expressed without exposing raw database access to the app or FilmBrain, or without storing full row snapshots.
- A row snapshot cannot round-trip a column without putting a GRDB type in a public payload.
- An operation's `affected` set cannot be computed without reading rows it did not touch, or conflict detection would need a single primary subject to stay tractable.
- Lock or protection enforcement would have to live in SwiftUI to work.
- Merge or split cannot preserve original ids on undo (later journal entries would break).
- The undo bridge cannot register synchronously inside the undo closure against the actor-isolated session without dropping to a `Task` completion, or serialization would require queueing inverses rather than disabling the commands.
- A verification command fails twice after one reasonable scoped correction.
- The work expands into AI extraction, reconcile, review UI, asset requirements, or readiness (Plans 006–007 and Phase 2).

## Maintenance notes

- Plan 007's `applyExtractionRun` must call `perform(_:actor:jobID:in:)` (there is no `apply` primitive) once per underlying change with actor `.ai(jobID)` inside its own transaction and savepoints; do not add a second write path, and do not let it call the public wrappers.
- Every operation added later needs an `EditOperation` case, a `displayName`, an inverse, an `affected` set, a `JournalInverseTests` sample, a row in the protection matrix, and an Entity-menu item if a human can invoke it.
- If undo across relaunch is ever wanted, the journal already holds what is needed; only the `UndoManager` bridge is session-scoped (design §14 decision 6).
- `ProtectionRank` is a product rule, not an implementation detail. Changing it changes merge outcomes on existing projects; update design §3.5 first.
- Re-import of a revised draft with preservation of edits, and re-parse with a newer parser, are deferred by product decision (design §14.3). If they return, the alias-keyed entity model and `scripts.parser_version` are the hooks; the remap rule must be designed then, not improvised.
