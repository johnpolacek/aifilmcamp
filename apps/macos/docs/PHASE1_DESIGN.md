# Phase 1 Design — The Screenplay Brain

Status: APPROVED CONTRACT, 2026-08-18 — revised after four independent
reviews (executor feasibility, roadmap fidelity, data-model soundness, app
contract) with the accepted findings folded in; the roadmap deltas (§13) and
the decisions (§14) were accepted by the product owner on 2026-08-18. Planned against commit `02cf45c`
(Plan 001 DONE).

Prototype-mode amendment, 2026-09-03: the automated test and evaluation
infrastructure described by this historical contract has been removed while
the product is being prototyped. The domain and safety contracts remain in
force; §10 and test-gate requirements are suspended until the product owner
ends prototype mode after the MVP shape is settled.

Revision 2026-08-26 (product-owner decision): validated AI output is active
immediately. The routine Proposed/Accepted review queue and downstream
“unreviewed” badges are retired; users correct or reject exceptions through
the ordinary editing model. `reviewed_at` remains NULL unless a person
actually edits or rejects a fact, so provenance stays honest. Bundle schema
v8 activates legacy proposals on open without claiming human review.

Revision 2026-08-19 (fresh seven-agent review, before any Phase 1 plan
started): alias rows are keyed by normalized form (§3.5); the merge collision
list and merge-alias provenance are corrected (§3.5); the undo/revert conflict
rule gains cancellation via `edit_journal.inverts_seq`, transitive skips, and
a newest-run-only revert (§3.8, §4.3); the v1→v2 migration is ordered and
backfills `current_script_id`, normalized `source_text`, and `title_page_json`
(§4.2); PROV gains `created_source` so §7.2's `origin` survives human edits
(§4.3, §7.2); `SubjectKind`, `EntitySummary`, `ConfidenceBand`, and lock reads
join the FilmCore contract (§4.4, §6); the parsing rules for title page, cue
exceptions, `EST.`, `=`/`===`, boneyard-across-scenes, and sequence spans are
pinned (§5.1–§5.3); the chunk reuse key drops `effective_model` (§8.2); the
applied-merge channel, stale-proposal replacement, `.parserOwned`, and the
`ApplyReport` shape are defined (§8.3, §8.5). None of these change the
architecture; the product owner should note `created_source` (a PROV column)
and the merge channel (AI may apply an unprotected merge) as the two
substantive additions. A second pass the same day made the conflict rule
redo-safe (live entries, §3.8), composed the alias normalizer (§3.5), moved
the rebuilt-table indexes after the rebuilds (§4.2), added the synopsis PROV
columns and `Job`/`ExtractionSettings` homes (§4.3, §4.4, §8.5), made the
per-run request count reuse-aware (§9), and pinned sequence ordinals, FDX
renderings, and `title_page_json`'s shape (§5).

Revision 2026-08-20 (product-owner decision, after Plans 002–004 shipped):
**PDF import moves into Phase 1** as Plan 008. `docs/ROADMAP.md` always listed
PDF ("Add PDF after the structured formats work well") and `docs/OVERVIEW.md`
lists it as a supported format; §11 deferred it only on sequencing, and the
roadmap's precondition is now met — Fountain, FDX, and plain text ship with a
deterministic parser and byte-exact answer keys. The additions are §3.2a (the
PDFKit decision), §5.4a (the extraction and rendering contract), §4.2a
(bundle schema 3, which widens one `CHECK`), the `pdf` case on
`ScreenplayFormat` and `scripts.format`, and a rendered-from-synthetic PDF
sample in §7.1. Nothing else changes: a PDF becomes Fountain-style text and
goes through the same parser, so scene segmentation, offsets, evidence
anchoring, and every downstream contract are untouched.

This document is the shared contract for Plans 002–008 in
`docs/plans/`. Plans reference it by section; executors read it in full before
starting any Phase 1 plan.

The intent documents (`docs/ROADMAP.md` Phase 1, `docs/OVERVIEW.md`,
`docs/REFERENCE_PROJECTS.md`, `AGENTS.md`) remain authoritative. Where this
document deliberately deviates from or refines them, the deviation is listed
in “Roadmap deltas” at the end so the product owner can accept or reject it.

---

## 1. What Phase 1 must deliver

From `docs/ROADMAP.md` (Phase 1 — The Screenplay Brain):

```text
1a   import + parser + deterministic scene list
     + manual entity editing, including merge / split / lock
     → usable on its own, no AI involved

1b   AI extraction proposing into that same editing model
     → never a second, parallel path into the data
```

Exit criteria (verbatim from the roadmap, mapped to plans):

| Roadmap exit criterion | Plan |
|---|---|
| feature screenplay can be imported | 002 (parser) + 003 (import) |
| scene boundaries come from the parser, not the model | 002 |
| recurring characters normalize correctly | 007 (scored by 006, multi-chunk) |
| locations normalize correctly | 007 (scored by 006, multi-chunk) |
| important props are extracted | 007 |
| wardrobe/state changes can be represented | 003 (schema) / 005 (editing) / 007 (extraction) |
| continuity events can be represented | 003 (schema) / 005 (editing) / 007 (extraction) |
| filmmaker can correct AI output | 005 + 007 |
| entities can be merged and split | 005 |
| important fields can be locked | 005 |
| AI cannot silently overwrite locked canonical information | 005 (enforcement) + 007 |
| every extracted fact carries evidence spans into the script | 003 (parser facts) + 007 (AI facts; anchor rate is measured, see §3.3) |
| extraction quality is scored against the evaluation set | 006 (scorer + exporter) + 007 (bootstrap, baseline report, gate) |

Phase 1 is finished when all six plans are `DONE`, `./scripts/verify.sh`
passes, and the evaluation report for the shipped prompt/schema is committed.

---

## 2. Plan structure and order

| Plan | Title | Sub-phase | Depends on |
|---|---|---|---|
| 002 | Fountain/FDX parser and syntax samples | 1a | 001 |
| 003 | Storage v2 and screenplay import | 1a | 002 |
| 004 | App shell and automation | 1a | 003 |
| 005 | Human correction, provenance, and locking | 1a | 004 |
| 006 | Evaluation scorer and answer-key exporter | 1b | 003 (parallel with 004–005; exporter integration lands after 005) |
| 007 | Chunked AI extraction, reconcile, and review | 1b | 005, 006 |

002 is pure Swift (no GRDB, no UI) and independently verifiable. 003 and 004
were one plan; they split because storage/migration/import and the app shell
have different risk profiles and together were oversized. 006 precedes 007 so
extraction ships scored, and the answer key comes from the operator's review
rather than a hand-written key (§7.2).

After 002–005 the app is a useful screenplay breakdown tool with no AI:
parser scenes, speaking characters from cues, locations from headings, and
full manual editing. That is the roadmap's "1a must be usable on its own."

## 3. Architecture decisions

### 3.1 Package layout

```text
Packages/FilmCore/
  Sources/FilmScript/        NEW target: pure-Swift screenplay parsing
  Sources/FilmCore/          domain, storage, ProjectTools (imports FilmScript)
Packages/FilmBrain/
  Sources/FilmBrain/         harness, generic structured jobs, extraction tasks
  Sources/FilmEval/          NEW target: scorer + eval report types (imports FilmCore)
  Sources/filmcamp-eval/     NEW executable: opt-in live evaluation runner
AI Film Camp/                app target
```

`FilmScript` is a separate library target inside the FilmCore package (not a
new package) so `swift test --package-path Packages/FilmCore` still covers it
and no new `Package.resolved` appears. It has **no dependencies** — no GRDB, no
Foundation types beyond `String`/`Data`/`URL` in its public API — so parser
tests are fast and the parser can be fuzzed in isolation. FilmCore imports it;
FilmBrain and the app never import it directly (they receive parsed data through
FilmCore types).

Dependency direction stays: app → FilmBrain → FilmCore → FilmScript. FilmCore
still imports neither FilmBrain nor SwiftUI. SwiftUI still contains no
`Process`, Codex arguments, GRDB, JSON Schema, or parser logic.

### 3.2 Parser: build, do not adopt

Decision: write the Fountain parser and the FDX reader in `FilmScript`.

Rationale (see the research summary in §12): no maintained Swift-6, SwiftPM,
permissively licensed Fountain parser exposes source ranges; the strongest
open implementations are either Objective-C, app-embedded, or GPL (Beat), and
GPL code cannot be adopted into this product. The Fountain surface a breakdown
tool needs is small and well specified. FDX is plain XML read with Foundation’s
`XMLParser` (SAX) — no dependency.

Plain text is not a third parser: Fountain is a superset of plain-text
screenplay formatting, so `.txt` goes through the Fountain parser. If a text
file yields zero scene headings, import still succeeds with one synthetic
scene (see §5.3) and a visible import warning.

Deterministic-parse contract: for the same input bytes, the parser produces
byte-identical `ScreenplayDocument` output (stable ordinals, offsets, and
normalized cues). Answer key-file tests enforce this.

### 3.2a PDF: extract with PDFKit, then reuse the Fountain parser

Decision: read PDFs with Foundation's `PDFKit` inside `FilmScript`, recover
each line's left margin, classify elements by margin, render Fountain-style
text, and parse that with the same `FountainParser`. This is the FDX pattern
(§5.4) applied to a format whose structure is positional rather than declared.

PDFKit is a **system framework**, not a package dependency, so §3.1's "no
dependencies" rule holds — `Package.resolved` does not change and no PDFKit
type appears in a public signature (`PDFReader.read(_ data: Data) throws ->
ScreenplayDocument` keeps the `String`/`Data`/`URL` boundary). The cost is
that `FilmScript` now links a UI-adjacent framework; that is accepted because
the alternative is a third-party PDF library, and no maintained, permissively
licensed Swift one extracts per-line geometry.

The honest limitation, stated because it differs in kind from Fountain and
FDX: a screenplay PDF declares no element types. Cue, dialogue, parenthetical,
and action are inferred from left margins, so classification is a **heuristic**
and a badly formatted or non-standard PDF may misclassify. A PDF with no text
layer is refused rather than OCR'd (§5.4a); OCR is a later phase.

### 3.3 Source text, offsets, and evidence

- `scripts.source_text` is the **canonical normalized text**: UTF-8, BOM
  stripped, line endings normalized to `\n`, no other transformation. The
  original imported file is preserved untouched under `screenplay/` and
  recorded as a `project_assets` row.
- For FDX **and PDF**, `source_text` is a deterministic Fountain-style
  rendering produced by that format's reader (`FDXRenderer.render`,
  `PDFRenderer.render` — same input bytes → same text). The original `.fdx` /
  `.pdf` is preserved. Users see the rendered text in the app; the original
  remains available via Reveal in Finder. Every span in the database is an
  offset into the rendering, never into the source file.
- All spans are **UTF-16 code-unit offsets** into `source_text`
  (`start_utf16`, `end_utf16`, half-open). UTF-16 is chosen because AppKit
  text highlighting (`NSRange`) and `String.Index(utf16Offset:in:)` make it
  the cheapest to consume on macOS, and it is unambiguous across languages.
- Scenes store their own span. Every other span also stores `scene_id` so
  evidence is local to a scene and survives scene-relative rendering.
- **The model never emits offsets.** AI evidence arrives as a scene id plus a
  short verbatim quote (≤ 240 UTF-16 units). Film Camp locates the quote
  deterministically: search only within `[scene.start_utf16, scene.end_utf16)`;
  exact match first, then a normalized match (whitespace runs collapsed,
  curly/straight quotes and dashes folded) performed over an explicit
  `normalizedIndex → originalUTF16Offset` map so the recorded span is always
  an offset into `source_text`; **first occurrence in document order** wins;
  a span not entirely inside the scene is rejected. If no span is found, the
  fact is still recorded with `evidence.anchored = 0`, the quote retained, and
  `confidence = min(reported, 0.5)` (or `0.5` when none was reported) — never
  rejected, never guessed. The evaluation report records the **anchor rate**
  and Plan 007 sets a done criterion on it (≥ 95% on the scored sample);
  unanchored facts have their own review filter. This is a deliberate
  refinement of the roadmap's “every fact carries evidence spans” and is
  listed in §13.

### 3.4 One polymorphic entity table

Characters, locations, props, vehicles, creatures, and objects share one
`entities` table with a `kind` column. Aliases, scene appearances, states,
continuity events, relationships, evidence, locks, and provenance therefore
have exactly one shape each instead of six.

Rationale: “reclassify” (roadmap human-correction list) becomes a one-column
update; merge/split logic is written once; the extraction schema has one entity
array; Phase 2’s asset requirements can reference any entity uniformly. The
Swift domain layer exposes `Entity` with `kind: EntityKind`; typed convenience
accessors (`characters`, `locations`) are query filters, not separate types.

Roadmap Phase 1 lists these as separate model concepts; this is a storage
decision, not a product change (see Roadmap deltas).

`entities.name` is a **display name**. Parser-created entities get a
deterministic title-cased form of the cue/heading (`SARAH` → `Sarah`,
`McKAY` → `McKay`, `INT. SARAH'S APARTMENT` location text → `Sarah's
Apartment`; roman numerals, apostrophes, hyphens, and interior capitals
preserved; the algorithm lives in `FilmScript.DisplayCase` and is answer key-
tested); the raw cue/heading remains an alias. A mixed-case cue such as
`McKAY` is recognized only through the `Mc`/`Mac`/`O'` exception of the cue
rule (§5.1) or a forced `@` cue. All matching, uniqueness, and
scoring use `name_normalized` (Unicode case-folded, NFC, whitespace-collapsed
— the same function `entity_aliases.normalized` uses), so casing never affects
identity.

### 3.5 Aliases are the memory of merges

`entity_aliases` holds every surface form that maps to an entity: parser cues
(`SARAH`, `SARAH (V.O.)` → normalized `SARAH`), heading location strings,
AI-proposed aliases, and human merges/renames. A normalized alias is **unique
per project and kind** (`UNIQUE(project_id, kind, normalized)`), so alias
lookup is a function, not a query with several answers.

**Alias rows are keyed by their normalized form, one row per distinct
normalized form per entity.** `entity_aliases.normalized` is **always**
`EntityNormalization.normalize(…)` — one folding function for one column, so
§3.4's "the same function" holds — applied to `CueNormalizer.normalize(raw).name`
for `alias_kind = cue` (cue peeling first, so `SARAH`, `SARAH (V.O.)`,
`SARAH (CONT'D)` share one row whose `alias` is the first raw form seen) and
to the raw surface form for every other alias kind; `entities.name_normalized`
is the same function over the display name. Location aliases
use `ParsedScene.locationText`, never the full heading line. Every alias insert
on the parser, migration, and AI paths is conditional: an existing row with the
same `(project_id, kind, normalized)` on the **same** entity is skipped; on a
**different** entity it is the `.aliasConflict(existingEntityID:)` case below.

