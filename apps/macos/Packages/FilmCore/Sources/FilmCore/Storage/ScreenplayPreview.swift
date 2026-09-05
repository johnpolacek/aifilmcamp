import Foundation
import FilmScript

/// A parse-only look at a screenplay file, taken **before** any project exists —
/// the seam behind the screenplay-first Create Project flow.
///
/// The app never imports `FilmScript` directly (PHASE1_DESIGN §3.1), so this is
/// how it learns what a chosen file parses into and what the project should be
/// called, without creating or touching a bundle. Loading is blocking file I/O;
/// callers keep it off the main actor, exactly as `importScreenplay` does.
public struct ScreenplayPreview: Equatable, Sendable {
    /// The chosen file's name, shown verbatim on the confirmation sheet.
    public let fileName: String
    public let format: ScreenplayFormat
    /// Every parsed scene, preamble included — what the import will commit.
    public let sceneCount: Int
    public let warnings: [ParseWarning]
    /// The title page's title when there is one, otherwise the file name with
    /// its extension stripped. Always safe to use as a project directory name:
    /// no path separators, no line breaks, never empty.
    public let suggestedTitle: String

    public init(document: ScreenplayDocument, url: URL) {
        self.fileName = url.lastPathComponent
        self.format = document.format
        self.sceneCount = document.scenes.count
        self.warnings = document.warnings
        self.suggestedTitle = Self.suggestedTitle(
            from: document.titlePage,
            fallback: url.deletingPathExtension().lastPathComponent
        )
    }

    /// Parses `url` and previews it. Throws whatever `ScreenplayImporter.load`
    /// throws — the file is refused before any project exists.
    public static func preview(at url: URL) throws -> ScreenplayPreview {
        ScreenplayPreview(document: try ScreenplayImporter.load(url: url), url: url)
    }

    /// Title page first, fallback second: the Fountain `Title:` entry when the
    /// format carries entries, else the first title-page line (the PDF and FDX
    /// shape), else `fallback`. The result is collapsed to one line and stripped
    /// of `/` and `:` so it is safe to use as the project directory name.
    public static func suggestedTitle(from titlePage: TitlePage, fallback: String) -> String {
        let entry = titlePage.entries.first {
            $0.key.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Title") == .orderedSame
        }
        let candidate = entry?.value ?? titlePage.lines.first
        return projectTitle(from: candidate) ?? projectTitle(fromFileName: fallback) ?? "My Film"
    }

    /// Makes a filename read like a title: separators become spaces and word
    /// boundaries in camel- or Pascal-case names are expanded.
    private static func projectTitle(fromFileName value: String) -> String? {
        let expanded = value
            .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: "([A-Z])([A-Z][a-z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
        return projectTitle(from: expanded)
    }

    /// Turns a derived or user-edited title into one safe Finder folder name.
    /// The title field describes the project, not its filename, so a pasted
    /// `.aifilm` suffix is removed before the coordinator adds the real one.
    public static func projectTitle(from value: String?) -> String? {
        guard let value else { return nil }
        var flattened = value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if flattened.lowercased().hasSuffix(".aifilm") {
            flattened.removeLast(".aifilm".count)
            flattened = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return flattened.isEmpty ? nil : flattened
    }
}
