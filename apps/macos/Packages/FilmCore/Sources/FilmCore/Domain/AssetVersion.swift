import Foundation

/// A version's own verdict (PHASE2_DESIGN §6.1: three of the asset-state names reused).
///
/// At most one `approved` version per asset — the partial unique index
/// `index_asset_versions_approved` gives at-most-one; §7.3's operations give exactly-one
/// whenever the asset itself is Approved.
public enum AssetVersionStatus: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case needsReview = "needs_review"
    case approved
    case rejected
}

/// What kind of media a version holds (§4.1). MVP is still images only; video and audio
/// reference media are out of scope (§11).
public enum MediaKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case image
}

/// One `asset_versions` row: a file under `assets/` plus the integrity data captured at
/// import (§4.1, §4.3).
///
/// `relativePath` is a `RelativeProjectPath` resolved against the bundle root at read time,
/// so close/move/reopen needs no path repair; every read that opens the file goes through
/// `BundleContainment` (§4.1). Media is content-addressed for **integrity**, not layout:
/// `sha256` and `byteCount` are what a damaged-asset warning is derived from.
///
/// The PROV `reviewState` here is **inert**, exactly as on `Asset` (§3.7) — a version's
/// working verdict is `status`.
public struct AssetVersion: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let assetID: UUID
    /// One greater than the asset's previous maximum, assigned inside the import
    /// transaction; deleted versions leave gaps and numbers are never reused (§4.1).
    public let versionNumber: Int
    public let status: AssetVersionStatus
    public let relativePath: RelativeProjectPath
    public let sha256: String
    public let byteCount: Int
    /// The name of the file the filmmaker imported, kept for display only.
    public let originalFileName: String
    public let mediaKind: MediaKind
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let notes: String
    public let provenance: Provenance

    public init(
        id: UUID,
        assetID: UUID,
        versionNumber: Int,
        status: AssetVersionStatus,
        relativePath: RelativeProjectPath,
        sha256: String,
        byteCount: Int,
        originalFileName: String,
        mediaKind: MediaKind,
        pixelWidth: Int?,
        pixelHeight: Int?,
        notes: String,
        provenance: Provenance
    ) {
        self.id = id
        self.assetID = assetID
        self.versionNumber = versionNumber
        self.status = status
        self.relativePath = relativePath
        self.sha256 = sha256
        self.byteCount = byteCount
        self.originalFileName = originalFileName
        self.mediaKind = mediaKind
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.notes = notes
        self.provenance = provenance
    }
}
