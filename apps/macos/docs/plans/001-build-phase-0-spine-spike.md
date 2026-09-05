# Plan 001: Prove the Phase 0 spine end to end

> **Executor instructions**: Follow this plan in order. Run every non-live
> verification command and confirm the expected result before moving on. The
> live-gate policy below defines the only allowed deferrals. If a STOP condition
> occurs, stop and report it; do not improvise a larger architecture. When the
> plan is complete, change its row in `docs/plans/README.md` to `DONE`.
>
> **Drift check (run first)**: this plan was written before the workspace had
> Git metadata. Confirm that the three intent/reference documents still match the planning
> snapshot:
>
> ```bash
> printf '%s  %s\n' \
>   1f0e224d9d668bc10fa01ab55bf60e115b14bafd0931eb81c26d152d5a4467ac docs/ROADMAP.md \
>   8660b7114aa507a98ec2cf621176355cb912b749ff3b84395e6f4af6fb927691 docs/OVERVIEW.md \
>   282b1ae714029b96e932bff1eba236df0e05b76abc1fe6b434f90f11ca418d46 docs/REFERENCE_PROJECTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected at planning time: all three print `OK`. **This plan is complete;
> the hashes are the historical snapshot it was planned against, and they no
> longer match — the intent documents have moved on with Phase 1. Nothing here
> needs reconciling.** Read this plan as a record of what Phase 0 built, not as
> work to execute. Note that the vocabulary changed afterwards: what this plan
> calls the Phase 0 *fixture* (`phase0-fixture.fountain`, `fixtureURL:`) is now
> the bundled *sample* (`camp-signal.fountain`, `sampleURL:`).

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: L, approximately 10–12 focused engineering days
- **Risk**: MED-HIGH; the risks are process discovery from Finder, CLI protocol
  drift, and atomic persistence rather than UI complexity
- **Depends on**: none
- **Category**: direction / architecture / tests
- **Planned at**: no Git commit (unversioned workspace), 2026-08-18; intent-doc
  and reference-guide hashes are recorded in the drift check

## Why this matters

Phase 0 is the smallest vertical proof of the product's defining architecture:
a Finder-launched local macOS app discovers the filmmaker's Codex installation,
sends a fixture screenplay through one structured batch job, distrusts and
validates the result, and commits canonical project state atomically. Success
de-risks all later phases. Failure should identify a specific broken seam—bundle
storage, CLI discovery, process execution, structured output, validation, or
transactional persistence—before the richer film ontology is built.

The plan implements the Phase 0 exit criteria and preserves the FilmBrain,
cross-cutting validation, AI architecture, and project-storage boundaries in
`docs/ROADMAP.md`, under the product principles in `docs/OVERVIEW.md`.

## Definition of the Phase 0 outcome

After implementation, a person can:

1. Launch the Debug app through LaunchServices/Finder, not from Xcode.
2. See whether Codex is installed, authenticated, compatible, and exposes the
   capabilities the analysis job requires.
3. Create `My Film.aifilm`, containing `project.db` and the documented bundle
   directories.
4. Confirm the privacy disclosure and run `analyzeScreenplay` against the
   bundled fixture.
5. See coarse live progress, completion, cancellation, or an actionable error.
6. See persisted scenes, characters, and locations only after the result passes
   JSON Schema, typed decoding, and semantic validation.
7. Quit, relaunch, and open the same project with the same results.
8. Close the project, move the entire `.aifilm` package elsewhere, and reopen it
   without repairing paths.
9. Feed a malformed recorded result through the same pipeline and observe a
   failed job with canonical rows unchanged.

## Current state

The workspace contains only documentation plus repository instructions:

- `AGENTS.md` — workflow, architecture, product, and verification guardrails.
- `docs/ROADMAP.md` — staged product and architecture decisions.
- `docs/OVERVIEW.md` — product principles, storage layout, and harness-first
  boundary.
- `docs/REFERENCE_PROJECTS.md` — advisory Swift harness patterns, local source
  paths, adoption rules, and explicit non-adoptions.
- `docs/plans/` — this plan plus a redacted Codex 0.146.0 capture set at
  `docs/plans/captures/codex-0.146.0-2026-08-18/`. The captures are planning
  evidence, not an implementation package; copy the applicable files into the
  FilmBrain fixture directory when it exists.

Four downloaded source snapshots are available outside the workspace at
`../aifilmcamp-app-references/`. They have no Git metadata and are not project
dependencies.

There is no `.git`, Xcode project, Swift package, test target, CI workflow,
implementation fixture directory, or build command. At planning time the
machine had Xcode 26.6, Swift 6.3.3, XcodeGen 2.46.0, and Codex CLI 0.146.0.
Those observations and captures help bootstrap the spike but are not a
substitute for checked-in requirements and executable tests.

## Live-gate policy

Every command or manual check that uses the operator's logged-in Codex account
requires explicit approval immediately before it runs. Lack of approval defers
only these live gates: the Step 4 schema preflight, the Step 6 live adapter test,
and the live portions of the Step 8 manual acceptance matrix. Continue all
deterministic implementation, recorded-harness tests, CI, and Finder-smoke work;
in particular, Steps 5 and 7 use the delivered capture set and do not depend on
a new live call. If all non-live work is complete while approval remains absent,
mark Plan 001 `BLOCKED` with a one-line “live acceptance pending operator
authorization” reason rather than marking it `DONE` or pretending the live
criteria passed.

The product decisions that must survive implementation are:

- The app is native macOS Swift/SwiftUI, with AppKit where needed
  (see “Target Desktop Architecture” in `docs/ROADMAP.md`).
- `FilmBrain` owns harness discovery, execution, structured jobs, and validation;
  `FilmCore` owns canonical data and storage (see “Layered Structure” and
  “FilmBrain” in `docs/ROADMAP.md`).
- The LLM is never canonical; every result passes validation and a controlled
  persistence path (see “The Project Database Is Canonical” in
  `docs/OVERVIEW.md`).
- A batch job is one task, one schema, one validated result, and one transaction
  (see “AI Integration Modes” in `docs/ROADMAP.md`).
- The app never stores provider credentials. It reuses the user's local Codex
  authentication (see “Hard Requirement” in `docs/ROADMAP.md`).
- The bundle is portable, SQLite contains metadata rather than media blobs, and
  schema versioning is explicit (see the project-bundle contract below and
  “Bundle Schema Versioning” in `docs/ROADMAP.md`).
- AI mutations are recoverable, job history is retained, mutations are
  serialized per project, and the user is told where the screenplay goes
  (see “Cross-Cutting Concerns” in `docs/ROADMAP.md`).

Official Codex behavior to design against:

- `codex exec` is the stable non-interactive command and supports JSONL events,
  `--output-schema`, `--output-last-message`, read-only sandboxing, ephemeral
  sessions, and config/rules isolation.
- `--ask-for-approval`, `--sandbox`, `-C`, and `-c` are global `codex` options;
  place them before the `exec` subcommand. `--ignore-user-config` is an `exec`
  option and ignores `config.toml`, but it does not disable authentication or
  the global `AGENTS.md` loaded from `CODEX_HOME`.
- `codex login status` exits zero when credentials are present.
- `--json` emits events such as `thread.started`, `turn.started`, `item.*`,
  `turn.completed`, `turn.failed`, and top-level `error`; completed turns may
  include input/cached-input/cache-write-input/output/reasoning-output token
  usage.
- Codex may write progress, log, or diagnostic lines to stderr, so only
  structured terminal events plus process exit/result validation determine job
  outcome.
- `--output-schema` constrains Codex's final message, but Film Camp must still
  independently validate the file before decoding or persistence.

References:

- <https://learn.chatgpt.com/docs/non-interactive-mode>
- <https://learn.chatgpt.com/docs/developer-commands?surface=cli>
- <https://learn.chatgpt.com/docs/auth>
- `docs/REFERENCE_PROJECTS.md`, especially the adapter-contract, Finder-safe
  discovery, process lifecycle, and Phase 0 sections.
- `../aifilmcamp-app-references/rxcode/Packages/Sources/RxCodeCore/Backend/AgentBackend.swift`
  and
  `../aifilmcamp-app-references/rxcode/Packages/Sources/RxCodeCore/Backend/BackendCapability.swift`
  for separation of backend lifecycle from provider capability declarations.
- `../aifilmcamp-app-references/AIWorkstation/AIWorkstation/Agent/AgentCLI.swift`
  for bounded Finder-safe discovery and manual override behavior.

Phase 0 intentionally keeps `codex exec` as its one structured transport. The
Codex app-server implementation in RxCode is useful later, but adopting it now
would increase the spike's protocol and lifecycle surface without proving a
new Film Camp product assumption.

## Fixed architecture for the spike

Use this dependency direction:

```text
AI Film Camp app target
  ├── UI + @MainActor AppModel
  ├── FilmBrain.AnalyzeScreenplayJob
  └── FilmCore.ProjectSession