- **Merge B into A**: move B's aliases, appearances, states, events,
  relationships, evidence, and child locations to A; B's name becomes an
  alias on A whose provenance follows the actor — a `.human` merge inserts
  `alias_kind = human`, `source = human`, `accepted`; an `.ai` merge inserts
  `alias_kind = mention`, `source = ai`, `proposed`, `job_id` set — unless A
  already holds that normalized form; delete B. Moving aliases cannot collide
  (the alias index does not contain `entity_id`), but inserting B's **name**
  as an alias can collide project-and-kind-wide with an unrelated third
  entity's alias: that insert is skipped and recorded in the effect (the
  human path surfaces it; the AI path counts it under `aliasConflicts`).
  Two uniqueness constraints do collide during a move —
  `scene_entities(scene_id, entity_id, role)` and `entity_relationships(from,
  to, kind)` — so every move is: select colliding rows, snapshot them **in
  full** into the journal payload, retarget their evidence to the survivor,
  delete the losers, then `UPDATE` the rest. A collision-losing appearance
  was the only carrier of its `matched_alias_id`; that link is **not**
  recoverable by a later split (one `scene_entities` row holds one alias
  link), so the split sheet lets the user re-select such appearances by hand.
  When two rows collide the survivor is the more
  protected one — `human` > `accepted` > `parser` > `ai/proposed`, ties by
  earliest `created_at`, then by `id`. Lock rows on B are snapshotted and
  removed (a lock on B — whole or field — blocks the merge until unlocked,
  see §3.7); a whole-record lock on **A** also refuses the merge for both
  actors, because the merge adds an alias to A.
- **Split alias X out of A**: create entity A′ from alias X (`source =
  human`); move the appearances and evidence whose **`matched_alias_id`** is X,
  plus any rows the user selects in the split sheet. Its inverse is **not** a
  plain merge — a merge preserves the source's name as a new alias, which would
  leave A holding an alias that never existed before the split. The inverse is
  a payload-driven `unsplit`: move the recorded rows back by id, delete A′ and
  every row the split created (its name alias included), and restore A's
  snapshot. Round-tripping a split must leave the tables byte-identical. Every appearance and
  evidence row records the alias that produced it (§4.3), so this is a lookup
  — never a text comparison of an evidence quote against an alias, which would
  effectively never match.
- **Rename** inserts the previous name as an alias (`alias_kind = human`)
  unless an equal normalized alias already exists on that entity, so a later
  run maps the old surface form to the renamed entity instead of creating a
  duplicate. **Reclassify** carries aliases to the new kind and re-checks
  uniqueness there (conflict → refused with the conflicting entity named).
- `addAlias` throws `.aliasConflict(existingEntityID:)` when the normalized
  alias belongs to another entity of the same kind; the UI offers Merge.

**An `.ai` run may merge two `parser` entities** and may merge an `ai` entity
into a `parser` one. This is the exception to §3.6's parser-owned rule, and it
exists because `SARAH` and `SARAH MORGAN` both arrive as parser cues — without
it no run could ever satisfy the roadmap's "recurring characters normalize
correctly". The merge is journaled, revertible, and loses nothing: the source
name survives as an alias. AI still may not rename, reclassify, delete, or
change `is_relevant` on a parser entity, and may not merge one that is locked
or that a human has edited.

Because aliases persist, re-running extraction is idempotent: the apply step
maps any proposed name to an existing entity by normalized alias match
**deterministically in FilmCore**, regardless of what the model claims. For the
`.ai` actor aliases are **append-only**: an AI run may add aliases (subject to
uniqueness; conflicts are skipped and reported) but never removes or edits
one, whatever the entity's review state. A whole-record lock additionally
forbids AI alias addition. Every human action that sets or clears a review verdict — `acceptFacts`,
`rejectEntity`/`unrejectEntity`, and the tombstoning removes — stamps
`reviewed_at`; a `.human` insert (created entity, rename alias, merge alias,
split entity) is born with `reviewed_at` set, an `.ai` insert never is.

### 3.6 Provenance, review state, and the “protected” rule

Every fact row (entity, alias, appearance, state, continuity event,
relationship, synopsis) carries:

```text
source        parser | ai | human
confidence    REAL nullable, CHECK 0..1; model-reported only; NULL for parser/human
review_state  proposed | accepted | rejected
reviewed_at   TEXT nullable — set ONLY by an explicit human action
job_id        nullable → jobs.id that CREATED the row; never overwritten
created_at / updated_at
```

`review_state = accepted` alone does not mean a person looked at the row:
parser rows and structurally and semantically validated AI-run output are
active as `accepted` without a human-review claim.
**`reviewed_at` is the only signal that an operator actually vouched for a
fact**, and it is set solely by `acceptFacts`/`acceptAllProposed` or by a human
edit — never by import, parser creation, or an AI apply. `job_id` records the
job that *created* the row and survives later human edits, so "the model found
this and a person corrected it" stays distinguishable from "a person added
this". §7.2's answer key depends on both.

Definitions:

- **protected** := `source = 'human'` OR (`source = 'ai'` AND
  `review_state = 'accepted'`). AI may never modify or delete a protected row.
- **parser rows** are authoritative for the fields the parser owns —
  entity `kind`, `name` (display) and `name_normalized`, cue/heading aliases,
  scene bounds and heading fields, `is_omitted`, `speaking`/`setting`
  appearances. They are `review_state = accepted` but **not** protected in the
  sense above: AI may fill a parser entity's empty `description`, add
  aliases, add appearances/states/events/relationships/evidence that reference
  it, and may **not** rename, reclassify, delete, or change `is_relevant` on
  it, and may merge parser entities together (§3.5 — the one exception, so
  normalization is possible). Parser rows are otherwise regenerated only by a
  replace-import (§5.5).
- **replaceable** := `source = 'ai'` AND `review_state = 'proposed'`. This is
  retained for migration and defensive engine compatibility; successful run
  apply activates its validated output before commit.
- **rejected** is the tombstone that stops resurrection: when a human deletes
  an `ai`- or `parser`-sourced entity/state/event/relationship, the row is set to
  `rejected` (hidden from every default list, visible under a Rejected
  filter, aliases retained). Apply treats a proposal that maps to a rejected
  row as `skippedRejected`. Hard delete remains available for human-created
  rows and from the Rejected list.
- Any human edit converts a row to `source = human` (and `accepted`);
  `acceptFacts` sets `review_state = accepted` without changing `source`.
  Both are protected. AI may still add new appearance/evidence rows that
  reference a protected entity.

`review_state` on an entity governs the entity row; alias, appearance, state,
event, and relationship rows carry their own. Default reads exclude
`rejected` and, unless asked, keep `proposed` rows in the same lists as
everything else — there is no shadow “proposals” table. This is the roadmap's
“proposals into the same editing model; never a second, parallel path.”

### 3.7 Locks

`locks(subject_kind, subject_id, field)` where `field` is one of an
enumerated set — entity: `name`, `description`, `kind`, `is_relevant`, `*`;
scene: `synopsis`, `*`; **alias**: `*`; state/event/relationship: `*` — never
an arbitrary column. An alias lock pins that surface form to its entity: it
blocks removal or re-targeting of the alias and blocks splitting it out. Whole-record lock on an entity forbids AI rename, reclassify,
description change, alias addition or removal, merge-away, or delete. Field
lock forbids AI changes to that field. Locks never block adding evidence or
appearance rows that reference the entity. **Any lock on a subject — whole or
field — blocks `merge` of that subject as a source and `split` of a locked
alias, for both actors**; the human path requires `unlock` first.

Enforcement lives in FilmCore: every mutation carries a `MutationActor`
(`.human` or `.ai(jobID)`), and `ProjectTools` rejects AI mutations that hit a
lock with `ProjectStoreError.locked(subject, field)`. Human mutations to locked
fields also throw until an explicit `unlock` (the UI shows locked fields
read-only with an Unlock control; this human-side guard is listed in §13).
Rejected AI changes are recorded in the run's apply report so the user can see
what the model wanted to change. Lock rows are removed (and snapshotted for
undo) when their subject is deleted or merged away.

### 3.8 Edit journal, undo, and revert

FilmCore records mutations in `edit_journal` (seq, at, actor, job_id, op,
`affected` set, payload JSON holding **full row snapshots** of anything
deleted or overwritten — never only ids).

Three distinct levels, so "one journal row" and "compound ops call the
primitive repeatedly" stop contradicting each other:

| level | shape | journals |
|---|---|---|
| **mutate** | internal `mutate(_ op, actor:, in db:) throws -> MutationEffect` | nothing; returns the inverse op and the rows it touched |
| **perform** | internal `perform(_ op, actor:, jobID:, in db:) throws -> JournalEntry` = `mutate` + one row | exactly one row |
| **group** | internal `performGroup(_ ops, as: EditOperation, actor:, jobID:, in db:)` | exactly one row whose `op` is the compound case (`.batch`, `.acceptAll`, `.merge`) and whose payload holds every child inverse in order |

Public `ScreenplayEditing` methods are thin `queue.write { perform(…) }`
wrappers: one transaction, one row. Batch UI actions and `acceptAllProposed`
use `performGroup`: one transaction, one row, inverted as a group.
`applyExtractionRun` is the deliberate exception — it uses `perform` per
underlying change so a run is revertible change-by-change (§8.5). No public
op is ever called from inside another (GRDB's `DatabaseQueue` is not
reentrant).

`affected: Set<SubjectRef>` lists **every** row the entry touched — the
entity, its aliases, appearances, evidence, states, events, relationships,
and lock rows — not one primary subject. Conflict detection (undo and revert)
compares affected sets, so a later human edit to any dependent row is seen.

**Conflict rule.** Every journal entry that applies an inverse records the
`seq` it inverts in `edit_journal.inverts_seq`. An entry is **live** when no
later live entry inverts it (computed walking `seq` descending: the newest
entry is live; an entry is live iff no live entry has `inverts_seq` = its
`seq`). Entry `E` may be inverted only if (a) `E` is live, and (b)
`E.affected` is disjoint from the union of `affected` over every later live
entry with `actor = 'human'` **whose `inverts_seq` is NULL or less than
`E.seq`** — later inverses of entries newer than `E` only restore states `E`
already saw, so they never conflict; an inverse of an entry older than `E`
does. Under this rule rename → set-description → ⌘Z → ⌘Z → ⇧⌘Z → ⇧⌘Z all
succeed: the second ⌘Z sees the first ⌘Z's row as a later inverse of a newer
entry, and each ⇧⌘Z inverts the undo row, which is live because nothing has
inverted it yet. Inverses restore the snapshotted
`updated_at`, `reviewed_at`, `review_state`, and `source` of every row they
touch, so undoing an accept leaves `reviewed_at` NULL again and an apply →
inverse round trip is byte-identical across **all** columns.

`mutate` returns each operation's inverse in `MutationEffect.inverse` (the
inverse is **not** a property of `EditOperation`; payload-driven inverses carry
their snapshots as associated values); each operation also has a `displayName`
(“Rename Character”, “Merge Entities”, “Lock Name”). The mapping:

| op | inverse |
|---|---|
| rename / setDescription / setSynopsis / reclassify / setRelevance / setLocationParent | same op with prior value |
| lock / unlock | unlock / lock |
| addAlias / removeAlias | removeAlias / addAlias |
| createEntity | deleteEntity |
| deleteEntity (human-created) | restoreEntity (payload holds the entity graph incl. lock rows) |
| rejectEntity (ai-created) / unreject | unreject / rejectEntity |
| merge(B→A) | unmerge (payload: moved and snapshotted rows) |
| split(A→A′) | unsplit (payload-driven; never a plain merge — §3.5) |
| setSceneEntity / removeSceneEntity | remove / set |
| addState / editState / removeState, addEvent / editEvent / removeEvent, add/removeRelationship | remove / prior / add |
| acceptFacts / acceptAllProposed | payload lists exactly the `(kind, id)` pairs flipped; inverse flips those back |
| importScreenplay / replaceScreenplay | **non-invertible** (stated; confirmed in the UI) |
| applyExtractionRun(job) | **non-invertible** — reversed only through `revertExtractionRun(job)`, which is not itself undoable |

Payloads are storage-independent: a `RowSnapshot` is a table name plus an
ordered `[String: JSONValue]`, never a GRDB type, so `EditOperation` and
`JournalEntry` stay `public Codable` without leaking persistence into the app.

Applying an inverse is a controlled public operation —
`ScreenplayEditing.applyInverse(entryID:actor:) async throws -> JournalEntry`
— not a generic "apply this operation" door. It re-checks preconditions and
throws `.inverseNoLongerApplicable(reason:)` if the affected rows moved.

An extraction apply writes one journal row per underlying change, all
carrying the run's `job_id`, plus a final `applyExtractionRun` row whose
payload is the `ApplyReport` only. `revertExtractionRun(jobID)` walks
`WHERE job_id = ? ORDER BY seq DESC` in one transaction and applies each
inverse **whose `affected` set is disjoint from every later uncancelled human
entry's `affected` set**; the rest are skipped and counted in the returned
report ("Reverted 412 changes; 3 skipped because you edited them"). Skips
are **transitive backward**: once an entry is skipped, every earlier entry of
the same run whose `affected` intersects the skipped entry's `affected` is
skipped too (otherwise reverting the AI's `createEntity` would cascade-delete
the human-edited alias that was just preserved). Revert is refused with
`.newerRunExists` while a later completed run's entries exist — only the
newest run is revertible, which is what the UI's "Revert last run" means. The
journal UI collapses consecutive same-`job_id` rows into one item.

Undo in the app: the window model owns `UndoManager`, supplies it to AppKit
(so Edit ▸ Undo/Redo validate) and to SwiftUI's environment, and registers
each human edit's inverse **synchronously inside the undo closure before
awaiting the async apply**, choosing the stack from `isUndoing`/`isRedoing`;
registrations are never made from a `Task` completion. Undo and redo are
**serialized**: the window model keeps one in-flight inverse at a time and
disables Undo/Redo while one is applying, so a second ⌘Z cannot race the
first. Batch actions group into one undo step. Inverse application validates preconditions and throws
`.inverseNoLongerApplicable(reason:)` rather than partially applying; on any
throw the bridge clears the stack, reloads from the store, and surfaces the
error. **On a successful AI apply or revert, the undo stack is cleared**
(“Undo history was cleared by this run”); AI runs are reversed only through
Revert last run, which is not itself undoable. This satisfies “AI changes are
recoverable” without a backup/restore scheme.

### 3.9 Jobs: runs, chunks, and reconcile

The Phase 0 job model stays; it grows:

- `jobs.parent_job_id` (nullable), `chunk_index`, `chunk_count`,
  `script_id`, `script_sha256`, `apply_report`. A **run** is a parent job
  with `task = extractScreenplay`; its children are `extractChunk` jobs (one
  Codex process each) and one `reconcileEntities` job. Runs are numbered for
  display by their 1-based order among parents per project.
