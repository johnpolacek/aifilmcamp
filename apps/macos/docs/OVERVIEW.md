# AI Film Camp App — Overview

> **Document ownership:** This overview is authoritative for product vision,
> users, principles, and boundaries. [ROADMAP.md](ROADMAP.md) owns desktop
> architecture, phase sequencing, and exit criteria;
> [REFERENCE_PROJECTS.md](REFERENCE_PROJECTS.md) owns harness implementation
> references; [plans/](plans/README.md) contains executor-ready build plans.

## Product Summary

AI Film Camp App is a local-first desktop application for planning and producing long-form AI films.

The app takes a screenplay and turns it into a structured production system:

**Screenplay → Breakdown → Asset Manifest → Asset Creation → Asset Readiness → Generation Prompts → Provider Generation → Editing Handoff**

The goal is not to replace a video editor such as DaVinci Resolve, Premiere Pro, Final Cut Pro, or iMovie.

Instead, AI Film Camp App owns the difficult layer between **having a screenplay** and **having all of the generated material needed to edit the movie**.

It acts as the production brain for an AI film.

---

## Initial Users and Validation

The first design partners are independent AI filmmakers making narrative shorts
or features on a Mac who already coordinate screenplays, prompts, reference
images, and external generation tools through folders, notes, or spreadsheets.
They should be actively producing a film, comfortable bringing a locally
authenticated Codex installation, and willing to correct structured production
data. Studios with formal production-management systems and first-time creators
who need an all-in-one generator are not the initial target.

Validate the first externally useful version with 3–5 design partners using one
original, public-domain, or properly licensed screenplay each. Observe the
workflow rather than relying only on feature requests, and record:

- time from import to a reviewed asset manifest
- number and type of corrections required
- blocked scenes or missing requirements found earlier than the filmmaker's
  current process
- whether exported scene packages are usable in the filmmaker's real generation
  tool without rebuilding the context by hand
- whether the filmmaker returns to update the same project over multiple work
  sessions

Do not expand into shot planning, clip editing, or additional providers on the
strength of a demo alone. First prove the complete Higgsfield path — prepared
prompt card, paid job recovery, validated local output, and editing handoff —
with filmmakers who trust the canonical data and save meaningful coordination
time.

---

## Core Problem

AI video generation tools are increasingly capable of producing impressive individual shots, but making a coherent long-form film remains difficult.

A feature-length AI production may require:

- dozens of characters
- multiple character looks and wardrobe states
- dozens of locations
- location variants for time of day, weather, damage, or story state
- recurring props
- vehicles
- creature or object designs
- hundreds of reference images
- hundreds or thousands of shots
- model-specific prompts
- continuity tracking
- tracking which scenes are blocked by missing assets

Today, filmmakers often manage this across:

- screenplay files
- folders
- spreadsheets
- notes
- image-generation tools
- video-generation tools
- chat sessions
- prompt documents
- editing applications

AI Film Camp App consolidates the planning, asset, continuity, and generation-preparation layers into one structured local project.

---

# Product Vision

AI Film Camp App should become the **production operating system for long-form AI filmmaking**.

The application should always be able to answer questions such as:

> What do I still need to create before I can produce Scene 42?

> Which missing assets would unblock the most scenes?

> Which scenes use Sarah's red coat?

> What visual state should Michael be in during Scene 38?

> Which scenes are ready for Seedance generation?

> What changed after I rewrote Scenes 51–58?

> Which assets or generation packages are now stale because of that rewrite?

> Generate the correct prompt and reference package for Scene 62.

The core value of the application is not the underlying language model.

The core value is the **persistent, structured representation of the film and its production state**.

---

# Product Principles

## 1. Local First

Film projects, databases, scripts, images, references, and generated media should live locally by default.

A project should be portable as a self-contained directory or bundle.

The application should not require uploading an entire film project to AI Film Camp servers.

Benefits include:

- filmmaker ownership
- privacy
- large-media scalability
- low infrastructure costs
- easy backup and archival
- independence from a SaaS platform

---

## 2. The Project Database Is Canonical

The LLM is an interpreter and agent.

It is not the source of truth.

The authoritative state of the film lives in structured project data.

Examples:

- scenes
- characters
- character looks
- locations
- location states
- props
- assets
- scenes and optional future directed shots
- relationships
- continuity events
- production status

