import Foundation
import GRDB

final class ProjectDatabase: @unchecked Sendable {
    let queue: DatabaseQueue
    /// The `user_version` found before any migration ran; `UpgradeSummary` keys on it.
    let versionBeforeMigration: Int
    /// The `"v2"` migration's counters, when that migration ran here.
    let migrationOutcome: MigrationOutcome?

    init(url: URL, creating: Bool) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        queue = try DatabaseQueue(path: url.path, configuration: configuration)

        let version = try queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
        // Refused first, before any migration touches the file.
        if version > ProjectMigrator.currentVersion {
            throw ProjectStoreError.newerProjectVersion(
                found: version,
                supported: ProjectMigrator.currentVersion
            )
        }
        if !creating && version == 0 {
            throw ProjectStoreError.invalidBundle
        }
        versionBeforeMigration = version
        migrationOutcome = try ProjectMigrator.migrate(queue)
    }

    /// The upgrade this open performed, or `nil` when it performed none.
    ///
    /// The `== 1` test is load-bearing twice over, and must not be generalized to
    /// `< ProjectMigrator.currentVersion`:
    ///
    /// - A fresh `create` starts at `user_version = 0` and runs every migration, which is a
    ///   creation rather than an upgrade.
    /// - v2 → v3 is defined as **non-destructive and silent** (§4.2a): it widens one
    ///   `CHECK` and copies every row, so it must surface neither this summary's sheet nor
    ///   the one-way modal. Only a bundle that was at schema 1 reports an upgrade.
    var upgradeSummary: UpgradeSummary? {
        guard versionBeforeMigration == 1, let outcome = migrationOutcome else { return nil }
        return UpgradeSummary(
            fromVersion: versionBeforeMigration,
            toVersion: ProjectMigrator.currentVersion,
            sceneCount: outcome.sceneCount,
            entityCount: outcome.entityCount,
            sequenceCount: outcome.sequenceCount,
            synopsesDropped: outcome.synopsesDropped,
            parseWarnings: outcome.parseWarnings
        )
    }

    func checkpoint() throws {
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }
}
