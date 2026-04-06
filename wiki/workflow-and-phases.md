# Workflow And Phases

## Purpose

This page documents the project-development workflow encoded in the repo.

## Phase Model

The workflow phase list currently includes:

- `start-mode`
- `source-import`
- `concept`
- `title-logline`
- `film-length`
- `characters`
- `outline`
- `script-breakdown`
- `screenplay`
- `assets`
- `shot-prompts`

These phases are defined in `lib/types/development.ts`.

## Start Modes

Projects can begin in one of two modes:

- `blank`
- `import`

The import path expects a source document plus extracted context, while the blank path skips that dependency.

## Completion Logic

The workflow status is derived rather than manually tracked in one place. `lib/development.ts` calculates completion from the presence of:

- concept statement or concept directions
- title, logline, and length data
- character and location data
- outline and script-breakdown items
- screenplay text
- uploaded or generated assets
- prompt-shot coverage

## Visibility Model

Each phase also has a visibility setting:

- `private`
- `published`

By default, the earliest setup phases stay private while most downstream creative phases are treated as publishable.

## Practical Interpretation

The repo is not just storing finished films. It is modeling the intermediate development process for an AI-film project, from concept through screenplay, assets, and shot prompts.

## Why This Matters

Future work in this repo should respect that the product’s value proposition is partly the structured workflow itself, not only the final media output. If the tooling blocker shifts later, this phase model is likely to remain one of the most durable product assets.
