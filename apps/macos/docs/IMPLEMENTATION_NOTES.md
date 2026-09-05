# Implementation notes

Prototype-mode note, 2026-09-03: entries below describe the project as it existed
when each phase was implemented. References to test suites, fixtures, evaluation
gates, and `scripts/verify.sh` are historical; those facilities are no longer part
of the current prototype. Current validation is `./scripts/build.sh` plus manual
product walkthroughs.

## Phase 0 harness reference audit — 2026-08-18

Before implementing FilmBrain's harness boundary, the executor inspected the
smallest seams required by Plan 001:

- RxCode `AgentBackend.swift`, `BackendCapability.swift`, and
  `MockAgentBackend.swift` for an actor-owned adapter lifecycle, explicit
  capabilities, normalized streams, cancellation, and a replayable test fake.
- AIWorkstation `AgentCLI.swift` for manual-override precedence, interactive
  login-shell discovery, `/dev/null` stdin, a bounded timeout, and known-path
  fallback for Finder-launched apps.

Upstream HEADs checked on 2026-08-18 were RxCode
`5e7c5ae7fdaa0eeb0caf06338485ecd88c8c2826` (Apache-2.0) and AIWorkstation
`98d1566d8901e36bd842753782c302493e44e916` (MIT). The local source snapshots
have no Git metadata. Film Camp reimplements the architectural lessons behind
FilmBrain-owned types; no source was copied or substantially adapted, so no
source-level attribution notice is required for this implementation.

Film Camp intentionally rejects the reference projects' coding-agent request
envelopes, provider-specific domain objects, terminal UI, IDE/Git features,
configuration mutation, and terminal-screen parsing. Phase 0 keeps one
structured `codex exec` transport behind the FilmBrain boundary.

## Phase 0 deterministic acceptance — 2026-08-18

The intent/reference drift check passed with all three hashes recorded in Plan
001. Xcode 26.6 and XcodeGen 2.46.0 were asserted locally. The following final
deterministic gates exited 0:

- `./scripts/verify.sh`
- `./scripts/finder-smoke.sh`
- XcodeGen regeneration followed by
  `git diff --exit-code -- "AI Film Camp.xcodeproj"`

The Finder smoke uses the Debug-only recorded adapter and `open -n -W` to
exercise LaunchServices. It creates and analyzes a project, closes it, confirms
that `project.db` has no open process handle, moves the package, reopens it, and
compares both the app-visible identity report and the canonical SQLite rows.
Its temporary package and reports are removed on exit.

## Phase 0 live acceptance — 2026-08-18

After explicit operator authorization, both account-backed gates exited 0:

- `FILMCAMP_RUN_LIVE_CODEX=1 swift test --package-path Packages/FilmBrain --filter CodexSchemaCompatibilityTests`
  passed 1 test in 10.534 seconds.
- `FILMCAMP_RUN_LIVE_CODEX=1 swift test --package-path Packages/FilmBrain --filter LiveCodexAnalyzeScreenplayTests`
  passed 1 test in 12.977 seconds.

The visible Finder acceptance then found and corrected two Phase 0 launch seams:
the generated app now exports `com.aifilmcamp.project` as an `.aifilm` package,
and Finder URLs received before the SwiftUI view appears are queued for delivery.
Opening the same normalized URL twice is idempotent, preventing overlapping
session loads. Focused app tests cover both pending URL delivery and duplicate
open requests.

The stable Debug app discovered authenticated Codex CLI 0.146.0 through the
Finder-safe login-shell path. Its live job used `--ask-for-approval never`,
`--sandbox read-only`, an empty per-job workspace, the checked-in output schema,
and the minimal credential-free environment. The job completed with 2 scenes,
2 characters, and 2 locations; known usage persisted as 17,096 input, 9,984
cached input, 0 cache-write input, 282 output, and 0 reasoning-output tokens.
No credential was read, copied, persisted, or logged.

With the app closed and no process holding `project.db`, Finder moved
`Phase Zero.aifilm` from `source` to `moved`. Double-clicking the moved package
launched the stable app and showed the same project name, script checksum, and
2/2/2 canonical counts. A deterministic SQLite snapshot covering schema
version, project, script, completed job history and usage, canonical IDs and
content, and all relationships had the same pre/post SHA-256:
`e921a9d52037e51ae6cb95b726c4e678ae21fd9ae33faaae678efe29bec69a91`.

## Phase 0 final verification resolution — 2026-08-18

The first post-live `./scripts/verify.sh` run passed FilmCore (11 tests),
FilmBrain (31 deterministic tests; 2 live tests correctly skipped), the Debug
build, and all 4 app unit tests. Both UI tests then failed because six restored
SwiftUI windows exposed six matching `createProjectButton` elements to
XCUITest. The reasonable scoped correction changed the Phase 0 scene from a
multi-instance `WindowGroup` to a single `Window`; on the required second full
verification run, XCUITest launched the application without presenting that
window, so both UI tests failed again. The unsuccessful scene change was
reverted.

The STOP was resumed with operator direction. The root cause was test-process
state isolation, not the `WindowGroup` or the accessibility selector: restored
SwiftUI windows correctly exposed one create button per window. XCUITest and
the recorded Finder smoke now launch with AppKit persistence disabled for those
automation processes only. Production retains its multi-instance `WindowGroup`
and normal window-restoration behavior.

After the correction, both UI tests passed and the final `./scripts/verify.sh`,
`./scripts/finder-smoke.sh`, XcodeGen regeneration/diff, intent/reference drift,
sensitive-data, generated-artifact, and whitespace checks all passed. Plan 001
is `DONE`.

## Plan 002 — Fountain/FDX parser and parser samples — 2026-08-19

`FilmScript` is a dependency-free library target inside the FilmCore package
(design §3.1): `FountainParser`, `HeadingParser`, `CueNormalizer`,
`DisplayCase`, `FDXReader`/`FDXRenderer`, and `ScreenplayImporter`, with
`FilmScriptVersion.parser = "1"`. Parsing is deterministic and every committed
sample and adversarial input is pinned by a byte-exact `.parse.json` answer
key regenerated only via `FILMCAMP_UPDATE_EXPECTED=1` (the writer then fails
by design so no CI run passes by rewriting the contract).

### Sample inventory (`ScreenplaySamples`, all original synthetic works)

