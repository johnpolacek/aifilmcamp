import FilmBrain
import FilmCore
import Foundation

/// The scene-prompt run on the **window model** (PHASE5_DESIGN §8, §9; Plan 021 contract
/// A/D) — Plan 016's `+PromptRun` three-beat shape at scene scale, reusing its sites
/// rather than building parallels (§1.2's fourth-revision note): prepare (gate, then
/// one-time disclosure when needed), start (progress, run, apply), review.
///
/// The apply is **invertible**, so success routes the returned journal entry through
/// `didApply` and ⌘Z reads "Undo Generate Scene Prompt" — and a scene-prompt run is
/// **never** offered Revert (the Jobs arm enforces the UI half). Generate/Regenerate
/// render behind `ScenePromptRunGate`'s mirror; nothing batch-shaped renders anywhere
/// (§14.1's evidence gate is unmet on the recorded posture).
@MainActor
extension ProjectWindowModel {

    // MARK: - Availability (§5.5's Generate/Regenerate rows)

    /// Why Generate/Regenerate may not run right now — every §8.1 pre-flight condition
    /// evaluated through `ScenePromptRunGate` over this window's own reads, with
    /// FilmCore's own sentences. `nil` means enabled.
    var sceneGenerateDisabledReason: String? {
        guard selectedPackageSceneID != nil else { return nil }
        if isScenePromptGenerationActive { return "A scene prompt run is already active." }
        guard let refusal = scenePromptRunRefusal else { return nil }
        return refusal.error.errorDescription
    }

    var isScenePromptGenerationActive: Bool {
        activeScenePromptRun != nil || preparedScenePromptRun != nil || scenePromptProgress != nil
    }

    var scenePromptRunRefusal: ScenePromptRunGate.Refusal? {
        guard let sceneID = selectedPackageSceneID else { return nil }
        let bootstrapsIdle = !jobs.contains {
            $0.parentJobID == nil
                && ($0.task == Job.extractionTask || $0.task == Job.manifestTask)
                && !$0.state.isTerminal
        }
        // The custom-skill tree re-verifies here for early feedback; the materialiser's
        // staging walk stays the authority (§8.6).
        var treeVerified = true
        if let skill = selectedSkillRow {
            treeVerified = Self.verifySkillTree(skill, bundleRoot: session.bundleURL)
        }
        return ScenePromptRunGate.refusal(ScenePromptRunGate.Questions(
            sceneCounted: scenePackage(forSceneID: sceneID) != nil,
            assetReady: scenePackage(forSceneID: sceneID)?.assetReadyState == .assetReady,
            activeProfile: TargetProfileCatalog.profile(
                id: _scenePackageDetail?.activeProfile.id
                    ?? _scenePackages.first?.activeProfileID ?? ""
            ),
            activeProfileID: _scenePackageDetail?.activeProfile.id
                ?? _scenePackages.first?.activeProfileID ?? "",
            satisfiedReferenceCount: _scenePackageDetail?.plan.filter(\.isSatisfied).count ?? 0,
            customSkillTreeVerified: treeVerified,
            bootstrapsIdle: bootstrapsIdle
        ))
    }

    private static func verifySkillTree(_ skill: ImportedSkill, bundleRoot: URL) -> Bool {
        guard let manifest = try? SkillTreeOperations.manifest(
            of: bundleRoot.appending(path: skill.relativeRoot)
        ) else { return false }
        return manifest.treeDigest() == skill.treeSHA256
    }

    // MARK: - Descriptor resolution (§8.6)

    /// The selected descriptor for a run: the imported skill when one is selected —
    /// constructed from its row with the root resolved bundle-relatively, carrying the
    /// stored digest for the materialiser's authoritative check — otherwise the bundled
    /// default from Plan 016's construction site.
    func resolvedScenePromptSkill() throws -> (descriptor: PromptSkillDescriptor, expectedTreeSHA256: String?) {
        if let skill = selectedSkillRow {
            let root = session.bundleURL.appending(path: skill.relativeRoot)
            let descriptor = try PromptSkillDescriptor(
                id: "imported-\(skill.id.uuidString)",
                displayName: skill.displayName,
                rootURL: root,
                entryRelativePath: skill.entryRelativePath,
                stillImageRoutingRelativePath: skill.routingRelativePath.isEmpty
                    ? nil : skill.routingRelativePath
            )
            return (descriptor, skill.treeSHA256)
        }
        guard let descriptor = Self.defaultPromptSkillDescriptor else {
            throw ScenePromptRunError.materialisationFailed(
                "The bundled prompt skill is missing from this copy of AI Film Camp."
            )
        }
        return (descriptor, nil)
    }

    // MARK: - Prepare (§9's one-time disclosure)

    /// Arms the run after the preflight gate. A project that has not acknowledged the
    /// disclosure pauses once; every acknowledged Generate/Update/Regenerate gesture
    /// starts immediately.
    func prepareScenePromptRun() async {
        guard !isClosed, extractionAdapterFactory != nil,
              activeScenePromptRun == nil, preparedScenePromptRun == nil,
              selectedPackageSceneID != nil
        else { return }
        if let setID = _scenePackageDetail?.currentSet?.set.id {
            guard await flushInlinePromptEditors(setID: setID) else { return }
        }
        if let refusal = scenePromptRunRefusal {
            error = .project(refusal.error)
            return
        }
        isReplacingScenePrompt = _scenePackageDetail?.currentSet != nil
        scenePromptProgress = ScenePromptRunProgressPresentation(
            stage: .preparingContext,
            message: "Loading the scene, references, continuity, and prompt skill"
        )
        await armPreparedScenePromptRun()
    }

