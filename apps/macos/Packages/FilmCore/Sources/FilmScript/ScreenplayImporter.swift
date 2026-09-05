import Foundation

/// Loading a screenplay file from disk (PHASE1_DESIGN §5.1, Plan 002 Contracts).
///
/// Blocking file I/O; Plan 003 calls it off the main actor. Format is decided by
/// extension, with a content sniff only for extensions the table does not name.
public enum ScreenplayImporter: Sendable {
    /// Reads, decodes, normalizes, and parses the file at `url`.
    ///
    /// - Throws: `ScreenplayLoadError.unreadable` when the bytes cannot be read,
    ///   `ScreenplayLoadError.unsupportedEncoding` when they are neither UTF-8 nor
    ///   BOM-marked UTF-16, `FDXReadError` from the FDX path, and `PDFReadError` from the
    ///   PDF path.
    public nonisolated static func load(url: URL) throws -> ScreenplayDocument {
        guard let data = try? Data(contentsOf: url) else { throw ScreenplayLoadError.unreadable }
        let format = self.format(for: url, data: data)
        if format == .fdx {
            return try FDXReader.read(data)
        }
        // PDF bytes go straight to `PDFReader` and never reach the text decode below. An
        // unknown binary that reached `decode` would throw `.unsupportedEncoding`, and a
        // PDF reporting *that* instead of `PDFReadError.noTextLayer` would tell the
        // filmmaker the wrong thing about their file (§5.5).
        if format == .pdf {
            return try PDFReader.read(data)
        }
        guard let text = decode(data) else { throw ScreenplayLoadError.unsupportedEncoding }
        return FountainParser.parse(TextNormalization.normalize(text), format: format)
    }

    // MARK: - Pieces

    /// `.fdx` → `.fdx`, `.fountain`/`.spmd` → `.fountain`, `.txt` → `.text`, `.pdf` →
    /// `.pdf`; any other extension sniffs the first non-whitespace bytes for `%PDF-`,
    /// then for `<?xml` or `<FinalDraft`.
    ///
    /// Extension still wins over content, so a `.txt` file holding PDF bytes stays
    /// `.text` and throws `.unsupportedEncoding` from the decode — the §5.5 table's
    /// existing behaviour, unchanged.
    static func format(for url: URL, data: Data) -> ScreenplayFormat {
        switch url.pathExtension.lowercased() {
        case "fdx": return .fdx
        case "fountain", "spmd": return .fountain
        case "txt": return .text
        case "pdf": return .pdf
        default:
            // `%PDF-` is tested first: it is an unambiguous magic number, while the XML
            // test is a prefix guess.
            if hasLeadingMarker(data, "%PDF-") { return .pdf }
            return looksLikeFinalDraft(data) ? .fdx : .text
        }
    }

    /// Decodes UTF-8 (with or without a BOM), or UTF-16 when a UTF-16 BOM is present.
    ///
    /// The UTF-16 BOM is checked **first** even though the contract words UTF-8 first:
    /// UTF-16 bytes for ASCII text are also valid UTF-8 (the NUL padding bytes decode
    /// cleanly), so trying UTF-8 first would silently produce a NUL-riddled string
    /// instead of the intended text. Everything without a UTF-16 BOM still goes to
    /// UTF-8 first, and there is no lossy fallback.
    static func decode(_ data: Data) -> String? {
        if data.count >= 2 {
            let first = data[data.startIndex]
            let second = data[data.index(after: data.startIndex)]
            if (first == 0xFF && second == 0xFE) || (first == 0xFE && second == 0xFF) {
                return String(data: data, encoding: .utf16)
            }
        }
        return String(data: data, encoding: .utf8)
    }

    private static func looksLikeFinalDraft(_ data: Data) -> Bool {
        hasLeadingMarker(data, "<?xml") || hasLeadingMarker(data, "<FinalDraft")
    }

    /// Whether `data` starts with `marker` once a UTF-8 BOM and leading whitespace are
    /// skipped. One helper for both sniffs, so the PDF magic and the Final Draft prefix
    /// can never disagree about what "leading" means.
    private static func hasLeadingMarker(_ data: Data, _ marker: String) -> Bool {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        var index = data.startIndex
        if data.count >= 3, data[index] == 0xEF, data[data.index(index, offsetBy: 1)] == 0xBB,
           data[data.index(index, offsetBy: 2)] == 0xBF {
            index = data.index(index, offsetBy: 3)
        }
        while index < data.endIndex, whitespace.contains(data[index]) {
            index = data.index(after: index)
        }
        return data[index...].prefix(16).starts(with: Array(marker.utf8))
    }
}