- The Phase 0 “one active job per project” rule becomes **one active run per
  project**: `createJob` refuses a new *parent* while a parent is
  non-terminal and not `paused`; children of the active run may execute
  concurrently (§8.4). `Job.State` gains **`paused`** (`running → paused`,
  `paused → running | cancelled | failed`; non-terminal, survives relaunch).
  On `ProjectBundle.open`, non-terminal jobs other than `paused` whose owning
  process is gone are marked `failed` with `failure_code = abandoned`.
- Chunk jobs finish at `validating → completed` without committing anything
  canonical: their validated result files are inputs to reconcile. The
  transition is legal syntactically for all jobs; `ProjectRepository.
  transitionJob` rejects it when `parent_job_id IS NULL` (parents must go
  through `committing`).
- The parent run pins the script: apply throws `.scriptChangedDuringRun` if
  `scripts.sha256` differs from the run's `script_sha256`; import/replace are
  refused while any run is non-terminal or paused. Chunk payloads
  carry `(sceneID, ordinal)`; apply maps by id and uses the ordinal only to
  validate.
- The parent run owns the single canonical transaction (apply) and
  aggregates usage across children for display; reused children (§8.2)
  contribute zero usage.
- **Runner continuity.** Plan 003 generalizes Phase 0's `AnalyzeScreenplayJob`
  into `StructuredJobRunner` **in place**, keeping its seven behavior tests
  in tree against a test-only `EchoTask` and a probe schema; only the
  task-specific `analyzeScreenplay` pieces (DTO, validator, prompt, schema,
  `ProjectTools.applyAnalysis`/`analysisResults`, app views) are removed. Job
  history rows for the retired task remain readable. Between Plans 003 and 007
  the app detects Codex but offers no AI action; that is the roadmap's “1a
  usable on its own”.

### 3.9a `ProjectTools` becomes a composition of role protocols

Phase 0's `ProjectTools` is one protocol with nine members, and the test
decorator `FailingCommitProjectTools` re-implements all of them. Phase 1 adds
roughly thirty operations. To keep test doubles and future adapters small,
`ProjectTools` becomes a typealias over role protocols:

```swift
public typealias ProjectTools = ProjectReading & JobManaging & ScreenplayImporting
                              & ScreenplayEditing & ExtractionApplying & ProjectObserving
```

`ProjectSession` conforms to all of them. Tests decorate only the role they
need to fail. Phase 0's convenience overload `transitionJob(id:to:progress:)`
moves to `extension JobManaging` (a protocol composition cannot be extended).
`ProjectObserving` exposes `func changes() async -> AsyncStream<ProjectChange>`
(actor-isolated; a nonisolated version is impossible because the observation
needs the session's connection) implemented over GRDB `ValueObservation`
inside FilmCore with `.async(onQueue:)` scheduling and a `.bufferingNewest(1)`
continuation whose element is only the **set of changed areas** (`.script`,
`.scenes`, `.entities`, `.jobs`, `.journal`, `.locks`) — consumers always
refetch, so a coalesced duplicate is harmless. `close()` finishes all streams
before checkpointing. `DatabaseQueue` stays (single-project workload); reads
and observation contend with writes on the queue, so long writes (import,
apply, revert) show a blocking progress state in the UI and Plan 007 records
the measured apply time on a feature screenplay as an acceptance number.

### 3.10 Generic structured job runner

Plan 003 turns `AnalyzeScreenplayJob` into `StructuredJobRunner`, generic over
a `StructuredTask` that supplies: task name, schema resource URL, prompt
builder, and validator (result bytes → validated Swift value). The runner
keeps Phase 0's state machine, harness event handling, cancellation, and
failure mapping exactly; only the task-specific parts vary. `HarnessRequest`,
`HarnessAdapter`, `CodexHarnessAdapter`, and the invocation builder are
reused; `RecordedHarnessAdapter` gains a per-request script (ordered queue or
`(jobID) → sample` map) in Plan 007 so multi-chunk runs can be replayed;
its Phase 0 initializers are preserved.

### 3.11 App shell (Plan 004)

- **Windows.** A shared `AppCoordinator` owns Codex status, Finder URL
  routing, recent documents (`NSDocumentController.shared.
  noteNewRecentDocumentURL`), and the set of open `ProjectWindowModel`s. A
  project always opens in its own window (per-window model and
  `ProjectSession`); the Welcome window closes when a project opens and
  reopens when the last project window closes; opening a URL already open
  activates that window. There is no in-window Close Project — ⌘W closes the
  window and releases the session. Title = project name, subtitle = script
  display name or “No screenplay”, `.navigationDocument(bundleURL)` for the
  proxy icon.
- **No `NSDocument`.** SQLite is the document: every edit commits immediately,
  there is no dirty state or autosave. Undo comes from the journal (§3.8)
  through the window's `UndoManager`. **Duplicate Project…** (copy the bundle
  while closed — an open project is closed, copied, and reopened; Plan 004 —
  i.e. copy the closed
  bundle to a new location) is provided as the escape hatch for experiments.
- **Navigation.** `NavigationSplitView`: sidebar → content → inspector.
  Sections and contracts:

  | Section | Content list | Detail / inspector | Empty state |
  |---|---|---|---|
  | Scenes | `Table`: Ordinal, Scene #, Heading, INT/EXT, Location, Time (sortable) | scene text (selectable, evidence highlight, with a scene-local override editor), synopsis (read-only in 004; Plan 005 adds the editor), entities by role, states active in scene | “Import a screenplay to see its scenes.” (drop target) |
  | Characters / Locations / Props / Vehicles / Creatures / Objects | one shared `List` (multi-select): name, review badge, lock icon, appearance count | one shared inspector: name, kind, relevance, description, aliases, appearances by role, states, events, relationships, evidence (jump links), provenance line, locks | “Props appear after you analyze the screenplay, or add one with +.” |
  | Continuity | chronological continuity events: scene · entity · description · resulting state | event editor; linked state | “No continuity events yet.” |
  | Jobs | **runs** only, one row each (“Run 3 · date · 8 chunks · Completed · 41k tokens”), expandable to chunk rows | run card / apply report; Show Log in Finder; job UUID copyable | “No analysis runs yet.” |

  Nine sections in four groups; the entity empty state substitutes the
  section's plural noun (“Vehicles appear after…”) and is otherwise verbatim.
  The edit journal (Plan 005) is a sheet reached from Edit ▸ Show Edit
  Journal…, not a sidebar section.
  Multi-selection shows a count and only the actions valid for the whole
  selection. `.searchable` is scoped to the section (scenes: heading + text;
  entities: name + aliases). ⌘1…⌘9 switch sections; Return renames; Delete
  deletes with confirmation; ⌘I toggles the inspector; **⇧⌘I** is Import
  Screenplay…. Confidence renders as Low / Medium / High, never a raw float.
- **Menus.** A `Commands` block: File (New Project ⌘N, Open… ⌘O, Open Recent,
  Import Screenplay… ⇧⌘I, Duplicate Project…, Reveal in Finder, Close ⌘W);
  Edit (system Undo/Redo with action names, Delete, Show Edit Journal… —
  Plan 005); Entity (mirrors every
  context-menu action with shortcuts: Rename, Merge…, Split…, Move into…,
  Lock/Unlock, Mark Irrelevant, Accept, Reject/Delete); View (Toggle Sidebar,
  Toggle Inspector). A `Settings` scene (⌘,) with General / Codex / Advanced.
- **Navigation API.** `ProjectWindowModel.reveal(_ target: RevealTarget)`
  (`.scene(id, highlight: UTF16Range?)`, `.entity(id)`) switches section, sets
  selection, scrolls, and flashes the span; each section keeps its own last
  selection.
- **Data flow.** The window model reads through `ProjectSession` and refreshes
  from `ProjectObserving.changes()` (§3.9a). Views never hold GRDB types. The
  window model is constructible in unit tests over a temporary bundle
  (`ProjectWindowModel(session:undoManager:)`) and every command is an
  awaitable async method.
- **Accessibility.** Every actionable control has an accessibility
  identifier **and** label; icon-only controls (lock, badges) carry labels;
  evidence highlighting uses semantic colors.
- **Automation.** Phase 0 seams (`--film-camp-recorded`,
  `--film-camp-test-root`, Finder smoke) are kept. UI tests launch with
  persistence disabled (the Phase 0 lesson) and scope every query to a
  window. In Plan 003 the recorded flow becomes “create empty project →
  import bundled sample” and the Finder smoke and UI tests assert the
  sample's parser-derived counts instead of Phase 0's literal `1/1/1`; Plan
  007 appends “→ recorded extraction run → review” with Debug launch
  arguments to hold or fail a recorded run at a named stage so run-card,
  pause, and resume assertions are deterministic.

---

## 4. Bundle and storage changes

### 4.1 Bundle layout v2

```text
My Film.aifilm/
├── project.db                     user_version = 2
├── screenplay/
│   └── <original file name>       untouched import (fountain / fdx / txt)
├── assets/
├── exports/
├── cache/
│   └── jobs/<run-id>/             workspace/ (shared by the run's children)
│       └── <child-job-id>/        input.txt (chunk text), result.json
└── logs/
    └── jobs/<job-id>.jsonl
```

Projects are created **empty** in Phase 1 (`ProjectBundle.create(at:name:)`
replaces `create(at:name:sampleURL:)`; automation imports the bundled sample
after creation). `cache/jobs/*/input.txt` holds screenplay chunks for resume;
**Clear Job Cache** (Jobs section) deletes inputs and workspaces, keeps
`result.json` and logs. The disclosure names this (§9).

### 4.2 Migration v1 → v2

Registered as GRDB migration `"v2"` with the **default
`foreignKeyChecks: .deferred`** — it must not use `.immediate`, because the
`projects` rebuild relies on `PRAGMA foreign_keys = OFF` for the migration
(a `DROP TABLE` under enforcement would cascade-delete every child table).
`PRAGMA user_version = 2`; `FilmCoreVersion.bundleSchema` becomes 2. The
Phase 0 `projects` table has `CHECK (bundle_schema_version = 1)`, so v2
rebuilds it: create `projects_v2` with `CHECK (bundle_schema_version = 2)`,
`INSERT … SELECT …, 2, …` (rewriting the value), drop, rename.

Steps, in one migration transaction and **in this order** (the order is
load-bearing: backfills need the rebuilt tables, `scenes` is dropped before
the parser rebuild, indexes over rebuilt tables are created **after** the
rebuilds (a `DROP TABLE` takes its indexes with it, and a rebuilt table's new
columns do not exist until the rebuild), and `projects` is rebuilt last so
`current_script_id` resolves before GRDB's terminal `PRAGMA foreign_key_check`):

1. Create all **new** tables (§4.3) and the indexes on those new tables:
   `entities(project_id, kind)`, `scene_entities(entity_id)`,
   `scene_entities(scene_id)`, `evidence(subject_kind, subject_id)`,
   `evidence(scene_id)`, `evidence(owner_entity_id)`,
   `entity_states(entity_id)`, `entity_states(start_scene_id)`,
   `entity_states(end_scene_id)`, `continuity_events(scene_id)`,
   `continuity_events(entity_id)`, `entity_relationships(to_entity_id)`,
   `edit_journal(job_id)`, `edit_journal(inverts_seq)`,
   `scene_exclusions(scene_id)`, `edit_journal_affected(subject_kind,
   subject_id)`. (`entity_aliases(project_id, kind, normalized)` and
   `locks(subject_kind, subject_id)` are materialized by their `UNIQUE` /
   `PRIMARY KEY` constraints and are not created separately.)
2. Rebuild `scripts` and `jobs` (their `CHECK`s and `NOT NULL … REFERENCES`
   columns cannot be altered in place). Backfill `scripts.source_text =
   TextNormalization.normalize(source_text)` (Phase 0 stored raw bytes; v2
   offsets are into the normalized text), `format = 'fountain'`,
   `original_asset_id = source_asset_id`, `parser_version`, and recompute
   `sha256` over the normalized `source_text` (Phase 0 hashed file bytes).
3. Copy `characters`/`locations` into `entities` **grouped by
   `name_normalized`** (first row by `rowid` wins; later duplicates' names are
   retained as aliases on it), with
   `kind = character | location`, `source = ai`, `review_state = proposed`,
   `job_id` = the most recent completed `analyzeScreenplay` job if any; each
   Phase 0 name becomes an `entity_aliases` row (`source = ai`).
4. Drop `scene_characters` and `scene_locations`: Phase 0 appearances are
   not carried over (step 5 regenerates them from the parser), so nothing
   needs staging.
5. Re-parse the normalized `scripts.source_text` with `FilmScript`, drop and
   recreate `scenes` with **no row copy** (Phase 0's `CHECK (ordinal > 0)`
   forbids the preamble; the old model-produced rows are simply gone), and
   rebuild it with spans and parser metadata; backfill `title_page_json`,
   `parse_warnings_json`, and `scene_exclusions` from the same parse; if the
   parse yields no scenes, fall back to the §5.3 single synthetic scene and
   record `noSceneHeadings` in `parse_warnings_json` (the migration never
   throws on screenplay content). Phase 0 synopses carry over only where the
   parser scene count equals the old count (mapped by ordinal); otherwise
   every non-empty Phase 0 synopsis is dropped and counted in
   `synopsesDropped`. Phase 0 appearances are **not** carried over — the
   parser regenerates `speaking`/`setting` appearances authoritatively and a
   carried-over row would collide on `UNIQUE(scene_id, entity_id, role)`.
   Parser entities/aliases/appearances/evidence are created as in §5.3
   (existing entities are matched by `name_normalized` first; alias inserts
   are conditional per §3.5).
6. Backfill `jobs.script_id` from the single script (the columns themselves
   were added by the step-2 rebuild).
7. Rebuild `projects` last with `CHECK (bundle_schema_version = 2)` and set
   `current_script_id` to the single script's id (`NULL` only when the v1
   bundle holds no script). Drop `characters` and `locations`.
8. Create the indexes over the rebuilt tables: `jobs(project_id)`,
   `jobs(parent_job_id)`, `jobs(script_id)`, `jobs(supersedes_job_id)`,
   `scripts(project_id)`, `scenes(script_id, ordinal)`.

The migration test asserts row counts for `scripts`, `jobs`, and
`project_assets` before and after (guarding against the cascade failure mode),
plus the rebuilt scenes and entities, `script() != nil`, and — over two v1
fixtures synthesized in-test by SQL, not checked in — the synopses-dropped
branch (old scene count ≠ parser count) and the `noSceneHeadings` fallback. Phase 0 bundles are internal spike
artifacts; the app shows a one-way upgrade modal before migrating (what
changes: scenes rebuilt from the parser, model synopses dropped when the
scene count differs; Cancel / Upgrade) and an import-style summary after.

