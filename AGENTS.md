# AI Film Camp monorepo

- `apps/web` is the existing Next.js app, managed by the root pnpm workspace. Follow its `AGENTS.md`; bundled Next.js guides resolve from that directory.
- `apps/macos` is the native macOS app. Follow its `AGENTS.md` for app work.
- Keep the root pnpm lockfile and pinned package manager. The macOS image helper retains its independent npm lockfile and build script.
- Run web commands from the repository root: `pnpm dev`, `pnpm build`, `pnpm lint`, and `pnpm typecheck`.
- Build the native app with `pnpm build:macos`; build and launch it with `pnpm dev:macos`.
- Prefer to commit and pull whenever confident that the code is good and there are no questions about implementation.
