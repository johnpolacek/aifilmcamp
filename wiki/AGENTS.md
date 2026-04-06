# `aifilmcamp/wiki` Agent Guide

## Purpose

This wiki is the deep documentation layer for `/Users/johnpolacek/Projects/aifilmcamp`.

Use it for durable repo-specific knowledge such as:

- product shape and route structure
- project-development workflow and phase model
- storage, scene, and composition pipeline notes
- current operating posture, including blockers
- implementation details future work in this repo will need

Keep this wiki concise, persistent, and readable in plain markdown.

## What Belongs Here

- how the app is structured
- how projects, scenes, and supporting media flow through the system
- how the separate video-composer service fits into the repo
- current project posture and constraints that affect future work
- durable notes grounded in inspected code, config, or repo-local docs

## What Does Not Belong Here

- high-level cross-project summaries
- personal hub navigation
- duplicated summary content that belongs in `/Users/johnpolacek/Wiki`
- copied boilerplate README content
- speculative product claims not supported by inspected evidence
- temporary scratch notes or one-off planning fragments

## Boundary With `/Users/johnpolacek/Wiki`

This repo wiki is the source of truth for deep `aifilmcamp` knowledge.

`/Users/johnpolacek/Wiki` should hold only the high-level project summary, hub navigation, and cross-project context. When adding or updating durable deep docs here, update the hub summary only when the project's purpose, status, canonical wiki location, or current operating posture changes in a way the hub should reflect.

Do not maintain the same detailed implementation notes in both places.

## Core Files

### `index.md`

- read this first when answering from the project wiki
- keep it as the running catalog of durable project-wiki pages
- add new durable pages when they become part of the maintained wiki

### `log.md`

- treat it as append-only
- use headings like `## [YYYY-MM-DD] type | title`
- record bootstrap, ingest, lint, and meaningful update activity

## Canonical Operations

### `bootstrap`

1. Inspect the repo before writing.
2. Create only the smallest useful wiki structure justified by the repo.
3. Ground every page in inspected code, configuration, or docs.
4. Update `index.md` and `log.md` in the same session.

### `ingest`

1. Read the relevant repo files first.
2. Add or update one durable note per clear topic when practical.
3. Link the new note from `index.md`.
4. Append a concise `log.md` entry.

### `query`

1. Read `index.md` first.
2. Answer from the project wiki before re-inspecting the repo when possible.
3. If the answer creates durable repo knowledge, file it back into the wiki.

### `lint`

Check for:

- stale workflow or pipeline notes
- contradictions with the current repo
- orphan pages missing from `index.md`
- duplicated deep notes that should be merged
- missing hub-summary synchronization when project posture changes

Prefer lightweight fixes over large reorganizations.

## Writing Style

- plain markdown
- relative links where practical
- short sections
- concrete statements
- explicit uncertainty when evidence is thin

## Safety Defaults

- do not invent undocumented behavior
- do not copy large repo files into the wiki without synthesis
- do not create a large taxonomy unless the repo clearly earns it
- keep the wiki useful for future maintainers working inside this repo
