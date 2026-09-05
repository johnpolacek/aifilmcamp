import Foundation
import FilmScript

public struct Script: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let displayName: String
    public let sourceAssetID: UUID
    /// The format the text was imported from (§4.3).
    public let format: ScreenplayFormat
    /// The untouched original in `screenplay/`; `ON DELETE RESTRICT` keeps it referenced.
    public let originalAssetID: UUID
    /// Always the normalized text: every v2 span is an offset into it.
    public let sourceText: String
    /// Digest of `sourceText`'s UTF-8 bytes — not of the original file's bytes.
    public let sha256: String
    public let titlePage: TitlePage
    /// The `FilmScript` version that produced the scenes.
    public let parserVersion: String
    /// Persisted at import; the only way an import or upgrade summary can report warnings.
    public let parseWarnings: [ParseWarning]
    public let createdAt: Date

    public init(
        id: UUID,
        projectID: UUID,
        displayName: String,
        sourceAssetID: UUID,
        format: ScreenplayFormat,
        originalAssetID: UUID,
        sourceText: String,
        sha256: String,
        titlePage: TitlePage,
        parserVersion: String,
        parseWarnings: [ParseWarning],
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.displayName = displayName
        self.sourceAssetID = sourceAssetID
        self.format = format
        self.originalAssetID = originalAssetID
        self.sourceText = sourceText
        self.sha256 = sha256
        self.titlePage = titlePage
        self.parserVersion = parserVersion
        self.parseWarnings = parseWarnings
        self.createdAt = createdAt
    }
}
