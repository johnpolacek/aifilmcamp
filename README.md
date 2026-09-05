# AI Film Camp

A monorepo containing the web project workspace and native macOS filmmaking app.

```text
apps/
  web/       Next.js app: project planning, assets, and prompts
  macos/     Native SwiftUI app, Swift packages, tools, and design docs
wiki/        Web workflow and storage documentation
```

## Web development

Use Node 22 (`nvm use`) and the pnpm version pinned in the root `package.json`.

```sh
pnpm install --frozen-lockfile
cp apps/web/.env.example apps/web/.env.local # first-time setup only
pnpm dev
```

Configure `apps/web/.env.local` with Clerk authentication, AWS S3 storage, and Google AI credentials. Existing local environment files were moved into `apps/web`. The web app runs at http://localhost:3000.

Root commands delegate to the web workspace:

```sh
pnpm build
pnpm start
pnpm typecheck
pnpm lint
pnpm format:check
```

Formatting and check commands also run inside `apps/web`. For direct tool access, use `pnpm --filter @aifilm-camp/web exec <command>`.

## macOS development

Requires macOS 15+, Xcode 26.6, and XcodeGen 2.46.0.

```sh
pnpm build:macos
pnpm dev:macos
```

The build runs documentation checks, builds FilmCore and FilmBrain, regenerates the Xcode project, and builds the app. The development command builds and launches it. Both scripts also work directly without pnpm: `./apps/macos/scripts/build.sh` and `./apps/macos/dev`.

The image-generation helper keeps its own npm dependencies and lockfile under `apps/macos/Tools/ImageGenerationHelper`; the native build manages these. It is intentionally outside the pnpm workspace. Native CI is preserved in `.github/workflows/macos.yml`.

## Deployment

For the existing web hosting project, set its Root Directory to `apps/web`, use the Next.js framework preset, and enable access to files outside the Root Directory so the root pnpm workspace and lockfile are available. Use `pnpm install --frozen-lockfile` for installation and `pnpm build` for the build command. Hosting settings are not changed by moving the local files.

## Migration

The macOS source, resources, design drafts, and tooling were moved from `../aifilm.camp/apps/macos`. Imported from source commit `05348be396f247e1cc8a0e57b419a103e79567a6`, including local logo drafts. Its Git history remains in that sibling repository. Old native build caches and local agent worktrees remain there because they refer to their original paths; new builds use this repository. The sibling repository's unrelated changes are preserved.

Code paths in the web wiki are relative to `apps/web`.

See [web documentation](apps/web/README.md), [macOS documentation](apps/macos/README.md), and [the web wiki](wiki/index.md).
