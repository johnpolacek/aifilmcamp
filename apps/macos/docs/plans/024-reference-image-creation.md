# Plan 024: Reference image creation and archive (Phase 5c)

> Read `docs/PHASE1_DESIGN.md`, `docs/PHASE2_DESIGN.md`,
> `docs/PHASE3_DESIGN.md`, `docs/PHASE5_DESIGN.md`, Plans 011, 016, and 023,
> and `docs/REFERENCE_PROJECTS.md` in full before execution. This plan records the
> product-owner decisions of 2026-08-26 and supersedes Plan 023 contract B's focused
> reference sheet plus Phase 3 §14.3 / Phase 5 §11's integrated-image-provider non-goal.
> The reversal is deliberately narrow: still-image reference creation through a local
> executable only. It does not add generated video, takes, clips, review, editing, or
> rendering.

## Status

- **Status**: DONE
- **Depends on**: Plan 023 `DONE`
- **Category**: domain / media / local process / app / tests

> **2026-08-28 forward amendment:** Plan 025 replaces contracts C, E, G, the
> provider-specific portions of D, and STOP conditions 1 and 4 with a bundled
> multi-provider BYOK helper. This plan's card interactions, prompt workflow,
> canonical-dependency gate, archive, candidate selection, validated import, and
> transactional drift protection remain in force.

> **2026-08-28 UI forward amendment:** Plan 026 supersedes contract A's
> 112-point direct-action strip and scene-wide archive disclosure. Required
> references now render as 220–280-point adaptive cards and open an in-workspace
> reference detail containing that requirement's archive. The missing-image
> picker/Create actions, filled-card hover archive, prompt workflow, confirmed
> permanent deletion, transactional restore, and every validation rule remain
> in force.

## Contracts

### A. Required-reference interaction

- Remove the prominent `Add missing image for …` next-action button and the focused
  reference detail/history sheet.
- A missing reference card has two direct actions. Clicking its image well or `Add Image`
  opens the existing local image picker and imports the selected image as current in one
  controlled operation. `Create…` opens the image-creation sheet. Filled cards do not
  open either flow; hovering reveals a circled remove control in the upper-right.
- Removing a current image archives it immediately, without a confirmation. The action is
  journaled and undoable, clears the approved/current version, re-derives readiness, and
  marks direct dependent assets stale with the same one-level rule as an approval change.
- One collapsed `Archived Images` section sits beneath Required References, grouped by
  reference. Restoring an archived image uses the existing approval operation and archives
  any prior current image. Permanent deletion is available only in this section, requires
  confirmation, and follows the rows-first/files-second media rule.

### B. Prompt and dependency gate

- `Create…` loads the requirement's saved current asset prompt. If none exists, it starts
  the existing validated asset-prompt preparation flow; the resulting prompt appears in
  the creation sheet. Prompt text is editable and auto-saves through FilmCore's
  `setPromptBody`; no Save button exists. Generation flushes the pending edit first.
- The prompt surface has one icon-only Copy action with an accessibility label.
- Canonical dependency images are resolved from FilmCore's planned dependency read and
  passed in its deterministic order. A variant with any required canonical dependency
  missing has Create disabled with FilmCore's refusal sentence. Canonical originals have
  no reference-image dependency.
- Generate captures a FilmCore snapshot of the prompt body/digest, expected missing
  current image, and ordered canonical version IDs/hashes. Candidate import revalidates
  that snapshot inside its transaction; a prompt edit, dependency approval change, or
  newly installed current image during the run rejects the whole commit and asks to rerun.

### C. Provider-neutral local generation job

- FilmBrain owns `ImageGeneratorPreset`, discovery, request construction, process
  lifecycle, progress, cancellation, output validation, and diagnostics. SwiftUI owns no
  executable path, arguments, process, parsing, or media validation.
- Ship an app-wide built-in preset catalog beginning with **Nano Banana**. The preset
  targets a user-installed, externally authenticated executable and accepts an app-wide
  absolute executable override. The process receives a minimal allowlisted environment;
  Film Camp never reads, copies, persists, forwards, or logs provider credentials.