FilmBrain package ───────────────▶ FilmCore package
  harness adapters                 domain values
  Codex locator/process runner     project bundle and SQLite
  JSONL events                     controlled ProjectTools protocol
  JSON Schema + semantic checks    atomic apply operation

FilmCore imports neither FilmBrain nor SwiftUI.
SwiftUI imports no Process, JSON Schema, SQLite, or Codex command logic.
```

Use these packages:

- `GRDB.swift`, exact version 7.11.1, in `FilmCore`. Use `DatabaseQueue` for the
  single-project Phase 0 workload, migrations, foreign keys, and transactions.
- `ajevans99/swift-json-schema`, exact version 0.13.1, product `JSONSchema`, in
  `FilmBrain`. Keep the checked-in JSON Schema resource as the single schema
  artifact passed to Codex and used for independent validation. Do not generate
  a second schema from the Swift DTO in this phase.

Pin resolved versions in `Package.resolved`. Do not introduce Core Data,
SwiftData, an ORM above GRDB, or a second JSON library.

Use macOS 15 as the spike deployment floor, Swift 6 language mode, strict
concurrency checking, and the Observation framework for UI state. Keep App
Sandbox disabled in Phase 0: the app must launch a user-installed executable
outside its bundle. Do not add broad temporary exception entitlements to make a
sandboxed build appear to work.

## Target file layout

Create this structure. Small filename variations are acceptable only when they
preserve the module and responsibility boundaries.

```text
AGENTS.md
README.md
.gitignore
project.yml
AI Film Camp.xcodeproj/                 generated by XcodeGen and committed
AI Film Camp/
  App/
    AIFilmCampApp.swift
    AppDelegate.swift                   Finder open events
    AppModel.swift                      @MainActor presentation state only
    AppServices.swift                   composition root
  Views/
    WelcomeView.swift
    ProjectView.swift
    CodexStatusView.swift
    AnalysisJobView.swift
    AnalysisResultsView.swift
  Support/
    AIFilmProjectType.swift             exported UTType
    UserFacingError.swift
  Resources/
    Info.plist
    Fixtures/README.md                  fixture provenance and rights
    Fixtures/phase0-fixture.fountain
  Tests/
    AppModelTests.swift
  UITests/
    Phase0FlowUITests.swift

Packages/FilmCore/
  Package.swift
  Sources/FilmCore/
    Domain/Project.swift
    Domain/Script.swift
    Domain/Scene.swift
    Domain/Character.swift
    Domain/Location.swift
    Domain/ProjectAsset.swift
    Domain/Job.swift
    Domain/ScreenplayAnalysisProposal.swift
    ProjectTools.swift
    Storage/ProjectBundle.swift
    Storage/ProjectBundleLayout.swift
    Storage/ProjectDatabase.swift
    Storage/ProjectMigrator.swift
    Storage/ProjectRepository.swift
    Storage/ProjectSession.swift
    Storage/RelativeProjectPath.swift
  Tests/FilmCoreTests/
    ProjectBundleTests.swift
    ProjectMigrationTests.swift
    ProjectRepositoryTests.swift
    AnalysisTransactionTests.swift

Packages/FilmBrain/
  Package.swift
  Sources/FilmBrain/
    Harness/HarnessAdapter.swift
    Harness/HarnessStatus.swift
    Harness/HarnessCapabilities.swift
    Harness/HarnessEvent.swift
    Harness/ProcessRunning.swift
    Harness/FoundationProcessRunner.swift
    Harness/JSONLEventDecoder.swift
    Codex/CodexLocator.swift
    Codex/CodexCompatibilityPolicy.swift
    Codex/CodexInvocationBuilder.swift
    Codex/CodexHarnessAdapter.swift
    Tasks/AnalyzeScreenplay/AnalyzeScreenplayDTO.swift
    Tasks/AnalyzeScreenplay/AnalyzeScreenplayValidator.swift
    Tasks/AnalyzeScreenplay/AnalyzeScreenplayPrompt.swift
    Tasks/AnalyzeScreenplay/AnalyzeScreenplayJob.swift
    Testing/RecordedHarnessAdapter.swift
  Sources/FilmBrain/Resources/
    Schemas/analyze-screenplay-v1.schema.json
  Tests/FilmBrainTests/
    CodexLocatorTests.swift
    CodexCompatibilityTests.swift
    HarnessAdapterContractTests.swift
    JSONLEventDecoderTests.swift
    AnalyzeScreenplayValidatorTests.swift
    CodexSchemaCompatibilityTests.swift  opt-in live schema-only preflight
    LiveCodexAnalyzeScreenplayTests.swift opt-in live end-to-end adapter test
    AnalyzeScreenplayJobTests.swift
    Fixtures/codex-success.jsonl
    Fixtures/codex-success-error-item.jsonl
    Fixtures/codex-failure.jsonl
    Fixtures/analyze-valid.json
    Fixtures/analyze-malformed.json
    Fixtures/analyze-bad-reference.json
    Fixtures/README.md                  fixture provenance and redaction notes

