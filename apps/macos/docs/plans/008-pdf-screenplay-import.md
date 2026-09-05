# Plan 008: PDF screenplay import (Phase 1a, part 5)

> **Executor instructions**: Read `docs/PHASE1_DESIGN.md` in full first. This
> plan implements its §3.2a, §3.3 (the PDF half), §4.2a, §5.4a, the `pdf` row of
> §5.5's sniff table, and the `structure-piece.pdf` artifact of §7.1; it is the
> Plan 008 named by roadmap delta §13.11 and decision §14.8. It touches
> `FilmScript`, one GRDB migration, the app's import surface, and the sample
> corpus — **no** `ProjectTools` mutation API, editing, provenance, locks,
> scorer, or extraction; `FILMCAMP_RUN_LIVE_CODEX` stays unset and no Codex
> process runs. Run the steps in order and every verification command; honor the
> STOP conditions. Requires Plan 004 `DONE`; when done, mark this plan `DONE` in
> `docs/plans/README.md`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   1f0e224d9d668bc10fa01ab55bf60e115b14bafd0931eb81c26d152d5a4467ac docs/ROADMAP.md \
>   8660b7114aa507a98ec2cf621176355cb912b749ff3b84395e6f4af6fb927691 docs/OVERVIEW.md \
>   282b1ae714029b96e932bff1eba236df0e05b76abc1fe6b434f90f11ca418d46 docs/REFERENCE_PROJECTS.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all five print `OK`, and `git rev-parse --short HEAD` shows a commit
> descended from `a010702` (Plan 004 `DONE`). If a hash differs, stop for
> reconciliation when §3.2a, §4.2a, §5.4a, §5.5, or §7.1 changed — those five
> sections are this plan's entire mandate. `docs/PHASE1_DESIGN.md` was amended on
> 2026-08-20 to add §3.2a, §4.2a, §5.4a, delta §13.11, and decision §14.8; the
> hash above is that amended text.

## Status