- The Nano Banana command contract is explicit arguments, never a shell command: prompt,
  zero or more ordered input-image paths, output path, aspect ratio, resolution, and model.
  The production preset discovers `filmcamp-nano-banana` or uses its configured absolute
  override; that externally authenticated wrapper accepts the official `gemini-api run`
  argument shape and owns any delegation/authentication internally. Film Camp does not
  auto-launch `gemini-api`, because its environment/flag API-key authentication would
  violate the no-credential-forwarding boundary. Capability probes validate the required
  flags before a run; provider output is bounded and diagnostics exclude prompt/reference
  contents.
- One generation request creates 1–4 candidates, default 1. FilmBrain runs one bounded
  candidate process at a time and reports setup, candidate `i/n`, validation, import, and
  completion progress. Cancellation stops the active process group and starts no further
  candidate.
- Fixed smart defaults: character/creature `2:3`, location/vehicle `16:9`, prop/object
  `1:1`; resolution `1K`. These are visible but not user-configurable in this plan.
- Pressing Generate is the outbound-media consent gesture; the sheet states that the
  prompt and listed canonical images are sent through the selected local CLI. There is no
  additional per-run approval modal. No live provider request runs in CI or as part of
  this plan's deterministic verification.

### D. Validated commit and candidate choice

- Every returned file is untrusted. FilmBrain first requires a regular output file and
  bounded size; FilmCore performs a non-mutating preflight before any candidate preview,
  then repeats its magic-byte, extension, dimensions, containment, and SHA-256 checks in
  the commit path so a changed file cannot slip through.
- One candidate imports and becomes current immediately in one controlled transaction.
  For 2–4 candidates, the sheet previews all validated candidates and requires the user to
  choose one. The chosen image becomes current; every unselected candidate imports as an
  archived `needs_review` version. The complete generated set, prompt lineage, current
  choice, and prior-current demotion commit as one journal entry or nothing commits.
- Generated files are copied into the project bundle. Temporary job files are cache, not
  canonical state, and are cleaned through the existing cache posture.

### E. Reference seams and rejected scope

- Adopt the AIWorkstation/Codex locator seam only for Finder-safe absolute discovery,
  capability probes, minimal environment, and actionable status; adopt the RxCode seam
  only for normalized progress/cancel state; retain the `swift-acp`-derived process-group
  interrupt/terminate/kill ladder already implemented by `FoundationProcessRunner`.
- Reject terminal scraping, shell interpolation, provider credential storage, arbitrary
  user command templates, provider HTTP SDKs, modifying provider configuration, and any
  coding-cockpit/IDE/session surface.

### F. Prompt-streamlining amendment (accepted 2026-08-27)

- Keep the complete `AssetPromptInput` local as the persisted digest and apply-time drift
  guard. Derive a smaller deterministic creative context for Codex containing only the
  requirement's visual type, the entity name/aliases/stable description, variant-only
  visual states, and satisfied references' positive roles and fidelity. Do not send scene
  headings, synopses, continuity events, requirement reasons, generation exclusions,
  hashes, dimensions, or the complete digest payload to the prompt-writing request.
