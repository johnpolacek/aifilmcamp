import FilmBrain
import FilmCore
import Foundation

/// The manifest-inference run on the **window model** (PHASE2_DESIGN §3.6, §8.5, §8.6, §9 —
/// Plan 012 contract D).
///
/// Shaped exactly like `ProjectWindowModel+Extraction.swift`, because it is the same three
/// beats: prepare (gate, then disclosure or confirm), start (progress, run, report), and
/// review (the run's proposals arrive in Plan 010's grammar, its suggestions as advisory
/// rows). Nothing here enforces §3.6 — FilmCore throws all three refusals from `createJob`
/// and `ManifestRunGate` asks the same questions before launching, so this only keeps the
/// section from offering what the store would reject, with the reason attached.
@MainActor
extension ProjectWindowModel {

    // MARK: - Availability (§3.6's gates, surfaced)

    var inferManifestButtonTitle: String { "Infer Asset Manifest" }

    /// Why a manifest run may not be launched right now, from FilmBrain's coordinator-side
    /// gate over this window's own job history — never a predicate restated here.
    var manifestRunRefusal: ManifestRunGate.Refusal? {
        guard let script else { return nil }
        return ManifestRunGate.refusal(scriptID: script.id, jobs: jobs)
    }

    /// The refusal copy, verbatim from the FilmCore error the store would throw.
    var manifestRunRefusalMessage: String? {
        manifestRunRefusal?.localizedDescription
    }

    var canInferManifest: Bool {
        script != nil && !isClosed && extractionAdapterFactory != nil
            && activeManifestRun == nil && activeExtractionRun == nil
            && manifestRunRefusal == nil
    }

    /// §3.6: a completed manifest run **permanently closes extraction for this screenplay**.
    var extractionIsClosedByManifest: Bool {
        guard let script else { return false }
        return ManifestRunGate.extractionIsClosed(scriptID: script.id, jobs: jobs)
    }

    /// What the Analyze action says for itself once inference closed extraction — the §3.6
    /// clause, from the one FilmCore constant, so the sentence the operator reads and the
    /// sentence the store throws cannot drift apart.
    var analyzeClosedByManifestReason: String? {
        guard extractionIsClosedByManifest else { return nil }
        return "Analyzing is closed for this screenplay: \(ManifestRunGate.extractionClosedReason)."
    }

    // MARK: - Prepare (§9's two copy blocks)

    /// Arms the run: the full §9 acknowledgement when this project has never acknowledged
    /// one, otherwise the compact per-run confirm sheet. **Nothing is sent until Continue** —
    /// the `ManifestRun` is constructed here but not started.
    func prepareManifestRun() async {
        guard canInferManifest, let extractionAdapterFactory else {
            if let refusal = manifestRunRefusal {
                error = .project(refusal)
            }
            return
        }
        do {
            let adapter = try extractionAdapterFactory()
            preparedManifestRun = ManifestRun(project: session, adapter: adapter)
            if try await session.disclosureAcknowledgedAt() == nil {
                pendingManifestDisclosure = ManifestDisclosurePresentation()
                pendingManifestConfirmation = nil
            } else {
                pendingManifestConfirmation = ManifestConfirmationPresentation()
            }
        } catch {
            self.error = .project(error)
            preparedManifestRun = nil
        }
    }

    /// Acceptance stores the acknowledgement through the door extraction shares (§9).
    func continueAfterManifestDisclosure() async {
        do {
            try await session.acknowledgeDisclosure()
            pendingManifestDisclosure = nil
            pendingManifestConfirmation = ManifestConfirmationPresentation()
        } catch {
            self.error = .project(error)
            cancelPreparedManifestRun()
        }
    }

    func cancelPreparedManifestRun() {
        pendingManifestDisclosure = nil
        pendingManifestConfirmation = nil
        preparedManifestRun = nil
    }

    // MARK: - Run

    func startPreparedManifestRun() async {
        guard let run = preparedManifestRun, activeManifestRun == nil else { return }
        pendingManifestDisclosure = nil
        pendingManifestConfirmation = nil
        preparedManifestRun = nil
        activeManifestRun = run
        manifestProgress = .init(stage: .planning, message: "Preparing manifest inference")
        await startManifestProgressObservation(for: run)
        do {
            let report = try await run.start(
                engine: "codex",
                engineVersion: "current",
                settings: ManifestSettings()
            )
            // An AI run's journal entries are not this window's, so the stack goes (§3.8).
            undoManager.removeAllActions()
            syncUndoMenu()
            presentedManifestReport = ManifestReportPresentation(report: report)
            activeManifestRun = nil
            manifestProgressTask?.cancel()
            manifestProgressTask = nil
            await refresh()
        } catch {
            self.error = .project(error)
            activeManifestRun = nil
            manifestProgressTask?.cancel()
            manifestProgressTask = nil
            await refresh()
        }
    }

