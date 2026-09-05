# Plan 006: Evaluation scorer and answer-key exporter (Phase 1b infrastructure)

> **Executor instructions**: Read `docs/PHASE1_DESIGN.md` §7 in full first, plus §3.3 (evidence and anchoring),
> §3.6 (provenance and review state), §3.9 (runs, attempts, usage), §3.9a (`ProjectReading`), and §4.3 (schema
> v2). Follow the steps in order, run every verification command, and honor the STOP conditions. Requires Plan
> 003 `DONE`. Steps 1–4 may be executed in parallel with Plans 004–005; **Step 5 requires Plan 005 `DONE`**,
> because only its editing operations produce the accepted / human / rejected rows the exporter reads. When
> complete, set this plan's row in `docs/plans/README.md` to `DONE`.
>
> **Drift check (run first)**:
>
> ```bash
> printf '%s  %s\n' \
>   1f0e224d9d668bc10fa01ab55bf60e115b14bafd0931eb81c26d152d5a4467ac docs/ROADMAP.md \
>   8660b7114aa507a98ec2cf621176355cb912b749ff3b84395e6f4af6fb927691 docs/OVERVIEW.md \
>   61c6f3c56b80a0ba04ab024139b062ef83873988936c69e90d4b47b123683965 docs/PHASE1_DESIGN.md \
>   fbfd7b1c3202b49f63931f10b1f81e856eb5f37c87745b8aa6f422d7e6809aff AGENTS.md \
>   | shasum -a 256 -c -
> ```
>
> Expected: all print `OK`. If a hash differs and §7 changed, stop for reconciliation
> before writing code.

## Status

- **Status**: DONE
- **Priority**: P1
- **Effort**: M, approximately 4–5 focused engineering days
- **Risk**: LOW-MED; a scorer too strict to be useful or too loose to catch regressions — mitigated by
  hand-built snapshots with hand-computed scores, and by §7.2's unlisted-is-not-wrong rule
- **Depends on**: 003. Steps 1–4 run alongside 004–005; Step 5 (exporter integration) needs 005 `DONE`
- **Category**: tests / tooling
- **Planned at**: commit `02cf45c` + Plans 002–003; design hash in the drift check

## Current state

- **Plan 002** ships `ScreenplaySamples` (library product in FilmCore, `public static func url(named: String)
  -> URL`, taking a full filename and trapping on a missing packaged resource — Plan 002 freezes this), synthetic parser samples only (§7.1), used here only as import material for temp bundles. No
  `.answer-key.json` and no `AnswerKeyValidationTests` exist yet. Extraction samples are **paths, not
  resources** (§7.1): nothing in `FilmEval` may resolve a scored screenplay through `ScreenplaySamples`.
- **Plan 003 plus the Plan 006 preflight** supply schema v2 (§4.3),
  `ProjectBundle.create(at:name:)` / `open(at:)`, `ProjectSession.close()`,
  `ScreenplayImporting.importScreenplay`, the **public** `UTCDate.string(from:)` / `date(from:)` codec in
  `…/FilmCore/Storage/UTCDate.swift`, and the **public**
  `EntityNormalization.normalize(_:)` in `…/FilmCore/Domain/EntityNormalization.swift` (if Plan 003 left it
  internal, making it `public` is the one FilmCore edit this plan may make, and it appears in Step 5's expected
  tree), `JobUsage.empty` with `nil`-aware summation, and `Provenance` (`source`, `createdSource`, `reviewedAt`,
  `jobID`, …) on `Entity`, `EntityAlias`, `SceneEntity`, `EntityState`, `ContinuityEvent`. `ProjectReading`
  (§3.9a) is the whole surface this plan may read; Plan 003 guarantees that `SceneDetail.evidence` holds only
  synopsis-subject rows and `EntityDetail.evidence` every entity-owned row, so the two partition the table.
  `Job` carries `task`, `progressStage`, `usage`, `endedAt`, and — exposed by Plan 003 from the v2 columns —
  `parentJobID`, `chunkIndex`, `chunkCount`, `attemptIndex`, `supersedesJobID`, `scriptID`, `scriptSHA256`;
  there is no `createdAt`. `ProjectReading.continuityEvents()` (Plan 003) returns events including entity-less ones. Bundles are not in WAL mode (GRDB `DatabaseQueue` default journal), so a
  closed bundle is normally a single `project.db`; the WAL checks below are a safety net, not the common case.
- **Plan 005** supplies `acceptFacts`, `rejectEntity`, `createEntity`, `renameEntity`, `mergeEntities`, used by
  **Step 5 only** to build a reviewed bundle.
- `Packages/FilmBrain/Package.swift` today: one library product, targets `FilmBrain`/`FilmBrainTests`,
  `.package(path: "../FilmCore")`; schemas in `…/FilmBrain/Resources/Schemas/`; CI runs `./scripts/verify.sh`.
  `docs/eval/` does not exist, and `.gitignore` covers `*.aifilm/`, `*.db`, `*.db-shm`, `*.db-wal` but
  **not** `screenplays-private/`, which this plan adds.

## Contracts (normative)

### Package.swift additions (`Packages/FilmBrain/Package.swift`)

One product and three targets; no external dependency, no `Package.resolved` change:

```swift
let samples = Target.Dependency.product(name: "ScreenplaySamples", package: "FilmCore")  // above Package(…)
// products: keep .library(name: "FilmBrain", …) and add:
.executable(name: "filmcamp-eval", targets: ["filmcamp-eval"]),
// targets: keep FilmBrain and FilmBrainTests unchanged and add:
.target(name: "FilmEval", dependencies: ["FilmCore"],
        swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]),
.executableTarget(name: "filmcamp-eval", dependencies: ["FilmEval", "FilmCore"],
        swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]),
.testTarget(name: "FilmEvalTests", dependencies: ["FilmEval", samples],
        resources: [.process("Samples")]),
```

- `ScreenplaySamples` is a dependency of **test targets only** — `FilmEvalTests` here, and `FilmBrainTests` in
  Plan 007 (§7.1); `FilmEval` gets **no library
  product** and `project.yml` is **not** changed, so the app cannot link it.
- `FilmEval` may never import `FilmScript`, `FilmBrain`, `GRDB`, or `SwiftUI` (§3.1). `filmcamp-eval` links
  `FilmEval` + `FilmCore` in this plan; **Plan 007 adds `FilmBrain` to it** for the `run` subcommand, which
  drives the real harness — the ban is on the library, not the executable. If Plan 003's import entry point
  needs a pre-parsed `ScreenplayDocument`, add `.product(name: "FilmScript", package: "FilmCore")` to
  **`FilmEvalTests` only**.

### Answer key file and normalization

The §7.2 document, decoded by `FilmEval.AnswerKey` with `CodingKeys` matching it:

```swift
public struct AnswerKey: Codable, Sendable, Equatable {
    public struct DerivedFrom: Codable, Sendable, Equatable {
        public let bundleSHA256: String, runJobID: String?, exportedAt: String
        public let scriptSHA256: String, parserVersion: String, sceneCount: Int }   // binds the key to the parse its ordinals came from
    public struct EntityRef: Codable, Sendable, Hashable { public let kind: EntityKind, name: String }
    public enum Origin: String, Codable, Sendable { case confirmed, corrected, added }   // design §7.2; never accepted/human
    // Entity:   kind: EntityKind, name, aliases: [String], appearsIn: [Int], required: Bool, origin
    // Rejected: kind: EntityKind, name, aliases: [String]
    // State:    entity: EntityRef, category, startScene: Int, endScene: Int?, keywords: [String], origin
    // Event:    scene: Int, entity: EntityRef?, keywords: [String], origin
    public let sample: String, version: Int, derivedFrom: DerivedFrom
    public let entities: [Entity], rejected: [Rejected], states: [State], events: [Event]
}
```

- States and events reference an entity by the **`{kind, name}` pair**, never a bare display name: the same
  name may legally exist in two kinds (§3.4).