- Prompt-run progress in this workflow names the actual task ("Codex is generating the
  image prompt"), never the shared extraction transport's screenplay-analysis copy.
- A successful prompt run refreshes the creation sheet directly into its editable prompt
  view. The prompt apply report remains available to the Asset Workshop and Jobs surfaces,
  but the reference-image workflow does not interrupt with a report or Done button.

### G. Gemini CLI extension amendment (accepted 2026-08-27)

- Replace the bespoke `filmcamp-nano-banana` wrapper contract in §C with the official
  Gemini CLI extension path. FilmBrain discovers `gemini`, capability-probes its headless,
  extension-selection, MCP-allowlist, trust, and supplemental-policy flags, then runs
  `gemini extensions list` in its masked text format to require an active `nanobanana`
  extension. The JSON form is deliberately not used because current Gemini CLI includes
  resolved sensitive setting values in that representation.
- Authentication remains external. The operator installs and authenticates Gemini CLI,
  installs the Nano Banana extension, and configures its API key with
  `gemini extensions config nanobanana`; Gemini CLI stores a sensitive extension setting in
  Keychain and injects it only into the extension. Film Camp launches `gemini` with the
  existing credential-free environment and never reads, copies, persists, forwards, or
  logs the key. Discovery recognizes Gemini CLI's masked `API Key: [not set]` marker and
  reports the configuration remedy.
- Every candidate runs headlessly in its own disposable working directory with only the
  `nanobanana` extension enabled. A per-run supplemental admin policy denies every tool and
  allows exactly one Nano Banana MCP operation: `generate_image` for a canonical original,
  or `edit_image` for a variation with one canonical source. No interactive Gemini approval
  is inserted after the app's Generate gesture. The extension's `nanobanana-output/`
  directory is enumerated only inside that isolated workspace and must contain exactly one
  regular output file.
- Nano Banana extension v1.0.12 exposes text generation and single-image editing but no
  multi-reference image input and no explicit aspect-ratio or output-resolution fields.
  FilmBrain therefore passes the fixed composition defaults as positive prompt guidance and
  refuses a request with more than one canonical dependency before discovery. It never
  silently drops a reference. This is an explicit preset capability limitation until the
  extension adds multi-reference support or another preset is added.

## Steps

1. Add FilmCore archive/current mutations, grouped generated-candidate import, scene
   archive reads, prompt lineage, and exhaustive media/state/undo tests.
2. Add FilmBrain's preset catalog, Nano Banana discovery/request runner, progress,
   cancellation, bounded diagnostics, output checks, and recorded executable tests.
3. Add app-wide generator settings and wire the window model to prompt auto-save,
   dependency resolution, generation progress, candidate selection, archive restore, and
   confirmed permanent deletion.
4. Replace the focused reference sheet with direct missing/filled card interactions,
   build the creation sheet and grouped archive section, and update headless plus XCUITest
   coverage.
5. Run `scripts/test-changes.sh` during iteration, run the full verification gate, obtain
   separate core/process and app/UX reviews, record results, and mark this plan done.

## Done criteria

- [x] Missing cards pick local images directly; the blue next-action button and focused
      reference sheet are gone.
- [x] Filled cards archive with an undoable hover action; grouped archives restore and
      permanently delete only after confirmation.
- [x] Create loads or prepares a saved prompt, auto-saves edits, copies by icon, and
      refuses a variation whose canonical dependencies are missing.
- [x] Nano Banana produces 1–4 validated candidates through a local executable with
      visible progress/cancellation and no credential handling by Film Camp.
- [x] One candidate becomes current automatically; multiple candidates require a choice
      and archive the unselected images in one controlled commit.
- [x] FilmCore, FilmBrain, app-unit/headless, UI smoke, docs, and verification lanes
      pass without a live provider request.
- [x] Codex receives only the narrowed positive visual context, prompt progress is
      task-specific, and completion reveals the prompt editor without an intermediate report.

## Verification result

- `check-docs`, the generated Xcode project, the app build-for-testing, all 795 FilmCore
  tests, all 137 FilmBrain tests, and the complete app-unit bundle pass.
- The new recorded UI journey passes end to end: it qualifies a real entity, builds its
  missing cards, imports from `Add Image`, archives through the hover control, exposes the
  grouped archive, and opens `Create…`.
- Every consolidated workspace UI method passes in isolation. The all-method invocation
  also recorded the new journey and the final workspace journey passing, but Xcode exited
  65 after its automation runner was unexpectedly killed during the remaining pre-existing
  method on both clean attempts. There was no XCTest assertion failure; the repository's
  retry classifier identified both exits as test-infrastructure failures. No live provider
  request ran.
- The Gemini CLI amendment passes `check-docs`, all 795 FilmCore tests, all 147 FilmBrain
  tests (including 16 local-image-generation adapter tests), build-for-testing, and the
  complete app-unit bundle. On the amendment run, `SceneWorkspaceSmokeUITests` could not
  initialize after both repository-managed attempts and one exact-daemon reset
  (`Timed out while enabling automation mode`); zero UI test methods executed and no XCTest
  assertion failed. No live Gemini or image-provider request ran.

## STOP conditions

1. Any implementation would read, persist, forward, or log a provider credential.
2. Any canonical media row could land before every selected output validates, or a
   multi-candidate choice could partially commit.
3. SwiftUI would need to launch a process, build CLI arguments, parse provider output,
   validate media, or write storage directly.
4. Work expands into generated video, takes, clips, review/history sheets, editing,
   rendering, arbitrary shell commands, or direct provider HTTP.
5. A variation can run without every active canonical dependency's current image.