| Sample | Size | Scenes | Sequences | Warnings | Syntax covered |
|---|---|---|---|---|---|
| `camp-signal.fountain` | 19 lines | 2 | 0 | — | title page, INT./EXT. + NIGHT, two cues (byte-identical Phase 0 copy) |
| `structure-piece.fountain` | 363 lines (~6.6 pp) | 15 (incl. scene 0 preamble) | 6 (depths 1–2) | `duplicateSceneNumber` | INT./EXT., EST., forced headings, `#12A#` incl. one duplicate, CONTINUOUS/LATER, nested sections with a mid-scene section, `=` synopsis, `===` page break, `FADE IN:` preamble |
| `dialogue-piece.fountain` | 336 lines (~6.1 pp) | 9 | 0 | — | (V.O.), (O.S.), (CONT'D), stacked extensions, forced `@` cues, dual dialogue, parentheticals, lyrics, centered text, forced and unforced transitions, title page |
| `messy-piece.fountain` | 323 lines (~7 pp) | 6 | 0 | `unterminatedBoneyard` | BOM + CRLF, smart quotes, notes, boneyard spanning a heading, unterminated boneyard as last construct, lowercase heading, no-time-of-day heading, OMITTED, McKAY cue |
| `messy-piece.fdx` | 180 lines | 6 | 0 | — | hand-authored minimal FDX twin; agrees with the Fountain original on scene count, ordinals, headings, intExt, timeOfDay, sceneNumber, and per-scene normalized cue sets |
| `messy-piece-no-headings.fountain` | 33 lines | 1 (`UNTITLED`) | 0 | `noSceneHeadings` | §5.3 fallback |

Plus 20 adversarial inputs under `Tests/FilmScriptTests/Samples/adversarial/`
(18 Fountain/text + `fdx-features.fdx` + `fdx-malformed.fdx`), each with a
reviewed key except the malformed file, which is asserted to throw.

### FDX rules §12.1 left unsettled, and how they were resolved

- **Title-page routing through the renderer.** `FDXRenderer.render` takes only
  `[FDXParagraph]` but must return `titlePageLines`; the reader tags
  `TitlePage/Content` paragraphs with an internal sentinel type that the
  renderer routes to `titlePageLines` instead of the body. Public API unchanged.
- **Blank-line rule vs dialogue adjacency.** Blank lines separate logical
  blocks, not paragraphs: a `Character` paragraph opens a dialogue run and each
  immediately following `Parenthetical`/`Dialogue` joins it with a single
  newline, so the rendered text re-parses with the same cue/dialogue structure.
  An orphan `Character` (no dialogue after it) is force-`@`-prefixed rather
  than silently degrading to action.
- **`Note` text containing `]]`** is rewritten to `] ]` so the rendered
  Fountain note cannot terminate early; deterministic and tested.
- **Type matching is case-insensitive**, which folds `End of Act`/`End Of Act`
  into one rule.
- **Empty paragraphs** are dropped by the renderer (not the reader), keeping
  the paragraph list a faithful record of the file.

### Contract refinements frozen by the answer keys

- Sequence assignment is local (§5.2): a scene's owner is the most recent
  section of the shallowest depth *among the sections that start at or before
  its heading*; appending a section later in the file can never change an
  earlier scene's `sequenceOrdinal`.
- Excision covers the whole document, title page included: a note or boneyard
  opened in the title-page block is never title-page content and is clipped to
  the scenes it overlaps like any other.
- The `UNTITLED` fallback scene always spans the whole body; an empty range is
  the consequence of an empty body, never a special case.
- A forced `@` cue whose normalized name is empty is action, not a cue.
- Elements that overlap no scene (a preamble that does not qualify as scene 0)
  belong to no scene; its sections still become sequences.

### Reference code

No code was consulted or adapted from QiyangStudio/SwiftFountain (MIT) or any
other external parser; the implementation was written from the design contract
and the plan alone. No license notice is therefore required
(`docs/REFERENCE_PROJECTS.md` rule 5).

## Plan 003 — Storage v2 and screenplay import — 2026-08-19

### Live gate (deferred)

`CodexSchemaCompatibilityTests` was re-pointed at `HarnessProbeSchema.url` with the
inline probe prompt (contract C) but was **not run live**. This plan was executed
autonomously, so no operator approval was requested immediately before the run and
`FILMCAMP_RUN_LIVE_CODEX` stayed unset; per the plan's live-gate policy the deferral is
recorded here and the plan still completes. Anyone with account access can close it with:

```bash
FILMCAMP_RUN_LIVE_CODEX=1 swift test --package-path Packages/FilmBrain \
  --filter CodexSchemaCompatibilityTests
```

### App target cleanup (Step 4)

Confined to "App target during this plan": `AnalysisJobView` and `AnalysisResultsView`
deleted, `AppModel` reduced to create / open / import / close / reveal plus Codex status,
`ProjectView`'s analysis section and disclosure alert removed, `AppModelTests` rewritten
around `importBundledSample()`, `Phase0FlowUITests.swift` reduced to `Phase0LaunchUITests`
(one launch test), and `scripts/finder-smoke.sh` retargeted at the v2 snapshot, `PRAGMA
user_version = 2`, zero jobs, and the parser counts. `AppModel.importBundledSample()`
imports the app's own bundled `Resources/Samples/camp-signal.fountain` through
`AppServices.sampleURL()` (`Bundle.main`) rather than `ScreenplaySamples`, because the app
target links only the `FilmCore` product and `project.yml` is Plan 004's to change; the two
files are byte-identical. `project.yml`, `AppServices.makeAdapter`, and the
`Resources/Samples` build phase are untouched.

## Plan 004 — App shell and automation — 2026-08-19

The Phase 0 demo window is replaced by the §3.11 shell: a Welcome `Window` plus
a suppressed project `WindowGroup(for: URL.self)` with one
`ProjectWindowModel`/`ProjectSession` per window, a forwarding
`ProjectWindowDelegate` bridge (window identifiers, tracked teardown for
`terminateLater`), nine read-only sections in four groups, the shared entity
list/inspector, the single import code path (⇧⌘I, toolbar button, drop
target → `importScreenplay(from:actor: .human)`), the import summary sheet,
the §5.5 Replace confirmation surfacing FilmCore's refusal verbatim, and the
one-way v1 upgrade modal over `ProjectBundle.inspect` with its upgrade sheet
over `ProjectSession.upgradeSummary`. Automation: `--film-camp-recorded` is a
value-less flag selecting the automation panel service and sequential test
destinations; the smoke asserts the v2 snapshot plus the screenplay asset row.

Automation lessons recorded:

- With `--film-camp-recorded` as a bare flag placed before
  `--film-camp-test-root`, AppKit's NSUserDefaults argument domain pairs the
  flag with the following argument and the app presents no window under
  XCUITest. The flag is passed last everywhere, with a comment.
- Under `.terminateLater`, `AppServices.terminateApplication()` must enter
  `NSApp.terminate` from `RunLoop.main.perform(inModes: [.common])`: calling it
  from a main-actor task or a `DispatchQueue.main.async` block leaves the
  nested termination run loop unable to drain the reply, hanging the app after
  the smoke report is written.
- The Phase 0 note about a `Window` scene not presenting under XCUITest is
  superseded: with persistence disabled for automation processes, the Welcome
  `Window` presents reliably.

Human checks: the Step 2 walk-through and the Step 4 feature-length import are
being performed by the operator immediately after this plan's automated gates;
results are appended below when reported. Per the plan's deferral policy the
plan is marked DONE with the automated gates green.

## Plan 008 — PDF screenplay import — 2026-08-20

PDF import was pulled into Phase 1 by product-owner decision, reversing the
design's §11 deferral. This restores the roadmap's own sequencing rather than
extending scope: `docs/ROADMAP.md` says "Add PDF after the structured formats
work well" and `docs/OVERVIEW.md` lists PDF as supported; the precondition was
met once Plans 002–004 shipped a deterministic parser with byte-exact keys.

A PDF becomes Fountain-style text and goes through the same `FountainParser`,
so scene segmentation, UTF-16 offsets, evidence anchoring, and every downstream
contract are untouched. `PDFReader` (PDFKit, a system framework — no package
dependency, no `Package.resolved` change) recovers per-line geometry;
`PDFRenderer` rebuilds Fountain from it.

### Reconnaissance that shaped the contract

Measured on a real 91-page US Letter screenplay PDF before any code was
written. Left margins clustered cleanly — 1.50″ action and headings, 2.50″
dialogue, 2.90–3.00″ parentheticals, 3.50″ cues, 7.50″ page numbers — and
vertical gaps were trimodal (0pt same block, 12pt one blank line, 24pt two).
That measurement is why classification is margin-based and why blank lines are
reconstructed from gaps rather than guessed.

### Three defects the real file caught that the plan had not predicted

1. **The title page would have become three characters.** Its centered title,
   byline, and author name sit at 0.43–0.46 of page width — inside the
   character-cue cluster. §5.4a now treats page 1 as a title page when it holds
   no scene heading and at most 12 lines: those lines go to `TitlePage.lines`,
   are excluded from `source_text`, and are never margin-classified. Excluding
   them from `source_text` also keeps them out of extraction and Phase 2 asset
   generation, which is the product reason the rule exists — a title is data
   *about* a screenplay, not part of it. Proof it works: 761 cue occurrences
   against 764 cue-margin lines, exactly the three title-page lines suppressed.
2. **`(MORE)` markers survived furniture removal.** They sit at 0.894–0.909 of
   page height, just above the one-inch bottom margin and outside an 8% band.
   Furniture is now two rules: the self-identifying `(MORE)`/`CONTINUED:`
   pattern drops unconditionally, while the ambiguous numeric page-number rule
   keeps its positional and far-right guards — a bare number was observed as
   legitimate dialogue mid-page.
3. **PDFKit splits one visual line into two selections at a style-run change.**
   A character name set in a different font on first appearance yields two
   selections sharing a baseline, separated by one space width — which is
   indistinguishable from side-by-side dual-dialogue columns. Three such
   artifacts appeared in 91 pages, enough to trip a document-wide count, but
   never two in a row. The warning therefore requires three *consecutive*
   qualifying bands; bands are grouped by vertical position, not document
   order, because a page's two columns are returned one after the other.

### Known limitations, stated rather than worked around

- **A heading with no `INT.`/`EXT.`/`EST.` prefix is indistinguishable from
  action.** Geometry puts both at the action margin, and PDF carries no forcing
  marker. A forced heading such as `THE GANTRY - CONTINUOUS` is read as action
  and its scene is lost. `structure-piece.pdf` keeps the Fountain forcing dot
  for exactly this reason.
- **A scene number set in the page margin is not recognized.** Final Draft's
  default puts it in the gutter, where it has no anchor in §5.4a and surfaces
  as an unclassified line rendered as action. Production drafts commonly do
  this; inline numbers parse correctly. A candidate follow-up.
- **`#` sections and `=` synopses cannot survive a PDF round trip** — the
  format carries no such markers, so sequences come back empty and synopsis
  text returns as action. Asserted positively in the twin test.
- **Scanned PDFs are refused, never OCR'd.** `PDFReadError.noTextLayer` carries
  `pagesTotal` and `pagesWithText` so the message names how the file failed
  ("only 0 of 91 pages carry selectable text"). Whether OCR is worth building
  is a question about how often real material lands here, and a refusal that
  reports its own shape is the only honest way to gather that.

### Determinism

PDFKit is a system framework whose extraction can shift across macOS releases,
which threatens byte-exact `.parse.json` keys in a way our own code does not.
The keys stay byte-exact and a PDFKit-induced diff is treated as a real
detected regression requiring a reviewed regeneration plus a
`FilmScriptVersion.parser` bump in the same commit. Keys in this plan were
generated on **macOS 26.4.1 (25E253) / Xcode 26.6 (17F113)**, the same major as
CI's pinned `macos-26` runner. `CGPDFContext` stamps a creation date and file
id, so the sample generator is not byte-reproducible; the committed PDF is the
artifact of record.

### Schema

Admitting `'pdf'` widens a `CHECK`, which SQLite cannot alter in place, so
bundle schema 3 rebuilds `scripts` and `projects` and copies every row. The
registered `"v2"` migration was not edited — v2 bundles exist and GRDB records
migrations by name. v2 → v3 is non-destructive, so it is silent: the one-way
upgrade modal now gates on `BundleInspection.needsOneWayUpgrade`
(`schemaVersion == 1`) rather than `needsUpgrade`, which would have shown every
existing project a "scenes will be rebuilt" warning for a widened constraint.

### Acceptance

Operator screenplay, 91 pages, imported through `ScreenplayImporter.load`:
**69 scenes, 34 distinct characters, 761 cue occurrences, 4 title-page lines,
one `unclassifiedMargin` warning, 0.75 s**, deterministic across runs. No
`(MORE)`, `@(MORE)`, or `CONTINUED` text survived into the rendering, and no
page-1 line produced a character. The screenplay itself was never copied into
the repository, and no answer key, sample, or report derived from it exists
(§7.1). The in-app import walk-through is with the operator.

## Plan 005 — Human correction, provenance, and locking — 2026-08-20

Every divergence from the plan's contract, and the reasoning that produced it.
The contract itself is `docs/plans/005-human-correction-provenance-and-locking.md`;
nothing here re-states a rule it already fixes.

### `EditOperation` cases carry the entity kind

The plan writes the operation list as `renameEntity`, `deleteEntity`,
`rejectEntity`, `unrejectEntity`, and `createEntity` without saying what each
case holds. They are implemented as `renameEntity(id:kind:name:)`,
`deleteEntity(id:kind:)`, `rejectEntity(id:kind:)`,
`unrejectEntity(id:kind:priorState:)`, and
`createEntity(id:kind:name:description:)` — the **kind travels with the case**
— because `displayName` is the only source of an undo action name and the
contract's own example of one is "Rename Character", not "Rename Entity". The
kind cannot be looked up when the name is read: the row may be gone (a delete's
own action name) or may have been re-classified since. The public wrappers read
it off the row inside the same transaction that mutates it, so the case is
always stamped with the kind the operation actually applied to.

### The undo bridge: what two review passes changed

Two defects were found in the bridge as first written, and both are now
asserted by `ProjectWindowModelTests`.

- **A group must never be held across an `await`.** The first version opened
  `beginUndoGrouping()` before the session call and closed it after, so one
  batch action would be one undo step. But a `removeAllActions()` that lands in
  the middle — an AI entry seen by `refresh()`, a refused inverse, an import —
  resets the grouping level, and the matching `endUndoGrouping()` then crashes;
  a direct Edit ▸ Undo arriving in the same window nests a second group.
  Grouping is now opened and closed **synchronously around the one
  registration**, inside `registerUndoAction`, with no suspension in between.
  Nothing is lost: `performGroup` returns exactly one `JournalEntry`, so a
  batch action is exactly one registration and therefore one undo step for
  free.
- **`undo()` / `redo()` are AppKit's real door, not `canUndo` / `canRedo`.**
  Serialization was first enforced only in `ProjectWindowModel.undo()`, with
  `canUndo` returning `false` while an inverse applied. AppKit does not go that
  way: `undo:` / `redo:` reach the `NSUndoManager` **directly**, so a second ⌘Z
  popped the stack and ran the closure regardless. `ProjectUndoManager` now
  overrides `undo()` and `redo()` to refuse while `isApplyingInverse` — before
  anything is popped, so the stacks are genuinely untouched — and keeps the
  `canUndo` / `canRedo` overrides so everything that *does* consult them agrees.
  The in-closure re-registration branch survives as defence in depth only.

`EnvironmentValues.undoManager` is get-only in SwiftUI's public API, so the
plan's `.environment(\.undoManager, model.undoManager)` cannot be written.
SwiftUI resolves that value from the same AppKit path the menu uses —
`ProjectWindowDelegate.windowWillReturnUndoManager(_:)` — so the single hook
serves both.

### Revert: "delete every row the entry created" outranks the tombstone

§3.6 says a human deleting an `ai`- or `parser`-sourced row tombstones it
rather than removing it. §3.8 says an `unmerge` / `unsplit` / `restoreEntity`
inverse **deletes every row the entry created**. For a row the inverted entry
itself created these two collide, and §3.8 wins: reverting a run must leave the
project byte-identical to the pre-run digest, and a tombstone left behind is a
row that was not there before. The tombstone rule governs a **human's delete of
a fact that already existed**; it is not a floor under an inverse undoing the
creation of that same row. Step 6's revert therefore hard-deletes rows created
by the entries it inverts, and `RevertRunTests` asserts the digest, not the
tombstone.

### A mixed batch delete is two steps, deliberately

§6 routes Delete per row: a `human` row (or one already `rejected`) is
hard-deleted, a `parser` or `ai` row is tombstoned. FilmCore exposes
`deleteEntities(ids:)` and `rejectEntities(ids:)` and no mixed wrapper, so
`ProjectWindowModel.deleteEntities(ids:)` partitions the selection and issues
one group per half. A homogeneous selection — everything the list produces in
one gesture, and the overwhelming norm — stays exactly one journal row and one
undo step. A genuinely mixed selection is two. The alternative, tombstoning the
whole batch, would be one step but would quietly refuse to delete a row §6 says
is the operator's to delete; correct semantics won. A mixed `performGroup`
wrapper would be a change to §6's operation list, i.e. a FilmCore change, not
an app one.

### `acceptAllProposed`'s empty guard is in the app, and should not stay there

`acceptAllProposed()` on an empty project would journal an `.acceptAll(refs:
[])` — a row whose payload flips nothing, whose inverse flips nothing, and
whose only effect is an undo action that does nothing. The window model guards
it with `pendingReviewCount() > 0`. That is the app-side half; the exact
`refs.isEmpty` guard belongs beside `ReviewOperations.proposedRefs` in
FilmCore, where every caller gets it, and Plan 007 — which adds the second
caller — is the right place to move it.

### Step 8: the editing UI

- **Plain-key menu shortcuts stand down while text is being edited.** §3.11
  gives Entity ▸ Rename the Return key and Entity ▸ Reject/Delete the ⌫ key,
  with no modifiers. Those become real AppKit key equivalents, and a key
  equivalent is matched **before** the focused field editor sees the key — so
  as written they would eat every Return and every backspace typed into any
  text field in the window. A **disabled** menu item does not consume its key
  equivalent, so both items gate on `allowsPlainKeyShortcuts`, which is false
  while any text control outside a sheet has focus (a balanced depth count fed
  by the `tracksTextEditing` modifier), while an in-place rename is open, and
  while a sheet is up. The actions' own validity is a separate predicate, so
  the inspector's buttons and the context menu stay live throughout.
- **"Reject/Delete" is one item titled "Delete".** Read the way §3.11's
  "Lock/Unlock" is read — one item whose behaviour depends on the row — the
  pair names one command whose outcome §6 decides: a `parser` or `ai` row is
  tombstoned, which is what "Reject" means, and a `human` or already-rejected
  row is removed. The menu item is titled "Delete" because that is the gesture;
  the inspector additionally carries an explicit **Reject** button for the
  review workflow and a **Restore** button on a tombstone. Edit ▸ Delete is the
  same command without the shortcut — two menu items cannot share ⌫.
- **Continuity lists states as well as events.** §3.11's Continuity row
  describes events, but Plan 005 puts `StateEditorSheet` under
  `Views/Continuity/` and its own UI case asks for a wardrobe state to be
  visible "in the inspector **and** in Continuity". States are continuity data
  and this is where one reads next to the event that caused it, so the section
  shows both groups in the same `(scene ordinal, entity name)` order. A state
  cannot exist without an entity (§4.3), so it is **added** from that entity's
  inspector and edited from either place. There is no project-wide states read
  — §6 hangs them off `EntityDetail` — so the section loads them lazily, once
  per refresh, rather than making every window pay for them.
- **Move into… over a multiple selection is one operation per location.**
  `setLocationParent(id:parentID:)` is scalar and §6 lists no batch form, so
  the sheet loops and stops at the first refusal. Each move is its own undo
  step; the "one batch action, one undo step" rule covers the three operations
  FilmCore actually groups.
- **The review filter is a store query.** `ReviewFilters` re-reads
  `entitySummaries(reviewState:includeRejected:)` rather than filtering rows in
  the view, because a rejected row is excluded by every default read and can be
  seen no other way. Entity **names** are still read unfiltered, so a
  continuity row or a relationship line can name an entity the current filter
  hides, tombstones included.
- **Sheets are hosted once, by `ProjectSplitView`.** The Entity menu is a
  `Commands` block with a window model and no view to reach into, so every
  sheet is raised through `ProjectWindowModel.presentedSheet`.

### Four defects `Phase1EditingUITests` caught that nothing else would have

Every one of them builds, compiles clean, looks right in the source, and is
invisible to a headless test. They are the reason the UI suite is the gate.

- **A container that carries an accessibility label hides its children.**
  Naming a sheet's root `VStack` with `.accessibilityLabel` collapses it into a
  single accessibility element, so `confirmMergeButton` and
  `stateDescriptionField` did not exist as far as the automation — or a
  screen-reader user — was concerned. Plan 004 had already documented this on
  `EntityListView`; every named container now carries
  `.accessibilityElement(children: .contain)` beside its identifier.
- **Two `confirmationDialog`s on one view compete for one presentation slot.**
  The Delete confirmation, attached next to §5.5's Replace dialog on the same
  view, silently never appeared. It now hangs off the detail column instead.
- **SwiftUI's stock Edit ▸ Undo item is titled a bare "Undo".** It validates
  correctly against the window's `UndoManager` — the item was enabled — but it
  never appends the action name, so §3.8's "Edit ▸ Undo / Redo … show the action
  name" is not satisfied by leaving the system items in place, as Plan 004's
  comment assumed. `CommandGroup(replacing: .undoRedo)` now supplies items that
  read `undoMenuItemTitle` / `redoMenuItemTitle`. Their text and their enabled
  state come from an **observable mirror** (`ProjectWindowModel.undoMenu`,
  written only by `UndoBridge.syncUndoMenu()`): `UndoManager` is not
  `@Observable`, so a `Commands` body reading it directly renders once and never
  updates. AppKit still resolves the manager through
  `windowWillReturnUndoManager(_:)`, and `ProjectUndoManager.undo()` still
  refuses while an inverse applies, so the guard holds for any path that does
  not come through the menu.
- **A `confirmationDialog` can clear its `isPresented` binding before the
  button's action runs.** `confirmPendingDeletion()` read the armed rows back
  off the model and found them already cleared by the dismissal, so Delete did
  nothing at all. The dialog is now built with `presenting:` and hands the
  captured value to `performDeletion(_:)`.

  **§5.5's Replace dialog (Plan 004's) had the same defect, and it was not
  hypothetical**: confirming Replace silently imported nothing. It is fixed the
  same way — `presenting: model.pendingReplace` into
  `performReplace(_:)` — and `Phase1ImportUITests`
  .`testConfirmingReplaceReimportsTheScreenplay` now covers it: import the
  bundled sample, import it again, confirm, and the summary sheet must present
  again with the sample's counts. Reverting the fix makes that case fail with
  "the import summary sheet never presented", which is how the defect was
  confirmed rather than assumed. `confirmPendingReplace()` and
  `confirmPendingDeletion()` both survive as the no-captured-value path for
  callers that are not a dialog.