- No normalizer inside `FilmEval`: canonical keys are the stored `Entity.nameNormalized` /
  `EntityAlias.normalized`; answer-key names and aliases are raw surface forms run once through Plan 003's
  public `EntityNormalization.normalize(_:)` (§3.4–§3.5).
- No timestamp formatter inside `FilmEval`: answer-key validation and export use FilmCore's public
  `UTCDate.date(from:)` / `string(from:)`, so database rows and evaluation artifacts retain one UTC spelling.
- `AnswerKey.load(contentsOf:)` = decode + `validate()`; `derivedFrom` is **required**: `load` rejects a key without it, pointing at
  `filmcamp-eval save-answer-key`. `rejected`/`states`/`events` default to `[]`; unknown top-level keys are
  rejected; keys are files given by path, with no resource loader.
- `AnswerKey.validate()` checks self-consistency only, throwing `AnswerKeyError` naming the offending path:
  `version >= 1`; entity names unique per kind; `appearsIn` ordinals ≥ 0, sorted-unique; every
  `states[].entity` and non-null `events[].entity` matching a declared entity's `(kind, name)`
  (`.unknownEntityRef`); `keywords` non-empty and lower-case; `startScene` ≥ 0; `endScene` null or ≥
  `startScene`; `rejected` names unique per kind; **no two `entities` entries of the same `kind` sharing a
  normalized name or alias** (`.ambiguousAlias(kind:key:)`) — a shared key would make scorer assignment
  ambiguous; **no `rejected` entry whose name or alias normalizes to the name or an alias of an entry of the
  same `kind`** (`.rejectedCollision`); `bundleSHA256` and `scriptSHA256` matching `^[0-9a-f]{64}$`;
  `sceneCount >= 1`; `exportedAt` parsing through `UTCDate`. `kind`/`origin` are enforced by decoding.

### `save-answer-key`: reviewed state → answer key

`AnswerKeyExporter.key(from: CanonicalSnapshot, options: ExportOptions) -> AnswerKey` is **pure, synchronous,
and `nonisolated`**, so the mapping is unit-testable over hand-built snapshots; `export(bundleAt:options:)
async throws -> AnswerKey` is the thin bundle wrapper below. `ExportOptions`: `sample: String?`, `previous:
AnswerKey?`, `now: Date` (injected for determinism):

| Rule | Definition |
|---|---|
| source rows | the snapshot's `entities`, built from the three-`reviewState` union below |
| eligibility | **only rows with `reviewedAt` set** (design §3.6, §7.2). `review_state = accepted` alone is not review: parser rows are born accepted. Plan 005 stamps `reviewedAt` on accepts, on **rejections** (so the `rejected` array is non-empty), and on every `.human` insert (so rename/merge/split aliases export); an `.ai` insert never carries it. An untouched parser-only project therefore exports an empty key |
| `origin` | a **two-stage** rule, in this order: (1) by `reviewState` — `.rejected` → a `rejected` entry (whatever `source`/`createdSource` say: a human-edited or human-created row that was later rejected exports **only** as a tombstone), `.proposed` → excluded, `.accepted` → continue; (2) by `createdSource`/`source`, never the current `source` alone (a human edit flips it): `createdSource ∈ {parser, ai} && source != .human` → `"confirmed"`; `createdSource ∈ {parser, ai} && source == .human` → `"corrected"`; `createdSource == .human` → `"added"` (the model missed it — the only true recall signal) |
| `required` | always `true` on export; the exporter never writes `required: false`, which stays meaningful to the scorer for a hand-trimmed key |
| `name`, `aliases` | `EntityRow.name`; plus `EntityRow.aliases` surface forms **whose own `reviewedAt` is set** (accepting an entity accepts its alias rows, §3.5, so this is the normal case; an unreviewed AI-proposed alias — e.g. the one an AI merge inserts — is not ground truth and must not drive matching), de-duplicated by normalized form, sorted case-folded then raw |
| `appearsIn` | `EntityRow.appearances` whose rows carry `reviewedAt`, sorted ascending |
| states/events | `StateRow`/`EventRow` under the same origin rule (`proposed` excluded, `rejected` dropped); `startScene`/`endScene`/`scene` are the row's ordinals, `endOrdinal == nil` → `endScene: null`; `entity` is the owning row's `{kind, name}`; a row whose owning entity was not exported is **skipped** |
| keywords | `Keywords.swift`, from the row's `description`: case-fold and NFC-normalize; replace every non-letter/non-digit character with a space; collapse whitespace; split; drop tokens shorter than 3 characters; drop tokens in the checked-in sorted `Keywords.stopWords: Set<String>` (common English function words); de-duplicate preserving first occurrence; keep the first `Keywords.limit = 4`. Empty → retry without the stop list; still empty → skip the row, counting it as `skippedNoKeywords` |
| `bundleSHA256` | `BundleSnapshot.sha256` — the digest of the quiescent `project.db` that was copied, re-verified after the copy, so it describes the snapshot actually exported |
| `scriptSHA256`, `parserVersion`, `sceneCount` | `script()?.sha256`, `script()?.parserVersion`, and the number of scenes — so a later parser change that renumbers ordinals is detectable (a bundle with no script cannot be exported: exit 1) |
| `runJobID` | the snapshot's `runJobID` (selected below) as a lowercase UUID string, else `null`; `exportedAt` = `options.now` through `UTCDate` |
| `sample` | `options.sample`, else the previous key's `sample` when `--out` exists, else the bundle file name without `.aifilm` |
| `version` | `previous.version + 1` when `--out` exists and decodes, else `1`; an existing `--out` that does not decode fails with exit 1 and writes nothing |
| no leakage | no `AnswerKey` field can hold `sourceText` or an evidence `quote`, and neither the snapshot builder nor the exporter calls `sceneText(id:)` — a Step 5 test, not a convention |
| self-check | the exporter runs `AnswerKey.validate()` on what it built **before** writing; storage does not guarantee `.ambiguousAlias` (entity A's name may normalize to entity B's alias), so on failure it writes nothing, exits 1, and names both entities with "merge them in the app, then re-export" — the file is never hand-edited |
| output | atomic, `.sortedKeys`, `.withoutEscapingSlashes`, `.prettyPrinted`, arrays sorted by `kind`, then case-folded `name`, then `startScene`/`scene`, so re-export of an unchanged bundle differs only in `exportedAt` and `version` |

### Scoring: `CanonicalSnapshot` → `EvalRow`

Scoring is pure over a `Sendable` value, so every metric is testable without a database.
`Scorer.score(snapshot:answerKey:options:) throws` is synchronous and `nonisolated`; it throws
`.answerKeyHasNoRequiredEntries` (design §7.2 — no flattering recall of 1.0 against an empty key; the CLI maps
it to exit 1). `ScoreOptions`: `sample: String?` (defaults to the key's), `label: String` (`"default"`),
`chunkBudget: Int?` — the run's chunk budget **in UTF-16 units** (the unit `ExtractionChunker.budgetUTF16`
uses; 32,000 ≈ 8,000 tokens), supplied by the caller and recorded verbatim. `ScorerSemantics.version` (an
`Int` alone in `ScorerSemantics.swift`) pins the definitions below; it is recorded in every report and is an
eval-gate input, so changing a metric trips the gate.

```swift
public struct CanonicalSnapshot: Sendable, Equatable {
    // EntityRow: id, kind: EntityKind, name, reviewedAt: Date?, createdSource: FactSource, jobID: UUID?,
    //   aliases: [AliasRow] (surface form, normalized, reviewedAt — non-rejected), keys: Set<String>
    //   (nameNormalized ∪ alias.normalized), isRelevant, reviewState, source, evidenceCount: Int,
    //   appearances: [AppearanceRow] (scene ordinal, reviewedAt; role .mentioned excluded)
    // StateRow: entityID, category, description, startOrdinal: Int?, endOrdinal: Int?, reviewState, source,
    //   createdSource, reviewedAt, jobID
    // EventRow: entityID: UUID?, ordinal: Int?, description, reviewState, source, createdSource, reviewedAt, jobID
    public let sceneCount: Int, maxSceneOrdinal: Int   // ordinal 0 (preamble) makes these differ
    public let scriptSHA256: String?, parserVersion: String?
    public let entities: [EntityRow], states: [StateRow], events: [EventRow]
    //   entities sorted by id; states by (entityID, startOrdinal, category, description); events by (entityID, ordinal, description)
    public let aiEvidenceTotal: Int, aiEvidenceAnchored: Int
    public let chunkCount: Int                // 0 when no run exists
    public let usage: JobUsage, requestCount: Int, runJobID: UUID?
    public let engine: String?, engineVersion: String?, model: String?   // the run parent's engine, engineVersion, requestedModel
}
```

