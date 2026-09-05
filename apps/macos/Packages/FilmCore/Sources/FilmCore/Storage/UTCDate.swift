import Foundation
import Synchronization

/// The one ISO-8601 UTC timestamp spelling every persisted column uses
/// (PHASE1_DESIGN §4.3, Plan 006).
///
/// v2 writes fractional seconds so rows created inside one transaction still order by
/// `created_at`; reading also accepts v1 strings, which have none. `ISO8601DateFormatter`
/// is not `Sendable`, so the two shared instances live behind a `Mutex`.
public enum UTCDate {
    private static let writing = Mutex<ISO8601DateFormatter>({
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }())

    private static let readingWithoutFractionalSeconds = Mutex<ISO8601DateFormatter>({
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }())

    public static func string(from date: Date) -> String {
        writing.withLock { $0.string(from: date) }
    }

    public static func date(from value: String) throws -> Date {
        if let date = writing.withLock({ $0.date(from: value) }) { return date }
        // v1 bundles were written by a default ISO8601DateFormatter, without fractional seconds.
        if let date = readingWithoutFractionalSeconds.withLock({ $0.date(from: value) }) { return date }
        throw ProjectStoreError.invalidBundle
    }
}