A whole-window `value CONTAINS` predicate is also not a safe way to look for
text: it is evaluated against controls whose value is a number or a boolean and
does not survive the comparison. The suite asserts on identified static texts
and on a field's own value instead.

### Verification

Every component of `./scripts/verify.sh` passes: 337 FilmCore tests, 40 app unit
tests (`AppShellTests`, `ProjectWindowModelTests`), and both UI suites
(`Phase1EditingUITests`, `Phase1ImportUITests`).

macOS UI testing on this machine is intermittently blocked by `Timed out while
enabling automation mode.` — it hits Plan 004's already-committed suite
identically, clears after killing a stale `testmanagerd` and retrying, and has
nothing to do with the code under test. Retry once before treating it as a
failure.

The six UI cases are additionally asserted headlessly in
`ProjectWindowModelTests` — review filter and tombstone visibility, selection
validity, the name lock, a state reaching both the inspector and Continuity,
the synopsis edit and its undo, and the plain-key gating — so a regression in
the underlying behaviour is caught even where the automation environment is not
available.

## Plan 007 — run usage was double-counted in `runs()` — 2026-08-21

An external audit claimed extraction run histories "appear to double-count
usage by summing parent aggregates and child usage." **Confirmed, and fixed.**

The two halves of the contract were each implemented correctly, and then added
together:

- `ExtractionRun.finish` hands apply the aggregate over the run's leaves —
  `usage: JobUsage.sum(childUsage.values)`
  (`Packages/FilmBrain/Sources/FilmBrain/Extraction/ExtractionRun.swift:529`).
  Launched chunk attempts record their measured usage there
  (`ExtractionRun.swift:445`), reused attempts record `.empty`
  (`ExtractionRun.swift:495`), and reconcile records its own
  (`ExtractionRun.swift:637`).
- `ExtractionApplier.apply` writes exactly that value onto the parent row in the
  same transaction as the `completed` transition
  (`Packages/FilmCore/Sources/FilmCore/Extraction/ExtractionApplier.swift:290`).
- `runs()` then reported
  `JobUsage.sum([parent.usage] + children.map(\.usage))`
  (`Packages/FilmCore/Sources/FilmCore/Storage/ProjectRepository+Reads.swift:445`,
  before this change) — the stored aggregate **plus** the same leaves again.

