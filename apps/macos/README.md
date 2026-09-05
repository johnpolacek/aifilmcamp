# AI Film Camp

AI Film Camp is a local-first native macOS application that prepares a film
project for external AI video generation. Phase 1a turns it into a screenplay
breakdown tool: import a Fountain, FDX, PDF, or plain-text screenplay and work
through its parser-derived scenes, characters, and locations in a multi-window
shell.

The breakdown is yours to correct. Rename, reclassify, and describe entities;
add and remove aliases; merge two entities or split one apart; move a location
inside another; mark something irrelevant; accept or reject a fact; edit scene
synopses, scene entities, wardrobe and continuity states, continuity events,
and relationships. Every fact carries its provenance — who found it, who owns
it now, and whether a person has vouched for it — and every change is journaled
with a full-snapshot inverse, so ⌘Z undoes it by name ("Undo Rename Character")
and Edit ▸ Show Edit Journal… lists what happened. A **lock** pins a field, a
whole record, or a single alias so nothing later overwrites a decision you have
already made. Deleting a row the parser produced keeps it as a rejected
tombstone, visible under the entity list's Rejected filter, so a re-import
cannot resurrect it.

No AI is involved yet; the Codex harness from Phase 0 remains for the
extraction phase.

## Requirements

- macOS 15 or newer
- Xcode 26.6 with Swift 6
- XcodeGen 2.46.0
- Codex CLI 0.146.0 or newer for opt-in live acceptance only

Build and launch the latest development version with:

```bash
./dev
```

The shortcut regenerates the Xcode project, builds into the repository's
stable DerivedData directory, closes any older running copy, and launches the
fresh build.

The repository is currently in prototype mode. It intentionally has no unit,
integration, UI, snapshot, or evaluation test suites. Build the packages and
app after changes with:

```bash
./scripts/build.sh
```

This runs documentation consistency checks, builds both Swift packages, and
builds the macOS app. Product testing will be introduced after the MVP shape is
settled. Live Codex or provider requests remain manual, explicitly approved
operations and are never run by CI.
