import Foundation

/// The enumerated lock fields of PHASE1_DESIGN §3.7 — never an arbitrary column.
///
/// Which fields a subject kind admits is `LockPolicy`'s answer (Plan 005 step 4); this
/// type is only the vocabulary, and its raw values are exactly what `locks.field` stores,
/// so `Lock.wholeRecord` and `LockField.whole` are the same string.
public enum LockField: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case name
    case description
    case kind
    case isRelevant = "is_relevant"
    case synopsis
    /// A requirement's prose justification (PHASE2_DESIGN §7.5).
    case reason
    /// A requirement's `required | optional | not_needed` (§7.5).
    case necessity
    /// The whole record (`Lock.wholeRecord`).
    case whole = "*"

    /// The name an undo action or a lock button shows ("Lock Name", "Unlock Record").
    public var displayName: String {
        switch self {
        case .name: "Name"
        case .description: "Description"
        case .kind: "Kind"
        case .isRelevant: "Relevance"
        case .synopsis: "Synopsis"
        case .reason: "Reason"
        case .necessity: "Necessity"
        case .whole: "Record"
        }
    }
}
