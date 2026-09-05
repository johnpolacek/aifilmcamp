# Editorial app appearance

## Status

DONE — authorized and implemented 2026-09-04. The owner wants the website's
aesthetic in the native app and will iterate on workflows through use.

Validation: scripts/build.sh passed, including both packages, the app, and
documentation consistency. Live visual inspection timed out through the native
app-control service, so rendered layout, keyboard focus, and appearance switching
still need a hands-on check. Source review confirms presentation-only changes.

## Contracts

- Presentation only: preserve actions, navigation, data, generation, and disclosures.
- Translate the website's Rethink Sans / JetBrains Mono, neutral surfaces,
  amber emphasis, fine rules, and tight corners into native SwiftUI.
- Keep system fonts for controls and long-form editing. Bundle licensed fonts
  locally, register once, and add no animation or runtime network dependency.
- Preserve light/dark appearance, semantic statuses, accessibility labels,
  native keyboard behavior, and bounded image previews.

## Steps

1. Add shared appearance tokens and bundled display/metadata fonts.
2. Restyle Welcome, the scene rail, scene headings, and reference/prompt surfaces.
3. Build with scripts/build.sh, inspect the result where tools permit, and record
   any visual-verification limitation.

## Done criteria

- Main app surfaces use a coherent visual system derived from the website.
- Required build and documentation checks pass.
- No workflow or provider changes.

## STOP conditions

- Do not modify user project data or run paid generation to verify appearance.
- A tool failure preventing visual inspection must be reported honestly.
