# Storage And Composition

## Summary

AI Film Camp currently uses S3-backed JSON storage for project data and scenes, plus a separate Node/FFmpeg service for video composition.

## Project Storage

Project records are stored under the `projects/` prefix in S3 as JSON files.

Key responsibilities in `lib/projects.ts`:

- load a project by ID
- save project data back to S3
- list project IDs
- filter projects by username
- resolve a public project by username and slug
- delete project data

The save path also normalizes workflow-related fields such as duration, film length, phase status, and phase visibility.

## Scene Storage

Scene data is managed through `lib/scenes.ts`.

The current scene model supports two storage modes:

- scenes embedded in a project’s `scenes` array
- scenes stored separately under `scenes/{projectId}/{sceneId}.json`

That split exists to preserve compatibility while allowing newer scene persistence patterns.

## Media And Upload Layer

The repo includes:

- presigned-upload API support
- image optimization helpers
- video thumbnail helpers
- utilities for waveform, transitions, and export

S3 plus CloudFront are core infrastructure assumptions in the current codebase.

## Video Composer Service

The bundled `video-composer/` service is a separate Node.js service that:

1. receives composition jobs from the Next.js app
2. downloads source video and audio
3. uses FFmpeg to composite them
4. uploads final outputs to S3
5. reports completion through a webhook

This service is an important architectural boundary. Composition is not handled fully inside the Next.js app.

## Practical Implication

The repo already contains meaningful production-pipeline infrastructure, but that infrastructure is mostly about organizing, assembling, and exporting media once source materials exist. It does not by itself solve the upstream problem of generating consistently strong AI-film inputs.
