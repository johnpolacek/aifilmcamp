import Foundation
import PDFKit

/// PDF screenplay reading (PHASE1_DESIGN §3.2a, §5.4a).
///
/// The **only** file in `FilmScript` that imports `PDFKit`, and it keeps the framework
/// entirely inside its own function bodies: no PDFKit type appears in any signature here
/// or anywhere else, so `FilmScript`'s public boundary is still `String`/`Data`/`URL`
/// among Foundation types (§3.1). PDFKit is a **system** framework, so §3.1's "no
/// dependencies" rule holds and `Package.resolved` does not change (§3.2a). The moment a
/// PDFKit type appears in a signature, or a second file imports it, that boundary has been
/// given up — which is a design change, not a refactor.
///
/// Reading composes exactly as `FDXReader.read` does: `lines(_:)` recovers geometry,
/// `PDFRenderer.render` turns geometry into Fountain, and `FountainParser` parses that, so
/// PDF inherits the one scene contract instead of getting rules of its own.
public enum PDFReader: Sendable {
    /// Reads a PDF's text layer into a `ScreenplayDocument`.
    ///
    /// `sourceText` is the rendering, never the file's own byte stream, and every span in
    /// the result is an offset into that rendering (§3.3). The title page, when the §5.4a
    /// rule below recognizes one, populates `TitlePage.lines` and nothing else: positional
    /// text carries no key/value structure, so `entries` is empty exactly as it is for FDX.
    ///
    /// - Throws: `PDFReadError.unreadable` for bytes PDFKit will not open,
    ///   `.encrypted` for a locked or encrypted document, and
    ///   `.noTextLayer(pagesTotal:pagesWithText:)` for a document with under 200
    ///   characters of extractable text — a scanned PDF is **refused, never OCR'd** (§11
    ///   keeps OCR a non-goal) and never silently rendered as an empty screenplay.
    public nonisolated static func read(_ data: Data) throws -> ScreenplayDocument {
        let extracted = try lines(data)
        let split = splitTitlePage(extracted)
        let rendered = PDFRenderer.render(split.body)
        // Normalization is a no-op here — the renderer emits `\n` and no BOM — but the
        // contract is that `sourceText` is always normalized text, so it runs anyway.
        let text = TextNormalization.normalize(rendered.text)
        let document = FountainParser.parse(text, format: .pdf)

        return ScreenplayDocument(
            format: document.format,
            sourceText: document.sourceText,
            titlePage: TitlePage(entries: [], lines: split.titlePageLines),
            sequences: document.sequences,
            scenes: document.scenes,
            // Renderer warnings first, then the parser's, in that order (contract A).
            warnings: rendered.warnings + document.warnings
        )
    }

    // MARK: - The title page (§5.4a)

    /// The most lines a first page may hold and still be a title page (§5.4a).
    static let maximumTitlePageLines = 12

    /// Splits the extracted lines into the title page's verbatim text and the body that
    /// gets margin-classified.
    ///
    /// **Page 1 is a title page when it holds no scene heading and at most 12 lines.**
    /// Both halves matter, and the rule never guesses: a first page that fails either half
    /// is classified normally, so a screenplay that opens directly on a scene is untouched.
    ///
    /// This lives in the reader because the reader is the only place that knows where a
    /// page begins — which is also why `PDFRenderer.render` can keep returning a 2-tuple
    /// while `FDXRenderer.render` returns a 3-tuple. The body handed to the renderer no
    /// longer contains a single page-1 line, so **no** line of a title page is ever
    /// margin-classified. That is the specific failure this rule was written for: a
    /// centered title, `Written by`, and an author name sit at 0.43–0.46 of the page
    /// width, land squarely in the character-cue cluster, and would otherwise import as
    /// three character entities. Excluding them from `sourceText` also keeps title-page
    /// prose out of extraction, evidence, and Phase 2's asset generation — a title is data
    /// *about* the screenplay, not part of it.
    ///
    /// Page furniture is not subtracted before the 12-line count: §5.4a counts the lines
    /// the page holds, and dropping furniture is the renderer's job over the body.
    static func splitTitlePage(_ lines: [PDFLine]) -> (titlePageLines: [String], body: [PDFLine]) {
        let firstPage = lines.prefix { $0.pageIndex == 0 }
        guard !firstPage.isEmpty, firstPage.count <= maximumTitlePageLines else { return ([], lines) }
        guard !firstPage.contains(where: { FountainLineClassifier.isPrefixedHeading($0.text) })
        else { return ([], lines) }
        return (firstPage.map(\.text), Array(lines.dropFirst(firstPage.count)))
    }

    /// Extracts one `PDFLine` per text line, in page then reading order.
    ///
    /// Internal geometry extraction boundary, not part of the format's public surface.
    ///
    /// The error order is deliberate. A locked or encrypted document is reported as
    /// `.encrypted` **before** the text-layer test, so an encrypted file never tells the
    /// filmmaker it has no text; PDFKit hands back a document object for it, and its text
    /// would measure as empty.
    nonisolated static func lines(_ data: Data) throws -> [PDFLine] {
        guard let document = PDFDocument(data: data) else { throw PDFReadError.unreadable }
        guard !document.isLocked, !document.isEncrypted else { throw PDFReadError.encrypted }

        var extracted: [PDFLine] = []
        var characterCount = 0
        var pagesWithText = 0

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let mediaBox = page.bounds(for: .mediaBox)
            guard mediaBox.width > 0, mediaBox.height > 0 else { continue }
            guard let selection = page.selection(for: mediaBox) else { continue }

            let before = extracted.count
            for lineSelection in selection.selectionsByLine() {
                let raw = lineSelection.string ?? ""
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                characterCount += text.count

                let bounds = lineSelection.bounds(for: page)
                extracted.append(
                    PDFLine(
                        text: text,
                        pageIndex: index,
                        leftFraction: Double((bounds.minX - mediaBox.minX) / mediaBox.width),
                        rightFraction: Double((bounds.maxX - mediaBox.minX) / mediaBox.width),
                        topFraction: Double((mediaBox.maxY - bounds.maxY) / mediaBox.height),
                        bottomFraction: Double((mediaBox.maxY - bounds.minY) / mediaBox.height)
                    )
                )
            }
            if extracted.count > before { pagesWithText += 1 }
        }

        guard characterCount >= minimumTextLayerCharacters else {
            // The counts turn a bare refusal into a diagnosis: "no selectable text in 0 of
            // 91 pages" is what tells the filmmaker their file is a scan (§5.4a).
            throw PDFReadError.noTextLayer(
                pagesTotal: document.pageCount,
                pagesWithText: pagesWithText
            )
        }
        return extracted
    }

    /// Below this many extracted characters a PDF has no usable text layer (§5.4a).
    static let minimumTextLayerCharacters = 200
}