- **Status**: DONE (2026-08-20)
- **Priority**: P1
- **Effort**: M–L, approximately 5–7 focused engineering days (reader and
  renderer, the margin calibrator, a deterministic PDF fixture generator, one
  migration, the app's import surface, `structure-piece.pdf` and its key)
- **Risk**: MED. Two risks are specific to this plan and to nothing before it:
  classification is a **heuristic** over geometry rather than a decode of a
  declared structure, and `PDFKit` is a **system framework** whose extraction can
  change under a macOS upgrade, which puts a byte-exact answer key at the mercy
  of something this repository does not version. Contract D handles the second
  explicitly. No concurrency, process, account, or credential risk.
- **Depends on**: 004 (the app's import UI, the panel service, and the automation
  flags this plan extends). Independent of 005–007 — see
  `docs/plans/README.md`'s dependency notes.

## Why this matters

PDF is the format screenplays actually arrive in. `docs/ROADMAP.md` sequences it
"after the structured formats work well" and `docs/OVERVIEW.md` lists it as
supported; Plans 002–004 shipped the structured formats, so pulling PDF into
Phase 1a restores the roadmap rather than extending it (§13.11). Without it the
filmmaker with a locked PDF from a producer has to find a converter before the
app is of any use, and every Phase 1b measurement is taken on material that
reached the app through a format the operator had to negotiate for.

The design's answer is deliberately small: PDF gets **no scene rules of its
own**. `PDFReader` recovers per-line geometry, `PDFRenderer` turns geometry back
into Fountain, and the same `FountainParser` segments it — the exact pattern
`FDXReader`/`FDXRenderer` already prove (§5.4). One scene contract, four
formats. What is new is that the element type is *inferred* from a left margin
rather than read from an attribute, and this plan's job is to make that
inference deterministic, calibrated to the document in front of it, and honest
about what it cannot recover.

## Current state (Plan 004 DONE, commit `a010702`)

- `Packages/FilmCore/Sources/FilmScript/` holds eleven files and no dependency:
  `ScreenplayDocument.swift` (all value types and the four `String`-raw enums),
  `TextNormalization`, `FountainLineClassifier`, `FountainParser`,
  `HeadingParser`, `CueNormalizer`, `DisplayCase`, `FDXParagraph`, `FDXReader`,
  `FDXRenderer`, `ScreenplayImporter`. `FilmScriptVersion.parser == "1"`.
- `ScreenplayImporter.load(url:)` reads bytes, picks a format from the extension
  (`fdx` / `fountain` / `spmd` / `txt`, else a `<?xml`/`<FinalDraft>` content
  sniff), routes `.fdx` to `FDXReader`, and otherwise decodes **UTF-16 when a
  UTF-16 BOM is present, else UTF-8, else throws `.unsupportedEncoding`**. An
  unknown binary therefore throws today; PDF bytes must never reach that decode.
- `FDXRenderer.render(_:) -> (text: String, warnings: [ParseWarning],
  titlePageLines: [String])` is the shape this plan mirrors, and its
  logical-block blank-line rule (a `Character` paragraph opens a dialogue run
  that `Parenthetical`/`Dialogue` join with a single `\n`; every other boundary
  gets `\n\n`) is the rule §5.4a says PDF follows "exactly".
- `ScreenplaySamples` is a library target with one Swift file, `.copy("Resources")`,
  `url(named:)` (**frozen**, full filename, traps on miss), `all: [SampleDescriptor]`,
  and twelve resource files. `SampleDescriptor` is `Sendable, Hashable` with
  `name`, `screenplay`, `finalDraft`, `parseAnswerKey`, `finalDraftParseAnswerKey`,
  `syntaxCoverage`, and a public memberwise `init` constructed **only** inside
  `ScreenplaySamples.swift`.
- `Tests/FilmScriptTests/ExpectedParseSupport.swift` is the byte-exact answer key
  writer/checker: `inputExtensions = ["fountain", "fdx", "txt"]`,
  `excludedNames = ["fdx-malformed.fdx"]`, directory scan over
  `Tests/FilmScriptTests/Samples/adversarial/` and
  `Sources/ScreenplaySamples/Resources/`, `FILMCAMP_UPDATE_EXPECTED=1` writes then
  fails on purpose.
- Storage is bundle schema **2**: `SchemaV2.swift` holds the v2 DDL with
  `scripts … CHECK (format IN ('fountain','fdx','text'))`, `ProjectMigrator`
  registers the named GRDB migrations, `FilmCoreVersion.bundleSchema == 2`, and
  `ProjectDatabase` refuses a bundle whose `user_version` exceeds it. FilmCore
  reuses `FilmScript.ScreenplayFormat` directly (`RowDecoding.swift:21`), so a new
  enum case flows through the domain with no mapping table to edit.
- The app's screenplay chooser is `ProjectPanelService.screenplayToImport()`:
  `allowedContentTypes = [.plainText, .xml]` plus
  `ScreenplayOpenPanelDelegate.allowedExtensions = ["fountain", "txt", "fdx"]`, and
  the Scenes-empty-state drop target applies the same extension predicate.
  `project.yml` declares `com.aifilmcamp.fountain` and `com.finaldraft.fdx` as
  `UTImportedTypeDeclarations` only.
- `scripts/finder-smoke.sh:86` asserts `PRAGMA user_version` is `"2"`.
- `.gitattributes` marks `*.fountain` and `*.fdx` as `-text`. `.gitignore` ignores
  `*.aifilm/` (with Plan 003's negations for the v1 fixture) and `*.db*`; it says
  nothing about `*.pdf`.
- Toolchain pins unchanged: Xcode 26.6, Swift 6, macOS 15 floor, XcodeGen 2.46.0,
  GRDB 7.11.1, swift-json-schema 0.13.1, `macos-26` runner. **`Package.resolved`
  must not change** — PDFKit is a system framework, not a package (§3.2a).

### Empirical basis (reconnaissance, 2026-08-20)

`PDFKit`'s `selectionsByLine()` was run over a real 91-page operator screenplay
PDF (US Letter, 612×792pt) before this plan was written. The numbers below are
why §5.4a's algorithm is shaped the way it is, and the executor should expect
them to hold on any normally formatted screenplay PDF:

- The text layer is present and clean: 8,923 characters over the first ten pages.
- Left-margin buckets over all 91 pages: **1.50″ → 906 lines** (action *and* all
  69 scene headings), **2.50″ → 1,576** (dialogue), **2.90–3.00″ → 22**
  (parentheticals; 20 of them also matched a literal `(…)` test), **3.50″ → 764**
  (character cues), **7.50″ → 89** (page numbers; 90 numeric-only lines in total,
  matching the page count), plus roughly 11 scattered lines at 4.5–5.9″
  (right-aligned transitions and centered text).
- Vertical gap between consecutive lines: **0pt → 1,759** (same block), **12pt →
  1,285** (one blank line), **24pt → 144** (two), with about 48 negative gaps at
  page boundaries.
- Observed cue forms include `EVAN (CONT'D)`; the text carries smart quotes and
  U+2011 non-breaking hyphens.

Three conclusions are load-bearing for the contracts below. Margin
classification is viable and the four dominant clusters map cleanly onto §5.4a's
canonical anchors. Page numbers are ~10% of all lines and **must** be suppressed
or every page boundary injects a stray action line. Blank lines carry the block
structure and exist only as vertical gaps, so they must be reconstructed. Note
also that headings share the action margin — they are recovered by the §5.1
prefix test, not by geometry — and that the scattered 4.5–5.9″ lines fall below
any cluster threshold, which is precisely the `unclassifiedMargin` case.

## Contracts (normative)

### A. New `FilmScript` public API

Additive only. Every new type is `public` and `Sendable`; the struct is
`Codable` + `Equatable`; the error enum is `Error, Equatable` and never
raw-valued. **No PDFKit type appears in any public signature** (§3.2a): `import
PDFKit` is confined to the body of `PDFReader.swift`, and the public boundary
stays `String`/`Data`/`URL` among Foundation types (§3.1). Names, cases, and
stored properties are contracts:

```swift
enum ScreenplayFormat: String { case fountain, fdx, text, pdf }        // + pdf
enum WarningCode: String { …existing seven…                            // + two
      case unclassifiedMargin, dualDialogueColumnsDetected }

/// The reader → renderer value type, mirroring `FDXParagraph`'s role.
struct PDFLine {
  let text: String            // the line's text, trimmed of leading/trailing whitespace
  let pageIndex: Int          // 0-based, document order
  let leftFraction: Double    // (bounds.minX - mediaBox.minX) / mediaBox.width
  let rightFraction: Double   // (bounds.maxX - mediaBox.minX) / mediaBox.width
  let topFraction: Double     // (mediaBox.maxY - bounds.maxY) / mediaBox.height, 0 at page top
  let bottomFraction: Double  // (mediaBox.maxY - bounds.minY) / mediaBox.height, 1 at page bottom
}

enum PDFReader   { static func read(_ data: Data) throws -> ScreenplayDocument
                   static func lines(_ data: Data) throws -> [PDFLine] }   // internal, test seam
enum PDFRenderer { static func render(_ lines: [PDFLine]) -> (text: String, warnings: [ParseWarning]) }
enum PDFReadError: Error, Equatable { case unreadable, encrypted
                                      case noTextLayer(pagesTotal: Int, pagesWithText: Int) }
```

Six stored properties on `PDFLine`, frozen. Rationale for each choice, because
each is a decision the executor must not re-open:

- **Both axes are page-relative fractions, so `PDFLine` carries no absolute
  unit at all.** §5.4a normalizes the left edge so "Letter, A4, and scaled
  documents classify identically"; the same argument applies to the vertical
  axis, and normalizing it removes the need for a redundant per-line
  `pageHeight`. The page-furniture predicate then reads directly as
  `topFraction < 0.08 || bottomFraction > 0.92`.
- **`topFraction` is measured downward from the page top** while PDF's own
  coordinates run upward. §5.4a writes the inter-line gap as `previous.minY -
  current.maxY`; in these top-down fractions the identical quantity is
  `current.topFraction - previous.bottomFraction`. This is a sign convention,
  not a change of rule — do not flip it back, and do not mix the two.
- **A line's height is `bottomFraction - topFraction`**; there is no stored
  height field.
- **`rightFraction` exists only for the dual-dialogue column test** (§5.4a's
  "disjoint horizontal ranges"). Nothing else reads it.
- `text` is trimmed at extraction (§5.4a: "record its trimmed text"), so the
  renderer never re-trims and a leading-space difference cannot move an offset.

`PDFRenderer.render` returns a **two**-element tuple, unlike `FDXRenderer`'s
three. `PDFReader` applies the §5.4a **title-page rule** — page 1 with no scene
heading and at most 12 lines yields `TitlePage.lines` (verbatim, `entries`
empty), is excluded from `source_text`, and is never margin-classified, so a
centered title and author name cannot become character cues. The renderer
therefore still returns a 2-tuple; the title page is resolved in the reader,
which is the only place that knows page boundaries. A page-1 block that fails
either half of the test (a heading is present, or more than 12 lines) is
classified normally — the rule never guesses.

`PDFReader.read` composes exactly as `FDXReader.read` does: `lines(_:)` →
`PDFRenderer.render` → `FountainParser.parse(text, format: .pdf)`, with the
renderer's warnings prepended to the parser's warnings in that order.

**`FilmScriptVersion.parser` stays `"1"` in this plan.** Plan 002's rule is that
any commit changing a *committed* `.parse.json` bumps it; this plan *adds* keys
and changes none, and the Fountain parser's behaviour over Fountain, FDX, and
text input is untouched. Contract D states the one circumstance that does force a
bump.

### B. Extraction, classification, and rendering (§5.4a, restated to implement)

Restated here in full so the executor implements it without re-deriving it from
the design prose. Every number below is §5.4a's; none is invented.

**B1. Extraction.** `PDFDocument(data:)`. A `nil` document throws
`PDFReadError.unreadable`; a document whose `isLocked` or `isEncrypted` is true
throws `.encrypted` (check locked/encrypted **before** unreadable-by-content, so
an encrypted file never reports as "no text layer"). For each page in index
order, take `page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine()`
and, for each line selection, record its trimmed string and its `bounds(for:
page)` normalized against that page's `.mediaBox` per contract A. Lines whose
trimmed text is empty are not recorded. If the total extracted character count
across the whole document is **under 200**, throw `.noTextLayer` — a scanned PDF
is refused, never OCR'd (§11 keeps OCR a non-goal) and never silently rendered as
an empty screenplay.

**B2. Canonical anchors.** On an 8.5″ page: action `0.176` (1.5″), dialogue
`0.294` (2.5″), parenthetical `0.353` (3.0″), character cue `0.435` (3.7″). These
four constants, in ascending order, are the whole element vocabulary geometry can
supply.

**B3. Calibration.** Over **all** lines that survive B4, build a histogram of
`leftFraction` in **0.01** buckets. A **cluster** is any bucket holding at least
**2% of all lines**, merged with its immediate neighbouring buckets (a bucket
adjacent to a cluster joins it whether or not it clears 2%, so a margin that
straddles a bucket edge is one cluster and not two). A cluster's position is the
line-count-weighted mean of its members' `leftFraction`.

**B4. Page furniture is dropped before calibration.** A line is discarded when it
sits in the top or bottom **8%** of its page (`topFraction < 0.08 ||
bottomFraction > 0.92`) **and** either its trimmed text matches
`^\(?(CONTINUED|MORE)\)?:?$` case-insensitively, **or** it is purely a page
number — text matching `^\d+\.?$` **and** `leftFraction > 0.75`. Both conditions
are required; a `12` in body text at the dialogue margin is dialogue, and a
centered footer that is not a page number or a `(MORE)` is kept. **Nothing else
is ever dropped.** Dropping before calibration is deliberate: the recon found
page numbers at ~10% of all lines, which is above the 2% threshold and would
otherwise form a spurious fifth cluster.

**B5. Assignment.** Sort the clusters ascending by position. Assign each to its
nearest canonical anchor by absolute distance. When two clusters claim one
anchor, the closer one keeps it and the other falls to the next **unclaimed**
anchor in **ascending margin order**; if two distances tie exactly, the cluster
with the lower position wins. A line whose `leftFraction` falls in no cluster is
rendered as **action** and raises `unclassifiedMargin` **once per document**,
never once per line. Calibration is a pure function of the line list: same bytes
→ same clusters → same assignment.

The recon's right-aligned transitions and centered text (4.5–5.9″, ~11 lines out
of ~3,300) land in no cluster and therefore in this case. That is the intended
outcome, not a defect: a `CUT TO:` rendered as an action line still parses as a
Fountain transition (all-caps, ends in `TO:`, blank-line delimited), so the
transition survives the round trip. Centered text does not survive — `>text<`
is not reconstructible from geometry — and becomes action. Say so in the notes;
do not add a centering heuristic.

**B6. Blank lines are reconstructed from vertical gaps.** Within a page, the gap
between consecutive lines is `current.topFraction - previous.bottomFraction`.
Bucket every **positive** gap to 3 decimal places and take the mode; bucket every
line height (`bottomFraction - topFraction`) the same way and take the mode. A
gap of **at least half the modal line height** starts a new block; anything less
keeps the line in the current block. "Positive" is load-bearing — the recon's
largest single gap bucket is `0pt` (1,759 same-block continuations), so including
zero would make the mode zero and split nothing. A **page boundary always starts
a new block**, which is also why cross-page gaps (about 48 of them, negative) are
never measured. A document with fewer than two lines has no mode; then every line
is its own block.

On Letter the recon's three buckets normalize to 0.0, 0.01515 (12pt), and 0.0303
(24pt), against a threshold of about 0.0076 — a clean three-way separation, and
24pt collapses to the same single blank line as 12pt, which is what §5.4a's "a
new block" means.

**B7. Rendering** follows `FDXRenderer`'s rule **exactly**: one blank line
separates logical blocks, and **no** blank line appears inside a `character →
parenthetical → dialogue` run, so the rendered text re-parses with the same cue
structure. Scene headings are the action-margin lines matching a §5.1 prefix (the
recon confirms headings share the action margin), forced with a leading `.` only
when the line would not otherwise parse as a heading; character-margin lines take
a forced `@` only when the text would not otherwise parse as a cue; transitions
take `> ` only when needed. Reuse `FDXRenderer`'s existing forcing predicates
rather than writing second copies.

**B8. Dual dialogue.** Two lines that share a vertical band (their
`[topFraction, bottomFraction]` intervals overlap) but occupy **disjoint**
horizontal ranges (`a.rightFraction < b.leftFraction` or the reverse) are
side-by-side dual dialogue. They are rendered **sequentially in reading order**
and raise `dualDialogueColumnsDetected` **once per document**, because column
interleaving is not reconstructible from reading order alone. No `^` is emitted:
the renderer does not know which column is primary, and guessing would produce a
wrong `isDual` in a committed answer key.

### C. Import sniffing (§5.5)

`ScreenplayImporter.load(url:)` gains a `pdf` route, and the route is taken
**before** any text decode:

```swift
let format = self.format(for: url, data: data)
if format == .fdx { return try FDXReader.read(data) }
if format == .pdf { return try PDFReader.read(data) }        // Data straight through
guard let text = decode(data) else { throw ScreenplayLoadError.unsupportedEncoding }
```

`format(for:data:)` gains `case "pdf": return .pdf`, and its `default` branch
tests the PDF magic **first**: after skipping a UTF-8 BOM and leading whitespace
exactly as `looksLikeFinalDraft` already does, leading bytes `%PDF-` → `.pdf`,
else the existing `<?xml`/`<FinalDraft` test → `.fdx`, else `.text`. Extension
still wins over content, so a `.txt` file containing PDF bytes stays `.text` and
throws `.unsupportedEncoding` from the decode — the table's existing behaviour,
unchanged.

This is the whole reason the PDF branch is placed where it is: today an unknown
binary reaches `decode` and throws `ScreenplayLoadError.unsupportedEncoding`, and
a PDF that produced *that* error instead of `PDFReadError.noTextLayer` would tell
the filmmaker the wrong thing.

### D. Answer keys, frozen encodings, and the PDFKit determinism rule

**D1. Adding enum cases must not move a single committed byte.** `.parse.json` is
the JSON encoding of `ScreenplayDocument` with `[.sortedKeys, .prettyPrinted,
.withoutEscapingSlashes]`, and `ScreenplayFormat`/`WarningCode` are `String`-raw
`Codable`, so a value encodes as its own raw string and a *new* case cannot
change how an *existing* value encodes. No committed sample produces `pdf`,
`unclassifiedMargin`, or `dualDialogueColumnsDetected`, so no existing key's bytes
change. This is asserted, not assumed: every step's Verify block runs
`git diff --quiet -- 'Packages/FilmCore/**/*.parse.json'` after a full
`ExpectedParseTests` run, and Step 1's is the one that proves the enum additions
specifically.

**D2. `PDFLine`'s `Double`s never reach a committed key.** Like `FDXParagraph`,
`PDFLine` is a reader → renderer type and is not part of `ScreenplayDocument`, so
no floating-point value is ever formatted into a `.parse.json`. Only the rendered
text and its UTF-16 offsets are. Do not add `PDFLine` to any encoded type — that
would put binary-float formatting on the byte-exact path and is exactly the kind
of instability the keys exist to catch.

**D3. The determinism risk PDF introduces, and how it is handled.** §3.2a accepts
that `FilmScript` now links a system framework. The consequence this plan must
own is that **`PDFKit`'s text extraction is not versioned by this repository**: a
macOS release can change `selectionsByLine()`'s line splitting or bounds, and
`structure-piece.pdf.parse.json` would then differ on a machine where no line of
our code changed. The policy is:

1. **The PDF key stays byte-exact.** Loosening it to a structural comparison
   would silently absorb exactly the change worth knowing about.
2. **A PDFKit-induced difference is a real detected regression, not a flake.**
   `ExpectedParseTests` failing on a `.pdf` input is a finding to be reported,
   never a signal to re-run with `FILMCAMP_UPDATE_EXPECTED=1`.
3. **The remedy is a reviewed key update, not a blind one**: confirm from the
   diff that the change is in extraction (line splitting, bounds, character
   folding) and not in our classifier, regenerate, read the diff line by line,
   and **bump `FilmScriptVersion.parser` to `"2"` in the same commit** — the
   committed key changed, so Plan 002's bump rule fires. Record the macOS and
   Xcode versions before and after in `docs/IMPLEMENTATION_NOTES.md`.
4. **CI is insulated.** The runner is pinned to `macos-26` with Xcode 26.6, so
   the key is stable there; the exposure is a developer on a newer local macOS.
   Step 6 therefore records the macOS build the committed key was generated on,
   in `docs/IMPLEMENTATION_NOTES.md`, so a future mismatch is diagnosable in one
   look.
5. It is a **STOP condition** (below) to regenerate a `.pdf` key on a machine
   whose macOS differs from CI's runner.

**D4. Answer key naming.** `ExpectedParseSupport` gains `"pdf"` in
`inputExtensions` and a `pdf` branch in `expectedURL(for:)` producing
`<name>.pdf.parse.json` — the same convention the FDX twin uses, so
`structure-piece.fountain` → `structure-piece.parse.json` and
`structure-piece.pdf` → `structure-piece.pdf.parse.json` never collide. Fixtures
that throw (`pdf-no-text-layer.pdf`, `pdf-encrypted.pdf`) join `excludedNames`
and are asserted in `PDFReaderTests` instead.

**D5. `.gitattributes` gains `*.pdf binary`** before the first PDF is committed,
for the same reason `*.fountain -text` exists: no checkout setting may rewrite a
byte whose hash a key depends on.

### E. Migration v3 and the schema 2 → 3 ripple (§4.2a)

**E1. The migration.** Register a new GRDB migration named `"v3"` with the
default `foreignKeyChecks: .deferred`, exactly as `"v2"` is registered. The
registered `"v2"` migration is **not** edited to include `pdf`: v2 bundles exist,
GRDB records migrations by name, and retroactively changing one would leave old
and new databases carrying different constraints under the same name. `SchemaV2.swift`
is therefore **unchanged** — it is the historical v2 DDL — and the v3 rebuild DDL
is new. A freshly created bundle now runs `v1 → v2 → v3` and rebuilds two tables
on the way; that is a few milliseconds on an empty database and is the correct
semantics.

Steps, in one migration transaction and in this order:

1. Rebuild `scripts` with `CHECK (format IN ('fountain','fdx','text','pdf'))`.
   Every other column, `NOT NULL`, default, and foreign key is **unchanged**;
   copy every row with an explicit column list (never `SELECT *`); create
   `scripts_v3`, `INSERT … SELECT …`, `DROP TABLE scripts`, `ALTER TABLE
   scripts_v3 RENAME TO scripts` — the same pattern `"v2"` uses.
2. Rebuild `projects` with `CHECK (bundle_schema_version = 3)`, rewriting the
   stored value to `3` in the `INSERT … SELECT`.
3. Recreate the indexes over both rebuilt tables **after** both rebuilds — a
   `DROP TABLE` takes its indexes with it. `scripts(project_id)` (§4.2 step 8)
   is among them; recreate every index the v2 schema declares on `scripts` and
   on `projects`, and no others.
4. `PRAGMA user_version = 3`.

**E2. Non-destructive, and silent — and this is where the ripple has teeth.** No
re-parse, no row loss, no synopsis dropped, no entity touched. v2 → v3 therefore
shows **neither** the one-way upgrade modal of §3.11 **nor** the after-the-fact
upgrade sheet. Three existing guards decide that, and each needs a deliberate
decision rather than a mechanical bump:

- **`BundleInspection.needsUpgrade`** (`Storage/UpgradeSummary.swift:51`) is
  `schemaVersion < FilmCoreVersion.bundleSchema`, and `AppCoordinator.swift:160`
  and `:228` gate the one-way modal on it. After the bump that predicate is
  `true` for a **schema-2** bundle, so bumping the constant alone would make
  every existing project present a destructive-sounding "scenes will be rebuilt,
  synopses may be dropped" modal for a migration that does none of that — a
  direct violation of §4.2a. **Add `BundleInspection.needsOneWayUpgrade: Bool {
  schemaVersion == 1 }` and re-point both `AppCoordinator` call sites at it.**
  Leave `needsUpgrade` meaning "opening this will run a migration"; it is the
  honest name for that and something may still want it.
- **`ProjectDatabase.swift:38`'s `guard versionBeforeMigration == 1`** (the
  `upgradeSummary` gate) is **already correct and must stay `== 1`.** It was
  written to distinguish a fresh create from an upgrade; after this plan it is
  also what keeps v2 → v3 silent. Do **not** "fix" it to `< currentVersion` —
  that would surface an upgrade sheet for a migration §4.2a defines as invisible.
  Update its doc comment to say both reasons, so the next reader does not
  generalize it away.
