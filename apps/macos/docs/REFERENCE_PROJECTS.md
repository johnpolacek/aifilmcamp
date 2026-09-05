# Harness Reference Projects

## Purpose

AI Film Camp uses four open-source macOS and Swift projects as implementation references for local AI harness integration:

```text
aifilmcamp-app/
aifilmcamp-app-references/
├── AIWorkstation/
├── Calyx/
├── rxcode/
└── swift-acp/
```

The expected local path from this repository is `../aifilmcamp-app-references/`.

These projects are an advisory pattern library. They are not runtime dependencies, architectural authorities, or product requirements. Film Camp's product boundary, FilmCore model, and validated persistence rules remain canonical.

The current copies are downloaded source snapshots without Git metadata. Before depending on an implementation detail, check its upstream project for changes and record the upstream version or commit used in the relevant plan, pull request, or architecture decision.

## How We Use the References

Start with a Film Camp use case, then consult the smallest relevant implementation and its tests. Write a Film Camp-native interface before adapting or copying code.

Reference priority for harness transport:

1. A native structured protocol exposed by the harness.
2. Agent Client Protocol (ACP), when the harness supports it well enough.
3. A non-interactive CLI mode with structured output.
4. A PTY-backed terminal as a compatibility fallback, never as the source of schema-critical batch data.

This order is a design preference, not a promise that every provider supports every mode. Each FilmBrain adapter must advertise its real capabilities rather than pretend all harnesses are equivalent.

When reusing a pattern:

1. Confirm that it solves a current Film Camp requirement.
2. Inspect the implementation, neighboring types, and tests in the reference project.
3. Preserve the FilmBrain/FilmCore boundary.
4. Copy only the minimum code or idea needed.
5. Review the source license and retain required notices or attribution.
6. Add Film Camp contract tests or recorded-event fixtures.
7. Document important divergence from the reference.

## Project Index

