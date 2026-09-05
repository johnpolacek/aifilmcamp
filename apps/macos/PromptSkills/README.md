# Prompt Skills

Vendored, third-party prompt-authoring skills. These are **app payload, not app code**:
[Phase 5](../docs/ROADMAP.md#phase-5--generation-prompt-engine) specifies that Film Camp
assembles context and a *pluggable skill* writes the model-specific prompt in a harness
session. This directory holds the default skill for the first target profile.

```text
Film Camp assembles      scene text, canonical entities, approved references,
                         continuity state, style bible, target profile
        ↓
Prompt skill writes      the model-specific prompt, in a harness session
        ↓
Film Camp packages       prompt + metadata + reference images
```

Nothing here is imported by FilmCore or FilmBrain. It is Markdown, JSON, and standalone
Python that a harness session reads. The filmmaker can supply their own skill; swapping it
must not require an app change.

---

## Contents

| Directory | Profile | Status |
|---|---|---|
| `higgsfield/` | Seedance 2.5 (`higgsfield-seedance-2-5`) | Default |

---

## Provenance

| | |
|---|---|
| Upstream | <https://github.com/OSideMedia/higgsfield-ai-prompt-skill> |
| Commit | `c802845d4514179e9a8834c4663919a492840115` |
| Release | v3.32.0 |
| Vendored | 2026-08-21 |
| License | MIT — © 2026 O-Side Media (`higgsfield/LICENSE`) |

The upstream directory layout is preserved verbatim, because the skills address each other
through relative paths (`../higgsfield-seedance/SKILL.md`, `../../specs/model-specs.json`).
Do not flatten or rename directories inside `higgsfield/`.

**Vendored content is not edited.** Film Camp adaptations belong in the context Film Camp
assembles, or in a Film Camp-authored skill that references these — never in a patch here,
which would be silently lost on the next upstream sync.

---

## What was vendored, and what was not

Upstream ships 30 skills covering film, advertising, social content, and its own studio
workflow. The film-relevant closure of `higgsfield-seedance-2-5` was taken: **20 skills**,
plus the model specs, templates, and the preflight linter.

Kept, by role:

- **Seedance family** — `higgsfield-seedance-2-5` (the entry point), `higgsfield-seedance`
  (2.0 director; owns the shared engine rules and prompt-craft laws that 2.5 inherits),
  `higgsfield-seedance-vfx`
- **Performance and character** — `higgsfield-acting`, `higgsfield-facs`,
  `higgsfield-character-design`, `higgsfield-soul`
- **Craft** — `higgsfield-camera`, `higgsfield-cinema`, `higgsfield-prompt`,
  `higgsfield-style`, `higgsfield-motion`, `higgsfield-audio`, `higgsfield-moodboard`,
  `higgsfield-shotlist-director`
- **Support** — `higgsfield-models`, `higgsfield-pipeline`, `higgsfield-troubleshoot`,
  `higgsfield-gpt-image-2` (reference-sheet generation), `shared`

Excluded as out of scope: the advertising and social-content skills
(`higgsfield-marketing-studio`, `higgsfield-content-factory`, `higgsfield-canvas`,
`higgsfield-workspaces`, `higgsfield-apps`, `higgsfield-image-shots`,
`higgsfield-mixed-media`, `higgsfield-motion-design`, `higgsfield-vibe-motion`,
`higgsfield-recipes`, `higgsfield-stack`), upstream's own studio-workflow skills
(`higgsfield-assist`, `higgsfield-recall`), and upstream's repo scaffolding — tests, evals,
CI, PDF fonts, generation ledger, and historical `models_explore` snapshots.

### Known dangling references

Excluding those skills leaves five "see also" pointers unresolved. All are optional
cross-references in prose; none is on a path the Seedance 2.5 skill needs to author a prompt.

| Reference | From |
|---|---|
| `../higgsfield-assist/SKILL.md` | `higgsfield-seedance/SKILL.md` (×3) |
| `../higgsfield-recall/SKILL.md` | `higgsfield-seedance/HELL-GRIND.md` |
| `../higgsfield-marketing-studio/SKILL.md` | `higgsfield-gpt-image-2/reference-sheet-workflow.md` |
| `../higgsfield-marketing-studio/cross-surface-workflow.md` | `higgsfield-gpt-image-2/SKILL.md` |
| `../../specs/model-specs.json` | `higgsfield-seedance-vfx/references/first-frame.md` |

The last one is an upstream path bug, not a vendoring artifact — the file sits one directory
deeper than its siblings and needs `../../../`. It is broken upstream too, and is left
unpatched so this tree stays a clean copy.

---

## Preflight linter

Upstream ships a structural validator. It is pure stdlib, needs no install, and reads its
enums from `higgsfield/specs/model-specs.json`:

```bash
python3 PromptSkills/higgsfield/scripts/seedance_lint.py --preflight --model seedance_2_5 "<prompt>"
```

It checks duration, resolution, and reference-budget violations against the model specs,
flags provider-side content-filter false positives, and recalls prior failure modes.

This is a natural structural gate for Phase 5: the project rule is that **AI output is
untrusted — validate it structurally and semantically, then commit in one transaction**, and
a prompt returned by the harness is exactly that kind of output. Set `HF_DB_DIR` to redirect
the linter's memory store if per-production memory is ever wanted.

---

## Why this skill shapes the Phase 5 context contract

The skill's input grammar is more specific than "here is a scene," and Film Camp already owns
the data it wants. Two requirements reach upstream into the requirement and asset model:

1. **Per-reference role and fidelity.** Every reference needs an explicit role statement
   (`@Image 1 defines Sarah's identity`), an exclusion (`do not use the background`), and a
   fidelity grade — full-preserve, partial-preserve, attribute-transfer, or loose-guide. The
   skill's canonical failure is the vague bulk statement (`@Images 1–4 define four
   characters`). Film Camp's manifest knows which approved asset is an identity, a look, a
   location, or a prop, so the assembled context can emit that mapping mechanically and
   retire the error class.
2. **Character fields.** The skill's character formula has seven slots — role, skin, facial
   detail, eyes, hair, clothing, build — and **forbids writing age**.

Reference ordering also matters: canonical identities first, then looks, then locations and
props, within the 30-image budget.

---

## Updating

```bash
git clone --depth 1 https://github.com/OSideMedia/higgsfield-ai-prompt-skill.git
```

Re-copy the file set above, update the commit and release in **Provenance**, re-run the
linter smoke test, and re-check dangling references. Record the upstream version in the plan
or pull request that consumes the change, matching the convention in
[REFERENCE_PROJECTS.md](../docs/REFERENCE_PROJECTS.md).