scripts/
  verify.sh
  finder-smoke.sh
.github/workflows/ci.yml
```

## Project bundle contract

Version 1 bundles have this exact minimum layout:

```text
My Film.aifilm/
├── project.db
├── screenplay/
│   └── phase0-fixture.fountain
├── assets/
├── exports/
├── cache/
│   └── jobs/<job-id>/
│       ├── result.json
│       └── workspace/
└── logs/
    └── jobs/<job-id>.jsonl
```

Rules:

- All stored paths are normalized paths relative to the bundle root. Never
  persist the absolute bundle location in `project.db`.
- `RelativeProjectPath` rejects absolute paths, `..`, empty components, NULs,
  and resolutions that escape the standardized bundle URL.
- Create a bundle in a uniquely named sibling staging directory, initialize all
  directories and the database there, then rename the completed package to the
  requested destination. A failed create must leave no half-initialized target.
- Open only a regular, non-symlink `project.db` at the bundle root.
- Movement is supported after `ProjectSession.close()` has checkpointed SQLite
  and released the connection. Movement while open is not supported in Phase 0.
- Register `com.aifilmcamp.project` as an exported UTType conforming to
  `com.apple.package`. Register `.aifilm` as a document/package extension in
  `Info.plist` so Finder opens it with the app.
- Use `NSSavePanel` and `NSOpenPanel` behind a small AppKit service. Also handle
  `application(_:open:)` in `AppDelegate` so double-clicking a package works.

## SQLite version 1 contract

Use string UUIDs and ISO-8601 UTC timestamps. Enable foreign keys. The migration
must create only the Phase 0 entities plus relationship tables:

| Table | Required fields / constraints |
|-------|-------------------------------|
| `projects` | one row; `id`, `name`, `bundle_schema_version = 1`, created/updated timestamps |
| `scripts` | `id`, project FK, display name, source asset FK, source text, SHA-256, created timestamp |
| `scenes` | `id`, script FK, unique `(script_id, ordinal)`, heading, synopsis |
| `characters` | `id`, project FK, payload key, name, description; payload key unique per project |
| `locations` | same minimal shape as characters |
| `scene_characters` | scene/character composite primary key |
| `scene_locations` | scene/location composite primary key; one location per scene is enough for Phase 0 |
| `project_assets` | `id`, project FK, kind, relative path, SHA-256, created timestamp |
| `jobs` | `id`, project FK, task, engine, engine version, requested/effective model (nullable), schema version, input SHA-256, state, progress stage, nullable nonnegative input/cached-input/cache-write-input/output/reasoning-output token counts, log/result relative paths, start/end timestamps, failure code/message |

Name the usage columns `input_tokens`, `cached_input_tokens`,
`cache_write_input_tokens`, `output_tokens`, and `reasoning_output_tokens`.
Each is a nullable integer with a database check constraint permitting only
values greater than or equal to zero.

Use `PRAGMA user_version = 1` as the fast bundle schema stamp and retain
`projects.bundle_schema_version` as the human-queryable value. On open:

1. Read `user_version` before running migrations.
2. Reject a version greater than the app's `currentBundleSchemaVersion` with a
   clear `newerProjectVersion` error.
3. Migrate older versions in order. Version 0 is valid only for a newly created
   empty database during Phase 0.
4. Confirm the project singleton row and bundle schema version after migration.

`Job.State` is a closed enum with transitions:

```text
queued → discoveringHarness → running → validating → committing → completed
                                      ↘ failed
          queued/discovering/running/validating → cancelled
