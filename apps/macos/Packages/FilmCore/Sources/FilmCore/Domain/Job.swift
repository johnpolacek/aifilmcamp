import Foundation

public struct JobUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int?
    public var cachedInputTokens: Int?
    public var cacheWriteInputTokens: Int?
    public var outputTokens: Int?
    public var reasoningOutputTokens: Int?

    public init(
        inputTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        cacheWriteInputTokens: Int? = nil,
        outputTokens: Int? = nil,
        reasoningOutputTokens: Int? = nil
    ) throws {
        let values = [
            inputTokens,
            cachedInputTokens,
            cacheWriteInputTokens,
            outputTokens,
            reasoningOutputTokens,
        ].compactMap { $0 }
        guard values.allSatisfy({ $0 >= 0 }) else {
            throw ProjectStoreError.invalidUsage
        }
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }

    public static let empty = try! JobUsage()

    /// `nil`-aware addition (Plan 003 contract B), used to aggregate a run's usage.
    ///
    /// `nil` means "absent", not zero: a field is `nil` in the sum **only** when it is
    /// `nil` in every operand, so one child reporting no cache-write tokens cannot erase
    /// another child's count.
    public static func + (lhs: JobUsage, rhs: JobUsage) -> JobUsage {
        var sum = JobUsage.empty
        sum.inputTokens = adding(lhs.inputTokens, rhs.inputTokens)
        sum.cachedInputTokens = adding(lhs.cachedInputTokens, rhs.cachedInputTokens)
        sum.cacheWriteInputTokens = adding(lhs.cacheWriteInputTokens, rhs.cacheWriteInputTokens)
        sum.outputTokens = adding(lhs.outputTokens, rhs.outputTokens)
        sum.reasoningOutputTokens = adding(lhs.reasoningOutputTokens, rhs.reasoningOutputTokens)
        return sum
    }

    public static func += (lhs: inout JobUsage, rhs: JobUsage) {
        lhs = lhs + rhs
    }

    /// The one `nil`-aware field addition: `nil` only when both operands are `nil`.
    public static func adding(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case let (value?, nil): value
        case let (nil, value?): value
        case let (left?, right?): left + right
        }
    }

    /// The `nil`-aware sum of a whole run's usage.
    public static func sum(_ values: some Sequence<JobUsage>) -> JobUsage {
        values.reduce(.empty, +)
    }
}

public struct Job: Codable, Equatable, Sendable, Identifiable {
    public static let reusedProgressStage = "Reused"

    /// The extraction run's parent task — the only job whose `apply_report` column holds
    /// an `ApplyReport` (PHASE1_DESIGN §8.5).
    public static let extractionTask = "extractScreenplay"
    /// The manifest-inference run's parent task — the only job whose `apply_report` column
    /// holds a `ManifestApplyReport` (PHASE2_DESIGN §8.1, §8.5).
    public static let manifestTask = "inferAssetManifest"
    /// The asset-prompt run's parent task — the only job whose `apply_report` column holds
    /// an `AssetPromptApplyReport` (PHASE3_DESIGN §8.1, §8.5). Deliberately **never**
    /// added to the run-revert walk's closed task list (§7.4's prohibition): a completed
    /// prompt run must block neither revert.
    public static let assetPromptTask = "generateAssetPrompt"
    /// The scene-prompt run's parent task — the only job whose `apply_report` column
    /// holds a `ScenePromptApplyReport` (PHASE5_DESIGN §8.1, §8.5). Like its asset-scale
    /// sibling it is deliberately **never** added to the run-revert walk's closed task
    /// list (§7.4's prohibition carried to scene scale): the apply is invertible and
    /// recovery is undo or delete-the-newest, never Revert.
    public static let scenePromptTask = "generateScenePrompt"
    /// Child job that independently reviews and rewrites a generated scene prompt. It
    /// never owns an apply report or canonical mutation; its parent commits the refined
    /// output only after this child validates.
    public static let scenePromptRefinementTask = "refineScenePrompt"

    public enum State: String, Codable, CaseIterable, Sendable {
        case queued
        case discoveringHarness
        case running
        case validating
        case committing
        /// A run parked so a later one may supersede it (§3.9).
        case paused
        case completed
        case failed
        case cancelled

