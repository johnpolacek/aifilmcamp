# AI Film Camp App — Development Roadmap

> **Document ownership:** This roadmap is authoritative for architecture,
> phase sequencing, dependencies, and exit criteria. [OVERVIEW.md](OVERVIEW.md)
> owns product vision, initial users, principles, and boundaries;
> [REFERENCE_PROJECTS.md](REFERENCE_PROJECTS.md) owns harness implementation
> references; [plans/](plans/README.md) contains executor-ready build plans.

## Purpose

This document defines the staged development plan for the AI Film Camp desktop application.

AI Film Camp is a local-first production system for long-form AI filmmaking.

Its workflow is:

**Screenplay → Breakdown → Asset Manifest → Asset Creation → Asset Readiness → Generation Prompts → Provider Generation → Editing Handoff**

The product deliberately stops **after provider generation delivery and before
editorial post-production**.

AI Film Camp should not become:

- a nonlinear video editor
- a shot/take rating or approval system
- an automatic retry or provider-fallback queue
- a render pipeline
- a DaVinci Resolve / Premiere / Final Cut competitor

The application's job is to get every scene to the point where it is:

> **Ready to generate through a configured integration and deliver a validated
> immutable output to the filmmaker's editor.**

---

# Product Boundary

The app owns:

- screenplay understanding
- structured film data
- characters
- character looks
- locations
- location states
- props
- continuity
- required asset planning
- asset creation workflows
- asset approval
- asset readiness and generation readiness
- model-specific generation prompts
- reference packages
- exports
- provider integrations and explicit paid generation requests
- durable asynchronous generation jobs
- validated immutable generated outputs and editing handoff

The app does **not** own:

- editing
- transitions
- audio mixing
- color grading
- rendering
- final movie assembly

The first generation integration is Higgsfield. Portable packages remain the
handoff for other generation providers until they receive adapters. Downstream
editing tools include:

- DaVinci Resolve
- Premiere Pro
- Final Cut Pro
- iMovie

---

# Target Desktop Architecture

AI Film Camp is a native macOS application: Swift, SwiftUI with AppKit where needed.

macOS-only for the foreseeable future.

## Distribution

The macOS app will be distributed as a signed and notarized download rather than through the Mac App Store.

## Hard Requirement

AI runs through the user's locally installed agent CLI and their own login/subscription.

```text
Codex          primary harness
Claude Code    secondary, where permitted
Grok Build     secondary
```

The app never holds provider credentials for these.

Codex is the first and primary integration. Claude Code and Grok Build can follow through separate adapters after their compatibility and terms have been verified.

Direct still-image providers are an implemented narrow exception for reference creation.
Google Nano Banana 2 and OpenAI GPT Image 2 run through the app's bundled helper with
Settings-only BYOK credentials stored only in macOS Keychain. This does not change the
credential-external contract for Codex or any other locally authenticated agent harness.

## Layered Structure

```text
AI Film Camp.app          SwiftUI / AppKit shell
      │
      ├── FilmBrain        harness adapters, structured jobs, project tools
      │
      └── FilmCore         domain model, project storage, screenplay parsing,
                           provenance, readiness, continuity, export
```

The important boundary is that AI integration remains separate from the canonical domain model and persistence layer.

Implementation references and adoption boundaries are documented in [Harness Reference Projects](REFERENCE_PROJECTS.md). Consult that guide when planning or building FilmBrain, harness discovery, approvals, controlled tools, process lifecycle, or MCP support.

## Multi-Agent

The architecture should allow more than one harness session, but the initial implementation only needs to prove the Codex path.

Agents propose changes through structured output or controlled project tools. The app validates and applies all mutations.

## Harness Discovery

The app must reliably discover supported CLIs when launched from Finder and report whether each engine is installed, authenticated, and compatible.

Each adapter also reports the capabilities available for the detected version, including structured results, progress events, cancellation, approvals, session resume, and controlled tools. Features require capabilities explicitly instead of assuming parity across Codex, Claude Code, Grok Build, or ACP-compatible agents.

## AI Integration Modes

Two modes, named explicitly:

```text
Batch structured job
one task, one schema, one validated result, one transaction

Harness session with controlled Film Camp tools
controlled mutations, provenance-aware, no DB access for the agent
```

Batch structured jobs are the workhorse through Phase 5: screenplay extraction, manifest inference, and prompt generation.

Harness sessions with controlled Film Camp tools power the Phase 6 assistant and any interactive "do X across the project" work. MCP can provide this interface where supported.

Preferred transport order is a native structured protocol, ACP, a structured non-interactive CLI, and finally a PTY compatibility fallback. Terminal-screen parsing never supplies schema-critical batch results.