| Metric | Rule |
|---|---|
| matching | candidate when `kind`s are equal and key sets intersect; each canonical entity matches **at most one** entry — highest key-overlap count wins, ties break by entry `name` ascending (case-folded, then raw), so assignment is order-independent (`.ambiguousAlias` already removed the case of two entries claiming one key) |
| tombstones | unmatched entities with `createdSource != .parser` are then tested against `AnswerKey.rejected` by the same rule → `resurrectedRejected`; entries always win over tombstones. Unmatched **parser**-created entities matching a tombstone are `parserResurrected` (reported, never gating: a fresh import recreates every cue and heading deterministically, and the operator may legitimately have rejected one). Matching neither → `newUnreviewed`, reported with `name`, `kind`, `evidenceCount` |
| `resurrectedRejected` meaning | a scored run imports into a **fresh** bundle holding no tombstones, so §8.5's apply-time skip cannot suppress these rows. A nonzero count is therefore a prompt or model regression re-introducing dismissed noise — never an apply defect |
| sets | `considered` = `isRelevant == true` (irrelevant rows leave the counts but stay eligible to match); `consideredExcludingRejected` = `considered` minus `reviewState == .rejected`. Every entity metric is computed over both. Recall's numerator counts an entry as matched by **any** canonical entity, `considered` or not (an entry matched only by an irrelevant row is not in `missingRequired`); the `considered` restriction applies to precision terms and per-kind counts |
| precision | `count(matched) / (count(matched) + count(resurrectedRejected))`, with `newUnreviewed` in no precision term |
| recall | `count(matched required entries) / count(required entries)`; `required: false` entries never enter the recall denominator but do count as matches for precision |
| f1, zeroes | harmonic mean, `0` when `precision + recall == 0`; a zero denominator yields `nil` (rendered `—`), never `0` |
| missing required | names of unmatched `required: true` entries, ascending |
| appearance Jaccard | over entries with non-empty `appearsIn`, against the **union** of that entry's matched canonical appearance sets; the row reports the mean, or `nil` |
| fragmentation | count of entries matched by more than one canonical entity, plus the list `(entry kind, entry name, [canonical names])`; `applicable: false` and `—` below `chunkCount` 2 |
| states/events | on top of §7.2's criteria: the key's `{kind, name}` ref must resolve to the entity matched to that entry; a `null` `endScene` means `maxSceneOrdinal` on both sides; `startOrdinal == nil` never matches; keyword comparison tokenizes the canonical `description` with the same `Keywords` tokenizer and requires a **whole-token** match (`cut` does not match `haircut`); matching is one-to-one, greedy in `(startOrdinal, category, description)` order for states and by equal scene ordinal for events (entity match, or both `nil`) |
| parse binding | when the snapshot's `scriptSHA256` or `parserVersion` differs from the key's `derivedFrom`, the row gets a `notes` entry naming both (the ordinals may no longer line up) — never silent |
| anchor rate | `aiEvidenceAnchored / aiEvidenceTotal`, both counts kept, `nil` at total 0 |
| rounding | ratios stored rounded to 4 decimals (`(x * 10_000).rounded() / 10_000`) for byte-stable JSON; markdown prints 3 |

### Report (`reportVersion: 1`)

JSON is the machine format read by `--baseline` and `scripts/eval-gate.sh`; markdown is the rendering.
`runSettings` is read from `scripts/eval-run-settings.txt`, never invented per run; an empty value is `null`.

```jsonc
{ "reportVersion": 1, "generatedAt": "2026-09-02T18:04:11.412Z", "gitSHA": "a1b2c3d",
  "engine": "codex", "engineVersion": "0.146.0", "model": null, "bundleSchemaVersion": 3,
  "scorerSemanticsVersion": 1, "schemaVersions": {"extract-chunk": 1, "reconcile-entities": 1},
  "runSettings": {"chunkBudget": 32000, "reducedBudget": 16000, "concurrency": 3,
                  "chunkModel": null, "chunkEffort": null, "reconcileModel": null, "reconcileEffort": null},
  "manifest": "<sha256>  Packages/FilmBrain/…/extract-chunk-v1.schema.json\nabsent  …\n",
  "inputsDigest": "<sha256 of the manifest string>",
  "rows": [ /* EvalRow */ ], "totals": { /* micro-averaged, recomputed from rows */ } }
```

`generatedAt` and `gitSHA` come from an injected `ReportEnvironment { now: Date, gitSHA: String, repoRoot:
URL }` — `main.swift` fills `gitSHA` by reading `.git/HEAD` (and the ref it points at) from `repoRoot`,
`"unknown"` outside a repository; tests inject fixed values. `repoRoot` is found by walking up from the
current directory to the first `.git`, or given with `--repo-root`; every manifest path resolves against it,
never against the CWD.

| Piece | Rule |
|---|---|
| `EvalRow` | `sample`, `label`, `answerKey` (`version`, `bundleSHA256`, `runJobID`, `exportedAt`, from `derivedFrom`), `chunkCount`, `chunkBudget` (nullable — `nil` means "not recorded", allowed; otherwise what this row actually ran at), `entities` (`overall`, `byKind`, `excludingRejected`), `missingRequired`, `newUnreviewed` (`count`, `entities: [{name, kind, evidenceCount}]`), `resurrectedRejected` (`count`, `entities: [{name, kind}]`), `appearanceJaccard`, `states`, `events`, `fragmentation` (`applicable`, `count`, `entities`), `anchorRate` (`anchored`, `total`, `rate`), `usage` (five `JobUsage` fields plus `requests`), `notes`. No field may hold screenplay text or an evidence quote |
| rows | keyed by `(sample, label)`; schema and renderer must handle §7.2's two rows per sample and may never assume one. Order: `sample` ascending, then `label`, `"default"` first, rest alphabetical. A row labelled `default` or `reduced` whose non-`nil` `chunkBudget` differs from `runSettings.chunkBudget` / `runSettings.reducedBudget` gets a `notes` entry ("ran at 24000, settings say 32000") — never a refusal, so plain `score` and exploratory labels still write; Plan 007's `run` is what refuses a mismatching flag before spending a request |
| `parserResurrected` | per row, count + `[{name, kind}]`, rendered in the `Resurr` column as `n (+p parser)`; never in precision |
| `totals` | micro-averaged: sum counts across rows, then compute P/R/F1; `appearanceJaccard` is the matched-entity-count-weighted mean; anchor rate from summed counts; `newUnreviewed`, `resurrectedRejected`, and `parserResurrected` are summed |
| report name | `docs/eval/<date>-<git-sha>.{md,json}` where `<date>` is `YYYY-MM-DDTHHMMSSZ` UTC and `<git-sha>` is the 7-character short SHA (so `ls | LC_ALL=C sort` is time order); Plan 007's `run` and `docs/eval/README.md` cite this rule rather than re-spelling it |
| encoding | `.sortedKeys` and `.withoutEscapingSlashes`; encoding the same report twice must give identical bytes |
| markdown header | §7.2's honesty block: per distinct key, ``Answer key `<sample>` v<version> — snapshotted <exportedAt> from bundle <first 12 of bundleSHA256>, run <runJobID \| none>``, then §7.2's "not absolute truth" sentence dated `<exportedAt>`, then a counts-and-approved-names-only line |
| columns | `Sample \| Budget \| Chunks \| Ent P \| Ent R \| Ent F1 \| Ent F1 (−rej) \| Missing required \| New \| Resurr \| Appear J \| State F1 \| Event F1 \| Frag \| Anchor`, then a bold `totals` row; `nil` renders `—` |
| list sections | `### New since last snapshot` lists each row's `newUnreviewed` as `<name> (<kind>, <n> evidence)`, capped at 25 per row with `… and N more`; `### Resurrected rejections` lists every `resurrectedRejected` entity uncapped, under one line naming it a prompt regression |
| `--baseline` | annotates each numeric cell with ` ▲+0.021`, ` ▼-0.014`, or ` =` (unchanged within 0.0005) against the row with the same `(sample, label)`, marks rows absent from the baseline `new`, and never changes the exit code |
| precision caveat | `docs/eval/README.md` states that precision is `matched / (matched + resurrectedRejected)` and is therefore 1.0 by construction when the operator rejected nothing — `Ent F1` then tracks recall alone; read it as such |