| Project | Best used for | Do not inherit |
| --- | --- | --- |
| [Calyx](https://github.com/yuuichieguchi/Calyx) (MIT) | Broad provider integration, provider-specific hooks and configuration, normalized agent status, approvals, MCP wiring, and session recovery | An embedded terminal product, terminal-driven feature scope, or silent modification of a user's harness configuration |
| [AIWorkstation](https://github.com/sbaruwal/AIWorkstation) (MIT) | Finder-safe CLI discovery, manual binary overrides, a small process/controller/registry split, and a readable PTY fallback | Terminal-screen parsing for structured jobs, a canvas UI, or Git-worktree product scope |
| [RxCode](https://github.com/rxtech-lab/rxcode) (Apache-2.0) | A provider-neutral backend protocol, capability sets, actor-isolated services, normalized async event streams, Codex app-server integration, ACP integration, permissions, and MCP | A coding IDE, editor/Git features, mobile sync, or its provider-specific request envelope as Film Camp's public domain API |
| [swift-acp](https://github.com/wiedymi/swift-acp) (MIT) | A pure-Swift ACP client/server SDK, JSON-RPC transport, capability negotiation, streaming updates, permissions, process lifecycle, and agent discovery | Making ACP mandatory, exposing unrestricted filesystem or terminal delegates, or assuming all ACP agents implement optional capabilities consistently |

## What to Inspect by Task

### Adapter Contract and Capabilities

Start with RxCode:

- `../aifilmcamp-app-references/rxcode/Packages/Sources/RxCodeCore/Backend/AgentBackend.swift`
- `../aifilmcamp-app-references/rxcode/Packages/Sources/RxCodeCore/Backend/BackendCapability.swift`
- `../aifilmcamp-app-references/rxcode/RxCodeTests/MockAgentBackend.swift`

RxCode demonstrates a useful separation between a common actor-based backend, a request envelope, provider capabilities, normalized `AsyncStream` events, cancellation, and finalization. FilmBrain should adopt the separation, not the exact coding-agent capabilities or provider-specific fields.

For negotiated protocol capabilities, also inspect:

- `../aifilmcamp-app-references/swift-acp/Sources/ACPModel/Capabilities.swift`
- `../aifilmcamp-app-references/swift-acp/Sources/ACPModel/Updates.swift`
- `../aifilmcamp-app-references/swift-acp/Sources/ACP/Client.swift`

FilmBrain should describe capabilities that matter to Film Camp, including:

- structured result delivery
- progress and event streaming
- cancellation
- interactive approvals
- session creation and resume
- controlled Film Camp tools or MCP
- non-interactive execution
- transport kind and compatibility status

Do not design to the lowest common denominator. An adapter reports a capability; the calling feature either requires it, supplies a safe Film Camp-side fallback, or explains why that harness cannot perform the task.

### CLI Discovery from a Finder-Launched App

Start with AIWorkstation:

- `../aifilmcamp-app-references/AIWorkstation/AIWorkstation/Agent/AgentCLI.swift`

It shows why a Finder-launched app cannot rely on its inherited `PATH`, how to ask the user's login shell, how to bound shell startup with a timeout, how to check common install locations, and how to support a manual executable override.

Treat Finder-safe discovery and Finder-safe execution as one problem. Use an
interactive login shell for the bounded lookup because common fnm/nvm setup
lives in `.zshrc`; attach `/dev/null` to stdin and do not interpolate user
input. Resolve candidates for deduplication, continue after a failed probe, and
retain the first candidate that actually passes version/capability checks.

For the real job, launch the selected absolute executable directly—never a
shell command string—but give it a minimal allowlisted environment containing
an explicitly framed login-shell `PATH` and optional `CODEX_HOME`, plus ordinary
GUI process values such as `HOME`, `TMPDIR`, and locale. Do not parse a full
`env` dump. This is required for npm or fnm launchers whose shebang uses
`/usr/bin/env node`. Do not copy the shell
environment wholesale or forward API-key/credential variables. RxCode's
environment resolution is useful evidence for the `PATH` requirement, but Film
Camp should narrow the resulting environment before execution:

- `../aifilmcamp-app-references/rxcode/RxCode/Services/CodexAppServer+Process.swift`

Compare Calyx for additional tool and session resolution patterns:

- `../aifilmcamp-app-references/Calyx/Calyx/Features/AgentMonitor/AgentToolPaths.swift`
- `../aifilmcamp-app-references/Calyx/Calyx/Features/Sessions/SessionBinaryResolver.swift`

Film Camp discovery must distinguish at least:

```text
not installed
installed but not authenticated
installed but incompatible
ready, with reported capabilities
```

Discovery must be bounded, non-blocking to the UI, and testable without depending on the developer machine's shell configuration.

### Structured Process and Event Lifecycles

Start with the provider services and stream coordinator in RxCode:

- `../aifilmcamp-app-references/rxcode/RxCode/Services/ClaudeService.swift`
- `../aifilmcamp-app-references/rxcode/RxCode/Services/ClaudeService+Process.swift`
- `../aifilmcamp-app-references/rxcode/RxCode/Services/CodexAppServer.swift`
- `../aifilmcamp-app-references/rxcode/RxCode/Services/CodexAppServer+Protocol.swift`
- `../aifilmcamp-app-references/rxcode/RxCode/Services/CodexAppServer+Process.swift`
- `../aifilmcamp-app-references/rxcode/RxCode/Services/ACPService.swift`
- `../aifilmcamp-app-references/rxcode/RxCode/App/AppState+Stream.swift`

Use these to inform actor isolation, one-turn lifecycle ownership, JSON-RPC framing, event normalization, cancellation, cleanup, and prevention of double completion.

FilmBrain's normalized event vocabulary should stay small and product-oriented. A starting point is:

```text
started
progress
message
toolCall
approvalRequired
completed
failed
cancelled
```

Provider payloads should remain inside the adapter unless retaining a redacted diagnostic payload is explicitly useful.

### PTY Compatibility Fallback

Use AIWorkstation when an interactive terminal is truly necessary:

- `../aifilmcamp-app-references/AIWorkstation/AIWorkstation/Terminal/TerminalController.swift`
- `../aifilmcamp-app-references/AIWorkstation/AIWorkstation/Terminal/TerminalRegistry.swift`
- `../aifilmcamp-app-references/AIWorkstation/AIWorkstation/Persistence/WorkspaceStore.swift`

The controller/registry split is useful: a live process has stable ownership independent of SwiftUI redraws, while persisted UI state does not pretend a dead PTY survived relaunch.

Terminal output heuristics may support user-facing activity hints, but they must not create canonical scenes, assets, prompts, or other schema-critical data. Those flows require structured output that Film Camp can validate.

### Provider Hooks and Configuration Files

Calyx has the broadest set of provider-specific configuration examples:

- `../aifilmcamp-app-references/Calyx/Calyx/Features/AgentMonitor/AgentHooksCoordinator.swift`
- `../aifilmcamp-app-references/Calyx/Calyx/Features/AgentMonitor/ClaudeHooksConfigManager.swift`
- `../aifilmcamp-app-references/Calyx/Calyx/Features/AgentMonitor/CodexHooksConfigManager.swift`
- `../aifilmcamp-app-references/Calyx/Calyx/Features/AgentMonitor/GrokHooksConfigManager.swift`
- `../aifilmcamp-app-references/Calyx/Calyx/Features/AgentMonitor/AgentEvent.swift`
- `../aifilmcamp-app-references/Calyx/Calyx/Features/AgentMonitor/AgentRegistry.swift`

Useful patterns include independent per-provider results, managed configuration sections, reversible install/remove operations, preserving unrelated user configuration, normalizing different event envelopes, source precedence, and stale-session cleanup.

Film Camp must make any configuration change explicit and reversible. It must never silently install or re-enable integrations merely because a CLI appears on disk.

### Approvals and Permission Requests

Compare all three levels:

- Calyx UI/state patterns:
  - `../aifilmcamp-app-references/Calyx/Calyx/Features/ApprovalInbox/ApprovalInboxStore.swift`
  - `../aifilmcamp-app-references/Calyx/Calyx/Features/ApprovalInbox/ApprovalPolicy.swift`
- RxCode request routing:
  - `../aifilmcamp-app-references/rxcode/RxCode/Services/PermissionServer.swift`
- ACP protocol types and delegate boundary:
  - `../aifilmcamp-app-references/swift-acp/Sources/ACPModel/Permission.swift`
  - `../aifilmcamp-app-references/swift-acp/Sources/ACP/ClientDelegate.swift`

Film Camp approvals should describe the requested Film Camp operation in product language. A harness approval is not, by itself, authorization to bypass Film Camp validation or write directly to `project.db`.

### MCP and Controlled Film Camp Tools

Compare Calyx and RxCode for configuration and server lifecycle:

- `../aifilmcamp-app-references/Calyx/Calyx/Features/IPC/CalyxMCPServer.swift`
- `../aifilmcamp-app-references/Calyx/Calyx/Features/IPC/MCPProtocol.swift`
- `../aifilmcamp-app-references/rxcode/RxCode/Services/MCPService.swift`

For ACP-provided MCP session configuration, inspect:

- `../aifilmcamp-app-references/swift-acp/Sources/ACP/Client.swift`
- `../aifilmcamp-app-references/swift-acp/Sources/ACPModel/Session.swift`

Film Camp tools expose narrow domain operations such as querying a scene, checking asset readiness, or proposing a validated update. They do not expose SQLite, arbitrary SQL, or unrestricted bundle mutation.

### Session Recovery and Reconnection

Start with Calyx:

- `../aifilmcamp-app-references/Calyx/Calyx/Features/Persistence/SessionPersistenceActor.swift`
- `../aifilmcamp-app-references/Calyx/Calyx/Features/Sessions/SessionReconnectCoordinator.swift`

Compare ACP session discovery and loading in:

- `../aifilmcamp-app-references/swift-acp/Sources/ACP/Client.swift`

Persist Film Camp job metadata and provider session identifiers, not live process objects. On relaunch, verify the provider, working directory, project identity, and session capability before offering resume.

### Process Shutdown and Cancellation

Compare:

- `../aifilmcamp-app-references/swift-acp/Sources/ACP/Internal/ProcessManager.swift`
- `../aifilmcamp-app-references/swift-acp/Sources/ACP/Transport/StdioTransport.swift`
- `../aifilmcamp-app-references/rxcode/RxCode/Services/CodexAppServer+Process.swift`
- `../aifilmcamp-app-references/rxcode/RxCode/Services/ClaudeService+Process.swift`

Define cancellation as a FilmBrain contract, not a UI convenience. A cancelled job must stop accepting events, release process resources, and never commit a partial canonical mutation.

## Planning Guide by Film Camp Phase

### Phase 0 — Spine Spike

Use the references to reduce infrastructure uncertainty without expanding the product:

- Model the FilmBrain adapter boundary after RxCode's backend/capability split.
- Model Finder-safe CLI discovery after AIWorkstation.
- Carry the discovered launch environment into execution and cover a
  `/usr/bin/env node` launcher with a Finder-empty-`PATH` test.
- Implement one structured Codex path first. Plan 001 deliberately uses non-interactive `codex exec` because it is the smallest Phase 0 proof; RxCode's Codex app-server implementation is a later evaluation reference, not a reason to expand the spike.
- Create a fake adapter and recorded normalized event fixtures before adding another provider.
- Treat Calyx's hooks/configuration as a later provider-compatibility option, not a Phase 0 requirement.
- Evaluate `swift-acp` behind the FilmBrain boundary; do not make Phase 0 wait for ACP or expose ACP types to FilmCore.

### Phases 1, 2, and 5 — Structured Batch Work

Screenplay extraction, asset inference, and prompt generation require:

- structured results
- schema validation outside the harness
- progress reporting
- cancellation
- one validated persistence transaction
- replayable adapter tests that do not require a live CLI in CI

Do not use terminal scraping for these phases.

#### Phase 1 specifics

Phase 0 ran one job at a time. Phase 1 runs many structured jobs per screenplay
and adds four seams the references already solved. Consult them in the plan that
owns each seam; the plan must name what it adopts and what it rejects.

| Seam | Phase 1 owner | Inspect |
| --- | --- | --- |
| Generic runner over a task, with capabilities the caller requires rather than assumes | Plan 003 | `rxcode/Packages/Sources/RxCodeCore/Backend/AgentBackend.swift`, `.../BackendCapability.swift` |
| Normalized failure/event envelopes across providers | Plan 003 | `Calyx/Calyx/Features/AgentMonitor/AgentEvent.swift`, `rxcode/RxCode/App/AppState+Stream.swift` |
| A replayable test double scripted per request | Plans 003, 007 | `rxcode/RxCodeTests/MockAgentBackend.swift` |
| Process shutdown that leaves no orphan | Plan 007 | `swift-acp/Sources/ACP/Internal/ProcessManager.swift`, `swift-acp/Sources/ACP/Transport/StdioTransport.swift`, `rxcode/RxCode/Services/CodexAppServer+Process.swift` |
| Bounded concurrency and one-turn lifecycle ownership across many in-flight jobs | Plan 007 | `rxcode/RxCode/Services/ACPService.swift`, `rxcode/RxCode/App/AppState+Stream.swift` |
| Pause and resume that survive relaunch | Plan 007 (runs), Plan 003 (abandoned-job reaping) | `Calyx/Calyx/Features/Persistence/SessionPersistenceActor.swift`, `Calyx/Calyx/Features/Sessions/SessionReconnectCoordinator.swift` |

Load-bearing detail from `ProcessManager.swift`: it makes the child its own
process-group leader (`setpgid(pid, pid)`) at launch, then on shutdown detaches
readability handlers, closes pipes, drains output, signals the **group**
(`killpg`), waits two seconds, and escalates to `SIGKILL` on the group. Film
Camp must signal the group for the same reason: a Codex installed through npm is
a `/usr/bin/env node` launcher that spawns the real binary as a child, so
signalling the launcher alone can orphan it. Film Camp's ladder starts at
`SIGINT` rather than `SIGTERM` because `codex exec` handles only `SIGINT`
gracefully.

**Plans that need no reference at all**: 002 (parser and samples), 005 (editing,
provenance, locks), 006 (evaluation scorer). They touch no harness, transport,
process, or approval surface. Do not spend executor time there.

### Phase 6 — Interactive Production Assistant

Revisit `swift-acp`, Calyx MCP, and RxCode MCP/permission patterns when controlled Film Camp tools become necessary.

The assistant may inspect canonical data and propose changes through tools. Film Camp remains the authorization, validation, and persistence boundary.

### Adding Claude Code, Grok, or Another Harness

Adding a provider should require a new FilmBrain adapter and compatibility fixtures, not a FilmCore migration.

For each provider, document:

- executable discovery and supported versions
- authentication detection
- preferred transport and fallback transport
- structured output behavior
- progress/event behavior
- cancellation behavior
- approval behavior
- session resume behavior
- controlled-tool or MCP behavior
- known limitations and compatibility tests

## Explicit Non-Adoptions

These reference projects solve adjacent problems that are outside Film Camp's current product boundary. Do not add them merely because working code exists:

- a general-purpose embedded terminal
- a source-code editor or coding IDE
- Git branch or worktree management
- a multi-agent coding cockpit or agent canvas
- unrestricted shell, filesystem, or database tools
- mobile agent control or cloud session sync
- provider credential ownership
- provider-specific objects in FilmCore

## License and Provenance

The local projects currently declare these licenses:

- Calyx — MIT
- AIWorkstation — MIT
- RxCode — Apache License 2.0
- swift-acp — MIT

Ideas and architectural patterns can be reimplemented in Film Camp. Directly copied or substantially adapted code must be reviewed against the applicable license, preserve required copyright/license notices, and be called out in the implementation record. Dependency licenses must also be included in the app's eventual third-party notices.