```

Reject illegal transitions in `FilmCore`; do not let the UI invent strings.
Serialize mutations with one `ProjectSession` actor plus GRDB's
`DatabaseQueue`. Disable the Analyze button while an analysis job is active.
Cancellation is accepted through `validating`. Once `committing` begins, refuse
or defer cancellation, show “Finishing commit,” and let the atomic transaction
finish as either `completed` or `failed`; a committed result must never be
reported as cancelled.

The final apply operation must run in one `dbQueue.write` transaction:

1. Delete prior Phase 0 analysis rows for the script. Phase 0 supports reruns,
   and every successful rerun atomically replaces the prior analysis.
2. Insert characters and locations.
3. Insert scenes and join rows.
4. Mark the job `completed` with its counts and completion timestamp.

If any statement fails, the transaction rolls back, preserving the previous
analysis. Mark the job `failed` in a separate post-rollback transaction.

## `analyzeScreenplay` output contract

Check in one JSON Schema with Draft 2020-12 vocabulary and
`additionalProperties: false` on every object. It must represent this shape:

```json
{
  "schemaVersion": 1,
  "scenes": [
    {
      "id": "scene_1",
      "ordinal": 1,
      "heading": "INT. CAMP CABIN - NIGHT",
      "synopsis": "...",
      "characterIds": ["char_maya"],
      "locationId": "loc_camp_cabin"
    }
  ],
  "characters": [
    {
      "id": "char_maya",
      "name": "MAYA",
      "description": "..."
    }
  ],
  "locations": [
    {
      "id": "loc_camp_cabin",
      "name": "CAMP CABIN",
      "description": "..."
    }
  ]
}
```

Codex-facing schema requirements:

- All properties shown above are required. `locationId` may be a string or
  `null`; descriptions may be empty strings but may not be omitted.
- `schemaVersion` is `{ "type": "integer", "const": 1 }`. Structured Outputs
  rejects a property that has `const` but omits its sibling `type` on the Phase 0
  Codex CLI path.
- `scenes` has `minItems: 1` and a defensive `maxItems: 5000`.
- Character and location arrays have `maxItems: 2000`.
- IDs use predictable prefixes (`scene_`, `char_`, `loc_`) and a conservative
  ASCII pattern.
- Arrays define item shapes and bounds; no unconstrained object or arbitrary
  dictionary appears in the payload.
- Keep the schema within the smallest Structured Outputs subset the product
  needs. A 2026-08-18 probe confirmed that Codex CLI 0.146.0 accepts
  `minLength`/`maxLength` and a top-level `$schema`, but omit both from the
  Codex-facing artifact: length remains a mandatory semantic check, and the
  dialect keyword provides no Phase 0 runtime value. Re-run the compatibility
  test whenever the schema or minimum Codex version changes.

Validation order is security- and correctness-relevant:

1. Reject a missing, non-regular, or larger-than-16-MB result file.
2. Parse JSON using the JSON Schema package.
3. Validate the exact file against the checked-in schema.
4. Decode the same bytes into `AnalyzeScreenplayDTO` with `JSONDecoder`.
5. Run semantic validation not expressible in the schema:
   - IDs are unique in their collections.
   - Character and location names are unique after trim/case fold.
   - Scene ordinals are unique and contiguous from 1.
   - Every scene character/location reference exists.
   - Trimmed IDs, names, and headings are nonempty and contain no control chars.
   - IDs, names, and headings are at most 128 Unicode scalar values; synopsis
     and description fields are at most 2,000.
6. Convert to `FilmCore.ScreenplayAnalysisProposal` with newly assigned canonical
   UUIDs. Payload IDs are temporary relationship keys, not canonical IDs.
7. Only the validated proposal can be passed to `ProjectTools.applyAnalysis`.

Keep the invalid result and semantic-reference fixtures as permanent regression
tests. Never offer an unchecked initializer for the validated proposal in the
production target.

## Codex discovery and compatibility contract

`CodexLocator` must not rely solely on the Finder process's `PATH`. Discover
candidates in this order, deduplicate standardized/resolved URLs, and select the
first candidate that passes interrogation:

1. An explicit override supplied to the locator (test seam now; user-facing
   executable picker can come later).
2. Executable named `codex` found in the inherited `PATH`.
3. Output from the user's login shell running the constant command
   `command -v -- codex`. Invoke the shell as an interactive login shell so
   common fnm/nvm initialization in `.zshrc` is included, bound startup to five
   seconds, attach `/dev/null` to stdin, and never interpolate user input.
4. Known user/package-manager locations:
   `~/.local/bin/codex`,
   `~/.local/share/fnm/aliases/default/bin/codex`,
   `~/.volta/bin/codex`,
   `~/.bun/bin/codex`,
   `/opt/homebrew/bin/codex`, and `/usr/local/bin/codex`.

For every candidate:

- Require an absolute, existing executable file and resolve symlinks for
  deduplication and display. Retain a launchable absolute URL; a failed probe
  must be recorded and skipped rather than ending discovery while later
  candidates remain.
- Invoke that absolute URL directly through `Process`; never launch analysis
  through `/bin/sh`, `env`, or a command string.
- Run `--version`, cap output at 64 KB, enforce a 5-second timeout, and parse
  `codex-cli <semantic-version>` without assuming the prefix is the path name.
- Probe both root `--help` and `exec --help`. Require global `-C`, `-c`,
  `--sandbox`, and `--ask-for-approval`, plus these `exec` capabilities: `--json`,
  `--output-schema`, `--output-last-message`, `--ephemeral`,
  `--skip-git-repo-check`, `--ignore-user-config`, and `--ignore-rules`.
- Require version `>= 0.146.0`. A newer version is compatible only when all
  required capabilities are still present.
- Run `login status`; exit 0 means authenticated. Derive `authenticationMode`
  from its bounded stdout only when it matches a recognized status such as
  `Logged in using ChatGPT`; if a successful response is unrecognized, expose
  a generic `signedIn` mode rather than failing detection. Do not log the raw
  response or read auth files, keychains, tokens, environment secrets, or config
  contents.

Expose a value-type `HarnessStatus` with mutually exclusive states:

```text
notInstalled
installedButUnauthenticated(path, version)
installedButIncompatible(path, version, missingCapabilities)
ready(path, version, authenticationMode, capabilities)
detectionFailed(actionableMessage)
```

The UI can display the executable path and version, but logs must not include
environment dumps or credential material. `Refresh` reruns detection. The app
may tell the user to run `codex login`; it must not perform login or hold the
credential itself.
If no candidate passes, the actionable message summarizes the sanitized paths
tried and whether each was missing, non-executable, timed out, or failed its
version launch; one broken package-manager install must not hide a later valid
candidate.

Finder-safe discovery and Finder-safe execution are one contract. Capture a
bounded, explicitly framed `PATH` and optional `CODEX_HOME` value from the same
interactive login shell; do not run or parse `env`. Build a minimal launch
environment from an allowlist: `HOME`, `TMPDIR`, `USER`, `LOGNAME`, `LANG`,
`LC_*`, the captured `PATH`, and the captured `CODEX_HOME` only when nonempty.
The app may also preserve `SSL_CERT_FILE` and `SSL_CERT_DIR` only when they
resolve to existing absolute file/directory paths, plus a bounded
`NO_PROXY`/`no_proxy` host list; never log their values. Do not copy the shell
environment wholesale. Explicitly exclude `OPENAI_API_KEY` and `CODEX_API_KEY`.
An inherited `HTTP_PROXY`, `HTTPS_PROXY`, or `ALL_PROXY` value, including its
lowercase form, may be forwarded only when it is at most 2,048 bytes, contains
no control characters, parses as an `http` or `https` URL with a nonempty host,
and has neither a user nor a password component. Never log the value. Omit any
malformed or credential-bearing proxy URL; if the process then reports a
network failure, the actionable error must say that unsupported proxy values
were not forwarded. Authenticated corporate-proxy support needs a separately
approved credential design. The captured `PATH` is required for shebang
launchers such as npm/fnm-installed Codex, where `/usr/bin/env node` must
resolve `node`. Unit tests must reproduce that Finder-empty-`PATH` case.

## Codex execution contract

`CodexHarnessAdapter` launches the absolute executable reported as `ready`.
Build the argument array directly. The Phase 0 invocation is conceptually:

```text
codex
  --ask-for-approval never
  --sandbox read-only
  -C <bundle/cache/jobs/job-id/workspace>
  -c project_doc_max_bytes=0
  exec
  --ephemeral
  --ignore-user-config
  --ignore-rules
  --skip-git-repo-check
  --color never
  --json
  --output-schema <app-resource-schema-path>
  --output-last-message <bundle/cache/jobs/job-id/result.json>
  -
