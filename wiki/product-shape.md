# AI Film Camp Product Shape

## Summary

AI Film Camp currently looks like a hybrid product: part community site, part project workspace for developing AI film projects, with asset management, prompt planning, and project exports.

## Public App Surface

The App Router currently exposes:

- `/` for the public landing page
- `/about`, `/films`, `/projects`, and `/resources` for public content and discovery
- `/{username}/{projectSlug}` for public project pages

## Authenticated Workspace Surface

The dashboard area includes:

- `/dashboard`
- `/dashboard/profile`
- `/dashboard/projects/new` and `/dashboard/projects/{id}/edit`
- `/dashboard/projects/{id}/scenes/{sceneId}/edit` for scene planning and shot prompts

These routes align with the repo’s project, profile, and publishing workflows rather than a simple content site.

## Major Product Areas

### Community and discovery

The home view and public sections present AI Film Camp as a community for AI filmmakers rather than only a production tool.

### Project development workspace

The repo includes forms, editors, and workflow utilities for:

- project setup
- screenplay editing
- scene planning
- shot and prompt management
- export and publishing behavior

### Planning and asset tools

The app retains source imports, reference assets, image generation, shot prompts, and project exports. The timeline, video editor, audio tools, stitching pages, and composition backend were removed on 2026-09-04. A native macOS editor may be explored in the future.

## Architectural Character

This is more than a marketing site, but it is not yet a full end-to-end AI-film production platform either. The repo contains meaningful workflow scaffolding and media tooling, while the current project posture still depends heavily on external model/tool quality for the actual creation of strong AI films.

## Important Context

The root `README.md` describes local setup and the product boundary. This wiki holds the deeper workflow and storage notes.