### Executable `filmcamp-eval`

Foundation-only argument parsing; adding ArgumentParser is a STOP condition.

```text
filmcamp-eval save-answer-key <bundle.aifilm> --out <answer-key.json> [--sample <name>] [--json]
filmcamp-eval score    <bundle.aifilm> --answer-key <answer-key.json>
                       [--sample <name>] [--label <s>] [--chunk-budget <n>]
                       [--json] [--out <path>] [--baseline <report.json>]
filmcamp-eval report   --input <report.json> [--input …] [--out <path>]
                       [--baseline <report.json>] [--json]
filmcamp-eval run      …                     # exits 2 until Plan 007
filmcamp-eval --help | <subcommand> --help
```

| Subcommand | Behavior |
|---|---|
| `save-answer-key` | prints a human summary (counts by origin and kind, rejected count, excluded `proposed` count, `skippedNoKeywords`, resulting `version`), or the key JSON with `--json`; `--out` is required and its parent directories are created |
| `score` | requires `--answer-key`; `--sample` only overrides the row's sample key; default output is the markdown table on stdout, `--json` prints JSON; `--out foo.md` writes **both** `foo.md` and `foo.json`, `--out foo.json` writes only JSON; parents are created |
| `report` | merges its inputs' `rows` (rejecting any `reportVersion` other than 1, duplicate `(sample, label)` keys, or inputs that disagree on `engine`, `engineVersion`, `model`, `bundleSchemaVersion`, or `scorerSemanticsVersion` — exit 1 naming the field), recomputes `totals`, and re-derives `manifest`/`inputsDigest`/`runSettings` from the working tree, so a committed report always describes the tree that produced it |
| exit codes | `0` success (including a low score); `1` usage/IO/validation error — including `.answerKeyHasNoRequiredEntries` and an exporter self-check failure — with the message on stderr; `2` only for `run` — "`filmcamp-eval run` requires the extraction pipeline from Plan 007; use `score` on an existing bundle." |

> **Bundle schema note (recorded by Plan 008).** `bundleSchemaVersion` moved from 2 to 3
> when Plan 008 widened `scripts.format` to admit `pdf` (PHASE1_DESIGN §4.2a). Because
> `report` refuses to merge inputs that disagree on that field, reports straddling the bump
> are unmergeable and a `--baseline` comparison across it is invalid. This plan is still
> `TODO` and has produced no committed report, so any pre-bump report is **discarded**, not
> migrated — the merge rule stays exactly as specified above.

### Bundle snapshot, and `CanonicalSnapshot` construction

`ProjectBundle.open` is **not read-only** (pending migrations plus `ProjectDatabase.checkpoint()`; the v1→v2
migration rebuilds scenes), so neither command may open the artifact under measurement — and a live
`project.db-wal` means `project.db` alone is **not** a snapshot of logical state, so it may be neither copied
nor digested. One helper in `BundleCopy.swift`, whose doc comment states both reasons:

```swift
public struct BundleSnapshot: Sendable, Equatable { public let sha256: String, sourceURL: URL }

func withBundleSnapshot<T: Sendable>(
    at url: URL, _ body: @Sendable (ProjectSession, BundleSnapshot) async throws -> T
) async throws -> T
```

| Phase | Rule |
|---|---|
| 1. require quiescent | the source must already be closed and checkpointed: `project.db` exists and `project.db-wal` is absent or zero length (`ProjectSession.close()` checkpoints — Plan 003). Otherwise throw `EvalBundleError.bundleNotCheckpointed(url)`: "close the project (quit the app) first; a non-empty `project.db-wal` means `project.db` is not the whole state." The source is **never opened** by this tool |
| 2. digest | `sha256` over the source `project.db`, streamed in 1 MiB blocks through `FileHandle.read(upToCount:)` |
| 3. copy | `FileManager.copyItem` the bundle directory to `FileManager.default.temporaryDirectory/filmcamp-eval-<uuid>/<name>.aifilm` |
| 4. re-verify | repeat phases 1–2; a changed digest or a grown WAL throws `.bundleChangedDuringCopy(url)` and nothing is reported. This is what makes `bundleSHA256` a digest of the snapshot actually exported |
| 5. body | open the **copy** — migration and checkpoint touch the copy only — and run `body(session, snapshot)` against a `ProjectReading` session |
| 6. cleanup | explicit `do { … } catch { try? await session.close(); try? FileManager.default.removeItem(at: root); throw error }`, then close-then-remove on the success path. **Never `defer`**: a `defer` body may not contain `await`, so a deferred `close()` does not compile |

`BundleScorer.score(bundleAt:answerKey:options:) async throws -> EvalRow` and
`AnswerKeyExporter.export(bundleAt:options:)` are thin wrappers over it; both build one `CanonicalSnapshot`
(`SnapshotBuilder.swift`) and then call the matching pure function:

| Field | Source |
|---|---|
| entities | union of `entities(kind: nil, reviewState: s, includeIrrelevant: true, includeRejected: true)` for `s` in `.proposed`, `.accepted`, `.rejected` (default reads hide `rejected`; the primary numbers must include it), de-duplicated and sorted by `id`; `reviewedAt`, `createdSource`, `jobID` from each row's `Provenance`; `aliases` = `EntityDetail.aliases` with `reviewState != .rejected`, each with its surface form, normalized form, and `reviewedAt`; appearances are `EntityDetail.appearances` with `reviewState != .rejected` and role `.mentioned` excluded, each with its `reviewedAt`, mapped through the `[UUID: Int]` scene-id → ordinal table from `scenes()` (`sceneCount` = its size, `maxSceneOrdinal` = its maximum); `evidenceCount` = count of `EntityDetail.evidence`; states and events come from the same `EntityDetail`, ordinals through the same table; `scriptSHA256`/`parserVersion` from `script()` |
| evidence | §4.3's `CHECK ((subject_kind = 'synopsis') = (owner_entity_id IS NULL))` partitions the table, so `EntityDetail.evidence` plus `SceneDetail.evidence` covers every row exactly once; the builder walks `scene(id:)` for every scene in `scenes()` to collect the synopsis half (it never calls `sceneText(id:)`), and the anchor-rate counters take the subset with `source == .ai` |
| events | from `ProjectReading.continuityEvents()` (Plan 003), so entity-less events (`entityID == nil`) enter the snapshot; `EntityDetail` alone would drop them |
| run | newest `jobHistory()` job with `parentJobID == nil`, `task == "extractScreenplay"`, `state == .completed`, and `scriptID == script()?.id` — the newest completed extraction **for the current script**, not merely the newest completed parent — ordered by `endedAt` then `id` (there is no `createdAt`); it is also `runJobID` |
| leaves | every job in that run's tree (linked by `parentJobID`) that is no other job's parent: the chunk and reconcile **attempts**, retried and superseded attempts included |
| `usage` | sum over **leaves only** with Plan 003's `nil`-aware `JobUsage` addition (`nil` only when every operand is `nil`). §3.9 stores usage on attempt rows and the parent aggregates it for display, so adding parent + children double-counts |
| `requestCount` | count of leaves with `progressStage != Job.reusedProgressStage` (a `public static let` on `Job` in FilmCore, value `"Reused"`, added here as a one-line FilmCore edit so Plan 007 and this plan share one constant) — the attempts that actually launched a Codex process; §8.2 reused attempts record zero usage and count zero. It is **not** `children + 1`: reconcile is already a child |
| `chunkCount` | the parent's `chunkCount` ?? the number of **distinct** `chunkIndex` values over the leaves, so a retried chunk does not inflate it |
| no run | `chunkCount = 0`, `requestCount = 0`, `usage = .empty`, `nil` `runJobID` and engine/version/model |