AI actions should create or modify validated structured objects rather than leaving important information trapped inside chat history.

---

## 3. Harness-First AI

AI runs through the filmmaker's own locally installed agent CLI, signed in with their own login or subscription.

The app never holds those credentials.

Engines:

- Codex — primary
- Claude Code — secondary, where permitted
- Grok Build — secondary

The goal is to allow users to bring their preferred intelligence layer rather than locking Film Camp to a single model provider.

Where provider terms allow it, locally authenticated harnesses may reduce the need for separate per-token API billing.

Codex is the first integration. Claude Code and Grok Build can follow through separate adapters after compatibility and terms have been verified.

Reference still-image creation also supports direct Google and OpenAI providers through a
bundled, provider-neutral helper. Those user-supplied API keys are a narrow BYOK exception:
they enter only in app Settings, live only in macOS Keychain at rest, and are read
ephemerally for the generation request the filmmaker starts. They never enter a project
bundle, preference, log, diagnostic, or locally authenticated agent-harness process.

The local Swift reference projects and the rules for learning from them are documented in [Harness Reference Projects](REFERENCE_PROJECTS.md). They inform FilmBrain implementation without defining Film Camp's product scope or becoming dependencies by default.

---

## 4. Generation-Agnostic

AI Film Camp should not depend on a single image or video model.

The ecosystem changes too quickly.

The application should work with:

- Seedance
- Kling
- Veo
- Runway
- Grok
- fal-hosted models
- image-generation APIs
- future models
- external tools not directly integrated

Every generation workflow should support a basic escape hatch:

**Copy Prompt → Generate Anywhere → Import Result**

Integrations should improve convenience, not create lock-in.

---

## 5. Assets Before Generation

A coherent long-form production requires reusable visual assets before reliable scene generation.

The app should first determine:

> What must exist for this screenplay to be producible?

Only then should it focus on generation packages. Explicit in-app shot planning
is not on the roadmap; it is a non-goal the target model makes unnecessary, and
reopening it would be a product decision rather than a scheduled phase.

---

## 6. Stop at the Editing Handoff

AI Film Camp should have a clear endpoint:

> **A prepared scene can be generated through an authorized provider integration,
> recovered if the app closes, validated locally, and handed to the filmmaker's
> editor with complete provenance.**

The app may:

- prepare scene prompts
- identify required reference assets
- package references for generation
- export scene packages
- copy prompts
- reveal required files
- submit an explicit paid generation request through a configured integration
- track and recover the provider job without hiding retries or costs
- download and validate immutable generated video outputs
- play, reveal, remove, or export those outputs for editing

Higgsfield is the first integration. Provider execution is optional: portable
scene-package export remains available, and no project is locked to a provider.
The integration boundary is generation delivery, not editorial post-production.

That means avoiding:

- shot/take rating, comparison, or approval workflows
- automatic retry or provider-fallback queues
- timeline or sequence editing
- trimming
- transitions
- audio mixing
- color grading
- effects
- titling
- rendering
- full timeline editing

Generation happens through provider integrations such as Higgsfield, with
portable export as the fallback for Kling, Veo, Runway, or whatever comes next.

Editing happens in tools such as DaVinci Resolve, Premiere Pro, Final Cut Pro, or iMovie.

AI Film Camp's responsibility is to make sure generation receives the right
assets, continuity, references, prompt, and settings, and that the resulting
media reaches the editor without losing job or provenance information.

---

# Primary Workflow

## Stage 1 — Create or Open Film Project

The filmmaker creates a local Film Camp project.

Example:

```text
The Last Signal.aifilm/
├── project.db
├── screenplay/
├── assets/
├── exports/
├── cache/
└── logs/
```

The project should remain portable and recoverable without relying on Film Camp cloud infrastructure.

---

## Stage 2 — Import Screenplay

Supported formats should eventually include:

- Final Draft `.fdx`
- Fountain
- plain text
- PDF
- pasted screenplay text

The app ingests the screenplay while preserving the original source.

---

## Stage 3 — Screenplay Breakdown

An AI agent analyzes the screenplay and extracts the film's production graph.

Initial categories include:

- scenes
- sequences
- characters
- locations
- props
- wardrobe
- vehicles
- creatures
- important objects
- visual states
- continuity events

