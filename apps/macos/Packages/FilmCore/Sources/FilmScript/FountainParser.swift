import Foundation

/// The deterministic screenplay parser (PHASE1_DESIGN §5.1–§5.3).
///
/// One pure function from normalized text to a `ScreenplayDocument`: same bytes in,
/// byte-identical encoding out. No global mutable state, no I/O, no AI.
///
/// ## Range and text conventions
///
/// - Every range is a **half-open UTF-16 code-unit offset pair** into `sourceText`,
///   which is always the normalized text (§3.3). `parse` re-runs
///   `TextNormalization.normalize` as a guard; it is idempotent, so passing already
///   normalized text changes nothing.
/// - A **line** is the text up to but not including its `\n`. `lineStart` is the offset
///   of its first code unit, `lineEnd` the offset of its `\n` (or end of text).
/// - **Element range** = `[lineStart(first line), lineEnd(last line))` — the newline
///   that ends the block is *not* included. Single-line elements therefore span exactly
///   their line's content.
/// - **Cue range** = the cue line's content range.
/// - **Scene range** = `[heading lineStart, next heading lineStart)`, or end of text for
///   the last scene, so trailing blank lines belong to the preceding scene (§5.2).
/// - **Sequence range** = `[# lineStart, start of the next section of the same or
///   shallower depth)`, or end of text (§5.2).
/// - **Element text** is the source over the element's range with excised note and
///   boneyard spans removed, verbatim ("as authored"), for `sceneHeading`, `action`,
///   `character`, `parenthetical`, and `dialogue`. The marker-carrying kinds store the
///   payload instead: `section` → title, `synopsis` → text after `=`, `centered` →
///   interior of `> <`, `transition` → line without a forcing `>`, `lyric` → text after
///   `~`, `pageBreak` → the trimmed `===` run. `note` and `boneyard` store their **raw**
///   source slice, markers included, over their (per-scene clipped) range.
/// - A line whose text is empty **after excision** counts as blank for every
///   block-boundary rule, so a line holding nothing but a note terminates the block
///   around it.
/// - Contiguous action lines join into one `action` element with `\n`; contiguous
///   dialogue lines (between parentheticals) join into one `dialogue` element the same
///   way; each parenthetical is its own element.
/// - A scene belongs to the most recent section of the **shallowest depth among the
///   sections that start at or before its heading** (§5.2). The rule is local: a deeper
///   section never reassigns a scene, and appending a section later in the file cannot
///   change an earlier scene's `sequenceOrdinal`.
/// - Elements that overlap **no** scene belong to no scene. That happens only in a
///   preamble that does not qualify as scene 0 — its sections still become sequences,
///   and its other elements are simply not reported.
/// - Notes and boneyard are excised **before** classification (§5.1) over the **whole**
///   document, title page included, so a heading or cue inside one starts nothing.
///   Each is emitted as its own element, clipped to every scene it overlaps and
///   emitted once per scene; on an equal start offset the
///   excision sorts **before** the element that shares it, matching document order —
///   except against the scene's own `sceneHeading`, which stays first so that every
///   numbered scene's `elements` still begins with its heading.
public enum FountainParser: Sendable {
    /// Parses `text` (normalized, or normalized here as a guard) into a document.
    public nonisolated static func parse(_ text: String, format: ScreenplayFormat) -> ScreenplayDocument {
        var builder = FountainParseBuilder(source: TextNormalization.normalize(text), format: format)
        return builder.run()
    }
}

// MARK: - Builder

/// One parse in progress. A value type created, used, and dropped inside `parse`, so
/// nothing escapes and there is no shared state to synchronize.
private struct FountainParseBuilder {
    // MARK: Storage

    private struct Line {
        let start: Int
        let end: Int
    }

    /// One excised `[[ ]]` or `/* */` span, in document order.
    private struct Excision {
        let start: Int
        let end: Int
        let kind: ElementKind
    }

    /// An element before it is assigned to a scene.
    private struct Pending {
        let kind: ElementKind
        let start: Int
        let end: Int
        let text: String
    }

