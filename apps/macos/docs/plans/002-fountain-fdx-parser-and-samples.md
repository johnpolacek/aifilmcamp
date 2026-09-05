# Plan 002: Fountain/FDX parser and parser samples (Phase 1a, part 1)

> **Executor instructions**: Read `docs/PHASE1_DESIGN.md` in full first. This
> plan implements its §3.1, §3.2, §3.4 (`DisplayCase` only), §5.1–§5.4, and the
> **parser** samples and byte-exact expected-parse files of §7.1; it writes **no
> answer key** (§7.2, decision §14.4). Pure Swift: **no GRDB, schema change, UI,
> `project.yml` change, or Codex**; `FILMCAMP_RUN_LIVE_CODEX` stays unset. Run
> the steps in order and every verification command; honor the STOP conditions.
> Fully autonomous — no live gate, no human gate, no `BLOCKED` outcome. Requires
> Plan 001 `DONE`; when done, mark this plan `DONE` in `docs/plans/README.md`.
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
> descended from `02cf45c`. If a hash differs, stop for reconciliation when the
> parsing rules (§5), package layout (§3.1), display-name rule (§3.4), or the
> sample/answer key contract (§7) changed.

## Status

- **Status**: DONE (2026-08-19)
- **Priority**: P1
- **Effort**: M–L, approximately 7–10 focused engineering days (parser, FDX
  reader, three original 6–15 page samples, inspecting every expected-parse
  file, adversarial suite)
- **Risk**: MED; Fountain edge cases and FDX rules that no public schema pins
  down. No storage, concurrency, process, account, or human-gate risk here.
- **Depends on**: 001
- **Category**: feature / architecture / tests
- **Planned at**: commit `02cf45c`, 2026-08-18; design hash in the drift check

## Why this matters

Scene boundaries come from the parser, never the model: one deterministic
function from screenplay bytes to a scene list with offsets, in a
dependency-free target. No screenplay carries a license that allows bundling
(§12.1), so the syntax-coverage corpus is authored here from scratch.

## Current state (Plan 001 DONE, commit `02cf45c`)

- `Packages/FilmCore/Package.swift`: product `FilmCore`, dependency `GRDB.swift`
  exact 7.11.1, targets `FilmCore` + `FilmCoreTests`, `.macOS(.v15)`,
  `swiftLanguageModes: [.v6]`, `StrictConcurrency`; **no resources declared**.
- The repo's only screenplay is `AI Film Camp/Resources/Samples/
  camp-signal.fountain`; `project.yml` line 27 ships that directory as an app
  resource and `ProjectBundle.create(at:name:sampleURL:)` copies it into new
  bundles. **Copy, never move** it; Plan 004 deletes the app-side copy (Plan 003
  still uses it for its retargeted smoke).
- `scripts/verify.sh` already runs `swift test --package-path Packages/FilmCore`,
  which runs **every** test target, so **it needs no change** — a done criterion,
  not an oversight. Package tests use Swift Testing.
- Toolchain pins unchanged: Xcode 26.6, Swift 6, macOS 15 floor, XcodeGen
  2.46.0, GRDB 7.11.1, swift-json-schema 0.13.1, `macos-26` runner.

## Contracts (normative)

### FilmScript target and public API

New library target and product `FilmScript`, **no dependencies** (§3.1):
Foundation internal only (`XMLParser`, `Data`, `JSONEncoder`), public API
limited to `String`/`Data`/`URL`. Every type is `public` and `Sendable`; every
struct `Codable` + `Equatable` (`UTF16Range` also `Hashable`). Value enums
(`ScreenplayFormat`, `IntExt`, `ElementKind`, `WarningCode`) are `String`-raw
`Codable`; error enums (`ScreenplayLoadError`, `FDXReadError`) are `Error,
Equatable`, never raw-valued, and carry associated values where the case needs
them. Names, cases, and stored properties are contracts:

```swift
enum ScreenplayFormat: String { case fountain, fdx, text }
enum IntExt: String { case int, ext, intExt = "int_ext", unknown }   // the other value enums are String-raw too
enum ElementKind: String { case sceneHeading, action, character, parenthetical, dialogue,
      transition, centered, section, synopsis, note, boneyard, pageBreak, lyric }
enum WarningCode: String { case noSceneHeadings, emptyDocument, unterminatedBoneyard,
      unterminatedNote, duplicateSceneNumber, dualDialogueWithoutPrimary,
      unsupportedParagraphType }

struct UTF16Range { let start: Int; let end: Int }              // half-open, into sourceText
struct ScreenplayDocument { let format: ScreenplayFormat; let sourceText: String  // normalized
      let titlePage: TitlePage; let sequences: [ParsedSequence]  // `#` sections; may be empty
      let scenes: [ParsedScene]; let warnings: [ParseWarning] }  // optional scene 0, then 1...n
struct TitlePage { let entries: [Entry]                          // Fountain key/value, ordered; empty for FDX
      let lines: [String]                                        // Fountain: the block's non-blank source lines verbatim; FDX: the only populated field
      struct Entry { let key: String; let value: String; let range: UTF16Range } }   // non-optional: FDX has no entries
