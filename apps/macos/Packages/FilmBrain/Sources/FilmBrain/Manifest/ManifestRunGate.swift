import FilmCore
import Foundation

/// The coordinator-side consumer of §3.6's bootstrap ordering (PHASE2_DESIGN §3.6, §8.1).
///
/// **Placement is contract**: all three refusals are FilmCore throws beside the
/// import/replace refusals in `ProjectRepository`/`ProjectSession`, so no path around the
/// UI exists. This type never enforces anything — it asks the same questions of the run
/// history *before* launching, so the coordinator can decline without creating a job row
/// and the UI can grey the action out with the reason attached.
public enum ManifestRunGate: Sendable {
    /// Why a manifest run may not be launched right now.
    public enum Refusal: Error, Equatable, LocalizedError, Sendable {
        /// Run-once (§3.6): a completed `inferAssetManifest` run exists for this script.
        /// A failed or cancelled attempt applied nothing and leaves the action available.
        case alreadyApplied
        /// An extraction run for this script is non-terminal or **paused** — Phase 1's
        /// one-active-run rule alone does not cover paused runs, which may otherwise resume
        /// and apply after the manifest exists.
        case extractionRunActive

        public var errorDescription: String? {
            switch self {
            case .alreadyApplied: ProjectStoreError.manifestAlreadyApplied.errorDescription
            case .extractionRunActive:
                ProjectStoreError.manifestRefusedDuringExtraction.errorDescription
            }
        }
    }

    /// `nil` when a manifest run may be launched for `scriptID`.
    ///
    /// Both questions are **script-scoped**, like the extraction latch and for the same
    /// reason (§8.1): §5.5's Replace deletes `scripts` and `entities` but not `jobs`, so a
    /// project-scoped gate would strand a replaced screenplay that could then be neither
    /// analyzed nor manifested.
    public static func refusal(scriptID: UUID, jobs: [Job]) -> Refusal? {
        let ours = jobs.filter { $0.parentJobID == nil && $0.scriptID == scriptID }
        if ours.contains(where: { $0.task == Job.manifestTask && $0.state == .completed }) {
            return .alreadyApplied
        }
        if ours.contains(where: {
            $0.task == Job.extractionTask && !$0.state.isTerminal
        }) {
            return .extractionRunActive
        }
        return nil
    }

    /// `true` once a completed manifest run has **permanently closed extraction for this
    /// screenplay** (§3.6). The Analyze action reads this to explain itself; FilmCore
    /// refuses the run regardless.
    public static func extractionIsClosed(scriptID: UUID, jobs: [Job]) -> Bool {
        jobs.contains {
            $0.parentJobID == nil && $0.scriptID == scriptID
                && $0.task == Job.manifestTask && $0.state == .completed
        }
    }

    /// The §3.6 refusal clause, verbatim from the one FilmCore constant — so the sentence
    /// the operator reads and the sentence the store throws cannot drift apart.
    public static var extractionClosedReason: String {
        ProjectStoreError.manifestClosesExtractionReason
    }
}
