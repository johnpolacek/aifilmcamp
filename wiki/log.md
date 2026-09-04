# Project Wiki Log

`log.md` is the append-only record of meaningful project-wiki activity.

Preferred heading format:

`## [YYYY-MM-DD] type | title`

Keep entries concise and grounded in repo evidence.

## [2026-04-05] bootstrap | initialize aifilmcamp project wiki

- Inspected the repo root, route structure, workflow utilities, S3-backed project and scene storage, and the `video-composer` service before creating wiki files.
- Added the minimal durable wiki set: `AGENTS.md`, `index.md`, `log.md`, `product-shape.md`, `workflow-and-phases.md`, `storage-and-composition.md`, and `current-status.md`.
- Recorded the project wiki as the canonical deep-doc location for this repo and synchronized the high-level summary in `/Users/johnpolacek/Wiki`.

## [2026-09-04] update | retire browser video editing and composition

- Preserved the existing dependency, branding, authentication, and compatibility changes in checkpoint `a5ed51b`.
- Removed the browser timeline, video/shot editor, audio tools, stitching pages, composition service, and dedicated processing code.
- Kept project development, assets, scene planning, shot prompts, publishing, and exports. Existing stored media and historical JSON properties remain intact.
- Updated the product, storage, status, and setup docs to reflect the web app's planning/asset focus and a possible future native macOS editor.
- Validation: production build and TypeScript passed; lint reported 18 warnings and 2 informational diagnostics, with no errors. Local HTTP checks passed for retained public pages and returned 404 for the retired tools and processing routes.
- Verified that planning edits preserve historical media fields in both embedded and separate scene storage, and that new/extracted scenes no longer initialize timeline fields.
