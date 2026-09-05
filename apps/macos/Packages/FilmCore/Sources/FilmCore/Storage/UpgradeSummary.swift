import Foundation
import FilmScript

/// What opening a bundle upgraded (PHASE1_DESIGN §4.2; Plan 003 contract B).
///
/// `ProjectSession.upgradeSummary` is non-nil **exactly** when a migration ran — a fresh
/// `create` runs both migrations over an empty database and yields `nil`. The app shows a
/// one-way upgrade modal before migrating and this summary after.
public struct UpgradeSummary: Equatable, Sendable {
    public let fromVersion: Int
    public let toVersion: Int
    public let sceneCount: Int
    public let entityCount: Int
    public let sequenceCount: Int
    /// Non-empty Phase 0 synopses dropped because the parser's scene count differed.
    public let synopsesDropped: Int
    /// Decoded from the persisted `scripts.parse_warnings_json`; nothing else can report them.
    public let parseWarnings: [ParseWarning]

    public init(
        fromVersion: Int,
        toVersion: Int,
        sceneCount: Int,
        entityCount: Int,
        sequenceCount: Int,
        synopsesDropped: Int,
        parseWarnings: [ParseWarning]
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.sceneCount = sceneCount
        self.entityCount = entityCount
        self.sequenceCount = sequenceCount
        self.synopsesDropped = synopsesDropped
        self.parseWarnings = parseWarnings
    }
}

/// What `ProjectBundle.inspect(at:)` can say about a bundle without opening it.
public struct BundleInspection: Equatable, Sendable {
    public let bundleURL: URL
    /// The `user_version` stamped in `project.db`, read from its header bytes.
    public let schemaVersion: Int

    public init(bundleURL: URL, schemaVersion: Int) {
        self.bundleURL = bundleURL
        self.schemaVersion = schemaVersion
    }

    /// `true` when opening this bundle would run a migration — **any** migration, including
    /// a silent one. Not the modal's gate; see `needsOneWayUpgrade`.
    public var needsUpgrade: Bool { schemaVersion < FilmCoreVersion.bundleSchema }
    /// `true` when opening this bundle would run the **one-way, destructive** Phase 0
    /// upgrade — the only one the §3.11 modal warns about.
    ///
    /// Only v1 → v2 re-parses the screenplay, rebuilds scenes, and can drop synopses, so
    /// only schema 1 earns the modal. v2 → v3 widens one `CHECK` and copies every row
    /// (§4.2a), and gating the modal on `needsUpgrade` would make every existing project
    /// open with a warning that its scenes are about to be rebuilt.
    public var needsOneWayUpgrade: Bool { schemaVersion == 1 }
    /// `true` when this build refuses the bundle outright.
    public var isNewerThanSupported: Bool { schemaVersion > FilmCoreVersion.bundleSchema }
}
