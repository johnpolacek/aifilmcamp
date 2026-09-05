import Foundation

/// Turns a Codex terminal failure into PHASE1_DESIGN §8.4's normalized
/// `HarnessFailureKind`.
///
/// This is the **only** place in FilmBrain that string-matches provider wording
/// (`usage_limit`, `rate limit`, `429`, model-not-found). Everything downstream reacts
/// to the kind, per the roadmap's "the adapter owns communication details".
///
/// The split between `.usageLimit` and `.retryable` follows §12.2: Codex retries
/// transport and stream errors itself (`stream_max_retries`, `request_max_retries`) but
/// never retries a 429 (`retry_429: false`), so a plain rate-limit rejection reaches us
/// as a terminal event that a backoff *can* fix — `.retryable`. An exhausted usage
/// window (`usage_limit_reached`) cannot be fixed by a backoff of any length the app is
/// willing to wait, so it pauses the run instead — `.usageLimit`.
public enum CodexFailureClassifier: Sendable {
    /// The longest reset hint kept from a provider message.
    static let maximumResetHintLength = 200

    public static func kind(code: String, message: String) -> HarnessFailureKind {
        let haystack = "\(code) \(message)"
        if contains(haystack, any: usageLimitMarkers) {
            return .usageLimit(resetHint: resetHint(in: message))
        }
        if contains(haystack, any: unknownModelMarkers) {
            return .unknownModel
        }
        if contains(haystack, any: retryableMarkers) {
            return .retryable
        }
        return .fatal
    }

    /// `usage_limit_reached` is the API's own code; the CLI surfaces the phrase too.
    private static let usageLimitMarkers = [
        "usage_limit",
        "usage limit",
        "quota",
    ]

    /// A model id is a runtime value typed by the operator (§8.4), so the app never
    /// hard-codes a catalog — it recognizes only the shape of the rejection.
    private static let unknownModelMarkers = [
        "model_not_found",
        "unknown model",
        "unknown_model",
        "unsupported model",
        "unsupported_model",
        "invalid model",
        "invalid_model",
        "unrecognized model",
        "model not found",
        "model does not exist",
        "no such model",
    ]

    private static let retryableMarkers = [
        "rate limit",
        "rate_limit",
        "429",
        "too many requests",
        "temporarily unavailable",
        "overloaded",
    ]

    private static func contains(_ haystack: String, any markers: [String]) -> Bool {
        markers.contains { haystack.range(of: $0, options: [.caseInsensitive]) != nil }
    }

    /// The provider's own wording about when the window reopens, if the message has any.
    ///
    /// Kept verbatim from the marker to the end of its sentence so the UI can show it
    /// without this file pretending to understand Codex's phrasing or clock.
    private static func resetHint(in message: String) -> String? {
        let markers = ["try again", "resets", "reset at", "available again", "retry after"]
        let starts = markers.compactMap { prose(message, startOf: $0) }
        guard let start = starts.min() else { return nil }
        var tail = message[start...]
        if let sentenceEnd = tail.firstIndex(where: { $0 == "." || $0 == "\n" }) {
            tail = tail[..<sentenceEnd]
        }
        let hint = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hint.isEmpty else { return nil }
        return String(hint.prefix(maximumResetHintLength))
    }

    /// The first occurrence of `marker` that reads as prose rather than as part of a
    /// serialized key such as `"resets_at"` — a raw API error body is not a sentence a
    /// person should be shown.
    private static func prose(_ message: String, startOf marker: String) -> String.Index? {
        var searchStart = message.startIndex
        while let range = message.range(
            of: marker,
            options: [.caseInsensitive],
            range: searchStart..<message.endIndex
        ) {
            let before = range.lowerBound == message.startIndex
                ? nil
                : message[message.index(before: range.lowerBound)]
            let after = range.upperBound == message.endIndex ? nil : message[range.upperBound]
            let boundaryBefore = before.map { $0.isWhitespace || $0.isPunctuation } ?? true
            let boundaryAfter = after.map { $0.isWhitespace || $0 == "." || $0 == "," } ?? true
            if boundaryBefore, boundaryAfter, before != "\"", before != "_" {
                return range.lowerBound
            }
            searchStart = range.upperBound
        }
        return nil
    }
}
