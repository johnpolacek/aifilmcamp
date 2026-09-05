import FilmCore
import Foundation

/// PHASE1_DESIGN §8.4's normalized failure classes.
///
/// The kind is produced **inside the adapter** — `CodexFailureClassifier` is the only
/// place that inspects provider wording — so a run coordinator can react without
/// knowing anything about Codex. Plan 003 consumes no kind: every failure is still
/// terminal for the job. Plan 007's coordinator pauses on `.usageLimit`, retries once
/// on `.retryable`, fails the run on `.unknownModel`, and fails the chunk on `.fatal`.
public enum HarnessFailureKind: Equatable, Sendable {
    /// The account's usage window is exhausted; `resetHint` is the provider's own
    /// wording about when it reopens, when the message carried one.
    case usageLimit(resetHint: String?)
    /// Transient; the same request may succeed after a backoff.
    case retryable
    /// The requested model id was rejected.
    case unknownModel
    /// Anything else: not worth retrying, not the account's quota.
    case fatal
}

public enum HarnessEvent: Equatable, Sendable {
    case started(threadID: String?, effectiveModel: String?)
    case progress(String)
    case diagnostic(String)
    case completed(JobUsage)
    case failed(code: String, message: String, kind: HarnessFailureKind)
    case cancelled
    case decodeWarning(String)
    case unknown(type: String)

    public var isTerminalSuccess: Bool {
        if case .completed = self { return true }
        return false
    }

    public var isTerminalFailure: Bool {
        switch self {
        case .failed, .cancelled: true
        default: false
        }
    }
}