```

The empty per-job workspace plus `project_doc_max_bytes=0` prevents project
instructions from being loaded from the selected directory hierarchy. Current
Codex still loads the user's global `AGENTS.md` from `CODEX_HOME`; Phase 0
accepts that user-controlled ambient instruction because the CLI exposes no
supported disable switch. Installed Codex skills and plugin-provided
descriptions or instructions may also enter model context; on 0.146.0,
`--ignore-user-config` does not provide a supported global extension-disable
switch. Do not claim complete prompt isolation or enumerate extension contents
from Film Camp. Hard safety continues to come from the read-only sandbox, no
approvals, a fixed prompt, schema plus semantic validation, and Film Camp's
controlled transaction. If the product requires suppression of global
instructions or installed extension context, STOP until Codex provides a
supported capability or a separately approved transport does so.

Phase 0 deliberately uses the logged-in account's Codex default model rather
than hard-coding a potentially unavailable identifier. Store
`requested_model = null`; capture the exact effective model from structured
startup metadata when Codex exposes it, otherwise leave `effective_model = null`
and display “Codex default.” Codex CLI 0.146.0 was observed to omit the model
from `thread.started`, so null is the expected Phase 0 value and must not be
inferred from config or marketing defaults. A future reproducibility decision
may add an app-owned explicit `--model` after compatibility and account
availability are defined.

Write a fixed instruction plus the screenplay text to stdin, then close stdin.
The instruction must say: analyze only the supplied screenplay; do not use
tools or modify files; return only the schema-defined scenes, characters, and
locations; preserve scene order; do not invent production ontology beyond the
fields requested.

Process requirements:

- Read stdout and stderr concurrently to avoid pipe deadlock.
- Treat stderr as a bounded diagnostic stream only. Codex may write progress,
  log, or diagnostic lines there, including ERROR-level implementation logs
  even when the turn succeeds; stderr text alone must never transition the job
  to `failed`.
- Decode stdout incrementally by newline. Handle split UTF-8 chunks, unknown
  event/item types, and a final line without a newline.
- Persist the raw JSONL stream to `logs/jobs/<id>.jsonl` with a 32-MB cap.
- Map events to coarse UI stages, not fake percentages:
  `thread.started/turn.started → running`, agent/tool item activity → still
  running with a short status message, `turn.completed → validating`, and
  `turn.failed`/top-level `error`/nonzero exit → `failed`.
- An `item.completed` event whose nested `item.type` is `error` is a diagnostic
  status item, not a terminal event. Log and surface a safe message, then wait
  for `turn.completed`, `turn.failed`, top-level `error`, or process exit.
- When `turn.completed` includes usage, store its nonnegative `input_tokens`,
  `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, and
  `reasoning_output_tokens` values on the job. Leave unavailable fields null,
  ignore unknown usage keys for forward compatibility, and never estimate
  values.
- Treat unknown events as loggable forward-compatible data, not fatal errors.
- Apply a 10-minute timeout. Cancellation first calls `terminate()`, waits up to
  two seconds, then interrupts only if still running. Record `cancelled` rather
  than `failed` for user cancellation.
- Never pass `--dangerously-bypass-approvals-and-sandbox`, workspace-write, an
  API key, or a credential environment variable.
- A zero exit without a valid result file is a failure. A result file without a
  successful process exit is also a failure.

Use `RecordedHarnessAdapter` for unit/UI tests. It replays checked-in JSONL and
result fixtures through the same event, validation, and persistence path. The
live adapter is selected in normal builds; recorded mode requires a Debug-only
launch argument and must be impossible in Release.

Bootstrap the implementation fixtures from
`docs/plans/captures/codex-0.146.0-2026-08-18/`. Its README records provenance,
the exact invocation shape, and the limited normalization performed. Copy—not
move—the applicable schema, result, success, nested-error, failure, and stderr
files into `Packages/FilmBrain/Tests/FilmBrainTests/Fixtures/`, renaming them to
the target layout where necessary. Keep the docs capture immutable as planning
evidence. Preserve synthetic unknown-event cases as well so forward
compatibility does not depend on one observed CLI version. Any future live
refresh must be inspected, stripped of paths/usernames/prompts, and have every
real `thread_id` replaced with a stable fixture ID before check-in.

## Minimal UI contract

Use one resizable window and native controls. No design system work is needed.

### Empty state

- Create Project and Open Project buttons.
- Codex status card with installed/authenticated/compatible status, path,
  version, Refresh, and an actionable instruction when unavailable.

### Open project state

- Project name and current bundle path, plus Reveal in Finder and Close.
- Fixture screenplay name and checksum; Phase 0 does not expose general import.
- An inline disclosure: “Running analysis sends this screenplay to Codex using
  your local Codex account. Codex may include your global instructions and
  installed skill/plugin descriptions in the same model context; Film Camp
  does not read or store those contents.”
- Analyze Screenplay button, disabled unless the project is open, Codex is
  ready, and no mutation is active.
- On the first run, require a confirmation alert repeating the disclosure.
- Job card with state, indeterminate progress while the process is active,
  latest safe status message, Cancel, and Retry after failure.
- Results sections for scenes, characters, and locations with counts and simple
  lists. Load these from SQLite on open; never display an in-memory uncommitted
  DTO as if it were canonical.

Errors must distinguish at least: project create/open, newer bundle schema,
Codex not found, Codex signed out, incompatible Codex, process launch, timeout,
cancelled, nonzero Codex exit, JSONL decode warning, missing/oversized result,
schema validation, semantic validation, and database commit failure.

## Commands you will need

After bootstrap, `scripts/verify.sh` must run these in order and stop on failure:

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Generate project | `xcodegen generate --spec project.yml` | exit 0; `AI Film Camp.xcodeproj` exists |
| FilmCore tests | `swift test --package-path Packages/FilmCore` | exit 0; all tests pass |
| FilmBrain tests | `swift test --package-path Packages/FilmBrain` | exit 0; all tests pass without invoking live Codex |
| App build | `xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build` | exit 0, app is ad hoc signed, `** BUILD SUCCEEDED **` |
| App/unit/UI tests | `xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test` | exit 0, UI test runner launches, `** TEST SUCCEEDED **` |
| Full verification | `./scripts/verify.sh` | exit 0 after all gates above |

Use a stable DerivedData path inside `.build/DerivedData` in scripts so the
Finder smoke script can locate the app deterministically. Ignore `.build/`,
`DerivedData/`, `.DS_Store`, and user Xcode state.

The optional live test is never part of CI and must be explicitly enabled:

```bash
FILMCAMP_RUN_LIVE_CODEX=1 swift test \
  --package-path Packages/FilmBrain \
  --filter LiveCodexAnalyzeScreenplayTests
```

Expected: skipped without the environment variable; with it, uses the local
logged-in Codex account and produces a schema-valid result for the small
fixture. Do not run it automatically because it uses the person's account.

## Git workflow

The workspace had no Git metadata at planning time.

1. If it is still unversioned, run `git init -b main` before creating source.
2. If a remote is already configured instead, run `git pull --ff-only` before
   changing files. If there is no remote, do not invent one.
3. Use focused commits after each milestone. Recommended messages:
   - `chore: bootstrap macOS workspace`
   - `feat(core): add portable film project bundles`
   - `feat(brain): add Codex discovery and process events`
   - `feat(brain): validate screenplay analysis results`
   - `feat: run and persist screenplay analysis jobs`
   - `feat: add Phase 0 macOS workflow`
   - `test: verify Phase 0 spine`
