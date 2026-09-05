import FilmCore
import Foundation

/// What the scene-prompt run is doing, for the Generation section's progress line —
/// `PromptRunProgress`'s shape at scene scale.
public struct ScenePromptRunProgress: Equatable, Sendable {
    public enum Stage: String, Equatable, Sendable {
        // The original broad cases remain decodable for persisted compatibility while
        // current runs emit the detailed stages below.
        case planning, running, apply
        case preparingContext, preparingHarness, generating, reviewing, validating, saving
        case completed, failed
    }
    public let stage: Stage
    public let message: String

    public init(stage: Stage, message: String) {
        self.stage = stage
        self.message = message
    }
}

/// Immediate, filmmaker-visible observability for either run mode. Child jobs retain
/// their own persisted timestamps and usage; this summary also accounts for the local
/// context and apply work surrounding those requests.
public struct ScenePromptRunSummary: Equatable, Sendable {
    public let qualityMode: ScenePromptQualityMode
    public let preparationMilliseconds: Int
    public let draftMilliseconds: Int
    public let improvementMilliseconds: Int
    public let validationAndSaveMilliseconds: Int
    public let totalMilliseconds: Int
    public let draftUsage: JobUsage
    public let improvementUsage: JobUsage?
    public let effectiveModel: String?

    public init(
        qualityMode: ScenePromptQualityMode,
        preparationMilliseconds: Int,
        draftMilliseconds: Int,
        improvementMilliseconds: Int,
        validationAndSaveMilliseconds: Int,
        totalMilliseconds: Int,
        draftUsage: JobUsage,
        improvementUsage: JobUsage?,
        effectiveModel: String?
    ) {
        self.qualityMode = qualityMode
        self.preparationMilliseconds = preparationMilliseconds
        self.draftMilliseconds = draftMilliseconds
        self.improvementMilliseconds = improvementMilliseconds
        self.validationAndSaveMilliseconds = validationAndSaveMilliseconds
        self.totalMilliseconds = totalMilliseconds
        self.draftUsage = draftUsage
        self.improvementUsage = improvementUsage
        self.effectiveModel = effectiveModel
    }

    public var requestCount: Int { qualityMode.requestCount }
    public var totalUsage: JobUsage {
        improvementUsage.map { draftUsage + $0 } ?? draftUsage
    }
}

public enum ScenePromptRunError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning
    case refused(ScenePromptRunGate.Refusal)
    /// The §8.1 pre-flight: an over-budget input fails **before any request is made**,
    /// with the size named, never by silent truncation (§11 defers chunking deliberately).
    case inputTooLarge(measuredUTF16: Int, limitUTF16: Int)
    /// The materialiser refused the skill (unsafe path, symlink, unreadable tree,
    /// imported-tree digest mismatch at the authoritative staging boundary).
    case materialisationFailed(String)
    /// The model returned structurally valid output that missed one of the scene-prompt
    /// semantic contracts. This is phrased for the filmmaker instead of exposing an
    /// internal snake-case validator code.
    case generatedPromptRejected(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "A scene prompt run is already active."
        case let .refused(refusal): refusal.error.errorDescription
        case let .inputTooLarge(measured, limit):
            ProjectStoreError.scenePromptInputOverBudget(
                measuredUTF16: measured, limitUTF16: limit
            ).errorDescription
        case let .materialisationFailed(reason):
            "The prompt skill could not be staged for this run: \(reason)"
        case let .generatedPromptRejected(reason): reason
        }
    }
}