- **`UpgradeSummary.toVersion`** is written by the `"v2"` closure as the literal
  `2` (`ProjectMigrator.swift:346` writes the same literal into
  `bundle_schema_version`). A **v1 → v3** open must report `toVersion == 3`, the
  schema actually reached. Populate it from `FilmCoreVersion.bundleSchema` rather
  than from a literal inside a versioned migration closure.

**E2a. The `"v3"` closure must not touch `MigrationOutcomeBox`.**
`ProjectMigrator`'s outcome box is single-slot and is written only by the `"v2"`
closure (`:289`), because only v2 has anything to report (scenes rebuilt,
synopses dropped). v3 rebuilds two tables and reports nothing. On a v1 → v3 path
v2 fills the box and v3 must leave it alone; on a v2 → v3 path it stays `nil`,
which — together with the `== 1` gate above — is exactly the silence §4.2a asks
for.

**E3. The migration test** asserts, over a schema-2 fixture: **unchanged row
counts for every table** before and after, `PRAGMA foreign_key_check` empty
(`ProjectMigrationTests.swift:106` already has the idiom), `PRAGMA user_version
== 3`, `projects.bundle_schema_version == 3`, that inserting a `format = 'pdf'`
script now succeeds and a `format = 'gibberish'` one still fails the `CHECK`, and
that `SchemaV2.requiredIndexes` still holds afterwards (the existing loop at
`ProjectMigrationTests.swift:174-180`) — in practice that means
`index_scripts_on_project_id` survives, since `projects` declares no explicit
index at all. Add a case asserting that opening a schema-2 bundle yields
`upgradeSummary == nil` and `needsOneWayUpgrade == false`. The schema-2 fixture is
produced in-test by creating a bundle at the current code; only the v1 fixture
(`Samples/v1-phase0.aifilm`, Plan 003) is committed.

