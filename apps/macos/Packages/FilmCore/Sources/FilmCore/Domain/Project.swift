import Foundation

public enum FilmCoreVersion {
    /// The bundle schema this build writes and accepts. V16 records scene outfit origins. V15 stores scene-specific creative
    /// direction separately from screenplay text. V12 retains successful human image
    /// edits as durable visual amendments. V11 migrates the default character
    /// identity template from four views to the face + headless front/back bundle. V8 retires the routine review queue:
    /// existing proposed AI facts become active without pretending a person reviewed them.
    /// V7 admitted evidence for scene-wide continuity events whose domain-level `entityID`
    /// is intentionally nil. V6
    /// was introduced by Plan 018, whose
    /// `"v6"` migration adds the scene-package tables and the project's style-bible and
    /// target-profile columns (PHASE5_DESIGN §4.2); `"v5"` (Plan 013) added the prompt
    /// tables and the workflow-marker column (PHASE3_DESIGN §4.2); `"v4"` (Plan 009)
    /// added the asset-manifest tables (PHASE2_DESIGN §4.2); `"v3"` (Plan 008) widened
    /// `scripts.format` to admit `'pdf'` (PHASE1_DESIGN §4.2a).
    public static let bundleSchema = 16
}

public struct Project: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let bundleSchemaVersion: Int
    /// The script every read resolves against; `nil` until a screenplay is imported.
    public let currentScriptID: UUID?
    /// The first-run privacy acknowledgement, travelling with the bundle (§9).
    public let disclosureAcknowledgedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        name: String,
        bundleSchemaVersion: Int,
        currentScriptID: UUID?,
        disclosureAcknowledgedAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.bundleSchemaVersion = bundleSchemaVersion
        self.currentScriptID = currentScriptID
        self.disclosureAcknowledgedAt = disclosureAcknowledgedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