4. Pull with `--ff-only` before the final commit when a remote exists. Do not
   push or open a PR unless the operator asks.

## Steps

### Step 1: Bootstrap the reproducible macOS workspace

Create `.gitignore`, a concise root `README.md`, both Swift packages, XcodeGen
`project.yml`, app/unit/UI test targets, and `scripts/verify.sh`. Configure the
app product name `AI Film Camp`, bundle identifier under `com.aifilmcamp`, macOS
15 deployment target, Swift 6, strict concurrency, generated asset catalogs only
if actually used, and the custom `Info.plist` with `.aifilm` declarations.

Keep `project.yml` canonical. Generate and commit the `.xcodeproj`; CI must
regenerate before building so hand-edited project drift is caught.

**Verify**:

```bash
xcodegen generate --spec project.yml
swift package describe --package-path Packages/FilmCore >/dev/null
swift package describe --package-path Packages/FilmBrain >/dev/null
xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

Expected: all commands exit 0, the app is ad hoc signed, and the app build
reports `BUILD SUCCEEDED`. Do not use `CODE_SIGNING_ALLOWED=NO` for the later UI
test gate; macOS UI test runners need a launchable signed host.

### Step 2: Implement FilmCore project bundles and migrations

Add the bundle layout, relative-path validation, v1 domain records, migrator,
repository, and actor-backed `ProjectSession`. Creation copies the fixture into
`screenplay/`, hashes it with CryptoKit SHA-256, adds a `ProjectAsset`, adds one
`Script`, stamps schema version 1, and finishes by moving the staged package
into place. Opening performs the newer-version refusal before migration.

Define `ProjectTools` as the only FilmBrain-facing mutation interface. It can
load the selected script, create/update jobs through legal transitions, apply a
validated `ScreenplayAnalysisProposal`, fetch canonical results, and close.
It must not expose a raw GRDB database or arbitrary SQL.

**Verify**:

```bash
swift test --package-path Packages/FilmCore
```

Expected: tests pass for initial layout, source checksum, schema stamp,
newer-version refusal, relative-path traversal rejection, closed-session move
and reopen, legal/illegal job transitions, nullable/nonnegative job usage fields,
and transaction rollback.

### Step 3: Implement harness contracts, Codex discovery, and process safety

Before coding, inspect the RxCode backend/capability files and AIWorkstation
locator named in `docs/REFERENCE_PROJECTS.md`. Adopt their separation of
responsibilities and bounded discovery lessons, not their product models or UI.
Reimplement the patterns behind FilmBrain-owned types; if code is copied or
substantially adapted, perform the license and attribution review required by
the reference guide.

Add value types/protocols for statuses, events, requests, and process execution.
Make filesystem, environment, login-shell lookup, clock, and process execution
injectable so discovery tests never depend on the developer machine. Implement
the exact discovery/capability/auth contract above and bound all probe output and
timeouts.

Treat the selected executable plus its minimal launch environment as one
`CodexLaunchContext`. Test recognized and unrecognized successful
`login status` output, including the generic `signedIn` fallback. Test a
launcher whose shebang is
`#!/usr/bin/env filmcamp-fake-tool`, with the fake interpreter placed only in a
temporary fixture `PATH`: inherited Finder `PATH` must fail, while the captured
login-shell `PATH` succeeds. This proves shebang resolution without requiring
Node or another host-installed interpreter. Also prove that credential and
credential-bearing/malformed proxy URL variables are excluded, eligible
credential-free proxy URLs and validated certificate paths may pass, and no
environment value appears in logs. Exercise the safe network-error wording when
a proxy value is omitted.

Define explicit Phase 0 capabilities for structured result delivery, progress
events, cancellation, and non-interactive execution. Add adapter contract tests
against `RecordedHarnessAdapter`; later providers must pass the same lifecycle
tests without exposing provider types to FilmCore.

Implement the process runner and incremental JSONL decoder independently of the
Codex adapter. The runner owns lifecycle/cancellation and yields byte chunks;
the decoder owns lines/events. Test chunk boundaries and unknown event types.

**Verify**:

```bash
swift test --package-path Packages/FilmBrain \
  --filter CodexLocatorTests
swift test --package-path Packages/FilmBrain \
  --filter JSONLEventDecoderTests
```

Expected: all tests pass, including a simulated Finder-empty `PATH` that still
finds the fake shebang interpreter/known fnm path, unauthenticated and
incompatible states, timeouts, split UTF-8/JSON lines, nested error-typed items,
top-level errors, diagnostic stderr, usage fields, malformed lines, and
oversized output.

### Step 4: Add the schema, prompt, and validation boundary

Add the fixture screenplay, schema, DTO, prompt, and validators. Use the schema
file both as the Codex `--output-schema` input and the application's validation
input. Add valid, structurally malformed, and semantically invalid fixtures.
Keep string-length constraints in semantic validation to minimize dependence on
optional Structured Outputs keywords while array bounds and ID patterns remain
in the checked-in schema. Add `CodexInvocationBuilder` now so the schema probe
and Step 6 live adapter cannot drift into different flag orderings.
Document that the screenplay is synthetic/original and record fixture
provenance and redaction rules in the fixture READMEs; do not use a commercial
screenplay as test data.

Do not treat `JSONDecoder` success as schema validation. Do not accept output
wrapped in Markdown fences. Do not repair malformed AI output. A failed result
remains in the local cache/log for diagnosis and produces a failed job.

**Verify**:

```bash
swift test --package-path Packages/FilmBrain \
  --filter AnalyzeScreenplayValidatorTests
```

Expected: the valid fixture becomes a proposal; malformed JSON, extra keys,
wrong schema version, oversized fields/arrays, duplicate names/IDs, noncontiguous
ordinals, and dangling references are rejected with deterministic error codes.

The delivered capture set shows that this schema and invocation shape were
accepted by Codex CLI 0.146.0 on 2026-08-18, so it is sufficient to bootstrap
fixtures and continue deterministic work. Still ask the operator before running
this account-backed schema-only preflight against the implemented schema and
shared invocation builder:

```bash
FILMCAMP_RUN_LIVE_CODEX=1 swift test \
  --package-path Packages/FilmBrain \
  --filter CodexSchemaCompatibilityTests
```

The test uses the exact checked-in schema, global/exec flag ordering, minimal
launch environment, empty per-job workspace, and a tiny synthetic screenplay.
It is never part of CI and skips unless explicitly enabled. Expected when
enabled: Codex accepts the schema, emits a terminal success event, writes a
schema-valid result, and exits 0. STOP at Step 4 if an authorized run rejects
the schema or flags; do not weaken independent semantic validation. If the
operator does not authorize account use, record this live gate as deferred and
continue with Steps 5–7 under the live-gate policy.

