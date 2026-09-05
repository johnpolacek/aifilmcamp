# AI Film Camp — fresh mark exploration

Four standalone symbols, developed from the brief without reference to the earlier
concepts in this repo. No wordmark, no initials. Open `comparison-board.html` in a
browser for the full board (all SVGs are embedded, so the file is self-contained).

## Palette

| Role | Hex | Notes |
| --- | --- | --- |
| Amber | `#F5A524` | The only chromatic colour. Firelight, not orange. |
| Ink | `#1C1917` | Neutral for the second shape on light grounds. |
| Cream | `#F7F3EE` | The same neutral, swapped for dark grounds (app tile). |

Marks 01 and 03 use a second flat colour; 02 and 04 are single-colour and rely
entirely on negative space. No gradients, shadows, strokes-as-decoration, or
sub-pixel detail anywhere.

## Concepts

### 01 — Bokeh Sparks
Three embers lifting off a fire on a rising diagonal, cut as the hexagonal bokeh a
lens makes of a point of light. Fire and optics collapse into one shape: the spark
*is* the aperture. The most playful and the most modular — the three elements can
animate, stack, or serve as a list bullet. Weakest single silhouette of the four.

### 02 — Ember Arc
A lens ring caught mid-open: one blade has peeled off the barrel and tapered into a
single lick of flame, so ring and fire are one unbroken stroke. Deliberately has no
centre dot — a ring plus a pupil reads as an eye, which the brief rules out.

### 03 — Ember Iris
A true three-blade iris. The blades are split by tangential seams, the way real
aperture blades overlap, rather than by radial spokes, and they open onto a
triangular core of firelight — the campfire seen straight down the barrel.

### 04 — Hearth Lens
A single flame with a clean circular lens cut through its heart. The hooked,
off-centre tip is what keeps it fire rather than a water droplet; the void is what
keeps it optics rather than a candle. One shape, one counterform, one colour.

## Files per concept

| File | Purpose |
| --- | --- |
| `color.svg` | Full colour, 96×96 viewBox, transparent ground |
| `mono-dark.svg` | Solid `#000000` |
| `mono-light.svg` | Solid `#FFFFFF`, for dark grounds |
| `small.svg` | The mark at 32, 24 and 16 px in one strip |
| `tile.svg` | 256×256 macOS-style dark rounded tile, mark at 75% |

All SVGs carry `role="img"` with a `<title>` and `<desc>`, use a transparent
background, and are hand-authored — no editor cruft, no `<style>` blocks, minimal
path precision.

## Status

Exploration only. Nothing here is wired into the app, and nothing is committed.

`prior-run/` holds an earlier set of `fresh-model` concepts that was already on disk
when this round started; it was moved aside rather than deleted.