    /// Stores the one-time acknowledgement, then starts the run requested by the original
    /// Generate/Update/Regenerate gesture.
    func continueAfterScenePromptDisclosure() async {
        do {
            try await session.acknowledgeDisclosure()
            pendingScenePromptDisclosure = nil
            await startPreparedScenePromptRun()
        } catch {
            self.error = .project(error)
            cancelPreparedScenePromptRun()
        }
    }

    /// Constructs the run, pausing only for the one-time disclosure when necessary.
    private func armPreparedScenePromptRun() async {
        guard let extractionAdapterFactory else { return }
        do {
            let adapter = try extractionAdapterFactory()
            let resolved = try resolvedScenePromptSkill()
            preparedScenePromptRun = ScenePromptRun(
                project: session, adapter: adapter, descriptor: resolved.descriptor,
                expectedTreeSHA256: resolved.expectedTreeSHA256,
                bundleRoot: session.bundleURL
            )
            if try await session.disclosureAcknowledgedAt() == nil {
                pendingScenePromptDisclosure = ScenePromptDisclosurePresentation()
            } else {
                await startPreparedScenePromptRun()
            }
        } catch {
            self.error = .project(error)
            preparedScenePromptRun = nil
            scenePromptProgress = nil
            scenePromptRunStartedAt = nil
            isReplacingScenePrompt = false
        }
    }

    func cancelPreparedScenePromptRun() {
        pendingScenePromptDisclosure = nil
        preparedScenePromptRun = nil
        scenePromptProgress = nil
        scenePromptRunStartedAt = nil
        isReplacingScenePrompt = false
    }

    // MARK: - Run

    func startPreparedScenePromptRun() async {
        guard let run = preparedScenePromptRun, activeScenePromptRun == nil,
              let sceneID = selectedPackageSceneID
        else {
            scenePromptProgress = nil
            isReplacingScenePrompt = false
            return
        }
        pendingScenePromptDisclosure = nil
        preparedScenePromptRun = nil
        scenePromptRunStartedAt = .now
        scenePromptProgress = ScenePromptRunProgressPresentation(
            stage: .preparingContext,
            message: "Loading the scene, references, continuity, and prompt skill"
        )
        activeScenePromptRun = run
        await startScenePromptProgressObservation(for: run)
        do {
            let outcome = try await run.start(
                sceneID: sceneID,
                engine: "codex",
                engineVersion: "current",
                settings: ScenePromptSettings(
                    inputBudgetUTF16: 0,
                    qualityMode: scenePromptQualityMode
                )
            )
            let summary = await run.lastSummary
            // The apply is invertible, so the entry registers on this window's undo stack
            // and ⌘Z reads "Undo Generate Scene Prompt". The stack is deliberately NOT
            // cleared the way an extraction or manifest run clears it.
            didApply(outcome.entry)
            presentedScenePromptReport = ScenePromptReportPresentation(
                report: outcome.report,
                summary: summary
            )
            activeScenePromptRun = nil
            scenePromptProgressTask?.cancel()
            scenePromptProgressTask = nil
            scenePromptProgress = nil
            scenePromptRunStartedAt = nil
            await refresh()
            isReplacingScenePrompt = false
        } catch {
            self.error = .project(error)
            activeScenePromptRun = nil
            scenePromptProgressTask?.cancel()
            scenePromptProgressTask = nil
            scenePromptProgress = nil
            scenePromptRunStartedAt = nil
            await refresh()
            isReplacingScenePrompt = false
        }
    }

    func cancelScenePromptRun() async {
        guard let activeScenePromptRun else {
            cancelPreparedScenePromptRun()
            return
        }
        do {
            try await activeScenePromptRun.cancel()
        } catch {
            self.error = .project(error)
        }
        scenePromptProgressTask?.cancel()
        scenePromptProgressTask = nil
        scenePromptProgress = nil
        scenePromptRunStartedAt = nil
        self.activeScenePromptRun = nil
        isReplacingScenePrompt = false
        await refresh()
    }

    private func startScenePromptProgressObservation(for run: ScenePromptRun) async {
        scenePromptProgressTask?.cancel()
        let stream = await run.progress()
        scenePromptProgressTask = Task { [weak self] in
            for await progress in stream {
                guard let self, !Task.isCancelled else { return }
                self.scenePromptProgress = ScenePromptRunProgressPresentation(progress: progress)
            }
        }
    }
}

/// One scene-prompt run's progress line — `PromptProgressPresentation`'s shape.
struct ScenePromptRunProgressPresentation: Equatable, Sendable {
    let stage: String
    let message: String

    init(stage: ScenePromptRunProgress.Stage, message: String) {
        self.stage = stage.rawValue
        self.message = message
    }

    init?(progress: ScenePromptRunProgress) {
        self.init(stage: progress.stage, message: progress.message)
    }
}

struct ScenePromptDisclosurePresentation: Identifiable, Equatable {
    let id = UUID()
}

struct ScenePromptReportPresentation: Identifiable, Equatable {
    let id = UUID()
    let report: ScenePromptApplyReport
    let summary: ScenePromptRunSummary?
}