The filmmaker can review and correct the analysis.

Examples:

- merge duplicate characters
- rename locations
- mark an extracted prop as irrelevant
- split one location into multiple production spaces
- correct a wardrobe state
- add an asset the AI missed

The AI proposes.

The filmmaker approves.

The database becomes canonical.

For the MVP, this analysis is an initial setup step. The filmmaker can adjust the canonical project data afterward. Automated screenplay re-analysis and downstream change propagation are later capabilities.

---

## Stage 4 — Character Bible

Each recurring character should have a persistent production identity.

Example:

```text
SARAH MORGAN

Canonical identity
├── face reference
├── headless full-body front + back sheet
└── description

Looks
├── Office
├── Dinner
├── Hospital
├── Injured
└── Final Sequence

Continuity
├── hair state
├── makeup
├── injuries
├── age
└── carried objects
```

The application should understand which scenes require each look. If optional
directed shots are introduced later, they inherit those scene requirements.

---

## Stage 5 — Location Bible

Locations should be represented as reusable production assets rather than simple screenplay headings.

Example:

```text
SARAH'S APARTMENT

Exterior
├── day
└── night

Interior
├── living room — day
├── living room — night
├── kitchen
└── bedroom
```

The app may eventually track:

- layout
- architecture
- lighting
- weather
- time of day
- damage/state changes
- recurring camera directions
- reference images

---

## Stage 6 — Prop and Object Bible

Important recurring objects should have their own identity and continuity.

Examples:

- red notebook
- Sarah's phone
- antique revolver
- blue suitcase
- detective's car
- alien device

The application should know:

- where an object first appears
- scenes that require it
- whether its state changes
- whether multiple versions are needed

---

## Stage 7 — Asset Manifest

After understanding the screenplay, the app generates the required visual asset inventory.

Example:

```text
SARAH

○ Canonical face
○ Headless full body — front + back
○ Office outfit
○ Dinner outfit
○ Hospital outfit
○ Injured hospital variant
```

Example:

```text
MOTEL

○ Exterior — day
○ Exterior — night
○ Room — wide
○ Bathroom
○ Hallway — night
```

Each requirement links back to the screenplay:

```text
Sarah — Office Outfit

Required by:
Scene 4
Scene 5
Scene 7
Scene 11
Scene 12
```

This allows the filmmaker to create the smallest practical set of reusable assets needed for the production.

Each requirement is a slot: named, justified by the scenes that need it, and waiting for an image. The filmmaker fills it by generating or importing, and the approved file is copied into the project bundle.

Prop and object reference prompts stay intentionally compact: one or two short
sentences naming the object, its few defining visible traits, and a clean
front/side/back reference-sheet layout.

Requirements come from two places. The canonical character identity bundle — face closeup plus a headless full-body front/back sheet — is a project template, created for any entity appearing in more than one scene. The variants, such as Sarah — Office Outfit, are inferred from actual screenplay usage.

The canonical identity is an input reference for every look derived from it, so canonical assets are created first.

In a scene workspace, references are presented as large entity bundles rather
than an unrelated card list. A character bundle keeps Face Closeup and Headless
Full Body — Front + Back together and offers Generate Body from Face after the
face is approved. That action runs in place: the 16:9 body slot becomes the
loading surface, uses the approved face as its canonical reference, and fills
after the generated image passes validation and is committed. Only the front
figure is headless; the rear view includes the complete back of the head and
hairstyle. A location bundle
groups that location's existing canonical and usage-derived requirements; it
does not impose extra mandatory camera views.

Image edits become durable visual changes without overwriting the original
prompt. Current approved imagery and human visual changes override conflicting
older prompt details in later generations. Editing a canonical face marks its
dependent body stale; the bundle then offers Update Body from Face, but never
starts a paid synchronization request automatically.

The reusable base prompt is directly editable for intentional corrections,
including legacy projects whose saved description no longer matches the approved
image. A body update freezes the current face prompt into its generation context
and combines it with a fixed headless front/back layout instruction. It excludes
the body's older prompt entirely, so obsolete wardrobe language cannot compete
with the corrected canonical description.

---

## Stage 8 — Asset Workshop

Each asset gets its own workspace.

Example:

```text
SARAH — DINNER OUTFIT

Status
Prompt Ready

Used In
Scenes 22, 23, 24

References
Sarah Canonical Identity
Restaurant Style Reference

Prompt
[generated prompt]

Versions
v1
v2
v3

Approved
v3
```

Possible actions:

- generate prompt
- regenerate prompt
- generate through integrated provider
- copy prompt
- import image
- drag/drop image
- approve asset
- reject asset
- add notes
- create variation

The approved asset becomes the canonical reference for downstream scene generation.

---

## Stage 9 — Scene Asset Readiness

Every scene should expose whether all of its required assets exist.

Example:

```text
SCENE 27 — MOTEL ROOM

ASSET READINESS: 87%

✓ Sarah
✓ Sarah — Blue Sweater
✓ Michael
✓ Motel Room — Night
✓ Blue Suitcase
✓ Bedside Lamp
✕ Bloody Towel

6 / 7 assets ready
```

At the film level:

```text
92 scenes

37 Asset Ready
41 Partial
14 Blocked
```

Asset Ready means the scene has its approved visual assets. It becomes Generation Ready only after its prompt, continuity context, and reference package are prepared.

The app should help answer:

> What should I create next?

Eventually, the agent can optimize production:

> Creating these four assets would unblock eleven scenes.

---

## Stage 10 — Prompt Generation

Once a scene is ready, Film Camp creates a generation package.

The working surface is scene-first: a searchable scene rail opens one workspace with
collapsed scene data, required references, and paste-ready prompt cards. Most scenes
have one card; a long scene or one with incompatible generation jobs may have an ordered
set. Cards remain scene-level handoffs, not stored shots or downstream clips.

If a derived prop is not actually needed in a particular scene, the filmmaker can
remove it from that scene's required references without deleting the prop, its image,
or its use elsewhere. The scene's readiness, prompt context, and export package all
honor that same scene-specific decision, and Undo restores it.

The app assembles the context. A pluggable prompt skill, running in a harness session, writes the prompt.

The filmmaker can bring their own skill; swapping it should not require an app change.

Assembled context should incorporate:

- screenplay intent
- scene text
- approved character references
- character state
- wardrobe
- approved location reference
- props
- action
- style bible
- scene tone
- continuity
- model-specific prompting practices

Example output profiles:

```text
Seedance
Kling
Veo
Runway
Generic
```

The same scene may produce different prompts for different models.

---

## Stage 11 — Generation Package

A scene should become a self-contained generation task.

Example:

```text
SCENE 027 — MOTEL ROOM

Status
Generation Ready

Target
Seedance 2.5

References
✓ Sarah — Injured
✓ Motel Room — Night
✓ Bloody Towel

Prompt Cards
1. [locally numbered reference thumbnails]
   [scene prompt, written by the prompt skill]
2. [only when duration or incompatible jobs require a split]

Actions
[Copy Prompt]
[Reveal / Drag Images]
[Export Scene Package]
```

The generation package should contain everything needed to reproduce the intended scene in an external AI video tool:

- final prompt
- scene metadata
- required reference assets
- character/look references
- location references
- prop references
- continuity notes
- model-specific guidance

The package is both a portable export and the validated request envelope used
by an integrated provider.

---

## Stage 11A — Integrated Provider Generation

A Generation Ready prompt card may be sent directly to a configured provider.
Higgsfield is first; the domain model remains provider-neutral.

```text
Prompt Card 1
Higgsfield — Seedance 2.5
30s · 16:9 · 720p · audio on
12 ordered references · paid request

[Generate Video]

Queued → Generating → Downloading → Validating → Output Ready

[Play] [Reveal] [Export]
```

The job survives app restart. Film Camp records the exact prompt-card version,
reference digests, provider/model/settings, remote job identifier, lifecycle,
and validated local output. A later prompt or asset change can make the package
stale without rewriting the historical generation receipt. Each Generate click
creates exactly one visible paid job; retries are separate human gestures.

Generated outputs are immutable production handoffs, not timeline clips or
approved takes. Playback verifies delivery; editorial selection and assembly
remain in the filmmaker's dedicated editor.

---

## Stage 12 — Production Dashboard

The project dashboard should make a feature-length production understandable at a glance.

Example:

```text
THE LAST SIGNAL

Screenplay
92 scenes

Assets
Characters             14
Character Looks         39
Locations               31
Props                   68

Asset Completion        81%

Scenes
Asset Ready             37
Partial                 41
Blocked                 14

Generation Packages
Generation Ready        24
Needs Preparation      13
```