### `scripts/eval-gate.sh`, `eval-inputs.txt`, `eval-run-settings.txt`

Inputs are listed once, in `scripts/eval-inputs.txt` — one repo-relative path per line, `#` comments allowed,
**no globs** — so the script and `FilmEval.EvalInputs` cannot disagree, and so the list is §7.2's explicit
manifest rather than a schema sweep. Paths Plan 007 has not created yet are listed now and render `absent`
until it does. Initial contents:

```text
# Files whose change invalidates the committed evaluation baseline (design §7.2).
# Explicit paths only: a glob would sweep in the harness probe schema and miss every prompt.
Packages/FilmBrain/Sources/FilmBrain/Resources/Schemas/extract-chunk-v1.schema.json
Packages/FilmBrain/Sources/FilmBrain/Resources/Schemas/reconcile-entities-v1.schema.json
Packages/FilmBrain/Sources/FilmBrain/Resources/Prompts/extract-chunk-v1.md
Packages/FilmBrain/Sources/FilmBrain/Resources/Prompts/reconcile-entities-v1.md
Packages/FilmBrain/Sources/FilmBrain/Extraction/ExtractionChunker.swift
Packages/FilmBrain/Sources/FilmBrain/Extraction/ChunkTextBuilder.swift
Packages/FilmBrain/Sources/FilmBrain/Extraction/ExtractChunkTask.swift
Packages/FilmBrain/Sources/FilmBrain/Extraction/ReconcileEntitiesTask.swift
Packages/FilmBrain/Sources/FilmBrain/Extraction/ExtractChunkValidator.swift
Packages/FilmBrain/Sources/FilmBrain/Extraction/ReconcileValidator.swift
Packages/FilmBrain/Sources/FilmBrain/Extraction/ReconcileInputBuilder.swift
Packages/FilmBrain/Sources/FilmBrain/Extraction/ExtractionProposalBuilder.swift
Packages/FilmCore/Sources/FilmCore/Extraction/ExtractionApplier.swift
Packages/FilmCore/Sources/FilmCore/Extraction/EvidenceAnchor.swift
Packages/FilmCore/Sources/FilmCore/Domain/EntityNormalization.swift
Packages/FilmBrain/Sources/FilmEval/ScorerSemantics.swift
scripts/eval-run-settings.txt
```

`scripts/eval-run-settings.txt` holds the run settings §7.2 requires the report to record, one `<key>=<value>`
per line, keys `chunkBudget` and `reducedBudget` (UTF-16 units), `concurrency`, `chunkModel`, `chunkEffort`,
`reconcileModel`, `reconcileEffort` (empty value = the account default, recorded as JSON `null`). Step 4 seeds
it with `chunkBudget=32000`, `reducedBudget=16000`, `concurrency=3`, and the four model/effort keys empty. It
is both a listed input and the source of the report's `runSettings`, and **Plan 007's `run` reads it as its
defaults** (its `--chunk-budget`/`--reduced-budget`/`--concurrency` flags override for one invocation and
are recorded verbatim in the rows). The script runs `set -euo pipefail` and `cd`s to the repo root, then
picks the newest report with `report=$(ls docs/eval/*.json 2>/dev/null | LC_ALL=C sort | tail -1 || true)`
— the `|| true` is required: under `pipefail` a failing `ls` would otherwise abort the script before the
emptiness test (lexical order is time order under the report-name rule above); with none it exits
0 with `eval-gate: no committed report yet; skipped`. The script's shebang is `#!/bin/bash`
(`<(…)` is a bash-ism; `sh` rejects it).