    /// Everything the line walk produces.
    private struct Classification {
        var elements: [Pending] = []
        var cues: [ParsedCue] = []
        var headings: [(lineIndex: Int, parsed: ParsedHeading)] = []
        var sections: [(start: Int, depth: Int, title: String)] = []
    }

    let source: String
    let format: ScreenplayFormat
    private let units: [UInt16]
    private let lines: [Line]
    private var masked: [Bool]
    private var excisions: [Excision] = []
    private var warnings: [ParseWarning] = []

    init(source: String, format: ScreenplayFormat) {
        self.source = source
        self.format = format
        let units = Array(source.utf16)
        self.units = units
        self.masked = [Bool](repeating: false, count: units.count)

        var lines: [Line] = []
        var start = 0
        var index = 0
        while index < units.count {
            if units[index] == 0x000A {
                lines.append(Line(start: start, end: index))
                start = index + 1
            }
            index += 1
        }
        // Always one final line, possibly empty: a text ending in `\n` has an empty
        // last line, and the empty document has exactly one empty line.
        lines.append(Line(start: start, end: units.count))
        self.lines = lines
    }

    // MARK: Entry point

    mutating func run() -> ScreenplayDocument {
        // Excision comes first and covers the WHOLE text (§5.1): notes and boneyard are
        // removed before *any* line classification, the title-page block included. A
        // `[[ ]]` or `/* */` span is therefore never title-page content — the block is
        // detected, delimited, and valued over the excised view — and a span that opens
        // inside the title page is still emitted as an element, clipped to whichever
        // scenes it overlaps, exactly like one that opens in the body.
        excise()
        let (effective, trimmed) = effectiveLineTexts()

        let (titlePage, bodyStartLine) = parseTitlePage(effective: effective, trimmed: trimmed)
        let bodyStart = bodyStartLine < lines.count ? lines[bodyStartLine].start : units.count

        let classification = classify(from: bodyStartLine, effective: effective, trimmed: trimmed)
        let sequences = buildSequences(from: classification.sections)
        let scenes = buildScenes(bodyStart: bodyStart, sequences: sequences, classification: classification)

        return ScreenplayDocument(
            format: format,
            sourceText: source,
            titlePage: titlePage,
            sequences: sequences,
            scenes: scenes,
            warnings: sortedWarnings()
        )
    }

    // MARK: Text access

