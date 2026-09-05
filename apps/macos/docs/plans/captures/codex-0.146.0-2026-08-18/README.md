# Codex CLI 0.146.0 capture set (2026-08-18)

Real `codex exec --json` streams captured on 2026-08-18 against Codex CLI
0.146.0 (ChatGPT login), using the Plan 001 invocation shape. They exist so
Steps 3–5 of `docs/plans/001-build-phase-0-spine-spike.md` can start from
observed CLI behavior instead of hand-authored guesses. Copy them into
`Packages/FilmBrain/Tests/FilmBrainTests/Fixtures/` when that package exists;
this directory is documentation, not a package.

## Provenance

- Codex CLI: `codex-cli 0.146.0`, npm/fnm install (`#!/usr/bin/env node`
  launcher), authenticated via ChatGPT login.
- Invocation (global flags before `exec`, exactly as the plan specifies):

  ```text
  codex --ask-for-approval never --sandbox read-only -C <empty-workspace> \
    -c project_doc_max_bytes=0 \
    exec --ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check \
    --color never --json --output-schema <schema> --output-last-message <result> -
  ```

- stdin: a fixed instruction plus a three-line synthetic screenplay
  (`INT. CAMP CABIN - NIGHT` / `MAYA sits by the fire.`). Nothing here derives
  from a commercial screenplay.
- Redaction: every real `thread_id` was replaced with a stable fixture ID.
  Nothing else was changed. The captures contained no filesystem paths,
  usernames, prompts, or credentials.

## Files

| File | What it is | Use it for |
|------|------------|------------|
| `codex-success-error-item.jsonl` | Verbatim successful stream. Contains an `item.completed` whose nested `item.type` is `error` ("Skill descriptions were shortened…") **followed by** `agent_message` and `turn.completed`. Exit was 0 and the result file was schema-valid. | The "nested error-typed item is diagnostic, not terminal" regression case. |
| `codex-success.jsonl` | Same stream with the nested error item removed. | Plain `codex-success.jsonl` bootstrap fixture. |
| `codex-failure-schema-rejected.jsonl` | Terminal failure: top-level `error` + `turn.failed`, process exit 1, no result file. Cause: `schemaVersion` declared as `{"const": 1}` without `type`. | `codex-failure.jsonl` bootstrap fixture; also documents why the plan requires `{"type":"integer","const":1}`. |
| `result-success.json` | The `--output-last-message` file from the successful run. | Bootstrap `analyze-valid.json` (it validates against `schema-accepted.json`). |
| `schema-accepted.json` | The plan-conformant schema that Codex accepted: typed `const`, `pattern` IDs, `minItems`/`maxItems`, nullable `["string","null"]`, `additionalProperties:false`, no `maxLength`, no `$schema`. | Starting point for `analyze-screenplay-v1.schema.json`. |
| `schema-rejected-const-without-type.json` | The variant Codex rejected. | Negative test for the Step 4 schema preflight. |
| `stderr-diagnostic-on-success.txt` | The single stderr line emitted during the *successful* run: an `ERROR`-level Codex log about a local models cache. | "stderr never fails a job" regression case. |

## Observations worth keeping

- `thread.started` carries only `thread_id`; no model identifier anywhere in
  the stream. `effective_model` will be null on 0.146.0.
- `turn.completed.usage` keys observed: `input_tokens`, `cached_input_tokens`,
  `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens`.
  Tolerate unknown usage keys.
- A three-line screenplay cost ~17k input tokens: base instructions plus the
  user's installed skills/plugins are in context even with
  `--ignore-user-config`.
- Separately probed and accepted on 0.146.0 (not included as fixtures):
  `maxLength` on strings and a top-level `$schema`. The plan intentionally
  omits both from the Codex-facing schema.