**E4. Every assertion that moves from 2 to 3.** The list is the contract, and
Step 3's Verify block greps for stragglers. It was compiled by reading the tree,
not by guessing:

| Location | Change |
|---|---|
| `FilmCore/Domain/Project.swift:4` | `public static let bundleSchema = 2` → `3`. `ProjectMigrator.currentVersion`, `ProjectRepository.swift:20` and `:32`, and `UpgradeSummary.swift:51`/`:53` all read the constant and need no edit. |
| `FilmCore/Storage/ProjectMigrator.swift` | `registerV3` added to `makeMigrator()` after `registerV2`; new `"v3"` closure; rebuild helpers use a **`_v3`** temp-table suffix (`scripts_v3`, `projects_v3`) so they cannot collide with the v2 body's `scripts_v2`/`projects_v2` strings. `:288`'s `PRAGMA user_version = 2` and `:346`'s `SELECT id, name, 2,` stay — they are inside the `"v2"` closure. |
| `FilmCore/Storage/SchemaV3.swift` (new) | `scripts(table:)` and `projects(table:)` for v3, differing from `SchemaV2`'s only in the two `CHECK`s. `SchemaV2.swift` is **not** edited. |
| `FilmCore/Storage/UpgradeSummary.swift` | `+ BundleInspection.needsOneWayUpgrade` (E2) |
| `FilmCore/Storage/ProjectDatabase.swift:38` | `== 1` **kept**; doc comment updated (E2) |
| `FilmCoreTests/ProjectMigrationTests.swift` | `:10` rename `stampsUserAndProjectVersionTwo`; `:23`/`:24` `== 2` → `3`; `:35` writes `user_version = 4` and `:42` expects `.newerProjectVersion(found: 4, supported: 3)`, with `:45`/`:49` following; `:59` `inspection.schemaVersion == 2` → `3`; `:80` `summary.toVersion == 2` → `3`; `:87` `project.bundleSchemaVersion == 2` → `3`; `:100` `user_version == 2` → `3`. The v1-fixture assertions at `:74`, `:79`, `:265`, `:275` keep their `1`s, and `:94`'s `parserVersion == "1"` stays (contract A). |
| `FilmCoreTests/ProjectBundleTests.swift:29` | `project.bundleSchemaVersion == 2` → `3` |
| `AI Film Camp/App/AppCoordinator.swift:160`, `:228` | `inspection.needsUpgrade` → `inspection.needsOneWayUpgrade` (E2) |
| `AI Film Camp/Tests/AppShellTests.swift:238` | `summary.toVersion == 2` → `3`; `:209`–`:211`'s v1 assertions stay |
| `scripts/finder-smoke.sh:86` | `= "2"` → `"3"`. Lines 15–16 snapshot `user_version` and `bundle_schema_version` generically; the snapshot text changes and the before/after `cmp` still passes. |
| `docs/plans/006-evaluation-scorer.md` | See E5 — two factual edits, made by **this** plan's executor. |

`SchemaV2.swift`, the `"v1"` and `"v2"` migration bodies, and Plan 003's committed
`Samples/v1-phase0.aifilm` fixture keep their `2`s and `1`s — they are history.
**Do not edit `docs/plans/002`–`004`**; a DONE plan records what it built and is
not amended because a later one moved a number. `ProjectObservation.swift:19-29`
declares the observed region `(.script, ["scripts", "projects"])` **by table
name**; the v3 rebuild renames the temporaries back to those exact names, so it
needs no edit — but confirm it, because a rebuild that left `scripts_v3` in place
would silently stop the app observing its own script.

**E5. Plan 006 is the one TODO plan this bump actually reaches.** Plans 005 and
007 mention "schema v2" only in prose "current state" claims (`005:43`, `007:56`)
that assert no number and break nothing. Plan 006 has two **factual** couplings,
and this plan's executor fixes both:

1. `006:207` — the canonical evaluation-report example carries
   `"bundleSchemaVersion": 2`, which is filled from `FilmCoreVersion.bundleSchema`
   and is simply wrong once the constant is `3`. Change the literal to `3`.
2. `006:255` — `filmcamp-eval report` is specified to **refuse to merge** inputs
   that disagree on `bundleSchemaVersion`. That rule is right, but it means
   reports produced either side of this bump are unmergeable and a `--baseline`
   comparison across it is invalid. Since Plan 006 is `TODO` and has produced no
   committed report yet, the resolution is a one-line note in 006 recording that
   the schema moved to 3 in Plan 008 and that any pre-bump report is discarded
   rather than migrated. Add it; do not relax the merge rule.

### F. App import surface

No parsing moves into the app, and no new SwiftUI file is required.

1. `ScreenplayOpenPanelDelegate.allowedExtensions` gains `"pdf"` →
   `["fountain", "txt", "fdx", "pdf"]`. The Scenes-empty-state drop predicate reads
   the same set (Plan 004 contract D), so it follows automatically — verify that
   it does rather than adding a second list.
2. `ProjectPanelService.screenplayToImport()`'s `allowedContentTypes` gains
   `.pdf` → `[.plainText, .xml, .pdf]`. The extension predicate still does the
   real filtering, per Plan 004's reasoning about exported UTIs winning over
   imported ones.
3. **No new UTI declaration.** This differs from Plan 004 contract E item 3,
   which had to declare `com.aifilmcamp.fountain` and `com.finaldraft.fdx` as
   imported types: PDF's UTI is the **system** type `com.adobe.pdf`, surfaced as
   `UTType.pdf`, so `project.yml` gains **nothing**, `UTImportedTypeDeclarations`
   is unchanged, `Info.plist` is not regenerated by this plan, and
   `Support/ScreenplayUTTypes.swift` needs no `UTType(importedAs:)` entry. State
   this in the commit message; a reviewer comparing against Plan 004 will look
   for the declaration that is deliberately absent.
