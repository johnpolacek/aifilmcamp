# Plan 025: Multi-provider BYOK reference image generation (Phase 5c)

> Read `docs/PHASE1_DESIGN.md`, `docs/PHASE2_DESIGN.md`,
> `docs/PHASE3_DESIGN.md`, `docs/PHASE5_DESIGN.md`, Plans 011, 016, 023, and
> 024, and `docs/REFERENCE_PROJECTS.md` in full before execution. This plan
> records the product-owner decisions of 2026-08-28. It supersedes Plan 024
> contracts C, E, G, the provider-specific parts of D, and STOP conditions 1
> and 4. Plan 024's card interactions, prompt workflow, dependency gate,
> archive, candidate selection, validated import, and transactional drift
> protection remain authoritative.

## Status

- **Status**: IN PROGRESS — implementation and deterministic verification complete;
  four manual owner requests remain
- **Depends on**: Plan 024 `DONE`
- **Category**: storage / provenance / credentials / provider helper / app / tests
- **Estimated effort**: XL (10–14 engineering days, plus owner manual verification)

## Accepted product decisions

1. Launch with two direct providers: **Google Nano Banana 2** and **OpenAI GPT
   Image 2**. The first built-in model identifiers are
   `gemini-3.1-flash-image` and the pinned OpenAI snapshot
   `gpt-image-2-2026-04-21`.
2. Use Vercel AI SDK Core behind a small provider-neutral helper. There is no
   Vercel AI Gateway, Film Camp server, proxy, or account.
3. Bundle the helper with the app. A filmmaker installs no Node runtime,
   Gemini CLI, Nano Banana extension, or provider wrapper.
4. Remove the Gemini CLI / Nano Banana extension integration completely. It
   is not a fallback and Film Camp does not modify or uninstall the user's
   external Gemini setup.
5. Provider selection is **app-wide and Settings-only**. The Create Reference
   Image sheet shows the selected provider but has no per-generation provider
   override.
6. Each requirement keeps one provider-neutral saved prompt. Switching the
   app-wide provider neither rewrites nor forks that prompt.
7. Provider API keys enter only through dedicated Settings UI, live only in
   macOS Keychain at rest, and are held only long enough to authorize the
   user-initiated request. Settings offers Set/Replace/Remove, never Reveal or
   Copy.
8. Resolution is fixed at **1K** and is not shown as a preset or control. The
   existing smart aspect-ratio policy remains: character/creature `2:3`,
   location/vehicle `16:9`, prop/object `1:1`.
9. Candidate count remains 1 by default and 1–4 per generation. Candidates
   are separate, visible requests so progress and cancellation remain honest.
10. A selected provider with missing credentials or incompatible capabilities
    disables Generate with a precise remedy. Film Camp never silently drops a
    reference, changes an aspect ratio, changes a model, or falls back to a
    different provider.
11. Automated verification is deterministic and free. It uses fake/recorded
    helper responses and never makes a provider request. Real-provider
    acceptance is manual only, performed by the owner with their own keys.

### Product-owner amendment — 2026-08-28: inline credential entry

The product owner superseded decision 5's **Settings-only** entry rule and
contract D's prohibition on accepting a key through a project sheet. Provider
selection remains app-wide and there is still no per-generation override, but
the missing-credential state in Create Reference Image now offers a compact
**Add API Key** control in that same sheet. It lets the filmmaker choose one of
the two built-in providers and enter a blank secure field; a successful
Keychain write also selects that provider app-wide and refreshes generation
readiness in place. A provider whose key is already configured can be selected
without re-entering it. The sheet never reveals, copies, pre-populates, or
persists a key outside Keychain. Settings remains the full Set/Replace/Remove
surface and shows a green provider-specific configured label.

### Product-owner acceptance repair — 2026-08-28: truthful output media and inline errors