struct ParsedSequence { let ordinal: Int; let title: String
      let depth: Int; let range: UTF16Range }                    // `#` = 1, `##` = 2, ...
struct ParsedScene { let ordinal: Int                            // 0 = preamble, then 1...n
      let heading: String                                        // no `#12A#`, no forcing `.`
      let intExt: IntExt; let locationText: String; let timeOfDay: String  // "" when absent
      let sceneNumber: String?                                   // author number; never orders
      let sequenceOrdinal: Int?; let range: UTF16Range           // owning sequence per §5.2
      let elements: [ParsedElement]
      let cues: [ParsedCue]                                      // EVERY cue occurrence, document order (not deduped)
      let isOmitted: Bool }
struct ParsedElement { let kind: ElementKind; let range: UTF16Range; let text: String }
struct ParsedCue { let raw: String; let normalized: String; let extensions: [String]
      let range: UTF16Range; let isDual: Bool }
struct ParsedHeading { let heading: String; let intExt: IntExt; let locationText: String
      let timeOfDay: String; let sceneNumber: String?; let isOmitted: Bool }
struct FDXParagraph { let type: String; let text: String         // reader → renderer only
      let number: String?; let isDualSecond: Bool }
struct ParseWarning { let code: WarningCode; let message: String; let range: UTF16Range? }

enum TextNormalization { static func normalize(_ raw: String) -> String }
enum FountainParser { static func parse(_ text: String, format: ScreenplayFormat) -> ScreenplayDocument }
enum HeadingParser { static func parse(_ headingLine: String) -> ParsedHeading
                     static let timeOfDayTokens: Set<String> }
enum CueNormalizer { static func normalize(_ raw: String) -> (name: String, extensions: [String]) }
enum DisplayCase { static func titleCased(_ raw: String) -> String }
enum FDXReader { static func read(_ data: Data) throws -> ScreenplayDocument }
enum FDXRenderer { static func render(_ paragraphs: [FDXParagraph])
                     -> (text: String, warnings: [ParseWarning], titlePageLines: [String]) }
enum ScreenplayImporter { static func load(url: URL) throws -> ScreenplayDocument }
enum FilmScriptVersion { static let parser: String = "1" }
enum ScreenplayLoadError: Error, Equatable { case unreadable, unsupportedEncoding }
enum FDXReadError: Error, Equatable { case malformed(line: Int, column: Int) }
```

- `FilmScriptVersion.parser` is what Plan 003 writes to `scripts.parser_version`
  (§5.5). **Any commit that changes a committed `.parse.json` must bump it in
  the same commit.** The spelling is frozen: no `version`/`parserVersion` alias.
- `ParsedSequence` is parser-side naming; FilmCore's storage type is
  `ScriptSequence` (§4.4) and mapping is Plan 003's job. `ParsedScene.cues` lists
  **every** cue occurrence in document order — `raw`, `range`, and `isDual` differ
  per occurrence and Plan 003 needs each one for aliases (§3.5, one alias row per
  distinct normalized form), `speaking` appearances, and per-occurrence evidence
  spans (§5.3); grouping by `normalized` is Plan 003's job, never the parser's.
- `UTF16Range` is re-declared in FilmCore (Plan 003) under the same name by design;
  FilmCore's import mapper qualifies this one as `FilmScript.UTF16Range`.
- Every entry point is a `nonisolated static func` over no global mutable state.
  `FDXReader` builds its `XMLParser` and a `final class` delegate inside one
  function body; neither escapes, neither claims `Sendable`.

### Normalization, loading, segmentation (§5.1–§5.3)

- `TextNormalization.normalize`: strip a leading UTF-8 BOM; `\r\n` and lone `\r`
  → `\n`; nothing else. Offsets are computed **after** normalization and
  `sourceText` is always the normalized string. `FountainParser.parse` **requires**
  normalized input and is idempotent over it (it may re-run `normalize` as a
  guard; the result must not change). `ScreenplayImporter.load` normalizes before
  parsing, and `ExpectedParseTests` goes through `load(url:)`, never `parse`
  directly, so the CRLF/BOM samples exercise the real path.
- `ScreenplayImporter.load(url:)`: decode UTF-8 (BOM or not), else UTF-16 when a
  UTF-16 BOM is present, else throw `.unsupportedEncoding` — no lossy fallback.
  Sniff `.fdx` → `.fdx`, `.fountain`/`.spmd` → `.fountain`, `.txt` → `.text`,
  any other extension → `.fdx` when the first non-whitespace bytes are `<?xml`
  or `<FinalDraft`, else `.text`. Only `.fdx` goes to `FDXReader`. Blocks on
  file I/O; Plan 003 calls it off the main actor.

Refinements beyond §5.1–§5.3, fixed here so the answer keys are stable (§5.1's
"rules the plans must not have to guess" are normative and repeated only where
this plan adds detail):

- **Title page** (§5.1): exists only when the first non-blank line of the
  normalized text matches `^[A-Za-z][A-Za-z ]*:`; the block runs to the first
  blank line; indented continuation lines append to the previous value (joined
  with `\n`); `FADE IN:` is never a key; `Entry.range` covers the key line through
  its last continuation line (FDX has no entries at all, so the range is
  non-optional); `TitlePage.lines` holds the block's non-blank source lines
  verbatim in order (continuation lines as separate elements) — for FDX it is
  the only populated field. The body — and every offset rule below — starts
  after the blank line that ends the block, at offset 0 when there is no title
  page, or at end of text when the block runs to EOF (then the body is empty
  and the empty-body rule applies). Plan 003 stores the whole `TitlePage` object
  in `scripts.title_page_json` (§4.3's `'{}'` default is an empty object).
- **Notes and boneyard** (§5.1): `[[ ]]` and `/* */` spans are excised **before**
  line classification, so a heading or cue inside a boneyard starts nothing; each
  is emitted as its own `note`/`boneyard` element, clipped to every scene it
  overlaps and emitted once per scene (which is what `scene_exclusions` stores);
  unterminated forms warn and run to end of text; `messy-piece.fountain`'s
  unterminated boneyard is therefore its **last** construct. They are excluded
  from every other element's text. Plan 003 persists each as a `scene_exclusions`
  row (§4.3) and Plan 007's chunker subtracts them via
  `ProjectReading.sceneExclusions(id:)` (§8.2) — nothing outside FilmCore ever
  re-parses. Never drop these elements; never add a "clean text" field.
- **Heading**: first body line, or preceded by a blank line, matching a §5.1
  prefix then `.` or whitespace; or forced with one leading `.` not followed by
  another. A trailing blank line is **not** required. `EST.` → `.ext`; `I/E`,
  `INT./EXT.`, `INT/EXT` → `.intExt`. A forced heading is `intExt = .unknown`
  unless its text after the dot starts with a prefix. `heading` drops the forcing
  dot and the `#…#` number; `range` still starts at the line's first character.