### 4.2a Migration v2 → v3 (Plan 008)

Adding `pdf` to `scripts.format` widens a `CHECK`, which SQLite cannot alter
in place, so bundle schema 3 is a registered GRDB migration `"v3"` that
rebuilds exactly two tables and copies every row:

1. Rebuild `scripts` with `CHECK (format IN ('fountain','fdx','text','pdf'))`;
   every other column, index, and foreign key is unchanged.
2. Rebuild `projects` with `CHECK (bundle_schema_version = 3)` and rewrite the
   stored value to `3`.
3. Recreate the indexes over both rebuilt tables (§4.2 step 8's
   `scripts(project_id)` among them) **after** the rebuilds.
4. `PRAGMA user_version = 3`; `FilmCoreVersion.bundleSchema` becomes 3.

The registered `"v2"` migration is **not** edited to include `pdf`: v2 bundles
already exist, GRDB records migrations by name, and retroactively changing one
would leave old and new databases with different constraints under the same
name. v2 → v3 is non-destructive — no re-parse, no row loss, no synopsis
dropped — so it does **not** show the one-way upgrade modal of §3.11, which
fires only for schema 1. The migration test asserts unchanged row counts for
every table and a clean `PRAGMA foreign_key_check`.

### 4.3 Schema v2 (new and changed tables)

