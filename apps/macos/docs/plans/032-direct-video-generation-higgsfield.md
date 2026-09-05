# Plan 032: Direct video generation through integrations — Higgsfield first (Phase 5d)

> Read `docs/PHASE1_DESIGN.md`, `docs/PHASE5_DESIGN.md`, Plans 021–025,
> and `docs/REFERENCE_PROJECTS.md` in full before execution. This plan records
> the product-owner boundary change of 2026-09-01: Film Camp no longer stops at
> Generation Ready. It may submit prepared prompt cards through replaceable
> provider integrations and deliver validated immutable generated video to the
> editing handoff. Higgsfield is first. Re-run Step 0 because the provider's
> CLI, MCP OAuth, model catalog, and schemas change independently of the app.

> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   8660b7114aa507a98ec2cf621176355cb912b749ff3b84395e6f4af6fb927691 docs/OVERVIEW.md \
>   1f0e224d9d668bc10fa01ab55bf60e115b14bafd0931eb81c26d152d5a4467ac docs/ROADMAP.md \
>   bd477ef76dbb98c2f7dbffdae5310b8f824e309e904bcd91f03cca2004eb7ee1 docs/PHASE5_DESIGN.md \
>   282b1ae714029b96e932bff1eba236df0e05b76abc1fe6b434f90f11ca418d46 docs/REFERENCE_PROJECTS.md \
>   | shasum -a 256 -c -
> ```
>
> Reconcile any mismatch before execution. A Higgsfield provider/model/transport
> drift is handled by Step 0; a changed product boundary, ownership rule, or
> credential policy requires an owner decision rather than a local re-pin.

## Status

- **Status**: TODO — boundary accepted; research complete; Step 0 must select
  and pin a safe Higgsfield transport and exact Seedance 2.5 contract
- **Depends on**: Plans 022–025; reconcile the current schema-v14 work and its
  verification baseline before assigning schema v15
- **Category**: provider integration / video generation / asynchronous jobs /
  storage / provenance / credentials / media validation / app
- **Priority**: P1 — this is the primary purpose of the integration
- **Estimated effort**: XL (15–22 engineering days after Step 0 passes, plus
  explicitly approved live contract and acceptance requests)

## Accepted product decisions

1. **Direct generation is the feature.** A filmmaker can generate a current
   scene prompt card through Higgsfield without rebuilding its prompt,
   references, or settings in the Higgsfield web application.
2. **The architecture is provider-neutral.** FilmCore stores neutral requests,
   jobs, inputs, lifecycle, provenance, and outputs. FilmBrain owns transport
   and validation. Higgsfield types never enter FilmCore or SwiftUI.
3. **Higgsfield is provider one; Seedance 2.5 is activation target one.** Never
   run a Seedance 2.5 prompt through Seedance 2.0 or another model silently.
4. **CLI and MCP are candidate transports, not product concepts.** Step 0 pins
   the smallest surface that proves the exact model and safety contract. The
   app exposes “Higgsfield,” not a routine CLI/MCP picker. There is no silent
   per-job transport fallback.
5. **One Generate gesture creates one paid job.** No hidden retry, candidate
   batch, provider fallback, or automatic paid batch generation. A retry is a
   second explicit human gesture and a second recorded job.
6. **Jobs are durable.** A submitted paid job survives app close/crash and can
   resume polling. Local cancellation must not pretend to cancel or refund a
   remote job unless Higgsfield proves that contract.
7. **Outputs are immutable production handoffs.** Film Camp downloads,
   validates, stores, plays, reveals, removes, and exports generated video. It
   does not rate/approve takes, compare cuts, trim, assemble a timeline,
   composite, grade, mix, or render a final movie.
8. **Portable export remains first-class.** A project can reach Generation
   Ready and export packages with no provider installed or authorized.
9. **Credentials remain outside project data.** API keys, OAuth tokens, CLI
   credential files, signed URLs, and raw provider output never enter a bundle,
   defaults, logs, diagnostics, fixtures, analytics, source control, or UI.
10. **Live requests are manual gates.** Every live Higgsfield request needs a
    dedicated environment flag, immediate operator approval, and never runs in
    CI.

## Revised product boundary

```text
Current prompt card + exact ordered references + target settings
                              |
                              v
                    explicit paid consent
                              |
                              v
                    Higgsfield provider job
                              |
                    durable poll / recovery
                              |
                              v
                restricted download + validation
                              |
                              v
               immutable local generated video
                              |
                              v
                    Play / Reveal / Export
                              |
                              v
                       external editor