    func cancelManifestRun() async {
        guard let activeManifestRun else { return }
        do {
            try await activeManifestRun.cancel()
        } catch {
            self.error = .project(error)
        }
        manifestProgressTask?.cancel()
        manifestProgressTask = nil
        self.activeManifestRun = nil
        await refresh()
    }

    private func startManifestProgressObservation(for run: ManifestRun) async {
        manifestProgressTask?.cancel()
        // The continuation is installed before `start()` can emit, for the reason the
        // extraction observer documents: a fast recorded run otherwise leaves the section
        // showing the locally seeded planning line forever.
        let stream = await run.progress()
        manifestProgressTask = Task { [weak self] in
            for await progress in stream {
                guard let self, !Task.isCancelled else { return }
                self.manifestProgress = progress
            }
        }
    }

    // MARK: - Inclusion suggestions (§3.4: advisory, never auto-applied)

    /// The newest completed manifest run's persisted suggestions, as advisory rows.
    ///
    /// They live in `jobs.apply_report` (§8.5), which is why they survive reopen: this reads
    /// the stored report rather than any in-memory run state. Props never appear — §3.4 gives
    /// them the direct-proposal channel, and the validator refuses a prop suggestion outright.
    var manifestInclusionSuggestions: [ManifestSuggestionRow] {
        guard let report = newestManifestRun?.job.manifestReport else { return [] }
        return report.suggestions.map { suggestion in
            ManifestSuggestionRow(
                suggestion: suggestion,
                entityName: entityNames[suggestion.entityID] ?? "Unknown entity"
            )
        }
    }

    /// One click on an advisory row: the human override §3.4 describes, performed as
    /// `.human` through §7.2's operation — the run never wrote `manifest_inclusion` itself.
    func applyManifestSuggestion(_ row: ManifestSuggestionRow) async {
        await runEdit {
            try await self.session.setManifestInclusion(
                entityID: row.entityID, inclusion: row.inclusion, actor: .human
            )
        }
    }

    // MARK: - Reviewing what the run proposed (§8.6)

    /// The Manifest section's own review banner count: proposed **requirement** rows, which
    /// `pendingReviewCount()` (Phase 1's entity-side tally) does not include.
    var hasProposedRequirements: Bool { proposedRequirementCount > 0 }

    /// The banner's Accept All: exactly the proposed requirement rows, in **one** operation
    /// and therefore one undo step, through §7's `acceptFacts`. The rows are read rather than
    /// taken off the filtered list, so the current filter cannot narrow what Accept All means.
    func acceptAllProposedRequirements() async {
        guard !isClosed else { return }
        do {
            let proposed = try await session.requirementSummaries(
                kind: nil, tier: nil, reviewState: .proposed, includeRejected: false
            )
            await acceptFacts(refs: proposed.map { SubjectRef(kind: .requirement, id: $0.id) })
        } catch {
            self.error = .project(error)
        }
    }

    // MARK: - The Jobs section, task-aware (contract D)

    /// The newest completed run of **either** bootstrap task — what "Revert last run"
    /// resolves. `RevertOperations`' closed task list is still the authority; this only
    /// keeps the button from offering what FilmCore refuses — and a prompt run never
    /// offers Revert at all (PHASE3_DESIGN §7.4's prohibition, §8.4): recovery is undo
    /// while on the stack, `deletePrompt` forever after.
    var newestRevertableRun: RunSummary? {
        runs.last {
            $0.job.state == .completed && $0.job.task != Job.assetPromptTask
                && $0.job.task != Job.scenePromptTask
        }
    }

    var canRevertLastRun: Bool { newestRevertableRun != nil }

    var newestManifestRun: RunSummary? {
        runs.last { $0.job.task == Job.manifestTask && $0.job.state == .completed }
    }