| Rule | Definition |
|---|---|
| manifest | identical in bash and Swift: one line per listed path, `<sha256>  <path>\n` when it exists and `absent  <path>\n` when it does not, sorted by path under `LC_ALL=C`; `inputsDigest` = SHA-256 of that text; `--print-manifest` prints it and exits 0 |
| no globs | a line containing `*`, `?`, `[`, or naming a directory is a configuration error: exit 1 naming the line. §7.2 requires an explicit manifest, and `absent` lines make a typo visible in `--print-manifest` |
| comparison | digest via `shasum -a 256`; recorded digest via `plutil -extract inputsDigest raw -o - -- "$report"` (no `jq`/`python` dependency; a missing `inputsDigest` **or `manifest`** key fails with a pointer to `docs/eval/README.md`); on a mismatch print both digests plus `diff <(./scripts/eval-gate.sh --print-manifest) <(plutil -extract manifest raw -o - -- "$report") \|\| true` — the `\|\| true` is required because `diff` exits 1 on a difference and `set -e` would otherwise abort before the message; the report stores the manifest as one string for exactly this reason (`plutil` key paths cannot address slash-containing keys) — and exit 1 with "prompt or schema changed since the last scored run (`<report>`). Re-run `filmcamp-eval run` and commit a new report." |
| run settings | the container is extracted **once**: `settings=$(plutil -extract runSettings json -o - -- "$report")` (a one-line JSON object; per-key `plutil -extract … json` fails on every scalar leaf — `plutil`'s JSON writer refuses a non-container top level — and per-key `raw` exits 1 on `null`, so neither per-key form works); inside `if ! settings=$(…); then` so a plutil failure is a named error rather than a `set -e` abort. Each `<key>=<value>` line of `scripts/eval-run-settings.txt` is then matched against the object: an empty value must appear as `"<key>":null`, a number as `"<key>":<n>`, a string as `"<key>":"<s>"`; a difference exits 1 with "run settings changed since the last scored run (`<report>`)", naming the keys |
| scope | deliberately **no** bypass variable; answer keys deliberately **not** listed — re-exporting improves the key and is not a prompt change |
| wiring | `scripts/verify.sh` gains `./scripts/eval-gate.sh` as its **last** step, after the app test bundle, so a policy failure never hides a build or test failure; a no-op until Plan 007 commits a report |

## Target file layout (additions)

```text
Packages/FilmBrain/
  Package.swift                  + executable product, FilmEval, filmcamp-eval, FilmEvalTests
  Sources/FilmEval/              AnswerKey, Keywords, CanonicalSnapshot,
    ScorerSemantics (the constant, alone in its file), Matching, Metrics, Scorer, AnswerKeyExporter,
    EvalReport, ReportEnvironment, EvalInputs, BundleCopy, SnapshotBuilder, BundleScorer  (one .swift each;
    no Normalization.swift — FilmEval has no normalizer)
  Sources/filmcamp-eval/         main.swift, Arguments.swift, Commands.swift
  Tests/FilmEvalTests/           TestSupport.swift (snapshot builders + EvalTemporaryProject),
    AnswerKeyDecodingTests, KeywordsTests, ExportMappingTests, MatchingTests, MetricsTests,
    ScorerTests, ReportRenderingTests, EvalInputsTests, BundleScorerTests, AnswerKeyExporterTests,
    Samples/{sample.answer-key.json, report-expected.json, report-expected.md, baseline.json}
Packages/FilmCore/Sources/FilmCore/Domain/Job.swift   + `Job.reusedProgressStage` (one line, Step 2)
Packages/FilmCore/Sources/FilmCore/Domain/EntityNormalization.swift   `public` only if Plan 003
  left `normalize` internal (Step 1)
scripts/eval-gate.sh, scripts/eval-inputs.txt, scripts/eval-run-settings.txt   new
scripts/verify.sh                + eval-gate.sh as the final step
.gitignore                       + screenplays-private/
docs/eval/README.md              the review → export → score loop and the policy
docs/eval/answer-keys/           where exported answer keys are committed (first one: Plan 007)
```

## Steps

Steps 1–4 need only Plan 003 and may be executed while Plans 004–005 are in flight; Step 5 is the integration
half of the exporter and requires Plan 005 `DONE`.

### Step 1: Package targets, answer key, keywords, matching, metrics, and the export mapping

Add the product and three targets exactly as specified (and, if Plan 003 left it internal, make
`EntityNormalization.normalize` `public` — the exporter's key derivation needs it), then implement
`AnswerKey`, `Keywords`, `CanonicalSnapshot`, `ScorerSemantics`, `Matching`, `Metrics`, `Scorer`, and
`AnswerKeyExporter.key(from:options:)` — all pure and `Sendable`; only `AnswerKey.load` touches disk. Tests
are hand-computed over hand-built `CanonicalSnapshot` values, at minimum:

| Suite | Cases |
|---|---|
| `MatchingTests`, `MetricsTests`, `ScorerTests` | perfect match; missing `required`; missing optional (recall unchanged); unlisted entity (`newUnreviewed`, precision unchanged); tombstone match by an AI-created entity (`resurrectedRejected`, precision drops, name listed) and by a parser-created one (`parserResurrected`, precision unchanged); an empty key throws `.answerKeyHasNoRequiredEntries`; a `scriptSHA256` mismatch adds a `notes` entry; two canonical entities on one entry (fragmentation with `kind`, at `chunkCount` 1 and 3, proving `applicable`); alias-only match (`SAZ`); same name, wrong `kind`; a state whose `{kind, name}` ref names that same name in the other kind (no match); irrelevant-marked entity out of the counts but still matching; a `rejected` row moving the primary numbers but not `excludingRejected`; tie-break determinism under shuffled order; appearance Jaccard with partial overlap and with the fragmented union; state range edges (touching endpoints, open-ended `endScene` against `maxSceneOrdinal` with a preamble present, `startOrdinal == nil`); keyword miss and a substring-only near-miss (`cut` vs `haircut`); event ordinal mismatch; anchor rate at 0 and mixed; every zero denominator (`nil`, not `0`) |
| `ExportMappingTests` | origin mapping over hand-built rows: an AI-created row accepted unchanged → `"confirmed"`; a parser-created row the operator accepted → `"confirmed"`; an AI- or parser-created row a human edited (`source == .human`, `createdSource` unchanged) → `"corrected"`; a human-created row → `"added"`; a row without `reviewedAt` → excluded whatever its state; `proposed` in neither array; `rejected` only in `rejected` with its aliases — **including a human-edited row and a human-created row that were later rejected**; a rename-created (human) alias exports while an AI-merge-created alias does not; an unreviewed alias on a reviewed entity is **not** exported while a reviewed one is; `required: true` always; alias de-duplication and sort; `appearsIn` sorted-unique over reviewed appearances; a state or event whose owning entity was not exported is skipped; `endOrdinal == nil` → `endScene: null`; the emitted key passes `AnswerKey.validate()`; an entity whose name collides with another's alias makes the exporter throw before writing; two exports with a fixed `now` are byte-identical; `version` is 1 with no `previous` and `previous.version + 1` with one |
| `AnswerKeyDecodingTests` | `Tests/FilmEvalTests/Samples/sample.answer-key.json` plus malformed cases — missing `derivedFrom`, two entries of one kind sharing an alias, a `rejected` entry colliding with an entry alias of the same kind, unknown `origin`, a state whose `{kind, name}` names no declared entity, an upper-case keyword, `version: 0`, malformed `bundleSHA256` — each error naming the offending path |
| `KeywordsTests` | derivation pinned on fixed descriptions, plus the stop-word fallback and the no-alphanumerics skip |

**Verify**:

```bash
swift build --package-path Packages/FilmBrain
for s in AnswerKeyDecoding Keywords ExportMapping Matching Metrics Scorer; do
  swift test --package-path Packages/FilmBrain --filter "${s}Tests" || echo "FAILED $s"
done
xcodegen generate --spec project.yml
xcodebuild -project "AI Film Camp.xcodeproj" -scheme "AI Film Camp" \
  -configuration Debug -derivedDataPath .build/DerivedData \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

Expected: every score equals the hand-computed value exactly; each malformed key is rejected with the
offending path in the message; the app still builds (the executable product must not break Xcode's package
resolution).

### Step 2: Bundle snapshot helper, snapshot builder, and bundle scorer

Add `Job.reusedProgressStage` (FilmCore, one line), then implement `BundleCopy.withBundleSnapshot`,
`SnapshotBuilder`, `BundleScorer`, and `AnswerKeyExporter.export(bundleAt:options:)`. `BundleScorerTests`
uses only Plan 003 surface: a temp bundle
from `ProjectBundle.create(at:name:)` plus an imported `ScreenplaySamples` screenplay, scored against a
test-owned key produced by the exporter. Assert:

| Assertion | Detail |
|---|---|
| loop (half) | export on a parser-only, unreviewed bundle yields an **empty** key (no required entries) and `score` refuses it with `.answerKeyHasNoRequiredEntries` rather than reporting recall 1.0; `derivedFrom` carries the bundle's `scriptSHA256`, `parserVersion`, and `sceneCount`. The positive half — review, export, score → recall 1.0 — needs Plan 005's `acceptFacts` (nothing in Plan 003 sets `reviewed_at`, and raw SQL is a STOP) and lives in Step 5 |
| no run | with no AI facts: anchor rate `nil`, `chunkCount` 0, `requestCount` 0, `usage == .empty`, `runJobID` nil, fragmentation `applicable: false` |
| run facts | over hand-inserted job rows (parent + two chunk attempts, one of them a `"Reused"` retry, plus reconcile): `usage` equals the sum over **leaves only** — not the parent's aggregate and not parent + children; `requestCount` counts only non-`Reused` leaves; `chunkCount` counts distinct `chunkIndex`; a completed parent for a **different** script is not selected |
| snapshot integrity | the source `project.db` size, modification date, and SHA-256 are unchanged afterwards, and `derivedFrom.bundleSHA256` equals `shasum -a 256` of it; the temp directory is gone on both the success and the throwing path |
| refusals | a bundle with a non-empty `project.db-wal` throws `.bundleNotCheckpointed` and copies nothing; a non-existent bundle throws a typed error rather than trapping |

**Verify**:

```bash
swift test --package-path Packages/FilmBrain --filter BundleScorerTests
swift build --package-path Packages/FilmBrain --product filmcamp-eval
```

Expected: tests pass; the source bundle is byte-identical after both commands.

### Step 3: Report, executable, and eval inputs

Implement `EvalReport` JSON + markdown + baseline diff, `EvalInputs`, and the `score`, `save-answer-key`,
`report`, `run` (stub), and help subcommands.

| Suite | Coverage |
|---|---|
| `ReportRenderingTests` | render a fixed two-sample, four-row report (each sample at `default` and `reduced` budgets) against the committed `report-expected.md`/`.json`, constructing the `EvalReport` value directly with an injected `ReportEnvironment`, `manifest`, `inputsDigest`, and `runSettings` — it must **never** read the working tree, or Plan 007's new files would change the digest and break the fixture; check byte-stable re-encoding, the honesty header, `scorerSemanticsVersion` and `runSettings`, the `New`/`Resurr` columns (with the `(+p parser)` suffix) and their two list sections including the 25-item cap, the `▲/▼/=` annotations and `new` marker against `baseline.json`, the `—` rendering of every `nil`, that `--out foo.md` writes both files, that a row whose `chunkBudget` matches neither setting gets the `notes` entry, and that `report` rejects duplicate `(sample, label)` keys and disagreeing top-level fields |
| `EvalInputsTests` | the Swift manifest equals `scripts/eval-gate.sh --print-manifest` byte for byte, including `absent` lines (this suite deliberately compares two **live** derivations against the working tree, unlike `ReportRenderingTests`); a glob line is rejected by both |

**Verify**:

```bash
swift test --package-path Packages/FilmBrain --filter ReportRenderingTests
swift test --package-path Packages/FilmBrain --filter EvalInputsTests
BIN="$(swift build --package-path Packages/FilmBrain --show-bin-path)"
"$BIN/filmcamp-eval" --help; echo "help exit=$?"
"$BIN/filmcamp-eval" run; echo "run exit=$?"
"$BIN/filmcamp-eval" score; echo "usage exit=$?"
"$BIN/filmcamp-eval" save-answer-key --help; echo "help exit=$?"
"$BIN/filmcamp-eval" save-answer-key /nonexistent.aifilm --out /tmp/x.answer-key.json; echo "missing exit=$?"
test ! -e /tmp/x.answer-key.json && echo "wrote nothing on failure"
```

Expected: tests pass; `--help` prints all four subcommands and exits 0; `run` prints the Plan 007 message on
stderr and exits 2; `score` with no bundle prints a usage error and exits 1; `save-answer-key --help`
documents `--out` and `--sample`; a missing bundle prints a typed error, exits 1, and creates no output file.

### Step 4: Gate script, verify.sh wiring, .gitignore, and policy docs

Add `scripts/eval-inputs.txt`, `scripts/eval-run-settings.txt`, `scripts/eval-gate.sh` (`chmod +x`),
`./scripts/eval-gate.sh` at the end of `scripts/verify.sh`, `screenplays-private/` to `.gitignore`, and
`docs/eval/README.md`, which states:

- **The loop** (§7.2; nobody hand-authors a key): run extraction, review it in the app, then `filmcamp-eval
  save-answer-key <bundle> --out docs/eval/answer-keys/<sample>.answer-key.json`; later runs are scored with
  `filmcamp-eval score <bundle> --answer-key <that file>`. Re-exporting after a later review pass raises
  `version`; `newUnreviewed` is the queue driving that pass, and `resurrectedRejected` entries are the
  regressions to act on first — a scored run starts from a fresh bundle with no tombstones, so they are always
  a prompt or model regression, never an apply defect.
- Quit the app (or close the project) before running either subcommand: the tools refuse a bundle whose WAL is
  not checkpointed rather than copy a half-written database.
- How to read precision: it is `matched / (matched + resurrectedRejected)`, so with no rejections in the key it
  is 1.0 by construction and `Ent F1` then tracks recall alone; `parserResurrected` is informational.
- Per §7.2: `origin`, the honest limits, and the privacy rule. Plus the report-name rule above (`<date>-<git-sha>.md`, `YYYY-MM-DDTHHMMSSZ`, 7-char SHA) and
  its `.json` twin; the score-before-shipping policy, quoting the delta against the previous report in the
  commit message or PR; how to read each column (fragmentation only at `chunkCount ≥ 2`, `newUnreviewed`
  deliberately not a false-positive count, two rows per sample, baseline thresholds advisory); and what to do
  when `eval-gate.sh` fails, including the run-settings check and `absent` lines.

**Verify**:

```bash
./scripts/eval-gate.sh; echo "no-report exit=$?"
./scripts/eval-gate.sh --print-manifest
mkdir -p docs/eval
printf '{"reportVersion":1,"inputsDigest":"deadbeef","manifest":"","runSettings":{"chunkBudget":32000,"reducedBudget":16000,"concurrency":3,"chunkModel":null,"chunkEffort":null,"reconcileModel":null,"reconcileEffort":null}}' \
  > docs/eval/1970-01-01T000000Z-000000.json
./scripts/eval-gate.sh; echo "mismatch exit=$?"
printf '{"reportVersion":1,"inputsDigest":"%s","manifest":"","runSettings":{"chunkBudget":32000,"reducedBudget":16000,"concurrency":3,"chunkModel":null,"chunkEffort":null,"reconcileModel":null,"reconcileEffort":null}}' \
  "$(./scripts/eval-gate.sh --print-manifest | shasum -a 256 | cut -d' ' -f1)" \
  > docs/eval/1970-01-01T000000Z-000000.json
./scripts/eval-gate.sh; echo "null-settings exit=$?"
sed -i '' 's/^concurrency=3$/concurrency=4/' scripts/eval-run-settings.txt
./scripts/eval-gate.sh; echo "settings-mismatch exit=$?"
sed -i '' 's/^concurrency=4$/concurrency=3/' scripts/eval-run-settings.txt   # the file is untracked here; git checkout cannot restore it
grep -q '^concurrency=3$' scripts/eval-run-settings.txt
rm docs/eval/1970-01-01T000000Z-000000.json
git check-ignore -v screenplays-private/anything.fountain
./scripts/verify.sh
```

Expected: with no report, `eval-gate: no committed report yet; skipped` and exit 0 (the `|| true` guard);
the manifest lists every listed path in `LC_ALL=C` order with its SHA-256 or `absent`; with the fake digest,
exit 1 and a message naming the report and a manifest diff; with the matching digest and all-`null`
model/effort values, **exit 0** (the `json`-extraction rule — a `raw` extraction would abort here); with one
changed setting, exit 1 naming `concurrency`; `git check-ignore` reports the new `.gitignore` line;
`verify.sh` exits 0 with the final gate step a skip. Remove the fake report before continuing.

### Step 5: Exporter integration against reviewed state (requires Plan 005 `DONE`)

Only now can the exporter be exercised against real review signals. `AnswerKeyExporterTests` builds a bundle
with `ProjectBundle.create(at:name:)`, imports a `ScreenplaySamples` screenplay, and uses Plan 005's
`acceptFacts`, `rejectEntity`, `createEntity`, `renameEntity`, and `mergeEntities` to produce accepted, human,
rejected, and still-`proposed` rows plus states and events. Assert:

| Assertion | Detail |
|---|---|
| origin mapping | parser rows the operator accepted export as `"confirmed"`; parser rows the operator renamed export as `"corrected"` (`createdSource` stays `parser`); `createEntity` rows export as `"added"`; `proposed` rows and untouched parser rows (no `reviewedAt`) in neither array; rejected rows only in `rejected` with their retained aliases (§3.6); the exported key passes `AnswerKey.validate()` |
| loop | after `acceptFacts` over the parser rows, export → score gives recall 1.0, no `missingRequired`, no `resurrectedRejected`, `parserResurrected == 0`, and an identical `EvalRow` on a second run; rejecting one parser entity then importing the same screenplay into a fresh bundle and scoring it reports that entity under `parserResurrected`, not `resurrectedRejected` |
| merges, renames | a merged entity exports once with the source name among its aliases; a rename leaves the old name as an alias |
| shape | `appearsIn` holds scene ordinals, excludes role `.mentioned`, and is sorted-unique; states and events carry `{kind, name}` refs and lower-case keywords by the Step 1 rule |
| no leakage | with a screenplay containing the sentinel line `XYZZY-SENTINEL-TEXT`, the emitted JSON contains neither the sentinel nor any evidence `quote`, and `AnswerKey` has no `sourceText` key |
| versioning | `version` is 1 with no prior file and `previous.version + 1` with one; a corrupt existing `--out` throws, exits 1, and leaves the file untouched |

**Verify**:

```bash
swift test --package-path Packages/FilmBrain --filter AnswerKeyExporterTests
./scripts/verify.sh
git status --short
```

Expected: tests pass; `verify.sh` exits 0 — the FilmBrain suite now includes `FilmEvalTests` and the final
`eval-gate.sh` step is a skip — and `git status --short` lists only `Packages/FilmBrain/Package.swift`, the
new `Sources/FilmEval`, `Sources/filmcamp-eval` and `Tests/FilmEvalTests` files,
`Packages/FilmCore/Sources/FilmCore/Domain/Job.swift` (the `reusedProgressStage` constant; plus
`EntityNormalization.swift` only if it had to be made public), `scripts/eval-gate.sh`,
`scripts/eval-inputs.txt`, `scripts/eval-run-settings.txt`, `scripts/verify.sh`, `.gitignore`,
`docs/eval/README.md`, and this plan's status row; no `.aifilm` bundle, database, DerivedData, exported key,
or temp report. Suggested commits: `feat(eval): add FilmEval scorer`, `feat(eval): score bundles through a
checkpointed snapshot`, `feat(eval): add filmcamp-eval report tool`, `ci: gate on scored-run inputs`,
`test(eval): export answer keys from reviewed state`.

## Done criteria

- [ ] `FilmEval`, `filmcamp-eval`, and `FilmEvalTests` exist with exactly the target/product/dependency shape
  above; `ScreenplaySamples` is a test-target dependency only; no new external dependency, no
  `Package.resolved` change, no `project.yml` change; `FilmEval` holds no normalization, parsing, harness,
  GRDB, or SwiftUI code and is not linkable by the app (the executable may gain `FilmBrain` in Plan 007).
- [ ] `filmcamp-eval save-answer-key <bundle> --out <answer-key.json> [--sample <name>]` exports a §7.2 key
  from reviewed canonical state with `origin` ∈ {`confirmed`, `corrected`, `added`} derived from
  `createdSource`, reviewed-only aliases and appearances, `rejected`, `derivedFrom` (bundle and script digests,
  parser version, scene count), `{kind, name}` state and event refs, and a `version` incrementing over the key
  it replaces; `proposed` and unreviewed rows are excluded; the exporter validates before writing; a test
  proves the output holds no `sourceText` and no evidence quote.
- [ ] `AnswerKey.load` rejects a key with no `derivedFrom`, one whose `rejected` entry collides with an entry
  of the same kind, and one whose accepted entries share an alias within a kind.
- [ ] Every scorer metric is covered by a hand-computed test and matches exactly; matching is provably
  order-independent; an unlisted entity is `newUnreviewed` and does **not** reduce precision; a tombstone
  match by an AI-created entity is `resurrectedRejected` and does, by a parser-created one is
  `parserResurrected` and does not; an empty key is refused; a parse-binding mismatch is noted.
- [ ] Both `save-answer-key` and `score` refuse a bundle that is not checkpointed, digest the source before
  copying, re-verify it after, open only the copy, and clean up without a `defer` that awaits; a test asserts
  the source bundle is unchanged and `bundleSHA256` matches it.
- [ ] `usage` is summed over leaf attempts only, `requestCount` counts non-`Reused` leaves, `chunkCount`
  counts distinct `chunkIndex`, and the run is the newest completed `extractScreenplay` parent for the current
  script — each with a test.
- [ ] The report carries `reportVersion: 1`, `scorerSemanticsVersion`, and `runSettings`, supports two rows
  per sample with `chunkCount` and `chunkBudget`, reports P/R including and excluding `rejected`, the anchor
  rate, `newUnreviewed`, and `resurrectedRejected`, marks fragmentation inapplicable below two chunks, and
  prints the `derivedFrom` header plus the "not absolute truth" line.
- [ ] `score` scores any bundle and writes an `EvalReport` JSON; `report` merges report files and recomputes
  `totals`; `--baseline` annotates with `▲/▼/=`; `run` exits 2 with the Plan 007 message.
- [ ] `scripts/eval-inputs.txt` is the explicit §7.2 manifest (both schemas, both prompts, the chunker, the
  chunk-text builder, both tasks, both semantic validators, the reconcile input builder, the proposal
  builder, the apply/matching sources, `ScorerSemantics`, and the run settings file), contains no glob, and excludes the harness probe
  schema; `scripts/eval-gate.sh` passes with no report, passes with all-`null` model settings, fails on a
  digest mismatch and on a run-settings mismatch, and is the last step of `scripts/verify.sh`; `.gitignore`
  ignores `screenplays-private/`; `docs/eval/README.md` documents the loop, the living key, the
  score-before-shipping policy, the precision caveat, the report naming, and the gate's remedy.
- [ ] No answer key under `docs/eval/answer-keys/` was hand-authored (the decoding fixtures under
  `Tests/FilmEvalTests/Samples/` are deliberately hand-written test data, and Plan 002's repo-wide
  `.answer-key.json` guard is a point-in-time check that ends when this plan lands), no screenplay text was
  committed, and no live Codex call, network access, or `FILMCAMP_RUN_LIVE_CODEX` use occurred anywhere in
  this plan.
- [ ] `./scripts/verify.sh` exits 0; `docs/plans/README.md` marks Plan 006 `DONE`.

## STOP conditions

Stop and report instead of improvising if:

- The design-doc hash differs and §7 changed.
- A step appears to need a live model call, the network, or a harness process to be verifiable — that is Plan
  007's work. There is no deferral path: every command must pass before this plan is `DONE`.
- `ScreenplaySamples.url(named:)` is missing, or is not the frozen `(String) -> URL` of Plan 002. Likewise
  a `.answer-key.json` checked in from an earlier draft of Plan 002: it is hand-authored, §7.2 forbids it,
  and removing it is Plan 002's call.
- A bundle cannot be snapshotted without opening it (for example its WAL cannot be checkpointed from outside).
  Adding a FilmCore snapshot or backup operation is Plan 003's call — never copy a live bundle directory and
  never digest a `project.db` with a non-empty WAL.
- Plan 005 has not shipped the editing operations Step 5 needs: land Steps 1–4, leave Step 5 and this plan's
  row in `docs/plans/README.md` open, and report. Never fabricate review state through raw SQL.
- Any key or report field would have to carry screenplay text, an evidence quote, or a path outside the
  repository.
- Scoring would require extraction result files, `cache/jobs/`, or raw SQL instead of canonical state through
  `ProjectReading`; or `ProjectReading` cannot expose evidence such that entity-owned and synopsis rows
  partition the `evidence` table, which would make the anchor rate wrong.
- Agreeing with storage would require a second normalizer inside `FilmEval`, or the CLI appears to need
  `swift-argument-parser` or any other new dependency.
- Adding the executable product breaks the app build or the XcodeGen diff check.
- A verification command fails twice after one reasonable scoped correction. If the failure is demonstrably
  external test infrastructure that occurs before any test executes (for example, macOS UI automation mode
  cannot initialize), and every focused and deterministic gate for the change passed, stop changing code,
  commit the scoped work with the failed gate recorded, and report it; do **not** mark this plan `DONE` until
  a later full `./scripts/verify.sh` run passes. For a build failure, an executed test failure, or any failure
  plausibly caused by the change, stop without committing.

## Maintenance notes

- The scorer is a contract. Changing a metric's definition invalidates every committed report: change §7.2
  first, bump `ScorerSemantics.version` and `reportVersion`, and re-score before comparing old and new
  numbers. `report-expected.*` under `Tests/FilmEvalTests/Samples/` are regenerated deliberately and reviewed
  by hand — never to make a failing test pass. The answer key is the opposite: re-export after every review
  pass and let `version` be the audit trail, never hand-editing a key to improve a score.
- Changing `Keywords.stopWords` or `Keywords.limit` changes which states and events match, invalidating
  comparisons across keys exported on either side of the change; re-export to bump `version`.
- Plan 007 owns the `run` subcommand (import samples **by path** → extract → apply → score → write report,
  with `--sample <path>`, `--concurrency`, `--chunk-budget`, `--reduced-budget`, defaults from
  `scripts/eval-run-settings.txt`), the default and reduced-budget rows, the first exported key under
  `docs/eval/answer-keys/`, and the first committed baseline under `docs/eval/`. `scripts/eval-inputs.txt`
  already lists every extraction source and prompt Plan 007 creates (as `absent` lines until then); 007
  **reconciles** names — a renamed file means editing the list, never appending a second spelling and never
  a glob. Nothing else in `FilmEval` changes for it.
- Keep `scripts/eval-inputs.txt` precise: anything that can move a score belongs on it, and nothing else —
  a gate that fires on unrelated edits will be routed around.