```

The boundary now includes provider submission and generated-media delivery. It
ends before editorial post-production. A generated output is not a `Shot`, an
approved `Take`, or a timeline clip. The scene and prompt card remain the
production units; the job is a receipt for executing one card.

## Scope

### In scope

- One Higgsfield integration in app-wide Settings.
- One **Generate Video** action per fresh Seedance 2.5 prompt card.
- Exact prompt body, ordered card references, duration, aspect ratio,
  resolution, and audio generation setting.
- Optional cost preflight only if it is side-effect-free and contractually
  reliable; otherwise clear credit disclosure without invented estimates.
- Durable submit, poll, cancel-or-stop-waiting, restart recovery, terminal
  failure, result retrieval, and expiry handling.
- Bundle-contained immutable video output with digest, dimensions, duration,
  container/codec facts, and exact request provenance.
- Inline progress and recorded output playback/reveal/export/removal.
- A provider adapter seam suitable for later Kling, Veo, Runway, or other
  integrations without another FilmCore schema redesign.

### Not in scope

- Reference-image generation through Higgsfield; Google/OpenAI Plan 025 remains.
- Shot planning, per-shot prompt decomposition, or a `Shot` table.
- Take labels, ratings, approvals, side-by-side comparison, or editorial notes.
- Automatic retry, auto-cheapest/auto-best routing, cross-provider fallback, or
  autonomous generation.
- Paid batch generation, sequences, playlists, timelines, trimming,
  transitions, compositing, effects, grading, audio editing/mixing, titles, or
  final rendering.
- Uploading generated outputs to a Film Camp cloud service.
- General-purpose MCP tools, Higgsfield Soul/audio/history/balance/website
  surfaces, or arbitrary model discovery in the UI.

## Research findings pinned on 2026-09-01

### Higgsfield CLI

- The official CLI supports authenticated image/video jobs, JSON output,
  submit/get/wait commands, wait timeout/polling flags, and local media paths
  that it uploads. The official skills document also describes stdin prompt
  input; Step 0 must prove that this works for the selected video job rather
  than only a subset of models.
- Inspected release `1.1.24` reports build
  `74e091aaff646537b8f77d42e695ecccafbaa761` from 2026-08-29. Its darwin-arm64
  archive matched the published SHA-256
  `cf23707ea8f437c93102d891125c10318c5812233f60b4c3bfda2d1d5334fe4b`.
- Its public repository contains documentation, installer, licenses, and
  notices, but no CLI implementation source. The macOS binary was locally
  observed linker/ad-hoc signed as `Identifier=a.out` with no Team ID.
- CLI auth uses an independently managed OAuth session/local credential file.
  `auth token` prints the access token and is forbidden to Film Camp.
- The checked-in 1.1.24 model catalog documents `seedance_2_0`, not
  `seedance_2_5`. It allows 9 image, 3 video, and 3 audio inputs with a 12-file
  total for 2.0. Those limits must not be applied to 2.5 by analogy.

### Higgsfield MCP and current model surface

- Higgsfield advertises MCP as a remote OAuth service with asynchronous
  generation and broad image/video/Soul/audio/history capabilities. Its public
  MCP/model pages advertise Seedance 2.5, up to 30 seconds, synchronized audio,
  and a much larger reference surface than the checked-in CLI 2.0 catalog.
- MCP is therefore a credible route to the app's existing Seedance 2.5 target,
  but it adds Streamable HTTP, OAuth discovery/PKCE/refresh/revocation, dynamic
  tool schemas, and a broad authority surface that Film Camp must hard-allowlist.
- Unauthenticated probing returned standards-based protected-resource metadata,
  while recent public issue reports describe OAuth issuer/registration failures.
  Treat issue reports as risk signals, not universal current behavior.
- CLI and MCP generation always consume credits at standard rates; web-plan
  unlimited/free generation does not apply. Generated media remains in the
  user's Higgsfield Assets.

### Consequence

The existing prompt profile is Seedance 2.5, while the inspected CLI's static
catalog is Seedance 2.0. Step 0 must query the live authenticated surfaces and
choose deliberately:

- Prefer the CLI only if it exposes an exact, stable Seedance 2.5 schema and
  meets prompt, job, cost, cancel/resume, and result safety contracts.
- Otherwise prefer a narrowly allowlisted native MCP adapter only if OAuth and
  the Seedance 2.5 tool contract pass the same gates.
- If neither surface passes, stop. Do not downgrade the target or ship a button
  that opens Higgsfield without completing the direct-generation loop.

## Architecture

```text
SwiftUI
  Scene prompt card / Settings / output player
                    |
                    v