---

## Project Bundle

Each project is a portable `.aifilm` package:

```text
My Film.aifilm/
├── project.db
├── screenplay/
├── assets/
├── exports/
├── cache/
└── logs/
```

SQLite stores canonical metadata and relationships, not large media blobs.
Project-internal paths are bundle-relative, `project.db` carries an explicit
schema version, and migrations run on open while newer unsupported bundles are
refused without mutation. A project must survive close, move, and reopen
without path repair. The selected implementation plan owns the version-specific
layout and migration details.

---

# Development Philosophy

The phases are ordered to prove increasingly product-specific assumptions.

Do not build the whole product at once.

Each phase should end with something that can be used and evaluated before starting the next phase.

The progression is:

```text
Prove infrastructure
        ↓
Understand screenplay
        ↓
Know what must be created
        ↓
Help create it
        ↓
Know which scenes are asset ready
        ↓
Prepare generation packages
        ↓
Add project-wide intelligence
```

---

# Phase 0 — Spine Spike

## Goal

Phase 0 proves the core vertical path through a deliberately minimal app: project bundle, Codex discovery, a schema-validated result, and persistence.

This is not a framework evaluation. The stack is decided.

Phase 0 should answer:

> Does the spine hold end to end — a Finder-launched macOS app that finds Codex, analyzes a screenplay, validates what comes back, and commits it safely to the project?

---

## Core Deliverable

An extremely minimal application that can:

1. create, open, and move a `.aifilm` bundle containing `project.db`
2. detect whether Codex is installed, authenticated, and compatible from a Finder-launched build
3. run one Codex analysis against a sample screenplay
4. show job progress and failure in the UI
5. produce a schema-validated `analyzeScreenplay` result — scenes, characters, locations
6. commit the result safely
7. quit and reopen the project

---

## Initial Data Model

Only implement:

```text
Project
Script
Scene
Character
Location
ProjectAsset
Job
```

Do not add the final film ontology yet.

---

## FilmBrain

Implement the FilmBrain Swift package:

```text
Harness adapter       run and observe a supported local agent
Harness detection     installed / authenticated / compatible
Structured output     JSON Schema per task, validated before persistence
Project tools         controlled access to canonical project operations
Capabilities          runtime support reported per adapter and version
Normalized events     progress / approval / completion / failure / cancellation
```

The adapter owns command discovery and communication details so those details can change without affecting FilmCore or the UI.

No AI logic belongs in the SwiftUI layer.

Use the Phase 0 guidance in [Harness Reference Projects](REFERENCE_PROJECTS.md): take the backend/capability separation from RxCode, Finder-safe discovery lessons from AIWorkstation, and evaluate Calyx and `swift-acp` behind the FilmBrain boundary. Implement one structured Codex path plus a fake adapter and replay fixtures before adding another provider.

---

## First AI Task

Implement:

```text
analyzeScreenplay()
```

Input:

```text
screenplay text
```

Output:

```text
scenes
characters
locations
```

The result must be schema validated before entering SQLite.

---

## Exit Criteria

- [ ] build launches from Finder
- [ ] `.aifilm` bundle can be created and opened
- [ ] `project.db` is created and stamped with a bundle schema version
- [ ] Codex installed / authenticated / compatible state is reported
- [ ] a Codex analysis job runs and reports progress
- [ ] `analyzeScreenplay` returns results that validate against the schema
- [ ] scenes, characters, and locations commit in one transaction
- [ ] a malformed result is rejected without corrupting `project.db`
- [ ] project survives quit and reopen
- [ ] project survives moving to a different directory

---

# Phase 1 — The Screenplay Brain

## Goal

Build a trustworthy structured representation of the screenplay.

The Phase 0 analysis only proves infrastructure.

Phase 1 creates the actual film-production ontology.

---

## Core Question

> What does this screenplay contain, and how are its production elements related?

---

## Phase 1a and Phase 1b

Split the phase:

```text
1a   import + parser + deterministic scene list
     + manual entity editing, including merge / split / lock

1b   AI extraction proposing into that editing model
```

1a must be usable on its own, with no AI involved.

1b adds proposals to the same editing model. It never introduces a second, parallel path into the data.

---

## Expand the Domain Model

Add:

```text
Project
Script
Sequence
Scene

Character
CharacterAlias
CharacterState
CharacterLook

Location
LocationState

Prop
Vehicle
Creature
Object

ContinuityEvent

Relationship

Provenance
```

Not all categories need their own rich UI immediately, but the schema should begin reflecting real production concepts.

---

## Screenplay Import

