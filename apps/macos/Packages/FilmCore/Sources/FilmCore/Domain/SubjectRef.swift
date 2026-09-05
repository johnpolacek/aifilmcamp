import Foundation

/// The one subject vocabulary (PHASE1_DESIGN §3.8, §4.4).
///
/// `locks.subject_kind` accepts the `entity | alias | scene | state | event | relationship`
/// subset and `evidence.subject_kind` the `entity | alias | appearance | state | event |
/// relationship | synopsis` subset; both are enforced by their `CHECK`s. There is no
/// separate `LockSubject` type.
public enum SubjectKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case entity
    case alias
    case appearance
    case scene
    case state
    case event
    case relationship
    case synopsis
    case script

    // PHASE2_DESIGN §7.5: every table the manifest operations touch, so affected sets and
    // snapshots stay complete.

    /// An `asset_requirements` row.
    case requirement
    /// An `asset_requirement_scenes` row — a variant requirement's stored scene link.
    case requirementScene
    /// An `asset_requirement_basis` row — an immutable citation, never reviewed (§3.7).
    case basis
    /// An `asset_dependencies` row.
    case dependency
    /// An `assets` row — the media slot of one requirement.
    case asset
    /// An `asset_versions` row.
    case version
    /// An `asset_requirement_types` row — a template entry, which is settings, not a fact.
    case templateEntry

    // PHASE3_DESIGN §7.4: every table the prompt model adds, so affected sets and
    // snapshots stay complete.

    /// An `asset_prompts` row.
    case prompt
    /// An `asset_prompt_references` row — an immutable citation, never reviewed (§3.3).
    case promptReference

    /// The subset `locks.subject_kind` admits (§3.7 — `alias` included; PHASE2_DESIGN
    /// §4.2 step 4 rebuilt the `CHECK` to admit `requirement`, and §7.5 adds that kind
    /// **only**).
    public static let lockable: Set<SubjectKind> = [
        .entity, .alias, .scene, .state, .event, .relationship, .requirement,
    ]

    /// The subset `evidence.subject_kind` admits (§4.3).
    ///
    /// Unchanged by Phase 2: requirements justify themselves through **basis** rows, not
    /// evidence rows, so the `evidence` CHECK is not widened (PHASE2_DESIGN §7.5).
    public static let evidenceable: Set<SubjectKind> = [
        .entity, .alias, .appearance, .state, .event, .relationship, .synopsis,
    ]
}

/// One row identified across tables, as journal `affected` sets and locks name it.
public struct SubjectRef: Codable, Equatable, Hashable, Sendable {
    public let kind: SubjectKind
    public let id: UUID

    public init(kind: SubjectKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}
