# Plan 004: App shell and automation (Phase 1a)

> **Executor instructions**: Read `docs/PHASE1_DESIGN.md` in full first. This plan implements its
> §3.11 (every part except the editing controls of §6) and the UI half of §5.5. It changes no
> schema, no migration, no `ProjectTools` protocol, and no FilmBrain job code: it consumes
> `ProjectSession` and its `ProjectReading` / `ScreenplayImporting` / `ProjectObserving` roles as
> Plan 003 left them (including `entitySummaries`, `EntityDetail.locks`, `ProjectBundle.inspect`,
> and `upgradeSummary`); the one FilmCore addition it may make is the static
> `ProjectBundle.duplicate(from:to:)` named in contract A below. SwiftUI stays presentation-only — no
> GRDB, no `FilmScript`, no `Process`, no parsing. Follow the steps in order, run every
> verification command, and honor every STOP condition. Requires Plan 003 `DONE`. When complete,
> set this plan's row in `docs/plans/README.md` to `DONE`.
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
> Expected: all four print `OK`, and `git rev-parse --short HEAD` is descended from `02cf45c`.
> If a hash differs, stop for reconciliation when §3.11, §5.5, or the §3.9a roles changed. Harness
> discovery and execution are untouched here, so `docs/REFERENCE_PROJECTS.md` is not in the check.

## Status

- **Status**: DONE (2026-08-19)
- **Priority**: P1
- **Effort**: M–L, approximately 5–7 focused engineering days
- **Risk**: MED; the risks are per-window session ownership across `WindowGroup(for: URL.self)`,
  driving a one-way v1→v2 upgrade from the UI, and rewriting automation that Phase 0 depends on —
  not view volume
- **Depends on**: 003
- **Category**: feature / tests
- **Planned at**: commit `02cf45c` + Plans 002–003; design hash in the drift check
- **Live gates**: none; two **human** checks (Step 2's manual walk-through, Step 4's feature import), neither a deferral blocker. Nothing here calls Codex; status detection is discovery only. Every command
  must pass with no network and without `FILMCAMP_RUN_LIVE_CODEX`. One **human** gate exists
  (Step 4); its deferral policy is below.

## Why this matters

Plan 003 made parser facts real but left them invisible. This plan turns the Phase 0 demo window
into the multi-window breakdown shell the filmmaker actually uses — import, browse, inspect — and
re-points automation at the parser's counts so every later plan has a deterministic app harness.

## Current state (after Plan 003)