        public var isTerminal: Bool {
            switch self {
            case .completed, .failed, .cancelled: true
            default: false
            }
        }

        public func canTransition(to next: State) -> Bool {
            switch (self, next) {
            case (.queued, .discoveringHarness),
                 (.discoveringHarness, .running),
                 (.running, .validating),
                 (.validating, .committing),
                 (.committing, .completed):
                true
            // Legal syntactically for every job; `ProjectRepository.transitionJob` rejects
            // it when `parent_job_id IS NULL` — parents go through `committing` (§3.9).
            case (.validating, .completed):
                true
            // A run may be parked and resumed so a later one can supersede it (§3.9).
            case (.running, .paused),
                 (.validating, .paused),
                 (.paused, .running):
                true
            case (.paused, .cancelled),
                 (.paused, .failed):
                true
            case (.queued, .cancelled),
                 (.discoveringHarness, .cancelled),
                 (.running, .cancelled),
                 (.validating, .cancelled):
                true
            case (.queued, .failed),
                 (.discoveringHarness, .failed),
                 (.running, .failed),
                 (.validating, .failed),
                 (.committing, .failed):
                true
            default:
                false
            }
        }
    }

    public let id: UUID
    public let projectID: UUID
    public let task: String
    public let engine: String
    public let engineVersion: String
    public let requestedModel: String?
    public let effectiveModel: String?
    public let schemaVersion: Int
    public let inputSHA256: String
    public let state: State
    public let progressStage: String
    public let usage: JobUsage
    public let logRelativePath: RelativeProjectPath
    public let resultRelativePath: RelativeProjectPath
    public let startedAt: Date?
    public let endedAt: Date?
    public let failureCode: String?
    public let failureMessage: String?
    /// A run's children point at it; `ON DELETE RESTRICT` keeps a parent alive (§3.9).
    public let parentJobID: UUID?
    public let chunkIndex: Int?
    public let chunkCount: Int?
    public let attemptIndex: Int?
    public let supersedesJobID: UUID?
    public let scriptID: UUID?
    public let scriptSHA256: String?
    /// The raw `jobs.apply_report` JSON. Plan 003 kept it internal because `ApplyReport`
    /// did not exist yet; Plan 005 declares the type and `applyReport` decodes it.
    let applyReportJSON: String?

    /// What the **extraction** run's apply did (PHASE1_DESIGN §8.5), or `nil` when the
    /// column is empty.
    ///
    /// A column that will not decode reads as `nil` rather than throwing: a job row is a
    /// progress record, and a malformed report must not make the Jobs list unreadable.
    ///
    /// The accessor **gates on `task`** (PHASE2_DESIGN §4.4): one nullable JSON column now
    /// carries two report types, and shape-gating on disjoint keys alone would be an
    /// accident rather than a contract.
    public var applyReport: ApplyReport? {
        decodedReport(ApplyReport.self, task: Self.extractionTask)
    }

    /// Whether a completed extraction parent actually crossed the canonical apply boundary.
    ///
    /// Older builds could incorrectly complete a parent after every chunk failed, recording
    /// an empty report whose `chunksFailed` covered the entire run. Treating that legacy row
    /// as unapplied repairs retry eligibility without weakening the one-applied-run latch.
    public var didApplyExtraction: Bool {
        guard task == Self.extractionTask, state == .completed else { return false }
        guard let chunkCount, chunkCount > 0, let report = applyReport else {
            // Rows written before chunk metadata/reporting existed retain their historical
            // meaning: a completed extraction parent applied successfully.
            return true
        }
        return report.chunksFailed < chunkCount
    }

    /// What the **manifest-inference** run's apply did (PHASE2_DESIGN §8.5), or `nil` when
    /// the column is empty. Task-gated exactly as `applyReport` is.
    public var manifestReport: ManifestApplyReport? {
        decodedReport(ManifestApplyReport.self, task: Self.manifestTask)
    }

    /// What the **asset-prompt** run's apply did (PHASE3_DESIGN §8.5), or `nil` when the
    /// column is empty. Task-gated exactly as its two siblings are.
    public var assetPromptReport: AssetPromptApplyReport? {
        decodedReport(AssetPromptApplyReport.self, task: Self.assetPromptTask)
    }