The dashboard should emphasize actionable work rather than vanity metrics.

---

# Film Graph

The core product can be thought of as a connected graph.

```text
Film
│
├── Sequence
│     └── Scene
│           └── Shot (optional, not on the roadmap)
│
├── Character
│     └── CharacterLook
│
├── Location
│     └── LocationState
│
├── Prop
│
├── AssetRequirement
│     └── Asset
│
└── ContinuityEvent
```

Relationships are more important than isolated records.

Example:

```text
Sarah
   ↕
Sarah — Hospital / Injured
   ↕
Scenes 48–52
   ↕
Reference Images
   ↕
Generation Prompts
```

That connected production graph is one of the application's primary long-term advantages.

---

# AI Production Assistant

Because the AI operates on structured project state, Film Camp can eventually support a project-level assistant.

Examples:

> What should I work on next?

> Which assets are blocking the most scenes?

> Find continuity problems.

> Which characters still need full-body references?

> Which locations appear only once?

> Can any one-off locations be consolidated?

> Which scenes are most expensive from an asset standpoint?

> Sarah is now injured starting in Scene 38. Update the affected production requirements.

> I rewrote Scenes 42–47. Determine what existing assets and generation packages need review.

> Prepare the generation package for Scene 29.

> Prepare every remaining asset-ready scene for Seedance.

> Export the generation packages for Scene 29.

The assistant should operate through explicit project tools rather than raw database access where practical.

---

# Technical Architecture

