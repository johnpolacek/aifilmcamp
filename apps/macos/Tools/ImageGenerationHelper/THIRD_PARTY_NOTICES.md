# Image generation helper third-party notices

The bundled helper is built from the exact versions recorded in `package-lock.json`.
Runtime dependencies and their licenses are:

- Vercel AI SDK (`ai`, `@ai-sdk/provider`, `@ai-sdk/provider-utils`) — Apache-2.0
- Vercel Google and OpenAI provider packages — Apache-2.0
- `@standard-schema/spec` — MIT
- `eventsource-parser` — MIT
- `json-schema` — AFL-2.1 or BSD-3-Clause
- `zod` — MIT
- Node.js 24.14.1 — MIT and bundled third-party notices distributed by Node.js

Build-only dependencies (`esbuild`, `postject`, `tsx`, TypeScript, and Node type
declarations) are not included as separate runtime files in the app. Their licenses are
recorded by the locked npm dependency metadata.

Source and license links:

- https://github.com/vercel/ai
- https://github.com/nodejs/node
- https://github.com/evanw/esbuild
- https://github.com/nodejs/postject
- https://github.com/privatenumber/tsx
- https://github.com/microsoft/TypeScript

Film Camp makes no modification to provider services or their terms. Users supply their
own provider account and API key.