    /// The source over `[start, end)` with excised spans removed.
    private func maskedText(_ start: Int, _ end: Int) -> String {
        var out: [UInt16] = []
        out.reserveCapacity(end - start)
        var index = start
        while index < end {
            if !masked[index] { out.append(units[index]) }
            index += 1
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// The source over `[start, end)` verbatim, excised spans included.
    private func rawText(_ start: Int, _ end: Int) -> String {
        String(decoding: units[start..<end], as: UTF16.self)
    }

    // MARK: Title page (§5.1)

    /// Returns the title page and the index of the first body line.
    ///
    /// A title page exists only when the first non-blank line matches
    /// `^[A-Za-z][A-Za-z ]*:` and its key is not `FADE IN`. The block runs to the first
    /// blank line; a block line with leading whitespace continues the previous entry.
    /// The body starts after the blank line that ends the block (offset 0 when there is
    /// no title page, end of text when the block runs to EOF).
    private mutating func parseTitlePage(effective: [String], trimmed: [String]) -> (TitlePage, Int) {
        let empty = TitlePage(entries: [], lines: [])
        var index = 0
        while index < lines.count, trimmed[index].isEmpty {
            index += 1
        }
        guard index < lines.count else { return (empty, 0) }
        guard let firstKey = Self.titlePageKey(of: effective[index]) else { return (empty, 0) }
        // `FADE IN:` is a transition/action line, never a key (§5.1).
        guard firstKey.trimmingCharacters(in: .whitespaces).uppercased() != "FADE IN" else {
            return (empty, 0)
        }

        var blockLines: [Int] = []
        var cursor = index
        while cursor < lines.count, !trimmed[cursor].isEmpty {
            blockLines.append(cursor)
            cursor += 1
        }

        var entries: [TitlePage.Entry] = []
        var keys: [String] = []
        var values: [[String]] = []
        var firstLines: [Int] = []
        var lastLines: [Int] = []

        for lineIndex in blockLines {
            let raw = effective[lineIndex]
            let isIndented = raw.first?.isWhitespace == true
            if !isIndented, let key = Self.titlePageKey(of: raw) {
                keys.append(key.trimmingCharacters(in: .whitespaces))
                let after = raw.dropFirst(key.count + 1).trimmingCharacters(in: .whitespacesAndNewlines)
                values.append(after.isEmpty ? [] : [after])
                firstLines.append(lineIndex)
                lastLines.append(lineIndex)
            } else if !keys.isEmpty {
                values[values.count - 1].append(raw.trimmingCharacters(in: .whitespacesAndNewlines))
                lastLines[lastLines.count - 1] = lineIndex
            }
        }
        for position in keys.indices {
            entries.append(
                TitlePage.Entry(
                    key: keys[position],
                    value: values[position].joined(separator: "\n"),
                    range: UTF16Range(start: lines[firstLines[position]].start, end: lines[lastLines[position]].end)
                )
            )
        }

        let verbatim = blockLines.map { effective[$0] }
        // Skip exactly the one blank line that ends the block.
        let bodyStartLine = (blockLines.last ?? index) + 2
        return (TitlePage(entries: entries, lines: verbatim), min(bodyStartLine, lines.count))
    }

    /// The `^[A-Za-z][A-Za-z ]*` key of a title-page line, or `nil` when the line is not
    /// a key line. The returned key keeps its authored spacing; the caller trims it.
    private static func titlePageKey(of line: String) -> String? {
        guard let first = line.first, first.isASCII, first.isLetter else { return nil }
        var key = ""
        for character in line {
            if character == ":" { return key }
            guard character == " " || (character.isASCII && character.isLetter) else { return nil }
            key.append(character)
        }
        return nil
    }

    // MARK: Notes and boneyard (§5.1)

    /// Excises every `[[ ]]` and `/* */` span in the document, before any
    /// classification — title page included, so a note or boneyard is never part of a
    /// title-page value or of `TitlePage.lines`.
    private mutating func excise() {
        let slash: UInt16 = 0x2F, star: UInt16 = 0x2A, bracket: UInt16 = 0x5B, closeBracket: UInt16 = 0x5D
        var index = 0
        while index + 1 < units.count {
            let isBoneyard = units[index] == slash && units[index + 1] == star
            let isNote = units[index] == bracket && units[index + 1] == bracket
            guard isBoneyard || isNote else {
                index += 1
                continue
            }
            let closeFirst: UInt16 = isBoneyard ? star : closeBracket
            let closeSecond: UInt16 = isBoneyard ? slash : closeBracket

            var scan = index + 2
            var end = units.count
            var terminated = false
            while scan + 1 < units.count {
                if units[scan] == closeFirst && units[scan + 1] == closeSecond {
                    end = scan + 2
                    terminated = true
                    break
                }
                scan += 1
            }

            excisions.append(Excision(start: index, end: end, kind: isBoneyard ? .boneyard : .note))
            for position in index..<end { masked[position] = true }
            if !terminated {
                warnings.append(
                    ParseWarning(
                        code: isBoneyard ? .unterminatedBoneyard : .unterminatedNote,
                        message: isBoneyard
                            ? "Unterminated boneyard; it runs to the end of the document."
                            : "Unterminated note; it runs to the end of the document.",
                        range: UTF16Range(start: index, end: end)
                    )
                )
            }
            index = end
        }
    }

    /// Per-line text with excisions removed, plus its trimmed form.
    private func effectiveLineTexts() -> ([String], [String]) {
        var effective: [String] = []
        var trimmed: [String] = []
        effective.reserveCapacity(lines.count)
        trimmed.reserveCapacity(lines.count)
        for line in lines {
            let text = maskedText(line.start, line.end)
            effective.append(text)
            trimmed.append(text.trimmingCharacters(in: .whitespaces))
        }
        return (effective, trimmed)
    }

    // MARK: Line walk (§5.1)

    private func classify(from bodyStartLine: Int, effective: [String], trimmed: [String]) -> Classification {
        var result = Classification()
        let lineCount = lines.count
        guard bodyStartLine < lineCount else { return result }

        func isBlank(_ index: Int) -> Bool {
            index < bodyStartLine || index >= lineCount || trimmed[index].isEmpty
        }
        // The body always begins after a blank line or at the start of the file, so the
        // first body line satisfies every "preceded by a blank line" rule.
        func previousIsBlank(_ index: Int) -> Bool { index == bodyStartLine || isBlank(index - 1) }
        func nextIsBlank(_ index: Int) -> Bool { index + 1 >= lineCount || isBlank(index + 1) }

        func element(_ kind: ElementKind, _ first: Int, _ last: Int, _ text: String) -> Pending {
            Pending(kind: kind, start: lines[first].start, end: lines[last].end, text: text)
        }

        var index = bodyStartLine
        while index < lineCount {
            let line = trimmed[index]
            if line.isEmpty {
                index += 1
                continue
            }

            if let marker = FountainLineClassifier.marker(in: line) {
                switch marker {
                case let .section(depth, title):
                    result.elements.append(element(.section, index, index, title))
                    result.sections.append((start: lines[index].start, depth: depth, title: title))
                case let .pageBreak(text):
                    result.elements.append(element(.pageBreak, index, index, text))
                case let .synopsis(text):
                    result.elements.append(element(.synopsis, index, index, text))
                case .forcedHeading:
                    result.elements.append(element(.sceneHeading, index, index, effective[index]))
                    result.headings.append((lineIndex: index, parsed: HeadingParser.parse(line)))
                case let .centered(text):
                    result.elements.append(element(.centered, index, index, text))
                case let .forcedTransition(text):
                    result.elements.append(element(.transition, index, index, text))
                case let .lyric(text):
                    result.elements.append(element(.lyric, index, index, text))
                case .forcedCue:
                    result.elements.append(element(.character, index, index, effective[index]))
                    appendCue(line: line, lineIndex: index, into: &result)
                    index = consumeDialogue(after: index, trimmed: trimmed, effective: effective,
                                            lineCount: lineCount, into: &result)
                    continue
                }
                index += 1
                continue
            }

            if previousIsBlank(index), FountainLineClassifier.isPrefixedHeading(line) {
                result.elements.append(element(.sceneHeading, index, index, effective[index]))
                result.headings.append((lineIndex: index, parsed: HeadingParser.parse(line)))
                index += 1
                continue
            }

            if previousIsBlank(index), nextIsBlank(index), FountainLineClassifier.isTransitionCandidate(line) {
                result.elements.append(element(.transition, index, index, line))
                index += 1
                continue
            }

            if previousIsBlank(index), !nextIsBlank(index), FountainLineClassifier.isCueCandidate(line) {
                result.elements.append(element(.character, index, index, effective[index]))
                appendCue(line: line, lineIndex: index, into: &result)
                index = consumeDialogue(after: index, trimmed: trimmed, effective: effective,
                                        lineCount: lineCount, into: &result)
                continue
            }

            // Action: every following non-blank line that does not itself start a
            // marker syntax joins this element.
            var last = index
            while last + 1 < lineCount,
                  !trimmed[last + 1].isEmpty,
                  FountainLineClassifier.marker(in: trimmed[last + 1]) == nil {
                last += 1
            }
            let text = effective[index...last].joined(separator: "\n")
            result.elements.append(element(.action, index, last, text))
            index = last + 1
        }
        return result
    }

    private func appendCue(line: String, lineIndex: Int, into result: inout Classification) {
        let normalized = CueNormalizer.normalize(line)
        result.cues.append(
            ParsedCue(
                raw: line,
                normalized: normalized.name,
                extensions: normalized.extensions,
                range: UTF16Range(start: lines[lineIndex].start, end: lines[lineIndex].end),
                isDual: line.hasSuffix("^")
            )
        )
    }

    /// Consumes the dialogue block after a cue and returns the next unconsumed line.
    private func consumeDialogue(
        after cueLine: Int,
        trimmed: [String],
        effective: [String],
        lineCount: Int,
        into result: inout Classification
    ) -> Int {
        var index = cueLine + 1
        while index < lineCount, !trimmed[index].isEmpty {
            if FountainLineClassifier.isParenthetical(trimmed[index]) {
                result.elements.append(
                    Pending(kind: .parenthetical, start: lines[index].start, end: lines[index].end,
                            text: effective[index])
                )
                index += 1
                continue
            }
            // A marker syntax ends the dialogue block and returns to the main walk.
            if FountainLineClassifier.marker(in: trimmed[index]) != nil { return index }
            var last = index
            while last + 1 < lineCount,
                  !trimmed[last + 1].isEmpty,
                  !FountainLineClassifier.isParenthetical(trimmed[last + 1]),
                  FountainLineClassifier.marker(in: trimmed[last + 1]) == nil {
                last += 1
            }
            result.elements.append(
                Pending(kind: .dialogue, start: lines[index].start, end: lines[last].end,
                        text: effective[index...last].joined(separator: "\n"))
            )
            index = last + 1
        }
        return index
    }

    // MARK: Sequences (§5.2)

    private func buildSequences(from sections: [(start: Int, depth: Int, title: String)]) -> [ParsedSequence] {
        sections.enumerated().map { position, section in
            var end = units.count
            var next = position + 1
            while next < sections.count {
                if sections[next].depth <= section.depth {
                    end = sections[next].start
                    break
                }
                next += 1
            }
            return ParsedSequence(
                ordinal: position + 1,
                title: section.title,
                depth: section.depth,
                range: UTF16Range(start: section.start, end: end)
            )
        }
    }

    // MARK: Scenes (§5.2, §5.3)

    private mutating func buildScenes(
        bodyStart: Int,
        sequences: [ParsedSequence],
        classification: Classification
    ) -> [ParsedScene] {
        struct Span {
            let ordinal: Int
            /// `nil` for the preamble and for the `UNTITLED` fallback.
            let heading: ParsedHeading?
            /// Used when `heading` is `nil`: `""` for the preamble, `UNTITLED` for the
            /// §5.3 fallback scene.
            let fallbackHeading: String
            let start: Int
            let end: Int
        }

        var spans: [Span] = []
        let headings = classification.headings

        if headings.isEmpty {
            // §5.3: a document always has at least one scene.
            let isEmptyBody = classification.elements.isEmpty && excisions.isEmpty
            warnings.append(
                ParseWarning(
                    code: .noSceneHeadings,
                    message: "No scene headings; the whole body is one UNTITLED scene.",
                    range: nil
                )
            )
            if isEmptyBody {
                warnings.append(
                    ParseWarning(code: .emptyDocument, message: "The document body is empty.", range: nil)
                )
            }
            // The fallback scene always spans the whole body, `[bodyStart, end of text)`.
            // For a truly empty body those two offsets coincide, so an empty range is a
            // consequence of the body, never a special case.
            spans = [Span(ordinal: 1, heading: nil, fallbackHeading: "UNTITLED",
                          start: bodyStart, end: units.count)]
        } else {
            let firstHeadingStart = lines[headings[0].lineIndex].start
            let preambleKinds: Set<ElementKind> = [.action, .dialogue, .centered, .lyric]
            let preambleQualifies = classification.elements.contains {
                $0.start >= bodyStart && $0.start < firstHeadingStart && preambleKinds.contains($0.kind)
            }
            if preambleQualifies {
                spans.append(Span(ordinal: 0, heading: nil, fallbackHeading: "",
                                  start: bodyStart, end: firstHeadingStart))
            }
            for (position, heading) in headings.enumerated() {
                let start = lines[heading.lineIndex].start
                let end = position + 1 < headings.count
                    ? lines[headings[position + 1].lineIndex].start
                    : units.count
                spans.append(Span(ordinal: position + 1, heading: heading.parsed,
                                  fallbackHeading: "", start: start, end: end))
            }
            warnDuplicateSceneNumbers(headings)
        }

        var scenes: [ParsedScene] = []
        var elementCursor = 0
        var cueCursor = 0
        let orderedElements = classification.elements
        let orderedCues = classification.cues

        for span in spans {
            var items: [Pending] = []
            while elementCursor < orderedElements.count, orderedElements[elementCursor].start < span.start {
                elementCursor += 1
            }
            while elementCursor < orderedElements.count, orderedElements[elementCursor].start < span.end {
                items.append(orderedElements[elementCursor])
                elementCursor += 1
            }
            for excision in excisions where excision.start < span.end && excision.end > span.start {
                let start = max(excision.start, span.start)
                let end = min(excision.end, span.end)
                let clipped = Pending(kind: excision.kind, start: start, end: end, text: rawText(start, end))
                // Ties put the excision first: its markers precede the element's text.
                var insertion = items.firstIndex { $0.start >= start } ?? items.count
                // ...except against the scene's own heading, which always stays first:
                // a boneyard that ends on the heading line (so the heading survives
                // excision) would otherwise displace it.
                if insertion == 0, let first = items.first, first.kind == .sceneHeading, first.start == start {
                    insertion = 1
                }
                items.insert(clipped, at: insertion)
            }

            while cueCursor < orderedCues.count, orderedCues[cueCursor].range.start < span.start {
                cueCursor += 1
            }
            var sceneCues: [ParsedCue] = []
            while cueCursor < orderedCues.count, orderedCues[cueCursor].range.start < span.end {
                sceneCues.append(orderedCues[cueCursor])
                cueCursor += 1
            }

            // §5.2, and the rule is LOCAL: look only at the sections that start at or
            // before this scene's heading, take the shallowest depth among *those*, and
            // pick the most recent section at that depth. A deeper section never
            // reassigns a scene, and a section appended later in the file can never
            // change an earlier scene's owner.
            let candidates = sequences.filter { $0.range.start <= span.start }
            var sequenceOrdinal: Int?
            if let shallowest = candidates.map(\.depth).min() {
                sequenceOrdinal = candidates.last { $0.depth == shallowest }?.ordinal
            }

            for cue in sceneCues where cue.isDual {
                let hasPrimary = items.contains { $0.kind == .character && $0.start < cue.range.start }
                if !hasPrimary {
                    warnings.append(
                        ParseWarning(
                            code: .dualDialogueWithoutPrimary,
                            message: "Dual-dialogue cue with no preceding dialogue block in the scene.",
                            range: cue.range
                        )
                    )
                }
            }

            let heading = span.heading
            scenes.append(
                ParsedScene(
                    ordinal: span.ordinal,
                    heading: heading?.heading ?? span.fallbackHeading,
                    intExt: heading?.intExt ?? .unknown,
                    locationText: heading?.locationText ?? "",
                    timeOfDay: heading?.timeOfDay ?? "",
                    sceneNumber: heading?.sceneNumber,
                    sequenceOrdinal: sequenceOrdinal,
                    range: UTF16Range(start: span.start, end: span.end),
                    elements: items.map { ParsedElement(kind: $0.kind, range: UTF16Range(start: $0.start, end: $0.end), text: $0.text) },
                    cues: sceneCues,
                    isOmitted: heading?.isOmitted ?? false
                )
            )
        }
        return scenes
    }

    private mutating func warnDuplicateSceneNumbers(_ headings: [(lineIndex: Int, parsed: ParsedHeading)]) {
        var seen: Set<String> = []
        for heading in headings {
            guard let number = heading.parsed.sceneNumber else { continue }
            let key = number.uppercased()
            if seen.contains(key) {
                warnings.append(
                    ParseWarning(
                        code: .duplicateSceneNumber,
                        message: "Duplicate scene number #\(number)#.",
                        range: UTF16Range(start: lines[heading.lineIndex].start, end: lines[heading.lineIndex].end)
                    )
                )
            } else {
                seen.insert(key)
            }
        }
    }

    // MARK: Warnings

    /// Document order by range; warnings without a range (the document-level ones) keep
    /// their emission order at the end. The sort is stable.
    private func sortedWarnings() -> [ParseWarning] {
        warnings.enumerated()
            .sorted { left, right in
                let leftStart = left.element.range?.start ?? Int.max
                let rightStart = right.element.range?.start ?? Int.max
                if leftStart != rightStart { return leftStart < rightStart }
                return left.offset < right.offset
            }
            .map(\.element)
    }
}