The authoritative desktop architecture, integration modes, transport order,
project-bundle contract, provider strategy, and implementation-reference rules
live in [ROADMAP.md#target-desktop-architecture](ROADMAP.md#target-desktop-architecture).
This overview intentionally does not restate them; the product principles above
are the constraints that architecture must satisfy.

---

# Asset States

A simple production state system should be used consistently. These names are
the canonical cross-phase vocabulary until an explicit migration changes them.

Asset states:

```text
Needed
Prompt Ready
In Progress
Needs Review
Approved
Rejected
Deprecated
```

Scene asset-readiness states:

```text
Blocked
Partial
Asset Ready
```

Generation-package states:

```text
Needs Preparation
Generation Ready
Stale
```

A scene becomes **Generation Ready** when its required assets, continuity context, prompt, and reference package are complete.

---

# Continuity

Continuity is especially difficult in AI filmmaking and should become a first-class concept.

Examples of continuity state:

```text
Character
├── wardrobe
├── hair
├── makeup
├── injury
├── age
├── dirt/wetness
└── carried objects

Location
├── time of day
├── weather
├── lighting
├── damage
└── object placement

Prop
├── possession
├── condition
├── location
└── destruction/state
```

The application should eventually understand events such as:

```text
Scene 36
Sarah is injured.

Scene 37–42
Sarah must use the injured character state.

Scene 43
Sarah changes clothes.

Scene 44+
New wardrobe state applies.
```

This continuity graph can then inform asset requirements and scene prompts automatically.

---

# Style Bible

Every project should eventually support a visual style bible.

Possible fields:

```text
Visual Language
Camera Style
Lens Preferences
Color Philosophy
Lighting
Production Design
Costume Direction
Image Texture
Film References
Avoidances
Prompt Rules
```

The style bible should automatically influence:

- asset prompts
- location prompts
- character references
- optional directed-shot planning
- video prompts

---

# User Control

The app should never assume AI output is correct.

Important actions include:

```text
Approve
Reject
Edit
Merge
Split
Regenerate
Lock
Override
```

A filmmaker should be able to lock important information so future AI operations cannot casually change it.

Examples:

```text
LOCKED

Sarah canonical appearance
Motel room layout
Film aspect ratio
Primary visual style
```

---

# Rewrites and Change Propagation

One long-term differentiator should be understanding screenplay changes.

If a filmmaker changes:

```text
Scene 42

Sarah is now wearing the red coat.
```

Film Camp should eventually determine:

```text
Affected:

Scene 42

New requirement:
Sarah — Red Coat

Possibly invalid:
1 scene prompt
1 reference package
```

The app should present the consequences before modifying production state.

---

# Optimization Intelligence

Because Film Camp understands the entire film, it can eventually provide production optimization.

Examples:

> This location appears in only one scene.

> Rewriting Scene 31 into the existing warehouse location eliminates five unique assets.

> These three scenes can use the same nighttime street reference.

> Creating Sarah's rain-soaked variant next will unblock eight scenes.

> Six props appear only once and may not need dedicated reference images.

This could become particularly valuable for feature-length AI productions.

---

# Export Philosophy

Film Camp should make it easy to leave Film Camp.

Possible export:

```text
Production Export/
│
├── Scene 027/
│   ├── prompt.md
│   ├── scene.json
│   └── references/
│
└── Scene 028/
```

Other possible exports:

- CSV
- JSON
- Markdown
- asset manifest
- prompt pack
- reference package

Film Camp should not become a prison for project data.

---

# AI Film Camp Community

The desktop application can be complemented by **AI Film Camp** at `aifilmcamp.com`.

The site can serve as the broader ecosystem around the application.

Possible community content:

- tutorials
- filmmaking workflows
- model comparisons
- prompt recipes
- downloadable templates
- production case studies
- filmmaker showcases
- interviews
- asset creation techniques
- shot planning techniques
- model-specific best practices

Eventually the desktop app may integrate optional community resources such as:

```text
Production Templates
Prompt Profiles
Style Presets
Workflow Recipes
Model Guides
```

The community and application should reinforce one another without making the local application dependent on the website.

---

# Business Model Considerations

The local-first architecture enables a relatively low-cost software business.

AI Film Camp does not necessarily need to pay for:

- user inference
- large video storage
- rendering
- project hosting

Possible revenue models include:

- paid desktop license
- annual upgrades
- subscription for continued app updates
- optional AI Film Camp Pro community membership
- paid workflow/template packs
- optional cloud sync later
- optional hosted generation credits
- affiliate relationships with generation providers

The exact monetization model should be decided after validating the production workflow.

---

# Development Sequence

[ROADMAP.md](ROADMAP.md) is the single source of truth for phase scope, order,
dependencies, and exit criteria. In brief, development proves the technical
spine (Phase 0), builds screenplay understanding and the asset workflow (Phases
1–4), prepares scene-level packages and delivers them through provider
integrations (Phase 5), and adds project-wide intelligence only after the core
workflow is validated (Phase 6).

---

# MVP Boundary

The first externally useful version should likely include:

```text
Import Screenplay
       ↓
AI Breakdown
       ↓
Characters / Locations / Props
       ↓
Asset Manifest
       ↓
Asset Library
       ↓
Asset Readiness
```

It proves planning value before provider execution is enabled, but the complete
MVP includes direct video generation and a validated editing handoff.

The next major product layer becomes:

```text
Scene Generation Prompts
       ↓
Generation Package / Export
       ↓
Higgsfield Generation
       ↓
Validated Local Output
```

---

# Non-Goals

AI Film Camp should initially avoid becoming:

- a screenplay-writing application
- a Final Draft replacement
- a nonlinear video editor
- a DaVinci Resolve competitor
- a video rendering engine
- an effects package
- a social network inside the desktop app
- a proprietary AI video model
- a mandatory cloud storage service

The application wins by being exceptional at production organization,
AI-assisted preparation, and reliable provider delivery while leaving editing
to dedicated tools.

---

# Competitive Position

The product occupies the space between:

```text
Screenwriting
      ↓
AI FILM CAMP — planning + provider generation
      ↓
Video Editing
```

Existing tools increasingly solve individual parts of AI filmmaking.

AI Film Camp should specialize in the difficult connective tissue:

> **Understand the entire film, determine what needs to exist, help create it
> consistently, generate prepared scenes through replaceable integrations, and
> deliver validated outputs to editing.**

---

# Long-Term Product Thesis

As AI video quality improves, generating an individual clip will become increasingly commoditized.

The harder problem will be coordinating thousands of production decisions across a coherent long-form film.

That includes:

- identity
- continuity
- reusable assets
- visual consistency
- dependencies
- production progress
- model-specific prompting
- revisions
- generation preparation
- organization

AI Film Camp is designed around that future.

The ultimate product promise is:

> **Give AI Film Camp your screenplay, and it will help you systematically turn it into the assets, scene packages, references, and prompts you need to generate the movie—with directed shot plans available later where they add real value.**
