import FilmBrain
import FilmCore
import Foundation

/// The asset-prompt run on the **window model** (PHASE3_DESIGN §8, §9; Plan 016
/// contract E) — the manifest run's three beats at single-requirement scale:
/// prepare (gate, then disclosure or confirm), start (progress, run, apply), and review.
/// The reference-image workflow deliberately collapses prepare + start. Missing detail
/// starts preparation on open; only the project's one-time disclosure may pause that path.
///
/// Two deliberate deviations from the manifest beat sheet, both §13.11: the apply is
/// **invertible**, so success routes the returned journal entry through `didApply` and ⌘Z
/// reads "Undo Generate Prompt" — the undo stack survives generation — and a prompt run is
/// **never** offered Revert (§7.4's prohibition; the Jobs arm below enforces the UI half).
@MainActor
extension ProjectWindowModel {

    // MARK: - Availability (§5.8's Generate/Regenerate rows)

    /// Why Generate/Regenerate may not run right now — every decided condition evaluated,
    /// with FilmCore's own sentences. `nil` means enabled.
    var generateDisabledReason: String? {
        guard promptRunRequirementDetail != nil else { return nil }
        if activePromptRun != nil { return "A prompt run is already active." }
        guard let refusal = promptRunRefusal else { return nil }
        return refusal.error.errorDescription
    }

    /// The coordinator-side gate over this window's own job history and the selected
    /// requirement's detail — never a predicate restated here.
    var promptRunRefusal: AssetPromptRunGate.Refusal? {
        guard let detail = promptRunRequirementDetail else { return nil }
        let bootstrapsIdle = !jobs.contains {
            $0.parentJobID == nil
                && ($0.task == Job.extractionTask || $0.task == Job.manifestTask)
                && !$0.state.isTerminal
        }
        return AssetPromptRunGate.refusal(detail: detail, bootstrapsIdle: bootstrapsIdle)
    }

    private var promptRunRequirementDetail: RequirementDetail? {
        referenceCreationRequirementID == nil
            ? requirementDetail
            : referenceImageCreationDetail
    }

    /// The default skill (§3.5): resolved from the bundle's vendored folder resource. The
    /// descriptor is data — a swapped skill is this one construction, nothing else (§14.4).
    static let defaultPromptSkillDescriptor: PromptSkillDescriptor? = {
        guard let root = Bundle.main.url(
            forResource: "higgsfield", withExtension: nil, subdirectory: "PromptSkills"
        ) else { return nil }
        return try? PromptSkillDescriptor(
            id: "higgsfield",
            displayName: "Higgsfield",
            rootURL: root,
            entryRelativePath: "SKILL.md",
            stillImageRoutingRelativePath: "image-models.md"
        )
    }()

    // MARK: - Prepare (§9's two copy blocks + §8.7's confirm)

    /// Arms the run. Order of gates before anything renders: the §8.7 regenerate confirm
    /// when the current prompt is human-written or human-edited (`source == .human`, the
    /// standard conversion), then the full §9 acknowledgement when this project has never
    /// acknowledged one, otherwise the compact per-run confirm sheet. Nothing is sent
    /// until Continue.
    func preparePromptRun() async {
        guard !isClosed, extractionAdapterFactory != nil, activePromptRun == nil,
              referenceImageGenerationTask == nil,
              let requirementID = referenceCreationRequirementID ?? workshopRequirementID
        else { return }
        if let refusal = promptRunRefusal {
            error = .project(refusal.error)
            return
        }
        // §8.7: regenerating over a human prompt confirms first ("your edited prompt stays
        // in history"). An AI-generated current prompt skips it.
        if await needsRegenerateConfirm(requirementID: requirementID) {
            pendingPromptRegenerateConfirm = PromptRegenerateConfirmPresentation()
            return
        }
        await continueAfterRegenerateConfirm()
    }

    private func needsRegenerateConfirm(requirementID: UUID) async -> Bool {
        (try? await session.requirement(id: requirementID))?
            .currentPrompt?.source == .human
    }

    /// The regenerate confirm's Continue: on into the §9 flow.
    func continueAfterRegenerateConfirm() async {
        pendingPromptRegenerateConfirm = nil
        await armPreparedPromptRun()
    }

    /// §9's acceptance path: store the acknowledgement through the shared door. Reference
    /// image creation starts immediately after this one-time disclosure; the workshop keeps
    /// the compact per-run sheet.
    func continueAfterPromptDisclosure() async {
        do {
            try await session.acknowledgeDisclosure()
            pendingPromptDisclosure = nil
            if let referenceImageDisclosureGate {
                self.referenceImageDisclosureGate = nil
                referenceImageDisclosureGate.resolve(true)
            } else if referenceCreationRequirementID != nil {
                await startPreparedPromptRun()
            } else {
                pendingPromptConfirmation = PromptConfirmationPresentation()
            }
        } catch {
            self.error = .project(error)
            cancelPreparedPromptRun()
            await failInPlaceReferenceGenerationIfNeeded(
                message: error.localizedDescription
            )
        }
    }