4. The import summary sheet (`importSummarySheet`) already renders
   `script.format`; confirm it shows **"PDF"** rather than the raw `pdf` — if it
   displays a raw value, that is the one display change this plan makes, and it
   is uppercase for PDF and FDX and title case for Fountain and Text.
5. Parser warnings already surface in that sheet, so `unclassifiedMargin` and
   `dualDialogueColumnsDetected` reach the filmmaker with no new plumbing.
   Give each a plain-language `ParseWarning.message` — the warning code is not
   what the user reads.
6. **The one-way upgrade modal's gate moves** — `AppCoordinator.swift:160` and
   `:228` switch from `inspection.needsUpgrade` to `inspection.needsOneWayUpgrade`
   (contract E2). This is not cosmetic: leaving them on `needsUpgrade` makes every
   schema-2 project on the filmmaker's disk open with a modal warning that scenes
   will be rebuilt and synopses may be dropped, for a migration that widens one
   `CHECK` constraint. It is the single highest-consequence line in this plan.
7. Automation is untouched: the recorded flow still imports
   `camp-signal.fountain`, and `finder-smoke.sh` changes only its
   `user_version` literal (contract E4).

### G. Samples: `structure-piece.pdf`, its generator, and `SampleDescriptor`

**G1. The artifact.** `Sources/ScreenplaySamples/Resources/structure-piece.pdf`,
**generated from the committed `structure-piece.fountain`** (§7.1), plus
`structure-piece.pdf.parse.json`. It is original synthetic work like every other
sample; no operator or third-party screenplay is ever committed here.

**G2. The generator's home**: a test-only generator,
`Tests/FilmScriptTests/PDFSampleGenerator.swift`, gated by
`FILMCAMP_UPDATE_PDF_SAMPLE=1`, which writes and then **fails on purpose** —
the exact idiom `ExpectedParseSupport` already uses for answer keys, resolving
the source tree from `#filePath`. Rejected alternatives, so they are not
relitigated: a `scripts/*.sh` generator would need a layout tool (`enscript`,
`wkhtmltopdf`) that nothing in this repo pins, and a new SwiftPM executable
target would add a product and a build artifact for something run perhaps twice a
year. The generator adds **no** target, **no** product, and **no** manifest change
beyond what already exists.

**G3. How it lays out.** It parses `structure-piece.fountain` with
`FountainParser`, maps each `ParsedElement.kind` to its canonical margin (action
and `sceneHeading` → 1.5″, `dialogue` → 2.5″, `parenthetical` → 3.0″,
`character` → 3.7″; `transition` right-aligned at 6.0″; anything else → the
action margin), and draws it into a `CGContext(consumer:mediaBox:auxiliaryInfo:)`
PDF at US Letter 612×792 in **12pt Courier** with **12pt leading**, a 1″ top
margin, 55 lines per page, one blank line between blocks and none inside a
`character → parenthetical → dialogue` run. It closes the loop by construction:
the fountain's blocks become margins and gaps, and §5.4a's classifier has to
recover them.

**G4. The generator is not required to be byte-reproducible, and the committed
PDF is the artifact of record.** `CGPDFContext` stamps a creation date and a file
ID, so re-running the generator produces different bytes for the same layout.
That is fine and must be said out loud: `structure-piece.pdf` is committed once,
its `.parse.json` is a key over **those** bytes, and regenerating the PDF is a
deliberate, reviewed change exactly like regenerating an answer key — never
something a test does incidentally. What **is** required to be deterministic is
`PDFReader.read` over fixed bytes, and `PDFReaderTests` asserts that directly by
reading the committed PDF twice in one process and comparing encoded documents.

**G5. `SampleDescriptor` gains two fields**, mirroring the FDX pair:

```swift
public let pdf: String?                 // "structure-piece.pdf"
public let pdfParseAnswerKey: String?   // "structure-piece.pdf.parse.json"
```

with the memberwise `init`'s two new parameters **defaulted to `nil`** and placed
after `finalDraftParseAnswerKey`. Plan 002 froze `ScreenplaySamples.url(named:)`
and `FilmScriptVersion.parser` by name; `SampleDescriptor`'s initializer is not on
that list, every construction site is inside `ScreenplaySamples.swift` itself, and
defaulted parameters keep the call source-compatible for any caller outside it —
so this is a strictly additive change that breaks no consumer. The consumers to
check nonetheless, because Plan 002's Maintenance notes name them: Plans 003, 004,
and 006 call `ScreenplaySamples.url(named:)` and `ScreenplaySamples.all` (`AppServices.swift:220`,
`FilmCoreTests/TestSupport.swift:29` and the FilmCore import/reading/observation
suites, `FilmScriptTests/CampSignalParseTests` and `FDXReaderTests`,
`ScreenplaySamplesTests/SampleResourceTests`); **none constructs a
`SampleDescriptor`**, and `url(named:)` is untouched.

`SampleResourceTests` extends with the same shape it already uses for FDX: the
resolves-every-file loop adds `[sample.pdf, sample.pdfParseAnswerKey]`, and the
frozen-naming test asserts `pdf == "\(name).pdf"` and `pdfParseAnswerKey ==
"\(name).pdf.parse.json"` when `pdf != nil`, both `nil` otherwise.
`structure-piece`'s `syntaxCoverage` gains `"pdf-twin"`, `"pdf-margin-classification"`,
and `"pdf-page-furniture"`.

**G6. The twin assertion** (§7.1), in `PDFReaderTests`, mirroring
`FDXReaderTests`'s existing messy-piece twin test: `structure-piece.pdf` and
`structure-piece.fountain` agree on scene count, ordinals, `heading`, `intExt`,
`timeOfDay`, `sceneNumber`, and the per-scene **set of normalized cues**. Spans
differ and are not compared — the PDF's `source_text` is a rendering (§3.3).
Sequences are **not** compared: `#` sections have no geometric representation and
the PDF simply loses them; assert that explicitly (`pdf.sequences.isEmpty`) so the
loss is a recorded fact rather than a surprise.

### H. Adversarial PDF fixtures

All generated by a test-only `PDFFixtureBuilder` (`Tests/FilmScriptTests/`) that
draws text at explicit points with CoreGraphics and CoreText — **never** a
third-party or operator screenplay, and never a binary of unknown provenance
checked in without a generator beside it. Fixtures live in
`Tests/FilmScriptTests/Samples/adversarial/` beside the Fountain ones, so
`ExpectedParseSupport`'s directory scan picks them up once `"pdf"` is in
`inputExtensions`.

| Fixture | How it is generated | What it must prove |
|---|---|---|
| `pdf-standard.pdf` | Letter, the four canonical margins, a heading, action, cue, parenthetical, dialogue, a `CUT TO:` at 6.0″ | the happy path: four clusters, four anchors, blocks reconstructed; committed `.pdf.parse.json` |
| `pdf-a4.pdf` | **A4** (595.276 × 841.89), same content at the same *inch* offsets → fractions 0.181/0.302/0.363/0.448 | fraction normalization: nearest-anchor assignment recovers the identical classification and the rendered text equals `pdf-standard.pdf`'s |
| `pdf-page-furniture.pdf` | three pages with `CONTINUED:` in the top 8%, `(MORE)` in the bottom 8%, a right-aligned page number at 7.5″, **and** a decoy `12` at the dialogue margin in body text | all three furniture forms dropped, the decoy kept as dialogue, no spurious cluster |
| `pdf-unclassified-margin.pdf` | the standard page plus several lines at ≈0.60 that clear no 2% threshold | rendered as action, exactly **one** `unclassifiedMargin` warning |
| `pdf-dual-columns.pdf` | two cue/dialogue columns sharing vertical bands with disjoint x ranges | rendered sequentially, exactly **one** `dualDialogueColumnsDetected` warning |
| `pdf-no-text-layer.pdf` | one page with a filled rectangle and **no** text | throws `PDFReadError.noTextLayer`; in `excludedNames` |
| `pdf-encrypted.pdf` | `CGContext(consumer:mediaBox:auxiliaryInfo:)` with `kCGPDFContextUserPassword`/`kCGPDFContextOwnerPassword` set | throws `PDFReadError.encrypted`; in `excludedNames`. If the toolchain will not produce an encrypted PDF this way, assert `.encrypted` against a `PDFDocument` stub instead and record why in the notes — do **not** download one |
| (no file) | `Data("not a pdf".utf8)` passed to `PDFReader.read` | throws `PDFReadError.unreadable` |

## Target file layout (additions and changes)

