import Foundation

/// A storage-independent JSON value (PHASE1_DESIGN §3.8).
///
/// Journal payloads must stay `public Codable` without leaking persistence into the app,
/// so a snapshot is a table name plus plain JSON — never a GRDB row type.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    indirect case array([JSONValue])
    indirect case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// A full snapshot of one database row: the table it came from plus its columns.
///
/// Journal payloads hold these for anything deleted or overwritten — never only ids —
/// so an inverse restores `updated_at`, `reviewed_at`, `review_state`, and `source`
/// byte-identically (§3.8).
public struct RowSnapshot: Codable, Equatable, Hashable, Sendable {
    public let table: String
    public let columns: [String: JSONValue]

    public init(table: String, columns: [String: JSONValue]) {
        self.table = table
        self.columns = columns
    }
}

/// The JSON coders every journal payload uses. `.sortedKeys` keeps payloads stable so a
/// round trip through the journal is byte-identical.
enum JournalCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(UTCDate.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return try UTCDate.date(from: container.decode(String.self))
        }
        return decoder
    }()
}

/// What one `mutate` call did (§3.8): the inverse to journal and every row it touched.
///
/// Internal by contract — the public door is `perform`, not "apply this operation".
struct MutationEffect {
    /// The operation that undoes this one, or `nil` for a non-invertible operation.
    var inverse: EditOperation?
    /// Every row the mutation touched, for conflict detection.
    var affected: Set<SubjectRef>
    /// Full snapshots of anything deleted or overwritten.
    var snapshots: [RowSnapshot]
    /// Merge only (§3.5): source names whose normalized form already belonged to an
    /// unrelated third entity, so the alias insert was skipped rather than thrown. The
    /// human path surfaces them through `MergeResult`; Plan 007's applier counts them
    /// under `ApplyReport.aliasConflicts`.
    var skippedAliases: [String]
    /// What a screenplay write produced, when the operation was one — the counts and
    /// names `ImportSummary` reports. Never journalled.
    var screenplayWrite: ScreenplayWriteResult?
    /// What a selective revert undid and what it left alone (§3.8), for the wrapper that
    /// returns it. Never journalled — the counts are the report, not the payload.
    var revertReport: RevertReport?
    /// PHASE2_DESIGN §4.1's **rows first, files second**: the media files whose rows this
    /// mutation removed, for the session wrapper to unlink **after commit**. Never
    /// journalled, and never acted on inside the transaction — a crash in the gap leaves an
    /// orphaned file, which is harmless and sweepable, and never a row pointing at nothing.
    var removedMediaPaths: [RelativeProjectPath]

    init(
        inverse: EditOperation?,
        affected: Set<SubjectRef> = [],
        snapshots: [RowSnapshot] = [],
        skippedAliases: [String] = [],
        screenplayWrite: ScreenplayWriteResult? = nil,
        revertReport: RevertReport? = nil,
        removedMediaPaths: [RelativeProjectPath] = []
    ) {
        self.inverse = inverse
        self.affected = affected
        self.snapshots = snapshots
        self.skippedAliases = skippedAliases
        self.screenplayWrite = screenplayWrite
        self.revertReport = revertReport
        self.removedMediaPaths = removedMediaPaths
    }
}