- **Cue**: preceded by a blank line, followed by a non-blank line, no lowercase
  letter outside trailing parenthesized extensions **except** the interior of a
  leading `Mc`/`Mac`/`O'` (`McKAY`, `MacLEOD`, `O'BRIEN` are cues — §5.1), not a
  heading or transition, not purely punctuation/digits, not ending in `:`
  (`FADE IN:` followed by action is never a cue); or forced with `@`. A
  trailing `^` sets `isDual`; a `^` cue with no preceding dialogue block in the
  scene warns `dualDialogueWithoutPrimary`.
- **Transition**: all-caps line ending in `TO:` between blank lines, or forced
  with `>` when the line does not also end with `<` (that is centered text).
- **Synopsis vs page break** (§5.1): a line starting with a single `=` is a
  `synopsis` element; a line of three or more `=` is a `pageBreak`. Synopses are
  parsed and kept as elements; Plan 003 deliberately does not write them to
  `scenes.synopsis`.
- **Preamble**: scene `ordinal 0` only when it holds at least one `action`,
  `dialogue`, `centered`, or `lyric` element (§5.2 counts the last two as
  action); its range starts at the first character of the body (after the title
  page); heading ordinals 1…n are assigned either way.
- **No headings**: the §5.3 `UNTITLED` fallback also sets `locationText = ""`,
  spans the whole body, and produces no scene 0; an **empty body** yields that
  same single `UNTITLED` scene (empty range) plus both `noSceneHeadings` and
  `emptyDocument` — a document always has at least one scene (§5.3).
- **Sequences**: assignment per §5.2; `depth` = count of `#`; `ordinal` is
  contiguous from 1 in document order across **all** depths (never a per-depth
  counter — it feeds `sequences.UNIQUE(script_id, ordinal)`); `title` is the line
  after the leading `#` run, trimmed; a sequence's
  `range` runs from the start of its `#` line to the start of the next section of
  the same or shallower depth, or end of text (§5.2).
- Duplicate author scene numbers warn and are kept; `structure-piece` contains
  one deliberately.
- `CueNormalizer.normalize`: trim; strip a leading `@` and a trailing `^`; peel
  every trailing parenthesized group into `extensions` (uppercased, apostrophes
  folded to `'`, parentheses removed, order kept); collapse internal whitespace;
  uppercase the remainder; strip trailing `.,;:`. `SARAH`, `SARAH (V.O.)`,
  `SARAH (CONT'D)`, `SARAH (V.O.) (CONT'D)`, `@Sarah`, and `SARAH ^` all
  normalize to `SARAH`; it never merges different names (`SARAH` vs
  `SARAH MORGAN` stay distinct).
- `HeadingParser.timeOfDayTokens` is exactly the §5.2 list, compared after
  trimming and after peeling one **trailing** parenthesized group, so
  `NIGHT (LATER)` matches on `NIGHT`; `timeOfDay` stores the full segment as
  authored (`NIGHT (LATER)`), never the bare token. Only the **last** ` - `,
  ` – `, or ` — ` segment is considered; a heading whose last segment is not a
  token keeps the whole remainder as `locationText` with `timeOfDay = ""`.
  `locationText == "OMITTED"` sets `isOmitted`.

### DisplayCase (§3.4)

