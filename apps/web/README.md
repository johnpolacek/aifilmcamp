# AI Film Camp

A project workspace and asset manager for developing AI films: concepts, characters, outlines, screenplays, reference assets, scene plans, and shot prompts. Projects can publish selected development phases and export their materials.

## Development

Use Node 22 (`nvm use`) and the pnpm version pinned in `package.json`.

```sh
pnpm install
pnpm dev
```

Configure `.env.local` with Clerk authentication, AWS S3 storage, and Google AI credentials. See `.env.example` for the variable names. The app runs at http://localhost:3000.

```sh
pnpm build
pnpm typecheck
pnpm lint
```

## Product boundary

This web app handles project planning, assets, and prompts. The browser video editor, timeline, audio mixing, stitching tools, video generation pipeline, and FFmpeg composer were removed in September 2026. The native macOS app lives alongside this app in `../macos`.

Existing uploaded media and historical fields in stored project JSON are preserved. No data migration or remote media deletion is required for this removal. New scenes contain planning and asset metadata only.

## Documentation

See [the project wiki](../../wiki/index.md) for workflow and storage details.