Prioritize:

1. Fountain
2. Final Draft `.fdx`
3. plain text

Add PDF after the structured formats work well.

The original source file should always be preserved inside the project.

---

## Scene Segmentation

Scene segmentation is deterministic, produced by the Fountain/FDX parser.

Never ask the model to find scene boundaries.

The AI does interpretation only: entities, aliases, states, continuity.

---

## Structured Extraction

Working from the parsed scene list, the AI should identify:

- characters
- recurring aliases
- locations
- props
- wardrobe references
- vehicles
- creatures
- visual conditions
- injuries
- weather
- time-of-day changes
- recurring objects
- important continuity events

Extraction is a batch structured job.

---

## Chunked Extraction and Reconcile

Extraction runs per scene or per chunk, then a project-level pass reconciles and normalizes.

```text
parse        deterministic scene list
extract      per scene or per chunk, small context, comparable results
reconcile    aliases merged, entities normalized, project-level identity assigned
```

Reconcile is where "SARAH" and "SARAH MORGAN" become one character, not the extraction step.

---

## Provenance

Every extracted fact carries:

```text
source       ai | human
locked       boolean
confidence   model-reported or derived
evidence     scene id + character range spans into the script text
```

Provenance supports locking, human review, "why does this requirement exist", and future change propagation.

Establish provenance in Phase 1 so later capabilities can rely on it.

---

## Evaluation Set

Keep sample screenplays in the repository, with an answer key of the entities
they contain — exported from a reviewed extraction run, never hand-written.

Extraction quality is measured against them, not eyeballed.

Score before shipping any prompt, schema, or engine change.

---

## Human Correction

Every extracted entity must be editable.

Users should be able to:

- rename
- merge
- split
- delete
- mark irrelevant
- reclassify
- lock
- add missing information

Examples:

```text
"SARAH" and "SARAH MORGAN"
→ Merge

"APARTMENT"
→ Rename to "Sarah's Apartment"

"RED MUG"
→ Mark as non-production-relevant
```

---

## AI Rules

The AI proposes.

The database is authoritative.

The application should never require replaying the original chat to reconstruct project state.

For the MVP, screenplay analysis is treated as an initial setup step. After that analysis, the filmmaker edits the canonical project data directly. Automated screenplay re-analysis and downstream change propagation remain a later capability.

---

## Exit Criteria

- [ ] feature screenplay can be imported
- [ ] scene boundaries come from the parser, not the model
- [ ] recurring characters normalize correctly
- [ ] locations normalize correctly
- [ ] important props are extracted
- [ ] wardrobe/state changes can be represented
- [ ] continuity events can be represented
- [ ] filmmaker can correct AI output
- [ ] entities can be merged and split
- [ ] important fields can be locked
- [ ] AI cannot silently overwrite locked canonical information
- [ ] every extracted fact carries evidence spans into the script
- [ ] extraction quality is scored against the evaluation set

---

# Phase 2 — Asset Manifest

## Goal

Turn screenplay understanding into a production inventory.

This is the phase where AI Film Camp begins becoming a real product rather than a screenplay-analysis tool.

---

## Core Question

> What visual assets must exist before this screenplay can be generated coherently?

---

## Asset Requirement Model

Add:

```text
AssetRequirement
AssetRequirementType
AssetDependency
Asset
AssetVersion
```

Distinguish between:

```text
Requirement
```

and:

```text
Actual created asset
```

Example:

```text
Requirement:
Sarah — Office Outfit

Asset:
sarah-office-v3.png
```

---

## Requirements Are Slots

A requirement is an empty slot with a name, a reason, and a place in the graph.

The filmmaker fills it by generating an image or importing one. The chosen file is copied into the project bundle. One version is approved as canonical.

```text
slot          Sarah — Office Outfit
              required by Scenes 4, 5, 7, 11, 12
              depends on Sarah — Canonical Face

fill          generate through the selected image provider, or import / drag in

versions      v1  v2  v3

approved      v3        → copied into assets/, referenced downstream
```

Until a slot is filled and approved, everything downstream of it is blocked.

---

## Two Tiers of Requirement

Requirements come from two different places, and only one of them is inferred by AI.

```text
Canonical identity set     per entity, from a project template
                           Sarah: face closeup, headless full body — front + back
                           Motel Room: establishing view

Usage-derived variants     per entity, inferred from actual screenplay usage
                           Sarah — Office Outfit, required by Scenes 4, 5, 7
                           Motel Room — Night, required by Scenes 27, 28
```

The canonical set is policy, not intelligence. Do not ask the model which base views a character needs — that is a project setting.