Whitespace runs collapse to one space, result trimmed. Each whitespace token
splits on `-`, `'`, `.`, `/` keeping delimiters; each part takes the **first**
matching rule: (1) no cased letter → unchanged (`#2`, `&`); (2) all-uppercase,
length ≤ 4, only the letters `I V X L`, strict roman-numeral pattern → unchanged
(`II`, `XIV`); (3) begins with `MC`/`Mc` or `MAC`/`Mac` (any case) with ≥ 3
letters → `Mc`/`Mac` + title-cased remainder (`MCKAY`, `McKAY` → `McKay`;
`MACLEOD`, `MacLEOD` → `MacLeod`); (4) contains a lowercase
letter at index ≥ 1 → unchanged, preserving authored interior capitals
(`DeVries`); (5) otherwise first letter uppercased, rest lowercased. The
apostrophe rule **overrides** the numbered rules for the part right after an
apostrophe: lowercased when it is a single letter (`SARAH'S` → `Sarah's`),
title-cased otherwise (`O'BRIEN` → `O'Brien`). Must hold:
`SARAH'S APARTMENT` → `Sarah's Apartment`; `JEAN-LUC` → `Jean-Luc`; `J.T.` →
`J.T.`; `MAN #2` → `Man #2`; `ACT II` → `Act II`; `MacLEOD` → `MacLeod`. Tested
from a committed table.

### FDX (§5.4)

`FDXReader` uses Foundation `XMLParser` (SAX) and implements §5.4 exactly; read
§12.1 first. These rules are reverse-engineered and non-negotiable:

- Walk `/FinalDraft/Content` **direct-child** `Paragraph` elements with an
  explicit depth counter (SAX re-entry), descending into `DualDialogue` only —
  `SceneProperties/Summary`, `SceneArcBeats`, and `ScriptNote` are metadata and
  must never reach the body.
- Renderings per §5.4: `Shot`, `General`, `Cast List`, `End of Act`/`End Of Act`,
  `Act Info`, `Show/Ep. Title` → action (recognized, no warning); `Lyrics` → `~`
  line; `Sequence`/`New Act`/`Cold Opening` → `#` section; `Summary`, `Note`,
  `Outline *` → Fountain note/boneyard; `fdx-features.fdx` carries a top-level
  `Note` and an `Outline 1` paragraph so that path is exercised.
- Absent `Paragraph@Type` → `Action`; unknown type → action plus
  `unsupportedParagraphType`; never drop a paragraph.
- Paragraph text = **direct** `Text` children, **no separator, no trimming**,
  accumulated across `foundCharacters` calls.
- Scene number is `Paragraph@Number`, never `SceneProperties`; it renders as the
  `#N#` suffix.
- `TitlePage` is excluded from `sourceText`; its non-empty lines become
  `TitlePage.lines` in order (`entries` stays empty for FDX).
- Rendering emits forced `.`/`@`/`> ` markers only when the text would not
  otherwise parse as that element; it is deterministic, and the rendered text
  goes through `FountainParser.parse(_:format: .fdx)` — one scene contract.
- Malformed XML throws `FDXReadError.malformed(line:column:)` from the parser's
  reported position. UTI `com.finaldraft.fdx` is declared by Plan 004 as an
  imported type — no `project.yml` change here or in Plan 003.

### ScreenplaySamples target

New library target and product in the same package. SwiftPM rejects a
resource-only target and `Bundle.module` is internal, so it carries exactly one
Swift file with a public accessor:

```swift
public enum ScreenplaySamples {
  public static func url(named fileName: String) -> URL     // "structure-piece.fountain"
  public static let all: [SampleDescriptor]                // stable order, see table
}
public struct SampleDescriptor: Sendable, Hashable {       // all `public let`
  name: String; screenplay: String; finalDraft: String?; parseAnswerKey: String
  finalDraftParseAnswerKey: String?
  syntaxCoverage: [String]                                  // lowercase-hyphenated tags, non-empty
}
```

- `syntaxCoverage` names what the sample exercises (`"forced-heading"`,
  `"dual-dialogue"`, `"boneyard-unterminated"`, …); it is data for
  `SampleResourceTests`, not for the parser.
- Resources are declared `.copy("Resources")` (not `.process`) so the directory
  survives; lookup is `Bundle.module.url(forResource:withExtension:
  subdirectory: "Resources")`.
- **Frozen signature**: `url(named fileName: String)` takes the **full filename
  with extension** (`"camp-signal.fountain"`), never a stem, and **traps** on a
  missing file — a packaging error, not a runtime one. Plans 003, 004, and 006
  call it and `FilmScriptVersion.parser` verbatim; add no stem overload, no
  optional-returning variant, no renamed label.

Contents of `Sources/ScreenplaySamples/Resources/`, and the order of `all` after
`camp-signal`:

| File(s) | Purpose — the syntax it covers |
|---|---|
| `README.md` | states these are original synthetic works authored for this repo for **parser syntax coverage**, that no commercial or third-party screenplay text is committed (§12.1), that the operator's own screenplays are never added here (§7.1), and how `.parse.json` answer keys are regenerated |
| `camp-signal.fountain`, `.parse.json` | byte-identical **copy** of the Phase 0 sample: `Title:`/`Credit:` title page, two plain `INT.`/`EXT.` headings with `NIGHT`, two cues |
| `structure-piece.fountain`, `.parse.json` | §7.1 sample 1 — `INT./EXT.`, `EST.`, forced headings, `#12A#` scene numbers including one **duplicate** (`duplicateSceneNumber`), `CONTINUOUS` and `LATER`, a `#`/`##` section structure (sequences) with a section starting mid-scene, a `=` synopsis and a `===` page break, and a `FADE IN:` + action preamble before the first heading (no title page) |
| `dialogue-piece.fountain`, `.parse.json` | §7.1 sample 2 — `(V.O.)`, `(O.S.)`, `(CONT'D)`, forced `@` cues, a dual-dialogue block, parentheticals, lyrics, centered text, transitions |
| `messy-piece.fountain`, `.parse.json`, `messy-piece.fdx`, `messy-piece.fdx.parse.json` | §7.1 sample 3 — notes `[[ ]]`, a boneyard `/* */` that spans a heading (which therefore starts no scene), an unterminated boneyard as the **last** construct, CRLF and BOM, smart quotes, a heading with no time of day, a lowercase heading, `OMITTED`, a `McKAY` cue. The FDX twin is hand-authored minimal valid FDX, **never** exported from Final Draft; it has no CRLF/BOM/boneyard equivalents (so it simply **omits** the boneyard-spanned heading), and "the same" means: scene count, ordinals, headings, `intExt`, `timeOfDay`, `sceneNumber`, and per-scene normalized cue sets agree (spans may differ), asserted in `FDXReaderTests` |
| `messy-piece-no-headings.fountain`, `.parse.json` | the "body with no heading at all" §7.1 lists under sample 3; ships as a one-page companion exercising the §5.3 `UNTITLED` + `noSceneHeadings` fallback |

The three pieces are 6–15 pages each (§7.1); `structure-piece` needs enough
headings to make sequence assignment and duplicate scene numbers observable.
Syntax, not story: no planted ambiguity, nicknames, or continuity puzzles.

### Parse answer key format (frozen)

- `*.parse.json` is the JSON encoding of `ScreenplayDocument` with
  `JSONEncoder.outputFormatting = [.sortedKeys, .prettyPrinted,
  .withoutEscapingSlashes]`, UTF-8, `\n` endings, one trailing newline; the test
  compares **bytes**, not decoded values.
- These are the only answer keys this plan produces; the §7.2 answer key is
  *derived* later by Plan 006's `filmcamp-eval save-answer-key <bundle> --out
  <answer-key.json>`. Do not hand-author one and do not freeze a format for one
  (decision §14.4).
- **Regeneration**: `ExpectedParseTests` writes instead of asserting when
  `FILMCAMP_UPDATE_EXPECTED=1` is set (source directory from `#filePath`,
  test-only), then **fails** ("answer keys updated; re-run without
  FILMCAMP_UPDATE_EXPECTED to verify") so no CI run passes by rewriting the
  contract. Without the variable it never writes.

## Target file layout (additions only)

```text
Packages/FilmCore/
  Package.swift                                    + 2 products, 2 targets, 2 test targets
  Sources/FilmScript/
    ScreenplayDocument.swift  TextNormalization.swift  FountainLineClassifier.swift
    FountainParser.swift      HeadingParser.swift      CueNormalizer.swift
    DisplayCase.swift         FDXParagraph.swift       FDXReader.swift
    FDXRenderer.swift         ScreenplayImporter.swift
  Sources/ScreenplaySamples/ScreenplaySamples.swift + Resources/… (table above)
  Tests/FilmScriptTests/     suites: TextNormalizationTests, HeadingParserTests,
    CueNormalizerTests, DisplayCaseTests, FountainParserTests, FDXReaderTests,
    ExpectedParseTests, ParserPerformanceTests
    ExpectedParseSupport.swift (test-only answer key writer),
    Samples/display-case.json, Samples/adversarial/*.{fountain,fdx,txt,parse.json}
    (ExpectedParseSupport resolves `../../Sources/ScreenplaySamples/Resources/` from `#filePath`
    for the sample keys)
  Tests/ScreenplaySamplesTests/SampleResourceTests.swift
.gitattributes   NEW: `*.fountain -text` and `*.fdx -text`, so no `core.autocrlf`
                 setting rewrites the CRLF/BOM samples and breaks their byte-exact keys