### Step 5: Orchestrate the recorded job and atomic commit first

Implement `AnalyzeScreenplayJob` against `HarnessAdapter` and `ProjectTools`.
Exercise the complete state machine using `RecordedHarnessAdapter`: load script,
record input hash, run events, locate result, validate, convert, commit, reload
canonical results. Add failure, cancellation, and commit-rollback tests.

Copy `codex-success.jsonl`, `codex-success-error-item.jsonl`, the terminal
failure stream, valid result, and stderr diagnostic from the delivered docs
capture into the implementation fixture directory, preserving the capture
README's CLI version/date provenance and normalization notes. Both success
streams must end in `turn.completed` and exercise the same successful job path;
the failure fixture remains terminal with top-level `error` and/or
`turn.failed`.

The recorded success UI/integration path must work before connecting the live
adapter. This creates a deterministic baseline for every layer except the real
Codex process.

**Verify**:

```bash
swift test --package-path Packages/FilmBrain \
  --filter AnalyzeScreenplayJobTests
swift test --package-path Packages/FilmCore \
  --filter AnalysisTransactionTests
```

Expected: success commits all records and the job together; malformed output
commits no analysis; an injected database failure preserves the prior analysis;
cancellation leaves no partial analysis and records `cancelled`; a nested
error-typed item followed by `turn.completed` succeeds; available usage values
including `cache_write_input_tokens` persist, absent values remain null, and an
unknown future usage key is ignored.

### Step 6: Connect the live Codex adapter

Reuse `CodexInvocationBuilder` from the Step 4 preflight, stream
stdin/stdout/stderr safely, write result/events into bundle-relative job paths,
and translate process/events into the harness abstraction. Keep the full live
run opt-in in tests. Verify the adapter never shells out for the analysis
command and never reads credentials. Re-run the schema compatibility test first
if the schema, invocation builder, or detected Codex version changed after Step
4. Confirm the job reports the intentionally requested “Codex default,” leaves
the effective model null when 0.146.0 omits it, and records available usage.

Run the live test once manually only after the operator understands it uses the
local Codex account. If approval is withheld, complete the adapter and all
deterministic tests, defer only the live command below, and continue with Step 7.
When a new live stream is captured, inspect it before refreshing the recorded
full-analysis fixture; remove paths, usernames, prompts, and real thread IDs
when they are not material to the parser test.

**Verify**:

```bash
swift test --package-path Packages/FilmBrain
FILMCAMP_RUN_LIVE_CODEX=1 swift test \
  --package-path Packages/FilmBrain \
  --filter LiveCodexAnalyzeScreenplayTests
```

Expected: deterministic tests pass. When explicitly approved and enabled, the
live test discovers Codex, sees authenticated/compatible status, emits progress
events, produces a schema-valid result, and exits 0.

### Step 7: Build the minimal SwiftUI workflow

Compose `FilmCore` and `FilmBrain` in `AppServices`. `AppModel` owns only
presentation state and delegates work to those services. Implement create/open,
Finder open events, Codex status, privacy confirmation, job progress/cancel/
retry, and canonical results. Add accessibility identifiers to the small set of
buttons/status labels needed by UI tests.

The Debug-only recorded-harness launch mode accepts a test project root and
replays the success/malformed fixtures. Release builds must ignore/reject those
launch arguments.

**Verify**:

```bash
xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Expected: unit and UI tests pass. The main UI test creates a package, confirms
the disclosure, runs the recorded job, sees persisted counts, closes/reopens the
project, and sees the same counts. The malformed test sees an error and zero
canonical analysis rows.

### Step 8: Add CI and the Finder/move acceptance harness

Add a macOS GitHub Actions workflow pinned to `macos-26`, with
`DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`. Assert that
`xcodebuild -version` reports Xcode 26.6 before building. Install exact XcodeGen
2.46.0, regenerate the project, verify no generated-project diff, and run
`scripts/verify.sh`. Do not use `macos-latest`, do not silently select another
Xcode, and never run the live Codex test or require credentials.

`scripts/finder-smoke.sh` should build into the stable DerivedData path and use
`open -n` on the `.app`, exercising LaunchServices instead of executing the Mach
binary directly. Use the recorded adapter for automation. Keep the final live
Finder test manual because it depends on the user's login and a visible app.

Perform the manual move test only while the project is closed:

1. Create and live-analyze `Phase Zero.aifilm` in one directory.
2. Quit the app and confirm no process holds `project.db`.
3. Move the package to a different directory/volume through Finder.
4. Double-click it.
5. Confirm the project name, script checksum, job history, scenes, characters,
   and locations match pre-move values.

The CI, recorded Finder smoke, and recorded close/move/reopen checks are
deterministic and must proceed without account approval. Defer only the live
analysis and live Finder evidence when approval is withheld; leave the plan
`BLOCKED` at final handoff if those live acceptance criteria remain outstanding.

**Verify**:

```bash
./scripts/verify.sh
./scripts/finder-smoke.sh
git status --short
```

Expected: both scripts exit 0; only intentional source/project/plan changes are
listed; no `.aifilm`, database, result, log, DerivedData, auth, or secret file is
staged.

## Test plan

### FilmCore unit tests

- Bundle creation is staged and leaves no partial target on injected failure.
- V1 creates every directory, `project.db`, the fixture, checksum, asset, and
  script row.
- `PRAGMA user_version` and project metadata equal 1.
- A higher schema version is refused without changing the database.
- Relative path validation rejects escape attempts and absolute paths.
- Close → move → reopen preserves all IDs, counts, checksums, and relationships.
- Legal job transitions work; illegal transitions throw.
- Cancellation through validation records `cancelled`; cancellation requested
  after `committing` begins is deferred/refused and the transaction reaches
  `completed` or `failed` atomically.
- All five usage columns accept null or nonnegative counts and reject negative
  values.
- One active mutation per project is enforced.
- A successful proposal replaces prior analysis atomically.
- A trigger-injected failure during the second scene insert rolls back the
  entire replacement and preserves prior canonical data.

### FilmBrain unit tests

- Locator ordering, deduplication, symlink resolution, Finder-empty PATH, fake
  shebang interpreter, known fnm path, nonexistent/non-executable candidates.
- Version parse, minimum version, required capability probe, auth exit code,
  recognized auth mode, generic signed-in fallback, probe timeout, and bounded
  output.
- Capability reporting and recorded-adapter contract behavior for start,
  progress, completion, failure, and cancellation.
- JSONL decoding for fragmented bytes, CRLF/LF, missing final newline, unknown
  event and item types, nonterminal error-typed items, top-level errors, all
  five known usage keys, an unknown usage key, malformed line, and output cap.
- Diagnostic stderr—including lines containing `ERROR`—does not fail a process
  that exits zero with `turn.completed` and a valid result.
- JSON Schema acceptance and rejection cases.
- Semantic duplicate/reference/order/control-character cases.
- Recorded job success, process failure, schema failure, semantic failure,
  timeout, cancellation, and commit failure.
- Exact live argument array contains all safety flags and none of the forbidden
  flags or credential values.
- Global flags precede `exec`; the job uses its empty `-C` workspace,
  `project_doc_max_bytes=0`, the minimal launch environment, and no credential
  environment variables.
- Credential-free proxy URLs may pass; credential-bearing or malformed proxy
  URLs do not, their values never reach logs, and omitted-proxy network errors
  explain the limitation without exposing the value.

### App and UI tests

- Finder URL routing opens a valid project and reports invalid/newer bundles.
- Analyze is disabled until project + ready Codex + idle state.
- Privacy disclosure appears before first run.
- Privacy disclosure names possible global instruction and installed
  skill/plugin context without claiming Film Camp reads those contents.
- Recorded success shows progress then canonical results.
- Recorded malformed output shows failure and no results.
- Relaunch/reopen shows persisted results from SQLite.
- Error states expose actionable text and accessibility identifiers.

### Manual live acceptance matrix

| Roadmap exit criterion | Manual evidence to capture |
|------------------------|----------------------------|
| Finder launch | screenshot/video of app opened with `open` or double-click, not Xcode |
| Create/open `.aifilm` | Finder package plus app path/name |
| Schema version | diagnostic view or `sqlite3 project.db 'pragma user_version;'` returns `1` while app is closed |
| Installed/authenticated/compatible | status card shows path, version, auth mode, and Ready |
| Progress/failure | one successful run and one recorded/live-safe failure state |
| Schema-valid result | job completes with counts and retained result artifact |
| One transaction | automated rollback test output |
| Malformed rejection | recorded malformed UI test + unchanged DB counts |
| Quit/reopen | same canonical IDs/counts after relaunch |
| Move/reopen | same canonical IDs/counts after moving closed bundle |

## Done criteria

All must hold:

- [x] `./scripts/verify.sh` exits 0 from a clean checkout.
- [x] XcodeGen regeneration produces no uncommitted project diff.
- [x] FilmCore and FilmBrain package tests pass without a network connection or
  live Codex account.
- [x] App unit/UI tests pass with the recorded harness.
- [x] GRDB.swift 7.11.1, swift-json-schema 0.13.1, XcodeGen 2.46.0,
  `macos-26`, and Xcode 26.6 are pinned/asserted as documented.
- [x] An opt-in live run succeeds using a Finder-discovered, logged-in Codex.
- [x] The live command uses read-only sandbox, never bypasses approvals/sandbox,
  and never accepts or stores credentials.
- [x] Finder-safe probes and execution use the bounded login-shell `PATH` and a
  minimal credential-free environment; a broken earlier candidate is skipped.
- [x] The exact JSON Schema file is used for Codex output and independent app
  validation.
- [x] `schemaVersion` includes both `type: integer` and `const: 1`, and the
  opt-in Step 4 schema compatibility test passes before job orchestration.
- [x] Only top-level terminal errors or process failure fail a job; nested
  error-typed items and diagnostic stderr do not override terminal success.
- [x] All available known Codex token usage, including cache-write input, is
  persisted without estimation; unknown usage keys are tolerated and effective
  model remains null when the CLI does not report it.
- [x] Malformed, semantically invalid, failed, timed-out, and cancelled jobs
  leave canonical scene/character/location rows unchanged.
- [x] Successful rows and completed job status commit in one transaction.
- [x] A project survives quit/reopen and close/move/reopen.
- [x] A newer bundle schema is refused without mutation.
- [x] Finder/LaunchServices opens both the app and a double-clicked `.aifilm`.
- [x] No absolute project-internal path is stored in SQLite.
- [x] No Phase 1 ontology, general screenplay import, human correction, extra
  harness, MCP, video workflow, API-key flow, or cloud storage was added.
- [x] `docs/plans/README.md` marks Plan 001 `DONE`.
- [x] Working tree contains no generated project bundle/database/log/result,
  DerivedData, credential, token, or secret.

## STOP conditions

Stop and report instead of improvising if:

- Either intent-document hash differs and the changed text affects Phase 0,
  architecture, storage, Codex, validation, or exit criteria.
- An app/package implementation already exists with conflicting module or
  persistence boundaries.
- The product owner requires App Sandbox in Phase 0. Executing a user-installed
  CLI then needs a separately approved entitlement/security design.
- The product owner requires complete suppression of the user's global
  `AGENTS.md` or installed skill/plugin context; Codex CLI 0.146.0 has no
  supported switch for that guarantee.
- Root `codex --help` or `codex exec --help` on the minimum supported version
  lacks a required global/subcommand flag, or `--output-schema` cannot be used
  with JSONL plus an output file.
- The selected Swift JSON Schema library cannot validate the checked-in schema
  on the deployment target. Report the failing schema/keyword; do not silently
  replace schema validation with `Codable` alone.
- Supporting package movement requires absolute internal paths or moving an
  open SQLite database.
- Project mutation cannot be expressed through `ProjectTools` without exposing
  raw database access to FilmBrain.
- A verification command fails twice after one reasonable scoped correction.
- A required fix expands into deterministic screenplay parsing, provenance,
  merge/split/editing, asset manifests, or any later-phase ontology.
- Live testing would require changing, reading, copying, or logging the user's
  Codex credentials.

## Maintenance notes

- Phase 1 must reuse the project bundle, migrator, `ProjectTools`, job history,
  and validation pipeline. It should replace AI scene segmentation with a
  deterministic Fountain/FDX parser; do not treat the Phase 0 model-produced
  scene list as the final ontology.
- Capability probing is the primary protection against Codex CLI drift. Review
  it whenever the command changes, and add a recorded event fixture before
  changing the parser.
- The payload schema has its own version separate from the bundle schema. Bump
  them independently and retain old result decoders only when a real migration
  or cached-result requirement appears.
- Reviewers should scrutinize process argument construction, shell use, output
  caps, path containment, actor isolation, transaction boundaries, and Release
  exclusion of the recorded harness.
- Signing/notarization, hardened runtime, final minimum macOS, and app-update
  delivery are intentionally deferred until the spine is proven.
- A richer `NSDocument` architecture may become worthwhile when Phase 1 adds
  autosave, multiple open projects, and editing. Do not migrate preemptively.