- Plan 003 left a **reduced** Phase 0 app: create / open / import (an `AppModel` method with no
  UI control) / close / reveal plus Codex status, no analysis UI, one shared `AppModel`,
  `AppServices.makeAdapter` and the `Resources/Samples` phase intact, `AppModelTests` rewritten to
  the no-AI flow (keeping the two Finder-URL tests), `Phase0FlowUITests` reduced to a single
  launch test so `AI Film Camp/UITests/` stays tracked for `project.yml`, and `finder-smoke.sh`
  already retargeted at v2 (create → import → close → move → reopen; `FinderSmokeReport` keeps
  003's full field list, which adds `sceneCount`, `characterNames`, `locationNames`). This plan
  replaces that shell; it does not start from Phase 0.

- Plan 003 `DONE`: schema v2, `ProjectBundle.create(at:name:)` (creates an **empty** project),
  `importScreenplay(from:actor:) -> ImportSummary`, the six-role `ProjectTools` composition,
  `ProjectObserving.changes()`, `StructuredJobRunner`, and the removal of the Phase 0 analysis
  task. Read those sources instead of re-deriving them.
- `AppServices.makeAdapter(status:)` is the recorded-vs-live adapter seam: **Plan 003 does not
  delete it, and neither does this plan**; Plan 007 extends it. No Phase 1a UI calls it.
- The app is still the Phase 0 shell — a multi-instance `WindowGroup` over `WelcomeView` with
  one shared `AppModel` and `ProjectView` (no analysis views remain after 003); `project.yml`
  ships `AI Film Camp/Resources/Samples` as a resources build phase and the app links whole
  packages rather than named products.
- `--film-camp-recorded <success|malformed>` takes a value today (`AppServices.RecordedMode`);
  `--film-camp-test-root` and the two Finder-smoke arguments are unchanged.
- Automation lesson (`docs/IMPLEMENTATION_NOTES.md`): UI tests launch with
  `-ApplePersistenceIgnoreState YES` and `-NSQuitAlwaysKeepsWindows NO`, production keeps window
  restoration, and multi-window queries must be window-scoped. The same note records a reverted
  experiment with a single `Window` scene that did not present under XCUITest — it ran **before**
  persistence was disabled and was never retried — so Step 1 re-tests that Welcome presents
  under XCUITest before building sections.
- `AppDelegate.openURLsHandler` is a one-shot closure today, assigned from `WelcomeView.onAppear`
  and flushed once by its `didSet`; with Welcome becoming a scene that closes and reopens, that
  assignment must move.
- This plan uses no reference-project seam (`docs/REFERENCE_PROJECTS.md` names none for the app
  shell), which is why its drift block omits that file.
- Pins unchanged, nothing new added: Xcode 26.6, Swift 6 with complete strict concurrency, macOS 15
  floor, XcodeGen 2.46.0, GRDB 7.11.1, `macos-26` CI runner.

## Contracts (normative)

Build §3.11 exactly as written there; the contracts below are only what this plan adds, decides, or
defers. Where §3.11 gives a string, use it verbatim.

### A. Coordinator, windows, data flow

- `AppCoordinator` (`@MainActor @Observable`) owns Codex status, Finder URL routing (it installs
  `AppDelegate.openURLsHandler` **once, at its own construction**, before any scene appears — never
  from a view's `onAppear`, which would re-flush or stale the one-shot queue), recent documents
  via `NSDocumentController.shared.noteNewRecentDocumentURL(_:)`, and the open
  `ProjectWindowModel`s keyed by **standardized + symlink-resolved** bundle URL.
- Scenes, **in this order in `body`**, using the explicit macOS 15 APIs rather than declaration
  order alone: `Window("Welcome", id: "welcome").defaultLaunchBehavior(.presented)` first, then
  `WindowGroup(for: URL.self).defaultLaunchBehavior(.suppressed)` for projects — never
  auto-presented on a cold launch; the coordinator opens it with `openWindow(value:)` for Finder,
  Open…, Open Recent, and New, always passing the **standardized, symlink-resolved** URL (SwiftUI
  matches an existing window by value equality, so a raw `/var/…` and a resolved `/private/var/…`
  would otherwise open twice). Welcome closes when a project window opens and reopens when the
  last one closes; opening a URL that is already open activates that window instead of opening a
  second session. There is no in-window Close Project; ⌘W closes the window.
- **Window bridge.** `AppCoordinator` installs one `ProjectWindowDelegate: NSObject,
  NSWindowDelegate` per project window at creation (via a `NSViewRepresentable` host whose
  `NSView` subclass captures `view.window` in `viewDidMoveToWindow`). It **preserves and
  forwards** the delegate SwiftUI already installed (captured as `next`; everything it does not
  implement is forwarded via `responds(to:)`/`forwardingTarget(for:)` — replacing SwiftUI's
  delegate outright would break group membership, `dismissWindow`, and restoration), sets
  `NSWindow.setAccessibilityIdentifier` (`projectWindow` / `welcomeWindow`), implements
  `windowWillClose(_:)` to run the model's teardown — `Task { try await session.close() }` is one
  of the two permitted detached tasks (Plan 005's undo bridge is the other), and the coordinator
  tracks it so `applicationShouldTerminate` awaits every outstanding close before replying (the
  Finder smoke's `lsof` check depends on this) — and, in Plan 005,
  `windowWillReturnUndoManager(_:)`. Plan 005 extends this delegate; do not build a second one.
- **Ownership.** `AppDelegate` (updated here) constructs and owns the `AppCoordinator` in
  `applicationWillFinishLaunching` — which precedes `application(_:open:)`, so the one-shot URL
  handler is installed before any Finder URL arrives and before any scene appears — exposes it
  to `AIFilmCampApp` (a `@State` default cannot reference the adaptor property), and implements
  `applicationShouldTerminate` as `.terminateLater` + `NSApp.reply(toApplicationShouldTerminate:
  true)` once the tracked closes finish.
- **Restoration.** Production keeps window restoration, so SwiftUI re-presents project windows
  on relaunch **without** the coordinator's `openWindow`. The project root view therefore adopts
  its URL: `.task(id: url)` calls `AppCoordinator.adopt(url:)`, which runs the same `inspect` →
  v1 modal → open path as a Finder open (so a v1 bundle can never be migrated without the
  modal), and calls `dismissWindow` on Cancel or on a missing/unreadable bundle with a
  recoverable error; once the first adoption succeeds the coordinator dismisses `welcome`, which
  `.defaultLaunchBehavior(.presented)` had shown.
- Title = project name; subtitle = script display name or `No screenplay`;
  `.navigationDocument(bundleURL)` for the proxy icon.
- `ProjectWindowModel(session:undoManager:)` (`@MainActor @Observable`) is constructible in unit
  tests over a temporary bundle. Every command is an **awaitable async method** (no fire-and-forget
  `Task` inside a command); it reads through the session's `ProjectReading`, refreshes from
  `changes()`, and exposes no GRDB or `FilmScript` type. The `UndoManager` is stored and passed
  through unused here — Plan 005 registers on it.
- **Duplicate Project…** is invoked from an open project's File menu (that is where §5.5's refusal
  copy sends the user), so it must work on an open bundle: `AppCoordinator.duplicateProject(at:to:)`
  closes that window's session (`ProjectSession.close()`), copies the bundle with
  `ProjectBundle.duplicate(from:to:)` — a static FilmCore copy of a closed bundle directory, no
  schema or migration change, added here if Plan 003 did not — then reopens the original in the
  same window and leaves the copy closed. Reopening yields a new `ProjectSession`, so the
  coordinator **replaces the `ProjectWindowModel` in place**: a new model over the new session,
  `ProjectWindowDelegate` rebound to it, `undoManager.removeAllActions()`, and the previous
  section and selection ids restored (`AppShellTests` asserts an empty undo stack and a surviving
  section). From the Welcome window (`duplicateProjectButton`) it duplicates a closed bundle
  chosen in an open panel. It refuses only while the source is mid-import (the model's in-flight
  flag) or mid-run (`runs()` reports a non-terminal or `paused` parent).
- `ProjectBundle.inspect(at:) -> BundleInspection` (schema version from the `project.db` header,
  never opening the database) is Plan 003's; if it is absent, add exactly that and nothing else.

### B. Sections, lists, inspector — read-only here

- `NavigationSplitView` sidebar → content → inspector with §3.11's **nine sections in four groups**
  (Scenes · Characters, Locations, Props, Vehicles, Creatures, Objects · Continuity · Jobs — ⌘1…⌘9
  in that order), its empty states verbatim except that the entity string substitutes the
  section's plural noun (“Vehicles appear after you analyze the screenplay, or add one with +.”;
  the `+` control arrives in Plan 005 — do not reword further and do not add the control), and the
  Scenes empty state as a drop target.
- Scenes use a `Table` with sortable Ordinal, Scene #, Heading, INT/EXT, Location, Time; the detail
  shows `sceneText(id:)` read-only and selectable with evidence highlighting, the synopsis as
  static text (§3.11 as revised: Plan 005 adds the editor, since `setSynopsis` is a
  `ScreenplayEditing` op that does not exist yet), entities by role, and — deferred to Plan 005
  with the state editors — "states active in scene".
- Characters / Locations / Props / Vehicles / Creatures / Objects share **one** `List` over
  `ProjectReading.entitySummaries(…)` (name, review badge, lock icon from `isLocked`, appearance
  count) and **one** inspector over `entity(id:)`. Both are read-only in this plan: review badges,
  lock icons, relevance, aliases, appearances, states, events, relationships, evidence jump links,
  locks, and the provenance line (`ConfidenceBand` for any confidence) all render; nothing is
  editable, nothing is added or deleted, Return and Delete do nothing, and the Entity menu does
  not exist yet (Plan 005 adds all of it).
- Continuity is a read-only list over `ProjectReading.continuityEvents()` (Plan 003; entity-less events shown with an em dash). Jobs lists **runs** only (`runs()`), expandable to child rows,
  with §3.11's read-only affordances built now over `jobHistory()`: Show Log in Finder and a
  copyable job UUID; the run card and apply report arrive in Plan 007. It is empty until then.
- `.searchable` is scoped per section: scenes match heading + text, entities match name + aliases.
  ⌘1…⌘9 switch sections, ⌘I toggles the inspector. Multi-selection shows a count and no actions.
  Confidence renders Low / Medium / High, never a raw float.
- `RevealTarget` (`Support/RevealTarget.swift`) with `.scene(id, highlight: UTF16Range?)` and
  `.entity(id)`; `ProjectWindowModel.reveal(_:)` switches section, sets selection, scrolls, and
  flashes the span. Each section keeps its own last selection.

### C. Menus, Settings, accessibility

- One `Commands` block: **File** (New Project ⌘N — `CommandGroup(replacing: .newItem)`, because
  `WindowGroup` otherwise contributes its own New Window ⌘N; Open… ⌘O, Open Recent, Import
  Screenplay… ⇧⌘I, Duplicate Project…, Reveal in Finder, Close ⌘W); **Edit** (system Undo/Redo
  with action names, Delete — inert here; Plan 005 adds Show Edit Journal…); **View** (Toggle
  Sidebar, Toggle Inspector). No Entity menu (Plan 005). **Open Recent** has no automatic menu
  without `DocumentGroup`, so it is a `CommandGroup(after: .newItem)` submenu built from the
  `@Observable` coordinator's `recentURLs: [URL]` — refreshed in the same method that calls
  `noteNewRecentDocumentURL(_:)` and on Clear Menu (`NSDocumentController.recentDocumentURLs`
  itself is not observable, so a menu built from it would never update within a session) —
  each item calling `AppCoordinator.open(url:)`; presentation wiring only.
- `Settings` scene (⌘,) with General / Codex / Advanced tabs. Advanced shows
  "Model and concurrency settings arrive with AI analysis." until Plan 007 fills it.
- The Codex status view is retained. **No AI action exists anywhere in the UI.**
- Every actionable control carries an accessibility identifier **and** label; icon-only controls
  (lock, badges) carry labels; evidence highlighting uses semantic colors. Identifiers the tests
  use: `welcomeWindow`, `projectWindow`, `createProjectButton`, `openProjectButton`,
  `codexStatusLabel`, `refreshCodexButton`, `importScreenplayButton`, `importSummarySheet`,
  `importedSceneCount`, `importedCharacterCount`, `importedLocationCount`, `sectionSidebar`,
  `sceneTable`, `sceneTextView`, `entityList`, `entityInspector`, `migrationUpgradeButton`,
  `duplicateProjectButton`. The two window identifiers are set on the `NSWindow` by the window
  bridge (contract A); SwiftUI's `.accessibilityIdentifier` cannot name a window.

### D. Import UI and the v1 upgrade modal (§5.5)

- Three entry points, one code path: File ▸ Import Screenplay… ⇧⌘I, the `importScreenplayButton`,
  and a drop on the Scenes empty state. All call
  `ScreenplayImporting.importScreenplay(from:actor: .human)` on the window's session. The code path
  (`ProjectWindowModel.importScreenplay(from:)` + the panel service) is built in **Step 2**, so the
  sections can be verified over real data; the sheet, drop target, and upgrade modal follow in Step 3.
- The open panel and the drop destination accept `.fountain`, `.fdx`, **and `.txt`** (§3.2: plain
  text goes through the Fountain parser; Plan 002's `noSceneHeadings` path is reachable only this
  way): `allowedContentTypes = [.plainText, .xml]` plus an `NSOpenSavePanelDelegate`
  `panel(_:shouldEnable:)` that enables only the `fountain`/`txt`/`fdx` extensions (the drop
  destination applies the same extension predicate) — not the app's own imported UTI alone,
  which loses to any installed screenwriting app's exported declaration and would grey the file
  out, and not `allowsOtherFileTypes`, which is a save-panel property. The app never sees a
  `ScreenplayDocument` and never parses.
- On success, an **import summary sheet** (`importSummarySheet`) shows format, scenes, characters,
  locations, sequences, and parser warnings, then the window reveals the first scene.
- When a script already exists: if `canReplaceScreenplay()` is `true`, show a confirmation naming
  Replace as non-invertible and, on confirm, import; otherwise call `importScreenplay` anyway and
  present the thrown `.replaceRefused(reason:)` text verbatim — `canReplaceScreenplay()` returns a
  `Bool`, the wording lives in the error, and there is no separate replace entry point. Refusals
  while a run is non-terminal or paused (`.importRefusedDuringRun`) surface as-is.
- **v1 upgrade modal**: on open, `ProjectBundle.inspect(at:)` reporting schema 1 shows a **one-way**
  modal naming what changes — scenes are rebuilt from the parser; model synopses are dropped when
  the scene count differs — with Cancel / Upgrade (`migrationUpgradeButton`). Cancel opens nothing.
  Upgrade opens the bundle (which migrates) and then shows an **upgrade** sheet built from
  `ProjectSession.upgradeSummary` (Plan 003): from/to version, scene, entity and sequence counts,
  how many synopses were dropped, and the persisted parse warnings. It is not the import sheet —
  `open` yields a session, not an `ImportSummary`, and warnings exist only because Plan 003
  persists them.

### E. project.yml / XcodeGen

All changes go in `project.yml`, which stays canonical. `xcodegen generate` rewrites
`AI Film Camp/Resources/Info.plist`; commit it and the regenerated `AI Film Camp.xcodeproj` so CI's
`git diff --exit-code -- "AI Film Camp.xcodeproj"` stays green.

1. Replace the app target's package dependencies with explicit products: `{package: FilmCore,
   product: FilmCore}`, `{package: FilmCore, product: ScreenplaySamples}`, `{package: FilmBrain,
   product: FilmBrain}`. The app target declares **no `FilmScript` product dependency and no app
   source imports `FilmScript`** (it is linked transitively through `FilmCore`; Step 1's grep is
   the check). Linking `ScreenplaySamples` ships
   the small synthetic parser samples and their keys in Release; that is accepted (a few hundred
   KB of original text) in exchange for one copy of `camp-signal.fountain` in the repo.
2. **Keep** the `AI Film Camp/Resources/Samples` sources entry and its `buildPhase: resources`: the
   recorded adapter still needs `recorded-success.jsonl` and `recorded-result.json`. Delete the
   now-duplicated `camp-signal.fountain` **and `recorded-malformed.json`** (contract F retires
   `RecordedMode`, its only reader) and update `Samples/README.md`; `AppServices.sampleURL()` becomes
   `ScreenplaySamples.url(named: "camp-signal.fountain")` (full filename, see Plan 002).
3. Add `UTImportedTypeDeclarations` for `com.aifilmcamp.fountain` (conforms to
   `public.plain-text`, extension `fountain`) and `com.finaldraft.fdx` (conforms to `public.xml`,
   extension `fdx`) as **imported** types only. `CFBundleDocumentTypes` and
   `UTExportedTypeDeclarations` are unchanged — the app does not claim to open screenplays.
   `Support/ScreenplayUTTypes.swift` resolves them with `UTType(importedAs:)`, which traps when the
   declaration is missing — another reason the regenerated `Info.plist` is committed.
4. Give **both** `AI Film CampTests` and `AI Film CampUITests` a second `sources` entry —
   `path: Packages/FilmCore/Tests/FilmCoreTests/Samples/v1-phase0.aifilm`, **`type: folder`**
   (XcodeGen's default `group` would flatten the bundle's files into the test bundle root; `.aifilm`
   is a package only to Finder), `buildPhase: resources` — (Plan 003's `.gitignore` negations keep
   it tracked), so the unit test can copy the v1 bundle to a temporary directory and drive the
   upgrade path and the UI test can copy it into `--film-camp-test-root` before launch; the app
   target itself does not get it.

### F. Automation

- `--film-camp-recorded` becomes a **flag** with no value; `AppServices.RecordedMode` is deleted
  and `recorded-malformed.json` with it (Plan 007 adds its own recorded samples and injects
  failures through `--film-camp-recorded-fail`, never through a mode). The flag selects the
  automation panel service (no `NSSavePanel`/`NSOpenPanel`), a synthetic ready Codex status, and
  `ProjectPanelService.screenplayToImport()` returning `AppServices.sampleURL()`. The automation
  branch allocates **sequential** destinations under `--film-camp-test-root` —
  `destinationForNewProject()` yields `Phase Zero.aifilm` first (the name `scripts/finder-smoke.sh:73`
  hardcodes), then `Phase Zero 2.aifilm`, …; `projectToOpen()` returns the most recently allocated;
  a new `destinationForDuplicate(of:)` returns `<name> copy.aifilm` — so the UI tests' second
  project and Duplicate cases need no new launch argument (the STOP condition stays intact).
  `--film-camp-test-root` and the Finder-smoke arguments are unchanged.
- The recorded flow stays **create empty project → import bundled sample** (Plan 003 already moved
  it there); this plan re-points it at `AppCoordinator.runFinderSmoke`.
- `makeAdapter` under the flag returns the `RecordedHarnessAdapter` over `recorded-success.jsonl`
  and `recorded-result.json`. Because no UI calls it, `AppShellTests` constructs it once so the
  seam cannot rot.
- `AppCoordinator.runFinderSmoke`, `scripts/finder-smoke.sh`, and the UI tests assert: **2 scenes**;
  characters `Maya` and `Eli` (display case, aliases `MAYA` and `ELI`); locations `Camp Cabin` and
  `Camp Dock`; `PRAGMA user_version = 2`; `SELECT count(*) FROM jobs` = 0.
- The smoke script's v2 snapshot SQL is Plan 003's; this plan confirms it, adds the assertion that
  `screenplay/camp-signal.fountain` exists with a matching `project_assets.relative_path`, drops
  the recorded flag's value argument, and keeps `FinderSmokeReport`'s 003 field list unchanged (which adds `sceneCount`,
  `characterNames`, `locationNames`).
- UI tests launch with persistence disabled and scope every query to a window.

## Target file layout (additions, changes, deletions)

```text
AI Film Camp/
  App/     + AppCoordinator.swift, ProjectWindowModel.swift, ProjectWindowDelegate.swift (window bridge),
           RecentDocumentsMenu.swift, AppCommands.swift, SettingsView.swift;
           AIFilmCampApp, AppDelegate (owns the coordinator; applicationShouldTerminate), and
           AppServices (ProjectPanelService destinations) updated; AppModel.swift DELETED
  Views/   + ProjectSplitView, Scenes/{SceneTableView,SceneDetailView},
           Entities/{EntityListView,EntityInspectorView,ProvenanceLabel} (Plan 005 extends all three), Continuity/ContinuityListView,
           Jobs/RunsListView, ImportSummarySheet, MigrationUpgradeSheet; WelcomeView and
           CodexStatusView updated; ProjectView.swift DELETED
  Support/ + ScreenplayUTTypes.swift, RevealTarget.swift
  Resources/Samples/  camp-signal.fountain and recorded-malformed.json DELETED,
           recorded-success.jsonl + recorded-result.json kept, README.md updated
  Tests/AppShellTests.swift (replaces Plan 003's rewritten AppModelTests.swift — deleted in Step 1)
  UITests/Phase1ImportUITests.swift (replaces Plan 003's reduced Phase0FlowUITests.swift)
project.yml, AI Film Camp.xcodeproj, scripts/finder-smoke.sh   updated per contracts E and F
```

## Existing tests that break, and how each is rewritten

| File | Change |
|---|---|
| `AI Film Camp/Tests/AppModelTests.swift` (Plan 003's rewrite) | Replaced by `AppShellTests.swift`: create → import → 2/2/2; a second Finder open of the same URL activates the existing window model instead of loading a second session; the URL handler is installed once at coordinator construction; a v1 bundle (copied from the new test resource) reports upgrade-required, is not mutated by `inspect`, and opens with a non-nil `upgradeSummary` after Upgrade; the window model refreshes after a `changes()` emission; `duplicateProject` closes, copies, and reopens an open bundle and copies a closed one; `makeAdapter` under the recorded flag returns an adapter. |
| `AI Film Camp/UITests/Phase0FlowUITests.swift` (Plan 003's reduced launch test) | Replaced by `Phase1ImportUITests.swift`: Welcome presents at launch; create → import bundled sample → summary shows 2/2/2 → selecting a scene shows its text and characters → close and reopen shows the same counts → a second project opens in its own window and Welcome closes → Duplicate Project… on the open project produces a copy and the original stays open → opening a v1 bundle shows the modal, Cancel opens nothing, Upgrade opens it with the upgrade sheet. Window-scoped queries (`projectWindow`/`welcomeWindow`), persistence disabled. |
| `scripts/finder-smoke.sh` | Adds the asset assertion and drops `--film-camp-recorded`'s value argument; the v2 snapshot SQL is Plan 003's. |

## Steps

### Step 1: Coordinator, window lifecycle, project.yml

Implement contract A (scenes with explicit launch behavior, the window bridge, `AppDelegate`
ownership, restoration adoption, Duplicate) and contract E; delete `AppModel`, the Phase 0
project view, **and `AppModelTests.swift`** (it references `AppModel`, and `xcodebuild test`
compiles the unit-test target even under `-only-testing`; `AppShellTests` lands in Step 3); put a
placeholder body in the project window so the app builds before contract B lands. Replace
`Phase0FlowUITests.swift` with a first `Phase1ImportUITests` case that only asserts the Welcome
window presents at launch.

**Verify**:

```bash
xcodegen generate --spec project.yml
git diff --exit-code -- "AI Film Camp.xcodeproj" || echo "commit the regenerated project"
xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -only-testing:"AI Film CampUITests" test
grep -rn "GRDB\|FilmScript\|Process(" "AI Film Camp/App" "AI Film Camp/Views" "AI Film Camp/Support" \
  "AI Film Camp/Tests" "AI Film Camp/UITests"
```

Expected: the build succeeds; after committing the regenerated project the diff check is clean;
Welcome presents under XCUITest and no project window opens on a cold launch; the `grep` prints
nothing; `plutil -p "AI Film Camp/Resources/Info.plist"` shows both UTIs under
`UTImportedTypeDeclarations` and an unchanged `CFBundleDocumentTypes`.

### Step 2: Import code path, sections, inspector, reveal, menus, Settings

Implement contract D's single import code path (menu item + `ProjectWindowModel.importScreenplay(from:)`
+ panel service; no sheet or drop target yet), then contracts B and C over `ProjectReading` and
`changes()`.

**Verify**: run Step 1's `xcodegen` / `xcodebuild … build` / `grep` block again (it must stay
green), then the **human check**: launch the Debug app, create a project, and confirm each
section's empty state; import the bundled sample via File ▸ Import Screenplay… and confirm the
sortable scene `Table`, the scene text, the entity list with appearance counts, the read-only
inspector with no editing control, scoped `.searchable`, ⌘1…⌘9, ⌘I, and Open Recent listing the
project. The same assertions become `Phase1ImportUITests` cases in Step 3.

### Step 3: Import UI, upgrade modal, automation, and tests

Implement the rest of contract D (summary sheet, drop target, replace confirmation, v1 upgrade modal and sheet) and contract F, plus `AppShellTests` and the remaining `Phase1ImportUITests` cases per the rewrite table.

**Verify**:

```bash
xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
./scripts/finder-smoke.sh
```

Expected: app unit and UI tests pass, including the v1 case against Plan 003's checked-in v1 sample
bundle (now an app-test resource, copied to a temporary directory first), the Duplicate and modal
UI cases, and every refusal path; the smoke creates a project, imports the sample, closes, moves
the package, reopens it, and reports contract F's snapshot unchanged.

### Step 4: Feature-length manual acceptance and full verification

Import an operator-supplied feature-length screenplay (Fountain, and FDX if available) into a
project **outside** the repository; browsing it must not lag. Record scene count, entity counts,
import wall time, and parser warnings in `docs/IMPLEMENTATION_NOTES.md` — numbers only, **no
screenplay text**, no title, no path. The screenplay is never committed. Update `README.md` if its
description of the app is now wrong.

**Human-gate deferral policy**: this is the plan's only human gate and no automated gate depends on
it. If the operator has no screenplay to hand when everything else is green, record the deferral in
`docs/IMPLEMENTATION_NOTES.md` and still mark the plan `DONE`.

**Verify**:

```bash
./scripts/verify.sh
git status --short
```

Expected: exit 0; only intentional source, project, `Info.plist`, script, and documentation changes
are listed (CI diffs only the `.xcodeproj`, so an uncommitted `Info.plist` would surface here, not
there); no `.aifilm` package, screenplay, DerivedData, log, result, or secret is staged.

## Done criteria

- [ ] `./scripts/verify.sh` and `./scripts/finder-smoke.sh` exit 0; the regenerated `.xcodeproj` and
  `Info.plist` are committed and CI's diff check passes.
- [ ] Welcome is the first scene and presents at launch while the project group is suppressed;
  several projects stay open at once, each in its own window, session, and `UndoManager`; Welcome
  closes and reopens per contract A; a duplicate Finder open activates the open window (canonical
  URLs); ⌘W releases the session through the forwarding window bridge and quit awaits outstanding
  closes; restored windows adopt through `inspect`; Duplicate replaces the model and clears undo;
  title, subtitle, and `navigationDocument` are set.
- [ ] The shell matches §3.11 as revised: nine sections in four groups, empty states verbatim with
  the per-kind noun, sortable scene `Table`, entity list over `entitySummaries`, scoped
  `.searchable`, ⌘1…⌘9, ⌘I, `RevealTarget`, a working Open Recent, Duplicate Project… for open and
  closed bundles, Show Log / copy UUID in Jobs, the `Commands` block, the `Settings` scene,
  identifiers **and** labels (window identifiers via the bridge).
- [ ] The entity inspector, Continuity, and Jobs are read-only; no Entity menu, no rename, delete,
  merge, split, lock, accept, or reject control exists; no AI action exists; Codex status is visible.
- [ ] ⇧⌘I, the button, and a drop on the Scenes empty state all import `.fountain`, `.fdx`, and
  `.txt` through `importScreenplay(from:actor:)` and show the summary sheet; replace is confirmed and
  refusals surface FilmCore's thrown text unchanged.
- [ ] A v1 bundle shows the one-way upgrade modal before anything is migrated; Cancel opens nothing;
  Upgrade opens, migrates, and shows the summary.
- [ ] The two screenplay UTIs are imported declarations only and absent from `CFBundleDocumentTypes`;
  the app links `FilmCore`, `ScreenplaySamples`, and `FilmBrain` and declares no `FilmScript`
  product (linked transitively only); no GRDB, `Process`, or `FilmScript` symbol appears in any
  app-target source.
- [ ] `AppServices.makeAdapter` still exists with both branches and is covered by a test;
  `RecordedMode` and `recorded-malformed.json` are gone; automation uses the `--film-camp-recorded`
  flag and the bundled sample; smoke and UI tests assert 2 scenes, `Maya`/`Eli`, `Camp Cabin`/`Camp
  Dock`, `user_version = 2`, and zero jobs.
- [ ] The feature-length import is recorded in `docs/IMPLEMENTATION_NOTES.md` with no screenplay
  text, or its deferral is recorded there.
- [ ] No editing operation, lock, extraction, scorer, storage change, or Phase 2 concept was added;
  `docs/plans/README.md` marks Plan 004 `DONE`.

## STOP conditions

- The `docs/PHASE1_DESIGN.md` hash differs and §3.11, §5.5, or §3.9a changed.
- The UI cannot be built without importing GRDB or `FilmScript` into the app target.
- `WindowGroup(for: URL.self)` cannot give one `ProjectSession` per window with deterministic
  teardown on ⌘W through the window bridge (report the leak or the double-open rather than falling
  back to one window), or the Welcome `Window` scene does not present under XCUITest with
  persistence disabled.
- Reading a v1 bundle's schema version mutates it, so the upgrade modal cannot be shown before
  migrating.
- The Finder smoke or the UI tests cannot be made deterministic without a new launch argument that
  §3.11 does not name.
- A verification command fails twice after one reasonable scoped correction.
- Work expands into editing, locks, provenance beyond display, chunking, extraction, or any change
  to storage, migrations, or the job runner (Plans 003, 005, 007).

## Maintenance notes

- Keep the entity list and inspector one shared view per §3.11; Plan 005 adds editing to that single
  pair, not to per-kind copies.
- Leave `makeAdapter`, the recorded samples, and the Jobs section as empty seams rather than
  half-implemented AI: Plan 007 fills all three and appends "→ recorded extraction run → review" to
  the automation flow.
- Every window command stays awaitable — the UI tests and `AppShellTests` depend on there being no
  fire-and-forget work to race; the one detached task is the bridge's `windowWillClose` teardown,
  which the coordinator tracks.
- `ProjectWindowDelegate` is the single AppKit bridge per window; Plan 005 adds
  `windowWillReturnUndoManager` to it rather than installing a second delegate.
