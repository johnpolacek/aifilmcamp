# Current Status

## Direction

As of 2026-09-04, AI Film Camp is focused on asset management and the development pipeline for AI films. The user chose to delete the browser timeline and video scene-editing experience because it did not work well. A native macOS editor may be built separately later.

## Retained Product

- public community, discovery, and project pages
- concept, character, outline, and screenplay workflows
- reference assets, source-document imports, and image generation
- scene planning and shot prompts
- S3-backed project and scene storage
- publishing and project exports

## Removed Product

The browser timeline, clip trimming, audio mixing/extraction, scene playback editor, stitching tools, video-generation workflow, and FFmpeg composition service have been removed. Existing stored media and historical JSON fields are preserved.

## Near-Term Boundary

Continue developing the web app's planning, asset, and prompt workflows. Do not restore the old editor or add native-app scaffolding without a new request. Upstream AI-film quality remains a consideration, but this cleanup does not depend on solving generation quality.

## Evidence

- `README.md`
- `lib/types/development.ts`
- `lib/projects.ts`
- `lib/scenes.ts`
- `components/views/edit-scene-prompts-view.tsx`
