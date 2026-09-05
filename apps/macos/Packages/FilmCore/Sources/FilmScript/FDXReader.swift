import Foundation

/// Final Draft XML reading (PHASE1_DESIGN §5.4).
///
/// There is no public FDX schema; every rule below is reverse-engineered (§12.1) and
/// non-negotiable. The two that published importers most often get wrong, and that this
/// reader is built around:
///
/// 1. **`Paragraph` is recursive.** `SceneProperties/Summary`, `SceneArcBeats`, and
///    `ScriptNote` all nest paragraphs, so a descendant selector injects outline and
///    synopsis prose straight into the screenplay. This walk takes only the **direct**
///    `Paragraph` children of `/FinalDraft/Content`, and descends into `DualDialogue`
///    and nothing else.
/// 2. **Paragraph text is the concatenation of its direct `Text` children with no
///    separator and no trimming.** Styled words split a sentence into runs and the
///    spaces live at the run boundaries, so joining with a space (or keeping only the
///    first run) corrupts one paragraph in five.
///
/// Reading never decodes the bytes itself: `XMLParser` owns encoding detection, so the
/// XML declaration and any byte order mark are its problem, not this file's.
public enum FDXReader: Sendable {
    /// Reads Final Draft XML into a `ScreenplayDocument`.
    ///
    /// The paragraphs are rendered to Fountain by `FDXRenderer` and parsed by
    /// `FountainParser` with `format: .fdx`, so scene segmentation is identical for both
    /// formats (§5.4). `sourceText` is the rendered text; the `TitlePage` carries `lines`
    /// only, because FDX has no key/value entries.
    ///
    /// - Throws: `FDXReadError.malformed(line:column:)` at the parser's reported
    ///   position for XML that does not parse.
    public nonisolated static func read(_ data: Data) throws -> ScreenplayDocument {
        /// The SAX walk. Local, so it cannot escape and needs no `Sendable` claim; it is
        /// created, driven, and dropped before this function returns.
        final class Walk: NSObject, XMLParserDelegate {
            /// A body paragraph being captured, and where it sits on the element stack.
            struct Open {
                let stackIndex: Int
                let type: String
                let number: String?
                var text: String
                let isDualChild: Bool
            }

            /// Which `Content` element the walk is inside, if any.
            enum ContentKind { case body, titlePage }

            /// Element names, innermost last. Indices into it are how "direct child" is
            /// decided without assuming a fixed nesting depth.
            private(set) var stack: [String] = []
            private(set) var paragraphs: [FDXParagraph] = []

            private var contentKind: ContentKind?
            private var contentStackIndex: Int?
            /// Stack index of a `DualDialogue` whose parent is a body-level paragraph.
            private var dualStackIndex: Int?
            /// Stack index of the body-level wrapper paragraph holding that `DualDialogue`.
            private var dualWrapperStackIndex: Int?
            /// `Character` cues seen so far inside the open `DualDialogue`; the second
            /// one is the `^` speaker (§5.4).
            private var dualCharacterCount = 0
            private var open: Open?
            /// Stack index of the direct `Text` child whose characters are being taken.
            private var textStackIndex: Int?

            func parser(
                _ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]
            ) {
                let parent = stack.last
                stack.append(elementName)
                let index = stack.count - 1

                switch elementName {
                case "Content":
                    // `TitlePage` has its own `Content`; anything else is not a content
                    // root and its paragraphs are metadata.
                    if parent == "FinalDraft" {
                        contentKind = .body
                        contentStackIndex = index
                    } else if parent == "TitlePage" {
                        contentKind = .titlePage
                        contentStackIndex = index
                    }

                case "DualDialogue":
                    // Only a `DualDialogue` directly inside a captured body paragraph is
                    // the real thing. Its wrapper paragraph carries no type and no text
                    // of its own, so it is suppressed and its children are captured flat.
                    if let current = open, current.stackIndex == index - 1, !current.isDualChild {
                        dualWrapperStackIndex = current.stackIndex
                        dualStackIndex = index
                        dualCharacterCount = 0
                        open = nil
                        textStackIndex = nil
                    }

                case "Paragraph":
                    let isDirectChild = parent == "Content" && contentStackIndex == index - 1
                        && contentKind != nil
                    let isDualChild = parent == "DualDialogue" && dualStackIndex == index - 1
                    guard isDirectChild || isDualChild else {
                        // `SceneProperties/Summary`, `SceneArcBeats`, `ScriptNote`: metadata.
                        break
                    }
                    let type: String
                    if isDirectChild, contentKind == .titlePage {
                        type = FDXRenderer.titlePageType
                    } else {
                        // Absent `Paragraph@Type` defaults to `Action` (§5.4).
                        type = attributes["Type"] ?? "Action"
                    }
                    open = Open(
                        stackIndex: index,
                        type: type,
                        number: attributes["Number"],
                        text: "",
                        isDualChild: isDualChild
                    )
                    textStackIndex = nil

                case "Text":
                    // Direct `Text` children only; a `Text` nested deeper (inside a
                    // metadata paragraph, say) must not leak into this paragraph.
                    if let current = open, current.stackIndex == index - 1 {
                        textStackIndex = index
                    }

                default:
                    break
                }
            }

            func parser(_ parser: XMLParser, foundCharacters string: String) {
                // Characters belong to the innermost open element, so this also rejects
                // text inside an element nested *within* the captured `Text` run.
                guard let textIndex = textStackIndex, textIndex == stack.count - 1 else { return }
                open?.text += string
            }

            func parser(
                _ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?
            ) {
                let index = stack.count - 1
                defer { if !stack.isEmpty { stack.removeLast() } }

                if textStackIndex == index { textStackIndex = nil }

                if let current = open, current.stackIndex == index {
                    var isDualSecond = false
                    if current.isDualChild, current.type.lowercased() == "character" {
                        dualCharacterCount += 1
                        isDualSecond = dualCharacterCount == 2
                    }
                    paragraphs.append(
                        FDXParagraph(
                            type: current.type,
                            text: current.text,
                            number: current.number,
                            isDualSecond: isDualSecond
                        )
                    )
                    open = nil
                }
                if dualStackIndex == index {
                    dualStackIndex = nil
                    dualCharacterCount = 0
                }
                if dualWrapperStackIndex == index { dualWrapperStackIndex = nil }
                if contentStackIndex == index {
                    contentStackIndex = nil
                    contentKind = nil
                }
            }
        }

        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let walk = Walk()
        parser.delegate = walk
        guard parser.parse() else {
            throw FDXReadError.malformed(line: parser.lineNumber, column: parser.columnNumber)
        }

        let rendered = FDXRenderer.render(walk.paragraphs)
        // Normalization is a no-op here — the renderer emits `\n` and no BOM — but the
        // contract is that `sourceText` is always normalized text, so it runs anyway.
        let text = TextNormalization.normalize(rendered.text)
        let document = FountainParser.parse(text, format: .fdx)

        return ScreenplayDocument(
            format: document.format,
            sourceText: document.sourceText,
            titlePage: TitlePage(entries: [], lines: rendered.titlePageLines),
            sequences: document.sequences,
            scenes: document.scenes,
            warnings: merge(rendered.warnings, document.warnings)
        )
    }

    /// Renderer warnings and parser warnings in one stable document order: by range
    /// start, rangeless warnings last, ties keeping renderer-before-parser order.
    private static func merge(_ rendererWarnings: [ParseWarning], _ parserWarnings: [ParseWarning]) -> [ParseWarning] {
        (rendererWarnings + parserWarnings)
            .enumerated()
            .sorted { left, right in
                let leftStart = left.element.range?.start ?? Int.max
                let rightStart = right.element.range?.start ?? Int.max
                if leftStart != rightStart { return leftStart < rightStart }
                return left.offset < right.offset
            }
            .map(\.element)
    }
}