    /// Constructs the armed-but-not-started run and decides which §9 sheet renders first.
    private func armPreparedPromptRun() async {
        guard let extractionAdapterFactory else { return }
        do {
            let adapter = try extractionAdapterFactory()
            guard let descriptor = Self.defaultPromptSkillDescriptor else {
                error = .project(PromptRunError.materialisationFailed(
                    "The bundled prompt skill is missing from this copy of AI Film Camp."
                ))
                return
            }
            preparedPromptRun = AssetPromptRun(
                project: session, adapter: adapter, descriptor: descriptor,
                bundleRoot: session.bundleURL
            )
            if try await session.disclosureAcknowledgedAt() == nil {
                pendingPromptDisclosure = PromptDisclosurePresentation()
                pendingPromptConfirmation = nil
            } else if referenceCreationRequirementID != nil {
                pendingPromptConfirmation = nil
                await startPreparedPromptRun()
            } else {
                pendingPromptConfirmation = PromptConfirmationPresentation()
            }
        } catch {
            self.error = .project(error)
            preparedPromptRun = nil
        }
    }

    func cancelPreparedPromptRun() {
        referenceImageDisclosureGate?.resolve(false)
        referenceImageDisclosureGate = nil
        pendingPromptDisclosure = nil
        pendingPromptConfirmation = nil
        pendingPromptRegenerateConfirm = nil
        preparedPromptRun = nil
        startNextReferenceImageJobIfNeeded()
    }

    // MARK: - Run

    func startPreparedPromptRun() async {
        guard let run = preparedPromptRun, activePromptRun == nil,
              let requirementID = referenceCreationRequirementID ?? workshopRequirementID
        else { return }
        let isReferenceImageCreation = referenceCreationRequirementID != nil
        pendingPromptDisclosure = nil
        pendingPromptConfirmation = nil
        preparedPromptRun = nil
        activePromptRun = run
        await startPromptProgressObservation(for: run)
        do {
            let outcome = try await run.start(
                requirementID: requirementID,
                engine: "codex",
                engineVersion: "current",
                settings: AssetPromptSettings(inputBudgetUTF16: 0)
            )
            // §13.11's stated deviation: the apply is invertible, so the entry registers
            // on this window's undo stack and ⌘Z reads "Undo Generate Prompt". The stack
            // is deliberately NOT cleared the way an extraction or manifest run clears it.
            didApply(outcome.entry)
            presentedPromptReport = isReferenceImageCreation
                ? nil
                : PromptReportPresentation(report: outcome.report)
            activePromptRun = nil
            promptProgressTask?.cancel()
            promptProgressTask = nil
            await refresh()
            if isReferenceImageCreation {
                await refreshReferenceImageCreationContext()
                await continueInPlaceReferenceGenerationIfReady()
            }
            startNextReferenceImageJobIfNeeded()
        } catch {
            self.error = .project(error)
            activePromptRun = nil
            promptProgressTask?.cancel()
            promptProgressTask = nil
            await refresh()
            await failInPlaceReferenceGenerationIfNeeded(
                message: error.localizedDescription
            )
            startNextReferenceImageJobIfNeeded()
        }
    }

    func cancelPromptRun() async {
        guard let activePromptRun else { return }
        do {
            try await activePromptRun.cancel()
        } catch {
            self.error = .project(error)
        }
        promptProgressTask?.cancel()
        promptProgressTask = nil
        self.activePromptRun = nil
        await refresh()
        startNextReferenceImageJobIfNeeded()
    }

    func startPromptProgressObservation(for run: AssetPromptRun) async {
        promptProgressTask?.cancel()
        let stream = await run.progress()
        promptProgressTask = Task { [weak self] in
            for await progress in stream {
                guard let self, !Task.isCancelled else { return }
                self.promptProgress = PromptProgressPresentation(
                    stage: progress.stage, message: progress.message
                )
            }
        }
    }
}

/// One prompt run's progress line, beside the manifest section's own.
struct PromptProgressPresentation: Equatable, Sendable {
    let stage: String
    let message: String

    init(stage: PromptRunProgress.Stage, message: String) {
        self.stage = stage.rawValue
        self.message = message
    }

    init?(progress: PromptRunProgress) {
        self.init(stage: progress.stage, message: progress.message)
    }
}

struct PromptDisclosurePresentation: Identifiable, Equatable {
    let id = UUID()
}

struct PromptConfirmationPresentation: Identifiable, Equatable {
    let id = UUID()
}

struct PromptRegenerateConfirmPresentation: Identifiable, Equatable {
    let id = UUID()
}

struct PromptReportPresentation: Identifiable, Equatable {
    let id = UUID()
    let report: AssetPromptApplyReport
}