    /// What the **scene-prompt** run's apply did (PHASE5_DESIGN §8.5), or `nil` when the
    /// column is empty. Task-gated exactly as its three siblings are.
    public var scenePromptReport: ScenePromptApplyReport? {
        decodedReport(ScenePromptApplyReport.self, task: Self.scenePromptTask)
    }

    private func decodedReport<Report: Decodable>(_ type: Report.Type, task expected: String) -> Report? {
        guard task == expected, let applyReportJSON else { return nil }
        return try? JournalCoding.decoder.decode(type, from: Data(applyReportJSON.utf8))
    }

    public init(
        id: UUID,
        projectID: UUID,
        task: String,
        engine: String,
        engineVersion: String,
        requestedModel: String?,
        effectiveModel: String?,
        schemaVersion: Int,
        inputSHA256: String,
        state: State,
        progressStage: String,
        usage: JobUsage,
        logRelativePath: RelativeProjectPath,
        resultRelativePath: RelativeProjectPath,
        startedAt: Date?,
        endedAt: Date?,
        failureCode: String?,
        failureMessage: String?,
        parentJobID: UUID? = nil,
        chunkIndex: Int? = nil,
        chunkCount: Int? = nil,
        attemptIndex: Int? = nil,
        supersedesJobID: UUID? = nil,
        scriptID: UUID? = nil,
        scriptSHA256: String? = nil,
        applyReportJSON: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.task = task
        self.engine = engine
        self.engineVersion = engineVersion
        self.requestedModel = requestedModel
        self.effectiveModel = effectiveModel
        self.schemaVersion = schemaVersion
        self.inputSHA256 = inputSHA256
        self.state = state
        self.progressStage = progressStage
        self.usage = usage
        self.logRelativePath = logRelativePath
        self.resultRelativePath = resultRelativePath
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.failureCode = failureCode
        self.failureMessage = failureMessage
        self.parentJobID = parentJobID
        self.chunkIndex = chunkIndex
        self.chunkCount = chunkCount
        self.attemptIndex = attemptIndex
        self.supersedesJobID = supersedesJobID
        self.scriptID = scriptID
        self.scriptSHA256 = scriptSHA256
        self.applyReportJSON = applyReportJSON
    }
}

public struct JobRequest: Equatable, Sendable {
    public let id: UUID
    public let task: String
    public let engine: String
    public let engineVersion: String
    public let requestedModel: String?
    public let schemaVersion: Int
    public let inputSHA256: String
    public let logRelativePath: RelativeProjectPath
    public let resultRelativePath: RelativeProjectPath
    public let parentJobID: UUID?
    public let chunkIndex: Int?
    public let chunkCount: Int?
    public let attemptIndex: Int?
    public let supersedesJobID: UUID?
    public let scriptID: UUID?
    public let scriptSHA256: String?

    public init(
        id: UUID = UUID(),
        task: String,
        engine: String,
        engineVersion: String,
        requestedModel: String?,
        schemaVersion: Int,
        inputSHA256: String,
        logRelativePath: RelativeProjectPath,
        resultRelativePath: RelativeProjectPath,
        parentJobID: UUID? = nil,
        chunkIndex: Int? = nil,
        chunkCount: Int? = nil,
        attemptIndex: Int? = nil,
        supersedesJobID: UUID? = nil,
        scriptID: UUID? = nil,
        scriptSHA256: String? = nil
    ) {
        self.id = id
        self.task = task
        self.engine = engine
        self.engineVersion = engineVersion
        self.requestedModel = requestedModel
        self.schemaVersion = schemaVersion
        self.inputSHA256 = inputSHA256
        self.logRelativePath = logRelativePath
        self.resultRelativePath = resultRelativePath
        self.parentJobID = parentJobID
        self.chunkIndex = chunkIndex
        self.chunkCount = chunkCount
        self.attemptIndex = attemptIndex
        self.supersedesJobID = supersedesJobID
        self.scriptID = scriptID
        self.scriptSHA256 = scriptSHA256
    }
}