The variants are the AI's job: read the script, propose what the story actually requires.

## Who Gets a Canonical Set

Entities appearing in more than one scene.

```text
appears in 2+ scenes     canonical identity set + usage-derived variants
appears in 1 scene       no canonical set; handled inside that scene's package
```

This is computed from the parsed scene index, not inferred. It bounds the manifest on a feature-length script, where most speaking parts appear once.

Both directions are overridable: promote a one-scene entity that matters, or suppress a recurring one that does not.

---

## Asset Dependencies

The canonical identity is an input to everything derived from it.

```text
Sarah — Canonical Face
        ↓  used as a reference image when generating
Sarah — Office Outfit
Sarah — Dinner Outfit
Sarah — Injured
```

Consequences the app must handle:

- a derived requirement is blocked until its parent is approved
- generation order follows the dependency graph: canonical first, variants second
- re-approving a different canonical version marks every derived asset **stale**, not invalid — the filmmaker decides whether to regenerate

Asset-level staleness is in the MVP. Screenplay-level change propagation is Phase 6 and is not.

---

## Character Asset Requirements

Examples:

```text
SARAH

canonical identity
○ face closeup
○ headless full body — front + back

usage-derived
○ office wardrobe          Scenes 4, 5, 7, 11, 12
○ dinner wardrobe          Scenes 22, 23, 24
○ hospital wardrobe        Scenes 48, 49
○ injured hospital state   Scenes 50, 51, 52
```

The canonical set comes from the project template.

The AI infers the variants from actual screenplay usage.

---

## Location Asset Requirements

Examples:

```text
SARAH'S APARTMENT

○ exterior — day
○ exterior — night
○ living room — day
○ living room — night
○ kitchen
○ bedroom
```

Avoid automatically creating unnecessary variants.

---

## Prop Requirements

Not every mentioned prop needs a dedicated visual reference.

The AI should distinguish between:

```text
production-important recurring prop
```

and:

```text
incidental set dressing
```

---

## Requirement-to-Scene Links

Every requirement should know why it exists.

Example:

```text
Sarah — Office Outfit

Required by:
Scene 4
Scene 5
Scene 7
Scene 11
Scene 12
```

---

## Requirement Review

The filmmaker should be able to:

- approve
- reject
- edit
- combine
- split
- mark optional
- mark "no dedicated asset needed"

Validated inference output is active immediately. Removing a requirement rejects it—a tombstone that keeps a later run from resurrecting what the filmmaker dismissed—while editing, combining, splitting, marking optional, and marking no dedicated asset needed are ordinary corrections. There is no blanket Proposed/Accepted review pass or “unreviewed AI facts” badge.

---

## AI Integration Mode

Manifest inference is a batch structured job: one task, one schema, one validated result, one transaction.

---

## Exit Criteria

- [ ] app generates a complete asset manifest
- [ ] character requirements link to scenes
- [ ] location requirements link to scenes
- [ ] prop requirements link to scenes
- [ ] filmmaker can edit requirements
- [ ] irrelevant requirements can be removed
- [ ] duplicate requirements can be merged
- [ ] project can clearly answer "what assets are still missing?"
- [ ] manifest works on a real short or feature screenplay

---

# Phase 3 — Asset Workshop

## Goal

Help the filmmaker create, import, version, and approve the assets identified in Phase 2.

---

## Core Question

> How do I efficiently turn every required asset into an approved canonical reference?

---

## Asset Workspace

Each requirement should have its own workspace.

Example:

```text
SARAH — DINNER OUTFIT

Status
In Progress

Used In
Scenes 22, 23, 24

Canonical Character
Sarah Morgan

References
sarah-face-approved.png
restaurant-style-reference.png

Prompt
[generated prompt]

Versions
v1
v2
v3

Approved
v3
```

---

## Supported Workflows

Users should be able to:

- generate an asset prompt
- copy the prompt
- generate through an integrated service
- import an externally generated image
- drag/drop an image
- create variations
- approve one version
- reject versions
- add notes
- replace the canonical version

---

## Generation Providers

Initial integrations should be minimal.

Always support:

```text
Copy Prompt
Import Result
```

## Image Generation in V1

Copy Prompt and local import remain available. Integrated reference-image generation uses
an app-bundled, provider-neutral helper with Google Nano Banana 2 or OpenAI GPT Image 2,
app-wide provider selection, and Keychain-only BYOK. The asset model remains independent
of provider SDKs and stores only neutral generation provenance.

---

## Later Integrations

Possible additional direct integrations later:

- fal
- additional image-generation APIs
- external launcher/deep links

The product should not depend on any one generation provider.

---

## Canonical Assets