/// The scene-prompt run (PHASE5_DESIGN §8.1, §8.6): one parent owns the canonical apply.
/// Standard mode has one child silently draft, review, repair, and validate the final
/// result. High Quality adds an independent refinement child in the same staged workspace;
/// only its refined result can reach FilmCore. There is no fan-out, resume, run-once gate,
/// or fallback to a weaker draft.
///
/// Before the session starts, the skill materialises for this run through the built arm-B
/// path. For an **imported** skill the run passes the stored `tree_sha256` as
/// `expectedTreeSHA256`, so the exact manifest the materialiser walks produces the digest
/// compared **before any copy or clone** — the atomic §8.6 boundary; a tree modified
/// under `skills/` after import refuses via `.treeDigestMismatch` with nothing staged.
/// The bundled default carries no row, passes `nil`, and is exempt.
public actor ScenePromptRun {
    private let project: any ProjectTools
    private let adapter: any HarnessAdapter
    private let descriptor: PromptSkillDescriptor
    /// The stored tree digest for an imported skill; `nil` for the bundled default.
    private let expectedTreeSHA256: String?
    /// The project bundle root — where `cache/skills/` lives (§4.1). A parameter because
    /// FilmBrain never resolves a bundle itself; the app passes its session's root.
    private let bundleRoot: URL
    private var draftRunner: StructuredJobRunner<GenerateScenePromptTask>?
    private var refinementRunner: StructuredJobRunner<RefineScenePromptTask>?
    private var isActive = false
    private var parentIsCommitting = false
    private var continuation: AsyncStream<ScenePromptRunProgress>.Continuation?
    public private(set) var lastOutcome: ScenePromptSetApplyOutcome?
    public private(set) var lastReport: ScenePromptApplyReport?
    public private(set) var lastSummary: ScenePromptRunSummary?
    public private(set) var runJobID: UUID?

    public init(
        project: any ProjectTools,
        adapter: any HarnessAdapter,
        descriptor: PromptSkillDescriptor,
        expectedTreeSHA256: String?,
        bundleRoot: URL
    ) {
        self.project = project
        self.adapter = adapter
        self.descriptor = descriptor
        self.expectedTreeSHA256 = expectedTreeSHA256
        self.bundleRoot = bundleRoot
    }

    public func progress() -> AsyncStream<ScenePromptRunProgress> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    /// Runs generation to a committed `ScenePromptApplyOutcome`.
    ///
    /// - Parameter settings: model/effort from the shared Advanced surface plus the
    ///   budget, captured into `ScenePromptSettings` with the skill identity (§8.1); a
    ///   preference edited mid-run does not apply (§8.5's rule, Phase 3's).
    @discardableResult
    public func start(
        sceneID: UUID,
        engine: String,
        engineVersion: String,
        settings: ScenePromptSettings
    ) async throws -> ScenePromptSetApplyOutcome {
        guard !isActive else { throw ScenePromptRunError.alreadyRunning }
        isActive = true
        defer {
            isActive = false
            draftRunner = nil
            refinementRunner = nil
            parentIsCommitting = false
        }
        lastOutcome = nil
        lastReport = nil
        lastSummary = nil
        let clock = ContinuousClock()
        let runStarted = clock.now
        var preparationMilliseconds = 0
        var draftMilliseconds = 0
        var improvementMilliseconds = 0
        emit(.preparingContext, "Loading the scene, references, continuity, and prompt skill")

        // The gate is asked here so the run declines without creating a job row; FilmCore
        // throws its refusals from createJob/apply regardless (§8.1). The custom-skill
        // tree re-verifies here for early feedback — authoritatively at the materialiser
        // below (§8.6).
        if let refusal = try await Self.gateRefusal(
            project: project, sceneID: sceneID,
            descriptor: descriptor, expectedTreeSHA256: expectedTreeSHA256
        ) {
            emit(.failed, refusal.error.localizedDescription)
            continuation?.finish()
            throw ScenePromptRunError.refused(refusal)
        }

        // The §8.2 snapshot is both the request payload and the one digest of §3.4.
        let snapshot = try await project.scenePromptInput(sceneID: sceneID)
        emit(
            .preparingContext,
            "Scene context ready with \(snapshot.input.references.count) approved reference"
                + (snapshot.input.references.count == 1 ? "" : "s")
        )
        let budget = settings.inputBudgetUTF16 > 0
            ? settings.inputBudgetUTF16
            : ScenePromptInputBudget.defaultUTF16Limit
        do {
            try ScenePromptInputBudget.check(text: snapshot.text, limit: budget)
        } catch ProjectStoreError.scenePromptInputOverBudget(let measured, let limit) {
            emit(.failed, ProjectStoreError.scenePromptInputOverBudget(
                measuredUTF16: measured, limitUTF16: limit
            ).errorDescription ?? "The scene's context exceeds the budget.")
            continuation?.finish()
            throw ScenePromptRunError.inputTooLarge(
                measuredUTF16: measured, limitUTF16: limit
            )
        }

        // Materialise the skill for THIS run before the workspace is put to use (arm B):
        // shared copy once per tree digest in unique bytes, then this run's clone under
        // workspace/skill/. For an imported skill the comparison against the stored
        // digest happens before any copy or clone — no gap between check and use.
        let runID = UUID()
        let workspace = try await project.prepareRunWorkspace(runID: runID)
        let materializer = PromptSkillMaterializer(
            descriptor: descriptor, bundleRoot: bundleRoot
        )
        let materialized: MaterializedSkill
        do {
            materialized = try materializer.materialize(
                workspaceURL: workspace.workspaceURL,
                expectedTreeSHA256: expectedTreeSHA256
            )
        } catch {
            emit(.failed, error.localizedDescription)
            continuation?.finish()
            throw ScenePromptRunError.materialisationFailed(error.localizedDescription)
        }

        // §3.7's fifth-revision routing scope: only the bundled default under the active
        // `seedance_2_5` profile pins the Seedance 2.5 sub-skill and its omni-reference
        // template — the Plan 016 posture that keeps the session off excluded sub-skills.
        // An imported skill names its own entry and optional routing file with no
        // assumption the higgsfield tree exists; anything else routes to the descriptor's
        // entry alone. The profile id comes from the snapshot's own record — the same P
        // the gate asked about.
        var pinning: (subSkillPath: String, omniTemplatePath: String)?
        if expectedTreeSHA256 == nil,
           snapshot.input.targetProfile.id == TargetProfileCatalog.seedance2_5.id {
            let root = materialized.entryURL.deletingLastPathComponent()
            pinning = (
                subSkillPath: root.appending(
                    path: "skills/higgsfield-seedance-2-5/SKILL.md"
                ).path,
                omniTemplatePath: root.appending(
                    path: "templates/seedance/omni-reference-2-5.md"
                ).path
            )
        }

        // The settings travel with the report: captured knobs + descriptor-relative
        // provenance (never an absolute cache path).
        let captured = ScenePromptSettings(
            model: settings.model,
            effort: settings.effort,
            inputBudgetUTF16: budget,
            qualityMode: settings.qualityMode,
            skillID: descriptor.id,
            skillEntryPath: descriptor.entryRelativePath,
            skillEntrySHA256: materialized.entrySHA256
        )

        runJobID = runID
        do {
            let parentPaths = try await project.prepareChildPaths(runID: runID, jobID: runID)
            _ = try await project.createJob(JobRequest(
                id: runID,
                task: Job.scenePromptTask,
                engine: engine,
                engineVersion: engineVersion,
                requestedModel: captured.model,
                schemaVersion: ScenePromptSchema.version,
                inputSHA256: snapshot.digest,
                logRelativePath: parentPaths.logRelativePath,
                resultRelativePath: parentPaths.resultRelativePath
            ))
            _ = try await project.transitionJob(
                id: runID, to: .discoveringHarness,
                progress: captured.qualityMode == .highQuality
                    ? "Preparing high-quality prompt run" : "Preparing prompt run"
            )
            _ = try await project.transitionJob(
                id: runID, to: .running,
                progress: captured.qualityMode == .highQuality
                    ? "Generating draft" : "Generating self-reviewed prompt"
            )
        } catch {
            await failParentIfNeeded(runID, failure: error)
            emit(.failed, (error as? LocalizedError)?.errorDescription ?? "The scene prompt run failed.")
            continuation?.finish()
            throw error
        }

        emit(
            .preparingHarness,
            captured.qualityMode == .highQuality
                ? "Starting Codex and staging the draft request"
                : "Starting Codex and staging one self-reviewed request"
        )
        let draftRunner = StructuredJobRunner(
            task: GenerateScenePromptTask(
                input: snapshot.input,
                skillEntryPath: materialized.entryURL.path,
                skillRoutingPath: materialized.routingURL?.path,
                seedancePinning: pinning,
                enforcesQualityContract: captured.qualityMode == .standard
            ),
            projectTools: project,
            adapter: adapter,
            progressHandler: { [weak self] message in
                Task {
                    await self?.relayRunnerProgress(
                        message,
                        qualityMode: captured.qualityMode
                    )
                }
            }
        )
        self.draftRunner = draftRunner

        let project = self.project
        do {
            let draftStarted = clock.now
            preparationMilliseconds = Self.milliseconds(from: runStarted, to: draftStarted)
            let draftRun = try await draftRunner.run(
                input: StructuredTaskInput(
                    jobID: UUID(),
                    text: snapshot.text,
                    requestedModel: captured.model,
                    reasoningEffort: captured.effort
                ),
                engine: engine,
                engineVersion: engineVersion,
                parentJobID: runID
            )
            let draftFinished = clock.now
            draftMilliseconds = Self.milliseconds(from: draftStarted, to: draftFinished)
            self.draftRunner = nil

            let finalOutput: ScenePromptResult
            let improvementUsage: JobUsage?
            let improvementFinished: ContinuousClock.Instant
            let effectiveModel: String?
            if captured.qualityMode == .highQuality {
                let improvementStarted = draftFinished
                emit(.reviewing, "Reviewing screenplay fidelity, staging, camera geometry, audio, and continuity")

                let refinementPayload = try ScenePromptRefinementInput(
                    authoritativeInput: snapshot.input,
                    draft: draftRun.output
                ).rendered()
                let refinementRunner = StructuredJobRunner(
                    task: RefineScenePromptTask(
                        authoritativeInput: snapshot.input,
                        skillEntryPath: materialized.entryURL.path,
                        skillRoutingPath: materialized.routingURL?.path,
                        seedancePinning: pinning
                    ),
                    projectTools: project,
                    adapter: adapter,
                    progressHandler: { [weak self] message in
                        Task { await self?.relayRefinementProgress(message) }
                    }
                )
                self.refinementRunner = refinementRunner
                let refinedRun = try await refinementRunner.run(
                    input: StructuredTaskInput(
                        jobID: UUID(),
                        text: refinementPayload,
                        requestedModel: captured.model,
                        reasoningEffort: captured.effort
                    ),
                    engine: engine,
                    engineVersion: engineVersion,
                    parentJobID: runID
                )
                improvementFinished = clock.now
                improvementMilliseconds = Self.milliseconds(
                    from: improvementStarted,
                    to: improvementFinished
                )
                self.refinementRunner = nil
                finalOutput = refinedRun.output
                improvementUsage = refinedRun.usage
                effectiveModel = refinedRun.job.effectiveModel ?? draftRun.job.effectiveModel
            } else {
                improvementFinished = draftFinished
                finalOutput = draftRun.output
                improvementUsage = nil
                effectiveModel = draftRun.job.effectiveModel
            }

            if let effectiveModel {
                try await project.setEffectiveModel(
                    jobID: runID, effectiveModel: effectiveModel
                )
            }

            emit(
                .validating,
                captured.qualityMode == .highQuality
                    ? "Checking the improved prompt against references, screenplay, and profile settings"
                    : "Checking the final prompt against references, screenplay, and profile settings"
            )
            _ = try await project.transitionJob(
                id: runID,
                to: .validating,
                progress: captured.qualityMode == .highQuality
                    ? "Validating improved prompt" : "Validating final prompt"
            )
            emit(
                .saving,
                captured.qualityMode == .highQuality
                    ? "Saving the independently reviewed prompt"
                    : "Saving the self-reviewed prompt"
            )
            _ = try await project.transitionJob(
                id: runID,
                to: .committing,
                progress: captured.qualityMode == .highQuality
                    ? "Saving improved prompt" : "Saving final prompt"
            )
            parentIsCommitting = true

            let cards = finalOutput.cards.map { card in
                ScenePromptCardDraft(
                    title: card.title,
                    body: card.body,
                    guidance: card.guidance,
                    durationSeconds: card.settings.durationSeconds,
                    aspectRatio: card.settings.aspectRatio,
                    resolution: card.settings.resolution,
                    referencePositions: card.references.map(\.sourceDesignator)
                )
            }
            let proposal = try ScenePromptSetProposal(
                sceneID: sceneID,
                cards: cards,
                settings: captured
            )
            let outcome = try await project.applyScenePromptSetRun(
                proposal,
                runJobID: runID,
                usage: improvementUsage.map { draftRun.usage + $0 } ?? draftRun.usage
            )
            let runFinished = clock.now
            parentIsCommitting = false
            lastSummary = ScenePromptRunSummary(
                qualityMode: captured.qualityMode,
                preparationMilliseconds: preparationMilliseconds,
                draftMilliseconds: draftMilliseconds,
                improvementMilliseconds: improvementMilliseconds,
                validationAndSaveMilliseconds: Self.milliseconds(
                    from: improvementFinished,
                    to: runFinished
                ),
                totalMilliseconds: Self.milliseconds(from: runStarted, to: runFinished),
                draftUsage: draftRun.usage,
                improvementUsage: improvementUsage,
                effectiveModel: effectiveModel
            )
            setOutcome(outcome)
        } catch let failure as StructuredJobFailure
            where Self.generatedPromptFailureMessage(failure) != nil {
            await failParentIfNeeded(runID, failure: failure)
            let message = Self.generatedPromptFailureMessage(failure)!
            emit(.failed, message)
            continuation?.finish()
            throw ScenePromptRunError.generatedPromptRejected(message)
        } catch {
            await failParentIfNeeded(runID, failure: error)
            emit(.failed, (error as? LocalizedError)?.errorDescription ?? "The scene prompt run failed.")
            continuation?.finish()
            throw error
        }

        guard let outcome = self.outcome() else {
            throw ProjectStoreError.databaseCommit("The scene prompt run recorded no outcome.")
        }
        lastReport = outcome.report
        emit(
            .completed,
            captured.qualityMode == .highQuality
                ? "Scene prompt generated and independently refined"
                : "Scene prompt generated and self-reviewed"
        )
        continuation?.finish()
        return outcome
    }

    public func cancel() async throws {
        if parentIsCommitting { throw ProjectStoreError.cancellationTooLate }
        if let refinementRunner {
            try await refinementRunner.cancel()
        } else if let draftRunner {
            try await draftRunner.cancel()
        }
        if let runJobID {
            _ = try? await project.transitionJob(
                id: runJobID, to: .cancelled, progress: "Cancelled"
            )
        }
    }

    /// The §8.1 gate over the shipped reads, evaluated before a run is launched.
    static func gateRefusal(
        project: any ProjectTools,
        sceneID: UUID,
        descriptor: PromptSkillDescriptor,
        expectedTreeSHA256: String?
    ) async throws -> ScenePromptRunGate.Refusal? {
        let history = try await project.jobHistory()
        let bootstrapsIdle = !history.contains {
            $0.parentJobID == nil
                && ($0.task == Job.extractionTask || $0.task == Job.manifestTask)
                && !$0.state.isTerminal
        }
        let summaries = try await project.scenePackages()
        guard let summary = summaries.first(where: { $0.sceneID == sceneID }) else {
            return ScenePromptRunGate.refusal(ScenePromptRunGate.Questions(
                sceneCounted: false,
                assetReady: false,
                activeProfile: summaries.first.flatMap {
                    TargetProfileCatalog.profile(id: $0.activeProfileID)
                },
                activeProfileID: summaries.first?.activeProfileID ?? "",
                satisfiedReferenceCount: 0,
                customSkillTreeVerified: true,
                bootstrapsIdle: bootstrapsIdle
            ))
        }
        let detail = try await project.scenePackageDetail(sceneID: sceneID)
        var treeVerified = true
        if let expected = expectedTreeSHA256 {
            do {
                let manifest = try SkillTreeOperations.manifest(of: descriptor.rootURL)
                treeVerified = manifest.treeDigest() == expected
            } catch {
                treeVerified = false
            }
        }
        return ScenePromptRunGate.refusal(ScenePromptRunGate.Questions(
            sceneCounted: true,
            assetReady: summary.assetReadyState == .assetReady,
            activeProfile: TargetProfileCatalog.profile(id: detail.activeProfile.id),
            activeProfileID: detail.activeProfile.id,
            satisfiedReferenceCount: detail.plan.filter(\.isSatisfied).count,
            customSkillTreeVerified: treeVerified,
            bootstrapsIdle: bootstrapsIdle
        ))
    }

    private func setOutcome(_ outcome: ScenePromptSetApplyOutcome) {
        lastOutcome = outcome
    }

    private func outcome() -> ScenePromptSetApplyOutcome? {
        lastOutcome
    }

    private func emit(_ stage: ScenePromptRunProgress.Stage, _ message: String) {
        continuation?.yield(.init(stage: stage, message: message))
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Int {
        let components = (end - start).components
        let milliseconds = components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
        return Int(clamping: milliseconds)
    }

    private func relayRunnerProgress(
        _ message: String,
        qualityMode: ScenePromptQualityMode
    ) {
        switch message {
        case "Preparing harness":
            emit(.preparingHarness, "Starting Codex and preparing the generation workspace")
        case "Validating result":
            emit(
                .generating,
                qualityMode == .highQuality
                    ? "Checking the draft structure before the improvement pass"
                    : "Checking the final prompt structure and quality"
            )
        case "Finishing commit":
            emit(
                .generating,
                qualityMode == .highQuality
                    ? "Draft ready for the independent improvement pass"
                    : "Prompt passed self-review and quality checks"
            )
        case "Working", "Codex is working.", "Codex is analyzing the screenplay.":
            emit(.generating, "Codex is writing the scene prompt")
        case "Codex produced analysis output.":
            emit(.generating, "Codex returned a candidate prompt")
        default:
            emit(.generating, message)
        }
    }

    private func relayRefinementProgress(_ message: String) {
        switch message {
        case "Preparing harness":
            emit(.reviewing, "Starting the independent prompt reviewer")
        case "Validating result":
            emit(.reviewing, "Checking the reviewer's rewritten prompt")
        case "Working", "Codex is working.", "Codex is analyzing the screenplay.":
            emit(.reviewing, "Reviewing and rewriting the draft against the screenplay and Higgsfield guidance")
        case "Codex produced analysis output.":
            emit(.reviewing, "The reviewer returned an improved prompt")
        default:
            emit(.reviewing, message)
        }
    }

    private func failParentIfNeeded(_ runID: UUID, failure: Error) async {
        guard let parent = try? await project.jobHistory().first(where: { $0.id == runID }),
              !parent.state.isTerminal
        else { return }

        let structured = failure as? StructuredJobFailure
        let cancelled = structured?.code == "cancelled" || failure is CancellationError
        _ = try? await project.transitionJob(
            id: runID,
            to: cancelled ? .cancelled : .failed,
            progress: cancelled ? "Cancelled" : "Failed",
            failureCode: cancelled ? nil : structured?.code,
            failureMessage: cancelled ? nil : structured?.message
        )
    }

    private static func generatedPromptFailureMessage(_ failure: StructuredJobFailure) -> String? {
        guard failure.code == StructuredValidationFailure.Code.semanticViolation.rawValue else { return nil }
        let speakerPrefix = ScenePromptSemanticCode.missingDialogueSpeaker.rawValue + ": "
        if failure.message.hasPrefix(speakerPrefix) {
            return "The generated prompt has a dialogue speaker mismatch. "
                + failure.message.dropFirst(speakerPrefix.count)
        }
        return referenceDeclarationFailureMessages[failure.message]
    }

    private static let referenceDeclarationFailureMessages = [
        ScenePromptSemanticCode.missingReferenceRole.rawValue:
            "The generated prompt omitted the required role for one or more image references. Please generate it again.",
        ScenePromptSemanticCode.missingReferenceFidelity.rawValue:
            "The generated prompt omitted the required fidelity grade for one or more image references. Please generate it again.",
        ScenePromptSemanticCode.missingReferenceExclusion.rawValue:
            "The generated prompt omitted the required exclusion for one or more image references. Please generate it again.",
        ScenePromptSemanticCode.arbitraryCameraMeasurement.rawValue:
            "The generated prompt added an unsupported numeric camera measurement. Please generate it again.",
        ScenePromptSemanticCode.formattedSoundCue.rawValue:
            "The generated prompt formatted a sound cue as prompt markup instead of plain audio direction. Please generate it again.",
        ScenePromptSemanticCode.escapedAngleMarkup.rawValue:
            "The generated prompt escaped angle-bracket markup instead of producing clean paste-ready text. Please generate it again.",
        ScenePromptSemanticCode.qualityBoilerplate.rawValue:
            "The generated prompt retained generic or contradictory prompt boilerplate. Please generate it again.",
        ScenePromptSemanticCode.missingTimingPlan.rawValue:
            "The generated prompt omitted the total clip duration or stage timing plan. Please generate it again.",
        ScenePromptSemanticCode.invalidTimingPlan.rawValue:
            "The generated prompt's stage timings do not join cleanly or match the selected clip duration. Please generate it again.",
        ScenePromptSemanticCode.missingDialogueSpeaker.rawValue:
            "The generated prompt has a dialogue speaker mismatch. Use the canonical character name before “says” and put location or delivery directions after it. Off-screen and broadcast speakers may remain unseen. Please generate it again.",
        ScenePromptSemanticCode.invalidDialogueFormat.rawValue:
            "The generated prompt did not put each spoken line on one attributed, brace-delimited line. Please generate it again.",
        ScenePromptSemanticCode.dialogueOutsideStage.rawValue:
            "The generated prompt placed dialogue outside its timed stage. Please generate it again.",
        ScenePromptSemanticCode.dialogueSourceMismatch.rawValue:
            "The generated prompt omitted, added, repeated, reordered, or changed screenplay dialogue. Please generate it again; use the scene screenplay editor for intentional story changes.",
        ScenePromptSemanticCode.creativeDirectionNotApplied.rawValue:
            "The generated prompt omitted or contradicted your creative direction. Please generate it again.",
    ]
}