```

`Package.swift` edits — the **cumulative end state**, applied in two steps
because SwiftPM rejects a target whose source directory does not exist yet.
**Step 1** adds `.library(name: "FilmScript", targets: ["FilmScript"])` to
`products`, `.target(name: "FilmScript", swiftSettings:
[.enableUpcomingFeature("StrictConcurrency")])` with **no `dependencies:`**,
`.testTarget(name: "FilmScriptTests", dependencies: ["FilmScript"], resources:
[.copy("Samples")])`, `"FilmScript"` to the existing `FilmCore` target's
`dependencies` beside the GRDB product (no FilmCore source imports it here — the
edge is added now so Plan 003 adds only its own test resources), and
`"ScreenplaySamples"` to `FilmCoreTests`' `dependencies` (Plan 003's
`createWithScript()` calls it). **Step 3** adds `.library(name:
"ScreenplaySamples", targets: ["ScreenplaySamples"])`, `.target(name:
"ScreenplaySamples", resources: [.copy("Resources")], swiftSettings:
[...same...])`, `.testTarget(name: "ScreenplaySamplesTests", dependencies:
["ScreenplaySamples"])`, and `"ScreenplaySamples"` to `FilmScriptTests`'
dependencies. `dependencies`, `platforms`, and `swiftLanguageModes` are
unchanged; `Package.resolved` must not change. `project.yml` and `.gitignore` are untouched
(`.gitattributes` is new): every file added is `.fountain`, `.fdx`, `.json`, or
`.md`, and the app links neither new product until Plan 004.

## Steps

Commit after each step whose verification passes; `swift test --package-path
Packages/FilmCore [--filter <SuiteName>]` runs any suite named below.

### Step 1: Target, normalization, heading/cue/display-case

Create `.gitattributes` (`*.fountain -text`, `*.fdx -text`) **before any sample
is committed**, then add the Step 1 manifest edits, the target and product, the
value types, `TextNormalization`, `HeadingParser`, `CueNormalizer`,
`DisplayCase`, their unit tests, and
`Tests/FilmScriptTests/Samples/display-case.json` (≥ 40 input/output pairs
covering every rule and example above).

**Verify**:

```bash
swift package describe --package-path Packages/FilmCore | grep -c FilmScript
! grep -rq 'import GRDB\|import FilmCore\|import SwiftUI' Packages/FilmCore/Sources/FilmScript
swift test --package-path Packages/FilmCore \
  --filter TextNormalizationTests --filter HeadingParserTests \
  --filter CueNormalizerTests --filter DisplayCaseTests
```

Expected: the manifest names the target and product; the grep finds nothing;
tests cover BOM/CRLF/lone-CR normalization, every heading prefix, `I/E`, forced
headings, all three dashes, `NIGHT (LATER)`, a non-time-of-day ` - ` tail,
`OMITTED`, `#12A#`, every cue form above, the DisplayCase table.

### Step 2: Fountain parser, the expected-parse writer, and adversarial samples

Implement `FountainLineClassifier` and `FountainParser` per §5.1–§5.3 and the
segmentation contract. Add `ExpectedParseTests` and its `ExpectedParseSupport`
writer **now** (it is the generator as well as the checker; every later step
regenerates only the keys for the inputs it adds). Author adversarial samples
under `Tests/FilmScriptTests/Samples/adversarial/`, each with a `.parse.json`
beside it: `preamble`, `preamble-blank-only`, `no-headings`, `empty`,
`nested-sections`, `sections-synopses-pagebreaks`, `heading-variants`
(including `EST.`), `time-of-day`, `cues` (including `McKAY`/`O'BRIEN`),
`dual-dialogue`, `notes-boneyard` (with an unterminated note), `boneyard-spanning-scenes`
(a heading inside the block), `transitions-centered-lyrics`, `crlf-bom-smartquotes`,
`title-page` (including a file whose first line is `FADE IN:`, a multi-line value,
and a title-page-only file), and `plain-text.txt` (a heading-less page loaded
through `ScreenplayImporter.load` → `format == .text` + the `UNTITLED` fallback). Add
`ParserPerformanceTests`: concatenate an adversarial sample deterministically
into a ~30k-word input (longer than any committed sample); assert two parses
encode to identical bytes always, and — only when `FILMCAMP_PERF=1` is set, so
a slow CI runner never fails the suite — that one parse finishes in **under 3 s
in Debug**, a regression ceiling, not a benchmark.

**Verify**:

```bash
swift test --package-path Packages/FilmCore \
  --filter FountainParserTests --filter ExpectedParseTests \
  --filter ParserPerformanceTests
FILMCAMP_PERF=1 swift test --package-path Packages/FilmCore --filter ParserPerformanceTests
git check-attr text -- Packages/FilmCore/Tests/FilmScriptTests/Samples/adversarial/crlf-bom-smartquotes.fountain
FILMCAMP_UPDATE_EXPECTED=1 swift test --package-path Packages/FilmCore --filter ExpectedParseTests || true   # regenerates, then fails by design
```

Expected: preamble with action → scene 0 starting at the body's first character,
blank-only preamble → none; `no-headings` → one `UNTITLED` scene plus
`noSceneHeadings`; `empty` → one empty `UNTITLED` scene plus `noSceneHeadings`
and `emptyDocument`; nested sections give depth 1–3 sequences with the
contracted spans while scenes take the shallowest enclosing section and a
mid-scene section splits nothing; `=` is a synopsis and `===` a page break;
`FADE IN:` opens a preamble, not a title page, and is never a cue; a title-page-only file yields one empty `UNTITLED` scene with both warnings; `plain-text.txt` loads as `.text`; sequence ordinals are contiguous across depths; `McKAY` is a cue; element ranges
and cue occurrence order are as contracted; notes and boneyard appear only as
their own elements, clipped per scene, and a heading inside a boneyard starts no
scene; unterminated boneyard warns; CRLF/BOM/smart quotes parse with offsets into
the normalized text; every adversarial input matches its committed key
byte-for-byte; determinism passes unconditionally and the timing ceiling under
`FILMCAMP_PERF=1`.