```text
Packages/FilmCore/
  Sources/FilmScript/
    PDFLine.swift          NEW   the frozen six-property value type
    PDFReader.swift        NEW   the only file that `import PDFKit`
    PDFRenderer.swift      NEW   furniture, calibration, blocks, Fountain synthesis
    ScreenplayDocument.swift  CHANGED  + ScreenplayFormat.pdf, + 2 WarningCodes, + PDFReadError
    ScreenplayImporter.swift  CHANGED  + the pdf route and the %PDF- sniff
  Sources/FilmCore/
    Domain/Project.swift      CHANGED  FilmCoreVersion.bundleSchema 2 → 3
    Storage/ProjectMigrator.swift CHANGED  + registerV3 and the "v3" closure
    Storage/SchemaV3.swift    NEW   the v3 rebuild DDL (SchemaV2.swift untouched)
    Storage/UpgradeSummary.swift  CHANGED  + BundleInspection.needsOneWayUpgrade
    Storage/ProjectDatabase.swift CHANGED  doc comment only; the `== 1` gate stays
  Sources/ScreenplaySamples/
    ScreenplaySamples.swift   CHANGED  + pdf / pdfParseAnswerKey (defaulted), + tags
    Resources/structure-piece.pdf              NEW  generated, committed
    Resources/structure-piece.pdf.parse.json   NEW  byte-exact key
    Resources/README.md       CHANGED  how structure-piece.pdf is regenerated
  Tests/FilmScriptTests/
    PDFReaderTests.swift      NEW   extraction, the three errors, determinism, the twin
    PDFRendererTests.swift    NEW   calibration, furniture, gaps, warnings, A4
    PDFFixtureBuilder.swift   NEW   test-only CoreGraphics fixture generator
    PDFSampleGenerator.swift  NEW   test-only, FILMCAMP_UPDATE_PDF_SAMPLE=1
    ExpectedParseSupport.swift CHANGED + "pdf", the key-name branch, excludedNames
    Samples/adversarial/pdf-*.pdf + their .pdf.parse.json   NEW  (contract H)
  Tests/FilmCoreTests/
    ProjectMigrationTests.swift  CHANGED  + the v3 suite, versions 2 → 3
    ProjectBundleTests.swift     CHANGED  bundleSchemaVersion → 3
    ScreenplayImportTests.swift  CHANGED  + importing structure-piece.pdf end to end
  Tests/ScreenplaySamplesTests/SampleResourceTests.swift CHANGED  + the pdf pair
AI Film Camp/
  App/AppServices.swift     CHANGED  allowedExtensions + "pdf", allowedContentTypes + .pdf
  App/AppCoordinator.swift  CHANGED  :160 and :228 gate on needsOneWayUpgrade
  Tests/AppShellTests.swift CHANGED  toVersion 2 → 3, pdf accepted, no modal at schema 2
scripts/finder-smoke.sh     CHANGED  user_version 2 → 3
.gitattributes              CHANGED  + `*.pdf binary`
docs/plans/006-evaluation-scorer.md CHANGED  the two factual couplings of contract E5
docs/plans/README.md        CHANGED  + the Plan 008 row and its dependency note
docs/IMPLEMENTATION_NOTES.md CHANGED + the Plan 008 section (Step 6)
```

`Package.swift`, `Package.resolved`, and `project.yml` are **unchanged** —
PDFKit is a system framework (§3.2a) and PDF's UTI is a system type (contract F3).
`SchemaV2.swift` is unchanged (contract E1). No file is deleted.

## Existing tests that break, and how each is rewritten

| File | Change |
|---|---|
| `FilmCoreTests/ProjectMigrationTests.swift` | Nine assertions move (contract E4 names each by line): `:10`'s test name, `:23`/`:24`, `:59`, `:80`, `:87`, `:100`; the newer-version fixture at `:35` writes `user_version = 4` instead of `3` — **at schema 3 a `3` is no longer newer, so this test would pass vacuously if only the expectation were edited** — and `:42` expects `.newerProjectVersion(found: 4, supported: 3)`. **Adds** the contract E3 v2 → v3 suite. The `script.parserVersion == "1"` assertion at `:94` is **kept** (contract A does not bump the parser version), as are the v1-fixture `1`s at `:74`, `:79`, `:265`, `:275`. |
| `FilmCoreTests/ProjectBundleTests.swift:29` | `project.bundleSchemaVersion == 2` → `3`. |
| `AI Film Camp/Tests/AppShellTests.swift` | `:238`'s `summary.toVersion` `2` → `3`; `:209`–`:211`'s v1 assertions stay. **Adds** that `ScreenplayOpenPanelDelegate` enables a `.pdf` URL, that a schema-**2** bundle has `needsOneWayUpgrade == false` and opens with **no** modal and **no** upgrade sheet, and that a schema-**1** bundle still has `needsOneWayUpgrade == true` (contract E2). |
| `ScreenplaySamplesTests/SampleResourceTests.swift` | the resolves-every-file loop includes the pdf pair; the frozen-naming test covers `pdf`/`pdfParseAnswerKey`; `structure-piece`'s tag list grows. |
| `FilmScriptTests/ExpectedParseTests.swift` | unchanged in body — it iterates `ExpectedParseSupport.inputs`, which now includes the PDFs — but `corpusIsSane` asserts the two throwing PDF fixtures are excluded alongside `fdx-malformed.fdx`. |
| `scripts/finder-smoke.sh` | line 86's `"2"` → `"3"`. Nothing else in the smoke path changes; the recorded automation flow still imports `camp-signal.fountain`. |

## Steps

Commit after each step whose verification passes. `swift test --package-path
Packages/FilmCore [--filter <SuiteName>]` runs any suite named below.

**Ordering rule the executor must respect**: Steps 1 and 2 add
`ScreenplayFormat.pdf` while `scripts.format`'s `CHECK` still forbids `'pdf'`, so
neither step may add a FilmCore test that imports a PDF into a project. That test
belongs to Step 3, after the `CHECK` widens. The package is green at every step
regardless.

### Step 1: The PDF reader, renderer, and the import route

Add `.gitattributes`' `*.pdf binary` line **before any PDF is committed**. Add
`ScreenplayFormat.pdf`, the two `WarningCode` cases, `PDFReadError`, `PDFLine`,
`PDFReader`, and `PDFRenderer` per contracts A and B, and the contract C sniff.
Add `PDFFixtureBuilder` and the contract H fixtures, `PDFReaderTests`
(extraction geometry, the three error cases, in-process determinism), and
`PDFRendererTests` (calibration, cluster merging, anchor collision, furniture
including the decoy, gap-derived blocks, both once-per-document warnings, and the
A4 fixture rendering identically to the Letter one). No answer key is committed
yet — Step 2 does that — so the fixtures are asserted structurally here.

**Verify**:

```bash
grep -rl 'import PDFKit' Packages/FilmCore/Sources/FilmScript   # exactly PDFReader.swift
! grep -rq 'PDFDocument\|PDFPage\|PDFSelection' \
    Packages/FilmCore/Sources/FilmScript/PDFLine.swift \
    Packages/FilmCore/Sources/FilmScript/PDFRenderer.swift
! grep -rq 'import GRDB\|import FilmCore\|import SwiftUI' Packages/FilmCore/Sources/FilmScript
git diff --quiet -- Packages/FilmCore/Package.resolved Packages/FilmCore/Package.swift
swift test --package-path Packages/FilmCore \
  --filter PDFReaderTests --filter PDFRendererTests --filter ExpectedParseTests
git diff --quiet -- 'Packages/FilmCore/**/*.parse.json'
```

Expected: `import PDFKit` appears in `PDFReader.swift` and nowhere else; no PDFKit
type is named in the renderer or the value type; `FilmScript` still imports
neither GRDB, FilmCore, nor SwiftUI; the manifest and `Package.resolved` are
untouched. Extraction reports six normalized properties per line with
`topFraction` growing downward; `Data("not a pdf".utf8)` → `.unreadable`, the
encrypted fixture → `.encrypted`, the no-text-layer fixture → `.noTextLayer`,
each checked before the next. Calibration finds four clusters on
`pdf-standard.pdf` and assigns them to the four anchors; `pdf-a4.pdf` renders
byte-identical text; furniture is dropped and the decoy `12` survives as
dialogue; `unclassifiedMargin` and `dualDialogueColumnsDetected` each appear
exactly once; reading the same bytes twice encodes identically. **The last
command is the contract D1 proof**: adding two `WarningCode` cases and a
`ScreenplayFormat` case moved no committed byte.

### Step 2: PDF answer keys in `ExpectedParseSupport`

