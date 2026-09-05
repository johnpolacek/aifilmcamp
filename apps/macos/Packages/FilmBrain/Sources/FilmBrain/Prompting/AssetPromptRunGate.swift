import FilmCore
import Foundation

/// The coordinator-side twin of FilmCore's run gates (PHASE3_DESIGN §8.1; Plan 016
/// contract C) — the shipped `ManifestRunGate` pattern: this type never enforces anything,
/// it asks the same questions **ahead of launching** so the coordinator declines without
/// creating a job row and the UI greys the action out with the store's own refusal
/// sentence attached, never a paraphrase.
///
/// The pre-flight questions of §8.1: requirement accepted and active, not generation-
/// blocked, not whole-locked — plus §8.1's paused-run gate (a prompt run is refused while
/// any extraction or manifest run is non-terminal or paused). Budget is checked at run
/// start against the rendered snapshot itself.
public enum AssetPromptRunGate: Sendable {
    public enum Refusal: Error, Equatable, Sendable {
        /// An extraction or manifest run is non-terminal or paused.
        case bootstrapsBusy
        case requirementNotAccepted
        case requirementInactive(requirementID: UUID)
        case blocked(dependencyName: String)
        case wholeLocked(requirementID: UUID)

        public var error: ProjectStoreError {
            switch self {
            case .bootstrapsBusy: .promptRunRequiresIdleBootstraps
            case .requirementNotAccepted: .promptRequiresAcceptedRequirement
            case let .requirementInactive(id): .requirementInactive(requirementID: id)
            case let .blocked(name): .promptRequirementBlocked(dependencyName: name)
            case let .wholeLocked(id): .locked(
                subject: SubjectRef(kind: .requirement, id: id), field: .whole
            )
            }
        }
    }

    /// `nil` when a prompt run may be launched for this requirement right now.
    ///
    /// `blockedNames` maps `generationBlockedBy`'s ids to names so the refusal can name
    /// the first entry (§5.8) without this type re-reading the database.
    public static func refusal(
        detail: RequirementDetail,
        bootstrapsIdle: Bool
    ) -> Refusal? {
        guard bootstrapsIdle else { return .bootstrapsBusy }
        guard detail.requirement.provenance.reviewState == .accepted else {
            return .requirementNotAccepted
        }
        guard detail.isActive else {
            return .requirementInactive(requirementID: detail.id)
        }
        if let first = detail.generationBlockedBy.first {
            // Name the first blocker from the planned dependencies' own order.
            let name = detail.plannedDependencies.first {
                $0.requirementID == first
            }?.requirementName ?? "an unsatisfied reference"
            return .blocked(dependencyName: name)
        }
        if detail.locks.contains(where: \.isWholeRecord) {
            return .wholeLocked(requirementID: detail.id)
        }
        return nil
    }
}