The first live Nano Banana acceptance request exposed a result-contract gap:
Google may return either PNG or JPEG image bytes, while helper protocol v1
always wrote and reported the candidate as PNG. Helper protocol v2 reports a
canonical media type and uses the matching `.png` or `.jpg` suffix. FilmBrain
accepts PNG from either built-in provider and JPEG only from Nano Banana, then
requires the reported type, sniffed bytes, suffix, dimensions, workspace
containment, and FilmCore import inspection to agree. OpenAI remains PNG-only.

Generation and candidate-import failures now remain inside Create Reference
Image as an inline error. The prompt, settings, and any pending candidates stay
visible, and another Generate or candidate-selection gesture clears the error
before retrying. These workflow failures no longer raise a Project Error alert
behind the open sheet.

## Primary references pinned for implementation

Re-check these primary sources at execution time and record any contract drift
before changing the adapter:

- [AI SDK `generateImage()`](https://ai-sdk.dev/docs/reference/ai-sdk-core/generate-image)
  and the [Google provider](https://ai-sdk.dev/providers/ai-sdk-providers/google-generative-ai).
  At plan time, the pinned npm versions are `ai@7.0.83`,
  `@ai-sdk/google@4.0.56`, and `@ai-sdk/openai@4.0.50`; the committed lockfile,
  not a range, is authoritative during a build.
- [Google Gemini image generation](https://ai.google.dev/gemini-api/docs/image-generation)
  and [Gemini 3.1 Flash Image](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image).
  The stable Nano Banana 2 identifier is `gemini-3.1-flash-image`; the old
  `-preview` identifier is already deprecated.
- [OpenAI GPT Image 2](https://developers.openai.com/api/docs/models/gpt-image-2)
  and the [official image-generation guide](https://developers.openai.com/api/docs/guides/image-generation).
  GPT Image 2 supports text plus image inputs, direct generation/editing, and
  custom dimensions within documented bounds.
- [Node single-executable applications](https://nodejs.org/api/single-executable-applications.html).
  Use a pinned Node 24 LTS patch and verified upstream binaries; do not depend
  on a filmmaker's host runtime.

## Contracts

### A. Credential lifecycle and trust boundary

- Add an app-service `ImageProviderCredentialStore` protocol and a production
  Security-framework implementation. SwiftUI calls settings-model actions; it
  never calls Keychain APIs directly. FilmCore does not import Security and no
  credential type enters FilmCore.
- Store one generic-password item per provider under a versioned Film Camp
  service name and provider id account. Use the app's default access group,
  `kSecAttrSynchronizable = false`, and
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Store only the key bytes: no
  project id, prompt, model, or reference metadata belongs in the item.
- The app-wide selected provider id is ordinary non-secret preference state and
  may live in `UserDefaults`. Credential bytes may not. Switching providers
  preserves each provider's Keychain item so returning does not require
  re-entry.
- `Set` writes a new item, `Replace` performs an update, and `Remove` deletes
  the exact provider item after a standard confirmation. The UI displays only
  `Not configured` or `Configured`; it never reads a value for display, exposes
  length/suffix, copies it, or pre-populates the secure field.
- Generate is the authorization gesture. At that moment the app service reads
  the selected provider's key as opaque bytes, passes it to FilmBrain for one
  run, and releases references after the helper's stdin has closed. No claim
  is made that Swift/JavaScript process memory can be securely zeroed; the
  enforceable contract is short lifetime and no durable or observable copy.
- The key travels to the bundled helper only in the framed stdin request. It is
  forbidden from argv, environment variables, temporary files, stdout,
  stderr, `ProcessInfo`, crash annotations, `os.Logger`, signposts, analytics,
  job/apply reports, and project data.
- A provider error is untrusted and may echo request material. The helper maps
  it to a small allowlisted error code, HTTP status, retryability, and optional
  provider request id. FilmBrain bounds and parses that envelope. Raw response
  bodies and exception strings never cross into UI or logs.
- Do not add a paid `Test key` action. Readiness means the bundled helper passes
  its local handshake and a key exists. Authentication, quota, billing, and
  model-access failures surface on the first user-requested generation with an
  actionable provider-specific message.

### B. Provider-neutral bundled helper

- Add `Tools/ImageGenerationHelper/`, a TypeScript program using AI SDK Core
  plus only the Google and OpenAI provider packages. Commit `package.json`, the
  exact lockfile, source, schemas, deterministic tests, license notices, and a
  reproducible build script. Never commit `node_modules` or a built binary.
- Bundle the program as a Node 24 LTS single executable named
  `filmcamp-image-helper`. The build script verifies the exact SHA-256 of
  upstream Node binaries, bundles dependencies into one CommonJS payload,
  creates one SEA per supported macOS architecture, combines architectures
  for distribution when both are present, and leaves final nested-code signing
  to Xcode/release signing. A local development build may build only the host
  architecture; the release gate requires the supported distribution
  architectures.
- Add an XcodeGen helper target/build phase that copies the executable to a
  fixed app-bundle location and makes the app target depend on it. The helper
  must receive the same signing identity/team as nested executable code.
  Hardened Runtime, notarization, and archive validation must treat it as code,
  not an unsigned resource.
- FilmBrain locates only that fixed bundle helper. Delete executable-name PATH
  discovery, absolute executable overrides, `gemini extensions list`, trust
  flags, supplemental policy files, and every Nano Banana MCP invocation
  builder. A missing, non-regular, non-executable, wrongly signed, or
  protocol-incompatible helper is an app-build/install error with a repair
  message, never a search for another host executable.
- The helper supports two modes:

  - `--capabilities` emits one bounded JSON document with helper/protocol
    version, provider ids, model ids, aspect ratios, reference limits, and
    output formats. It reads no stdin secret and makes no network request.
  - `--stdio` reads exactly one length-prefixed JSON request from stdin, closes
    stdin after decoding, performs exactly one provider image request, writes
    exactly one result file using the predeclared candidate path stem, and
    emits bounded NDJSON lifecycle/result events on stdout. The terminal result
    carries the final path and canonical media type; protocol v2 may change the
    requested `.png` suffix to `.jpg` only for a Google JPEG result.

- Version the request/result schema from the first commit. Reject unknown
  protocol major versions, unknown fields where ambiguity could affect cost or
  media, paths outside the disposable job directory, malformed image inputs,
  duplicate output, oversized frames, extra stdout after terminal result, and
  multiple output files.
- The request contains provider id, model id, one prompt, ordered copied
  reference paths plus semantic kinds, exact target dimensions/aspect ratio,
  output path/format, and the ephemeral key. It never contains project-bundle
  paths: FilmCore returns verified bytes and the app copies them into the
  disposable job directory before FilmBrain launches the helper.
- Configure AI SDK with explicit provider instances (`apiKey` supplied in
  memory), `maxRetries: 0`, and an app-owned timeout/cancellation signal. One
  Generate for `N` candidates launches `N` sequential one-candidate helper
  processes. This avoids hidden paid retries, keeps progress `i/N` truthful,
  limits credential lifetime. Plan 033 supersedes Plan 024's window-wide
  cancellation semantics with active-item cancellation inside a FIFO.
- Preserve `FoundationProcessRunner`'s process-group
  interrupt/terminate/kill ladder and bounded pipes, extending its tested seam
  only as needed for framed stdin. Adopt no terminal, IDE, Git, session, shell,
  or MCP surface from the reference projects.

### C. Built-in provider catalog and capability rules

- Replace `ImageGeneratorPreset`'s executable/extension fields with a
  provider-neutral `ImageProviderDescriptor`: stable provider id, display
  name, credential label/help URL, model id, supported reference categories
  and counts, supported semantic aspect ratios, concrete 1K dimensions,
  output format, and helper protocol requirement. Descriptors are code-owned,
  immutable at runtime, and app-wide.
- Initial descriptors:

  | Provider | Model | 1K request mapping | References |
  |---|---|---|---|
  | Google — Nano Banana 2 | `gemini-3.1-flash-image` | AI SDK `aspectRatio` `2:3`, `16:9`, or `1:1`; Google `imageSize = 1K` | up to 14 total, with Google limits of 4 character references and 10 object/non-character references |
  | OpenAI — GPT Image 2 | `gpt-image-2-2026-04-21` | exact valid custom sizes `768x1152`, `1280x720`, or `1024x1024` | multi-image reference/edit input, capped by Film Camp at the same 14-reference product ceiling |

- The OpenAI dimensions are deliberate exact-ratio, roughly-1K mappings that
  satisfy GPT Image 2's documented multiples-of-16, pixel-count, and ratio
  bounds. They are not exposed as a resolution chooser. Google receives its
  native 1K setting. Validate actual output dimensions against a provider-aware
  tolerance/contract before FilmCore preflight; never stretch or crop an
  output silently.
- Extend each ordered FilmCore dependency with its entity kind so FilmBrain can
  enforce Google's character/object sublimits without inferring from names.
  Creature references count as characters; locations, vehicles, props, and
  objects count as non-character objects for the provider gate.
- Capability evaluation is a pure FilmBrain function. The selected provider
  must support the target semantic ratio, total references, category limits,
  image input, and configured model. A failure disables Generate and names the
  selected provider, violated limit, and Settings remedy. It never removes an
  input or switches provider/model.
- Provider adapters translate only after the neutral request validates. Google
  uses `google.image(...)` with a prompt object containing the ordered image
  bytes. OpenAI uses `openai.image(...)`; no-reference work goes through image
  generation and referenced work through the provider's image-edit path as
  selected by the AI SDK provider. OpenAI explicitly requests and requires PNG.
  Google uses its native 1K image response and may return PNG or JPEG; the
  helper preserves the actual format rather than relabeling or transcoding it.
- Adding a third provider later means one helper adapter, one descriptor, one
  Keychain account label/help link, provider contract fixtures, and settings
  copy. FilmCore schema and the Create Reference Image sheet do not change.

### D. App-wide settings and generation UX

- Replace the current Gemini executable override settings with an **Image
  Provider** section containing one app-wide provider picker and the selected
  provider's credential card. Default existing installs to Google/Nano Banana
  2; migrate the old `nano-banana` preset id to the new Google provider id and
  remove the obsolete executable-override preference. Do not inspect or alter
  Gemini CLI/extension configuration.
- Credential entry is a blank `SecureField` plus Set or Replace. After a
  successful Keychain mutation, clear the field immediately. Remove is
  available only when configured. Provider help links open the official key
  creation/account page. Per the 2026-08-28 amendment, the Create Reference
  Image sheet may use the same app-service action to add a missing key and
  select that provider app-wide; the secure-field and Keychain rules are
  identical to Settings.
- The Create Reference Image sheet shows a non-interactive line such as
  `Using Nano Banana 2` or `Using GPT Image 2`, candidate count 1–4, the saved
  prompt editor, references, progress, and Generate. It exposes no provider
  override while ready. Its missing-key state may expand an inline built-in
  provider picker solely to set the app-wide provider and credential; it
  exposes no per-generation provider picker, model picker, resolution control,
  executable path, authentication diagnostic dump, intermediate approval, or
  completion/Done screen.
- If not ready, replace generic Gemini CLI failure copy with inline state:
  `Missing image generation API Key` plus a small `Add API Key` action,
  helper-build failure, or the exact capability refusal. A successful key
  write replaces the missing state with a green provider-specific checkmark.
  Other setup failures retain a Settings action. A provider error leaves the
  prompt and sheet open for correction/retry.
- The existing Generate click remains the only outbound consent gesture and
  starts immediately. Nearby disclosure says the prompt and listed reference
  images are sent directly to the named provider using the user's key and may
  incur provider charges. Candidate count makes the request count explicit.
- Preserve Plan 024 behavior after success: one candidate commits/current
  immediately and closes/refreshes the sheet; 2–4 candidates display the
  chooser; unselected candidates archive on selection. Provider selection
  cannot change an in-flight run; each run captures its provider/model in the
  commit token at start.

### E. FilmCore provenance and schema v10

- Add an additive bundle-schema migration from v9 to v10. Old projects migrate
  without network/Keychain access and without fabricating provider provenance.
  Existing/manual asset versions keep nullable generation lineage.
- Add `image_generation_runs` with a generated id, requirement id, prompt id
  (nullable on later prompt deletion), provider id, model id, helper/protocol
  version, prompt-body SHA-256, semantic aspect ratio, requested width/height,
  fixed resolution label, requested candidate count, selected candidate index,
  and creation time. No credential, raw prompt body, provider response body,
  or app preference enters this row.
- Add ordered `image_generation_references` rows keyed by run and position.
  Each records referenced requirement id, nullable version id, immutable SHA-256
  and byte count, and semantic entity kind. Deleting an asset version may null
  the FK but must not erase the historical hash.
- Add nullable `image_generation_run_id` and `generation_candidate_index` to
  `asset_versions`, with uniqueness within a run. Extend `AssetVersion` reads
  with a separate optional neutral generation-provenance view rather than
  provider-specific fields on the base domain type where that keeps existing
  screens simpler.
- Introduce FilmCore `ImageGenerationCommitMetadata`, structurally bounded and
  provider-neutral. It contains identifiers/settings/protocol facts only; it
  cannot contain a credential. FilmCore validates ids, counts, indexes,
  dimensions, hashes, and agreement with the existing
  `ReferenceImageGenerationContext`.
- Extend `importGeneratedCandidates` so the generation run, ordered reference
  snapshots, candidate versions, selected approval, prior-current demotion,
  prompt lineage, and journal inverse all commit in the existing single
  transaction. A mismatch rolls back every row and removes every staged file.
- Rebuild the context inside the write transaction exactly as Plan 024 does.
  Add provider id/model/protocol and fixed settings to the captured run token
  so a Settings change during generation does not relabel a result. It may
  finish under the provider it started with; the next run uses the new app-wide
  selection.
- Undo/redo, archived restore, permanent archived deletion, prompt deletion,
  and orphan cleanup must preserve relational integrity. Deleting a generated
  candidate removes only its version/run linkage; delete the run row only when
  no candidate versions reference it, or retain it as provenance according to
  the migration's explicit FK policy. Test and document the chosen policy
  before landing the migration; recommendation: retain the run while any
  candidate exists and cascade it only when the last candidate is permanently
  deleted.

### F. Diagnostics, privacy, and security checks

- Replace Plan 024's credential-free environment assertion with a stronger
  transport assertion: the real key is absent from environment and argv and
  appears only in the bounded stdin frame. The helper receives a minimal
  allowlisted environment and no proxy URL containing userinfo.
- Redact by construction, not regex after logging. Diagnostic structures use
  enums and bounded public fields. Neither request JSON nor helper stderr is
  ever logged wholesale. `description`, `debugDescription`, Equatable failure
  messages, crash breadcrumbs, and test failure output must not serialize the
  credential-bearing request.
- The helper never enables AI SDK telemetry, OpenTelemetry exporters, request
  middleware logging, or provider debug logging. No analytics event contains a
  prompt, reference path/hash, key state beyond a boolean, provider request
  body, or generated bytes.
- Validate the bundled executable before every run or cache a validation tied
  to bundle identity/version. Capability output is untrusted and bounded.
  Output media remains untrusted and passes FilmBrain checks plus FilmCore's
  repeated magic-byte/dimension/containment/SHA validation.
- Do not automatically retry paid requests. The UI may offer a user-initiated
  retry after a transient error; that is a new Generate gesture and a new
  potentially billable request.

### G. Deterministic verification and manual acceptance

No automated lane may call Google, OpenAI, Vercel, Gemini CLI, or any other
network provider. No real API key is required by CI or stored in repository
configuration.

Automated coverage:

- **Helper unit/contract tests**: request schema, each provider translation
  against injected fake AI SDK models/transports, exact aspect/dimension
  mapping, ordered multi-reference bytes, truthful PNG/JPEG result typing,
  bounded result/error
  envelopes, no retries, timeout, cancellation, and no request/credential echo.
- **Packaging tests**: locked dependency install, license/known-vulnerability
  audit policy, reproducible bundle step, `--capabilities`, host-architecture
  launch, protocol mismatch, missing/tampered helper, and nested-code-signature
  validation where the test environment is signed.
- **FilmBrain tests**: provider catalog, configured/unconfigured state,
  capability mismatches, framed stdin, sequential 1–4 processes, progress,
  cancellation process-group ladder, output/path/size limits, sanitized error
  mapping, and removal of every Gemini CLI discovery/invocation path.
- **FilmCore tests**: v9→v10 migration, empty legacy provenance, generated-run
  reads, all-or-nothing candidate import, provider/model/settings lineage,
  reference hash order, stale context refusal, undo/redo, archive restore,
  deletion policy, and no credential-shaped schema fields or persisted values.
- **App unit/headless/UI tests**: app-wide provider switching, Keychain service
  through an injected in-memory fake, Set/Replace/Remove state without reveal,
  selected-provider readiness, Settings deep link, no provider/resolution
  override in the sheet, request-count disclosure, direct Generate, progress,
  candidate choice, success refresh, and sanitized failures.
- **Secret non-observability test**: use a synthetic sentinel (not a provider
  credential), force success/failure/cancel paths, and assert it is absent from
  argv, environment, stdout/stderr, diagnostics, logs captured by test doubles,
  UserDefaults, temp file names/content other than the single stdin pipe,
  project database/bundle, and journal/apply reports.

Manual owner verification only:

1. Build a signed app containing the helper; verify no Gemini CLI, extension,
   Node, or wrapper is installed or found by the app.
2. In Settings, enter a Google key, select Nano Banana 2, and generate one
   canonical image plus one one-reference variation at candidate count 1.
3. Enter an OpenAI key, select GPT Image 2, and repeat the same canonical plus
   variation checks at candidate count 1.
4. For each provider, confirm immediate generation from the first click,
   progress/cancel behavior, correct aspect, current/archive behavior, and
   provider/model provenance. Then Remove each test credential in Settings if
   desired.
5. Record only pass/fail, app/helper versions, provider/model ids, and any
   sanitized request id. Do not record keys, prompts, reference bytes, raw
   errors, generated image data, or account/billing details.

Candidate counts 2–4, provider failures, retries, and capability mismatches are
accepted through deterministic fakes; there is no paid automated acceptance
suite and no required recurring live-provider gate.

## Steps

### Step 1 — Reconcile rules, intent docs, and the supersession boundary

- Replace `AGENTS.md`'s absolute credential prohibition with contract A (done
  when this plan was authored).
- Amend `docs/ROADMAP.md` and `docs/OVERVIEW.md` so locally authenticated agent
  CLIs remain credential-external while direct still-image providers use the
  Keychain-only BYOK carve-out. Sweep every pinned document hash in the same
  commit as required by `check-docs.sh`.
- Add a dated forward-amendment note to Plan 024 and the relevant accepted
  design sections. Do not rewrite historical decisions: state precisely that
  Plan 025 supersedes the local Gemini adapter while retaining Plan 024's UI,
  archive, dependency, and transaction contracts.
- Record current official API/AI SDK/model contracts and the selected pinned
  dependency/runtime versions in implementation notes.

### Step 2 — Land schema v10 and provider-neutral provenance

- Add migration/domain/read/write contracts from §E first.
- Extend controlled import and journal snapshots without importing FilmBrain.
- Land migration, storage, transaction, undo/redo, archive/deletion, and drift
  tests before any network/helper code.

### Step 3 — Build and package the helper with recorded provider adapters

- Add the locked TypeScript helper, schema, fake provider seams, provider
  adapters, error sanitizer, and SEA build.
- Add XcodeGen packaging/signing and a deterministic helper handshake test.
- Demonstrate both adapters end-to-end against local fake HTTP/AI SDK models;
  make no real provider call.

### Step 4 — Replace FilmBrain's Gemini adapter

- Delete Gemini discovery, extension config parsing, MCP policy/request
  builders, executable override, and provider-specific error copy.
- Add descriptor/capability evaluation, bundle-helper validation, framed stdin,
  sequential candidate driver, sanitized errors, and provenance output.
- Extend `FoundationProcessRunner` only through the existing tested process
  seam; preserve bounded IO, cancellation, and process-group cleanup.

### Step 5 — Add Keychain settings and wire the app workflow

- Add the credential-store app service and injected fake; never place Security
  calls in SwiftUI.
- Replace settings and preferences, migrate old selection state, and wire the
  selected provider/readiness into the window model.
- Keep the ready creation sheet to current-provider display plus candidate
  count. In the missing-key state, reuse the app credential service through an
  inline built-in provider picker and blank secure field, selecting the saved
  provider app-wide; preserve direct Generate and the existing
  candidate/archive behavior.
- Attach the neutral generation provenance to the FilmCore import after
  revalidating the original prompt/dependency context.

### Step 6 — Verify without paid automation, then perform the manual check

- During iteration run `DRY_RUN=1 scripts/test-changes.sh <base-ref>`, then the
  selected lanes. Before committing each implementation slice, run the lanes
  covering that slice and require green results.
- Run `scripts/check-docs.sh`, helper tests/audits, FilmCore tests, FilmBrain
  tests, app unit/headless tests, build-for-testing, and the affected UI
  journeys. The full `./scripts/verify.sh` remains optional under repository
  rules but is recommended for the final integration.
- After deterministic gates pass, ask the owner to perform §G's four manual
  provider requests. Do not automate them and do not add an environment flag
  that CI could accidentally enable.
- Record verification in this plan and `docs/IMPLEMENTATION_NOTES.md`, flip the
  README row to `DONE`, and commit. Never push or open a PR unless asked.

## Commit sequence

Prefer small reversible commits in this order:

1. `docs(plan): specify multi-provider BYOK image generation`
2. `feat(core): persist provider-neutral image generation provenance`
3. `feat(helper): bundle AI SDK image provider executable`
4. `refactor(brain): replace Gemini CLI with provider helper`
5. `feat(app): add Keychain provider settings and direct generation`
6. `test(image): cover provider workflow and record manual acceptance`

Do not combine schema migration with helper/provider code; the storage contract
must be reviewable and green independently.

## Deterministic verification — 2026-08-28

- Toolchain: Xcode 26.6 (build 17F113), Apple Swift 6.3.3, XcodeGen 2.46.0,
  Node 24.14.1; warm repository caches.
- `npm run check` and `npm test` in `Tools/ImageGenerationHelper`: **PASS** —
  TypeScript validation plus 7 provider-neutral protocol/adapter tests. The
  adapter fakes assert explicit provider/key/model selection, Google native 1K
  aspect options, OpenAI exact PNG dimensions, ordered references, and
  `maxRetries: 0`; they perform no network request.
- `npm audit --omit=dev --audit-level=high`: **PASS** — 0 known
  production-dependency vulnerabilities reported at verification time.
- `./scripts/build-image-helper.sh`, bundled `--capabilities`, and
  `codesign --verify --deep --strict`: **PASS** — the host-architecture arm64
  build verified the official Node 24.14.1 archive against its pinned SHA-256;
  the resulting SEA launches from the built app's fixed `Contents/Helpers`
  location and validates as nested signed code. The release-mode
  `FILMCAMP_IMAGE_HELPER_ARCHITECTURES='arm64 x86_64'` path also produced a
  launchable, signed universal Mach-O from the two separately verified upstream
  archives; normal developer builds intentionally emit only the host slice.
- `DRY_RUN=1 ./scripts/test-changes.sh 41aeba9`: selected the full gate because
  the change covers schema, provider helper/tooling, XcodeGen, app, and docs.
- `VERIFY_CACHE_STATE=warm ./scripts/verify.sh`: **ALL GREEN** — docs; 797
  FilmCore tests; 139 FilmBrain tests; build-for-testing; 102 XCTest plus 10
  Swift Testing app/headless tests; `SceneWorkspaceSmokeUITests`; and the eval
  gate (honestly skipped because no committed eval report exists). Timing:
  FilmCore 15s, FilmBrain 5s, build 5s, app tests 211s, UI 51s. The app-test
  body remained green; most of that 211s was macOS test-host attachment delay.
- No live provider, Gemini CLI, Codex, or credential-bearing test lane was
  enabled. The remaining acceptance evidence is exactly the four manual owner
  requests in §G: canonical plus one-reference variation for each provider.
- Inline credential-entry amendment: `scripts/test-changes.sh 405dfd6` passed
  docs, 797 FilmCore tests, 139 FilmBrain tests, build-for-testing, every app
  unit/headless test, and `SceneWorkspaceSmokeUITests`. Added deterministic
  coverage proves an open Create Reference Image workflow can refresh from
  missing to ready without resetting its requirement or generation context.
  No live provider request or real credential was used.
- Truthful-media/inline-error repair: TypeScript checking and all 10 helper
  tests passed; FilmBrain passed all 140 tests, including a native Google JPEG
  result; build-for-testing passed; and all 104 XCTest plus 10 Swift Testing
  app/headless tests passed, including the inline error-state regression. The
  repository full-gate attempt also passed docs and all 797 FilmCore tests. Its
  UI runner could not begin `SceneWorkspaceSmokeUITests` because macOS timed
  out while enabling automation mode on the scripted retry and an explicit
  arm64 retry; no UI test case or assertion failed. No live provider request or
  real credential was used.

## Done criteria

- [x] Google Nano Banana 2 and OpenAI GPT Image 2 are selectable app-wide in
      Settings and use the documented fixed models/defaults.
- [x] The Create Reference Image sheet has no provider override and no
      resolution control; Generate starts on its first click.
- [x] Provider keys can be added from the missing state and
      Set/Replaced/Removed through Settings, exist at rest only in Keychain,
      and never appear in project/user defaults/argv/env/files/logs/diagnostics/
      analytics/tests/source/UI.
- [x] The signed bundled helper works without Gemini CLI, its extension, Node,
      or another user-installed wrapper/runtime.
- [x] The Gemini CLI adapter and executable override are removed with no hidden
      fallback.
- [ ] Both providers accept canonical generation and ordered reference-image
      variation through one neutral request contract; missing/incompatible
      state disables only the selected provider with no silent degradation.
- [x] Candidate count 1–4, progress, cancellation, output validation, selection,
      archive, staleness, and all-or-nothing import preserve Plan 024 behavior.
- [x] Every generated version records provider/model/helper/settings/prompt and
      ordered-reference provenance in schema v10 without storing request secrets
      or raw provider responses.
- [x] All deterministic helper/package/core/brain/app/UI/doc gates pass without
      a network provider request.
- [ ] The owner manually verifies one canonical and one referenced generation
      with each provider; no paid automated test or recurring live gate exists.

## STOP conditions

1. A key would be stored outside Keychain, sent by argv/environment/file,
   revealed in UI, or exposed through diagnostics, logs, analytics, tests, or
   source.
2. The helper cannot be bundled and signed so a filmmaker needs to install a
   runtime, CLI, extension, or wrapper.
3. A provider cannot preserve the required ordered canonical dependencies or
   exact smart aspect ratio without silently dropping/changing input.
4. Provider-specific request/response objects would enter FilmCore, or SwiftUI
   would need Security, process, transport, parsing, validation, or storage
   logic.
5. Any candidate/version/provenance row could land before every selected output
   and the prompt/dependency/provider run token validate, or a multi-candidate
   import could partially commit.
6. Automated verification would make a potentially billable provider request
   or require a real API key.
7. Work expands into a hosted gateway/backend, generated video, takes, clips,
   review/history sheets, editing, rendering, arbitrary provider/model entry,
   arbitrary command templates, or general-purpose credential storage.