App coordination and Keychain service
                    |
                    v
FilmBrain VideoGenerationProvider
  capability + auth + cost? + submit + poll + cancel? + fetch
                    |
          +---------+---------+
          |                   |
          v                   v
  Higgsfield CLI       Higgsfield MCP
  candidate adapter    candidate adapter
          \                   /
           +--------+--------+
                    |
                    v
FilmCore generation request/job/input/output records
  + controlled lifecycle + media containment + provenance
```

Only one Higgsfield adapter ships after Step 0. Later providers add a descriptor
and adapter; they do not add provider columns or execution code to SwiftUI.

Reference-project borrowing remains narrow:

- AIWorkstation: Finder-safe external executable discovery if CLI wins.
- RxCode: backend/capability/event separation.
- swift-acp: bounded process lifecycle and process-group termination.
- Calyx: explicit, reversible provider configuration and normalized status.
- Reject PTY/terminal UI, IDE/Git/session scope, silent config mutation,
  unrestricted MCP, arbitrary tool calls, and general agent orchestration.

## Step 0 — live contract and transport selection

No production code starts until this step has a dated redacted capture. Model
listing/auth probes should be free. Paid generation/cancellation probes require
separate immediate approval.

### A. Exact Seedance 2.5 capability

1. Query the live CLI model list/schema and MCP tool list/schema from a clean
   authenticated session.
2. Require an exact Seedance 2.5 identifier and stable mapping for prompt,
   ordered image references, duration through 30 seconds, Film Camp's ratios,
   `480p`/`720p`, and synchronized-audio on/off.
3. Record maximum images, total media, byte/dimension/media restrictions, prompt
   limit, output count, and any eligibility/content-safety preflight.
4. Refuse a prompt card that exceeds the chosen surface. Never truncate,
   reorder, coerce, or silently route to Seedance 2.0.

### B. Prompt and reference privacy

1. CLI candidate: prove Seedance 2.5 accepts the prompt through stdin or a
   mode-restricted request file. Prompt text may not enter argv/environment.
2. Copy verified reference bytes into random-named, mode-restricted staging;
   provider arguments never contain project paths, scene names, or asset names.
3. Prove repeated media inputs preserve Film Camp's card order and map to the
   designators used by the prompt. An ordered array without usable reference
   addressing is a STOP condition.
4. MCP candidate: bound and schema-validate the exact JSON request; allow only
   the selected video tool and required read-only protocol methods.

### C. Authentication and authority

1. CLI candidate: user installs/logs in outside Film Camp. Locate and probe the
   executable without reading/copying credentials and without `auth token`.
2. MCP candidate: complete OAuth discovery, authorization-code + PKCE (or the
   officially required native flow), refresh, revocation, logout, reconnect,
   and denial. Store access/refresh credentials only in Keychain through the
   dedicated integration settings service.
3. Confirm the smallest scopes and tool authority. If MCP cannot be restricted
   client-side to the selected generation contract, STOP.

### D. Cost, submit, idempotency, and job recovery

1. Determine whether cost estimation is documented, exact, side-effect-free,
   and does not upload media. If not, omit an estimate and show honest standard-
   credit disclosure plus exact request settings.
2. Record submit JSON, remote job ID, status sequence, poll cadence/rate limits,
   failure codes, terminal results, and job/result retention.
3. Require a durable remote job ID immediately after successful submission.
   Probe an idempotency/client-request key. If none exists, document the narrow
   crash window and ensure Film Camp never automatically resubmits an ambiguous
   request.
4. Establish remote cancel. If cancellation only stops local polling, label it
   **Stop Waiting**, keep the job resumable, and state that credits/job continue.
   If neither remote cancel nor reliable resume exists, STOP.
5. Determine provider/server retry behavior. A hidden paid retry, adjustment,
   model fallback, or duplicate job that cannot be disabled/detected is a STOP.

### E. Result delivery

1. Record terminal result schema, number of outputs, signed URL host/redirect
   chain and lifetime, file size/type, and whether the transport offers a safe
   download-to-path command/tool.
2. Require exactly one video for the submitted card. Reject ambiguity, extra
   media, semantic `adjustments`, and model/settings mismatch.
3. If Film Camp must download a URL, establish a stable HTTPS host allowlist and
   redirect policy. A generic arbitrary-URL fetcher is forbidden.
4. Record actual MP4/container, video/audio codec, dimensions, duration, and
   audio presence for the requested contract.

### F. Supply chain and transport decision

1. Re-check CLI release version/checksum/signature/notarization/source posture,
   licenses, and update compatibility. Film Camp never auto-installs or pipes an
   installer. Prefer Homebrew/manual verified installation in help copy.
2. Re-check MCP endpoint metadata, OAuth topology, protocol version, tool schema,
   and server identity.
3. Score both transports against: exact model, prompt privacy, ordered refs,
   settings fidelity, auth containment, cost honesty, job identity,
   cancel/resume, result safety, implementation/audit surface, and UX.
4. Pin one adapter ID, protocol/schema fingerprints, allowed version range, and
   compatibility fixtures. Record why the other route was rejected/deferred.

### G. Paid probes

With `FILMCAMP_RUN_LIVE_HIGGSFIELD=1` and immediate owner approval:

1. One minimal 480p/720p Seedance 2.5 request with disposable synthetic prompt
   and one synthetic reference.
2. A separate cancel/resume probe only if required and separately approved.
3. Capture only redacted field names/types, state transitions, hostnames,
   settings echo, size/duration/codec facts, adapter/model/version, and sanitized
   error codes. Never capture prompt, media, token, signed URL, raw output,
   account/workspace identity, or billing details.

Step 0 exits with `docs/plans/captures/higgsfield-video-contract-YYYY-MM-DD.md`.
If a required gate fails, mark this plan
`BLOCKED` and return for a product/transport decision.

## Contracts

### A. Provider-neutral FilmBrain API

- Add `VideoGenerationProvider` with typed `probe`, optional `quote`, `submit`,
  `poll`, optional `cancel`, and `retrieve` operations. Every operation receives
  a validated neutral request and returns closed, bounded event/result types.
- `VideoGenerationProviderDescriptor` pins provider/adapter/model IDs, display
  labels, transport/auth kind, allowed durations/ratios/resolutions/audio,
  reference/media limits, output contract, and compatibility versions.
- Capability evaluation is pure and runs before any paid request. It returns a
  precise refusal; it never edits inputs or selects a substitute.
- Provider stdout, stderr, MCP payloads, errors, and URLs are untrusted. Parse
  exact allowlisted fields, enforce byte/depth/event bounds, reject unknown
  semantic adjustments, and map to small sanitized error codes.

### B. Higgsfield adapter

If CLI wins:

- Add a Finder-safe `HiggsfieldCLILocator`, absolute Settings override, bounded
  version/model probes, direct `Process` execution, minimal environment, stdin
  prompt, random reference staging, and process-group shutdown. Strip all
  credential/config overrides and provider-key variables.
- Settings links to official install/login instructions and refreshes readiness;
  it never installs, updates, logs in/out, opens a token command, or mutates CLI
  config.

If MCP wins:

- Add a small Streamable HTTP MCP client in FilmBrain with fixed server identity,
  bounded initialize/tool-list/tool-call behavior, version negotiation, and an
  exact tool allowlist. Do not introduce a generic app-wide MCP host.
- Add app-owned OAuth/Keychain service and dedicated Connect/Disconnect UI.
  FilmCore receives only non-secret provider/account-connection state needed for
  display, never OAuth material or MCP types.

For either route:

- Use one selected Seedance 2.5 mapping. No transport fallback while a job is
  active. No generic model picker in v1.
- Copy reference bytes from FilmCore-validated reads into disposable staging in
  card order. Delete staging on every terminal path after remote upload no
  longer needs it.
- Separate submit from poll so the remote job ID is persisted promptly. Apply
  provider rate limits and bounded exponential polling without resubmission.

### C. FilmCore schema v15

After schema-v14 reconciliation, add provider-neutral tables:

- `video_generation_jobs`: local/client request ID, project/scene/card/set IDs,
  provider/adapter/model IDs and versions, transport kind, captured prompt-body
  SHA-256 and set input digest, duration/ratio/resolution/audio, lifecycle,
  nullable remote job ID, sanitized error code, timestamps, and last poll.
- `video_generation_job_references`: job ID, exact position, source version and
  requirement IDs when present, class/fidelity, source SHA-256, pixel facts;
  never source paths or names needed only for presentation.
- `generated_video_outputs`: job ID, bundle-relative contained path, SHA-256,
  byte count, media/container, video/audio codec facts, width/height, duration,
  audio presence, provider completion time, downloaded/validated timestamps,
  and local-presence state.

Constraints:

- One immutable request snapshot per job and at most one active output per job.
- Closed lifecycle transition table; terminal jobs never return to active.
- Remote job ID unique per provider when non-null. Client request ID always
  unique. Output path unique and bundle-relative.
- A card/set may be edited later; job snapshot/digests never change. Deleting or
  reverting prompts must not erase financial/provenance receipts. Define
  `ON DELETE` behavior accordingly rather than cascading paid history blindly.
- Technical lifecycle writes are not undoable human edits. They still use
  FilmCore controlled operations and transactions.

### D. Submission transaction and recovery

- Generate first rebuilds current scene-package/card materialization in
  FilmCore, requires fresh/valid Generation Ready state, verifies every
  reference digest, validates settings against descriptor capabilities, checks
  disk capacity, then inserts the `preparing` job snapshot transactionally.
- FilmBrain stages inputs and submits. Persist the remote ID and `submitted`
  state immediately in a second controlled transaction. If submission outcome
  is ambiguous, mark `submission_unknown`; never auto-submit it again.
- On app/project reopen, enumerate nonterminal jobs and resume polling after a
  non-paid compatibility/auth check. Authentication failure pauses; it does not
  discard the job or create another.
- Remote completed → retrieve → validate → staged local file → one transaction
  inserts output metadata and sets terminal `completed`. A stale package does
  not invalidate historical output; it only affects a future Generate action.
- Failed retrieval/validation retains the job receipt with `output_invalid` or
  `output_unavailable` and no canonical media path. A retry-download action may
  reuse the same completed remote job; it may never resubmit generation.

### E. Video retrieval and validation

- Prefer a chosen transport's bounded download-to-path operation. Otherwise
  add a purpose-built fetcher: HTTPS only; fixed host allowlist; reject
  userinfo/fragments/downgrade; validate every redirect; reject loopback,
  private, link-local, multicast, and non-public resolved addresses; cap
  redirects, time, and streaming bytes.
- Stage under a mode-restricted bundle-adjacent workspace. Require one regular
  file, no symlink/hard-link escape, and no extra output.
- Validate actual bytes/container with AVFoundation, not suffix or Content-Type:
  playable video track, allowed container/codec, bounded dimensions/duration,
  expected aspect/duration tolerances, audio presence matching the captured
  setting, nonzero frames, byte ceiling, and no path escape.
- Copy atomically into a generated-media bundle directory, fsync/verify digest,
  then commit metadata. Crash recovery either finishes a fully verified staged
  transfer or removes the orphan; never exposes a partial output.
- Removal requires confirmation, deletes only the validated contained file,
  retains the job/output receipt with `local_presence = removed`, and explains
  that Higgsfield Assets may retain the provider copy.

### F. Settings and scene UX

- Add an app-wide **Video Generation Integration** settings card: Higgsfield
  connection/readiness, selected pinned model, transport version, Connect/Login
  help or executable override as selected by Step 0, Refresh, and Disconnect or
  non-destructive reset. No secrets/account details are displayed.
- Each fresh Seedance 2.5 card shows **Generate Video**. A stale/invalid card
  shows its existing repair action; unsupported settings/references show the
  exact Higgsfield capability refusal; missing integration opens Settings.
- The confirmation sheet names provider, exact model, duration, ratio,
  resolution, audio, reference count, that prompt/references leave the Mac,
  that one paid request will be submitted, Higgsfield Assets retention, and
  exact quote only when Step 0 proves it. Generate is the authorization gesture.
- Show normalized progress: Preparing, Uploading, Submitted, Queued, Generating,
  Downloading, Validating, Output Ready. Percent appears only when provider data
  is meaningful; otherwise use state and elapsed time.
- Remote cancel uses **Cancel Generation** only when proven. Otherwise use
  **Stop Waiting**, explain that Higgsfield continues and credits may be spent,
  and offer Resume Waiting. Never leave only an indeterminate spinner.
- Output Ready embeds bounded AVKit playback and Play/Reveal/Export/Remove Local
  Copy. SwiftUI receives validated view data/URLs only; it performs no parsing,
  validation, storage, process, network, or GRDB work.
- Multiple manual generations appear as chronological job receipts under the
  card, not as approved takes. No star/rating/compare/selection semantics.

### G. Privacy, logging, and diagnostics

- Prompt body travels only in the selected transport's protected request body or
  CLI stdin; never argv/environment/logs. Reference staging uses random names.
- Never run/capture `auth token`. Never read a CLI credential file. MCP tokens
  exist only in Keychain and ephemeral authorized request memory.
- Persist prompt/reference digests, not duplicate prompt/reference bodies.
  Existing prompt-card storage remains canonical.
- Diagnostics may include provider/adapter/model/version, local job UUID,
  sanitized state/code, durations, byte/dimension/codec facts, and request count.
  They exclude remote IDs by default, signed URLs, raw payload/output, prompt,
  paths, asset/scene names, account/workspace IDs, and credentials.

## Prototype validation plan

Automated tests are intentionally deferred until the MVP shape is settled.
During prototype mode:

1. Run `scripts/build.sh` to check documentation consistency and compile
   FilmCore, FilmBrain, and the macOS app.
2. Exercise changed flows manually with disposable local projects. For storage
   migrations, provider recovery, containment, credential handling, and media
   validation, record the exact scenarios walked in the implementation notes.
3. Live acceptance uses `FILMCAMP_RUN_LIVE_HIGGSFIELD=1`, never CI, with
   immediate approval per paid request:

   - one short card, one reference, audio off;
   - one representative multi-reference card, audio on;
   - restart/recovery using one of those same jobs, not an extra generation;
   - cancel only as a separately approved request if remote cancel must be proven.

4. Record redacted evidence: chosen adapter/model/version, state sequence,
   request count, settings fidelity, reference count/order confirmation, output
   size/duration/dimensions/codecs/audio, local digest validation, and editing
   handoff. Record credits only as a user-observed aggregate if the owner chooses;
   no account/billing capture.

## Steps

1. Step 0 live contract capture and CLI-vs-MCP decision. Stop if no safe exact
   Seedance 2.5 transport exists.
2. Provider-neutral FilmBrain protocol, descriptor, and chosen Higgsfield
   adapter.
3. Schema v15 job/input/output domain, migration, controlled lifecycle, reads,
   containment, and recovery.
4. Safe video retrieval/validation and atomic local media commit.
5. App integration settings, coordinator, lifecycle/recovery, and disclosure.
6. SwiftUI Generate/progress/output surfaces and a manual disposable-project walk.
7. Prototype build validation and implementation-note record.
8. Explicitly approved live acceptance, redacted record, status update, and
   primary-contract/version pin.

Prefer commits at those boundaries only after the project builds. Never
push or open a PR unless asked.

## Done criteria

Plan 032 is `DONE` only when:

- Step 0 records and pins one safe exact Seedance 2.5 Higgsfield transport.
- Schema v15, provider-neutral jobs/inputs/outputs, chosen adapter, durable
  recovery, restricted retrieval, video validation, settings, consent,
  progress, output playback/reveal/export/removal, and portable fallback land.
- `scripts/build.sh` passes with no live provider activity.
- The explicitly approved live acceptance requests complete, exact settings and
  reference semantics are observed, restart recovery works, the local output
  validates, and the redacted acceptance record contains no sensitive data.
- `AGENTS.md`, Overview, Roadmap, Phase 5 design, this plan, and the plans index
  agree that the product ends at the editing handoff rather than Generation
  Ready, while editorial post-production remains excluded.

## STOP conditions

Stop and return to the owner if any applies:

1. Neither CLI nor MCP exposes an exact, stable Seedance 2.5 generation schema.
2. Prompt or credentials must enter argv, environment, world-readable files,
   logs, fixtures, diagnostics, project data, or UI.
3. Ordered references cannot be addressed with the same semantics as the
   prompt card, or the surface would truncate/reorder inputs.
4. Model, duration, ratio, resolution, audio, or output count can be silently
   adjusted/fallback-routed without a strict detectable refusal.
5. Paid submission has no durable job ID, or has neither remote cancel nor
   reliable resume after local interruption.
6. Hidden provider retries/duplicates cannot be disabled or detected; ambiguous
   submission would be automatically resubmitted.
7. Result retrieval requires arbitrary URLs or cannot be restricted, bounded,
   and validated before bundle commit.
8. MCP authority cannot be limited to the selected generation contract, or its
   OAuth credentials cannot remain Keychain-only.
9. The owner does not accept the chosen transport's current signing, source,
   OAuth, or supply-chain posture.
10. Work expands into shot planning, take approval/rating/comparison, automatic
    paid batch/retry/fallback, timeline editing, compositing, grading, mixing,
    or rendering.
11. Schema v14/baseline work is not reconciled enough to assign schema v15 and
    distinguish inherited failures from Plan 032 regressions.

## Primary sources

- [Higgsfield CLI README](https://github.com/higgsfield-ai/cli/blob/main/README.md)
- [Higgsfield CLI model reference](https://github.com/higgsfield-ai/cli/blob/main/MODELS.md)
- [Higgsfield CLI releases](https://github.com/higgsfield-ai/cli/releases)
- [Higgsfield official generation skill](https://github.com/higgsfield-ai/skills/blob/main/higgsfield-generate/SKILL.md)
- [Higgsfield MCP](https://higgsfield.ai/mcp)
- [Higgsfield Seedance 2.5](https://higgsfield.ai/seedance/2.5)
- [Higgsfield help: Seedance](https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-seedance)
- [Higgsfield help: MCP and credit behavior](https://higgsfield.ai/creator-hub/help-center/integrations/what-is-higgsfield-mcp)
- [CLI issue #50: macOS signing report](https://github.com/higgsfield-ai/cli/issues/50)
- [CLI issue #73: installer checksum report](https://github.com/higgsfield-ai/cli/issues/73)
- [CLI issue #75: MCP OAuth/DCR report](https://github.com/higgsfield-ai/cli/issues/75)
