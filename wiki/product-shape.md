# AI Film Camp Product Shape

## Summary

AI Film Camp currently looks like a hybrid product: part community site, part project workspace for developing AI film projects, and part tooling surface for stitching and exporting media.

## Public App Surface

The App Router currently exposes:

- `/` for the public landing page
- `/about`, `/films`, `/projects`, and `/resources` for public content and discovery
- `/tools/aifilmstitcher` and `/tools/aivideostitcher` for tool-facing entry points
- `/{username}/{projectSlug}` for public project pages

## Authenticated Workspace Surface

The dashboard area includes:

- `/dashboard`
- `/dashboard/profile`
- `/dashboard/projects`

These routes align with the repo’s project, profile, and publishing workflows rather than a simple content site.

## Major Product Areas

### Community and discovery

The home view and public sections present AI Film Camp as a community for AI filmmakers rather than only a production tool.

### Project development workspace

The repo includes forms, editors, and workflow utilities for:

- project setup
- screenplay editing
- scene editing
- shot and prompt management
- export and publishing behavior

### Tooling surfaces

The codebase includes dedicated tooling for:

- AI video stitching
- export
- audio tracks and waveform handling
- timeline and scene playback

## Architectural Character

This is more than a marketing site, but it is not yet a full end-to-end AI-film production platform either. The repo contains meaningful workflow scaffolding and media tooling, while the current project posture still depends heavily on external model/tool quality for the actual creation of strong AI films.

## Important Context

The root `README.md` is still boilerplate from project setup and should not be treated as the canonical project description. This wiki exists in part to replace that gap with repo-grounded documentation.