### Step 3: Samples target, FDX reader/renderer, and the messy twin

Add the `ScreenplaySamples` target, accessor, `README.md`, and the byte-identical
copy of the Phase 0 sample as `camp-signal.fountain`. Implement `FDXParagraph`,
`FDXReader`, `FDXRenderer`. Author `messy-piece.fountain` and
`messy-piece-no-headings.fountain` to the coverage in the sample table, and
hand-author the twin `messy-piece.fdx` (agreeing on the subset the table names,
minimal valid FDX). Add adversarial `fdx-features.fdx` (nested
`SceneProperties/Summary` and `ScriptNote` paragraphs, a paragraph with no
`Type`, multi-run `Text` with load-bearing boundary spaces, `Paragraph@Number`, a
`DualDialogue` block, `End Of Act`, `Sequence`, an unknown type, empty
paragraphs, tabs, `Text@Style`) and `fdx-malformed.fdx` (truncated XML; it
throws, so it is **excluded** from `ExpectedParseTests` and asserted in
`FDXReaderTests`). Generate the `.parse.json` for every sample added in this
step with the Step 2 writer and read them. Populate `all` for the samples that
exist so far, with their `syntaxCoverage` tags — every descriptor's files exist
at the end of this step. Add `CampSignalParseTests` (in `FilmScriptTests`) for
the Phase 0 sample's parse assertions below.

**Verify**:

```bash
cmp "AI Film Camp/Resources/Samples/camp-signal.fountain" \
  Packages/FilmCore/Sources/ScreenplaySamples/Resources/camp-signal.fountain
swift test --package-path Packages/FilmCore \
  --filter FDXReaderTests --filter CampSignalParseTests \
  --filter ExpectedParseTests --filter SampleResourceTests
```

Expected: `diff` silent and the app copy still present (Plan 004 removes it);
every file named by every `SampleDescriptor` resolves, names are unique, every
`syntaxCoverage` is non-empty and lowercase-hyphenated, and `all` is in the
table's order; `camp-signal.fountain` parses to 2 scenes
(`INT. CAMP CABIN - NIGHT`, `EXT. CAMP DOCK - NIGHT`, both `NIGHT`), cues
`MAYA` and `ELI`, title-page entries `Title` and `Credit`, no scene 0; the twins
agree on scene count, ordinals, headings, `intExt`, `timeOfDay`, `sceneNumber`,
and per-scene normalized cue sets (spans may differ); nested
`Summary`/`ScriptNote` prose reaches no scene text; multi-run text joins with no
inserted separator; the unknown type renders as action with
`unsupportedParagraphType`; re-rendering the same paragraphs is byte-identical;
the truncated file throws `FDXReadError.malformed(line:column:)`; every key
written so far matches byte-for-byte.

### Step 4: Author the structure and dialogue pieces, and the expected-parse files

Write `structure-piece.fountain` and `dialogue-piece.fountain` to the coverage in
the sample table (6–15 pages each), and finish `all` so every `syntaxCoverage`
names what its sample exercises. Generate their `.parse.json`, then **read them**
— an answer key is a contract, not a snapshot of what the parser happened to do.
`ExpectedParseTests` now covers every `ScreenplaySamples.all` entry and every
adversarial file except `fdx-malformed.fdx`.

**Verify**:

```bash
git add -A Packages/FilmCore
swift test --package-path Packages/FilmCore \
  --filter ExpectedParseTests --filter SampleResourceTests
git diff --quiet -- 'Packages/FilmCore/**/*.parse.json'
```

Expected: every sample and adversarial input matches its committed answer key
byte-for-byte; the union of `syntaxCoverage` over `all` contains every syntax
item §7.1 names for the three pieces; the `git diff --quiet` exits 0 — the run
wrote no answer key.

### Step 5: Full package verification and notes

Record in `docs/IMPLEMENTATION_NOTES.md` the sample inventory (names, page and
scene counts, syntax covered), any FDX rule §12.1 left unsettled and how it was
resolved, and any code consulted or adapted from QiyangStudio/SwiftFountain (MIT)
with its license notice, per `docs/REFERENCE_PROJECTS.md`; never vendored, never
a dependency.

**Verify**:

```bash
swift test --package-path Packages/FilmCore
./scripts/verify.sh
git status --short
! git ls-files | grep -q '\.answer-key\.json$\|planted\.md$'   # point-in-time: Plan 006 later commits test fixtures under Tests/FilmEvalTests/Samples/
```

Expected: the tests and `verify.sh` exit 0; `scripts/verify.sh` and
`project.yml` unmodified with the new test targets running through the existing
FilmCore line; nothing staged under `.aifilm`, DerivedData, or third-party
screenplay text; the last command exits 0 (no answer key, no planted notes).

## Done criteria

