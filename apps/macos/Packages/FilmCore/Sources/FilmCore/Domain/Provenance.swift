import Foundation

/// Who owns a fact row now (PHASE1_DESIGN §3.6).
public enum FactSource: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case parser
    case ai
    case human
}

/// The review verdict on a fact row (§3.6). `accepted` alone does not mean a person
/// looked at it — `Provenance.reviewedAt` is the only signal of that.
public enum ReviewState: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case proposed
    case accepted
    case rejected
}

/// Who is performing a mutation (§3.7, §3.8). Every controlled mutation carries one.
public enum MutationActor: Codable, Equatable, Hashable, Sendable {
    case human
    case ai(jobID: UUID)

    /// The `edit_journal.actor` / lock-enforcement discriminator.
    public var storageValue: String {
        switch self {
        case .human: "human"
        case .ai: "ai"
        }
    }

    /// The job that is applying this mutation, when the actor is a run.
    public var jobID: UUID? {
        switch self {
        case .human: nil
        case let .ai(jobID): jobID
        }
    }

    /// The `source` / `created_source` an insert by this actor is born with.
    public var factSource: FactSource {
        switch self {
        case .human: .human
        case .ai: .ai
        }
    }
}

/// One banding of model confidence, shared by the review UI and the evaluation reports.
public enum ConfidenceBand: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case low
    case medium
    case high

    public init(confidence: Double) {
        self = confidence < 0.5 ? .low : (confidence < 0.8 ? .medium : .high)
    }
}

/// The provenance every fact row carries (§3.6, §4.3's `PROV`).
///
/// `source` answers "who owns this row now" (protection); `createdSource` and `jobID`
/// answer "who found it" and are never overwritten by a later edit.
public struct Provenance: Codable, Equatable, Hashable, Sendable {
    public let source: FactSource
    public let createdSource: FactSource
    public let confidence: Double?
    public let reviewState: ReviewState
    /// Set *only* by an explicit human action — never by import, parser creation, or an AI apply.
    public let reviewedAt: Date?
    /// The job that CREATED the row.
    public let jobID: UUID?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        source: FactSource,
        createdSource: FactSource,
        confidence: Double? = nil,
        reviewState: ReviewState,
        reviewedAt: Date? = nil,
        jobID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.source = source
        self.createdSource = createdSource
        self.confidence = confidence
        self.reviewState = reviewState
        self.reviewedAt = reviewedAt
        self.jobID = jobID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// `true` when AI may neither modify nor delete the row (§3.6).
    public var isProtected: Bool {
        source == .human || (source == .ai && reviewState == .accepted)
    }

    /// `true` when a later run may update or remove the row (§3.6).
    public var isReplaceable: Bool {
        source == .ai && reviewState == .proposed
    }

    public var confidenceBand: ConfidenceBand? {
        confidence.map(ConfidenceBand.init(confidence:))
    }
}