Approved assets should become downstream references.
Asset workflow status uses the canonical [asset states](OVERVIEW.md#asset-states)
so workshop, dashboard, and persistence vocabulary stay aligned.

Example:

```text
Sarah
→ Canonical Identity
→ Office Look
→ Dinner Look
→ Injured Look
```

Downstream scene generation should use approved canonical assets rather than
arbitrary images.

---

## Exit Criteria

- [ ] every asset requirement can accept actual media
- [ ] media is copied into the project
- [ ] multiple versions can exist
- [ ] one version can be canonical
- [ ] prompt can be generated for an asset
- [ ] prompt can be copied
- [ ] externally generated result can be imported
- [ ] asset survives restart and project move
- [ ] project can be used to build a complete asset library

---

# Phase 4 — Scene Asset Readiness

## Goal

Turn the asset graph into an actionable production dashboard.

---

## Core Question

> Which scenes have all of their required visual assets, and what is blocking the others?

---

## Asset Readiness Model

A scene's asset readiness derives from its required assets.
Use the canonical [asset and scene readiness states](OVERVIEW.md#asset-states)
rather than introducing phase-specific status strings.

Example:

```text
SCENE 27 — MOTEL ROOM

6 / 7 required assets ready

✓ Sarah
✓ Sarah — Blue Sweater
✓ Michael
✓ Motel Room — Night
✓ Blue Suitcase
✓ Bedside Lamp
✕ Bloody Towel
```

Possible states:

```text
Blocked
Partial
Asset Ready
```

Asset Ready means the required assets have been approved. It does not yet mean the final prompt and reference package are prepared. Phase 5 establishes Generation Ready.

---

## Project Dashboard

Example:

```text
THE LAST SIGNAL

Assets
214 / 247 ready

Scenes
37 asset ready
41 partial
14 blocked
```

---

## Prioritization Intelligence

The AI can begin answering questions such as:

> Which asset should I create next?

> Which four assets would unblock the most scenes?

> Which missing locations are preventing the most production?

> Are there one-off assets I could avoid through a small rewrite?

---

## Exit Criteria

- [ ] every scene has deterministic asset readiness
- [x] asset readiness derives from approved asset state
- [x] blocked assets are visible
- [x] project dashboard summarizes asset readiness
- [x] clicking a missing asset opens the Asset Workshop
- [ ] ~~AI can recommend high-impact next actions~~ — dropped by owner decision
      2026-08-24: the AI advisor is out of scope; Phase 4 ships deterministic-only and
      the deterministic impact ranking carries this criterion's substance
- [x] filmmaker can identify what to work on next without using a spreadsheet

---

# Phase 5 — Generation Prompt Engine

## Goal

Turn each asset-ready scene into a high-quality model-specific generation
package, optionally submit it through an authorized provider integration, and
deliver a validated immutable output.

This is the primary endpoint of the application.

---

## Core Question

> What exactly should I give Seedance 2.5 to generate this scene correctly, and
> how can Film Camp submit and recover that job without losing provenance?

---

## Scene-Level Packages

The first target is Seedance 2.5, which accepts a scene-level prompt and performs its own multi-shot breakdown.

Film Camp does not cut the scene into shots. It assembles the context and lets the model cut.

A scene normally produces one generation prompt card. When its action cannot fit within
the target's 30-second ceiling or it contains incompatible generation jobs, it may
produce an ordered set of cards. These are generation request units, not a Shot
model: there is still no directed shot list or timeline. Each submitted card may
own provider-neutral job receipts and immutable outputs without becoming an
editorial take model.

The primary app experience is the scene workspace: search/select a scene, repair its
required reference images, then generate a card through the configured provider
or copy/export it for an external tool. Project-wide preparation actions stay
manual in a compact toolbar menu rather than becoming separate primary destinations.

---

## The App Assembles Context, A Skill Writes the Prompt

Prompt authoring is a pluggable skill run through the harness, not prompt engineering hard-coded into the app.

```text
Film Camp assembles      scene text, canonical entities, approved references,
                         continuity state, style bible, target profile
        ↓
Prompt skill writes      the model-specific prompt, in a harness session
        ↓
Film Camp packages       prompt + metadata + reference images
```

The filmmaker can supply their own skill. Swapping the skill must not require an app change.

The default skill for the Seedance 2.5 profile is vendored at
[`PromptSkills/higgsfield/`](../PromptSkills/README.md) — the film-relevant subset of
[OSideMedia/higgsfield-ai-prompt-skill](https://github.com/OSideMedia/higgsfield-ai-prompt-skill),
MIT licensed, pinned to a commit. It is app payload read by a harness session, not app code;
nothing in FilmCore or FilmBrain imports it.

Two of its requirements reach upstream into the requirement and asset model, so honor them
when assembling context:

- Each reference needs an explicit role, an exclusion, and a fidelity grade (full-preserve,
  partial-preserve, attribute-transfer, loose-guide). Bulk statements covering several
  references at once are the skill's canonical failure.
- Character description has seven slots — role, skin, facial detail, eyes, hair, clothing,
  build — and age must not be written.

It also ships a stdlib preflight linter that validates a prompt against the model specs.
That is the natural structural gate for AI output here, before a prepared prompt is committed
to a scene package.

---

## Prompt Inputs

The assembled context should include:

- screenplay intent
- scene text
- approved character identity
- approved character look
- approved location and location state
- approved props
- continuity state entering the scene
- action and dialogue
- style bible
- target profile conventions

---

## Provider Profiles

Support prompt profiles such as:

```text
Seedance 2.5
Kling
Veo
Runway
Generic
```

Seedance 2.5 first, and done well. Additional profiles can follow without changing the canonical film model.

---

## Export Scene Package

Possible export:

```text
Scene 027/
├── prompt.md
├── scene.json
└── references/
    ├── sarah-injured.png
    ├── motel-room-night.png
    └── bloody-towel.png
```

The references are the approved canonical assets for everything the scene uses.

Seedance 2.5 accepts up to 30 reference images, which is enough for a dense scene without subdividing it. Order them deliberately: canonical identities first, then looks, then locations and props.

---

## Batch Export

Allow:

```text
Export Scene
Export Sequence
Export All Generation Ready Scenes
```

The app should make it easy to move into external generation tools.

---

## Generation Readiness

A scene is Generation Ready when:

- its required assets are approved
- its continuity context is present
- its model-specific prompt has been prepared
- its reference package has been assembled

This is distinct from the Asset Ready state calculated in Phase 4.
Use the canonical [generation-package states](OVERVIEW.md#asset-states),
including `Stale` when inputs change after preparation.

Readiness remains an input/package state. Provider jobs have a separate durable
lifecycle (`preparing`, `submitted`, `queued`, `running`, `downloading`,
`validating`, and terminal states), so a failed provider request never changes
whether the underlying package is ready.

---

## Integrated Video Generation

Higgsfield is the first provider adapter. A Generation Ready prompt card can
submit exactly one explicit paid job with its exact prompt, ordered reference
images, target profile, duration, aspect ratio, resolution, and audio setting.
The app persists the provider-neutral receipt, recovers asynchronous work after
restart, downloads through a restricted transport, validates the returned
video, and stores an immutable local output with provenance.

Portable package export remains first-class. Provider availability never gates
manual preparation, and one provider's transport/auth types never enter
FilmCore. Additional providers add FilmBrain adapters and descriptors rather
than schema or SwiftUI-specific execution paths.

Initial provider execution is one card at a time. There is no automatic retry,
fallback, or paid batch generation. Playback, Reveal, Export, and removal of a
local output support the editing handoff; rating, approval, comparison, trimming,
timeline assembly, and rendering do not.

---

## Exit Criteria

- [ ] asset-ready scene can generate a model-specific prompt
- [ ] the prompt is authored by a swappable skill, not hard-coded in the app
- [ ] prompt incorporates canonical references
- [ ] prompt incorporates continuity
- [ ] user can switch prompt target profile
- [ ] user can copy prompt
- [ ] user can reveal reference assets
- [ ] scene package exports with its reference images
- [ ] scene packages can be exported in batch
- [ ] Asset Ready and Generation Ready are clearly distinguished
- [ ] a Generation Ready card can submit one explicit Higgsfield paid job
- [ ] submitted work survives app restart and can resume polling safely
- [ ] returned video is bounded, validated, stored locally, and tied to exact provenance
- [ ] output can be played, revealed, and exported for editing
- [ ] portable package export still works without a configured provider
- [ ] no timeline, clip editing, compositing, grading, mixing, or rendering exists

---

# Phase 6 — Production Intelligence

## Status

Not in the MVP.

Provenance and evidence spans still ship in Phase 1 because this phase eventually depends on them.

---

## Goal

Use the full film graph to provide reasoning that becomes increasingly valuable on larger productions.

---

## Core Question

> What can the app understand about the entire film that would be difficult for the filmmaker to track manually?

---

## AI Integration Mode

This phase uses the second mode: a harness session with controlled Film Camp tools, exposed through MCP where supported.

The agent gets no database access; it reads and proposes through tools, and the app validates, applies, and records provenance.

Batch structured jobs remain in use for everything they already cover.

---

## Production Assistant

Possible questions:

> What should I work on next?

> Which missing assets block the most scenes?

> Which scenes are asset ready but still need generation packages?

> Which scene packages are ready for Seedance?

> Which assets are only used once?

> Which locations could possibly be consolidated?

> Find continuity inconsistencies.

> Sarah is injured starting in Scene 38. What needs to change?

> I rewrote Scenes 42–47. What production work is affected?

> Prepare the generation package for Scene 29 for Kling.

---

## Change Propagation

When screenplay or canonical data changes, calculate impact.

Example:

```text
Change:
Sarah now wears the red coat in Scene 42.

Affected:
Scene 42

New requirement:
Sarah — Red Coat

Needs review:
1 scene prompt
1 reference package
```

Do not silently rewrite downstream data.

Show proposed impact first.

---

## Production Optimization

Possible recommendations:

```text
This location appears only once.

These three street scenes could use the same approved location asset.

Creating Sarah — Rain Variant will unblock eight scenes.

This prop appears once and probably does not need a dedicated reference image.

Moving Scene 31 into the warehouse would eliminate four unique asset requirements.
```

---

## Continuity Intelligence

Track:

### Character

- wardrobe
- injuries
- hair
- makeup
- wet/dry
- dirt
- age
- possession of objects

### Location

- time of day
- weather
- damage
- lighting
- object state

### Prop

- owner
- condition
- location
- destruction
- transformation

---

## Agent Tool Layer

This is the phase where a deliberate agent tool architecture should become first-class. It should allow agents to:

- inspect canonical project data
- query missing assets and readiness
- retrieve relevant continuity context
- propose validated changes
- report which downstream records may be affected

---

## MCP

The controlled project tool layer should be available to Codex, Claude, and Grok through MCP where supported. The transport details can be chosen during implementation.

Every tool goes through the same validation and provenance path as the UI.

Do not expose arbitrary filesystem or database mutation.

---

## Exit Criteria

- [ ] assistant can query the project graph
- [ ] assistant can recommend next work
- [ ] screenplay changes produce impact analysis
- [ ] continuity inconsistencies can be surfaced
- [ ] AI mutations use controlled tools
- [ ] locked data cannot be modified silently
- [ ] Film Camp operations are available to supported harnesses through controlled tools
- [ ] project remains model/provider independent

---

# Phase 7 — AI Film Camp Ecosystem

## Goal

Connect the local production application with the broader AI Film Camp community without making the desktop app dependent on the website.

---

## AI Film Camp Website

`aifilmcamp.com` can provide:

- tutorials
- workflow guides
- prompt techniques
- model comparisons
- filmmaking case studies
- downloadable templates
- community discussions
- filmmaker showcases
- interviews
- style recipes
- model-specific recommendations

---

## Optional Desktop Integrations

Possible future integrations:

```text
Community Prompt Profiles
Style Bible Templates
Production Templates
Workflow Recipes
Model Guides
```

Examples:

```text
Seedance Dialogue Scene
Kling Action Sequence
Consistent Character Sheet
Low-Cost Feature Workflow
Naturalistic Handheld Drama
```

---

## Principles

Community functionality should be optional.

The desktop app must continue to work:

- offline
- locally
- without an AI Film Camp account
- without cloud project storage

---

## Exit Criteria

- [ ] website and desktop product reinforce each other
- [ ] community resources can be discovered from the app
- [ ] local projects remain independent of community services
- [ ] optional cloud features do not compromise local-first architecture

---

# Cross-Cutting Concerns

These concerns apply throughout development.

## Bundle Schema Versioning

`project.db` stores the bundle schema version.

Migrate on open. Refuse to open a bundle written by a newer app.

## Recoverable AI Changes

AI changes should be transactional and recoverable. The exact undo and backup mechanism can be selected during implementation.

## Job Cache and History

Keep enough job history to understand what ran, which engine produced it, and whether it succeeded. Caching and storage details can evolve with the implementation.

## Privacy

Storage is local. The app uploads nothing on its own.

The screenplay is sent to whichever engine the user chose. Say so plainly in the UI, before the first run.

When a local harness cannot suppress the user's global instructions or installed
skill/plugin context, disclose that those may accompany the request. Film Camp
must not inspect, persist, enumerate, or claim isolation from that ambient
context unless the detected harness exposes and passes a supported isolation
capability.

## Serialized Mutations

The app serializes mutations per project so concurrent jobs cannot apply conflicting changes.

## Testing Strategy

```text
sample screenplays + answer keys      extraction quality, scored not eyeballed
deterministic readiness tests           no model in the loop
expected export files                 generation packages compared byte for byte
recorded harness event streams          replayed in CI, no CLI required
adapter contract tests                   every provider obeys the same lifecycle guarantees
```

---

# Recommended MVP Boundaries

## Test Project

A real feature screenplay should be used alongside the smaller samples.

Not a toy sample. Scale, ambiguity, and recurring characters are the point.

The small sample screenplay stays for Phase 0 and for parser tests.

Every screenplay used for development, evaluation, demos, or design-partner
validation must be original, public domain, or used under permission/license.
Keep repository samples synthetic or original. Record provenance and rights in
a README beside them; never commit a commercial screenplay merely because a team
member owns a copy. Design-partner projects remain in the partner's local bundle
unless explicit permission covers a redacted research artifact.

---

## External Validation Gates

Use the [initial-user protocol](OVERVIEW.md#initial-users-and-validation) with
3–5 active filmmakers. After Phase 4, require evidence that most partners can
reach a reviewed asset manifest and use readiness to find blocked work with less
manual coordination. After Phase 5, require evidence that Higgsfield accepts a
prepared card without rebuilt context, the paid asynchronous job recovers, and
the validated local output reaches editing; portable package export must still
work without a configured provider. Treat correction burden, time saved, and
repeat use as decision inputs; do not broaden providers, or reopen the
shot-planning non-goal, solely because the demo is technically complete.

---

## Internal Technical Prototype

Phase 0.

```text
Project
→ Script
→ AI Analysis
→ SQLite
→ Results
```

---

## Asset Planning MVP

Phases 1–4.

```text
Import Screenplay
       ↓
Screenplay Brain
       ↓
Asset Manifest
       ↓
Asset Workshop
       ↓
Asset Readiness
```

At this stage, AI Film Camp can already replace a substantial amount of spreadsheet/folder/manual tracking work.

---

## Integrated Generation MVP

Phases 1–5. Phase 6 is not in the MVP.

```text
Screenplay
    ↓
Breakdown
    ↓
Assets
    ↓
Asset Readiness
    ↓
Scene Generation Package
    ↓
Higgsfield / Seedance 2.5
    ↓
Validated Generated Output
    ↓
Editing Handoff
```

The model performs the shot breakdown. Film Camp supplies the scene, approved
references, continuity, and settings, then preserves the paid job receipt and
validated output.

This represents the original core product vision, minus the shot-planning layer the target model makes unnecessary.

---

# Explicit Non-Goals Across All Phases

Do not introduce these without a major product decision:

- shot/take rating, approval, and comparison workflows
- automatic retry or provider-fallback queues
- video timeline
- trimming
- transitions
- audio editing
- effects
- color grading
- rendering
- final export of a movie
- proprietary video-generation model
- mandatory Film Camp cloud storage
- in-app shot planning: a `Shot` model, a per-shot breakdown, or a directed shot
  list

Shot planning was a phase of its own until 2026-08-23, when it was removed and
the later phases were renumbered. The first target model, Seedance 2.5, takes a
scene-level prompt and performs its own multi-shot breakdown, so Film Camp hands
it a whole scene and lets the model cut. Reopening this needs a target model
that requires explicit per-shot input, or a filmmaker who wants to direct the
cut here — and a product decision, not a scheduled phase. The removed design
sketch is in the history of this file.

---

# Working Rules for Coding Agents

Repository-wide agent workflow and architecture guardrails live in
[`AGENTS.md`](../AGENTS.md). Executors must also read the selected plan and,
before harness work, [Harness Reference Projects](REFERENCE_PROJECTS.md). This
section is intentionally a pointer so the session-level instructions do not
drift from a second copy here.

---

# Definition of Product Success

AI Film Camp succeeds when a filmmaker can give the application a screenplay and systematically reach this state:

```text
Film understood
      ✓

Required assets identified
      ✓

Canonical assets created
      ✓

Scenes unblocked
      ✓

Continuity supplied
      ✓

References assembled
      ✓

Model-specific prompts prepared
      ✓

GENERATED OUTPUT READY FOR EDITING
```

At that point, AI Film Camp's job is complete.

The filmmaker reveals or exports the validated output and assembles the final
film in a dedicated editor.

---

# Long-Term Product Thesis

The product thesis and promise live in
[OVERVIEW.md#long-term-product-thesis](OVERVIEW.md#long-term-product-thesis).
The roadmap's implementation consequence is narrower: preserve a canonical,
portable film graph and validated provider-independent generation boundary so
new models and optional directed-shot workflows do not require rebuilding the
asset, continuity, or project-storage foundations.
