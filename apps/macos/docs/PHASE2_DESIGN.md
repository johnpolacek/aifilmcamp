# Phase 2 Design — Asset Manifest

Prototype-mode amendment, 2026-09-03: automated testing and evaluation have
been removed while the product is being explored. Historical test prescriptions
below remain design history, not current delivery requirements. Validate current
work with `./scripts/build.sh` and hands-on product walkthroughs until the owner
explicitly ends prototype mode.

Revision 2026-09-03 (scene-workspace repair): a visible character or location
earns its canonical identity set from its first visible scene. The 2+ recurrence
threshold remains the automatic rule for vehicles, creatures, and objects;
props remain governed by §3.4. This closes the Phase 5 gap where a one-scene
speaking character or heading location could reach generation without any
reference slot, and supersedes older one-scene language below where necessary.

Revision 2026-08-30 (product-owner decision; Plan 031): a filmmaker may remove
a canonical prop-family reference (prop, vehicle, or object) from one scene without rewriting screenplay
appearances or deleting the shared prop, requirement, or media. Schema v13 stores
that scene-specific exclusion; the shared readiness/reference derivation subtracts
it so the workspace, prompt context, and exports remain synchronized.

Revision 2026-08-29 (product-owner decision; Plan 030): successful image edits
are durable visual amendments. Schema v12 retains exact human edit text on the
immutable generation run, derives active direction through current approved
image lineage, and makes that ordered lineage part of generation drift
validation. Character canonical amendments apply across the identity bundle;
saved prompt history remains unchanged.

Revision 2026-08-29 (product-owner decision; Plan 029): the default character
identity template is now a two-slot bundle—Face Closeup plus Headless Full
Body — Front + Back. The stable `full_body` code is retained; `profile_side`
and `waist_up` remain stored but disabled. Schema v11 migrates existing
projects without deleting their media or history and makes Full Body depend
on Face Closeup. This narrowly supersedes the four-view passages and decision
§14.8 below.

Revision 2026-08-26 (product-owner decision): structurally and semantically
validated inference output is active immediately. The routine requirement
approval queue and “unreviewed AI facts” badges are retired; users edit,
combine, split, reject, or restore exceptions in place. Bundle schema v8 also
activates legacy proposals while preserving NULL `reviewed_at`.

Status: ACCEPTED CONTRACT, 2026-08-21; revised three times the same day
after three rounds of an external implementation-readiness audit. The third
round's product change, and the largest since acceptance: **extraction now
closes at its first applied run** (§3.6, §14.9 revised) — the owner settled
four rounds of audit pressure by choosing the strict latch over the
manifest-completion boundary, so Re-analyze no longer exists and a new run
means a new project. The third
round's repairs: `ManifestInputBuilder` is a FilmCore type so §8.4 step 0
can rebuild the input inside the apply transaction, and the final report
write is an in-transaction primitive (§8.2, §8.4); Build returns a typed
`ManifestBuildResult` and journals nothing when it creates nothing (§5.2);
the Build-collision and reclassify remedies say delete, not reject, because
a tombstone keeps its normalized name (§5.2, §5.3, §7.4); a human re-add of
a tombstoned scene link or dependency un-rejects the tombstone instead of
raw-failing UNIQUE (§7.2); merge collisions never let a tombstone survive
over an active row (§7.4); `approveVersion` clears the asset's own
staleness (§6.3). The third round re-raised closing extraction at the first
successful run; it remains declined per §3.6's recorded reasons and the
owner-confirmed §14.9 boundary. The second round's
repairs: apply-time stale-input protection became an input-digest guard
(§8.4 step 0 — the auditor's preferred fix, simpler and stronger than
per-reference re-resolution); manifest completion closes **initial**
extraction, not only re-analysis (§3.6); Build's cross-tier name collision
skips and badges instead of failing raw (§5.2); the combine asset-survivor
rule covers a target with no asset (§7.2); split's basis and dependency
rules are pinned (§7.2); basis-row replaceability is defined through the
requirement (§8.4); and containment covers the symlinked leaf and every
read path (§4.1). (The second and third rounds' demand to close extraction
at its first applied run was declined at the time and has since been
**accepted** by the owner — see the fourth-round change above and §14.9.)
The first round's repairs:
bootstrap ordering §3.6, apply-time stale-input protection §8.4 step 0,
variant-tier-only split/combine §7.2, `rejected_explicitly` surviving
deprecation §4.3/§6.3, the `'never'` override binding every proposal channel
§8.3/§8.4, and physical realpath containment for media §4.1 — plus the P2
tightenings: frozen template codes, an explicit input budget, boolean
CHECKs, historical filenames, full-predicate dependency satisfaction, and a
precise privacy claim). The audit's one product question — when the
bootstraps close — was answered by the owner the same day (§14.9) and
revised by them on 2026-08-21 to the strict latch above. The product owner had
earlier accepted §14's
decisions 3–8 as recommended, **reversed decision 1** — prop importance is
the AI's judgment, not a computed rule; §3.3, §3.4, §5, and §8 are revised
accordingly — and **declined manifest re-runs** (decision 2): inference is
run-once, and the re-run machinery was removed from §3.6, §8.4, and §9.
Earlier the same day the draft was revised after four independent
adversarial reviews (roadmap/product fidelity,
data-model and migration soundness, built-surface fidelity, and a
fresh-eyes external pass), with every accepted finding folded in. The
material repairs: the `assets` DDL constraint placement (§4.3); defined
interactions between the existing entity operations and the requirement
graph (§7.4); a hand-ordered inverse for `approveVersion` against the
partial unique index (§7.3); the revert gate and runner-completion changes
the manifest run actually needs (§8.4, §8.1); combine now merges version
histories and tombstones the source (§7.2); graph-level replacement rules
in apply (§8.4); the deprecation/approved-version invariant (§6.1); persisted
inclusion suggestions (§8.5); and a single active-requirement predicate
(§6.4). Written against the built Phase 1 surface at commit `17981af`
(Plans 001–008 DONE, Plan 007's account-backed evaluation gate deferred
per its live-gate policy); every claim about
existing schema, mutation-engine, or FilmBrain behavior was verified
against source, not against Phase 1 prose. This document becomes the shared
contract for the Phase 2 plans once the product owner accepts §13 and §14.

This is the same kind of document as `docs/PHASE1_DESIGN.md`: one contract,
numbered sections that plans cite by §. Executors read it in full before
starting any Phase 2 plan. The intent documents (`docs/ROADMAP.md` Phase 2,
`docs/OVERVIEW.md`, `AGENTS.md`) remain authoritative; deliberate deviations
are listed in §13 for the product owner to accept or reject.

Layering is unchanged: FilmCore owns domain, storage, migrations, provenance,
and controlled mutations; FilmBrain owns harness and structured jobs; SwiftUI
is presentation only.

---

## 1. What Phase 2 must deliver

From `docs/ROADMAP.md` (Phase 2 — Asset Manifest), the core question:

> What visual assets must exist before this screenplay can be generated
> coherently?

Exit criteria (verbatim from the roadmap, mapped to sections of this
contract):

| Roadmap exit criterion | Contract |
|---|---|
| app generates a complete asset manifest | §5 (deterministic tier) + §8 (AI variants) |
| character requirements link to scenes | §3.3, §4.3 (`asset_requirement_scenes`, derived canonical links) |
| location requirements link to scenes | same |
| prop requirements link to scenes | same |
| filmmaker can edit requirements | §7 |
| irrelevant requirements can be removed | §7 (reject tombstone; `necessity`) |
| duplicate requirements can be merged | §7.2 (`combineRequirements`, filled slots included) |
| project can clearly answer "what assets are still missing?" | §6.4 |
| manifest works on a real short or feature screenplay | §10 (acceptance) |

Product decisions this contract is bound by, restated so no plan re-litigates
them:

