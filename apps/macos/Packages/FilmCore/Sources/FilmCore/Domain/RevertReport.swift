import Foundation

/// What `revertExtractionRun(jobID:)` undid, and what it left alone (PHASE1_DESIGN §3.8).
///
/// Revert is **selective**: an entry whose `affected` set intersects a later uncancelled
/// human entry's is skipped so the operator's own edit survives, and skips are transitive
/// backward through the run. The report is what the UI reads out — "Reverted 412 changes;
/// 3 skipped because you edited them".
public struct RevertReport: Codable, Equatable, Hashable, Sendable {
    public let jobID: UUID
    public let reverted: Int
    public let skipped: Int
    /// The subjects the skipped entries touched, deduplicated and ordered by `(kind, id)`.
    public let skippedSubjects: [SubjectRef]

    public init(jobID: UUID, reverted: Int, skipped: Int, skippedSubjects: [SubjectRef]) {
        self.jobID = jobID
        self.reverted = reverted
        self.skipped = skipped
        self.skippedSubjects = skippedSubjects
    }
}