So every completed run reported exactly twice its real usage, in the run card's
"N tokens total" (`AI Film Camp/Views/Extraction/RunCardView.swift:12`) and in
the Jobs list (`AI Film Camp/Views/Jobs/RunsListView.swift:96`). This
contradicts §8.5 ("The parent row also stores the aggregated child usage,
written by apply in the same transaction; `runs()` reports that stored aggregate
and never re-sums children") and Plan 007's usage bullet (lines 175-178).

**Why nothing caught it.** `ProjectReadingTests`
.`runsAggregateUsageOverChildrenNilAware` completed the parent with
`usage: .empty` — a state no production path produces, since apply is the only
writer of a parent's usage and it always writes the aggregate. With the parent
at zero, summing children happened to give the right answer, so the test agreed
with both the correct and the broken implementation.

**Fix.** `runs()` now reports `parent.usage` and nothing else. The test above
completes the parent with the aggregate the way apply does, and a new case,
`runUsageCountsEachLaunchedChildExactlyOnce`, pins the rule: one launched child
with usage in all five fields plus one `Reused` child with `.empty`, and the
run's reported usage must equal the launched child's exactly — the old
expression returns double it, so the regression is caught rather than assumed.

A run whose parent never reached `completed` (failed, cancelled, paused) now
reports zero at the run level, because no aggregate has been written yet. That
is the contract, and it loses nothing: per-attempt usage is listed on the
attempt rows of the same run card (Plan 007, line 425).

This matters beyond Plan 007 — Phase 2's manifest run (Plan 012) reports usage
through these same job surfaces.

### Verification

`./scripts/verify.sh` passes end to end (exit 0): 348 FilmCore tests, 100
FilmBrain/FilmEval tests, 42 app unit tests, and both UI suites (17 cases).
The macOS UI runner hit the documented automation flake twice on the way there
— once as `Timed out while enabling automation mode.` and once as `Lost
connection to the application` in two `Phase1EditingUITests` cases that pass
in isolation and passed on the clean run. Neither touches the code changed here.

---

## Plan 011 — Asset media, versions, and approval — 2026-08-22

### Step 3's manual check, performed and recorded honestly

Plan 011 Step 3 asks for a manual check: "one real image imported, approved, and
surviving a Finder move on a real bundle". What was actually done, on
2026-08-22, is this — stated plainly because it is **not** a hand-driven Finder
session:

- An automated harness (a throwaway SwiftPM executable in a scratch directory,
  depending on this repository's `FilmCore` by path — not committed) ran the
  whole sequence in one process.
- The image was a **real** 640 × 480 RGB gradient rendered with CoreGraphics and
  encoded to PNG by ImageIO — 6,595 bytes on disk — not a hand-built test
  fixture.
- It created a real bundle (`ProjectBundle.create`), imported a real screenplay,
  created a variant requirement on the parsed character, and imported the image
  through `ProjectSession.importAssetVersion`, which landed at
  `assets/character/sarah/office-outfit/v1.png` with `640 × 480` read from the
  header and its SHA-256 recorded.
- It approved that version, and confirmed the slot read `approved` before the
  move.
- It closed the session and moved the bundle with **`/bin/mv`** — which is what
  a Finder move performs — from
  `…/plan011-manual-<uuid>/Manual Check.aifilm` to
  `…/plan011-manual-<uuid>/moved/Manual Check.aifilm`. **No human dragged
  anything in Finder.** The project-movement discipline being exercised is the
  Phase 0 one: movement while the project is closed.
- It reopened the bundle at the new path, and asserted: the same version id came
  back, still `approved`; `resolve(_:)` produced a path inside the **moved**
  bundle; the file read back through `BundleContainment.withReadDescriptor`
  (descriptor-relative, no-follow) with its byte count and SHA-256 both matching
  the row; a capped `CGImageSourceCreateThumbnailAtIndex` rendered a 256 × 192
  thumbnail — the same call the app's `AssetPreviewLoader` makes, reproduced in
  the harness because that type lives in the app target and is not reachable
  from a FilmCore-only script; and `orphanedMedia()` reported 0.

Result: **passed**. Nothing needed path repair, which is the property §4.1 buys
by storing a `RelativeProjectPath` and resolving it at read time.

What this check does **not** cover, and is covered elsewhere: the app's own
window and inspector rendering the reopened image (the UI suite and the headless
twins drive that), and the planted-symlink refusals (`AssetWindowModelTests`
plus FilmCore's `MediaContainmentTests`).

### The app-side shape, and two deviations worth recording

- `AssetPreviewLoader` hands back **PNG bytes**, not a `CGImage`, so the read,
  the integrity check, and the capped decode can all run off the main actor
  under strict concurrency. It verifies size (`fstat` on the walked descriptor)
  **and** SHA-256 — the design permits hashing "on demand", and since the bytes
  are already in memory for the thumbnail, always hashing costs nothing and
  makes the damaged-asset warning exact.
- The two destructive gestures share **one** `pendingMediaDeletion` value and
  therefore one `confirmationDialog`, because two dialogs on one view compete
  for the same presentation slot (the defect Plan 005 already documented). The
  media dialog hangs on `content`, the orphan-sweep dialog inside
  `RunsListView`, and the two Phase 1 dialogs keep their existing hosts.
- **Per-version notes have no control yet.** `setVersionNotes` exists on the
  window model and is exercised by FilmCore's suites; only asset-level notes got
  a field, because a second text field per version row would have made the row
  the wrong shape for the "minimal slot surface" contract C asks for. Phase 3's
  workshop window is where a version gains room for its own note.

### Verification

`./scripts/verify.sh` passes end to end (exit 0) on 2026-08-22: 535 FilmCore
tests, 98 FilmBrain/FilmEval tests, 57 app unit tests (8 of them the new
`AssetWindowModelTests`), and 28 UI cases across five suites (5 of them the new
`Phase2AssetUITests`). `project.yml` and every `Package.resolved` are unchanged;
only the XcodeGen-regenerated `pbxproj` moved.

The documented macOS UI-runner flake showed up **three times** before the clean
run, on a machine that had been sleeping: twice as `Timed out while enabling
automation mode.` — including on a pre-existing, untouched
`Phase2ManifestUITests` case, which is what established it as environmental
rather than a regression — and once as `The test runner hung before establishing
connection.` One real failure hid among them and was fixed rather than retried:
`Phase2AssetUITests` case (b) clicked **Add Variant** after Build, and that
control rides on §5.3's "qualifies — Build to add" row, which Build clears. The
case now adds the variant before Build, which is also the order that gives it
§3.5's dependency on every canonical row Build creates.

## Plan 012 — Manifest inference — 2026-08-22

### Step 3's live gates were not run; the operator declared manual verification done

Recorded plainly, because the plan's exit evidence is an operator activity and
this is a deviation from it. Plan 012's live-gate policy lists two
account-backed gates, and **neither was executed**:

1. the schema-compatibility probe
   (`ManifestSchemaCompatibilityTests.testLiveManifestSchemaPreflight`), and
2. the §10 acceptance run on the operator's feature screenplay — the plan's
   stated `DONE`-blocking exit evidence.

Both remain gated behind `FILMCAMP_RUN_LIVE_CODEX=1` and skip cleanly in the
default suite, which is what the verification run below shows. On 2026-08-22 the
product owner directed that manual verification be considered done and the
branch merged, so **no accepted/edited/rejected proposal counts from a real
Codex run exist to record here**, and none are invented. The deterministic
half — every §8.3 validator case, the §8.4 match enumeration with its step-0
digest guard, the three §3.6 bootstrap gates, cross-task revert, and the
recorded-run UI path — is covered by the suites and did run.

If a real acceptance run is performed later, its counts belong in this section,
and the manifest inference path should be treated as unexercised against live
Codex until then.

### What Step 3 shipped

- `ProjectWindowModel+ManifestRun.swift` carries the whole run on the window
  model, shaped like `ProjectWindowModel+Extraction.swift`: prepare (gate, then
  disclosure or confirm), start (progress, run, report), review. It enforces
  nothing — FilmCore throws all three §3.6 refusals from `createJob` and
  FilmBrain's `ManifestRunGate` asks the same questions before launching, so the
  model only keeps the section from offering what the store would reject, with
  the store's own refusal sentence attached.
- `ManifestDisclosureText` holds §9's two copy blocks verbatim, out of the view
  so `ManifestRunModelTests` can assert them character for character.
- The Jobs section became task-aware: row labels, the report line, child
  ordering, and the newest-revertable-run choice all moved from `RunsListView`
  onto the window model, because a rule restated inside a `View` body cannot be
  tested. A manifest run is childless by design (§8.1), so it says "Manifest
  run" and renders no chunk lines rather than "0 chunks".
- The recorded harness adapter answers `infer-manifest-*` requests by
  materializing a result from the §8.2 input the request carries — the same
  reason the extraction branch materializes: a freshly imported project's ids
  are random, so a checked-in result could not resolve. The judgments are fixed
  and synthetic; the ids are read back out of the input so the §8.3 validator
  sees something that resolves.

### Verification

`./scripts/verify.sh` did **not** exit 0 on this branch, and the merge to `main`
was made anyway on the product owner's explicit direction. Stated precisely,
because "verify.sh passes" is the repository's standing gate and this is a
deviation from it:

- **Green**: `check-docs.sh`; FilmCore 563 tests; FilmBrain/FilmEval 124 tests;
  the app target **BUILD SUCCEEDED**; the app-hosted unit bundle, including
  `ManifestRunModelTests` — Step 3's headless twins.
- **Unexercised**: every UI suite. Not failing — *unexercised*. The UI runner
  could not initialize automation mode, so **zero UI cases executed**, including
  the new `Phase2InferenceUITests`. The recorded-run flow through the actual UI
  has therefore never been observed on this commit.
- **Never run**: both live Codex gates, as recorded above.

The UI blockage is environmental and was diagnosed rather than assumed. Two
distinct macOS faults stacked:

1. A **wedged `testmanagerd`** (1h17m uptime, having survived several killed test
   runs) hung the app-hosted unit bundle with "The test runner hung before
   establishing connection" and "Timed out after 120.0s while initiating control
   session with daemon". Proof it was the daemon and not this plan's code: the
   **pre-Step-3 baseline commit `8944bec`**, in a separate worktree with its own
   `-derivedDataPath`, hung with a byte-identical signature in a checkout
   containing no Step 3 code at all; and after `kill -9` on the daemon, the same
   bundle on the same commit with the same derived data went from 700s+ of
   hanging to **passing in 16.5 seconds**.
2. Underneath it, the **UI automation-mode flake** already documented for this
   machine ("Timed out while enabling automation mode"), which reproduced twice
   in a row on an idle machine with a fresh daemon and did not clear on retry.
   The remaining suspect is macOS automation/accessibility authorization state,
   which is a login-session security setting and was deliberately **not** altered
   to make a build pass. It is possible, though unproven, that killing
   `testmanagerd` made this stickier.

The honest reading: the deterministic half of Plan 012 is well evidenced, and the
UI half rests on code review plus the headless twins. A reboot followed by one
clean `verify.sh`, or a run from an interactive Terminal where a TCC prompt can be
answered, is what would close it. Anyone touching the Manifest section next should
run the UI suites first and treat a failure there as plausibly pre-existing rather
than theirs.

Two `verify.sh` invocations were also found running concurrently in this worktree
earlier — one left over from another session — sharing `.build/DerivedData` and
both driving UI tests against the same app. Both were killed and `DerivedData` was
removed before any run recorded here, because neither of their results meant
anything.

## Plan 009 — Storage v4 and the requirement model — recorded 2026-08-22

Recorded by Plan 013 (contract E) with the finding its repair settles; the plan
itself shipped with its in-file `## Status` block still reading `TODO` while
`docs/plans/README.md` listed it `DONE` (flipped 2026-08-22 ahead of Plan 013).

**Phase 2 defect — the dependency reads counted tombstoned edges.**
`ManifestGraph`'s dependency load (`ProjectRepository+ManifestReads.swift`)
fetched every `asset_dependencies` row with **no review-state filter**, unlike
the sibling scene-link load and `RequirementOperations.activeEdges`, which both
filter `review_state <> 'rejected'`. Because `removeDependency` *tombstones*
`ai`/`parser` edges rather than deleting them, the shipped `dependsOn`,
`dependents`, `unsatisfiedDependencies`, and therefore Phase 2's own dashboard
Blocked count all counted dependencies the filmmaker had removed.

Repaired by Plan 013 in `manifestGraph(in:)`; the repairing/verifying tests are
`DependencyFilterRepairTests.aTombstonedEdgeStopsCountingEverywhere()` (all four
reads: `dependsOn`, `dependents`, `generationBlockedBy`, and the Blocked count
through `missingAssets()`/`manifestSummary()`) and, for the new prompt reads,
the tombstone exclusion asserted across `PlannedDependencyTests`.

## Plan 010 — Requirement editing, review, and the manifest — recorded 2026-08-22

Recorded by Plan 013 (contract E); same status-block debt as Plan 009's entry,
settled the same day.

**Phase 2 finding — `tableOrder`/`deleteOrder` ordering mismatch on
`requirementScene`/`basis`.** The shipped `RowGraph.tableOrder` and
`InverseApplication.deleteOrder` disagree on where `asset_requirement_scenes`
and `asset_requirement_basis` sit relative to each other. Investigated during
Plan 013's §7.4 renumber and documented as **harmless**: the two tables do not
foreign-key each other, so neither restore order can dangle a reference. Left
as shipped. The guard going forward is
`DeleteOrderAgreementTests.newKindsRestoreInTableOrder()`, which asserts the
descending-restore / ascending-`tableOrder` agreement **for the new prompt
kinds only** — deliberately scoped so a global assertion would not fail on the
harmless disagreement.

## Plan 013 — Storage v5 and the prompt model — 2026-08-22

Executed across four commits on `main`. All FilmCore gates green (604 tests),
FilmBrain untouched and green (124), `check-docs.sh` green, the app target
builds with **zero** app-source changes (the plan adds no user-facing surface;
the only app-visible ripples are additive enum cases and read fields), and
`eval-gate.sh` short-circuits as designed (`eval-inputs.txt` is
extraction-scoped and untouched).

**Verification gate status — honest reading.** `./scripts/verify.sh` did not
exit 0 on this machine at completion time: the UI test runner failed to
initialize ("Timed out while enabling automation mode", then "The test runner
hung before establishing connection") on every retry, including after killing
`testmanagerd`, wiping `.build/DerivedData`, and a two-minute cooldown. This is
the same environmental degradation Plan 012's entry records, which worsens over
a long session of repeated UI-runner launches and whose documented remedy is a
reboot plus one clean run from an interactive Terminal. The evidence that this
is environmental and not Plan 013's code:

- The failure signature reproduces at the **runner-initialization stage**, before any test executes.
- The app build step passes; both app-hosted unit bundles pass (61 tests, 0 failures) when driven directly.
- The full UI suite passed twice earlier the same session on this machine (after process cleanup), including `Phase2InferenceUITests.testFirstManifestRunShowsTheFullDisclosureAndCancels`.
- Every Plan 013 change lives under `Packages/FilmCore/`; the app target's sources are byte-identical to the pre-plan tree.

The remedy stands: reboot, then one clean `./scripts/verify.sh`.

Also recorded here because it bit twice during execution: after changing
FilmCore's public interface, `Packages/FilmBrain/.build` served stale mixed
binaries whose symptom was spurious failures across otherwise-green suites
(`script() → nil`, `.noScreenplay`, and one `swiftpm-testing-helper` signal-11
crash). `swift package reset` in `Packages/FilmBrain` cleared all of it; the
failures did not reproduce after. Anyone seeing cross-suite "import didn't
stick" symptoms after a FilmCore change should reset before debugging.

## Plan 014 — Prompt operations, states, and interactions — 2026-08-23

Executed across four commits on `main`. All FilmCore gates green (634 tests);
FilmBrain untouched and green (124); the app target builds with no view added
or edited; no AI path exists.

**Owner-gate posture.** The §14 decisions this plan implements — §14.5 (human
prompt authoring and editing via `createPrompt`/`setPromptBody`) and §14.7
(In Progress as an explicit journaled gesture refused once versions exist) —
were **accepted by the product owner on 2026-08-22, as recommended**, recorded
in PHASE3_DESIGN §14; this plan builds them as written. §14.2's `deleteAsset`
branch (Empty Slot spares prompts and composes a fresh anchor reading
`prompt_ready`) shipped here; its confirm copy belongs to Plan 015. Confirmed
before flipping this plan's README row.

**Verification-gate status.** Same posture as Plan 013's entry: every
deterministic gate green (`check-docs.sh`, FilmCore, FilmBrain after
`swift package reset`, app build, eval-gate short-circuit). The UI runner on
this machine remains subject to the recorded automation-mode degradation;
Plan 014 adds no UI code, so its suites are unaffected either way.

## Plan 015 — The asset workshop — recorded 2026-08-23

Landed so far: §5.1's in-content master–detail (Manifest section narrows to a
300-pt master pane; `AssetWorkshopView` renders beside it); the wholesale
`AssetSlotView` re-host with every shipped identifier riding verbatim;
`requirementBlockedBadge`/`requirementStaleBadge`/`addVariantRequirementButton`
moved into the workshop header (grep count exactly 3, one host each);
§5.2–§5.6 surfaces (header badges, Used In, planned-dependency references with
designators/unsatisfied markers, prompt panel with Write/Copy/Edit/history,
stamped Import Result through `promptID:`, Generate/Regenerate disabled
false-safe with §5.8 reasons); `WorkshopConfirmText` + character-for-character
`WorkshopCopyTests`; headless twins (`WorkshopWindowModelTests`) covering the
§10 no-AI walk end to end; OVERVIEW Stage 8 reconciled to `Prompt Ready` with
every pinned hash swept (001 by hand) in the same commit.

**Honest gap at recording time.** `Phase3WorkshopUITests.swift` is not yet
written, and the machine's recorded automation-mode degradation again wedged
the runner mid-session, so `verify.sh` has not exited 0 for this plan. The
headless twins carry the assertions of record per §5.9. Next session: reboot,
write the UI walk following `Phase2AssetUITests`, run one clean `verify.sh`,
then flip this row to `DONE`.

**Owner decision, 2026-08-23:** Plan 015 flips to `DONE` under the **Plan 012
posture** — the deterministic gates are green, the headless twins carry the
assertions of record, and the UI walk (`Phase3WorkshopUITests`) plus one clean
`./scripts/verify.sh` remain outstanding solely because of the recorded
environmental runner wedge. Anyone touching the workshop next writes that UI
suite first and treats a failure there as plausibly environmental.

## Plan 016 — Asset prompt generation (Phase 3b) — live-gate deferrals, recorded before any materialiser code

**Sandbox probe (live gate 1): DEFERRED — arm B selected.** The §3.5 probe
(one live request reading an absolute path outside `-C`) was not run: the
operator declined to spend the request at execution time (2026-08-23). Per the
plan's live-gate policy the materialiser therefore implements **arm B**, the
clone-fallback design — correct under either probe outcome, since a cloned
skill is read from inside the workspace. Concretely: the shared copy still
resides at `cache/skills/<skill_id>/<tree-digest-prefix-12>/`, and each run
additionally receives an APFS `clonefile(2)` clone of that copy under its own
`workspace/skill/`; the rendered instructions name the **cloned** entry by
absolute path. The growth bound is stated in bytes of unique data (§3.5, §4.1):
unique bytes ≤ one skill tree per concurrent run. **Degradation observed in
testing**: when `clonefile(2)` returns `ENOTSUP`/`EXDEV` — a bundle on a
non-APFS volume, a runtime fact no build-time check settles — the materialiser
falls back to a plain per-run copy under the same `workspace/skill/` path,
swept by the same Clear Job Cache walk; the bound degrades to one tree per
live run and this note is its record. A later passing probe makes arm A a
cache-layout change, not a contract change.

**Schema-compatibility probe (live gate 2): DEFERRED.**
`asset-prompt-v1.schema.json` was not probed against live Structured Outputs
(operator decision, 2026-08-23). It follows the shipped `infer-manifest-v1`
pattern exactly (`additionalProperties: false` everywhere, `const` schema
version, no arrays, no `maxLength`), so the deferral risk is the same one the
manifest schema carried until its own probe. Record here: probe outstanding.

**§10 acceptance run (live gate 3): DEFERRED — the Plans 003/004 posture.**
All deterministic work lands; the acceptance run (exactly six requests on the
operator's feature project) stays deferred with the operator's consent
(2026-08-23). Per the live-gate policy this plan may complete with the run
deferred and recorded, but **Phase 3 itself is not finished until the
acceptance record is committed**, and the deferred run defers the batch driver:
Step 6 (contract D, `AssetPromptBatch`) is **skipped whole** — its §14.1
evidence gate (acceptance ≥ 5/6 plus owner spend approval) is unmet — and no
batch surface renders. Single-requirement generation, regeneration, and every
other contract stand. This deferral also leaves §1's last roadmap exit
criterion ("project can be used to build a complete asset library") at the
stated at-risk posture: delivered in principle through the per-slot loop,
unproven at batch scale.

## Plan 016 — execution record — 2026-08-23

Landed across four commits (`7769b9c` steps 1–2, `0d4c52b` step 3, `901f7a7`
step 4, step 5's commit): arm-B materialiser with the four containment rules,
the unfiltered `cache/skills` second-root sweep, the `PromptSkills` folder
resource with a build-product test, task/schema/instructions/validator, the
FilmCore run gates and invertible apply through `attachGeneratedPrompt`'s
pinned signature, the `AssetPromptRun` coordinator with `AssetPromptRunGate`,
the app-side replay branch, disclosure sheets, workshop wiring, the Jobs arm,
and the four headless twins (`PromptRunModelTests`) green end to end over the
recorded adapter.

**Verification-gate status (Plan 012/015 posture).** `check-docs.sh` green;
FilmCore 651 tests green; FilmBrain green (4 skips = the opt-in live gates);
app build green; eval-gate short-circuits as recorded. `verify.sh` has **not**
exited 0 on this machine: its full `xcodebuild test` leg remains subject to
the recorded environmental wedge (two runaway process-group stubs were found
spinning since 2026-08-22 and killed mid-session), and one Plan 015-era
assertion (`WorkshopWindowModelTests/
testGenerateRendersDisabledWithItsReasonAndProposedRefusesPromptWork`,
failing at `isWorkshopRequirementProposed`) fails here while every file in
Plan 016's diff is disjoint from that code path — treat it as plausibly
environmental and re-run on a clean machine before trusting it. The headless
twins carry the assertions of record per §5.9.

**Engine note for the record.** Redoing a generate required one addition to
Plan 014's engine plumbing: `attachGeneratedPrompt` gained the house-standard
`.inverting` arm (restore from the undo entry's snapshots, never through the
gesture guards — the `createPrompt(restoring:)` pattern), and the app's
`noteJournal` sweep exempts exactly `.attachGeneratedPrompt` arrivals from the
AI-entry stack clear (§13.11). The pinned operation signature and every Plan
014 surface are otherwise untouched.

**Owner decision, 2026-08-23:** Plan 016 flips to `DONE` under the recorded
deferral posture — all three live gates deferred with consent, Step 6 skipped
whole, quality unjudged until the acceptance run happens. Phase 3 closes only
when that acceptance record is committed.

## Phase 3 closed — owner decision, 2026-08-23

**The product owner closes Phase 3 with the §10 acceptance run waived.** The
design's standing rule ("Phase 3 itself is finished only when the acceptance
record is committed", §10) is amended by this decision, recorded here at the
owner's direction: the six-request acceptance run was never spent, no prompt
quality tier was ever graded, and the closure stands **without** that evidence.
Consequences, stated plainly so no future reader mistakes this for a pass:

- The roadmap's last Phase 3 exit criterion ("project can be used to build a
  complete asset library") remains **unproven at any scale** — neither the
  per-slot loop on real media nor the batch path was exercised end to end on a
  feature project.
- The §14.1 batch driver stays deferred permanently-until-reopened: its
  evidence gate (acceptance ≥ 5/6 plus spend approval) was never met, and no
  batch surface ships.
- Prompt-generation quality is **unknown**, not passed and not failed. If a
  later phase needs the evidence (Phase 6 inherits the descriptor seam and the
  citation grammar), the acceptance run is still the door: same six requests,
  same §10 tiers, recorded here as designed.
- Everything deterministic about Phase 3 — states, operations, staleness,
  gates, apply, disclosures, materialisation — shipped under its full test
  battery as recorded above.

## Shot planning removed; phases and stages renumbered — 2026-08-23

Shot planning had been a deferred Phase 5 in `docs/ROADMAP.md` and a deferred
Stage 10 in `docs/OVERVIEW.md`, each carrying a full reference design for a
`Shot` model the MVP was told not to build. The owner removed it rather than
leaving it deferred: the first target model, Seedance 2.5, performs its own
multi-shot breakdown from a scene-level prompt, so Film Camp hands it a whole
scene and lets the model cut. Both section bodies were deleted — they remain in
this file's history — and shot planning is now a bullet in the roadmap's
"Explicit Non-Goals Across All Phases", which is the list that already means
"not without a major product decision".

Everything after the removed phase moved down one:

```text
Phase 6  Generation Prompt Engine    →  Phase 5
Phase 7  Production Intelligence     →  Phase 6
Phase 8  AI Film Camp Ecosystem      →  Phase 7

Stage 11 Prompt Generation           →  Stage 10
Stage 12 Generation Package          →  Stage 11
Stage 13 Production Dashboard        →  Stage 12
```

Phases 0–4 and Stages 1–9 are untouched, so no plan changed phase, no plan
number moved, and no §-numbered section inside any design contract moved. The
renumber was mechanical everywhere except five places where the old text
described a *deferral* rather than a number, and those were rewritten rather
than renumbered: the roadmap's canonical-assets sentence and its external
validation gate, the Overview's Principle 5 and film-graph `Shot` node, and the
"deferred Phase 5" / "`Shot` anything (Phase 5, not in the MVP)" out-of-scope
lines in the Phase 2, 3, and 4 contracts, which now read "a roadmap non-goal".

Four accepted contracts were edited (`PHASE1`–`PHASE4_DESIGN.md`), which is
worth naming plainly: their §13/§14 decisions, acceptance dates, and section
numbers are unchanged, and every edit was a phase or stage number in prose. The
edits invalidated the pinned hashes in every drift block that names a touched
file, so all eighteen plans' drift blocks were re-pinned in the same commit and
`scripts/check-docs.sh` verifies them. Four Swift doc comments in FilmCore and
FilmBrain that cite the phase by number were renumbered too; no code changed.

`docs/plans/README.md` carries the old→new translation for reading anything
written before this date.

## Plan 017 — Scene readiness, the dashboard, and the deep link (Phase 4a) — recorded 2026-08-23/24

Landed across three commits (Step 1 `fc75941`, Step 2 `fa2b931`, Step 3): the
§4.4 4a types and the one derivation function behind
`ProjectRepository+ReadinessReads.swift`; `readinessSnapshot()` on
`ProjectReading`; the `.dashboard` section (first sidebar group, no ⌘-digit);
`DashboardView` panels 1–3 (no Suggestions panel, no Generation Packages row);
the Scenes table's Readiness column with the drill-down filter;
`SceneDetailView`'s Required Assets panel; `RevealTarget.requirement` routed
through the shipped `revealRequirement(id:)`. Bundle schema untouched at 5; no
`EditOperation`, no hub entry, no migration anywhere in the diff.

**FilmCore gates**: 670 tests green (651 shipped + 19 new across
`SceneReadinessDerivationTests`, `ReadinessImpactTests`,
`ReadinessConsistencyTests`): the §6.2 gesture table through real operations
with undo legs, every §3.4 rule both ways, the fold identity asserted on every
fixture state, the M₁/M₂ sole-unsatisfied fixture with both transitions,
every five-key ordering key exercised (including eight-scenes/zero-unblocks
outranking seven-scenes/ten-unblocks), byte-equality with `manifestSummary()`,
and reopen stability. One derivation defect was caught by the battery and
fixed before it could ship: the canonical scene-link load initially joined
requirements on entity without the tier filter, leaking variants into every
scene their entity appears in.

**App gates**: build green; headless twins (`ReadinessWindowModelTests`)
green — refresh-beat behavior across all four pinned areas, deep link
(section/selection/detail), drill-down filter, `0 / 0` data, help-text bounds.
`Phase4ReadinessUITests` passed twice early in the session (dashboard panels,
drill-down, Scenes column, checklist deep link into the workshop), as did the
new `Phase3WorkshopUITests`.

**Verification-gate status (Plan 012/015/016 posture).** `verify.sh` has not
exited 0 on this machine, for two separately-diagnosed reasons:

1. **Pre-existing Plan 015 debt, deterministic, now repaired.** Running the
   full UI suite for the first time since the re-host surfaced three Phase 2
   cases riding the removed pre-Build Add Variant affordance (reproduced at
   HEAD before any Plan 017 app code existed). Repairs: the staleness and
   combine fixtures re-targeted onto the workshop header menu after Build
   (`createRequirement` still seeds each variant's dependency on every active
   canonical, so the fixture shape is preserved); the collision case became an
   `XCTSkip` pointing at its twin — after Build every enabled slot is filled,
   so the pre-Build collision is unreachable from clicks alone, and
   `ManifestWindowModelTests.testBuildSkipsANameCollisionWithItsBadgeRatherThanErroring`
   carries the assertion.
2. **The recorded automation-mode wedge, re-engaged.** After the long
   full-suite session the runner failed at initialization ("Timed out while
   enabling automation mode") on every retry including after killing
   `testmanagerd` and a cooldown — the documented degradation whose remedy is
   a reboot plus one clean run. In the degraded full-suite run, the two
   re-targeted Phase 2 cases above failed once (their result bundle was pruned
   before the failure lines could be read); they are unverified post-fix, and
   their twins (`AssetWindowModelTests` staleness,
   `ManifestWindowModelTests` combine) carry those assertions. Outstanding:
   reboot, then one clean `./scripts/verify.sh`.

**Step 4 deferred under its STOP condition.** PHASE4_DESIGN's Status paragraph
still reads "§13's deltas await formal acceptance", so the delta-10 OVERVIEW
one-liner and its hash sweep did not land, and this plan's README row does not
flip `DONE`. When the owner records §13's acceptance, land Step 4 (edit
OVERVIEW Stage 9's "Partially Ready" → `Partial`; sweep every pinned OVERVIEW
hash — Plans 002–009, 011, 013, 014 plus Plan 001 by hand; re-pin this plan's
PHASE4 hash for the Status-paragraph change) and flip the row in one commit.

**Step 4 landed — §13 accepted, 2026-08-24.** The product owner reviewed all
twelve §13 deltas as yes/no questions with recommendations and **accepted
every one as recommended** (recorded at the owner's direction in the design's
Status paragraph). Consequences landed in one commit: the delta-10 edit
(OVERVIEW Stage 9's film-level "Partially Ready" → the pinned `Partial`;
grep now finds no match), the full OVERVIEW hash sweep — Plans 001 (by hand),
002–009, 011, 013, 014, each exactly once at the new hash
`5139e449…` — and the PHASE4_DESIGN re-pin (`70b96abb…`) swept across every
plan that pins it: 017, 018, and the Phase 5 plans 019/021 that had pinned the
old value. `check-docs.sh` green on the whole set. Plan 017 flips `DONE` under
the Plan 012/015 posture: every deterministic gate is green, both new UI
suites passed when the runner was healthy, and the single outstanding item —
one clean full `./scripts/verify.sh` after a reboot — is recorded here rather
than blocking the row. If that clean run surprises us, this record is where
the reversal starts.

## Plan 017 — Step 1 record — 2026-08-23

Step 1's carried debts, recorded before any Phase 4 code exists:

- `Phase3WorkshopUITests.swift` is written per PHASE3_DESIGN §10's App walk
  (no-AI portion): write prompt → `prompt_ready` → copy with the pasteboard
  asserted → mark in progress → import result through the `nextImage` handout →
  `needs_review` → approve → `approved`; plus §5.8's proposed-workshop rule
  (prompt work disabled, import enabled, Accept unlocks). Outcome: see the
  Step 1 record appended below once the run completes.
- Plans 013–015's in-file `## Status` blocks flipped to match the README.

**Step 1 outcome — the UI runner worked this session, and one recorded
"environmental" failure turns out to be real.** Both `Phase3WorkshopUITests`
cases pass (`testWritePromptCopyMarkInProgressImportAndApproveWalk`,
`testHumanVariantIsBornAcceptedAndUnlocksPromptWork`), driven through
`-only-testing` with no automation-mode wedge. The diagnosis that matters:

- The Plan 016-era record above ("`WorkshopWindowModelTests/
  testGenerateRendersDisabledWithItsReasonAndProposedRefusesPromptWork`,
  failing at `isWorkshopRequirementProposed` … treat it as plausibly
  environmental") was **not environmental**. The twin's premise — a workshop-
  created variant is born *proposed* — contradicts shipped behavior: since
  Plan 010 (`84d437c`) every human-actor creation lands **born `accepted`**
  (`RequirementOperations.create`'s `isHuman` rule; the app's Build button and
  the workshop's New Variant menu both ride `actor: .human`). A proposed
  requirement is unreachable by clicks alone in the deterministic harness.
- Repairs, both landed here: the twin now reaches a genuinely proposed row the
  honest way — `createRequirement(tier: .variant, actor: .ai(jobID:))`, which
  §7.1's write surface permits, with a real terminal `jobs` row behind it for
  the journal's `job_id` foreign key — and keeps its §5.8 assertions unchanged;
  the new UI case documents the shipped rule instead (`a human addition is born
  accepted`, so Write Prompt unlocks immediately). No production code changed.


## Plan 018 rejected — Phase 4 closes deterministic-only — owner decision, 2026-08-24

**The product owner declines the AI advisor outright.** After reviewing the
Phase 4 acceptance questions, the owner directed that `recommendNextActions`
and its Suggestions panel are out of scope: no schema probe, no live
recommendation run, no panel. Plan 018's row is REJECTED (with its in-file
status block matching), PHASE4_DESIGN's Status paragraph carries the
amendment superseding §14.3's earlier "yes," and the roadmap's Phase 4 exit
criterion "AI can recommend high-impact next actions" is closed as
deliberately not pursued — §3.5's deterministic impact ranking carries its
substance, which is also why the spreadsheet-replacement criterion stands on
4a alone.

Consequences, stated so no future reader has to re-derive them:

- **Phase 4 comprises exactly one plan, 017 (`DONE`).** There is no 4b.
- The dashboard ships without a fourth panel by design, not temporarily:
  `suggestionsPanel` and every `recommendation*` identifier from the design's
  §5.6 list are permanently unrendered unless an owner reopens the scope.
- The four report types stay three: the recommendation report will never ride
  `jobs.apply_report_json`, so the key-disjointness set is final at three.
- `ReadinessSnapshot`, `UnblockerImpact`, and the frozen
  `SceneReadinessState` raw values remain the seams they were — Phase 5's
  package worklist still starts here — but nothing downstream may assume an
  advisory job or its report exists.
- Docs updated in the same commit: ROADMAP (the criterion struck through with
  the decision recorded; ROADMAP hash swept across Plans 001–009 and 012),
  PHASE4_DESIGN (amendment + hash swept across 017/018/019/021), PHASE5_DESIGN
  (three status/prose fixes + hash swept across 019/020/021/022),
  plans README (row + dependency notes). `check-docs.sh` green throughout.

## Phase 5 plans renumbered; Plan 018 retired — 2026-08-24

Following the owner's decision to drop the AI advisor, the rejected 4b plan
was removed entirely rather than kept as a tombstone, and the Phase 5 plans
renumbered down one: **former Plans 019–022 are now Plans 018–021** (storage
v6 → package operations/export → Generation section → scene prompt
generation). `scripts/check-docs.sh`'s PHASE4/PHASE5 globs moved with them.

Translation key for anything dated before this entry: a reference to "Plan
018" in older records means the rejected recommendations plan, which no longer
exists; "Plans 019–022" mean today's 018–021. The dependency notes in
`docs/plans/README.md` and both design contracts were rewritten to match in
the same commit, with the two designs' pinned hashes re-swept across every
plan that carries them.

## Plan 018 — Storage v6 and the scene-package model (Phase 5a) — in progress, 2026-08-24

### Step 3 record: the `SkillTreeOperations` move-down (design §3.7)

The pure tree primitives moved from FilmBrain's `PromptSkillMaterializer`
(`Prompting/PromptSkillMaterializer.swift`) down into FilmCore's
`Storage/SkillTreeOperations.swift`, exactly as contract F draws the line:

**Moved to FilmCore** (`SkillTreeOperations`, with `OperationError`,
`TreeManifest`, `manifest(of:)`, `fileSHA256(at:)`, `copyTree(_:from:to:)`):
the no-follow manifest walk (`RelativeProjectPath` safe-path validation,
symlink refusal), the sorted-manifest tree digest, and the contained tree
copy through `BundleContainment`.

**Stayed in FilmBrain** (`PromptSkillMaterializer`): descriptor construction,
the shared-copy cache layout keyed by digest prefix (`resolveSharedCopy`),
`clonefile(2)` staging with its `ENOTSUP`/`EXDEV` plain-copy degradation
ladder, and prefix lengthening. The materialiser now consumes the primitives
and maps their errors 1:1 onto its public cases, so every caller sees the
identical refusals as before.

**New on the materialiser:** the `expectedTreeSHA256` parameter and the
`.treeDigestMismatch(expected:actual:)` refusal. For an imported skill the
exact manifest the staging walk produces is compared against the stored
digest **before any copy or clone**, closing §8.6's check/use gap at the one
authoritative boundary. The shipped asset-prompt path passes nothing and
behaves byte-identically; the full FilmBrain suite ran green before and after
the move.

**Fixture split (§10):** safe-path, symlink (leaf and component), manifest
walk, full-digest ordering/stability, and contained-copy fixtures moved to
FilmCore's `SkillTreeOperationsTests`; the forced digest-prefix-collision and
cache-directory-resolution fixtures stay in FilmBrain beside the staging
machinery that owns them.

### Plan 018 — execution record — 2026-08-24

All six contracts landed; the plan's row is DONE. Nothing writes the new
tables yet — Plan 019 owns every operation and the exporter, Plan 020 the
Generation section, Plan 021 the job. What shipped:

- **Contract A** — `SchemaV6.swift` + `registerV6` + `rebuildProjectsV6`;
  `FilmCoreVersion.bundleSchema = 6`. The round-trip test proves carried
  tables byte-identical (projects' schema change excepted; its carried values
  compared explicitly) and Phase 1–4 derivations value-equal across v5 → v6.
  `MigrationV5Tests` moved to the current-schema constant where it pinned
  literals, the Plan 013-on-v4 pattern.
- **Contract B** — §4.4's names in `Domain/ScenePackage.swift`;
  `TargetProfileCatalog` with `seedance_2_5` + `generic`; the agreement test
  reads the vendored snapshot at test time only.
- **Contract F** — recorded above in the step 3 entry.
- **Contracts C/D/E** — the two-branch inversion, continuity intervals, the
  §3.3 predicate against P, the four reads, the observation entries, the
  builder with its committed golden fixture
  (`Tests/FilmCoreTests/Samples/scene-prompt-input-golden-v1.json`, digest
  `49cb17e1140e6961c610a37fc6a986f729a17181d17836956e50ee00740bb2d4`).

**Recorded interpretation — scene-scale reference attributes.** PHASE5_DESIGN
§3.2 derives each planned reference's role/exclusion/fidelity "from
`ReferenceAttributeRules.attributes`" but does not name the owning side, which
at scene scale has no requirement of its own. The derivation cites each
planned reference **as its own row** (owning side == target side), which keeps
every output inside the pinned tables without new rules: identities define
themselves at full preserve ("defines Nadia's facial identity"), looks
transfer their named traits onto their entity ("transfers the Injured onto
Nadia" — the attribute-transfer target is named, per the vendored doctrine),
locations partially preserve, props fully preserve. A future reversal of this
reading is a renderer change: it bumps `ScenePromptInputBuilder.schemaVersion`
and re-fires the golden-fixture tripwire.

**Drift sweep.** AGENTS.md gained one line after planning (`5749d35`,
iteration guidance); its pin was swept to `0081ad82…` across every plan that
carries it, in the same commit as this record. No other pinned hash moved.

**Owner gates confirmed**: §14.2 and §14.6 still read ACCEPTED in the design;
nothing in this plan needed a live gate or an acceptance run, so nothing was
deferred.

## Plan 019 — Package operations, skill import, and export (Phase 5a) — execution record — 2026-08-24

All four contracts landed; the plan's row is DONE. No live gates existed and none were
deferred. What shipped:

- **Contract A** — `createScenePrompt` (the §8.1 pre-flight plus in-transaction capture),
  `setScenePromptBody`, `deleteScenePrompt`/`restoreDeletedScenePrompt`, `setStyleBible`,
  `setGenerationTargetProfile`, all journaled and invertible through
  `EditPrimitives.perform`. New typed refusals carry §5.5's verbatim sentences.
- **Contract B** — `importSceneSkill` (copy → re-walk verify → one grouped import+select
  entry), the undo posture word for word (undo orphans the tree; redo re-verifies against
  `tree_sha256` or refuses `.importedSkillTreeMissing`), `selectSceneSkill`,
  `orphanedSkillTrees()`/`clearOrphanedSkillTrees(confirming:)`, and
  `verifySelectedSkillTree()` as the FilmCore run gate's early-feedback half.
- **Contract C** — `ScenePackageExporter` with the three grains, the staged/verified/
  atomic write, and the committed byte-exact expected package
  (`Tests/FilmCoreTests/Samples/expected-scene-package-v1/`; regenerate with
  `UPDATE_EXPORT_FIXTURE=1 swift test --filter ScenePackageExporterTests` and review).
- **Contract D** — the full §6.2 table asserted with undo legs.

**Recorded interpretation — the parity seam (STOP condition 2).** At scene scale there is
no AI attach yet (Plan 021's op); the "attach path's capture" today is exactly what §8.4
step 0 prescribes for it: `ScenePromptInputBuilder.snapshot(sceneID:in:)`, rebuilt inside
the writer's transaction. `createScenePrompt` consumes that one function for digest,
format version, and citation plan — there is no second path to fork. The parity test pins
the row's capture to that snapshot plus the same derivation's satisfied subset.

**Recorded interpretation — settings guards read ''/nil as unset.** PHASE5_DESIGN §8.3
says `''` is allowed for aspect ratio and resolution while §4.3 defaults the columns to
`''`; Plan 018's `TargetProfile.accepts` refused a non-empty-set value including `''`.
The storage guard now treats `nil` duration and `''` strings as unset (only a value
outside a declared set refuses), which leaves every existing catalog assertion standing.
A future validator change that demands presence is §8.3's business, not the catalog's.

**Recorded interpretation — the atomic replace.** POSIX `renameat` cannot replace a
non-empty directory, so "atomically replaces the destination" lands as the standard dance:
the previous export renames aside (still whole and readable at its old name only
momentarily), staging renames in, and any failure renames the previous export back before
throwing. The destination path never holds a partial package and nothing is ever deleted
before its replacement exists — the STOP-4 posture. The rename runs descriptor-relatively
through `BundleContainment.renameEntry`.

**Determinism decisions the design did not spell out:** duplicate requirement slugs get a
deterministic `-2`/`-3` suffix (`scene.json` carries the binding truth, per the Phase 2
path-material rule); the stale-confirm token the caller must pass is the reads' own reason
spelling (`inputs changed` / `older input format`) so UI copy quotes the store; the skill
sweep's `ClearedCacheSummary.filesRemoved` counts **trees**, not files, for this surface;
staging directories are materialized through one marker file written and removed inside
the containment walk (no mkdir primitive was added).

**Owner-gate confirmations:** §14.5, §14.6 (operation half), and §14.7 still read ACCEPTED
in the design. No drift pins moved; PHASE5/PHASE3/PromptSkills/AGENTS hashes verified OK
at start.

**Environmental note.** Adding source files to FilmCore under a stale
`Packages/FilmBrain/.build` can fail with spurious "cannot find X in scope" errors until
`swift package reset` runs there — the path-dependency build graph does not always notice
new files. If FilmBrain fails that way after a FilmCore commit, reset before suspecting
the code.

**Verification posture.** `./scripts/verify.sh` ran 2026-08-25 with every deterministic
lane green — FilmCore (758 tests), FilmBrain (124), app build, build-for-testing, and the
app unit bundles — and all nine UI lanes failing identically with "Failed to initialize
for UI testing … Timed out while enabling automation mode", the runner never starting.
That is the recorded environmental wedge from Plans 015/017 (remedy: reboot, then one
run); a single-lane retry reproduced it exactly. This plan touches no UI surface, so the
headless suites above carry its assertions of record; the clean UI leg remains owed to
the same reboot as Plan 017's outstanding run.

## Plan 020 — Step 1 record: the carried workshop suite — 2026-08-25

`Phase3WorkshopUITests` verified present (Plan 017 carried the Plan 015 debt; two cases:
the write-prompt walk and the human-variant walk). It was run before any Generation-section
shell work, per the plan's order. Result: four consecutive launches failed identically with
"Failed to initialize for UI testing … Timed out while enabling automation mode", zero test
cases executed every time — including after `ui-cleanup.sh`, cooldowns, and killing a stale
`testmanagerd`. That is the recorded environmental runner wedge from Plans 012/015/016/017
(remedy: reboot plus one clean run from an interactive Terminal), not a failure of the suite
or of any code under test. Per the standing posture the headless twins remain the assertions
of record; this plan's Step 5 UI walk inherits the same wedge posture, and the clean
`Phase3WorkshopUITests` run remains owed to the same reboot as Plan 017's outstanding leg.

## Plan 020 — The Generation section (Phase 5a) — execution record — 2026-08-25

**Step 1, both halves.** `Phase3WorkshopUITests` was verified present at start and run
before any shell work: the morning's four launches all hit the recorded automation-mode
wedge (zero cases executed), and the day's **first full gate run later executed it green**
("Executed 3 tests, with 0 failures") once the environment briefly recovered — the carried
debt is therefore not just attempted but observed passing on this commit. The environment
then degraded again exactly as the standing record describes (below).

**Landed.** The `.generation` section over the enumerated ripple (sidebar group, split-view
content/inspector arms, section-picker identifier); the §5.3 list (ordinal order, §3.3
package-state badges beside Plan 017's Asset Ready state as visibly distinct labels, state
filter, counts line naming the active profile, excluded scenes under their existing labels);
both deep links (`RevealTarget.scenePackage` in; unsatisfied reference rows out through the
reused `RevealTarget.requirement` — STOP 3 never triggered); the §5.2 package view
(project-wide profile picker, the §3.2 reference plan with greyed optional rows and the
inline over-limit refusal, read-only continuity, prompt panel over `createScenePrompt` /
`setScenePromptBody` / delete-newest, byte-exact Copy Prompt, containment-paying Reveal
References, Export Scene Package with §14.7's confirm naming the store's reason verbatim,
§14.6's import/select chooser); the Dashboard's Generation Packages block fed by the same
one-read beat as the list (STOP 4 structurally impossible); delta 8's one-line OVERVIEW
Stage 11 edit with the full pinned-hash sweep (001 by hand, 002–009, 011, 013, 014) green
under check-docs check 5 in the sweep commit; the export session doors FilmCore's exporter
doc comment reserved for this plan; Generate/Regenerate render nowhere (the §5.6 reserved
identifiers stay unrendered for Plan 021).

**Recorded interpretations.** The export report sheet presents paths/sizes only (§3.8's
derived-artifact rule — nothing is read back). The stale-confirm token flows from the
refusal's associated value, so UI copy quotes the store. `Export Sequence` renders as a
menu of the script's sequences (read on the refresh beat), each item enabled per §5.5's
"≥ 1 Generation Ready scene in it". The skill chooser collects the descriptor-relative
entry path after the folder pick; import auto-selects inside FilmCore, so ⌘Z is one step.
Section position: sidebar group between Manifest and Jobs; no ⌘-digit (position 11).
The package predicates read the loaded detail (the view's selection beat), matching how
the rendered surface actually decides enablement.

**Verification posture.** Final unfiltered `./scripts/verify.sh`: every deterministic lane
green — check-docs, FilmCore (758), FilmBrain (124), app build, build-for-testing, app unit
bundles (81, the eight `GenerationWindowModelTests` twins among them) — plus **eight of ten
UI suites green**, including the carried Phase 3 workshop walk. Two UI failures remain:
`Phase4ReadinessUITests`, which had passed earlier the same day on identical app code and
whose isolation rerun executed zero cases (pure wedge), and the new `Phase5GenerationUITests`
walk, which was debugged progressively through every logic hurdle (merge → Build → slot
approvals → section counts) across runs until only infrastructure exits remained — the
runner dying at a different point each launch ("Timed out while enabling automation mode",
"Restarting after unexpected exit") with no application crash reports. That is the terminal
form of the recorded degradation whose remedy is a reboot plus one clean run from an
interactive Terminal; the headless twins carry the assertions of record, and the walk's
clean pass joins Plan 017's outstanding reboot debt.

## Plan 021 — Scene prompt generation (Phase 5b) — execution record — 2026-08-25

**Landed.** The full §8 pipeline at scene scale, on the recorded branch and with every
deterministic gate green: `GenerateScenePromptTask` (`generateScenePrompt`, schema
`scene-prompt-v1.schema.json` + instructions `scene-prompt-v1.md`) through the **unchanged**
`StructuredJobRunner` (no runner edit — STOP 2 never came close); the three routing
branches of §3.7's fifth revision (bundled default under `seedance_2_5` pins the Seedance
2.5 sub-skill `skills/higgsfield-seedance-2-5/SKILL.md` and its omni-reference template
`templates/seedance/omni-reference-2-5.md`; an imported skill names only its own entry and
optional routing file; anything else routes to the entry alone); `ScenePromptValidator`
v1 with the universal coverage contract and the **profile-carried declaration-line rule**
(sixth revision: `TargetProfile` gained `declaresReferenceGrammar` — `seedance_2_5` true,
`generic` false; the bulk statement fails mechanically under Seedance and passes
coverage-only under Generic, fixture-pinned both ways); `ScenePromptRunGate` mirroring
§8.1's pre-flight; `ScenePromptApplier` with the step-0 digest guard, the one invertible
`attachGeneratedScenePrompt` entry (⌘Z reads "Undo Generate Scene Prompt"; the undo
bridge exempts it via `isAttachGeneratedScenePrompt`), the task-gated
`ScenePromptApplyReport` through the internal primitive (key-disjointness extended across
all four report types), and in-transaction parent completion; the atomic imported-skill
check at the materialiser boundary (`expectedTreeSHA256` from Plan 018 contract F, first
live caller) with the §10 race test mutating the tree between the gate passing and
materialisation — refusal leaves nothing staged; the `scene-prompt-` recorded-replay
branch beside Plan 016's, materialising a declaration-line-compliant body from each
request's own payload; §9's two disclosure blocks verbatim in
`ScenePromptDisclosureText`; Generate/Regenerate live behind `ScenePromptRunGate`'s
window-model mirror (the reserved identifiers render at last), with the `+PromptRun`
three-beat shape reused rather than paralleled; regeneration confirming over human edits
with the shipped copy, new row at max+1; and the Jobs arm (kind label, report line,
Revert exclusion).

**Recorded interpretations.** The scene run resolves the skill descriptor per selection:
an imported row builds the descriptor bundle-relatively and carries its stored
`tree_sha256` into the materialiser; the bundled default carries none. The window-model
gate verifies an imported tree for early feedback only — the staging walk stays
authoritative. The §8.6 race test exercises the boundary directly (gate check → mutate →
materialise) because driving a full Asset Ready project inside FilmBrain would duplicate
FilmCore's readiness fixtures; the coordinator seam is the same two calls. The schema's
`durationSeconds` is a required integer (§8.3 verbatim); "unset" admits via empty ratio/
resolution strings, exactly `TargetProfile.accepts`.

**Live gates: two, both deferred — unspent, never failed.**

1. **Schema probe** (`testLiveScenePromptSchemaPreflight`, opt-in under
   `FILMCAMP_RUN_LIVE_CODEX=1`): not spent — no operator approval was available at
   execution time. Recorded fallback standing: the schema follows `asset-prompt-v1`
   exactly (`additionalProperties: false`, `const` version, no arrays, no `maxLength`),
   the same posture Plan 016's unspent probe left.
2. **The §10 acceptance run**: not performed — it needs the operator's feature project,
   six approved requests judged in their external generation tool on the tiered bar, and
   per-run approval; none of that exists in this session. **Quality is therefore unknown
   — neither passed nor failed**, the Phase 3 closure posture. The endpoint consequence
   stands stated: Phase 5 is the product's primary endpoint, so this deferral leaves the
   roadmap's after-Phase-5 partner-validation gate without its evidence. Exported
   packages have never yet been proven in a real external tool.

**Step 6 skipped whole.** The batch driver is evidence-gated (§14.1): eligibility needs
the acceptance run scoring ≥ 5/6 *and* the owner's counted-spend approval. Neither
exists, so nothing batch-shaped renders anywhere — no eligible-set thinning surface, no
batch confirm sheet. Contract E's semantics are pinned in the design and remain unbuilt,
the Plan 016 posture; the door reopens with the acceptance evidence.

**Verification posture.** Final unfiltered `./scripts/verify.sh`: **ALL GREEN** — every
lane, all ten UI suites included, with `Phase5GenerationUITests` passing cleanly for the
first recorded time. The walk's standing failure was found and fixed during this
execution, not carried: its fixture selected the Asset Ready scene by the combined row's
`label`, and on this OS the `.accessibilityElement(children: .combine)` row exposes its
concatenated text in **`value`** while `label` reads empty — so the fixture could never
find an Asset Ready scene no matter how many approvals landed (diagnosed by dumping the
live AX attributes from inside the failing run). The selection now checks both
attributes; the approval sweeps were also hardened (four passes, each approve click
waits for the chip flip) so a dropped approval under slow automation fails loudly
instead of silently thinning the fixture. The failure was present identically on a
pristine `HEAD` worktree before the fix, confirming it was never a Plan 021 regression.
New tests: FilmBrain validator matrix (20 fixtures incl. the cross-profile pair), gate
battery, prompt-render three-branch fixtures, integrity/race suite; FilmCore apply suite
(happy path, step-0 drift determinism, §3.9 write surface, undo/redo byte-identical,
regeneration, revert-walk exclusion), report-type extension; app
`ScenePromptRunModelTests` headless twin (recorded end-to-end, gate refusals,
regeneration confirm discipline, Jobs arm), with the walk's reserved-identifier
negatives flipped to positives.

## Bundle schema v7 — entity-less continuity-event evidence repair — 2026-08-26

An operator PDF extraction exposed a Phase 1 contract mismatch: the structured-output
schema and `ContinuityEvent.entityID` both admit scene-wide events with no entity, while
the v2 `evidence` CHECK admitted a NULL `owner_entity_id` only for synopsis evidence. A
valid model event therefore reached apply and failed the whole atomic transaction with
SQLite constraint 19. V7 rebuilds `evidence` without changing any existing row: synopsis
evidence remains ownerless, event evidence may be owned or ownerless, and every other
subject kind still requires an owner. Ownerless event evidence joins synopsis evidence
on `SceneDetail`; entity-owned evidence remains on `EntityDetail`, preserving the exact
partition the evaluation snapshot uses for anchor rate. Regression coverage exercises
v6 → v7 row preservation and CHECK behavior, the AI apply path, and the read partition.

## Automatic canonical manifest refresh after analysis — 2026-08-26

The feature-screenplay acceptance pass exposed a misleading intermediate state: analysis
could complete with no deterministic manifest refresh, so every scene read `Asset Ready ·
0 / 0` until the operator discovered a separate Build action. Extraction apply now runs
the idempotent canonical-requirement plan after all appearance writes, inside the same
transaction. The refresh journal entry carries the extraction run id, so selective Revert
removes those requirements before reverting their supporting facts. The explicit Build
action remains available for later human edits that change manifest qualification.

## Validated AI output is active without a review queue — 2026-08-26

The product-owner review of the feature screenplay found the Proposed/Accepted pass to be
busywork: users already have direct Edit, Merge, Reject, Restore, and Add Missing correction
tools. Extraction and manifest apply now activate every row from their validated run before
the atomic commit completes. The rows remain `source = ai`, and `reviewed_at` remains NULL,
so the database never claims a person vouched for them. Bundle schema v8 performs the same
activation for existing projects. Entity and manifest pending-review banners, routine
Proposed/Accepted filters, and downstream “unreviewed” badges are removed from presentation;
Rejected and Unanchored exception filters remain available.

## Gemini CLI Nano Banana adapter — 2026-08-27

Plan 024's bespoke wrapper contract was replaced at the product owner's direction with
Gemini CLI's extension path. The implementation was checked against Gemini CLI 0.57.0,
its current headless/extension/policy documentation, and Nano Banana extension v1.0.12 at
upstream commit `5badc5aafea8751fe059a054b629cf2d989bceb1` (Apache-2.0). Film Camp
reimplements only the process adapter; no extension source was copied.

Discovery uses masked text from `gemini extensions list`, never its JSON output: Gemini
CLI's current JSON serializer includes resolved extension setting values when present,
while the text formatter emits `[REDACTED]` or `[not set]` for sensitive settings. The app
can therefore report the unset-key remedy without reading the key. Each generated
candidate runs in an isolated cache workspace with only `nanobanana` enabled and a
supplemental policy that denies every tool except the one required image operation.

The extension's current MCP contract supports text-to-image and editing one source image;
it does not support multiple simultaneous image references or explicit aspect-ratio and
resolution fields. Film Camp maps zero references to `generate_image`, one reference to
`edit_image`, expresses its fixed composition settings as positive prompt guidance, and
refuses more than one reference before discovery. No reference is silently omitted. No
live image-generation request was used while implementing or testing the adapter.

## Bundled multi-provider BYOK image helper — 2026-08-28

Plan 025 removes the Gemini CLI/Nano Banana extension adapter described immediately
above. Film Camp now embeds `filmcamp-image-helper`, a Node 24.14.1 single executable
built from locked `ai@7.0.83`, `@ai-sdk/google@4.0.56`, and
`@ai-sdk/openai@4.0.50` dependencies. Its protocol v2 exposes only the pinned Nano
Banana 2 (`gemini-3.1-flash-image`) and GPT Image 2
(`gpt-image-2-2026-04-21`) models, one typed image result per process, 1–4
sequential candidate requests, fixed 1K mappings, and the smart 2:3 / 16:9 /
1:1 aspect policy. Protocol v2 was introduced after live Nano Banana acceptance
showed that Google may return JPEG even though the prior helper always named the
candidate `.png`; the helper now reports the actual media type and uses a
truthful `.png` or `.jpg` suffix. FilmBrain accepts JPEG only for Google and
still requires the reported type, magic bytes, suffix, dimensions, and job
workspace to agree before FilmCore repeats import validation.

Provider keys are app-wide Settings credentials stored as non-synchronizing generic
password items with `WhenUnlockedThisDeviceOnly` accessibility. The helper receives the
selected key only in its length-prefixed stdin frame; argv and the minimal environment are
credential-free, and raw provider errors never cross its allowlisted terminal envelope.
Schema v10 stores provider/model/helper/settings/prompt-digest and ordered immutable
reference hashes without a prompt body, provider response, or credential. The run remains
while any candidate exists and is removed when its final candidate is permanently deleted;
undo/redo snapshots restore it with the candidate group.

A same-day product-owner amendment makes missing credentials actionable where generation
is blocked. Create Reference Image now expands a compact built-in provider picker and
blank secure field in place; saving through the existing app credential service writes
Keychain, selects that provider app-wide, and refreshes readiness without resetting or
closing the workflow. An already-configured alternate provider can be selected without
re-entering its key. The ready sheet still has no provider override. Both the sheet and
Settings render a green provider-specific API-key check, while Settings remains the only
Remove surface. No credential is revealed, copied, or pre-populated.

Provider-generation and candidate-import failures are rendered inline in the
open Create Reference Image workflow. A failure preserves the prompt, settings,
and pending candidates for correction or an explicit retry instead of raising a
Project Error alert behind the sheet.

The implementation was checked against the official AI SDK `generateImage`, Google
Gemini image-generation/model, OpenAI GPT Image 2/image-generation, and Node SEA
contracts pinned in Plan 025. All automated checks use synthetic framed requests and
recorded helper responses; none makes a provider request. Manual owner acceptance remains
one canonical and one referenced request for each provider.

Deterministic verification on 2026-08-28 used Xcode 26.6, Swift 6.3.3, XcodeGen
2.46.0, and Node 24.14.1. The helper passed TypeScript checking, seven fake adapter/
protocol tests, a production-dependency audit with zero reported vulnerabilities, its
SEA build/capability handshake, and nested signature validation inside the built app.
The build downloads the official host-architecture Node archive into the ignored build
cache and checks its pinned upstream SHA-256 before extraction or executable injection.
Release automation can request both `arm64 x86_64`; the same script verifies both
official archives, injects one protocol payload into each slice, combines them with
`lipo`, signs the final nested executable, and validates its capability handshake. That
universal path was exercised locally; ordinary development builds remain host-only.
The warm unfiltered repository gate was **ALL GREEN**: docs, 797 FilmCore tests, 139
FilmBrain tests, build-for-testing, all app unit/headless tests, and the UI smoke journey.
No live-provider or live-Codex flag was enabled. Plan 025 therefore remains IN PROGRESS
only for its four owner-run provider requests; the app intentionally has no paid
automated test lane.

The truthful-media/inline-error repair repeated TypeScript checking and all ten helper
tests, all 140 FilmBrain tests, build-for-testing, and all 104 XCTest plus ten Swift
Testing app/headless tests. The full-gate attempt also passed documentation and all 797
FilmCore tests. macOS did not enable UI automation for `SceneWorkspaceSmokeUITests` on
the scripted retry or a separate arm64 retry, so that UI test never began; there was no
UI assertion failure. No provider request or credential-bearing test was run.

## Scene-prompt quality modes and truthful run accounting — 2026-08-31

Scene prompt generation now defaults to Standard, a single Codex request instructed to
draft, silently review, repair, and return only a final paste-ready Higgsfield prompt.
High Quality remains available as an explicit two-request mode that adds the independent
review-and-rewrite pass. Both paths apply the same strict structural and semantic checks,
including rejection of escaped angle-bracket names and preservation of concise text,
logo, caption, and watermark exclusions.

The completion summary reports the selected mode, request count, per-request elapsed time,
and separate input, cached-input, cache-write, output, and reasoning token counts instead
of presenting one ambiguous aggregate. This was prompted by an observed two-request run
that took 4m 14s and reported 372,927 combined tokens; the new Standard path removes that
second request by default while retaining High Quality for deliberate independent review.

The same quality contract now applies the pinned Higgsfield Seedance 2.5 timing and audio
guidance directly. Each final card declares a selected total duration and consecutive
stage budgets that start at zero and finish at that total; deterministic validation rejects
missing totals, mismatched arithmetic, gaps, and overlaps. Dialogue remains verbatim in
braces, but every line must now be introduced by the canonical screenplay character name
and `says`; validation derives screenplay cue-to-line ownership and rejects both missing and
wrong speaker attribution. The prompt author also budgets an opening geography beat,
natural delivery time, camera travel, reaction, and a final hold instead of blindly choosing
the profile maximum.

## Scene-local screenplay overrides and explicit image references — 2026-08-31

The scene workspace can now edit the screenplay text used for one scene without rewriting
the imported script. Bundle schema v14 adds nullable `scenes.screenplay_override`; scene
reads, search, and scene-prompt input resolve it before the imported UTF-16 slice. The edit
is journaled and undoable, and changing it changes the scene-prompt digest.

Required References now provides Add Image Reference. It lists approved, active images
across the project independently of Manifest filters and links the selected canonical
entity or scene-specific variant into the open scene. The refreshed scene plan assigns the
normal `@Image N` designator, so the next generated prompt receives the added reference.

## Larger reference cards and in-place detail — 2026-08-28

Plan 026 replaces the compact horizontal reference strip with a 220–280-point adaptive
grid and keeps focused reference work inside the selected scene. Current images, saved
prompt guidance, requirement-scoped archives, restore/delete controls, and the existing
import/create/archive operations now share one responsive detail. A root-level dark
lightbox covers the rail as well as the workspace and dismisses through its close control
or Escape. Preview decoding remains descriptor-relative and integrity-checked at fixed
256, 512, and 2048-pixel tiers; no view performs a raw or unbounded project-file decode.

Deterministic verification passed documentation checks, all 797 FilmCore tests, all 140
FilmBrain tests, focused preview/detail/generation app tests, final build-for-testing, and
the complete new reference-card/detail/archive/lightbox UI journey. The two existing
scene-workspace UI methods also passed in the full-gate attempt. A later unfiltered app
bundle rerun hit the known macOS test-host connection hang before assertions. No live
Codex or paid provider request was made.