Add `"pdf"` to `inputExtensions`, the `pdf` branch to `expectedURL(for:)`, and
`pdf-no-text-layer.pdf` / `pdf-encrypted.pdf` to `excludedNames`. Generate the
`.pdf.parse.json` for every non-throwing adversarial fixture with the existing
writer, then **read each one** — an answer key is a contract, not a snapshot of
what the classifier happened to do. Confirm the rendered `sourceText` in each key
is the Fountain a human would have written for that page.

**Verify**:

```bash
FILMCAMP_UPDATE_EXPECTED=1 swift test --package-path Packages/FilmCore \
  --filter ExpectedParseTests || true          # regenerates, then fails by design
swift test --package-path Packages/FilmCore --filter ExpectedParseTests
git diff --quiet -- 'Packages/FilmCore/**/*.parse.json'
git check-attr binary -- Packages/FilmCore/Tests/FilmScriptTests/Samples/adversarial/pdf-standard.pdf
swift test --package-path Packages/FilmCore
```

Expected: the update run writes only the new `pdf-*.pdf.parse.json` files and
fails with the update message; the verifying run passes and every input — old and
new — matches byte-for-byte; the final `git diff --quiet` exits 0, proving the
verifying run wrote nothing; `git check-attr` reports `binary: set`; the whole
FilmCore package is green.

### Step 3: Migration v3 and the schema 2 → 3 ripple

Implement contract E: `SchemaV3.swift`, `registerV3` and the `"v3"` closure
(`_v3` temp tables, `MigrationOutcomeBox` untouched), `bundleSchema = 3`,
`BundleInspection.needsOneWayUpgrade`, the `toVersion` fix, the contract E3
migration suite, and **every** row of the contract E4 table — including the two
`docs/plans/006` edits of contract E5. Add the end-to-end FilmCore test that
imports a PDF into a project; `structure-piece.pdf` does not exist until Step 5,
so use `pdf-standard.pdf` from the adversarial directory here and let Step 5
re-point it.

**Verify**:

```bash
swift test --package-path Packages/FilmCore --filter ProjectMigrationTests
swift test --package-path Packages/FilmCore
grep -rn "user_version\|bundle_schema_version\|bundleSchema" \
  Packages/FilmCore/Sources Packages/FilmCore/Tests "AI Film Camp" scripts \
  | grep -v 'SchemaV2.swift' | grep -E '= ?.?2.?$|== 2|"2"'
! grep -rn 'needsUpgrade' "AI Film Camp/App"
grep -n 'bundleSchemaVersion' docs/plans/006-evaluation-scorer.md
./scripts/finder-smoke.sh
```

Expected: a v1 bundle migrates straight through to `user_version = 3` with the
Plan 003 assertions intact and `upgradeSummary.toVersion == 3`; a v2 bundle
migrates with **every** table's row count unchanged, a clean `PRAGMA
foreign_key_check`, `index_scripts_on_project_id` restored,
`SchemaV2.requiredIndexes` still satisfied, `'pdf'` accepted by the widened
`CHECK` and a bogus format still rejected, `upgradeSummary == nil`, and
`needsOneWayUpgrade == false`; a bundle at `user_version = 4` is refused as
`.newerProjectVersion(found: 4, supported: 3)` without mutation. The first `grep`
prints **nothing** — no stale `2` survives outside `SchemaV2.swift` and the
historical `"v1"`/`"v2"` closures (a hit inside one of those, or inside the
committed v1 fixture, is correct and stays; anything else is a miss). The
`needsUpgrade` grep prints nothing: the app now gates on `needsOneWayUpgrade`.
The 006 grep shows `3`, not `2`. `finder-smoke.sh` passes against `"3"`.

### Step 4: The app's import surface

Implement contract F: the two collection additions, the modal-gate switch at
`AppCoordinator.swift:160`/`:228`, the format label, and the warning messages. Add
the `AppShellTests` cases (a `.pdf` URL is enabled by the panel predicate and by
the drop predicate; a schema-2 bundle opens with **no** modal and **no** upgrade
sheet; a schema-1 bundle still shows the modal). Confirm — do not assume — that
the drop target reads `ScreenplayOpenPanelDelegate.allowedExtensions` rather than
a second literal list.

**Verify**:

```bash
git diff --quiet -- project.yml "AI Film Camp/Resources/Info.plist"
! grep -rq 'com.adobe.pdf' project.yml
xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" \
  -derivedDataPath .build/DerivedData -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
./scripts/finder-smoke.sh
```

Expected: `project.yml` and the generated `Info.plist` are untouched and no
`com.adobe.pdf` declaration was added — PDF's UTI is a system type (contract F3),
which is the one place this plan deliberately does *less* than Plan 004 did for
`.fountain`/`.fdx`. The app builds and its tests pass; the panel and the drop
target both accept `.pdf`; the summary sheet renders `PDF`; the schema-1 bundle
still raises the one-way modal while the schema-2 bundle raises nothing at all;
the smoke script is still green.

### Step 5: `structure-piece.pdf`, its key, and the twin assertion

Add `PDFSampleGenerator` (contract G2/G3), generate
`Resources/structure-piece.pdf`, generate its `.parse.json` with the Step 2
writer, and **read both** — the PDF by opening it in Preview to confirm it looks
like a screenplay, the key by inspection. Add the `pdf`/`pdfParseAnswerKey` fields
and their defaults to `SampleDescriptor`, populate `structure-piece`'s entry and
tags, extend `SampleResourceTests`, add the contract G6 twin assertion to
`PDFReaderTests`, and update `Resources/README.md` with the regeneration command
and the note that the committed PDF's bytes — not the generator's output — are
the artifact of record. Re-point Step 3's FilmCore import test at the sample.

**Verify**:

```bash
FILMCAMP_UPDATE_PDF_SAMPLE=1 swift test --package-path Packages/FilmCore \
  --filter PDFSampleGeneratorTests || true     # writes the PDF, then fails by design
FILMCAMP_UPDATE_EXPECTED=1 swift test --package-path Packages/FilmCore \
  --filter ExpectedParseTests || true
swift test --package-path Packages/FilmCore \
  --filter ExpectedParseTests --filter SampleResourceTests --filter PDFReaderTests
git diff --quiet -- 'Packages/FilmCore/**/*.parse.json'
swift test --package-path Packages/FilmCore
```

Expected: the twin assertion holds — `structure-piece.pdf` and
`structure-piece.fountain` agree on scene count, ordinals, headings, `intExt`,
`timeOfDay`, `sceneNumber`, and per-scene normalized cue sets, while spans differ
and `pdf.sequences` is empty (contract G6). Every descriptor's files resolve,
`structure-piece.pdf` is named `\(name).pdf` and its key `\(name).pdf.parse.json`,
every tag is lowercase-hyphenated, and the descriptor order is unchanged. The
verifying run writes nothing.

### Step 6: Human acceptance, full verification, and notes

Import the operator's own **91-page screenplay PDF** (US Letter, 612×792pt; the
one the reconnaissance above was run against) through the app, into a project
**outside** the repository. The operator names the file at run time; it is never
committed, never copied into the repo, and **its title never appears anywhere in
this repository** — the same all-or-nothing rule §7.1 applies to every operator
screenplay, and Plan 004 Step 4 set the precedent of recording numbers only.

Record in `docs/IMPLEMENTATION_NOTES.md` under a `## Plan 008` heading, **numbers
only, no screenplay text, no title, no path**: page count, scene count, entity
counts, import wall time, the parse warnings raised and their counts, and — per
contract D3 item 4 — the **macOS and Xcode build the committed `.pdf.parse.json`
keys were generated on**. Also record which of §5.4a's limitations were actually
observed: the sequence loss (G6), the missing title page (contract A), and any
centered text that came through as action (B5). Expect roughly **69 scene
headings** from the recon; a materially different count is a finding, not a
rounding error — investigate it before recording it.