Column conventions as Phase 0: TEXT UUIDs, ISO-8601 UTC timestamps **with
fractional seconds** (new `UTCDate` options `.withInternetDateTime,
.withFractionalSeconds`), foreign keys ON at runtime, `CHECK` constraints on
closed enums, `ON DELETE` stated on every foreign key. Provenance columns (`source`, `confidence CHECK 0..1`, `review_state`,
`reviewed_at` nullable, `job_id` = the creating job and never overwritten,
`created_source CHECK IN ('parser','ai','human')` = `source` at creation and
never overwritten, `created_at`, `updated_at`) are abbreviated below as
**PROV**. `source` answers "who owns this row now" (protection, §3.6);
`created_source` + `job_id` answer "who found it" (§7.2's `origin`).

```text
projects  (rebuilt)
  + current_script_id TEXT nullable REFERENCES scripts(id) ON DELETE SET NULL
  + disclosure_acknowledged_at TEXT nullable         -- first-run privacy acknowledgement travels with the bundle

scripts
  + format            TEXT NOT NULL CHECK (format IN ('fountain','fdx','text','pdf'))
  + original_asset_id TEXT NOT NULL REFERENCES project_assets(id) ON DELETE RESTRICT
  + title_page_json   TEXT NOT NULL DEFAULT '{}'      -- the encoded FilmScript TitlePage object {entries, lines}
  + parser_version    TEXT NOT NULL                     -- FilmScript version that produced scenes (recorded; a re-parse capability is deferred)
  + parse_warnings_json TEXT NOT NULL DEFAULT '[]'      -- ParseWarning codes/messages/ranges; the only way import and upgrade summaries can report them
  (source_text remains the normalized text; sha256 = digest of source_text)

sequences
  id, script_id FK ON DELETE CASCADE, ordinal INT, depth INT, title TEXT,
  start_utf16 INT, end_utf16 INT, PROV
  UNIQUE(script_id, ordinal)                 -- from Fountain sections; empty otherwise

scenes  (rebuilt)
  id, script_id FK ON DELETE CASCADE, ordinal INT NOT NULL CHECK (ordinal >= 0),
  sequence_id FK nullable ON DELETE SET NULL,
  heading TEXT, int_ext TEXT CHECK IN ('int','ext','int_ext','unknown'),
  location_text TEXT, time_of_day TEXT,       -- parsed from heading, may be ''
  scene_number TEXT nullable,                 -- author's #12A#
  start_utf16 INT, end_utf16 INT,
  synopsis TEXT NOT NULL DEFAULT '',
  synopsis_source, synopsis_created_source, synopsis_confidence,
  synopsis_review_state, synopsis_reviewed_at, synopsis_job_id,
  synopsis_updated_at                         -- full PROV for the synopsis field only
  is_omitted INT NOT NULL DEFAULT 0
  UNIQUE(script_id, ordinal); UNIQUE(script_id, start_utf16)
  -- ordinal 0 exists at most once per script and only for a preamble with action/dialogue

entities
  id, project_id FK ON DELETE CASCADE,
  kind TEXT CHECK IN ('character','location','prop','vehicle','creature','object'),
  name TEXT NOT NULL, name_normalized TEXT NOT NULL,   -- display name; normalized = folded/NFC/whitespace-collapsed
  description TEXT NOT NULL DEFAULT '',
  parent_id TEXT nullable REFERENCES entities(id) ON DELETE SET NULL
            CHECK (parent_id IS NULL OR parent_id <> id),   -- locations only; cycle guard in Swift
  is_relevant INT NOT NULL DEFAULT 1,
  PROV
  UNIQUE(project_id, kind, name_normalized)

entity_aliases
  id, entity_id FK ON DELETE CASCADE, project_id FK, kind TEXT,   -- denormalized, kept in sync by reclassify/merge
  alias TEXT, normalized TEXT,
  alias_kind TEXT CHECK IN ('cue','heading','mention','human'),
  PROV
  UNIQUE(project_id, kind, normalized)

scene_exclusions                              -- ranges the model must not see
  id, scene_id FK ON DELETE CASCADE,
  kind TEXT CHECK IN ('note','boneyard'),
  start_utf16 INT, end_utf16 INT
  INDEX(scene_id)                             -- written by import from ParsedElement ranges

scene_entities
  id, scene_id FK ON DELETE CASCADE, entity_id FK ON DELETE CASCADE,
  role TEXT CHECK IN ('speaking','present','mentioned','setting','used'),
  matched_alias_id TEXT nullable REFERENCES entity_aliases(id) ON DELETE SET NULL,
  PROV
  UNIQUE(scene_id, entity_id, role)

entity_states
  id, entity_id FK ON DELETE CASCADE,
  category TEXT CHECK IN ('wardrobe','hair','makeup','injury','age','condition',
                          'possession','time_of_day','weather','lighting','damage','other'),
  description TEXT,
  start_scene_id FK NOT NULL ON DELETE CASCADE, end_scene_id FK nullable ON DELETE SET NULL,
  PROV

continuity_events
  id, scene_id FK NOT NULL ON DELETE CASCADE, entity_id FK nullable ON DELETE CASCADE,
  description TEXT, resulting_state_id FK nullable ON DELETE SET NULL, PROV

entity_relationships
  id, from_entity_id FK ON DELETE CASCADE, to_entity_id FK ON DELETE CASCADE,
  kind TEXT CHECK IN ('family','romantic','professional','adversarial','possession','other'),
  description TEXT, PROV
  UNIQUE(from_entity_id, to_entity_id, kind)

evidence
  id, subject_kind TEXT CHECK IN ('entity','alias','appearance','state','event','relationship','synopsis'),
  subject_id TEXT,
  owner_entity_id TEXT nullable REFERENCES entities(id) ON DELETE CASCADE,
        CHECK ((subject_kind = 'synopsis') = (owner_entity_id IS NULL)),
  scene_id FK ON DELETE CASCADE,
  matched_alias_id TEXT nullable REFERENCES entity_aliases(id) ON DELETE SET NULL,
  start_utf16 INT nullable, end_utf16 INT nullable, anchored INT NOT NULL,
        CHECK ((anchored = 1) = (start_utf16 IS NOT NULL AND end_utf16 IS NOT NULL)),
  quote TEXT, source TEXT CHECK IN ('parser','ai','human'), job_id nullable, created_at

locks
  subject_kind TEXT CHECK IN ('entity','alias','scene','state','event','relationship'),
  subject_id TEXT, field TEXT,                          -- enumerated per §3.7; '*' = whole record
  locked_at TEXT, PRIMARY KEY(subject_kind, subject_id, field)
  -- no FK (polymorphic); removed by delete/merge ops and snapshotted for undo

edit_journal
  seq INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT,
  actor TEXT CHECK IN ('human','ai'), job_id nullable,
  inverts_seq INTEGER nullable REFERENCES edit_journal(seq) ON DELETE SET NULL,
        -- set when this entry applied another entry's inverse (§3.8 cancellation)
  op TEXT, payload TEXT (JSON; RowSnapshots + child inverses for group entries)
edit_journal_affected                         -- the entry's read-write set (§3.8)
  seq FK ON DELETE CASCADE, subject_kind TEXT, subject_id TEXT
  PRIMARY KEY(seq, subject_kind, subject_id); INDEX(subject_kind, subject_id)

jobs
  + parent_job_id TEXT nullable REFERENCES jobs(id) ON DELETE RESTRICT
  + chunk_index INT nullable, chunk_count INT nullable
  + attempt_index INT nullable, supersedes_job_id TEXT nullable REFERENCES jobs(id) ON DELETE SET NULL
  + script_id TEXT nullable REFERENCES scripts(id) ON DELETE SET NULL, script_sha256 TEXT nullable
  + apply_report TEXT nullable (JSON)
  state CHECK gains 'paused'
```

Deleted-row policy: deleting an entity cascades to aliases, appearances,
states, relationships (both directions), and evidence via `owner_entity_id`;
lock rows are removed by the operation; the journal payload keeps the full
graph for undo. Human deletion of an `ai` or `parser` row is a `rejected`
tombstone (§3.6), not a delete.

### 4.4 Domain types

New public FilmCore types (exact names are contracts for the plans):
`Entity`, `EntityKind`, `EntityAlias`, `SceneEntity`, `EntityState`,
`ContinuityEvent`, `EntityRelationship`, `Evidence`, `Lock`, `Provenance`,
`ReviewState`, `MutationActor`, `EditOperation`, `JournalEntry`, `SubjectRef`,
`SubjectKind` (`entity | alias | appearance | scene | state | event |
relationship | synopsis | script`; `locks.subject_kind` and
`evidence.subject_kind` are subsets, named in §4.3), `ConfidenceBand`,
`EntitySummary`, `ScriptSequence` (not `Sequence`, which would shadow
`Swift.Sequence`); `Provenance` exposes `source`, `createdSource`,
`reviewedAt`, and `jobID`, and `Entity`/`EntityDetail` carry it; `Job`
exposes `parentJobID`, `chunkIndex`, `chunkCount`, `attemptIndex`,
`supersedesJobID`, `scriptID`, `scriptSHA256`, and `applyReport` beside its
Phase 0 fields; `ApplyReport` and `ExtractionSettings` (§8.5) are FilmCore
types;
`Scene` gains `intExt`, `locationText`, `timeOfDay`, `sceneNumber`, `range`
(UTF-16), `sequenceID`, `isOmitted`.

`FilmScript` public types: `ScreenplayDocument`, `ScreenplayFormat`,
`ParsedScene`, `ParsedElement` (`kind`, `range`, `text`), `ParsedCue`
(`raw`, `normalized`, `extensions`), `TitlePage`, `FountainParser`,
`FDXReader`, `ScreenplayImporter` (format sniffing + normalization),
`ParseWarning`.

---

## 5. Deterministic parsing contract (Plans 002–003)

### 5.1 Fountain elements the parser must recognize

Required for a breakdown tool: title page block; scene headings (`INT.`,
`EXT.`, `EST.`, `INT./EXT.`, `INT/EXT`, `I/E` prefixes, case-insensitive,
followed by `.` or space) and forced headings (`.` prefix); scene numbers
(`#12A#` suffix); character cues (uppercase line followed by non-blank line;
forced `@`; extensions `(V.O.)`, `(O.S.)`, `(O.C.)`, `(CONT'D)`, `(cont'd)`
etc.; dual-dialogue `^`); parentheticals; dialogue; action; transitions
(uppercase ending in `TO:` or forced `>`); centered text `> <`; sections `#`
(→ sequences) and synopses `=`; notes `[[ ]]`, boneyard `/* */`, page breaks
`===`, lyrics `~`; emphasis markers are preserved as text (not styled).

Rules the plans must not have to guess:

- **Title page**: exists only when the first non-blank line of the normalized
  text matches `^[A-Za-z][A-Za-z ]*:` and the block runs to the first blank
  line; indented continuation lines append to the previous value. `FADE IN:`
  is never a title-page key (it is a transition/action line), so a file that
  opens with it has no title page and its text before the first heading is
  the preamble. The body begins after the blank line that ends the block.
- **Cue**: an uppercase line (no lowercase letter outside trailing
  parenthesized extensions) **or** a line whose only lowercase letters are the
  interior of a `Mc`/`Mac`/`O'` prefix (`McKAY`, `O'BRIEN`), or a forced `@`
  cue; preceded by a blank line and followed by a non-blank line.
- **`EST.`** maps to `int_ext = ext`.
- **`=`** at line start is a synopsis; a line of three or more `=` is a page
  break. Fountain synopses are parsed as elements and deliberately **not**
  written to `scenes.synopsis` in Phase 1 (the synopsis column is AI/human).
- **Notes and boneyard** are excised **before** line classification, so a
  heading inside `/* … */` starts no scene; an element's range is clipped to
  each scene it overlaps and emitted once per scene, which is what
  `scene_exclusions` stores.

Treated as generic action text in Phase 1: emphasis, lyrics, centered text
(they count as "action" for the scene-0 rule in §5.2).
Notes and boneyard are excluded from the scene text used for extraction but
their ranges are preserved.

Normalization before parsing: strip UTF-8 BOM, `\r\n`/`\r` → `\n`, no other
changes (smart quotes and Unicode remain, so offsets stay honest).

### 5.2 Scene segmentation

- A scene starts at each scene heading or forced heading. Its span runs from
  the start of the heading line to the start of the next heading (or end of
  text). Trailing blank lines belong to the preceding scene.
- Text before the first heading (after the title page) is a **preamble**: it
  is stored as scene ordinal 0 only if it contains dialogue or action
  (centered text and lyrics count as action); otherwise it is not a scene.
  Scene 0's span starts at the first character after the title-page block
  (offset 0 when there is none). Ordinal 0 is displayed as “Before first
  scene”.
- Ordinals are parser-assigned, contiguous from 1 in document order.
  Author scene numbers (`#12A#`, FDX `Paragraph@Number`) are stored
  separately in `scene_number` and never used for ordering.
- Heading decomposition (best-effort, all stored, none inferred): `int_ext`
  from the prefix; `location_text` = heading minus prefix and minus the last
  ` - ` / ` – ` / ` — ` segment when that segment is a known time-of-day token
  (`DAY, NIGHT, DAWN, DUSK, MORNING, AFTERNOON, EVENING, LATER, CONTINUOUS,
  SAME, MOMENTS LATER, SUNSET, SUNRISE, MAGIC HOUR` and `NIGHT (LATER)`-style
  variants); `time_of_day` = that segment or ``. Headings without a
  time-of-day keep the full remainder as `location_text`.
- `CONTINUOUS`/`LATER`/`SAME` do not merge scenes; they are ordinary scenes
  whose `time_of_day` records the token. Interpretation is Phase 1b/2 work.
- Headings whose location text is `OMITTED` set `is_omitted = 1`.
- **Sequences.** A scene belongs to the most recent `#` section of the
  shallowest depth that starts at or before the scene heading; deeper
  sections are recorded as `sequences` rows (with `depth`) but do not reassign
  scenes; a section that starts inside a scene's span does not split it. A
  sequence's own span runs from the start of its `#` line to the start of the
  next section of the same or shallower depth, or end of text. Sequence
  `ordinal` is contiguous from 1 in document order across **all** depths (a
  depth-3 section takes the next ordinal, never a per-depth counter — it
  feeds `UNIQUE(script_id, ordinal)`); `title` is the line after the leading
  `#` run, trimmed.

### 5.3 Deterministic entities from the parser (source = parser)

Plan 003 creates entities without any AI:

- One `character` entity per distinct normalized cue (`SARAH (V.O.)`,
  `SARAH (CONT'D)`, `SARAH` → one entity `SARAH`, one `cue` alias row per
  distinct normalized form, §3.5), plus a `speaking` appearance for every
  scene in which the cue occurs, each with parser evidence (the cue line
  span) and `matched_alias_id` set.
- One `location` entity per distinct normalized `location_text`
  (case-folded, whitespace-collapsed), with one `heading` alias row per
  distinct normalized `location_text` and a `setting` appearance per scene,
  evidence = the heading span.
- Nothing else. Aliases such as `SARAH` vs `SARAH MORGAN`, non-speaking
  characters, props, and states are AI/human work.

If a text file yields no scene headings, import creates one scene
(`ordinal 1`, heading `UNTITLED`, `int_ext = unknown`) spanning the whole body
(after the title-page block, or the whole text when there is none),
plus cue-derived characters, and reports the warning `noSceneHeadings`. An
empty body yields that same single scene plus `emptyDocument`, so a script
always has at least one scene.

### 5.4 FDX

There is no public FDX schema; the rules below are reverse-engineered from
real files and existing importers (§12.1). `FDXReader` uses Foundation
`XMLParser` (SAX) with these rules:

- Read only `/FinalDraft/Content` **direct child** `Paragraph` elements.
  `Paragraph` is recursive: `SceneProperties/Summary`, `SceneArcBeats`,
  `ScriptNote`, and `DualDialogue` all nest paragraphs. Descend deliberately
  into `DualDialogue` only; everything nested elsewhere is metadata (a
  descendant selector would inject synopsis prose into the script text).
  Track element depth explicitly to survive SAX re-entry.
- `Paragraph@Type` is optional (absent on title-page and dual-dialogue wrapper
  paragraphs); default to `Action`. Recognized body types: `Scene Heading`,
  `Action`, `Character`, `Parenthetical`, `Dialogue`, `Transition`, `Shot`,
  `General`, `Cast List`, `New Act`, `End of Act` / `End Of Act`, `Lyrics`,
  and (declared by newer templates) `Outline 1–4`, `Outline Body`, `Cold
  Opening`, `Sequence`, `Summary`, `Note`, `Act Info`, `Show/Ep. Title`.
  `Shot`, `General`, `Cast List`, `End of Act`/`End Of Act`, `Act Info`, and
  `Show/Ep. Title` render as action lines (recognized, no warning); `Lyrics`
  renders with a leading `~`; `Sequence`/`New Act`/`Cold Opening` render as
  Fountain sections (`#`) so they become sequences; `Summary`, `Note`,
  `Outline *` render as Fountain notes/boneyard (excluded from scene text but
  ranged); any other type renders as action with warning
  `unsupportedParagraphType`. Never drop an unknown paragraph.
- Paragraph text = concatenation of **direct** `Text` children in order,
  **no separator, no trimming** (styled words split a sentence into runs and
  the spaces live at run boundaries). `Text@Style` tokens are `+`-joined
  (`Bold+Italic`), ignored for text. `Text` may contain embedded newlines
  (kept) and tabs. Empty paragraphs (`<Paragraph …/>`) are dropped from the
  body but kept for index alignment. `DynamicLabel` has no text.
- **Scene number is `Paragraph@Number`** (a string: `"12A"`), absent when
  numbering is off; `SceneProperties` carries `Title`, `Length`, `Page`,
  `Color` and never the number. Rendered as the `#N#` suffix.
- Dual dialogue: an outer wrapper paragraph containing `<DualDialogue>` with
  the two speakers' Character/Parenthetical/Dialogue paragraphs flat and in
  sequence; the second `Character` cue gets a Fountain `^`.
- `TitlePage` has its own `Content` and no semantic fields (positional free
  text, mostly empty spacer paragraphs); it is excluded from `source_text`
  and stored in `title_page_json` as `TitlePage.lines` = the non-empty
  lines in order (`entries` empty); for Fountain, `lines` holds the block's
  non-blank source lines verbatim and `entries` the parsed key/value pairs.
- Ignore `Revisions`, `TagData`, `SmartType`, `ScriptNotes`, and all UI/print
  state; do not require any element to exist; `FinalDraft@Version` is the
  schema revision (observed 1–6), not the app version.
- Rendering (deterministic Fountain-style `source_text`): paragraphs in
  document order, one blank line between paragraphs; headings and cues
  as authored (forced `.`/`@` prefix only when the text would not otherwise
  parse); transitions get `> ` only when needed. The rendered text is parsed
  by the same Fountain parser so scene rules are identical for both formats.
- Malformed XML throws `FDXReadError.malformed(line:column:)`. UTI:
  `com.finaldraft.fdx` (declared by Final Draft; the app declares it as an
  imported type).

### 5.4a PDF

A screenplay PDF encodes element type **positionally**: the left margin says
what a line is. `PDFReader` recovers that geometry and `PDFRenderer` turns it
back into Fountain, which the same `FountainParser` then parses — one scene
contract for all four formats.

**Extraction.** `PDFDocument(data:)`; a locked or encrypted document throws
`PDFReadError.encrypted`, an unopenable one `.unreadable`. For each page, take
`page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine()`, and for
each line record its trimmed text, its `bounds(for: page)`, and its page index.
A document whose total extracted text is under 200 characters has no usable
text layer and throws `.noTextLayer(pagesTotal:pagesWithText:)` — a scanned PDF
is refused, never OCR'd and never silently rendered as an empty screenplay. The
associated counts exist so the app can say *how* the file failed ("no selectable
text in 0 of 91 pages") rather than only that it did; whether OCR is ever worth
building is a question about how often real material lands here, and a refusal
that reports its own shape is the only honest way to answer it.

**Margins are fractions, not inches.** Every left edge is normalized as
`(minX - mediaBox.minX) / mediaBox.width`, so Letter, A4, and scaled documents
classify identically. The canonical screenplay anchors on an 8.5" page are
action `0.176` (1.5"), dialogue `0.294` (2.5"), parenthetical `0.353` (3.0"),
character cue `0.435` (3.7").

**Classification is document-calibrated, then anchored.** Build a histogram of
left-margin fractions over the whole document in 0.01 buckets; a **cluster** is
a bucket holding at least 2% of all lines, merged with its immediate
neighbours. Each cluster is assigned to the nearest canonical anchor, and when
two clusters claim one anchor the closer one wins and the other falls to the
next anchor in ascending margin order. Lines in no cluster are rendered as
action and warn `unclassifiedMargin` once per document. Calibration is
deterministic: same bytes → same clusters → same assignment.

**Page furniture is dropped** by two rules with different guards, because the
two kinds differ in how self-identifying they are. A line whose entire text
matches `^\(?(CONTINUED|MORE)\)?:?$` (case-insensitive) is **always** dropped,
wherever it sits: no screenplay has a line of body text that is only `(MORE)`
or `CONTINUED:`, and measurement on real material puts these markers at
0.89–0.92 of page height — just above the one-inch bottom margin, which a
tighter positional band misses. A line that is purely a page number
(`^\d+\.?$`) is dropped only when it sits in the top or bottom 8% of the page
**and** at a left fraction above `0.75`, because a bare number *can*
legitimately be dialogue or action and has been observed as such. Nothing else
is ever dropped — an unrecognized line becomes action.

**Blank lines are reconstructed from vertical gaps.** Within a page, the gap
between consecutive lines is `previous.minY - current.maxY`; the modal
positive gap across the document is the single-spaced baseline, and a gap of at
least half the modal line height starts a new block. A page boundary always
starts a new block.

**The title page is metadata, not screenplay content.** Page 1 is a title page
when it contains **no scene heading and at most 12 lines**; its non-empty lines
become `TitlePage.lines` verbatim in order (`entries` empty, as for FDX) and are
**excluded from `source_text`**, and no line on that page is margin-classified.
Both halves matter. Excluding it keeps title-page prose out of every downstream
consumer — extraction, evidence, and Phase 2's asset generation read
`source_text`, and a title is data *about* the screenplay rather than part of
it. Suppressing classification prevents the specific failure this rule was
written for: a centered title, `Written by`, and an author name sit at
0.43–0.46 of the page width, land in the character-cue cluster, and would
otherwise become three character entities on import. A screenplay that opens
directly on a scene has a heading on page 1 and is untouched by the rule.

**Rendering** follows `FDXRenderer`'s rule exactly: one blank line separates
logical blocks, and none appears inside a cue → parenthetical → dialogue run,
so the rendered text re-parses with the same cue structure. Headings are the
action-margin lines matching a §5.1 prefix (or forced with `.` only when they
would not otherwise parse); cues take a forced `@` only when the text would not
otherwise parse as a cue; transitions take `> ` only when needed. Two lines
that share a vertical band but occupy disjoint horizontal ranges are
side-by-side dual dialogue: they are rendered sequentially and warn
`dualDialogueColumnsDetected` once per document, because column interleaving is
not reconstructible from reading order alone. A **single** such pair is an
extraction artifact, not a dual-dialogue block — a real one spans a cue pair
and several dialogue lines — so the warning fires only when at least **three
consecutive** vertical bands each hold two or more horizontally disjoint lines.
The run, not the count, is what discriminates: PDFKit splits a single visual
line into two selections at a style-run change — a character name set in a
different font on first appearance produces two selections sharing a baseline
and separated by one space-width — and measurement on real material found three
such artifacts in a 91-page screenplay, enough to trip a document-wide count,
but never two in a row. Bands are grouped by vertical position rather than
document order, because a page's two columns are returned one after the other.

`ScreenplayFormat` gains `pdf`; `scripts.format` stores `'pdf'` (§4.2a).

### 5.5 Import and replace

`ScreenplayImporter.load(url)` (FilmScript) → sniff format (extension, then
content: leading `%PDF-` → pdf; XML root `FinalDraft` → fdx; else
Fountain/text) → normalize → parse
→ `ScreenplayDocument` + warnings. FilmCore's `importScreenplay(from url:
actor:)` calls it internally — the app never handles `ScreenplayDocument`
(§3.1) — copies the original into `screenplay/` (collision → `-2`, `-3`),
records the asset, inserts the script (`format`, `original_asset_id`,
`source_text`, `sha256` of the normalized text, `title_page_json`,
`parser_version`), sets `projects.current_script_id`, and inserts sequences,
scenes, parser entities/aliases/appearances/evidence, plus one non-invertible
`importScreenplay` journal entry — all in one transaction.

When a script already exists there is exactly one path in Phase 1:
**Replace**, allowed only while no protected fact and no lock exists (i.e. the
project holds nothing but parser facts and unreviewed AI proposals); it wipes
script-scoped rows and all entities, then imports fresh. It is refused while a
run is non-terminal or paused, confirmed in the UI, and non-invertible.
Otherwise import is refused with “This project already has a screenplay
you've worked on. Start a new project for a revised draft (File ▸ Duplicate
Project… copies this one).” Re-import of a revised draft with preservation of
edits, and re-parse of an existing project with a newer parser, are **out of
scope for Phase 1** (decision §14.3): the filmmaker corrects the breakdown
inside the app. A later generation-workspace extension may store a scene-local text
override without mutating the imported script; replacing a materially revised draft
remains a new-project workflow.
`scripts.parser_version` is recorded so a later phase can offer re-parse.

---

## 6. Editing contract (Plan 005)

`ProjectTools` grows a mutation API; every call takes `actor: MutationActor`
and returns the applied `JournalEntry` (with inverse and `displayName`) so
the app can register undo. Operations (public wrappers over the internal
primitives of §3.8):

```text
createEntity(kind, name, description) / deleteEntity(id)     // ai rows → rejectEntity
rejectEntity(id) / unrejectEntity(id)
renameEntity(id, name) / setDescription(id, text) / reclassify(id, kind)
setRelevance(id, isRelevant) / setLocationParent(id, parentID?)
addAlias(entityID, alias) / removeAlias(aliasID)
mergeEntities(sourceIDs: [UUID], into targetID)
splitEntity(entityID, aliasIDs: [UUID], newName, movedAppearanceIDs) → new entity
setSceneEntity(sceneID, entityID, role) / removeSceneEntity(id)
setSynopsis(sceneID, text)
addState / editState / removeState ; addEvent / editEvent / removeEvent
addRelationship / removeRelationship
lock(subject, field) / unlock(subject, field)
acceptFacts(subjectRefs) / acceptAllProposed()
revertExtractionRun(jobID) → RevertReport
```

Validation in FilmCore: names non-empty and unique per kind on
`name_normalized` after trim; merge target must not be among sources; split
requires ≥1 alias left on the source; kind change of a location with children
is refused; `setLocationParent` refuses non-locations, self, and cycles
(ancestor walk); alias conflicts per §3.5; lock/protection rules per §3.6–§3.7.
Each public op is one transaction and journals one entry;
`acceptAllProposed` journals one entry whose payload lists exactly the pairs it
flipped. Compound ops use the internal primitives (§3.8).

Reads (`ProjectReading`): `script()` (by `projects.current_script_id`),
`scenes()`, `scene(id)` with entities, the states active in the scene, and
**synopsis-subject** evidence only, `sceneText(id)`, `sceneExclusions(id)`,
`sequences()`, `continuityEvents()` (scene-ordinal order, entity-less events
included),
`entities(kind:reviewState:includeIrrelevant:includeRejected:)` (defaults
exclude rejected), `entitySummaries(kind:…)` (the list shape: name, kind,
review state, `isLocked`, `appearanceCount`), `entity(id)` with aliases/
appearances/states/events/relationships/evidence/**locks**, `locks()`,
`journal(limit:)`, `pendingReviewCount()`, `runs()` (parent jobs with
aggregated usage), `jobHistory()`, `disclosureAcknowledgedAt()`. Every
entity-owned evidence row appears in exactly one `EntityDetail` and every
synopsis row in exactly one `SceneDetail`, so the two partition the table
(Plan 006's anchor rate depends on it).

Undo: the app registers the entry's `seq` with the window `UndoManager` and
calls `applyInverse(entryID:actor:)` per
§3.8; AI-run revert is `revertExtractionRun` (selective, reported).

---

## 7. Evaluation contract (Plan 006)

Two artifacts do the measuring, and they are different things:

- an **expected-parse file** (`<name>.parse.json`) — a saved copy of exactly
  what the parser produced for a sample screenplay. The parser is
  deterministic, so if its output ever changes, a test fails and shows the
  diff. Mechanical; no judgment involved.
- an **answer key** (`<name>.answer-key.json`) — what the extraction *should*
  find in a screenplay, used to score AI runs. It is exported from the
  operator's review (§7.2), never written by hand.

### 7.1 Sample screenplays: two kinds, two purposes

**Parser samples — synthetic, committed, authored in Plan 002.** Their job is
syntax coverage, not story, so small and deliberately weird is the virtue.
Three original short Fountain screenplays (6–15 pages) plus the Phase 0
`camp-signal`, each with a byte-exact `.parse.json` answer key:

1. **Structure piece** — `INT./EXT.`, `EST.`, forced headings, `#12A#` scene
   numbers, `CONTINUOUS`/`LATER`, a `#`/`##` section structure (sequences), a
   preamble (`FADE IN:` + action) before the first heading.
2. **Dialogue piece** — `(V.O.)`, `(O.S.)`, `(CONT'D)`, forced `@` cues, a
   dual-dialogue block, parentheticals, lyrics, centered text, transitions.
3. **Messy piece** — notes `[[ ]]`, boneyard `/* */`, an unterminated
   boneyard, CRLF and BOM, smart quotes, a heading with no time of day, a
   lowercase heading, `OMITTED`, and a file whose body has no heading at all.
   Its FDX twin `messy-piece.fdx` is hand-authored minimal valid FDX (never
   exported from Final Draft) and must parse to the same scenes and cues.

Plan 008 adds a fourth artifact of the same kind: `structure-piece.pdf`,
**generated from `structure-piece.fountain`** by a committed generator that
lays the text out at standard screenplay margins. It is therefore original
synthetic work like everything else here, it exercises the §5.4a margin
classifier end to end, and it carries the same twin assertion as the FDX one —
same scene count, ordinals, headings, `intExt`, `timeOfDay`, `sceneNumber`, and
per-scene normalized cue sets (spans differ, since the PDF's `source_text` is a
rendering). An operator's own screenplay PDF is never committed (§7.1's
all-or-nothing rule applies unchanged).

These carry an expected-parse file each but **no entity answer key**, and need
no planted story ambiguity — the
parser is deterministic, so their answer keys are mechanical and reviewable by
inspection.

**Extraction samples — the operator's own screenplays.** Extraction quality
is measured on real feature-length material, because that is where the
ambiguity is authentic and where reconcile is actually exercised (a short
sample runs in one chunk, which makes the fragmentation metric meaningless
by construction). The operator supplies:

- one **scored** feature, the evaluation screenplay; and
- one **acceptance** feature, used for the manual live run in Plan 007 and
  never scored.

Committing them is the operator's IP decision, and it is all-or-nothing per
screenplay: a `.parse.json` answer key embeds `sourceText`, so a committed answer key
publishes the script. If they stay private they live in a git-ignored
`screenplays-private/` directory and `filmcamp-eval` takes their path; CI then
covers the synthetic parser samples only, which is sufficient because the
parser answer keys are the deterministic half.

`ScreenplaySamples` (SwiftPM target in the FilmCore package, one Swift file
exposing `public enum ScreenplaySamples { static func url(named:) }` plus a
library product) carries the synthetic samples only, so FilmScript tests,
FilmEval, and the app's automation share one copy.

### 7.2 The answer key is derived from the operator's review, not hand-authored

Nobody writes an answer key by hand. The operator reviews an extraction run in
the app — accepting, rejecting, merging, correcting, and adding what the model
missed, which is the ordinary Plan 007 review flow — and
`filmcamp-eval save-answer-key <bundle> --out <answer-key.json>` exports that reviewed
state as the answer key. Every later run is scored against it automatically.

This works because the review records the signals in canonical state (§3.6).
The exporter is a query, not a judgment call, and it exports **only rows with
`reviewed_at` set** — a fact nobody looked at is not ground truth, so an
untouched parser-only project exports an *empty* key and the scorer refuses to
score against a key with no required entries rather than reporting a flattering
recall of 1.0. `origin` has three values, derived from `created_source` (the
source at creation, never overwritten — §4.3), the creating `job_id`, and
`review_state`; the current `source` is deliberately **not** used, because a
human edit converts it to `human` (§3.6) and would mislabel a parser or model
find as a miss:

| origin | meaning | derived from |
|---|---|---|
| `confirmed` | the parser or the model found it and the operator vouched for it unchanged | `created_source IN (parser, ai)`, `source != human`, `review_state = accepted` |
| `corrected` | the parser or the model found it and the operator edited it — still a find | `created_source IN (parser, ai)`, `source = human` |
| `added` | the operator supplied it: **the model missed it**, the only true recall signal | `created_source = human` |

A **rejected** tombstone is a confirmed false positive; a **merge** is the
alias grouping reconcile should have produced. The derivation is applied in
two stages — first `review_state` (`rejected` → the `rejected` array,
`proposed` → excluded, `accepted` → continue), then `origin` from
`created_source`/`source` — so a human-edited row that was later rejected
exports only as a tombstone. Rejections stamp `reviewed_at` like any other
verdict (§3.5), which is what makes the `rejected` array non-empty. Alias and
appearance rows enter the key only when they themselves carry `reviewed_at`
(accepting an entity accepts its alias and appearance rows, §3.5, so this is
the normal case); an unreviewed AI-proposed alias is not ground truth and
must not drive matching.

```json
{
  "sample": "the-last-signal", "version": 2,
  "derivedFrom": {"bundleSHA256": "…", "runJobID": "…", "exportedAt": "2026-09-02T18:04:11.271Z",
                  "scriptSHA256": "…", "parserVersion": "1", "sceneCount": 112},
  "entities": [
    {"kind": "character", "name": "Sarah Morgan", "aliases": ["SARAH", "SARAH MORGAN", "SAZ"],
     "appearsIn": [1, 2, 5], "required": true, "origin": "confirmed"},
    {"kind": "prop", "name": "Red Notebook", "aliases": ["NOTEBOOK"],
     "appearsIn": [14, 22], "required": true, "origin": "added"}
  ],
  "rejected": [{"kind": "prop", "name": "Coffee Cup", "aliases": ["CUP"]}],
  "states": [{"entity": {"kind": "character", "name": "Sarah Morgan"}, "category": "injury",
              "startScene": 14, "endScene": null, "keywords": ["cut", "cheek"],
              "origin": "confirmed"}],
  "events": [{"scene": 14, "entity": {"kind": "character", "name": "Sarah Morgan"},
              "keywords": ["glass", "cut"], "origin": "corrected"}]
}
```

`required` is true for every exported entry — the operator confirmed,
corrected, or supplied each one. States and events reference an entity by
`{kind, name}`; a bare name is ambiguous because the same display name may
legally exist in two kinds.

Scorer (`FilmEval`), deterministic and unit-tested against hand-built
canonical states (it opens bundles through a **copy in a temp directory**,
since `ProjectBundle.open` migrates and checkpoints):

- **Entity matching**: kinds agree and any alias/name matches case-folded
  after cue normalization. Precision, recall, F1 per kind and overall;
  missing required entities are listed by name.
- **Unlisted is not wrong.** A canonical entity matching nothing in the
  answer key is **not** counted as a false positive; it is reported as
  `newUnreviewed` with its name and evidence. A better prompt that finds
  something real must not score as a regression — the list is a review queue
  for the next snapshot, not an error count.
- **Resurrected rejections**: an **AI-created** canonical entity matching a
  `rejected` entry is an unambiguous false positive and is counted and
  listed. This is the metric that catches a prompt change re-introducing
  noise the operator dismissed. Parser-created rows are excluded — a fresh
  import recreates every cue and heading deterministically, and an operator
  may legitimately have rejected one — and are reported separately as
  `parserResurrected`, which never gates.
- **Appearances**: per matched entity, Jaccard of scene-ordinal sets.
- **States/events**: matched by entity + category + overlapping scene range
  (states) or same scene (events) + ≥ 1 keyword in the description; P/R/F1.
- **Fragmentation**: canonical entities matching the same answer-key entry
  (should be 1), listed with the entry's `kind` — reconcile quality; reported `applicable` only when the run
  had ≥ 2 chunks. Because §3.5 now lets a run merge parser entities, this is
  the number that says whether "recurring characters normalize correctly" is
  met, so the extraction plan sets a threshold on it rather than only
  reporting it.
- **Anchor rate**: anchored evidence rows ÷ all AI evidence rows.

**Honest limits, stated in every report.** The answer key encodes the operator's
judgment at snapshot time, not ground truth: recall is measured against what
they have noticed so far, so a miss neither of them caught reads as success.
The report header therefore names the snapshot's `derivedFrom` and prints
"scored against reviewed judgment of <date>, not absolute truth". The answer key
is living: re-running `save-answer-key` after any later review pass raises `version`
and improves it, and the `newUnreviewed` list is the queue that drives the
next pass. Answer keys are committed under `docs/eval/answer-keys/<sample>.answer-key.json`
— they hold entity names, aliases, scene ordinals, and keywords the operator
approved, never screenplay text — so a private screenplay can stay private
while its answer key and its reports are versioned in the repo.

The scorer records a `notes` entry when the scored bundle's `scripts.sha256`
or `parser_version` differs from the key's `derivedFrom`, because every
ordinal in the key is parser-assigned.

Output: `EvalReport` JSON + a markdown table. `filmcamp-eval run` imports each
sample into a temporary bundle, runs the Plan 007 extraction through the real
harness, applies it, scores the result, and writes
`docs/eval/<date>-<git-sha>.md` (+ JSON). Reports are committed; when the
screenplay is private the report still commits (it contains counts and entity
names the operator approved, never script text — the exporter refuses to
write `sourceText` or evidence quotes into a report).

The baseline contains, per sample, one row at the default chunk budget and
one at a reduced budget yielding ≥ 4 chunks (`--chunk-budget`), so multi-chunk
reconcile is always scored. Policy: **score before shipping any prompt,
schema, or engine change**, and compare with the previous committed report in
the commit message. `scripts/verify.sh` fails when the committed **evaluation
inputs** differ from those recorded in the newest `docs/eval/` report ("inputs
changed since last scored run") — the roadmap's "score before shipping" rule as
a gate that needs no model in CI. The inputs are an explicit manifest, not a
schema glob, because anything that moves a score must trip it: the two
extraction schemas and their prompts, the chunker, the semantic validators, the
reconcile input builder, the apply/matching sources, a `ScorerSemantics.version`
constant, and the run settings recorded in the report (chunk budget,
concurrency, and the chunk and reconcile model/effort). Unrelated schemas, such
as the harness probe, are excluded.

---

## 8. Extraction contract (Plan 007)

### 8.1 Pipeline

```text
chunk      deterministic: consecutive scenes grouped by token budget
extract    one Codex job per chunk, schema extract-chunk-v1, concurrent
reconcile  one Codex job over all chunk outputs + canonical entities/aliases,
           schema reconcile-entities-v1
apply      FilmCore, one transaction, actor .ai(jobID): alias-match, lock and
           protection rules, evidence anchoring, provenance, journal
review     UI: proposed facts surfaced for accept / edit / merge / reject
```

The parent run job orchestrates; the reconcile job and apply are skipped only
if every chunk failed. Partial chunk failures are surfaced; the run completes
with an apply report listing chunks that failed and scenes not covered. The
primary action is **Analyze Screenplay** (the engine is named in the
disclosure, not the button).

> **Amended 2026-08-21 (owner; Phase 2 §3.6, §14.9).** Analysis runs **once
> per screenplay**: after a completed run the action is gone, not relabelled.
> This paragraph previously specified a **Re-analyze Screenplay…** title and a
> confirm sheet promising how many unreviewed AI facts would be replaced and
> how many accepted/locked facts kept; both are removed. FilmCore refuses a
> second applied `extractScreenplay` run for a script
> (`.extractionAlreadyApplied`), so the rule does not depend on the UI. A
> failed or cancelled attempt applied nothing and may retry; a paused run
> resumes as itself; reverting does not reopen eligibility; a new run means a
> new project. §5.5's Replace installs a new screenplay, which gets its own
> one run — the gate is script-scoped for exactly that reason.

### 8.2 Chunking

Deterministic from the parsed scene list: fill chunks in scene order until
adding the next scene would exceed the chunk budget (`FilmBrain
ExtractionChunker`). The budget is expressed in UTF-16 units approximating
tokens at ~4 units per token; **default ~8,000 tokens of screenplay text per
chunk** (≈ 8–12 scenes of a typical feature), minimum one scene per chunk, an
oversized single scene is its own chunk. A 30k-word feature therefore runs in
roughly 5–8 chunk calls plus one reconcile call.

Why the budget is large: research (§12.2) shows the binding constraint for a
ChatGPT-plan account is the **message quota per 5-hour window**, not tokens.
Per-scene calls (≈ 90 per feature) could exhaust a Plus user's window on one
screenplay; ≈ 10 calls is safe on any plan. The pre-run disclosure states the
number of Codex requests the run will make.

Each chunk carries `(sceneID, ordinal)` pairs, headings, spans, and the
parser's cue and heading facts as hints so the model confirms/extends rather
than rediscovers. Chunk inputs are written to
`cache/jobs/<run>/<chunk-job>/input.txt`. **Reuse key** (stored in
`jobs.input_sha256`) = SHA-256 over `{promptHash, schemaVersion,
validatorVersion, engine, engineVersion, requestedModel ?? "<account-default>",
reasoningEffort, chunkText}` (`effective_model` is **not** part of the key:
Codex 0.146–0.147 never reports one, so a key that required it could never
match). On resume/rerun, a matching completed chunk is
**not** re-run: a new child job row is created for the current run through
`createJob` and walked `queued → discoveringHarness → running → validating →
completed` with `progress_stage = Job.reusedProgressStage` and no process
launched (there is no create-in-`completed` seam), the prior result file is copied
to its own result path and **re-validated**, and usage is recorded as zero so
aggregation does not double-count; a missing or invalid file falls back to
running the chunk. Reconcile is never reused — its input includes the
canonical entity set, which changes with every review — so a fully reused
re-run still costs exactly one request.

### 8.3 Schemas (checked in, Structured-Outputs-safe as in Phase 0)

`extract-chunk-v1.schema.json` — per scene in the chunk: `sceneId` (echoed),
`sceneOrdinal`,
`synopsis` (`text`, `evidenceQuote`, `confidence`), `entities[]` (`kind`,
`name`, `aliasesInScene[]`, `role`, `description`, `evidenceQuote`,
`confidence`), `states[]` (`entityName`, `category`, `description`,
`evidenceQuote`, `confidence`), `events[]` (`entityName?`, `description`,
`evidenceQuote`, `confidence`), `relationships[]` (`fromEntityName`,
`toEntityName`, `kind` from the §4.3 enum, `description`, `evidenceQuote`,
`confidence`). Names are the model’s surface forms; the app maps them. Every
`entityName` in `states[]`, `events[]`, and `relationships[]` must resolve to
an entry of that scene's `entities[]`, from which its `kind` is taken — the
semantic validator rejects a dangling or cross-kind name.

`reconcile-entities-v1.schema.json` — input is a compact list of chunk-level
entities plus canonical entities with aliases and `locked`/`protected` flags;
output: `canonicalEntities[]` (`existingId?`, `kind`, `name`, `aliases[]`,
`description`, `mergedFrom[]` chunk names), `proposedMerges[]` of existing
entities. **Merge channel**: FilmBrain's proposal builder forwards each
`canonicalEntities[]` entry as a merge *candidate* (its `existingId`, `name`,
`aliases[]`, kind); **FilmCore's apply** resolves the candidate by normalized
alias match within kind (§3.5 — matching never happens in FilmBrain) and, when
it names more than one existing entity, applies it as one `perform(.mergeEntities)`
per source under `.ai(runJobID)` **only when every participant is unprotected,
no source or source alias carries any lock, and the target carries no
whole-record lock** (Plan 005's `mergeEntities` preconditions; parser↔parser
and ai→parser merges are allowed, §3.5); the target is the most protected
participant, ties by earliest `created_at`, then by `id`. Otherwise the
candidate is demoted to a suggestion. `proposedMerges[]` is advisory only:
surfaced in review with one-click Merge, never auto-applied; `ApplyReport.
mergesSuggested` counts both demoted candidates and advisory suggestions.

Both keep the Phase 0 rules: `additionalProperties: false`, typed `const`
schema versions, no `maxLength` (lengths in semantic validation), bounded
arrays. Both are probed by the opt-in schema compatibility test before use.

### 8.4 Concurrency, caching, cost, and failure classes

- **Warm-up then fan-out.** The first chunk runs alone; when it completes,
  remaining chunks run with bounded concurrency (default 3; Debug launch
  argument to override). Reason: prompt caching keys on an identical prefix,
  and Codex's per-process model-catalog cache is written non-atomically —
  a cold fan-out pays full price N times and races the cache write (§12.2).
- **One workspace per run.** All child jobs use `-C
  <bundle>/cache/jobs/<run-id>/workspace` (empty), not per-child dirs, because
  Codex's environment context includes the cwd and a differing cwd breaks the
  cached prefix. Result/log/input paths stay per child. A result path is
  never reused: Codex does not clear a stale `--output-last-message` file on
  failure.
- **Byte-identical prefix.** The instruction text and schema come first and
  never vary within a run; the chunk text is last.
- **Overhead reduction (supported config overrides, applied per process, no
  edit to the user's `config.toml`)**: `-c skills.include_instructions=false`,
  `-c include_apps_instructions=false`,
  `-c include_permissions_instructions=false`,
  `-c include_collaboration_mode_instructions=false`,
  `-c web_search="disabled"`, `-c mcp_servers={}`, and
  `-c current_time_reminder=false` (defends prompt caching). Values are TOML;
  strings are quoted exactly as shown. Verified present
  on Codex CLI 0.147.0 (§12.2); unknown keys are ignored by older versions,
  so they are safe to pass. Plan 007 measures the effect once in the live gate
  and records the input-token floor. `include_environment_context=false` is
  **not** used (may change model behavior). The invocation also passes
  `--ignore-user-config` and `-c project_doc_max_bytes=0` (Phase 0), so the
  project `AGENTS.md` is not read; whether the global `~/.codex/AGENTS.md`
  still loads is measured in Plan 007's preflight and recorded, and the §9
  disclosure keeps its hedged “may include” wording until that is known.
- **Model and effort.** Default remains the account's Codex default
  (`requested_model = null`). Because model choice changes the message
  allowance dramatically on ChatGPT plans, the app exposes an *Advanced*
  preference (app-level, not per project): model id and reasoning effort for
  chunk workers and for reconcile, passed as `-m` / `-c
  model_reasoning_effort="…"`, recorded in `jobs.requested_model`. **The
  parent run captures these values at start**; resume and retries use the
  captured values, and a preference edited mid-run has no effect (the pane
  says so). Model ids are runtime values typed by the user; the app validates
  them only by observing the job outcome (`unknownModel` above) and never
  hard-codes a catalog.
- **Failure classes are an adapter concern.** Codex retries transport/stream
  errors internally but treats HTTP 429 and `usage_limit_reached` as terminal
  (`turn.failed`, exit 1). `HarnessEvent.failed` carries a normalized
  `HarnessFailureKind` — `.usageLimit(resetHint:)`, `.retryable`,
  `.unknownModel`, `.fatal` — produced **inside `CodexHarnessAdapter`** from
  the terminal message (string matching on `usage_limit` / `rate limit` /
  `429` / model-not-found wording lives there, per the roadmap's “the adapter
  owns communication details”). Adapters also report `recommendedConcurrency`
  and `prefersWarmUp` capabilities. The run coordinator only consumes the
  kinds: `usageLimit` → **pause the run** (`paused` state), keep completed
  chunks, show the reset hint, offer Resume; `retryable` → retry that chunk
  once after a backoff; `unknownModel` → fail the run with “Codex rejected
  model ‘x’” and an Open Advanced Settings button; `fatal` → mark the chunk
  failed and continue. The run finishes with an apply report listing
  uncovered scenes.
- **Cancellation.** Codex handles only SIGINT (graceful `turn/interrupt`, no
  JSONL event, exit 1); SIGTERM kills instantly. Plan 007 changes the process
  runner's cancellation to interrupt → wait 2 s → terminate → wait 2 s → kill,
  and sends every signal to the child's **process group** (`setpgid(pid, pid)`
  at launch, then `killpg`) — an npm-installed Codex is a `/usr/bin/env node`
  launcher whose real binary is a child, so signalling the launcher alone can
  orphan it. Detach readability handlers, close pipes, and drain output before
  signalling. Pattern from `swift-acp`'s `ProcessManager` (REFERENCE_PROJECTS
  ▸ Phase 1 specifics).
  Run cancel cancels all children; already-validated chunk results are kept
  for resume.
- **Timeouts.** Codex has no wall-clock turn timeout; the app's per-process
  10-minute timeout stays.
- **Dedicated `CODEX_HOME` (not adopted).** Pointing the app at its own
  `CODEX_HOME` would remove the skills/plugins overhead, the global `AGENTS.md`
  ambient context, and the shared-cache contention in one move — but Codex
  keeps `auth.json` in `CODEX_HOME`, so it would force a second login into an
  app-owned directory. That conflicts with “the app never holds those
  credentials” as currently written and Plan 001's rule that the app never
  performs login. Recorded in Roadmap deltas as a product decision; Phase 1
  proceeds without it.

### 8.5 Apply rules (FilmCore, actor `.ai(jobID)`)

1. Verify `scripts.sha256 == run.script_sha256`; else throw
   `.scriptChangedDuringRun` (nothing applied).
2. Map every proposed entity to an existing entity by `name_normalized` /
   alias match within kind (a function — §3.5); a match to a `rejected` row is
   `skippedRejected`; else create it with `source = ai`. The transaction
   activates every validated row created by the run before completion, leaving
   `reviewed_at` NULL.
3. Never modify or delete protected rows (§3.6) or locked fields (§3.7);
   parser-owned fields are never changed; empty parser descriptions may be
   filled. Every skipped change is recorded in `jobs.apply_report`.
4. Replace only rows this or an earlier AI run created that remain
   `ai/proposed`; leave everything else. Aliases are append-only for AI.
4a. Stale proposals: an `ai/proposed` row created by an earlier run that
   this run does not re-propose (no entity, state, event, relationship, or
   appearance in the proposal maps to it) is **removed** (entities and their
   dependents journaled with full snapshots) and counted as `replaced`.

   > **Unreachable since 2026-08-21's one-run latch** (Phase 2 §3.6): this
   > rule only removes an *earlier applied run's* proposals, and there is no
   > longer a second run to do the removing. It stays as defensive apply
   > behavior — like §8.4's match enumeration — and nothing may depend on it
   > firing. Its confirm-sheet promise ("Up to X unreviewed AI facts will be
   > replaced") is removed with the Re-analyze action above.
5. **Each proposed change runs inside its own `SAVEPOINT`**; `.locked`,
   `.protectedFact`, `.parserOwned`, `.aliasConflict`, and `.rejected` roll
   back to the savepoint and are recorded; any other error aborts the whole
   apply. Merges per §8.3's merge channel run as one change each.
6. Anchor evidence quotes to spans (§3.3); store confidence per §3.6.
7. Journal one row per underlying operation tagged with the run's `job_id`,
   then the `applyExtractionRun` summary row (§3.8).
8. Commit; transition the run job to `completed` in the same transaction;
   clear the window's undo stack.

`ApplyReport` fields: `applied`, `replaced`, `mergesApplied`,
`mergesSuggested`, `skippedLocked`, `skippedProtected`, `skippedParserOwned`,
`skippedRejected`, `aliasConflicts`, `unanchoredEvidence`, `chunksFailed`,
`uncoveredSceneOrdinals`, `durationMs`, and `settings` (the
`ExtractionSettings` captured at run start, §8.4). Both `ApplyReport` and
`ExtractionSettings` (chunk/reconcile model and effort, chunk budget,
concurrency) are **FilmCore** types in `Domain/ApplyReport.swift` (Plan 005),
because FilmCore may not import FilmBrain. `jobs.apply_report` holds exactly
this one `Codable` value; before apply it holds the same type with `settings`
filled and every counter zero, written through `JobManaging.setApplyReport(
jobID:_:)` (parent jobs only, refused after `completed`). The parent row also
stores the aggregated child usage, written by apply in the same transaction;
`runs()` reports that stored aggregate and never re-sums children.

### 8.6 Correction UI

Run state is a toolbar item present in every section (progress + stage; click
opens the run card popover with per-chunk rows, usage, Cancel / Pause /
Resume); the full card and apply report live in the Jobs section. Validated
facts appear directly in the ordinary entity lists. Users edit, merge, reject,
restore, or add missing entities there; Rejected and Unanchored filters keep
the exception paths reachable. Advisory merge suggestions retain one-click
Merge. “Revert last run” lives in Jobs with §3.8's selective semantics. There
is no separate review queue or review write path.

---

## 9. Privacy and disclosure

Phase 1 sends the **whole screenplay**, chunk by chunk, to Codex — not a small
sample. Two pieces of copy, verbatim:

**First run per project** (acknowledgement stored in
`projects.disclosure_acknowledged_at`, so it travels with the bundle):

> Analyzing sends the full text of this screenplay to Codex through your own
> Codex account. Codex may include your global Codex instructions and the
> descriptions of your installed Codex skills or plugins in the same request;
> AI Film Camp does not read or store those. AI Film Camp keeps copies of the
> screenplay chunks it sent inside this project (cache/jobs) so an interrupted
> run can resume — you can clear them from the Jobs section. Nothing is sent
> until you choose Continue.

**Every run** (compact confirm sheet): “About N Codex requests” where N =
(chunks whose §8.2 reuse key matches no completed attempt) + 1 for reconcile,
computed from the same `ExtractionChunker` call that plans the run plus a
`jobHistory()` reuse-key scan (“retries may add a few”) — a first run says
chunks + 1, a fully reused re-run says 1 — plus, after a completed run exists,
“Up to X unreviewed AI facts will be replaced; Y accepted and Z locked facts
will be kept” (§8.5 4a). Requests, not tokens, are shown — quota is spent in
requests. Sample screenplays used by tests remain synthetic.

---

## 10. Testing strategy (all plans)

- Parser answer key files (byte-identical `ScreenplayDocument` JSON) for all
  samples, plus adversarial small cases (headings without TOD, lowercase
  headings, `INT./EXT.`, forced headings, dual dialogue, notes/boneyard,
  CRLF, BOM, smart quotes, no headings at all, a preamble before the first
  heading, nested sections).
- Migration test: checked-in v1 sample bundle (kept out of `.gitignore`'s
  `*.aifilm/` rule by an explicit negation, copied as a test resource) → open
  → v2 → verify entities, aliases, rebuilt scenes, **and unchanged row counts
  for scripts/jobs/assets**; `PRAGMA foreign_key_check` clean.
- Editing operations: every op has apply + inverse round-trip tests (table
  snapshots), lock/protection/rejection matrix (actor × lock kind × op),
  merge collision survivor rule, merge/split round-trip with original ids,
  journal payload sufficiency (restore after delete), an orphan-evidence
  query after every merge/split/delete test.
- Extraction: recorded multi-chunk samples through the generic runner;
  apply-rule tests for alias mapping, protection, locks, rejected tombstones,
  savepoint rollback of a partial change, evidence anchoring (found /
  normalized / multiple occurrences → first / outside scene → unanchored),
  partial chunk failure, pause/resume, resume reuse and re-validation,
  script-changed guard.
- Scorer unit tests against hand-built canonical states with known scores,
  including anchor rate, multi-chunk fragmentation, `newUnreviewed` never
  counting against precision, and `resurrectedRejected` being counted.
- Answer-key-exporter tests: accepted and human rows become required answer key
  entries with the right `origin`, rejected rows become the `rejected` array,
  `proposed` rows are excluded, and no screenplay text or evidence quote can
  reach an answer key or a report.
- Window-model unit tests over a temporary bundle: rename→undo→redo→undo,
  batch delete is one undo step, failing apply clears the stack, `changes()`
  updates `pendingReviewCount`, AI apply clears undo, selection survives
  reload.
- UI tests (persistence disabled, window-scoped queries): import → scene
  list; rename/merge/undo **via the Edit menu**; recorded extraction → review
  → accept; lock prevents AI change (recorded run with a conflicting
  proposal); recorded hold/fail stages for run-card assertions.
- Live gates remain opt-in (`FILMCAMP_RUN_LIVE_CODEX=1`) with per-run operator
  approval, exactly as Phase 0.

---

## 11. Non-goals for Phase 1

Asset requirements/manifest, CharacterLook grouping, readiness, prompt
generation, MCP/tools, Claude/Grok adapters, OCR of scanned PDFs, screenplay editing,
automated re-analysis or change propagation, re-import of a revised draft
with preservation of edits, re-parse of existing projects (a revised draft is
a new project in Phase 1), multi-script projects,
cloud, App Sandbox, notarization.

---

## 12. Research inputs

Recorded 2026-08-18. Everything below was verified against source or the
installed CLI unless marked *unverified*.

### 12.1 Screenplay parsing (§3.2, §5)

- **FDX format** (no public XSD/DTD; reverse-engineered from 13 real files
  spanning `FinalDraft@Version` 1–6 from Final Draft 10–13, Fade In,
  screenplain, WriterDuet, and from ten open importers — Beat `FDXImport.m`,
  Scrite `finaldraftimporter.cpp`, jumpcut `fdx.rs`, rsdoiel/fdx, afterwriting,
  storyboarder, screenplain, screenplay-tools, fdx-mcp-server, hekaya):
  scene number is `Paragraph@Number` (string, absent when numbering is off);
  `SceneProperties` carries `Title/Length/Page/Color`, never the number;
  `Paragraph@Type` optional; 20% of paragraphs in a real 940-paragraph script
  had multiple `Text` runs whose boundary whitespace is load-bearing;
  `Paragraph` nests inside `DualDialogue`, `SceneProperties/Summary`,
  `SceneArcBeats/CharacterArcBeat`, `ScriptNote` (descendant selectors inflate
  paragraph counts by 4–98 in the corpus and inject synopsis prose);
  `TitlePage` has its own `Content` with no semantic fields; `Text@Style`
  tokens are `+`-joined; colors are 12-digit 16-bit hex; `DynamicLabel` has no
  text; tabs occur, NBSP and CDATA did not occur in the corpus; the macOS UTI
  is `com.finaldraft.fdx`. Several published parsers get these wrong (first
  `Text` run only; joining runs with a space; reading the number off
  `SceneProperties`; trimming per chunk) — do not model on them.
- **Sample licensing**: no clean public-domain or explicitly CC-licensed
  screenplay in Fountain/FDX form was found that could be bundled safely; the
  two canonical Fountain samples are unusable — “Big Fish” carries an active
  studio copyright notice in its own title page and “Brick & Steel” has no
  license anywhere. The one CC0 Fountain repo found is a small personal one
  with no provenance. Best-run open parsers (wildwinter/fountain-tools,
  dmongrel/fdx-mcp-server) ship self-authored synthetic samples. Hence §7.1:
  original synthetic screenplays only.
- **Swift Fountain parsers** (surveyed 2026-08-18 via GitHub API):
  nyousefi/Fountain — MIT, Objective-C, last commit 2015, no SwiftPM, no
  offsets; wildwinter/screenplay-tools (formerly fountain-tools) — MIT,
  maintained, **no Swift implementation**, elements are type+text only;
  lmparppei/Beat — GPL-3.0-or-later, app-embedded (disqualified);
  QiyangStudio/SwiftFountain — MIT, SwiftPM, tools 6.0, Foundation-only,
  UTF-16 `SourceRange` on every line, normalizes CRLF before computing
  offsets, but 3 commits / 1 author / 2 stars, line-level only (no block
  grouping), scoped to editor highlighting; SwiftEscribo — MIT but macOS 26+
  and a span tiler; several others unlicensed or apps. **Conclusion: build**
  (§3.2). SwiftFountain's `SourceRange` + normalize-then-offset shape may be
  consulted as a reference under the `docs/REFERENCE_PROJECTS.md` rules
  (review license, retain the MIT notice if any code is adapted, record it in
  the implementation notes); it is not a dependency. Do **not** adopt
  nyousefi's bundled test corpus (“Big Fish”, “Brick & Steel”) as samples —
  see the licensing note above.

### 12.2 Codex CLI behavior for batch extraction (§8)

Verified against `openai/codex` at tag `rust-v0.147.0` and the installed
`codex-cli 0.147.0` (the machine updated past 0.146.0 during planning; the
minimum supported version stays 0.146.0 and is capability-probed).

- **Concurrency**: no documented per-account concurrency cap; limits are
  usage windows (`RateLimitWindow`, 5-hour rolling; e.g. Plus ≈ 10–100 messages
  for the default model, more for lighter models). `codex exec --json` emits
  no rate-limit event. Shared-state hazards under `CODEX_HOME`:
  `models_cache.json` is written with a plain non-atomic `fs::write`
  (`models-manager/src/cache.rs:227`); the stderr `failed to load models
  cache: missing field base_instructions` seen in Phase 0 is version skew
  between CLI versions sharing the cache (non-fatal, costs a catalog fetch per
  run). Thread writer locks are per-thread `flock`; `--ephemeral` skips them.
- **Config keys verified on 0.147.0** (`config/mod.rs`, `skills_config.rs`,
  `config.schema.json`): `-m/--model`, `model_reasoning_effort` (free string;
  catalog-advertised values `low|medium|high|xhigh|max|ultra`),
  `model_verbosity`, `web_search` (`disabled|cached|indexed|live`, default
  `cached`), `mcp_servers`, `skills.include_instructions` (default true),
  `skills.bundled.enabled`, `include_apps_instructions`,
  `include_permissions_instructions`,
  `include_collaboration_mode_instructions`, `include_environment_context`,
  `current_time_reminder` (feature, default off), `--disable <feature>`,
  `service_tier`. **Not present**: `model_max_output_tokens`,
  `skills.max_context_tokens`, `disable_response_storage`.
- **Where Phase 0's ~17k base tokens go** (from the models cache and
  source constants): instructions template ≈ 4.4k; skills catalog capped at 2%
  of context window (`SKILL_METADATA_CONTEXT_WINDOW_PERCENT = 2`,
  `ext/skills/src/render.rs:20`) ≈ 5.4k at 272k — Phase 0's “Skill
  descriptions were shortened” item shows the cap was hit; remainder ≈ 6–7k of
  tool schemas and apps/permissions/collaboration/environment blocks.
  Estimated floor with the §8.4 overrides: **~6–8k** — *unverified in
  combination*; Plan 007 measures it (`codex debug prompt-input` renders the
  model-visible prompt without a turn or quota, though without
  `--ephemeral`/`--ignore-user-config`).
- **Models**: catalog is server-driven; ids observed on this account
  included `gpt-5.6-sol` (default), `gpt-5.6-terra`, `gpt-5.6-luna`,
  `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.3-codex-spark`. Context window
  per the catalog: 272k. Pin nothing.
- **Output**: `--output-last-message` writes the final agent message
  verbatim with no parse, validation, or size cap
  (`exec/src/event_processor.rs:31-48`); written only on
  `TurnStatus::Completed`; **not** written on `turn.failed`/interrupt, and a
  stale prior file is not cleared. A stream that ends without
  `TurnCompleted` yields exit 0 with no file. Truncated structured output is
  written as-is with exit 0. Phase 0's rules (“zero exit without a valid file
  is failure; validate independently”) cover all three.
- **Schema wire shape**: `text.format = { type: json_schema, strict: true,
  name: codex_output_schema, schema }` (`codex-api/src/common.rs:361-379`) —
  OpenAI strict-mode rules apply, as Phase 0 found.
- **Input**: no stdin byte cap (`read_to_end`); UTF-8 BOM stripped, UTF-16
  by BOM decoded; `-` forces stdin-only (root command only — `resume`
  ignores piped stdin when a prompt is given).
- **Timeouts/retries**: no wall-clock turn timeout in the exec crate;
  provider defaults `stream_idle_timeout_ms = 300000`, `stream_max_retries =
  5`, `request_max_retries = 4`, `retry_429: false`; a plain 429 or
  `usage_limit_reached` is non-retryable → `turn.failed` → exit 1
  (`codex-api/src/api_bridge.rs:94-129`, `protocol/src/error.rs:362-401`).
- **Signals**: only `ctrl_c()` (SIGINT) is handled (`exec/src/lib.rs:850-856`)
  → `turn/interrupt` → `TurnStatus::Interrupted` → no JSONL event, exit 1. No
  SIGTERM handler; SIGTERM kills immediately.
- **Sessions**: `--json`, `--output-schema`, `--output-last-message`,
  `--ephemeral` are global and work with `exec resume`; ephemeral sessions
  cannot be resumed; a failed resume lookup silently starts a new thread;
  HTTP transport replays the full conversation each turn (no
  `previous_response_id`); prompt cache key = session id but caching itself
  is prefix-based, so N ephemeral processes with an identical prefix cache as
  well as N turns in one thread. Conclusion: independent ephemeral processes
  per chunk (as designed) are cheaper past a few chunks and more
  deterministic.
- **`--json` item types** (`exec/src/exec_events.rs`): `agent_message`,
  `reasoning`, `command_execution`, `file_change`, `mcp_tool_call`,
  `collab_tool_call`, `web_search`, `todo_list`, `error`; `thread.started`
  carries only `thread_id`. Confirms Phase 0's terminal-event rules.

### 12.3 Phase 0 follow-ups discovered by this research

Small, and folded into Plan 007 (which touches the runner anyway):

1. `FoundationProcessRunner` cancellation order becomes interrupt → terminate
   → kill (currently terminate → interrupt).
2. The adapter's launch environment gains the §8.4 config overrides through
   `CodexInvocationBuilder` (still one builder for probes and runs).
3. Never reuse a job's result path across attempts (already true; now stated).

---

## 13. Roadmap deltas (accepted by the product owner, 2026-08-18)

1. Provenance `source` gains `parser` alongside `ai | human` (roadmap lists
   only the latter two). Parser facts are neither AI nor human, and are
   authoritative for parser-owned fields (§3.6).
2. `CharacterLook` and `LocationState` as **production groupings** are
   deferred to Phase 2 (asset manifest, “usage-derived variants”); Phase 1
   represents the underlying screenplay facts as `entity_states` for
   characters and locations.
3. `Prop`, `Vehicle`, `Creature`, `Object` are kinds of one `entities` table
   rather than separate tables (storage decision).
4. `Relationship` is represented (`entity_relationships`) and populated by
   extraction with a small kind vocabulary; add/remove editing exists, UI is
   list-only.
5. Re-import: **replace** (wipe) only while no protected facts exist;
   otherwise a revised draft is a new project (Duplicate Project… as the
   shortcut). Re-import with preservation and re-parse are out of scope for
   Phase 1 (§14.3); automated re-analysis/change propagation stays Phase 6.
6. “Every extracted fact carries evidence spans” is implemented as “every AI
   fact carries an evidence quote; spans are anchored deterministically; an
   unanchorable quote is kept as unanchored evidence, measured, and surfaced”
   (§3.3) — a refinement, listed so it is not silent.
7. Locks also guard the human against fat-finger edits (unlock first) — the
   roadmap frames locks as protection from AI only.
8. Deleting an AI-proposed fact is a `rejected` tombstone rather than a hard
   delete, so it does not resurrect on the next run (§3.6).
8a. The roadmap's “3–5 sample screenplays with answer keys in the
   repository” becomes: synthetic samples carry deterministic **parser**
   answer keys only, and the **entity** answer key is derived from the operator's
   review of their own feature screenplay (§7.2). The roadmap's intent —
   “measured against them, not eyeballed… score before shipping any prompt,
   schema, or engine change” — is preserved and enforced by
   `scripts/eval-gate.sh`; what changes is who writes the key and that the
   material is real rather than synthetic.
9. **Dedicated `CODEX_HOME` for the app** (§8.4): would remove ambient
   `AGENTS.md`/skills context and shared-cache contention, but requires a
   second Codex login into an app-owned directory. Not adopted in Phase 1;
   needs a product decision on compatibility with “the app never holds those
   credentials.”
10. Phase 1 raises no minimum Codex version (0.146.0 stays); overhead
    overrides verified on 0.147.0 are passed unconditionally because unknown
    keys are ignored.
11. **PDF import is pulled into Phase 1** (Plan 008), reversing §11's
    deferral on 2026-08-20. This restores rather than extends the roadmap:
    `docs/ROADMAP.md` sequences PDF "after the structured formats work well"
    and `docs/OVERVIEW.md` lists it as supported. Accepted consequences:
    `FilmScript` links the PDFKit system framework (§3.2a), element
    classification is a margin heuristic rather than a declared structure, a
    PDF with no text layer is refused rather than OCR'd, and the bundle schema
    goes to 3 to widen one `CHECK` (§4.2a).

---

## 14. Decisions (accepted by the product owner, 2026-08-18)

These were open questions; the recommendations below were accepted and are
now normative for Plans 002–007.

1. **Phase 2 consumes unaccepted (`proposed`) facts.** Manifest inference and
   every later consumer read all non-`rejected` facts. A requirement or
   downstream object derived from a still-`proposed` fact carries a visible
   “based on unreviewed AI facts” flag; accepting the fact clears it. Accept
   is a confidence-and-protection gesture (§3.6), not a gate. Plan 007's review
   copy says so (“Accepted facts are protected from future AI runs and stop
   showing as unreviewed downstream”). When Phase 2 is planned, `docs/ROADMAP.md`
   Phase 2 (“Requirement Review”) should restate this.
2. **Chunk concurrency default is 3, after one warm-up call** (§8.4).
   Rationale: research (§12.2) found no per-account concurrency cap, only
   shared usage windows; parallelism buys wall-clock, not quota; the warm-up
   populates the prompt cache and avoids racing Codex's non-atomic model-cache
   write. Debug launch argument overrides it; adapters may report
   `recommendedConcurrency` to lower it.
3. **Re-import with preservation is NOT in Phase 1** (reversed by the product
   owner on 2026-08-18 after initially being recommended). In Phase 1 the
   filmmaker corrects the breakdown inside the app; a materially revised draft
   is a new project (Duplicate Project… then Replace before editing is the
   supported shortcut). Re-parse of existing projects is likewise deferred.
   `scripts.parser_version` is still recorded so a later phase can offer it.
4. **No hand-authored answer keys; the answer key is exported from the operator's
   review** (§7.2, reversed from the original recommendation on 2026-08-18).
   The operator supplies their own feature screenplays (§7.1), reviews the
   first extraction run in the app as they would anyway, and
   `filmcamp-eval save-answer-key` turns that reviewed state into the answer key every
   later run is scored against. Synthetic samples remain only for
   deterministic parser answer keys, where no judgment is involved. Consequence
   accepted: recall is measured against the operator's reviewed judgment, not
   ground truth, and every report says so.
5. **Dedicated `CODEX_HOME` is not adopted in Phase 1** (delta 9). Phase 1
   uses the supported `-c` overrides (§8.4) to cut overhead and keeps the
   honest disclosure about ambient global instructions and installed skills.
   Revisit only if a later phase decides an app-owned `CODEX_HOME` written by
   the Codex CLI itself is compatible with “the app never holds those
   credentials.”
6. Undo is session-scoped (`UndoManager`); the journal already holds what a
   persisted undo would need.
7. The run confirmation shows **requests, not tokens** (§9).
8. **PDF import ships in Phase 1 as Plan 008** (product owner, 2026-08-20),
   built on PDFKit margin classification rather than a third-party library or
   OCR. Scanned PDFs are refused with a clear message; OCR is revisited only
   if real material demands it.
