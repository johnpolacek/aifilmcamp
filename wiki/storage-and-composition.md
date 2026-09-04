# Storage And Media

## Project And Scene Storage

Projects are stored as JSON under `projects/` in S3. `lib/projects.ts` loads, saves, lists, and resolves projects, and normalizes development phase status and visibility.

`lib/scenes.ts` supports scenes embedded in a project's `scenes` array and a fallback at `scenes/{projectId}/{sceneId}.json`. Scene planning saves preserve existing JSON properties, including historical media fields that the web app no longer interprets. Syncing an existing scene from the script breakdown also preserves those properties.

The active scene model in `lib/scenes-client.ts` contains screenplay details, characters, locations, prompt shots, and asset metadata. New scenes no longer initialize timeline or audio layers.

## Assets And Exports

Uploads for project documents, character images, and location images use the existing server actions and S3 helpers. Image optimization, Google image generation/reference analysis, and project exports remain. Historical generated video assets remain available to the existing export code.

S3 and CloudFront remain the storage and delivery infrastructure. Removing editing code does not delete stored project JSON or uploaded media.

## Composition Removal

On 2026-09-04, the browser timeline, shot/video editor, audio tools, stitching pages, FFmpeg composer service, and their processing APIs were removed. Video-generation polling and timeline migration/mutation helpers were also removed. The scene planning and shot prompt interface remains.

There is no composition service to start or deploy with this app. A possible native macOS editor is a future project, not a current dependency. The prior implementation is recoverable from Git history, including checkpoint `a5ed51b`.