**Human-gate deferral policy** (Plan 004's, unchanged): this is the plan's only
human gate and no automated gate depends on it. If the operator has no PDF to
hand when everything else is green, record the deferral in
`docs/IMPLEMENTATION_NOTES.md` and still mark the plan `DONE`.

**Verify**:

```bash
./scripts/verify.sh
./scripts/finder-smoke.sh
./scripts/check-docs.sh
git status --short
! git ls-files | grep -qi 'downloads/\|\.answer-key\.json$'
git ls-files '*.pdf'
```

Expected: `verify.sh` (which itself runs `check-docs.sh`, both package suites, and
the app build and tests) exits 0; only intentional source, script, sample, and
documentation changes are listed; no `.aifilm` package, operator screenplay,
DerivedData, log, or secret is staged. `git ls-files '*.pdf'` lists **exactly**
the synthetic fixtures and `structure-piece.pdf` — nothing else, and nothing
whose name is a screenplay title.

## Done criteria

- [ ] `swift test --package-path Packages/FilmCore`, `./scripts/verify.sh`,
  `./scripts/finder-smoke.sh`, and `./scripts/check-docs.sh` all exit 0;
  `Package.swift`, `Package.resolved`, `project.yml`, and
  `AI Film Camp/Resources/Info.plist` are **unchanged**.
- [ ] `FilmScript` exposes exactly the contract A additions, all `public` and
  `Sendable`, with `PDFLine`'s six stored properties as frozen; `import PDFKit`
  appears only inside `PDFReader.swift`; no PDFKit type appears in any public
  signature; `FilmScript` still imports neither GRDB, FilmCore, nor SwiftUI.
- [ ] Every §5.4a rule holds and is tested: fraction normalization on both axes
  (proved by the A4 fixture rendering identically to the Letter one), the
  0.01-bucket histogram with 2% clusters and neighbour merging, nearest-anchor
  assignment with ascending-order collision fallback, the two-part page-furniture
  predicate with its decoy, the modal-gap blank-line reconstruction with page
  boundaries always breaking, `FDXRenderer`'s exact blank-line rule, and
  `unclassifiedMargin` / `dualDialogueColumnsDetected` raised **once per
  document**.
- [ ] `PDFReadError.unreadable`, `.encrypted`, and `.noTextLayer` each fire on
  their fixture; a PDF is **never** OCR'd and PDF bytes **never** reach the
  UTF-8/UTF-16 decode path; `.pdf` and a leading `%PDF-` both route to `PDFReader`.
- [ ] Adding `ScreenplayFormat.pdf` and the two `WarningCode` cases changed **no**
  committed `.parse.json` byte, proved by a clean `git diff --quiet --
  'Packages/FilmCore/**/*.parse.json'` after a full `ExpectedParseTests` run;
  `FilmScriptVersion.parser` is still `"1"`.
- [ ] Migration `"v3"` is registered, `"v2"` and `SchemaV2.swift` are unedited,
  the `"v3"` closure leaves `MigrationOutcomeBox` alone,
  `FilmCoreVersion.bundleSchema` is `3`, `ProjectDatabase` refuses
  `user_version > 3` (proved with a `4`, not a `3`), and v2 → v3 preserves every
  row count and index with a clean `foreign_key_check`.
- [ ] v2 → v3 is **silent**: `AppCoordinator` gates the one-way modal on
  `needsOneWayUpgrade` (`schemaVersion == 1`) and no longer on `needsUpgrade`,
  `ProjectDatabase`'s `versionBeforeMigration == 1` gate is unchanged, a schema-2
  bundle opens with no modal and `upgradeSummary == nil`, a schema-1 bundle still
  gets both, and a v1 → v3 open reports `toVersion == 3`. Every contract E4 row
  and both contract E5 edits to Plan 006 are done.
- [ ] The open panel and the drop target accept `.pdf`, the summary sheet shows
  format `PDF` and the two new warnings in plain language, **no** UTI is declared
  for PDF, and no parsing, `Process`, GRDB, or Codex argument entered a SwiftUI
  file.
- [ ] `structure-piece.pdf` and `structure-piece.pdf.parse.json` are committed
  with their generator, `SampleDescriptor` carries `pdf`/`pdfParseAnswerKey`
  (defaulted, breaking no consumer), and the twin assertion holds on scenes,
  ordinals, headings, `intExt`, `timeOfDay`, `sceneNumber`, and per-scene
  normalized cue sets, with `pdf.sequences` empty.
- [ ] Every committed PDF is synthetic and has a committed generator; no operator
  or third-party screenplay, and no screenplay title, is anywhere in the
  repository; `docs/IMPLEMENTATION_NOTES.md` carries the Plan 008 acceptance
  numbers (or the recorded deferral) and the macOS/Xcode build the keys were
  generated on.
- [ ] No editing, provenance, lock, scorer, extraction, job-runner, or
  `ProjectTools` mutation change is included; `docs/plans/README.md` carries the
  Plan 008 row marked `DONE`.

## STOP conditions

Stop and report instead of improvising if:

- The design hash differs and §3.2a, §4.2a, §5.4a, §5.5, or §7.1 changed.
- **A `.pdf` answer key differs on a machine whose macOS differs from CI's pinned
  `macos-26` runner.** Do not regenerate it there. Report the two macOS versions,
  the diff, and which side of contract D3 the change falls on. Regenerating a
  PDFKit-induced diff on an unpinned machine would silently make the repository's
  contract depend on one developer's laptop.
- `PDFKit` cannot produce stable per-line geometry for some real screenplay PDF —
  overlapping selections, lines split mid-word, or bounds that move between runs
  in one process. Report the document's *shape* (page size, margin histogram, gap
  histogram) and never its text.
- Margin classification would need a fifth anchor, a per-page recalibration, a
  font-size heuristic, or any signal §5.4a does not name. §5.4a is the contract;
  a document it cannot classify is a finding, not a licence to extend the
  algorithm.
- You are about to make a PDF with no text layer work by adding OCR, Vision, or
  any text-recognition path. It is a §11 non-goal and decision §14.8 refuses it
  explicitly ("Scanned PDFs are refused with a clear message").
- You are about to add a package dependency for PDF reading, layout, or
  generation. §3.2a's whole argument is that PDFKit is a system framework and
  `Package.resolved` does not change.
- You are about to edit the registered `"v2"` migration, `SchemaV2.swift`, or a
  DONE plan (002–004) to make a number agree. §4.2a forbids the first two by
  name; the third is history.
- The v2 → v3 migration would drop a row, drop an index, re-parse a script, or
  trigger the v1 upgrade modal. It is defined as non-destructive and silent
  (§4.2a); any of those means the rebuild is wrong.
- Anyone supplies an operator or third-party screenplay PDF for the corpus. It is
  never committed, never added to `ScreenplaySamples`, and never given a
  `.parse.json` — a key embeds `sourceText` and would publish the script (§7.1).
  It is acceptance material for Step 6 only, and even its **title** stays out of
  the repository.
- A verification command fails twice after one reasonable scoped correction.
- Work expands into editing, provenance, or locks (**005**); the scorer,
  `filmcamp-eval`, or the answer key exporter (**006**); chunked extraction,
  reconcile, or review (**007**); or into title-page extraction, centered-text
  recovery, dual-dialogue column interleaving, or OCR — all four are named
  limitations, not gaps to close here.

## Maintenance notes

- **The PDF answer key is the canary for a system framework we do not version.**
  If `structure-piece.pdf.parse.json` or a `pdf-*.pdf.parse.json` starts failing
  and no line of our code changed, the finding is "PDFKit's extraction changed in
  macOS *X*" — follow contract D3, and record the before/after macOS in
  `docs/IMPLEMENTATION_NOTES.md` so the next person diagnoses it in one look. If
  a bump of `FilmScriptVersion.parser` ever results, note that
  `ProjectMigrationTests.swift:94` hardcodes the literal `"1"` and must become
  `FilmScriptVersion.parser` in the same commit.
- **`structure-piece.pdf` is not byte-reproducible and does not need to be**
  (contract G4). `CGPDFContext` stamps a creation date and file ID. The committed
  bytes are the artifact; the generator exists so the *layout* is auditable and
  regenerable, not so the bytes are stable. Regenerating it is a reviewed change
  that also regenerates its key.
- **Every classification bug found on a real PDF becomes an adversarial fixture
  before it is fixed**, generated by `PDFFixtureBuilder` from synthetic text, with
  its key in the fixing commit — Plan 002's rule, applied to geometry.
- **Named limitations, so a later phase does not rediscover them as bugs**: a PDF
  loses `#` sequences entirely; a PDF title page yields `TitlePage.lines` but
  never parsed `entries` (positional text carries no key/value structure);
  centered text becomes action; dual-dialogue columns
  are rendered sequentially with a warning and no `^`; a scanned PDF is refused.
  Each is a consequence of geometry carrying less than a declared structure, and
  each is accepted by §3.2a's "the honest limitation".
- **Downstream consumers** whose meaning cannot change without updating the
  design section that names them: FilmCore's `importScreenplay` (a `pdf` script
  row, `source_text` = the rendering per §3.3, spans into the rendering and never
  into the file); the app's Reveal in Finder, which is how the filmmaker reaches
  the original `.pdf` under `screenplay/`; Plan 006's scorer and Plan 007's
  chunker, both of which consume `ParsedScene.range` over the rendering exactly as
  they already do for FDX.
- Keep `PDFKit` inside `PDFReader.swift`. The moment a PDFKit type appears in a
  signature, or a second file imports it, `FilmScript`'s `String`/`Data`/`URL`
  boundary (§3.1) has been given up — that is a design change, not a refactor.