- **One extraction run.** AI screenplay analysis is a one-time bootstrap;
  afterward the app owns the data and updates are human edits. Nothing in
  Phase 2 may assume re-runnable extraction or ask for a new extraction
  field (§3.6, §3.4). This is a **latch, not merely posture** (owner,
  2026-08-21, reversing §14.9's earlier boundary): the first extraction run
  that *applies* closes analysis for that screenplay permanently, enforced
  in FilmCore. There is no second run — a new run means a new project.
- **Canonical identity set = project template** (policy, not AI).
  **Usage-derived variants = the AI's job** (§3.2).
- **Visible characters and locations earn a canonical set immediately; recurring
  production items earn one at 2+ scenes**, computed from the parsed scene index
  and overridable both directions (§3.3) — with the owner-decided exception that
  props are the AI's judgment instead (§3.4).
- **Requirement (slot) ≠ Asset ≠ AssetVersion.** One version approved as
  canonical (§3.1, §4.3).
- **Canonical identity → derived variants.** Re-approving a canonical marks
  derived assets stale, not invalid. Asset-level staleness is MVP;
  screenplay-level propagation is Phase 6 (§3.5, §6.2).
- **Manifest inference is a batch structured job** over the existing
  `StructuredJobRunner` (§8).
- **Requirement review consumes unaccepted facts.** Per Phase 1 decision
  §14.1, manifest inference and every downstream consumer read all
  non-`rejected` facts; anything derived from a still-`proposed` fact carries
  a visible "based on unreviewed AI facts" flag (§3.7).

Phase 2 is finished when its plans are `DONE`, `./scripts/build.sh` passes,
and the §10 acceptance record (a manifest built and reviewed on the
operator's feature screenplay) is committed.

---

## 2. Sub-phase structure

Phase 2 splits the way Phase 1 did, and for the same reason: the
deterministic half must be usable on its own, and the AI half proposes into
that editing model rather than through a second path.

```text
2a   requirement model + template-computed canonical sets + requirement
     review/editing + asset/version storage with import and approve
     → usable on its own, no AI involved

2b   manifest inference proposing usage-derived variants into that same
     review model, as one batch structured job
```

After 2a the app can already build the canonical half of a manifest for any
imported screenplay — parser-derived characters and locations qualify under
the 2+ rule with no AI run at all — and the filmmaker can fill and approve
slots. 2b adds the variant proposals. Plan boundaries inside 2a/2b are the
planning pass's decision, not this contract's.

---

## 3. Architecture decisions

### 3.1 Requirement ≠ Asset ≠ AssetVersion

Three distinct records, three distinct lifecycles:

- **AssetRequirement** — the slot: a name, a reason, and a place in the
  graph. It exists before any media does. Requirements are review-model
  facts: they carry PROV, can be proposed/accepted/rejected, locked,
  combined, and split.
- **Asset** — the produced artifact's identity, created when the first media
  arrives for a requirement. It owns the version list, the workflow status
  (§6.1), and the staleness flag (§6.2).
- **AssetVersion** — one imported file: immutable bytes on disk plus a row
  recording path, hash, and verdict. Exactly one version per asset may be
  approved at a time (§4.3's partial unique index).

Cardinality in the MVP: one requirement has **zero or one** asset; one asset
has one or more versions. Sharing one approved asset across several
requirements ("these three street scenes could use the same location asset")
is a real future capability but it is Phase 6 optimization-intelligence
territory; the MVP keeps the 1:1 slot-fill model and §11 names the seam.

`Asset` (the new FilmCore type) is distinct from the Phase 0 `ProjectAsset` /
`project_assets`, which records imported *screenplay source files* and is not
touched by this phase. The near-collision is unfortunate but renaming a
shipped table for aesthetics is not worth a rebuild; §14 lists it in case the
product owner disagrees.

### 3.2 Two tiers: template policy and AI variants

```text
canonical tier    per qualifying entity, from the project template —
                  Sarah: face closeup, headless full body — front + back
                  Motel Room: establishing view
                  → computed deterministically, never asked of a model

variant tier      per entity, inferred from actual screenplay usage —
                  Sarah — Office Outfit, required by Scenes 4, 5, 7
                  Motel Room — Night, required by Scenes 27, 28
                  → proposed by the manifest inference job (§8),
                    reviewed like any other AI fact
```

The template is a per-project table (`asset_requirement_types`, §4.3), seeded
from a built-in default per entity kind and editable by the filmmaker:

| entity kind | default template entries (frozen `code` values) |
|---|---|
| character | face closeup (`face_closeup`), headless full body — front + back (`full_body`); disabled legacy codes: profile / side (`profile_side`), waist up (`waist_up`) |
| location | establishing view (`establishing`) |
| prop, vehicle, creature, object | reference view (`reference`) |

The `code` values are frozen identifiers: seeding, tests, and §8.4's
prop-proposal mapping name entries by code, never by display name. A
disabled entry simply stops generating (and §8.4 skips prop proposals whose
`reference` entry is disabled, counted, rather than resurrecting it);
deleting a referenced entry is refused (§7.2).

Entries can be disabled, renamed, re-ordered, or added per project.
Editing the template affects which canonical requirements §5.2 *generates
from then on*; it never silently deletes or renames an existing requirement
row (§5.3; a requirement's `name` is its own, copied at creation).

### 3.3 Who gets a canonical set: kind-aware scene thresholds, computed

An eligible **character or location** earns a canonical identity set on its first
visible scene. An eligible **vehicle, creature, or object** earns one when it
appears in two or more scenes. Both thresholds are computed from the canonical
scene index — `scene_entities` rows — never inferred by a model. **Props are the
one exception**: by product-owner decision (2026-08-21, §14.1) a prop earns its
slot through the AI's judgment rather than the scene count — §3.4 owns that rule.

**Which roles count.** An appearance counts toward the rule when its `role`
is `speaking`, `present`, `setting`, or `used` — the visible roles. A
`mentioned` role does not: a character who is talked about in ten scenes but
on screen in one does not need a canonical identity bundle for the nine
conversations. Distinct qualifying scenes are counted, not rows (an entity
`speaking` and `present` in the same scene counts once). The same
visible-role set bounds which scenes a variant may claim (§8.3).

**Which entities are eligible at all.** The pool is entities with
`review_state != 'rejected'` and `is_relevant = 1`, of any kind. Rejected
tombstones and marked-irrelevant entities earn nothing. Still-`proposed` AI
entities are eligible (§3.7).

**Override, both directions.** `entities` gains one column,
`manifest_inclusion` (`automatic | always | never`, default `automatic`):

- `automatic` — the kind-aware scene threshold decides (for props: the AI
  proposes, §3.4).
- `always` — promote: a one-scene entity that matters (the alien device that
  appears once but defines the film) gets its canonical set anyway.
- `never` — suppress: a recurring entity that needs no dedicated reference
  (the coffee mug in every kitchen scene) earns nothing new; its existing
  requirements are surfaced for the filmmaker to reject, not auto-deleted
  (§5.3).

The override is a human edit through the mutation engine
(`setManifestInclusion`, §7.2); the manifest inference job may *suggest*
overrides but never applies one (§8.4).

**One-scene characters and locations** receive canonical sets because they are
visible generation inputs. One-scene vehicles, creatures, and objects remain
outside the automatic manifest unless promoted; props retain §3.4's separate
judgment path. This bounds incidental production items without omitting the
people and place a scene must depict.

### 3.4 Prop importance: the AI's judgment, reviewed, overridable

The roadmap asks the AI to distinguish a production-important recurring prop
from incidental set dressing, and the product owner confirmed that reading
(2026-08-21, §14.1): **which props earn a slot is the AI's judgment, not a
computed rule.** The original draft proposed a deterministic 2+-scene
default with AI advisories; the owner chose AI judgment outright.

How it works:

1. The manifest inference job (§8) receives **every** prop-kind entity,
   whatever its scene count, with its full structured record — description,
   where and how it appears (roles per scene), its states, and the
   continuity events that touch it.
2. For each prop it deems production-important, the job **proposes the
   prop's canonical reference-view requirement directly** — an
   `ai/proposed` requirement row with a reason ("the revolver recurs and a
   continuity event turns on it") and basis citations (§8.3's
   `importantProps`), landing in the same review queue as everything else.
   A prop it deems incidental simply gets no proposal. The filmmaker
   accepts, edits, or rejects each one; a rejection is a tombstone that
   stops re-proposal.
3. **Human override is still the last word**, both directions:
   `manifest_inclusion = 'always'` gives a prop its deterministic slot with
   no AI involved (created by §5.2's Build, like any other kind), and
   `'never'` makes apply skip any proposal for that prop. Creating a prop
   requirement by hand is always available.

One boundary, stated honestly: the judgment is made from the structured
breakdown, not by re-reading the screenplay. The Phase 1 extraction schema
recorded no importance signal (verified: no prominence, set-dressing, or
count field exists in `extract-chunk-v1.schema.json` or
`reconcile-entities-v1.schema.json`), extraction is a one-time bootstrap,
and the manifest job never sees screenplay text (§3.6). Descriptions,
usage roles, recurrence, states, and continuity events are what the model
judges from — which is also exactly what the review UI shows the filmmaker
checking its work.

Consequences elsewhere in this contract: props are excluded from §3.3's
automatic rule and from §5.2's deterministic Build (except under
`'always'`), so **props enter the manifest only after the AI pass, a manual
add, or an `'always'` override** — characters and locations appear
immediately after import, props after inference. `inclusionSuggestions`
(§8.3) remain for the *other* kinds — promote/suppress advisories on
entities the 2+ rule governs — while props use the direct-proposal channel
above.

### 3.5 Dependencies and staleness

The canonical identity is an input to everything derived from it:

```text
Sarah — Face Closeup (canonical)
        ↓  reference image when generating
Sarah — Office Outfit (variant)
Sarah — Dinner Outfit (variant)
```

Plan 029 adds one canonical bundle edge as well: the Headless Full Body —
Front + Back slot depends on Face Closeup for the same character. The approved
face is therefore sent automatically as the facial-identity reference when
composing the body sheet, while the sheet itself establishes front/rear build,
clothing, and silhouette. Only the front figure is headless; the rear view keeps
the complete back of the head and hairstyle without showing a second face. The
edge is seeded in either canonical creation
order and an existing rejected dependency tombstone remains authoritative.

**Dependencies live at the requirement level** (`asset_dependencies`, §4.3):
requirement R depends on requirement D. Readiness consequences derive
through the assets. A dependency is **satisfied** when its target
requirement has an Approved asset version **or is inactive under the full
§6.4 predicate** — requirement rejected or `not_needed`, *or* its entity
rejected or irrelevant — so a slot the filmmaker has retired, at either
level, can never block downstream work forever. R is **blocked** while any of its
dependencies is unsatisfied. Blocked is a *derived* read (§6.4), not a
stored state — Phase 4 builds its readiness dashboard on the same
derivation. The derived generation order — canonical requirements first,
then variants in dependency order — is exposed by the reads for the UI and
for Phase 3.

**Seeding is deterministic, and tombstones are respected.** When a variant
requirement is created (by apply, §8.4, or by hand, §7.2), it receives one
dependency row on each of its entity's existing active canonical
requirements. When `refreshCanonicalRequirements` (§5.2) creates a *new*
canonical requirement for an entity that already has variants, it seeds the
mirror-image rows — each existing variant gains a dependency on the new
canonical — so a late-enabled template entry still participates in
staleness, satisfying the roadmap's "the canonical identity is an input to
everything derived from it". In both directions, seeding skips any pair for
which a rejected dependency tombstone exists: `removeDependency` on an
`ai`/`parser`-created row tombstones it (the standard rule of Phase 1
§3.6), which is what makes a human's deliberate removal stick across
refreshes and inference.
The filmmaker can remove or add dependency rows freely; cross-entity
dependencies are legal; a Swift walk over the full prospective graph refuses
cycles and self-edges.

**Staleness.** When an asset's approved version *changes* — a different
version is approved over a previously approved one — every asset belonging
to a requirement that depends on the changed requirement is marked **stale**
(`is_stale = 1`, with `stale_since` and a reason naming the changed
dependency). First-time approval marks nothing stale. Stale is a flag, not a
status: the asset keeps its OVERVIEW state (an approved stale asset is still
Approved), the filmmaker decides whether to regenerate, and clearing
staleness is either approving a new version or an explicit "mark current"
(§7.3). This is how the contract satisfies "stale, not invalid" without
inventing a status string — see §6.2. Staleness does not cascade
transitively in the MVP: marking B stale because A changed does not mark C
(which depends on B) stale until B's own approved version actually changes.
Screenplay-level propagation is Phase 6.

### 3.6 One-run posture: what the manifest job consumes

The extraction run is a bootstrap that already distilled the screenplay into
canonical structured data: entities with aliases and descriptions,
appearances with roles, wardrobe/injury/weather/lighting states with scene
ranges, continuity events, relationships, synopses — each with evidence
spans. **Manifest inference consumes that canonical data and never the
screenplay text.**

Consequences, stated because each is load-bearing:

- The job's input is built by FilmCore reads — `ManifestInputBuilder` is a
  **FilmCore** type (it mirrors `ReconcileInputBuilder`'s rendering
  pattern, but §8.4 step 0 must rebuild it inside FilmCore's apply
  transaction, which forecloses a FilmBrain home; FilmBrain calls it
  through the session when launching the job) — is compact, and fits in
  **one Codex request** for a feature — no chunking, no reconcile pass
  (§8.1).
- Privacy improves: the run sends derived structured data (names,
  descriptions, state descriptions, synopses), not the screenplay (§9).
- Manifest quality is bounded by extraction quality plus the filmmaker's
  corrections. That is the product's stated shape — the database is
  canonical, the model interprets it — and it is why requirement review
  exists.
- Because no screenplay text is sent, variant evidence cannot be fresh
  quote-anchoring. Justification is instead **basis links** to the existing
  state/event/appearance rows the proposal cites (§4.3
  `asset_requirement_basis`), whose own evidence spans already anchor into
  the script. "Why does this requirement exist" is answered by scene links,
  the reason text, and the basis rows' evidence.
- **Manifest inference runs once** (product owner, 2026-08-21, §14.2) —
  the same one-time-bootstrap posture as extraction. One *completed applied*
  run per project: a failed or cancelled run may be retried, but after a
  completed run the action is unavailable and the manifest is the
  filmmaker's to edit directly through §7's operations. The §8.4 apply
  rules still enumerate every match case defensively, but nothing in
  Phase 2 depends on a second run existing.
- **The bootstraps close in order.** With extraction latched at its own
  first applied run, one ordering hole is left, and it is real: **nothing
  requires a prior extraction before a manifest run** (§8.1 gates only on
  there being no completed `inferAssetManifest`), so a project can infer
  its manifest from **parser data alone** and still hold its unspent
  analysis. Spending it afterwards would change canonical facts underneath
  requirements, basis citations, and approvals already built on them. So
  **a completed manifest run permanently closes extraction for that
  screenplay** (refused with "the asset manifest is built on this project's
  canonical data"), and a manifest run is **refused while any extraction
  run is non-terminal or paused** — Phase 1's one-active-run rule alone does not cover paused
  runs, which may otherwise resume and
  apply after the manifest exists.

  **Extraction closes at its first applied run** (owner, 2026-08-21,
  reversing the earlier manifest-completion boundary; §14.9). The rule, in
  full, and enforced by FilmCore so no path around the UI exists:

  - A completed `extractScreenplay` parent closes analysis **for that
    screenplay** permanently; a second one is refused with
    `.extractionAlreadyApplied`.
  - Failed and cancelled attempts applied nothing — apply and the parent's
    completion share one transaction — so they may retry.
  - A **paused run resumes as itself**; it never creates a second parent.
    Chunk reuse survives on exactly this path.
  - **Reverting does not reopen eligibility**: revert leaves the job row
    `completed`.
  - There is no second run. A new run means a **new project** (File ▸
    Duplicate Project… copies this one), which is also §5.5's existing
    answer for a revised draft.

  The gate is scoped to the **script**, not the project, because §5.5's
  Replace deletes `scripts` and `entities` but not `jobs`: a project-scoped
  gate would see the superseded run and strand a freshly replaced
  screenplay as parsed-but-unanalyzable. Replace is itself allowed only
  while no protected fact or lock exists and wipes every entity, so the
  screenplay it installs has never been analyzed and gets its one run — it
  cannot stack a second analysis onto curated data. §7.5's widening extends
  Replace's refusal to every manifest row and any imported media.

  Consequences, recorded because each retires machinery rather than adding
  it: §8.5 rule 4a (stale-proposal removal) can never fire, since it only
  removes an *earlier applied run's* proposals — it stays as defensive
  apply behavior, like §8.4's match enumeration, and its confirm-sheet
  promise ("Up to X unreviewed AI facts will be replaced") is gone;
  extraction's basis sweep on stale-proposal removal is therefore **not**
  needed by Plan 012, which drops that edit and the live re-score it
  triggered; and cross-run chunk reuse is unreachable (reuse-on-resume is
  not).

### 3.7 Provenance and protection on the new rows

Requirement, scene-link, dependency, asset, and version rows carry the
standard PROV block (§4.3) and obey the existing rules — `protected`,
`replaceable`, `rejected` tombstones, `reviewed_at` as the only
operator-vouched signal — with no Phase 2 exceptions. The mutation engine's
`ProtectionPolicy` applies through the same checks (§7.5 names the plumbing
each new table needs). Two row families deliberately carry less:

- **Basis rows are immutable citations**, with reduced provenance like
  `evidence` (`source`, `job_id`, `created_at`): created with their
  requirement, never edited, removed with it, excluded from review. Their
  protection is their requirement's.
- **Template rows are settings**, like `locks`: no PROV, human-edited only,
  journaled through §7.2's template operations.
- **PROV `review_state` on assets and versions is inert.** Both are
  human-created (`source = 'human'`, born `accepted`, `reviewed_at` stamped
  per the Phase 1 human-create rule) and their entire working lifecycle
  lives in `status` (§6.1, §6.3). No read, filter, or operation consults
  their `review_state`; the block is present for engine uniformity
  (snapshots, protection, future actors), and this sentence is the contract
  that stops implementers from disagreeing about which axis "rejected"
  means on a version.

**`source = 'parser'` generalizes to "deterministic app pipeline".**
Template-computed canonical requirements are neither AI output nor human
input; they are exactly what Phase 1's parser rows are — deterministic,
authoritative for the fields the pipeline owns, born `accepted`, created
under a human gesture (Phase 1 precedent: `importScreenplay` runs as
`.human` and creates `parser` rows). Rather than widening `FactSource` and
forking the PROV `CHECK` that every existing table shares, canonical-tier
requirement rows and their seeded dependency rows use `source = 'parser'`,
and the docs read that value as "deterministic pipeline" from Phase 2 on.
Parser-owned on a `parser`-sourced canonical requirement is the `name`
field (AI may never rename it; `tier` and `type_id` are immutable columns
no operation edits, so they need no lock-field vocabulary), and AI may
never delete one; the human may (their edit converts `source` to `human`,
as everywhere). An **AI-proposed prop requirement** (§3.4) is canonical-tier
but `ai`-sourced — it follows the ordinary proposed/accepted/protected
lifecycle, not the parser-owned rules. §13 lists this as a delta.

Row-source summary:

| row | source | born as |
|---|---|---|
| canonical requirement from the template rule (§5.2), seeded dependencies | `parser` | `accepted` |
| AI-proposed prop requirement (§3.4), variant requirement, their scene links, basis rows, seeded dependencies (validated AI run) | `ai` | `accepted` with NULL `reviewed_at` |
| any human-created requirement/link/dependency | `human` | `accepted` |
| asset, asset version (human import) | `human` | `accepted` (inert, above) |

The read model retains its provenance-derived `hasUnreviewedFacts` value for
backward-compatible decoding and evaluation tooling, but product UI does not
render it. Schema v8 and successful run apply leave no routine proposals.

**Tombstoned and irrelevant entities.** Rejecting an entity does not cascade
into its requirements (the rows are tombstones, not deletes); instead every
requirement of a rejected or `is_relevant = 0` entity leaves the active set
(§6.4) and is surfaced under the same Rejected/irrelevant filters, for the
filmmaker to reject or delete deliberately. The inference run maps
proposals onto rejected requirements as `skippedRejected`, exactly as
extraction does.

### 3.8 The engine, not a second path

Every Phase 2 mutation is an `EditOperation` case dispatched through the
existing `EditPrimitives.mutate` / `perform` / `performGroup`, journaled in
`edit_journal` with full snapshots, inverted through `applyInverse`, and
guarded by `LockPolicy` and `ProtectionPolicy`. There is no requirement
store, no asset manager, and no import path that writes rows any other way.
§7 is the operation-by-operation contract; media files get one narrow,
stated carve-out for what a JSON snapshot cannot hold (§7.3).

---

## 4. Bundle and storage changes

### 4.1 Media on disk: the `assets/` contract

`assets/` has existed in every bundle since Phase 0 and nothing writes to it
today. Phase 2 gives it this layout:

```text
My Film.aifilm/
├── assets/
│   └── <entity kind>/                    character / location / prop / …
│       └── <entity slug>/                sarah-morgan
│           └── <requirement slug>/       face-closeup, office-outfit
│               ├── v1.png
│               ├── v2.png
│               └── v3.heic
```

Rules, each one a contract:

- **Slugs are path material, not identity.** A slug is
  `AssetPathing.slug(_:)` over the row's `name_normalized`: lowercase,
  runs of non-alphanumerics collapsed to single `-`, trimmed, truncated to
  64 characters, empty → `"unnamed"`. Slugs are computed **once, at the
  moment a version's destination path is chosen**, and the resulting
  relative path is stored on the version row. Renaming an entity or a
  requirement never moves files — the database is the join, the directory
  name is a human courtesy that reflects the name at import time.
- **Version file names are `v<version_number>.<ext>`**, extension taken
  lowercased from the imported file. `version_number` is assigned inside
  the import transaction as one greater than the maximum existing number
  for the asset (deleted versions leave gaps; numbers are never reused
  while any row holds a higher one). If the destination path already exists
  on disk (possible after an undone import orphaned a file, or after
  renames re-converge two slugs), the screenplay importer's collision rule
  applies to the stem: `v3-2.png`, `v3-3.png`.
- **Import copies, atomically, and never mutates the source.** The exact
  `importScreenplay` discipline: resolve a `RelativeProjectPath`, write the
  bytes with `.atomic` into the bundle, then perform the row insert and the
  journal entry in the same database transaction; on any throw, remove the
  staged file and rethrow. The source file outside the bundle is read once
  and never touched.
- **Every stored path is a `RelativeProjectPath`.** Bundle-relative, POSIX,
  validated; resolved against the bundle root at read time. Project
  close/move/reopen therefore needs no path repair — the same guarantee the
  screenplay copy already has, inherited rather than re-implemented.
- **Containment is physical, not lexical.** `RelativeProjectPath`'s checks
  are string-level, which a symlink inside the bundle can defeat (an
  `assets/` subdirectory replaced by a symlink would redirect writes or
  deletions outside the project). Every media operation — write, deletion,
  and **every read that opens the file**: preview, hash verification,
  Reveal in Finder, and later export — therefore resolves the destination
  with symlinks resolved (`realpath`), **the final leaf included**, and
  requires the result to sit under the bundle root's own `realpath`; a
  symlinked component or leaf anywhere under `assets/` refuses the
  operation with a clear error. Validation alone leaves a window — an
  intermediate directory swapped for a symlink after the check but before
  the operation — so the check is not check-then-operate on a path: the
  bundle root is opened once as a directory descriptor and every
  component is walked **descriptor-relative** with no-follow semantics
  (`openat` with `O_NOFOLLOW | O_DIRECTORY` per directory, the leaf with
  `O_NOFOLLOW`), and the operation itself runs against the resulting
  descriptor (`openat`/`renameat`/`unlinkat` forms), so no component can
  be swapped between check and use. Tests cover a planted symlinked
  component, a planted symlinked leaf, and swap-after-validation for
  both the leaf and an **intermediate** component. This hardening lands
  as a shared FilmCore containment check so the Phase 1 screenplay copy
  can adopt it in the same change.
- **Media is content-addressed for integrity, not for layout.** Each version
  row stores the file's SHA-256 and byte count at import. Reads that hand a
  version to the UI or (later) to an export verify size cheaply and may
  verify the hash on demand; a mismatch surfaces as a damaged-asset warning,
  never a crash or silent substitution.
- **MVP media kinds: still images only.** `media_kind` is `image`; accepted
  extensions are `png`, `jpg`/`jpeg`, `webp`, `heic`, `tiff`. Import sniffs
  magic bytes and refuses a file whose content does not match a supported
  image type — imported media is untrusted input like everything else that
  crosses the bundle boundary. Pixel dimensions are read at import and
  stored. Video/audio reference media is out of scope (§11).
- **Rows first, files second.** The two destructive operations
  (`deleteVersion`, `deleteAsset`, §7.3) commit their row removal in the
  database transaction and remove files only **after** commit. A crash in
  the gap leaves orphaned files — harmless and sweepable — and never a row
  pointing at a missing file. Nothing else — not rejection, not requirement
  tombstoning, not entity deletion (which is refused while assets exist,
  §7.4) — ever deletes media; undoing an import leaves the file and removes
  only the row.
- **Orphaned media is a maintenance concern, not a correctness one.**
  A file no version row references is invisible to the app and harmless.
  **Clear Orphaned Media**, next to Phase 1's Clear Job Cache, lists and
  deletes them after confirmation. It runs through the session (serialized
  with all writes), touches no rows and journals nothing, and is
  non-invertible; a pending redo of an undone import whose file it removed
  will refuse cleanly (§7.3's redo re-verification).

### 4.2 Migration v3 → v4

Bundle schema 4 is a registered GRDB migration `"v4"` in `ProjectMigrator`,
default `foreignKeyChecks: .deferred` like every predecessor;
`FilmCoreVersion.bundleSchema` becomes 4. DDL lives in a new `SchemaV4` enum
of raw SQL constants, in the house style (§4.3's SQL is that file's
contract). v3 → v4 is non-destructive — no re-parse, no row loss — so like
v2 → v3 it shows no one-way upgrade modal (that gate remains
`schemaVersion == 1` only).

Steps, in one migration transaction and **in this order** (new tables before
the `locks` rebuild so nothing references them mid-flight; `projects` rebuilt
last so GRDB's terminal `PRAGMA foreign_key_check` sees the final graph;
indexes on rebuilt tables created after the rebuilds, since a `DROP TABLE`
takes its indexes with it):

1. `ALTER TABLE entities ADD COLUMN manifest_inclusion TEXT NOT NULL
   DEFAULT 'automatic' CHECK (manifest_inclusion IN
   ('automatic','always','never'))`. (Legal SQLite: constant default,
   column-level CHECK — verified on the shipped library.)
2. Create the new tables (§4.3) in dependency order —
   `asset_requirement_types`, `asset_requirements`,
   `asset_requirement_scenes`, `asset_requirement_basis`,
   `asset_dependencies`, `assets`, `asset_versions` — and their indexes:
   `index_asset_requirements_on_entity_id`,
   `index_asset_requirements_on_type_id`,
   `index_asset_requirement_scenes_on_scene_id`,
   `index_asset_dependencies_on_depends_on_requirement_id`,
   `index_assets_on_project_id`, `index_asset_versions_on_asset_id`, and the
   partial unique index `index_asset_versions_approved` (§4.3). The
   requirement index leads on `entity_id` — the column every FK lookup and
   cascade actually uses; `project_id` is a constant in a one-project
   database. Constraints that already materialize an index (`UNIQUE`,
   `PRIMARY KEY`) are not indexed again, per house rule — which is also why
   `asset_requirement_basis` gets no separate index (its `UNIQUE` leads on
   `requirement_id`).
3. Seed `asset_requirement_types` with the §3.2 default template rows for
   the then-current four-view template rows for the existing project row,
   `sort_order` in table order, `is_enabled = 1`.
   A v3 bundle always holds exactly one project row; a **fresh** bundle
   reaches v4 with zero project rows and seeds nothing here — project
   creation (`ProjectBundle.create`) seeded the same historical content at
   schema 4. Schema v11 now owns current fresh-project seeding.
4. Rebuild `locks` with `subject_kind` widened to
   `('entity','alias','scene','state','event','relationship','requirement')`
   — copy every row explicitly (never `SELECT *`), drop, rename. `locks` has
   no separate indexes to recreate (its `PRIMARY KEY` materializes the only
   one) and no foreign keys, so the rebuild is self-contained. Its `field`
   column has no CHECK, which is why the new lock fields (§7.5) need no
   schema change.
5. Rebuild `projects` with `CHECK (bundle_schema_version = 4)`, rewriting
   the stored value to `4`; every other column unchanged. No `projects`
   indexes exist to recreate.
6. `PRAGMA user_version = 4`.

The registered `"v2"` and `"v3"` migrations are not edited, for the recorded
Phase 1 reason: bundles at those versions exist and GRDB records migrations
by name. The migration test asserts unchanged row counts for every v3 table,
the seeded template rows, the widened `locks` CHECK admitting a
`requirement` row, and a clean `PRAGMA foreign_key_check`.

### 4.2a Migration v10 → v11 (Plan 029 amendment)

Bundle schema 11 changes character-template policy without changing the
manifest table shape. In one transaction it disables `profile_side` and
`waist_up`; sets their existing requirements to `not_needed`, their assets to
`deprecated`, and their incoming dependency edges to rejected tombstones;
renames untouched default `Full Body` template/requirement labels to Headless
Full Body — Front + Back when no normalized-name collision exists; marks an
existing approved full-body asset stale; and inserts Full Body → Face Closeup
dependency rows with `INSERT OR IGNORE`, so any existing row—including a
rejected tombstone—wins. It deletes no requirement, asset, version, prompt,
media, or provenance. Customized labels remain unchanged. The `projects`
table is rebuilt only to pin `bundle_schema_version = 11`; fresh projects seed
the same current policy directly after inserting their project row.

### 4.2b Migration v11 → v12 (Plan 030 amendment)

Bundle schema 12 adds nullable `visual_amendment` and
`visual_amendment_scope` columns to immutable `image_generation_runs` rows.
It also adds `image_generation_amendments`, an immutable ordered snapshot of
the human amendments each successful run applied, so regeneration carries the
same direction even when it does not reference the prior target image.
Existing runs remain byte-for-byte meaningful with both columns NULL. The
projects table is rebuilt only to pin `bundle_schema_version = 12`; no prompt,
asset, version, media path, generation run, reference, or journal row is
deleted or rewritten. Successful post-migration edit imports persist the exact
validated human instruction and its requirement or character-bundle scope in
the same transaction as the generated versions and approval.

### 4.2c Migration v12 → v13 (Plan 031 amendment)

Bundle schema 13 adds `scene_reference_exclusions`, keyed uniquely by
`(scene_id, requirement_id)`, with cascading foreign keys to the owning scene
and requirement. Existing projects receive no exclusion rows and therefore keep
identical reference plans. The projects table is rebuilt only to pin
`bundle_schema_version = 13`; no screenplay appearance, requirement, asset,
version, prompt, generation run, media path, provenance, or journal row is
rewritten. Controlled mutations admit only human exclusions of canonical prop-family
requirements visibly linked to the scene. The readiness graph subtracts those
rows after canonical and variant link derivation.

### 4.3 Schema v4 (new and changed tables)

Column conventions exactly as Phase 1: TEXT UUIDs, ISO-8601 UTC timestamps
with fractional seconds, foreign keys ON at runtime, `CHECK` on closed
enums, `ON DELETE` stated on every foreign key, table-level constraints
after the last column. **PROV** abbreviates the existing shared block
verbatim:

```text
source TEXT NOT NULL CHECK (source IN ('parser','ai','human')),
confidence REAL CHECK (confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0)),
review_state TEXT NOT NULL CHECK (review_state IN ('proposed','accepted','rejected')),
reviewed_at TEXT,
job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL,
created_source TEXT NOT NULL CHECK (created_source IN ('parser','ai','human')),
created_at TEXT NOT NULL,
updated_at TEXT NOT NULL
```

New tables:

```text
asset_requirement_types                       -- the per-project template (§3.2); policy, not facts
  id TEXT PRIMARY KEY NOT NULL,
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  entity_kind TEXT NOT NULL CHECK (entity_kind IN
      ('character','location','prop','vehicle','creature','object')),
  code TEXT NOT NULL,                          -- stable slug: 'face_closeup', 'establishing'
  display_name TEXT NOT NULL,                  -- 'Face Closeup'
  sort_order INTEGER NOT NULL,
  is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(project_id, entity_kind, code)
  -- no PROV: template rows are settings (like locks), human-edited only,
  -- journaled through §7.2's template operations. Swift validation:
  -- code is [a-z0-9_]+, and display names are normalized-unique per
  -- (project, entity_kind) so generated requirement names cannot collide.

asset_requirements
  id TEXT PRIMARY KEY NOT NULL,
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
  tier TEXT NOT NULL CHECK (tier IN ('canonical','variant')),
  type_id TEXT REFERENCES asset_requirement_types(id) ON DELETE RESTRICT
      CHECK ((tier = 'canonical') = (type_id IS NOT NULL)),
  name TEXT NOT NULL,                          -- display: 'Face Closeup', 'Office Outfit'
  name_normalized TEXT NOT NULL,               -- EntityNormalization.normalize(name)
  reason TEXT NOT NULL DEFAULT '',             -- why this requirement exists, prose
  necessity TEXT NOT NULL DEFAULT 'required'
      CHECK (necessity IN ('required','optional','not_needed')),
  PROV,
  UNIQUE(entity_id, type_id),                  -- one canonical slot per template entry
                                               -- (NULL type_id rows — variants — are
                                               --  distinct under SQLite UNIQUE, by design)
  UNIQUE(entity_id, name_normalized)           -- names unique per entity, across tiers
  -- tier and type_id are immutable after creation: no operation edits them.
  -- display convention: the UI renders 'Sarah — Office Outfit' by joining
  -- entity name and requirement name; 'name' never embeds the entity.
  -- Swift validation: type_id's row must match the entity's kind and project.

asset_requirement_scenes                      -- variant-tier scene links (§5.2 derives canonical links)
  id TEXT PRIMARY KEY NOT NULL,
  requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE,
  scene_id TEXT NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
  PROV,
  UNIQUE(requirement_id, scene_id)
  -- Swift validation: rows exist only for tier = 'variant' requirements

asset_requirement_basis                       -- which existing facts justify this requirement (§3.6)
  id TEXT PRIMARY KEY NOT NULL,
  requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE,
  subject_kind TEXT NOT NULL CHECK (subject_kind IN ('state','event','appearance')),
  subject_id TEXT NOT NULL,                    -- no FK (polymorphic, like locks); swept on fact
                                               -- delete AND on cascaded fact deletion (§7.4)
  source TEXT NOT NULL CHECK (source IN ('parser','ai','human')),
  job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL,
  UNIQUE(requirement_id, subject_kind, subject_id)
  -- reduced provenance like evidence: an immutable citation, not a
  -- reviewable fact (§3.7). 'parser' is admitted for symmetry with the
  -- evidence CHECK though §3.7's table never produces one today.

asset_dependencies
  id TEXT PRIMARY KEY NOT NULL,
  requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE,
  depends_on_requirement_id TEXT NOT NULL REFERENCES asset_requirements(id) ON DELETE CASCADE
      CHECK (depends_on_requirement_id <> requirement_id),
  PROV,
  UNIQUE(requirement_id, depends_on_requirement_id)
  -- full-graph cycle check in Swift before any write (§3.5); removal of an
  -- ai/parser row is a rejected tombstone that seeding respects (§3.5)

assets
  id TEXT PRIMARY KEY NOT NULL,
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  requirement_id TEXT NOT NULL UNIQUE REFERENCES asset_requirements(id) ON DELETE RESTRICT,
  status TEXT NOT NULL CHECK (status IN
      ('needed','prompt_ready','in_progress','needs_review','approved',
       'rejected','deprecated')),               -- OVERVIEW asset states, §6.1
  is_stale INTEGER NOT NULL DEFAULT 0 CHECK (is_stale IN (0, 1)),
  stale_since TEXT,
  stale_reason TEXT,
  rejected_explicitly INTEGER NOT NULL DEFAULT 0
      CHECK (rejected_explicitly IN (0, 1)),  -- §6.3 rule 3; survives deprecation
  notes TEXT NOT NULL DEFAULT '',
  PROV,
  CHECK ((is_stale = 1) = (stale_since IS NOT NULL)),
  CHECK ((is_stale = 1) = (stale_reason IS NOT NULL))
  -- ON DELETE RESTRICT: a requirement (or its entity) with media cannot
  -- vanish implicitly; §7.3/§7.4 give the explicit, journaled path

asset_versions
  id TEXT PRIMARY KEY NOT NULL,
  asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  version_number INTEGER NOT NULL CHECK (version_number >= 1),
  status TEXT NOT NULL CHECK (status IN ('needs_review','approved','rejected')),
  relative_path TEXT NOT NULL,                 -- RelativeProjectPath into assets/ (§4.1)
  sha256 TEXT NOT NULL,
  byte_count INTEGER NOT NULL CHECK (byte_count > 0),
  original_file_name TEXT NOT NULL,
  media_kind TEXT NOT NULL CHECK (media_kind IN ('image')),
  pixel_width INTEGER CHECK (pixel_width IS NULL OR pixel_width > 0),
  pixel_height INTEGER CHECK (pixel_height IS NULL OR pixel_height > 0),
  notes TEXT NOT NULL DEFAULT '',
  PROV,
  UNIQUE(asset_id, version_number),
  UNIQUE(relative_path)                        -- deliberate: version rows carry no
                                               -- project_id; one project per bundle

-- partial unique index: at most one approved version per asset
CREATE UNIQUE INDEX index_asset_versions_approved
    ON asset_versions(asset_id) WHERE status = 'approved';
```

Changed tables:

```text
entities  (ALTER TABLE, §4.2 step 1)
  + manifest_inclusion TEXT NOT NULL DEFAULT 'automatic'
        CHECK (manifest_inclusion IN ('automatic','always','never'))

locks  (rebuilt, §4.2 step 4)
  subject_kind CHECK gains 'requirement'      -- fields per §7.5

projects  (rebuilt, §4.2 step 5)
  CHECK (bundle_schema_version = 4)
```

Deleted-row policy: hard-deleting a requirement cascades to its scene links,
basis rows, and dependency rows (both directions), is **restricted** by an
existing asset, and removes its lock rows through the operation (snapshotted
for undo) — but hard delete applies only to `human`-created rows and rows
already tombstoned, exactly as §3.6 of the Phase 1 design rules for
entities. Deleting an asset cascades to its versions' **rows**; files follow
§4.1's rows-first rule. Basis rows have no FK to their polymorphic subject;
the operations that delete or merge states/events/appearances sweep matching
basis rows in the same transaction, **including the cascade paths** — the
entity- and scene-delete capture lists sweep basis rows for every fact their
cascades remove (§7.4) — and Phase 1's orphan-evidence test pattern gains a
basis-row twin covering both the direct and cascaded paths.

### 4.4 Domain types

New public FilmCore types (names are contracts for the plans):

- `AssetRequirement`, `AssetRequirementTier` (`canonical | variant`),
  `RequirementNecessity` (`required | optional | notNeeded`, raw values
  `required`/`optional`/`not_needed`), `AssetRequirementType` (a template
  row), `AssetRequirementScene`, `AssetRequirementBasis`, `AssetDependency`
- `Asset`, `AssetStatus` (§6.1's seven states, raw values as in the CHECK),
  `AssetVersion`, `AssetVersionStatus` (`needsReview | approved | rejected`,
  raw values `needs_review`/`approved`/`rejected`), `MediaKind`
- `ManifestInclusion` (`automatic | always | never`) on `Entity`
- `DefaultRequirementTemplate` (the §3.2 seed constant),
  `AssetPathing` (slug + destination-path functions, §4.1)
- `RequirementSummary` and `RequirementDetail` (list/inspector read shapes,
  including the derived `isBlocked`, `requiredBy` scenes, the active flag
  (§6.4), and the unreviewed-facts flag), `ManifestSummary` (§6.4's counts),
  `MissingAsset` (the "what is still missing" row)
- `ManifestApplyReport`, `ManifestSettings`, and
  `ManifestInclusionSuggestion` (§8.5)
- `SubjectKind` gains cases per §7.5; `LockField` gains `reason` and
  `necessity` (§7.5); `ProjectChange` gains `.requirements` and `.assets`
  areas; `EntityDetail` gains its requirements
- `Job` gains a `manifestReport` accessor beside `applyReport`; **both
  accessors gate on `task`** (today `applyReport` shape-gates only by
  accident of disjoint keys), and a test asserts the two report types stay
  key-disjoint so run history can never cross-decode

---

## 5. The deterministic manifest (Phase 2a)

### 5.1 What exists with no AI at all

After a bare import (parser entities only) the manifest already has content:
speaking characters and heading locations that qualify under §3.3 get their
template canonical sets. After the extraction run, AI-found vehicles,
creatures, and objects join the pool. Props are the stated exception
(§3.4): they enter the manifest through the 2b inference pass, a manual
add, or an `'always'` override — everything else in 2a waits on no model.

### 5.2 Building canonical requirements

**Build Asset Manifest** (the 2a primary action; idempotent, repeatable) runs
`refreshCanonicalRequirements` (§7.2): for every eligible entity (§3.3 —
props only under `manifest_inclusion = 'always'`, §3.4) and
every enabled template entry for its kind, create the canonical requirement
if no row for `(entity_id, type_id)` exists — including a tombstoned one,
which is respected and skipped. **Name collisions are skipped, never raw
errors**: `UNIQUE(entity_id, name_normalized)` spans tiers, so an existing
requirement of any tier whose normalized name equals the entry's display
name (an AI-proposed variant named "Face Closeup", or a row created under a
since-renamed template entry) blocks that one creation — the child is
skipped with a typed refusal, counted in the Build result — Build returns
a typed `ManifestBuildResult` (`created`, `collisions:` pairs naming the
blocked entry and the existing row, and the journal entry **only when at
least one child ran**: the engine guards before `performGroup`, which
otherwise always journals, so an idempotent no-op Build writes nothing) —
and surfaced as
a §5.3 badge naming both rows; Build continues, and the filmmaker resolves
by renaming the collider — or deleting it, since rejecting is not enough:
a tombstone keeps its `name_normalized`, so the UNIQUE key stays taken
(the same tombstone-wins reading as Phase 1's entity names) — and Building
again. Created rows:
`tier = 'canonical'`,
`source = 'parser'`, `accepted`, `name` = the template entry's display name,
`necessity = 'required'`; for each new canonical, dependency rows are seeded
from the entity's existing variants per §3.5. Creation runs through a
dedicated engine case (`createCanonicalRequirement`, §7.2) so parser
provenance is fixed by the operation, not by trusting a caller; the whole
refresh journals as **one group, or nothing at all when there is nothing to
create** — a no-op refresh writes no journal row. A successful extraction
apply runs this refresh automatically in the same transaction after its
appearance writes, and tags the group with that run so Revert removes it.
The explicit Build action remains idempotent and repeatable for later human
edits that move entities across the qualification boundary; no other edit
silently triggers a refresh. Until that explicit refresh, the read layer
badges an entity that qualifies but lacks its set (§5.3).

**Canonical scene links are derived, not stored.** A canonical requirement's
"required by" is every scene where its entity appears in a qualifying role
(§3.3), computed at read time from `scene_entities`. Storing them would
create a second copy of the appearance data that goes stale under human
appearance edits; deriving keeps one source of truth. Variant requirements
store explicit `asset_requirement_scenes` rows because a variant is
precisely a *subset* judgment (office outfit ≠ all of Sarah's scenes) that
cannot be derived.

### 5.3 Drift between the rule and the rows

Human edits move entities across the 2+ boundary (merging two one-scene
characters, removing an appearance, flipping `manifest_inclusion`) and
reshape the template. Materialized requirement rows are review-model facts
that may carry approvals, media, and locks — so **neither the rule nor the
template ever deletes them**:

- An entity newly qualifying gains its canonical set on the next Build.
  Until then the manifest view badges it "qualifies but has no canonical
  set — Build to add".
- An entity no longer qualifying (or set to `never`) keeps its requirement
  rows; the view badges them "no longer qualifies (appears in 1 scene)" /
  "suppressed" and the filmmaker rejects, deletes, or keeps them
  deliberately.
- A disabled or renamed template entry does not touch existing rows; rows
  whose entry is disabled are badged "template entry disabled".
- A canonical slot Build could not create because of a §5.2 name collision
  is badged on the entity: "canonical slot '<entry>' blocked by an existing
  requirement name — rename or delete it, then Build" (delete, not reject:
  a rejected row keeps the normalized name, §5.2).

The rule proposes; the filmmaker disposes — the same asymmetry the whole
product is built on, applied to a deterministic proposer.

---

## 6. States, in OVERVIEW's exact vocabulary

`docs/OVERVIEW.md#asset-states` is the pinned cross-phase vocabulary. Phase 2
introduces no new status strings; it stores the asset states, reuses three of
their names for versions (`needs_review`, `approved`, `rejected`), expresses
requirement review through the existing PROV vocabulary, and leaves
scene-readiness and generation-package states to Phases 4 and 6.

### 6.1 Asset states (stored on `assets.status`)

The full canonical set is admitted by the CHECK so Phase 3 needs no
migration; Phase 2 reaches five of the seven:

| state | code | Phase 2 meaning |
|---|---|---|
| Needed | `needed` | asset row exists with zero version rows (reachable via `deleteVersion` of the last version); also the *derived* display state of a requirement with no asset row |
| Prompt Ready | `prompt_ready` | reserved for Phase 3 (prompt generated, nothing imported) |
| In Progress | `in_progress` | reserved for Phase 3 (generation workflow underway) |
| Needs Review | `needs_review` | at least one version, none approved, not explicitly rejected |
| Approved | `approved` | exactly one approved version — the canonical reference |
| Rejected | `rejected` | filmmaker explicitly rejected the slot's media as a whole (`rejected_explicitly`, §6.3 rule 3; no approved version; remaining versions may still be individually un-reviewed) |
| Deprecated | `deprecated` | asset retired because its requirement is rejected or `not_needed` (§6.3 rule 1); media kept |

**The approved-version invariant**, mutation-maintained and test-asserted:
an asset with `status = 'approved'` has exactly one approved version (the
partial unique index gives at-most-one; the §7.3 operations give
exactly-one). The converse is deliberately weaker: an approved version may
also exist on a **`deprecated`** asset — deprecation retires the slot
without demoting its media, so restoring the requirement restores the
Approved state losslessly (§6.3's recompute). No other status may hold an
approved version.

A requirement with no asset row **displays** as Needed. Requirement rows
themselves carry no asset-state column — a requirement's review lifecycle is
PROV `review_state` (`proposed`/`accepted`/`rejected`), which is Phase 1
vocabulary, not a new one. The two axes are orthogonal and the UI keeps them
visually distinct: a *proposed* requirement is an AI suggestion awaiting
review; a *Needed* asset is an accepted slot awaiting media.

### 6.2 Stale is a flag, not a state

The roadmap requires "re-approving a different canonical version marks every
derived asset **stale**, not invalid", but OVERVIEW's pinned asset-state list
has no Stale (Stale exists only among generation-package states). Adding one
would be inventing a status string. Resolution: staleness is the orthogonal
`is_stale` flag of §3.5 — an Approved asset that is stale remains Approved,
rendered with a stale badge and the reason. Phase 5's generation-package
Stale state is unrelated and untouched.

### 6.3 State machine (Phase 2 transitions)

Requirement (PROV `review_state`):

```text
proposed ──acceptFacts──▶ accepted ──reject──▶ rejected ──unreject──▶ (prior)
(human create/edit ⇒ accepted; AI may replace only wholly-proposed graphs, §8.4)
```

Asset status is maintained by **one recompute rule**, applied at the end of
every asset/version operation and by the inverse path (which restores
snapshots and therefore agrees by construction):

```text
recompute(asset):
  1. requirement rejected or necessity = not_needed   → deprecated
  2. an approved version exists                       → approved
  3. explicit rejection standing                      → rejected
  4. at least one version row                         → needs_review
  5. no version rows                                  → needed
```

Rule 1 is deliberately **requirement-level only**: entity-level inactivity
(a rejected or irrelevant entity, §6.4) is a read-time concern — it removes
the requirement from the active set and badges it, but never rewrites a
stored asset status, which is why §7.4's entity tombstoning touches no
requirement rows. "Explicit rejection standing" (rule 3) is the
`rejected_explicitly` column (§4.3): set by `rejectAsset`, cleared by
`unrejectAsset`, by `importAssetVersion`, and by `deleteVersion` removing
the last version row — and untouched by deprecation, so a rejected slot
that is retired and later restored comes back **rejected**, not quietly
reopened. With that column, `status` is fully determined by the recompute
rule; no operation writes it any other way.

Operation-by-operation consequences (each op's own preconditions in §7.3):

| gesture | effect on versions | asset status after recompute |
|---|---|---|
| first import (creates asset) | new `needs_review` version | `needs_review` |
| later import | new `needs_review` version; clears explicit rejection | `needs_review` (or `approved` if an approved version stands) |
| `approveVersion` | target → `approved`; previously approved → `needs_review` | `approved`; dependents' staleness per §3.5 |
| `rejectVersion` | target → `rejected` | recompute (rules 2–5) |
| `unrejectVersion` (user gesture) | target → `needs_review`, always | rule 2–5 |
| `deleteVersion` (rejected versions only) | row and file removed; deleting the last version clears a standing explicit rejection | rules 2–5 (`needed` when it was the last) |
| `rejectAsset` (precondition: no approved version) | sets `rejected_explicitly` | `rejected` |
| `unrejectAsset` | clears `rejected_explicitly` | rules 2–5 |
| requirement → `not_needed` or rejected | none (`rejected_explicitly` untouched) | `deprecated` |
| requirement restored to active | none | rules 2–5 — `approved` if the preserved approved version stands; `rejected` if the explicit rejection stands |

Two deliberate asymmetries, stated so nobody re-derives them: the *user
gesture* `unrejectVersion` always lands on `needs_review` (un-rejecting is
"reconsider", not "restore"), while the *inverse* of `rejectVersion` restores
the snapshotted prior status exactly — inverse application is byte-identical
restoration, not a gesture. And `importAssetVersion` is **refused while the
requirement is inactive** — media cannot resurrect a deprecated slot; restore
the requirement first. Deprecation checks both causes: un-rejecting a
requirement that is still `not_needed` leaves its asset `deprecated`.

### 6.4 Active requirements, and "what assets are still missing?"

One predicate, used by every manifest, blocked, stale, and summary read, so
counts and lists can never disagree:

> **active(requirement)** := requirement `review_state != 'rejected'`
> AND `necessity != 'not_needed'`
> AND its entity has `review_state != 'rejected'` and `is_relevant = 1`.

Qualification drift and `manifest_inclusion = 'never'` do **not** deactivate
existing rows — they only badge them (§5.3); the filmmaker deactivates by
rejecting or marking `not_needed`. `necessity = 'optional'` rows stay active
but are reported separately and will not block Phase 4 scene readiness.

Derived reads, no model in the loop:

- **Missing** := active requirements with `necessity = 'required'` whose
  asset is absent or not Approved.
- **Blocked** := a missing requirement with an unsatisfied dependency
  (§3.5) — create the dependency first; the reads expose the resulting
  creation order (canonical first, then variants in dependency order).
- **Stale** := Approved but `is_stale = 1` — worth revisiting, not missing.
- `ManifestSummary` reports, per kind and overall: requirement counts by
  tier, Approved / Needs Review / missing counts, blocked, stale, and
  optional counts — the numbers the roadmap's dashboard sketch shows.

---

## 7. Editing contract: extensions of the mutation engine

### 7.1 Ground rules

Every operation below is a new `EditOperation` case flowing through the
existing engine — `mutate` returns a `MutationEffect` with inverse and
affected set, `perform` journals one row, compound actions use
`performGroup`, inverses re-check preconditions and restore snapshots
byte-identically. New operation families live in new files under `Editing/`
(`RequirementOperations`, `AssetOperations`, `TemplateOperations`) that open
no transaction, matching the reentrancy rule the existing tests enforce
(the test globs `Editing/*.swift`, so new files are covered automatically).
The review verbs — approve is `acceptFacts` over requirement refs, reject is
the tombstone — are the *same* operations Phase 1 review uses, pointed at
new subject kinds; requirement review adds no parallel review path.

**The `.ai` actor's write surface, stated once.** The AI actor in Phase 2 is
the manifest inference run, and it may do exactly this: create variant
requirements with their scene links, basis rows, and seeded dependencies;
create canonical-tier **prop** requirements with basis rows (§3.4); and
replace graphs that are still wholly `ai/proposed` (§8.4). It never
creates, renames, or deletes `parser`-sourced canonical requirements
(parser-owned, §3.7);
never touches assets, versions, media files, template rows,
`manifest_inclusion`, or necessity; never edits dependencies on rows it did
not create; and never approves anything. Enforcement lives where everything
else's does — `ProtectionPolicy` over the new rows' PROV, plus human-only
guards (the existing `requireHuman` discipline) on every asset, template,
inclusion, necessity, and review operation.

### 7.2 Requirement and template operations

| op | inverse | notes |
|---|---|---|
| `createRequirement(id, entityID, tier, typeID?, name, reason)` | `deleteRequirement` | human path; validation: name non-empty, unique per §4.3's uniques, `tier`/`typeID` pairing, `typeID` kind/project agreement, entity in §3.3's **pool** (non-rejected, relevant) only — the 2+ rule, the prop exception, and `manifest_inclusion` bound Build and the AI, never a deliberate human add (a human may create a prop requirement, or one on a `'never'` entity, directly) |
| `createCanonicalRequirement(id, entityID, typeID, name)` | `deleteRequirement` | engine-internal case with fixed `parser` provenance; only `refreshCanonicalRequirements` emits it (§5.2) |
| `deleteRequirement(id)` | `restoreRequirement(graph:)` (payload holds the row graph incl. links, basis, dependencies both directions, lock rows) | human-created or already-rejected rows only; `ai`/`parser` rows tombstone instead (engine routes, as entity delete does); **refused while an asset row exists** — delete the asset first |
| `rejectRequirement(id)` / `unrejectRequirement(id, priorState)` | each other | the tombstone; stops re-proposal resurrection; recomputes its asset to/from `deprecated` in the same group (§6.3) |
| `renameRequirement(id, name)` / `setRequirementReason(id, text)` | same op, prior value | rename re-checks `UNIQUE(entity_id, name_normalized)` |
| `setRequirementNecessity(id, necessity)` | same op, prior value | covers the roadmap's "mark optional" and "mark no dedicated asset needed"; recomputes the asset in-group |
| `addRequirementScene(requirementID, sceneID)` / `removeRequirementScene(linkID)` | each other | variant tier only; edit the "required by" set; ai-created link removal tombstones per Phase 1 §3.6; a human add whose `(requirement_id, scene_id)` matches a tombstoned row **un-rejects that row** (one journal entry, inverse = reject) instead of raw-failing the UNIQUE key |
| `addDependency(requirementID, dependsOnID)` / `removeDependency(id)` | each other | full-graph cycle/self-edge check; both endpoints non-rejected; removal of an ai/parser row tombstones (seeding respects it, §3.5); a human add whose pair matches a tombstoned row **un-rejects that row** (cycle check still runs first; one journal entry, inverse = reject) instead of raw-failing the UNIQUE key |
| `combineRequirements(sourceIDs, into)` | `uncombineRequirements(payload)` | see below |
| `splitRequirement(id, sceneIDs, newName, newID)` | `unsplitRequirement(payload)` | variant tier; `sceneIDs` must be a **nonempty proper subset** of the source's stored links (moving everything is a rename, not a split); scene links in the subset move; basis rows follow their fact's scene footprint (below); the new requirement receives §3.5's deterministic dependency seeding (tombstones respected); **the source keeps its asset and versions — the split-off requirement is born empty**; payload-driven inverse deletes every row the split created (copies included) and moves the rest back, byte-identical, per the merge/split discipline |
| `setManifestInclusion(entityID, inclusion)` | same op, prior value | the §3.3 override; human-only |
| `setTemplateEntryEnabled(typeID, isEnabled)` / `renameTemplateEntry(typeID, displayName)` / `setTemplateEntryOrder(typeID, sortOrder)` / `addTemplateEntry(kind, code, displayName, sortOrder)` / `removeTemplateEntry(typeID)` | flip / prior / prior / remove / restore(snapshot) | human-only; `removeTemplateEntry` is refused while any requirement references the entry (`ON DELETE RESTRICT` backs it) — disable instead; renames never touch existing requirement rows (§3.2) |
| `refreshCanonicalRequirements` | `.batch` of the children's inverses | a `performGroup` of `createCanonicalRequirement` + seeded-dependency children; idempotent; journals nothing when there is nothing to create (§5.2) |

**`combineRequirements` (the roadmap's "combine"), fully specified** because
duplicate slots get filled before anyone notices they are duplicates:

- **All participants must be variant-tier.** Canonical requirements never
  combine: their scene links are derived, so a variant's stored links moved
  onto a canonical target would be stranded rows the reads ignore, and
  canonical duplicates only arise through entity merges, which resolve them
  by the §7.4 collision rule. The roadmap's "combine duplicates" case is a
  variant-tier phenomenon by construction.
- Scene links, basis rows, and dependencies move to the target; rows
  colliding on their uniques are snapshotted and dropped, survivor by the
  same ordering as §7.4's requirement collisions: **liveness first** — an
  active row always survives over a `rejected` tombstone, whatever its
  source or review rank — then the Phase 1 protection order, then earliest
  `created_at`, then `id`; dependency edges are retargeted with self-edges
  removed, duplicates dropped, and the full prospective graph re-checked for
  cycles before any write.
- **Assets merge, with a total survivor rule.** If only one participant has
  an asset it is re-pointed to the target requirement. If several do, the
  **surviving asset row** is chosen deterministically: the target's own
  asset when it has one; otherwise the participant asset preferred by
  (holds an approved version) first, then earliest `created_at`, then `id` —
  and the survivor is re-pointed to the target. Every other asset's version
  rows move under the survivor, renumbered deterministically (appended in
  source-requirement order, then version-number order, each taking
  max + 1); files never move — their recorded paths stay valid. At most one
  approved version survives: the **survivor's** approved version wins; any
  other approved version is demoted to `needs_review` (snapshotted). The
  survivor keeps its own `is_stale`/`stale_reason` and
  `rejected_explicitly`; the losers' flags are discarded with their rows,
  snapshotted in the payload. Status is recomputed once at the end. The
  inverse is payload-driven and **hand-ordered like `approveVersion`'s**:
  demote the survivor's approved version first, then restore the loser
  asset rows and their versions from snapshots — the partial unique index
  is enforced per statement.
  Moved version files keep their original names on disk — after a combine,
  a `v3.png` filename no longer implies `version_number = 3`; the row's
  `version_number` and `relative_path` are the truth, per §4.1's
  names-are-historical rule.
- **Sources are tombstoned, not deleted** (`review_state = 'rejected'`,
  their emptied graph snapshotted in the payload), so an inference run —
  or a retry after a failed one — that proposes the merged-away name maps
  onto the tombstone as `skippedRejected` instead of resurrecting the
  duplicate — the same job aliases do for entity merges. Hard delete of the
  tombstone remains available afterward.
- **Sources may belong to a different entity** than the target ("Sarah's
  blue sweater" extracted once as a prop requirement and once under the
  wrong character). The combined requirement lives on the **target's**
  entity; moved scene links are entity-agnostic (they reference scenes) and
  carry over unchanged. A tombstoned source stays on its own entity; if that
  entity is later merged away, the tombstone moves like any requirement and
  a name collision resolves through §7.4's collision-survivor rule (the
  active row wins; the tombstone is snapshotted and dropped).
- Any lock on any participant blocks the combine, both actors, per the
  Phase 1 lock-blocks-merge rule.

**`splitRequirement`'s basis assignment, pinned** — basis rows carry no
scene column, so assignment goes through the cited fact's scene footprint
(an appearance's scene; an event's scene; a state's scene range intersected
with the requirement's scenes). With M the moved scene set and R the
remainder: footprint entirely in M → the row moves; entirely in R → it
stays; **overlapping both** (a wardrobe state spanning the split) → the row
stays and a **copy** is created for the new requirement — legal because
basis uniqueness is per requirement, and correct because a citation is not
a resource that must live on one side. A fact whose footprint is empty
against both sets (an event outside every linked scene, legitimately citing
a variant it precedes) stays with the source. The inverse deletes the
copies and moves the moved rows back; nothing is guessed at undo time
because every assignment is recorded in the payload.

Review: `acceptFacts` and `acceptAllProposed` gain requirement,
requirement-scene, and dependency refs through `ReviewOperations`' existing
target mapping, and its `expand` step — which today fans an accepted entity
out to its alias and appearance rows — gains the requirement case: accepting
a requirement accepts its still-proposed scene links and dependencies (basis
rows are non-reviewable citations and are excluded). `acceptAllProposed`
therefore sweeps proposed requirements along with proposed facts, and the
manifest review UI's per-section Accept All passes explicit refs, exactly as
entity review does today.

### 7.3 Asset and version operations

| op | inverse | notes |
|---|---|---|
| `createAsset(id, requirementID)` | `removeAssetRow(assetID)` — inverse-only case, rows only, never files; its own inverse restores from snapshot | composed into the first import's group, so first-import undo **and redo** work; requirement must be active (§6.4); a proposed requirement is accepted implicitly in the same group (import is the strongest possible accept gesture, mirroring Phase 1's "Edit accepts implicitly") |
| `deleteAsset(id)` | **non-invertible** | removes the asset row, its version rows, and — after commit (§4.1) — their files; confirmed in the UI; exists so a requirement can be emptied or hard-deleted |
| `importAssetVersion(versionID, assetID, versionNumber, relativePath, sha256, byteCount, originalFileName, mediaKind, pixelWidth?, pixelHeight?)` | `removeVersionRow(versionID)` — row only, file kept (§4.1 orphan rule); asset-row changes restored from snapshot | the journaled half of media import; the file is staged before the transaction and removed on throw (§4.1); `versionNumber` = max + 1 in-transaction (§4.1); refused while the requirement is inactive (§6.3); clears a standing explicit rejection; recompute runs |
| `approveVersion(assetID, versionID)` | **hand-ordered payload-driven inverse** (below) | one transaction: demote the previously approved version to `needs_review` **first**, then approve the target, set status, clear the asset's **own** `is_stale`/`stale_since`/`stale_reason` (§3.5: approving a new version is one of the two staleness-clearing gestures), and when the approved version *changed*, set `is_stale` on dependents' assets per §3.5 — the affected set names every touched asset, so conflict detection sees staleness |
| `rejectVersion(versionID)` / `unrejectVersion(versionID)` | payload-driven prior-status restore / `rejectVersion` | user-gesture vs inverse semantics per §6.3; recompute runs |
| `deleteVersion(versionID)` | **non-invertible** | removes row (in-transaction) and file (post-commit, §4.1); allowed only on `rejected` versions; confirmed in the UI — with `deleteAsset`, the only gestures that destroy media |
| `clearAssetStale(assetID)` | restore flag (snapshot) | the explicit "mark current" (§3.5) |
| `rejectAsset(assetID)` / `unrejectAsset(assetID)` | each other (prior snapshots) | sets / clears `rejected_explicitly` (§6.3 rule 3); precondition: no approved version |
| `setAssetNotes(id, text)` / `setVersionNotes(id, text)` | same op, prior value | |

**The `approveVersion` inverse is hand-ordered, not a generic snapshot
restore.** The partial unique index is enforced per statement, so restoring
the prior approved row before demoting the current one fails; and the
snapshot store's collision precheck models only column-equality uniques and
cannot see a `WHERE status = 'approved'` predicate. The inverse therefore
executes as ordered statements — demote the currently approved version to
`needs_review`, then restore the prior approved version and every touched
asset's prior staleness from snapshots — inside one payload-driven case.
The same blindness is why `RowSnapshotStore.uniqueColumns` gains
`asset_versions` (`[asset_id, version_number]`, `[relative_path]`) but the
partial index is documented as invisible to `wouldCollide` (§7.5).

**The undo/redo/orphan walk, pinned** (this is the sequence executors would
otherwise each invent): import v3 → undo removes the row, `v3.png` stays as
an orphan → a *new* import computes max + 1 = 3 again, finds `v3.png` on
disk, and lands at `v3-2.png` per §4.1's collision rule → redo of the
original import now collides on `UNIQUE(asset_id, version_number)` and is
refused with `.inverseNoLongerApplicable` by the uniqueness precheck — a
graceful refusal, not a corruption. Redo after Clear Orphaned Media removed
the file likewise refuses: redo of an import re-verifies the file's
existence and SHA-256 before re-inserting the row, and reports the missing
file plainly.

### 7.4 Interactions with the existing entity operations

The Phase 1 operations gain requirement-graph awareness; this section is
contract because the built code enumerates child tables explicitly and would
otherwise silently strand or destroy the new rows:

- **`deleteEntity` (hard delete)** is refused while any of the entity's
  requirements has an asset — the FK RESTRICT would otherwise surface as a
  raw constraint failure mid-cascade; the Swift precheck turns it into
  "delete this entity's assets first". The delete's capture list grows to
  snapshot the full requirement graph (requirements, scene links, basis
  rows, dependencies both directions, requirement locks) so
  `restoreEntity`'s inverse restores it; basis rows citing the entity's
  cascaded states/events/appearances are swept in the same transaction
  (§4.3). Tombstoning (the normal path for `ai`/`parser` entities) touches
  no requirement rows — §3.7's inactive rule handles display.
- **`mergeEntities(B → A)`** moves B's requirements to A. A collision on
  `UNIQUE(entity_id, type_id)` or `UNIQUE(entity_id, name_normalized)`
  resolves by the Phase 1 collision-survivor rule (most protected wins,
  losers snapshotted and dropped) — with liveness outranking protection:
  an active row always survives over a `rejected` tombstone regardless of
  source or review rank, matching §7.2's tombstone-collision reading; the
  protection ranking orders rows of equal liveness only — **unless both members of a colliding
  pair have assets, which refuses the merge** with the pair named; the
  remedy depends on tier: combine the pair first (variants, §7.2) or delete
  or reject one side's asset (canonical pairs, which never combine). A
  losing requirement's asset (when only it has
  one) re-points to the surviving requirement. B's `manifest_inclusion` is
  discarded with B (A's stands). Dependency edges are retargeted with
  self-edges removed and the graph re-checked. Everything moved or dropped
  joins the merge payload so `unmerge` stays byte-identical.
- **`splitEntity`** leaves requirements on the source entity — a split is an
  identity correction, and which requirements belong to the new entity is a
  judgment the filmmaker expresses afterwards by re-creating or combining;
  the split sheet says so.
- **`reclassify`** is refused while the entity has canonical requirement
  rows, tombstoned ones included (their template types are kind-bound, and
  a tombstone keeps its `type_id`); delete them first — rejecting does not
  make the row absent. Variant requirements carry across kinds unchanged.
- **`removeSceneEntity` / merges of scenes' facts**: operations that delete
  or re-point states, events, and appearances sweep or re-point matching
  basis rows in the same transaction (§4.3).

### 7.5 Integration surface (the ripple a new SubjectKind pays)

`SubjectKind` gains `requirement`, `requirementScene`, `basis`, `dependency`,
`asset`, `version`, and `templateEntry` — every table the new operations
touch, so affected sets and snapshots stay complete. Each case must be
carried through the engine's known switch points; this list is contract so
no plan discovers one at implementation time:

- `SubjectKind.lockable` gains `requirement` only; `evidenceable` is
  unchanged (requirements justify themselves through basis rows, not
  evidence rows, so the `evidence` CHECK is not widened).
- **`LockField` gains `reason` and `necessity`** (with `displayName`
  strings); requirement lock fields are `name`, `reason`, `necessity`, `*`.
  A lock on a requirement blocks `combineRequirements` (as source or
  target) and `splitRequirement`, both actors, per the Phase 1
  lock-blocks-merge rule. The `locks` table's `field` column has no CHECK,
  so only the `subject_kind` rebuild (§4.2) is schema work.
- `LockPolicy.fields(for:)` and `ProtectionPolicy.parserOwnedFields(of:)`
  gain the `requirement` case (parser-owned: `name`; `tier`/`type_id` are
  immutable columns, §4.3, so they need no field vocabulary).
- The snapshot store's table/primary-key/unique-column maps, its
  `subjectKind(of:)` reverse map, and `RowGraph.tableOrder` gain every new
  table (template rows included — they are snapshot-restored by
  `removeTemplateEntry`'s inverse); `uniqueColumns` gains the §4.3 uniques,
  and the partial approved-version index is documented as invisible to
  `wouldCollide` (§7.3 owns the consequence).
- `InverseApplication`'s `deleteOrder` and prechecks gain the new kinds.
- **`ReviewOperations`**: `target(for:)` gains `requirement`,
  `requirementScene`, and `dependency`, and gains explicit *exclusions* for
  `basis`, `templateEntry`, `asset`, and `version` (they map snapshot tables
  but carry no reviewable PROV surface — without the guard, an accept aimed
  at them is a runtime SQL error); `expand(refs:)` gains the requirement →
  scene-links + dependencies case (§7.2); the `proposedRefs` table list
  gains the three reviewable tables.
- The observation hub's table→`ProjectChange` map gains the new tables
  (areas `.requirements`, `.assets`).
- **`canReplaceScreenplay`** (the Phase 1 §5.5 Replace gate) widens its hard-coded
  PROV-table enumeration to the v4 fact tables, and additionally treats
  *any* asset or version row as protected work: replace destroys the scenes
  the manifest is anchored to, so a project with imported media refuses
  Replace outright.
- `JobManaging` gains `setManifestReport(jobID:_:)` beside the
  extraction-typed `setApplyReport` (the pre-apply zero-counter write, §8.5,
  needs a typed door; the column stays one nullable JSON TEXT).
- `EditOperation.displayName` (compiler-enforced), the `mutate` dispatcher
  (compiler-enforced), `isInvertible` (`deleteAsset`, `deleteVersion`,
  `applyManifestRun` return false), `compoundChildren` (**every new case
  returns `nil`**, `refreshCanonicalRequirements` included — its children
  depend on database state and `compoundChildren` must stay a pure
  function, so the refresh builds its children at the `performGroup` call
  site), and `batchName` for the counted batch names ("Delete 3
  Requirements").
- `RevertOperations`: the summary skip recognizes `.applyManifestRun`
  beside `.applyExtractionRun`, and **`requireNewestRun` widens its task
  filter** — today it hard-codes `task = 'extractScreenplay'`, so without
  this change a manifest run could never be reverted (any completed
  extraction run would read as newer) and a newer manifest run would fail
  to block an extraction revert. The widened gate orders all parentless
  completed run tasks (`extractScreenplay`, `inferAssetManifest`) in one
  journal-sequence ordering; newest-run-only then holds across both run
  types.

### 7.6 Reads

`ProjectReading` grows: `requirements(entityID:)`,
`requirementSummaries(kind:tier:reviewState:includeRejected:)`,
`requirement(id:) -> RequirementDetail` (scene links — stored or derived per
tier — basis rows with their underlying facts' evidence, dependencies both
directions, asset with versions, locks, the derived blocked, active, and
unreviewed-facts flags), `manifestSummary()`, `missingAssets()`,
`requirementTemplate()`, and `orphanedMedia()`. All default reads exclude
rejected rows, same as entities, and every derived read uses §6.4's single
active predicate.

---

## 8. Manifest inference contract (Phase 2b)

### 8.1 Shape: one task, one request, one transaction

`InferManifestTask` is a `StructuredTask` (`taskName =
"inferAssetManifest"`, schema `infer-manifest-v1.schema.json`, prompt
`infer-manifest-v1.md`) run through the existing `StructuredJobRunner` with
a commit closure — a parent job with no children, which the existing
one-active-run-per-project rule already serializes against extraction runs
(the rule is task-agnostic; verified). No chunking and no reconcile pass:
the §8.2 input for a feature-length project is compact structured JSON
(order of tens of KB), and the model sees the whole project at once, which
is exactly what variant grouping needs. The bound is explicit and
deterministic: a `ManifestInputBudget` constant caps the rendered input in
UTF-16 units (the extraction chunker's own unit; the default value is
pinned by the plan and recorded in `ManifestSettings`), measured before any
request is made — an over-budget project fails pre-flight with a message
naming the size, never by silent truncation; a chunked fallback is not
designed until a real project needs one (recorded in §11).

**Run-once gating** (§3.6): the action is offered only while there is no
completed `inferAssetManifest` run **for the current script**; a failed or
cancelled run leaves it available for retry. The existing one-active-run rule
serializes the attempt itself.

Both manifest gates — run-once, and the closure of extraction above — are
scoped to the script for the same reason the extraction latch is (§3.6):
§5.5's Replace deletes `scripts` and `entities` but not `jobs`, and a fresh
manifest run leaves only `proposed` requirements and no assets, so
`canReplaceScreenplay` still permits Replace. Project-scoped gates would then
see the superseded run, while the requirements themselves cascaded away with
the entities — stranding the replaced screenplay unable to be analyzed *or*
manifested. Scoped to the script, Replace installs a screenplay that carries
both of its bootstraps unspent, and neither can stack onto curated data
because Replace refuses once any protected fact, lock, asset, or version
exists (§7.5). The manifest run pins its script already (step 5's
`scriptChangedDuringRun` guard), so the scoping needs no new column.

**One stated runner change.** The commit closure calls `applyManifestRun`,
which — like `ExtractionApplying` — completes the parent job *inside* the
apply transaction, so report, usage, and completion stay atomic. The built
runner then calls `completeJob` again after the closure returns and would
throw on the illegal `completed → completed` transition, surfacing a
committed run as failed. Phase 2 therefore amends `StructuredJobRunner`'s
commit path to skip its own `completeJob` when the closure has already
driven the job to `completed`, with test coverage. Existing behavior is
unaffected: the extraction coordinator never passes a commit closure to the
runner, and the runner's existing test closures do not complete jobs.

Other reuse notes, verified against the built runner: the input text is the
rendered JSON payload wrapped in a `<manifest-input>` delimiter tag (the
`ReconcilePrompt` pattern); `jobs.input_sha256` is the runner's default
digest of that text. Model and effort come from the same Advanced preference
surface as extraction, captured at start into `ManifestSettings`.

### 8.2 Input (built by FilmCore, read-only)

`ManifestInputBuilder` emits, for every eligible entity (§3.3) that
qualifies for a canonical set — and for **every eligible prop-kind entity
regardless of scene count**, with the same full record, since prop
importance is the model's judgment (§3.4):

```text
entities[]      id, kind, name, aliases, description, manifestInclusion,
                appearances[]  (id, sceneOrdinal, role — visible roles only),
                states[]  (id, category, description, startOrdinal, endOrdinal?),
                events[]  (id, sceneOrdinal, description),
                existingRequirements[]  (id, tier, name, necessity,
                                         protected, locked, rejected,
                                         sceneOrdinals[])
scenes[]        ordinal, heading, intExt, locationText, timeOfDay, synopsis
template[]      the project's template entries: id, entityKind, code,
                displayName, isEnabled — context for the model, and digest
                coverage for apply (§8.4 step 0)
borderline[]    non-qualifying non-prop entities (1 scene or inclusion
                'never'), compact: id, kind, name, appearances[] (id,
                sceneOrdinal, role) — the pool inclusion suggestions draw
                from; props never appear here, they ride in entities[]
```

Appearance rows carry their ids so proposals can cite them as basis
(§8.3). Scene synopses are context only — they are not a citable basis
kind, since a synopsis is itself derived prose rather than an anchored
fact. Existing requirements ride along with `protected`/`locked`/`rejected`
flags for the same reason reconcile's canonical entities do: the model must
propose around what it may not touch, and apply enforces it regardless.

### 8.3 Output schema (`infer-manifest-v1.schema.json`)

Structured-Outputs-safe like the Phase 1 schemas: `additionalProperties:
false` everywhere, `schemaVersion: const 1`, bounded arrays, no `maxLength`
(lengths in semantic validation), probed by the opt-in schema compatibility
test before use.

```text
variants[]  (max 1024)
  entityId              string  — echoed from input (ids are ours, unlike
                                  extraction's surface-form names)
  name                  string  — 'Office Outfit', never entity-prefixed
  reason                string  — one or two sentences
  sceneOrdinals[]       int, min 1 item
  basisStateIds[]       string  — input state ids this variant rests on
  basisEventIds[]       string
  basisAppearanceIds[]  string
  confidence            number 0..1

importantProps[]  (max 512)                    -- §3.4: the AI's prop judgment
  entityId              string  — a prop-kind entity from the input
  reason                string  — why this prop needs a dedicated reference
  basisStateIds[]       string
  basisEventIds[]       string
  basisAppearanceIds[]  string
  confidence            number 0..1

inclusionSuggestions[]  (max 256)              -- non-prop kinds only
  entityId, suggestion ('promote' | 'suppress'), reason, confidence
```

Semantic validation (an `InferManifestValidator`, versioned like its
Phase 1 peers): every variant's `entityId` resolves to `entities[]` —
never to `borderline[]`, and never to an entity whose input record carries
`manifestInclusion = 'never'` (apply re-checks this in-transaction, §8.4,
in case the override changed mid-run); every
`sceneOrdinal` is a scene where that entity appears **in a visible role**
(§3.3 — a wardrobe variant cannot claim a scene where the character is only
discussed); every basis id resolves to that entity's input rows, cited
states' scene ranges must overlap at least one of the variant's scenes, and
cited appearances must lie in them (events are entity-scoped only — a
scene-14 injury legitimately justifies a scenes-15-20 variant); variant
names non-empty, control-character-free, unique per entity after
`EntityNormalization` **within the proposal** (collisions with existing
rows are an apply concern, §8.4); confidence finite in 0…1; `importantProps` entries must name prop-kind
entities, at most once each, with basis ids resolving as for variants,
never an entity whose input record carries `manifestInclusion = 'never'`,
and never a kind whose input `template[]` holds no enabled `reference`
entry (apply never resurrects a disabled entry);
`promote` suggestions only for borderline entities, `suppress` only for
qualifying ones, and neither for props (which have their own channel).
Dangling references reject the result, exactly as
`dangling_entity_reference` does today.

### 8.4 Apply rules (FilmCore, actor `.ai(jobID)`)

`applyManifestRun(_ proposal: ManifestProposal, runJobID:, usage:)` joins
`ExtractionApplying`'s pattern — one transaction, parent job in
`committing`, per-change `SAVEPOINT`s, one journal row per change plus a
summary row, skip-and-count on policy errors, parent completed in the same
transaction (§8.1):

0. **The input digest is re-verified inside the apply transaction.**
   Validation (§8.3) ran against the input snapshot, but the filmmaker can
   edit while the model thinks — delete a cited state, reject an entity,
   flip an override, disable a template entry — and re-checking each
   semantic predicate piecemeal would inevitably miss one. Instead, apply
   **rebuilds the rendered input** (`ManifestInputBuilder` is
   deterministic and reads only canonical data, all inside this
   transaction) and compares its digest with the run's recorded
   `jobs.input_sha256`. Equal ⟹ every predicate the validator checked
   still holds, references included — nothing can dangle. Different ⟹
   throw `.manifestInputChangedDuringRun`: the run fails cleanly with
   nothing applied ("the project changed while the manifest was being
   inferred — run it again"), and run-once gating (§8.1) permits the
   retry. The script-hash guard covers the screenplay; this guard covers
   everything else, which is why the steps below need no per-reference
   existence checks.

1. Map each `importantProps` entry by `(entity_id, type_id)` — the
   enabled `reference` template entry from the input (the validator has
   already refused entries for `'never'` props and for kinds whose
   reference entry is disabled, §8.3, and the digest guard froze that
   state). A match to a rejected requirement → `skippedRejected` (the
   tombstone that stops re-proposal); to a wholly replaceable
   `ai/proposed` row → update in place; to anything else →
   `skippedExisting`; a §5.2-style name collision with an existing
   requirement of the entity → `skippedExisting` (never a raw error); no
   match → create the canonical-tier requirement (`ai/proposed`, §3.4)
   with its basis rows — scene links stay derived, as for every canonical
   requirement (§5.2).
2. Map each variant by `(entity_id, name_normalized)` — the unique spans
   tiers, so every match case is enumerated (the `'never'` override binds
   every proposal channel at validation time, §8.3, and the digest guard
   keeps it binding at apply time):
   - match to a **rejected** requirement → `skippedRejected`;
   - match to a **wholly replaceable** variant (the requirement and every
     owned scene-link/dependency row still `ai/proposed`, no asset row —
     importing accepts implicitly, §7.3, so an asset implies accepted;
     basis rows carry no review state and follow their requirement, §3.7)
     → update in place, reconciling children by stable keys (scene id;
     basis subject; depends-on id);
   - match to **anything else** — an accepted or human row, a canonical
     (`parser`) row of the same normalized name, or a proposed requirement
     with any reviewed or human child → skip untouched, counted
     `skippedExisting` (never an update, never a cross-tier rewrite);
   - no match → create the requirement (`ai/proposed`) with its scene
     links, basis rows, and §3.5-seeded dependencies (tombstoned
     dependencies respected), as one change.
3. Because inference is run-once (§3.6), the update and replace branches
   above are defensive only — on the one real run, no prior `ai/proposed`
   requirement rows exist to match. A retry after a failed run finds
   nothing applied (apply is one transaction) and behaves as a first run.
4. `inclusionSuggestions` are persisted in the report (§8.5) and surfaced
   in review as advisory rows with one-click `setManifestInclusion`; never
   applied by the run. Dismissal is simply not acting; the report is the
   immutable record and the newest run's suggestions are the ones shown.
5. Variant scene links land as scene **ids** resolved from ordinals inside the
   transaction against the run's pinned script (`scriptChangedDuringRun`
   guard, same as extraction; import/replace refusal while a run is live
   already covers manifest runs via the shared job-state rule).
6. Journal rows carry the run's `job_id`; the summary row is
   `.applyManifestRun(ManifestApplyReport)`. Revert uses the existing
   walk — newest-run-only, human-edit conflicts, transitive skips — with
   the two §7.5 changes (widened task gate, second summary-skip case). The
   undo stack clears on apply and revert, as for extraction.

### 8.5 `ManifestApplyReport`

A FilmCore type (FilmCore may not import FilmBrain), stored in the run's
`jobs.apply_report` through the new typed door (§7.5): `created`,
`skippedExisting`, `skippedRejected`,
`skippedProtected`, `skippedLocked` (no dangling-reference counter exists:
§8.4 step 0's digest guard makes a dangling reference unrepresentable —
the run fails whole instead), `suggestions:
[ManifestInclusionSuggestion]` (`entityID`, `direction` (`promote |
suppress`), `reason`, `confidence` — persisted in full so the advisory UI
survives reopen), `durationMs`, `settings: ManifestSettings` (`model?`,
`effort?`, `inputBudgetUTF16` — the §8.1 budget captured at run start, so
the recorded run is reproducible against the settings it actually ran
with). Written with zero counters before apply through
`setManifestReport` (§7.5); the post-apply rewrite happens **inside the
apply transaction** through an internal `in db:` primitive, the way
extraction's applier writes `apply_report` in its completion UPDATE — the
public setter opens its own transaction and refuses completed jobs, so it
cannot be the after-write. `.applyManifestRun` is non-invertible with
`compoundChildren = nil`, exactly like `.applyExtractionRun`; the two report
types stay key-disjoint and task-gated (§4.4).

### 8.6 Correction UI

Validated requirements appear directly in Manifest as active rows. The UI
keeps the actions that change a result—Edit, Reject/Restore, combine, split,
necessity, scene links—and keeps basis evidence with jump-to-scene
highlighting plus advisory inclusion suggestions. It does not present a
Proposed/Accepted queue, pending-review banner, or Accept All chore.

---

## 9. Privacy and disclosure

Manifest inference sends **derived structured data, not the screenplay
text**: entity names, aliases, descriptions, state and event descriptions,
scene headings and synopses. The claim is stated precisely, not
over-sold: those descriptions and synopses were distilled *from* the
screenplay and may echo its language — what is never sent is the
screenplay's own text. It is still the operator's creative material, so the
run keeps the confirm-before-send discipline.

**First run per project, when no disclosure has been acknowledged** — a
project can legitimately reach its first manifest run without ever running
extraction (bare import + Build + inference), so when
`projects.disclosure_acknowledged_at` is nil the run shows the full
acknowledgement (stored on acceptance, shared with extraction). Copy,
verbatim:

> Building the manifest sends this project's structured breakdown — entity
> names, descriptions, states, and scene synopses, not the screenplay
> text — to Codex through your own Codex account. Codex may include your
> global Codex instructions and the descriptions of your installed Codex
> skills or plugins in the same request; AI Film Camp does not read or
> store those. Nothing is sent until you choose Continue.

**Every manifest run** (compact confirm sheet):

> Building the manifest sends this project's structured breakdown — entity
> names, descriptions, states, and scene synopses, not the screenplay
> text — to Codex through your own Codex account, in about 1 request.
> This runs once; afterward you edit the manifest directly.

Media files never leave the bundle in Phase 2 — no image is sent to any
engine — and imported media is validated as untrusted input (§4.1).

---

## 10. Testing strategy

- **Migration**: v3 fixture bundle (synthesized in-test by SQL) → open → v4:
  unchanged row counts for every carried table, template rows seeded,
  `manifest_inclusion` defaulted, widened `locks` CHECK admits and
  round-trips a `requirement` lock, clean `PRAGMA foreign_key_check`; plus
  the fresh-create path seeding an identical template.
- **Deterministic manifest**: the 2+ rule over role/mention matrices;
  props excluded from Build except under `'always'` (§3.4);
  promote/suppress overrides; `refreshCanonicalRequirements` idempotence
  (run twice, byte-identical tables; no-op refresh journals nothing);
  tombstone respected; late-canonical dependency seeding (§3.5); drift
  badges (§5.3) as read-layer tests.
- **Editing operations**: every §7 op gets the Phase 1 battery — apply +
  inverse round-trip on table snapshots, lock/protection/rejection matrix
  (actor × lock × op), combine collision survivor rule, combine with
  filled participants (version renumbering, the §7.2 asset-survivor rule
  including a target with no asset, flag retention, source tombstone),
  split's basis footprint assignment (move / stay / copy-on-overlap, with
  the inverse deleting copies), Build's cross-tier name-collision skip
  (§5.2), combine/split round trip, journal payload sufficiency
  (restore after delete), an orphaned-basis-row query after every
  state/event/appearance delete and merge **including the cascade paths**,
  and the approve-version staleness fan-out with its hand-ordered inverse
  restoring prior staleness byte-identically.
- **Entity-op interactions (§7.4)**: hard-delete refusal with assets;
  restore-after-delete including the requirement graph; merge with
  colliding requirements (survivor, asset re-point, both-assets refusal);
  reclassify refusal with canonical requirements.
- **Media**: import staging atomicity (throw after copy leaves no row and no
  file; throw after insert removes the staged file), collision suffixing,
  magic-byte refusal of mislabeled files, the §7.3 undo/redo/orphan walk
  verbatim (including the refused redo after re-import and after Clear
  Orphaned Media), rows-first deletion ordering, and a bundle move/reopen
  test asserting every version resolves (the Phase 0 Finder-move discipline
  extended to media).
- **State machine**: §6.3's recompute rule and transition table as an
  exhaustive table test; the approved-version invariant (§6.1, including
  the deprecated-with-approved case) asserted after every asset op; the
  rejection-survives-deprecation walk (`rejectAsset` → requirement
  `not_needed` → restored → still `rejected`).
- **Containment**: a symlinked directory — and a symlinked final leaf —
  planted under `assets/` makes import, preview/hash reads, Reveal, and
  deletion refuse (§4.1's realpath and no-follow rules), with the refusal
  message asserted and a check-then-swap sequence covered; the lexical
  `RelativeProjectPath` checks alone must fail these tests.
- **Bootstrap ordering (§3.6)**: a second `extractScreenplay` run is refused
  once one has applied; a never-analyzed project is refused analysis after a
  completed manifest run; a second manifest run is refused once one has
  applied; a manifest run is refused while an extraction run is non-terminal
  or paused; and **after Replace installs a new screenplay all three gates
  open again** — the script-scoped rule, which a project-scoped one would
  fail by stranding the replacement.
- **Inference**: recorded single-request runs through the generic runner
  (including the amended commit path completing exactly once); validator
  cases (dangling ids, mentioned-only scenes, non-overlapping state basis,
  duplicate names, promote on a qualifying entity, a non-prop entity in
  `importantProps`, a `'never'` entity in either proposal channel, a prop
  whose kind has no enabled reference entry); apply cases (the full §8.4
  match enumeration including `skippedExisting` on a canonical-name
  collision, prop proposals onto tombstones, rejected
  tombstone, script-changed guard, run-once gating with retry-after-failure,
  and the §8.4 step-0 digest guard: a state deleted, an entity rejected, an
  override flipped, and a template entry disabled between validation and
  apply must each fail the run whole with `.manifestInputChangedDuringRun`
  and nothing applied — no orphaned basis row is representable — while a
  byte-identical rebuild applies cleanly); revert of a manifest run,
  including the human-edit skip and the widened cross-task newest-run rule.
- **Live gate** stays opt-in (`FILMCAMP_RUN_LIVE_CODEX=1`) with per-run
  operator approval; **acceptance** is the operator building and reviewing
  a manifest on their feature screenplay, with the review burden (counts
  accepted / edited / rejected, from the report and journal) recorded in
  `docs/IMPLEMENTATION_NOTES.md`. There is no manifest answer key in
  Phase 2: the extraction answer-key machinery scores extraction, and a
  manifest ground truth would have to be hand-authored, which Phase 1
  decision §14.4 rules out; the recorded review burden is the honest
  substitute until a reviewed manifest exists to export from. The
  `scripts/eval-inputs.txt` manifest gains the inference schema, prompt,
  validator, and input-builder sources only if the eval gate is extended to
  manifest runs — a planning-pass decision, not assumed here.

---

## 11. Non-goals for Phase 2 (and the seams left open)

Not in Phase 2: prompt generation and the per-requirement workshop UX
(Phase 3 — but it lands on §4/§6/§7's contract, which is why those are
specified to asset/version depth now); readiness dashboards and
next-action intelligence (Phase 4 — `missingAssets()` and the derived
blocked flag are its inputs); shot planning (a roadmap non-goal); generation
packages and export (Phase 5 — approved versions are its references);
screenplay change propagation, shared assets across requirements, and
transitive staleness (Phase 6); video/audio reference media; integrated
image generation providers (Phase 3 decides; the model here never depends on
one); scene-scoped or style-bible requirements not anchored to an entity;
chunked manifest inference; OCR, cloud, sandboxing.

Seams deliberately left where later phases expect them: `assets.status`
admits `prompt_ready`/`in_progress` unused; `media_kind` is an enum of one;
`asset_dependencies` is requirement-to-requirement so shared-asset reuse can
arrive as a fulfillment indirection without schema surgery; basis rows give
Phase 6's "why does this exist / what does this rewrite affect" a starting
join.

---

## 12. Research inputs

Recorded 2026-08-21, verified against source in this worktree (no external
research was required for this phase; the binding inputs are the built
Phase 1 surface). The review passes re-verified these line-by-line and
their corrections are folded into §4, §7, and §8:

- **Schema/storage**: migrations `"v1"`–`"v3"` in `ProjectMigrator` with DDL
  in `SchemaV2`/`SchemaV3` raw-SQL enums; `FilmCoreVersion.bundleSchema = 3`;
  the PROV block as quoted in §4.3; `project_assets` is screenplay-only
  (`ProjectAsset.Kind` has one case) with the atomic stage-then-insert import
  and `-2`/`-3` collision rule in `ProjectSession`; `assets/` and `exports/`
  are created by `ProjectBundleLayout` and referenced nowhere else;
  `RelativeProjectPath` validates and resolves every bundle path. SQLite
  behaviors verified empirically on the shipped library: `ALTER TABLE ADD
  COLUMN` with constant default + CHECK; NULL-distinct composite UNIQUE;
  cross-column column CHECK; table constraints must follow the last column
  (the §4.3 constraint placement); per-statement partial-unique-index
  enforcement (the §7.3 hand-ordered inverse); immediate RESTRICT
  enforcement inside a cascade (the §7.4 prechecks).
- **Mutation engine**: `EditOperation`'s full case list with kind-stamped
  entity cases; `MutationEffect`/`EditPrimitives` three-level shape with the
  no-transaction rule test-enforced over `Editing/*.swift`;
  `ProtectionPolicy` (locked → parser-owned → protected refusal order) and
  `LockPolicy` as the only lock reader; `LockField`'s current case list
  (hence §7.5's additions); `InverseApplication`'s liveness and
  human-conflict rules; the snapshot store's table-order/primary-key/
  unique-column maps and their column-equality-only collision model;
  `ReviewOperations`' subject target map and entity-only `expand`;
  `ExtractionApplier`'s savepoint-per-change skip-and-count apply with
  in-transaction parent completion; `RevertOperations`' newest-run gate
  hard-coded to `extractScreenplay` (hence §7.5's widening);
  `canReplaceScreenplay`'s hard-coded PROV table list (hence §7.5's
  widening); `Job.applyReport`'s shape-gated decode (hence §4.4's task
  gating). §7.4 and §7.5 are drawn from these, file by file.
- **FilmBrain**: `StructuredTask` + `StructuredJobRunner` (commit closure
  path calls `completeJob` after the closure — hence §8.1's stated runner
  change; the extraction coordinator bypasses the closure entirely);
  the one-active-run rule and the import/replace refusal are job-state
  based and task-agnostic; `extract-chunk-v1` / `reconcile-entities-v1`
  schemas and prompts contain no importance, prominence, or set-dressing
  signal of any kind (§3.4's premise); `ReconcileInputBuilder` as the
  canonical-state-to-model input pattern §8.2 mirrors;
  `ApplyReport`/`ExtractionSettings` live in FilmCore, are
  extraction-shaped, and `setApplyReport` is extraction-typed — hence the
  parallel `ManifestApplyReport` and its typed door.

---

## 13. Roadmap deltas (for product-owner acceptance)

1. **`source = 'parser'` is read as "deterministic app pipeline"** and used
   for template-computed canonical requirements (§3.7), rather than widening
   `FactSource` with a fourth value that would fork the shared PROV CHECK.
2. **Stale is an orthogonal flag, not an asset state** (§6.2), because
   OVERVIEW's pinned asset-state vocabulary has no Stale and this contract
   does not invent status strings. The roadmap's "marks every derived asset
   stale" is satisfied by the flag.
3. **Prop importance is the AI's judgment over structured data, not an
   extracted signal and not a computed rule** (§3.4, owner decision
   2026-08-21). The roadmap's "the AI should distinguish" is met by the
   manifest job proposing prop requirements directly, from the structured
   breakdown — not by re-reading the screenplay, which the one-run rule
   forecloses. Consequence, accepted: props enter the manifest only after
   the inference pass, a manual add, or an `'always'` override, so the 2a
   deterministic manifest covers every kind except props.
4. **Manifest inference sends structured breakdown data, not screenplay
   text** (§3.6, §9). The roadmap does not specify the payload; this is the
   privacy-preserving reading consistent with "consume what extraction
   produced".
5. **Manifest inference is run-once** (§3.6, owner decision 2026-08-21):
   one completed applied run per project, retry only after failure, the
   same bootstrap posture as extraction. The §8.4 match enumeration is kept
   as defensive apply behavior, not as re-run support.
6. **One requirement ↔ at most one asset in the MVP** (§3.1); shared-asset
   reuse deferred to Phase 6 with the seam named.
7. **Canonical scene links are derived, variant links stored** (§5.2) —
   a refinement of "requirement-to-scene links", not a reduction: every
   requirement still answers "required by" with scenes.
8. **The 2+ rule counts `speaking`/`present`/`setting`/`used` and excludes
   `mentioned`** (§3.3), and variant scene claims are bounded by the same
   visible-role set (§8.3) — the roadmap says "appears in", which this
   makes precise.
9. **Requirement review verbs reuse the existing review model** —
   approve = accept, remove = reject tombstone (§7.1) — per Phase 1
   decision §14.1. That decision also instructs that `docs/ROADMAP.md`'s
   Requirement Review section restate the proposed-facts rule when Phase 2
   is planned; the first Phase 2 plan carries that one-paragraph roadmap
   edit, so this contract does not amend the intent documents itself.
10. **Media deletion is non-invertible and explicit** (§7.3); undoing an
    import orphans the file instead of deleting it. Journal snapshots hold
    rows, never media bytes.
11. **`splitRequirement` and `combineRequirements` are variant-tier only**
    (§7.2): canonical requirements have derived scene links, so there is
    nothing to split, and canonical duplicates arise only through entity
    merges, which resolve them by the §7.4 collision rule; the roadmap's
    unqualified "split"/"combine" are narrowed accordingly. Within the
    variant tier, combine is unrestricted — filled duplicates merge version
    histories, and cross-entity sources are permitted (§7.2). A split
    leaves the asset on the source.
12. **Combining requirements tombstones the merged-away source** rather
    than hard-deleting it (§7.2), so an inference run cannot resurrect the
    duplicate — the requirement-world analog of Phase 1's merge-preserves-
    the-name-as-alias rule.
13. **Importing media into a proposed requirement accepts it implicitly**
    (§7.3), the same gesture logic as Phase 1's "Edit accepts implicitly" —
    which is also what keeps §8.4's defensive replacement branches from
    ever colliding with an asset.
14. **Extraction closes at its first applied run** (§3.6, owner
    2026-08-21): analysis runs once per screenplay and a new run means a
    new project, so Re-analyze does not exist. This **supersedes** the
    earlier manifest-completion boundary — see §14.9's revision. A manifest
    run is still refused while an extraction run is non-terminal or paused.

---

## 14. Decisions (product owner, 2026-08-21)

1. **Prop importance — REVERSED from the recommendation.** The draft
   proposed a computed 2+-scene default with AI advisories; the owner chose
   **"trust the AI to judge"**. §3.4 now has the manifest job propose prop
   requirements directly from the structured breakdown, reviewed like every
   other AI fact, with the `manifest_inclusion` override in both
   directions. The accepted boundary: the judgment reads the structured
   data, never the screenplay text, and props appear in the manifest only
   after the inference pass, a manual add, or an `'always'` override.
2. **Manifest re-run — DECLINED ("run once is fine").** Manifest inference
   is one completed run per project, retryable only after failure (§3.6,
   §8.1); afterward the filmmaker edits the manifest directly. The re-run
   confirm sheet and the stale-proposal replacement rule were removed from
   the contract accordingly.
3. **Accepted**: `source = 'parser'` reused for deterministic
   template-computed rows (§13.1); no fourth `FactSource` value.
4. **Accepted**: 1:1 requirement/asset for the MVP (§13.6).
5. **Accepted**: keep both `assets` and `project_assets` table names,
   documented; no rename rebuild.
6. **Accepted**: MVP media kinds are still images only
   (png/jpeg/webp/heic/tiff, §4.1).
7. **Accepted**: no manifest answer key in Phase 2; acceptance is the
   owner's own manual review of a manifest built on their feature
   screenplay, with the review burden recorded (§10).
8. **Revised 2026-08-29**: the §3.2 default character template is Face
   Closeup plus Headless Full Body — Front + Back. The earlier four-view
   default is superseded by Plan 029; location and prop-family defaults are
   unchanged.
9. **Revised 2026-08-21 — extraction closes at its first applied run, not
   at manifest completion.** The decision first drew the boundary at
   manifest completion ("we have a 'one run, then the app owns it'
   positioning for imports"), keeping Phase 1's deliberate Re-analyze as a
   guarded safety net until then. Four audit rounds read the headline rule
   and the surviving Re-analyze as a contradiction; asked to settle it, the
   owner chose the strict latch: **"There is no such thing as a 2nd run. If
   you do a new run, it makes a new project."** So Re-analyze is removed
   rather than deferred, FilmCore refuses a second applied
   `extractScreenplay` run per screenplay (§3.6), and the recovery path for
   a bad run is a new project — or, while nothing has been curated, §5.5's
   Replace. This strictly simplifies the contract: it retires §8.5 rule
   4a's reachability, cross-run chunk reuse, and Plan 012's extraction
   basis sweep with its live re-score.