- [ ] `swift test --package-path Packages/FilmCore` and `./scripts/verify.sh`
  exit 0 without `FILMCAMP_PERF`; `scripts/verify.sh`, `project.yml`, and
  `Package.resolved` unchanged; `.gitattributes` marks `*.fountain`/`*.fdx` as
  `-text`.
- [ ] `FilmScript` has no dependency, no `import GRDB`/`FilmCore`/`SwiftUI`,
  exposes exactly the contracted public API, all `Sendable`, clean under Swift 6
  strict concurrency, and `FilmScriptVersion.parser` is `"1"`.
- [ ] `FountainParser.parse` turns Fountain, plain text, and FDX-rendered text
  into a `ScreenplayDocument` and `FDXReader.read` produces the same type;
  parsing is deterministic (same bytes → byte-identical encoding) and every
  sample and adversarial input matches a committed `.parse.json`.
- [ ] Every segmentation refinement in Contracts holds — title-page rule, cue
  exception, boneyard excised before classification and clipped per scene,
  preamble ordinal 0 and its start offset, sequence assignment and spans, `=` vs
  `===`, `EST.`, the single `UNTITLED` + `noSceneHeadings` fallback (empty body
  included) — `ParsedScene.cues` lists every occurrence, and every FDX rule
  holds, with `messy-piece.fdx` matching `messy-piece.fountain` on the stated
  subset.
- [ ] `ScreenplaySamples` is a real library target with exactly one Swift file,
  public `url(named:)` and `all`, `.copy("Resources")`, every declared file
  resolving, and every `syntaxCoverage` naming the §7.1 syntax that sample
  exercises (their union covering every item §7.1 lists).
- [ ] `structure-piece`, `dialogue-piece`, `messy-piece` (+ its FDX twin and the
  no-heading companion) and `camp-signal.fountain` are committed with a README
  stating they are original synthetic works for parser syntax coverage and
  carrying the answer key/version-bump rule; no third-party screenplay text and
  no operator screenplay is present, and no `.answer-key.json` or `planted.md`
  exists anywhere in the repository.
- [ ] No storage, migration, `ProjectTools`, import, app, automation, or Phase 0
  task change is included; `docs/plans/README.md` marks Plan 002 `DONE`.

## STOP conditions

Stop and report instead of improvising if:

- The design hash differs and §3.1, §3.4, §5, or §7 changed.
- The Fountain surface required exceeds §5.1 in a way that needs a dependency.
  Report the construct; do not vendor GPL code (Beat), do not add a package.
- FDX rendering cannot be made deterministic for some real construct (report
  it), or a §12.1 corpus rule contradicts an actual file you were given.
- UTF-16 offsets cannot be kept stable for some input (report the input).
- A syntax item §7.1 lists cannot be covered by an original synthetic sample
  without borrowing third-party screenplay text. Report the item; no licensed
  text enters this repo — not "Big Fish", not "Brick & Steel", nothing from
  nyousefi/Fountain's corpus.
- Anyone supplies an operator screenplay (feature-length, real). Do not commit
  it, add it to `ScreenplaySamples`, or generate a `.parse.json` for it — an
  answer key embeds `sourceText` and would publish the script (§7.1). It belongs
  to Plan 006's git-ignored `screenplays-private/` path.
- You find yourself about to hand-author an entity answer key, a
  `.answer-key.json`, or a `planted.md` — reversed by decision §14.4; re-read
  §7.2.
- A verification command fails twice after one reasonable scoped correction.
- Work expands into schema v2 or its migration, `ProjectTools` role protocols,
  `importScreenplay`, parser entity/alias/appearance/evidence rows, the job
  runner, or removal of the Phase 0 `analyzeScreenplay` task (**003**); the app
  shell, UTType declarations, automation and Finder-smoke changes (**004**);
  editing, provenance, locks (**005**); scorer, `filmcamp-eval`, the answer-key
  exporter (**006**); extraction (**007**).

## Maintenance notes

- Every parser bug found on a real screenplay becomes an adversarial sample
  **before** it is fixed, with its answer key in the fixing commit.
- `.parse.json` files are contracts: regenerate only with an explicit, reviewed
  diff, with the `FilmScriptVersion.parser` bump Contracts requires.
- `ScreenplaySamples` stays synthetic and small — new samples for syntax the
  parser mishandles, never for story coverage.
- Downstream consumers, whose meaning cannot change without updating the design
  section that names them: Plan 003 (`ScreenplayDocument` → schema v2 rows,
  `cues` occurrences → one alias row per distinct normalized form plus
  per-**scene** `speaking` appearances and per-occurrence evidence, note/boneyard ranges →
  `scene_exclusions`, `DisplayCase` → display names, `CueNormalizer` → alias
  normalization, `FilmScriptVersion.parser` → `parser_version`); Plan 004
  (`ScreenplaySamples` → the app's automation sample; it deletes the app-side
  copy and declares the UTIs); Plan 006 (parser-side scorer tests, the *derived*
  §7.2 answer key); Plan 007's chunker (`ParsedScene.range`, `cues`,
  `sceneExclusions`, §8.2).
- Keep `FilmScript`'s public API to `String`/`Data`/`URL` among Foundation types
  (§3.1). If a future need pushes another one across that boundary, it is a
  design change, not a refactor.