    /// One run row's label. Extraction keeps its chunk count; single-request parent kinds
    /// use a semantic label. A scene-prompt run owns one generation child and may own an
    /// independent quality-review child, but its parent remains the filmmaker-facing run.
    func runRowTitle(_ run: RunSummary) -> String {
        var parts = ["Run \(run.runNumber)"]
        if let started = run.job.startedAt {
            parts.append(started.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append(runRowKindLabel(run))
        parts.append(run.job.state.displayName)
        if let duration = jobDurationSummary(run.job) { parts.append(duration) }
        parts.append(runTokenSummary(run.usage))
        return parts.joined(separator: " · ")
    }

    /// One run's kind label. Child counts are useful for extraction fan-out, while the
    /// two scene-prompt children have their own named rows below.
    private func runRowKindLabel(_ run: RunSummary) -> String {
        switch run.job.task {
        case Job.manifestTask: "Manifest run"
        case Job.assetPromptTask: "Prompt run"
        case Job.scenePromptTask: "Scene prompt run"
        default: "\(run.childCount) chunks"
        }
    }

    /// The run's report line, whichever report its task wrote (§8.5's counters beside
    /// extraction's). `nil` before a run has committed one.
    func runReportLine(_ run: RunSummary) -> String? {
        if let report = run.job.applyReport {
            return "Applied \(report.applied) · Replaced \(report.replaced) "
                + "· Skipped locked \(report.skippedLocked) "
                + "· Unanchored \(report.unanchoredEvidence)"
        }
        if let report = run.job.manifestReport {
            return "Created \(report.created) · Skipped existing \(report.skippedExisting) "
                + "· Suggestions \(report.suggestions.count)"
        }
        if let report = run.job.assetPromptReport {
            return "Prompt \(report.promptNumber) · Routed to \(report.targetModel) "
                + "· References \(report.referenceCount)"
        }
        if let report = run.job.scenePromptReport {
            return "Scene prompt \(report.promptNumber) · Profile \(report.targetProfile) "
                + "· References \(report.referenceCount)"
        }
        return nil
    }

    func childRowTitle(_ job: Job) -> String {
        var parts: [String] = []
        if let index = job.chunkIndex, let count = job.chunkCount {
            parts.append("Chunk \(index + 1) of \(count)")
            parts.append("attempt \((job.attemptIndex ?? 0) + 1)")
        } else {
            switch job.task {
            case Job.scenePromptTask:
                parts.append("Prompt generation")
            case Job.scenePromptRefinementTask:
                parts.append("Prompt quality review")
            default:
                parts.append(job.task)
            }
        }
        parts.append(job.progressStage == Job.reusedProgressStage
            ? Job.reusedProgressStage : job.state.displayName)
        if let duration = jobDurationSummary(job) { parts.append(duration) }
        parts.append(runTokenSummary(job.usage))
        return parts.joined(separator: " · ")
    }

    /// A run's child jobs in stable creation order. Extraction children carry chunk and
    /// attempt positions; scene-prompt children retain insertion order (draft, review).
    func runChildren(of run: RunSummary) -> [Job] {
        jobs
            .filter { $0.parentJobID == run.job.id }
            .sorted {
                if $0.chunkIndex != $1.chunkIndex {
                    return ($0.chunkIndex ?? Int.max) < ($1.chunkIndex ?? Int.max)
                }
                if $0.attemptIndex != $1.attemptIndex {
                    return ($0.attemptIndex ?? 0) < ($1.attemptIndex ?? 0)
                }
                func scenePromptPass(_ job: Job) -> Int {
                    switch job.task {
                    case Job.scenePromptTask: 0
                    case Job.scenePromptRefinementTask: 1
                    default: 2
                    }
                }
                let lhsPass = scenePromptPass($0)
                let rhsPass = scenePromptPass($1)
                if lhsPass != rhsPass { return lhsPass < rhsPass }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func runTokenSummary(_ usage: JobUsage) -> String {
        "\((usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)) tokens"
    }

    private func jobDurationSummary(_ job: Job) -> String? {
        guard let startedAt = job.startedAt, let endedAt = job.endedAt else { return nil }
        let seconds = max(0, Int(endedAt.timeIntervalSince(startedAt).rounded()))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

/// One advisory `manifest_inclusion` suggestion, ready to render (§3.4, §8.5).
struct ManifestSuggestionRow: Identifiable, Equatable, Sendable {
    let suggestion: ManifestInclusionSuggestion
    let entityName: String

    var id: UUID { suggestion.entityID }
    var entityID: UUID { suggestion.entityID }
    var direction: ManifestInclusionSuggestion.Direction { suggestion.direction }
    var reason: String { suggestion.reason }

    /// What the one-click action would set. `promote` is §3.3's `'always'` override,
    /// `suppress` its `'never'`.
    var inclusion: ManifestInclusion {
        switch direction {
        case .promote: .always
        case .suppress: .never
        }
    }

    var actionTitle: String {
        switch direction {
        case .promote: "Always Include"
        case .suppress: "Never Include"
        }
    }

    var line: String {
        let confidence = suggestion.confidence.map { " (\(Int(($0 * 100).rounded()))%)" } ?? ""
        let verb = direction == .promote ? "Suggests including" : "Suggests excluding"
        return "\(verb) \(entityName)\(confidence): \(reason)"
    }
}

struct ManifestDisclosurePresentation: Identifiable, Equatable {
    let id = UUID()
}

struct ManifestConfirmationPresentation: Identifiable, Equatable {
    let id = UUID()
}

struct ManifestReportPresentation: Identifiable, Equatable {
    let id = UUID()
    let report: ManifestApplyReport
}
