# Projects

A project is a home for a film. Creation needs only a title and defaults to private. The details editor supports a cover, a short description, a video link, and one Private/Public setting. YouTube and Vimeo links embed; other HTTP(S) video links open on their original site.

The dashboard is a project library. `/projects` and `/films` show public projects. A public project page shows only the film or cover, title, creator, and description. Owners can preview private pages; other visitors cannot read them or their metadata.

## Existing projects

No storage migration or deletion is required. Basics updates merge into the latest project object and retain its owner, URL slug, scripts, characters, scenes, assets, phase data, and unknown fields. The production editor remains at `/dashboard/projects/[id]/development`. Phase publishing controls have been removed; working material stays in the owner workspace.

Stored posts and post images remain in storage. Post UI, server actions, and export code are retired. Old public post links redirect to the project page, while dashboard post links redirect to project details. RSS GET and HTML export POST return HTTP 410. Old public screenplay links send owners to their editor and other visitors to the public project page (or 404 for a private project).

## Verification

From the repository root:

- `node --test apps/web/tests/*.test.mjs` (Node 24; uses native TypeScript stripping and module hooks)
- `pnpm typecheck`
- `pnpm lint`
- `pnpm build`

Tests exercise the actual save and access functions with isolated authentication and storage, including title-only creation, unique IDs, stable URLs, publish/unpublish access, unauthorized edits, and preservation of working material. URL tests cover safe links and YouTube/Vimeo embedding.
