# AI Film Camp — agent rules

- Before changing code, read `docs/plans/README.md`, the plan you are executing, and `docs/PHASE1_DESIGN.md` in full.
- This repository is in prototype mode and intentionally has no automated test
  suites. Historical design documents and completed plans may describe tests,
  fixtures, evaluation gates, or `scripts/verify.sh`; those requirements are
  suspended until the product reaches MVP. Do not add testing infrastructure
  unless the product owner explicitly ends prototype mode.
- `FilmCore` owns domain, storage, migrations, provenance, and controlled mutations; it imports neither FilmBrain nor SwiftUI.
- `FilmBrain` owns harness discovery and execution, structured jobs, and validation. Read `docs/REFERENCE_PROJECTS.md` before changing discovery, transports, process lifecycle, approvals, or MCP.
- SwiftUI is presentation only — no `Process`, Codex arguments, GRDB, validation, or parsing.
- AI output is untrusted: validate it structurally and semantically, then commit in one transaction.
- Provider API keys may be accepted only through dedicated settings UI, stored only in
  macOS Keychain, and held ephemerally for an authorized provider request. Never write
  them to project bundles, `UserDefaults`, command arguments, diagnostics, analytics,
  logs, tests, fixtures, or source control; never reveal or copy them back to the UI.
- Live Codex needs `FILMCAMP_RUN_LIVE_CODEX=1` and per-run operator approval. Never in CI.
- Provider integrations may submit generation-ready scene prompt cards, recover
  asynchronous paid jobs, and ingest validated immutable generated outputs with
  provenance. Higgsfield is the first integration. Stop at the editing handoff:
  no timeline, trimming, compositing, grading, audio mixing, or final rendering.
- `PromptSkills/` is vendored third-party payload, not app code. Never edit it in place and never import it from Swift; see `PromptSkills/README.md`.
- Documentation/planning-only changes require `scripts/check-docs.sh`.
- Code, schema, app, provider, and tooling changes require `scripts/build.sh`.
