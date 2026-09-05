import Foundation

/// Deterministic PDF geometry → Fountain rendering (PHASE1_DESIGN §5.4a).
///
/// PDF gets **no scene rules of its own**: the line list becomes Fountain text and
/// `FountainParser.parse(_:format: .pdf)` does the segmentation, so all four formats obey
/// one scene contract. This is `FDXRenderer`'s pattern applied to a format whose element
/// types are positional rather than declared — and that is the honest limitation (§3.2a):
/// cue, dialogue, parenthetical, and action are **inferred** from a left margin.
///
/// Same lines in → byte-identical text out, always. Nothing here reads the clock, the
/// environment, a dictionary's iteration order, or any global state; every place a
/// dictionary is walked is sorted first.
///
/// ## The pipeline, in order
///
/// 1. **Page furniture is dropped** (`isPageFurniture`) *before* calibration, because the
///    reconnaissance found page numbers at ~10% of all lines — comfortably above the 2%
///    cluster threshold — so leaving them in would invent a fifth margin.
/// 2. **Calibration** (`calibrate`) builds a 0.01-bucket histogram of left fractions,
///    grows clusters from every bucket holding ≥2% of the surviving lines, and assigns
///    each cluster to its nearest canonical anchor.
/// 3. **Blocks** (`blockMetrics`, `startsNewBlock`) reconstruct the blank lines the PDF
///    only encodes as vertical space.
/// 4. **Rendering** emits one line per `PDFLine`, separated by `FDXRenderer`'s exact
///    blank-line rule.
///
/// ## Blank-line rule
///
/// Identical to `FDXRenderer`'s, with a gap-derived *block* standing in for an FDX
/// paragraph: one blank line separates logical blocks, and **no** blank line ever appears
/// inside a `character → parenthetical → dialogue` run, so a cue is always followed by a
/// non-blank line and the run re-parses as dialogue. Lines inside one block join with a
/// single `\n`, which is what makes a three-line action paragraph render as one paragraph
/// instead of three.
///
/// ## Forcing markers
///
/// Forced `.`/`@`/`> ` markers are emitted **only when the line would not otherwise parse
/// as that element where it is rendered**. In practice a heading or transition the
/// geometry recognized is also block-delimited, so `.` and `> ` almost never appear; the
/// marker exists for the tightly set document that puts a heading inside a block, where
/// the alternative is silently losing a scene.
public enum PDFRenderer: Sendable {
    // MARK: - Public entry point

    /// Renders the extracted line list into Fountain text and its warnings.
    ///
    /// Unlike `FDXRenderer.render` this returns a **two**-element tuple, and not because
    /// PDF has no title page: §5.4a's title-page rule is resolved in `PDFReader`, which is
    /// the only place that knows where a page begins. By the time lines reach this
    /// function a recognized title page has already been lifted out, so every line here is
    /// body text to be margin-classified.
    public nonisolated static func render(
        _ lines: [PDFLine]
    ) -> (text: String, warnings: [ParseWarning]) {
        let body = lines.filter { !isPageFurniture($0) }
        guard !body.isEmpty else { return ("", []) }

        let calibration = calibrate(body)
        let metrics = blockMetrics(for: body)
        let dualIndex = dualColumnWarningIndex(body, metrics: metrics)

        var kinds: [RenderKind] = []
        var isUnclassified: [Bool] = []
        kinds.reserveCapacity(body.count)
        isUnclassified.reserveCapacity(body.count)
        for line in body {
            let margin = calibration.kind(for: line.leftFraction)
            isUnclassified.append(margin == nil)
            kinds.append(RenderKind(margin: margin, text: line.text))
        }

        var text = ""
        var inDialogueRun = false
        var unclassifiedRange: UTF16Range?
        var dualRange: UTF16Range?

        for index in body.indices {
            let line = body[index]
            let kind = kinds[index]
            let continuesRun = inDialogueRun && (kind == .parenthetical || kind == .dialogue)

            let separator: String
            if index == 0 {
                separator = ""
            } else if continuesRun {
                separator = "\n"
            } else if startsNewBlock(previous: body[index - 1], current: line, metrics: metrics) {
                separator = "\n\n"
            } else {
                separator = "\n"
            }
            text += separator
            let precededByBlank = index == 0 || separator == "\n\n"

            // Whether the *next* line will join this one with a bare `\n`. A cue is only a
            // cue when a non-blank line follows it, so this is what decides the `@`.
            let opensRun = kind == .character || continuesRun
            let followedWithoutBlank: Bool = {
                guard index + 1 < body.count else { return false }
                let next = kinds[index + 1]
                if opensRun, next == .parenthetical || next == .dialogue { return true }
                return !startsNewBlock(previous: line, current: body[index + 1], metrics: metrics)
            }()

            let start = text.utf16.count
            text += rendered(
                line: line,
                kind: kind,
                precededByBlank: precededByBlank,
                followedWithoutBlank: followedWithoutBlank
            )
            let range = UTF16Range(start: start, end: text.utf16.count)

            if isUnclassified[index], unclassifiedRange == nil { unclassifiedRange = range }
            if index == dualIndex { dualRange = range }

            inDialogueRun = opensRun
        }

        return (text, warnings(unclassified: unclassifiedRange, dual: dualRange))
    }

    // MARK: - Warnings (once per document, never once per line)

    /// Both §5.4a warnings are **document-level**: a screenplay whose parentheticals sit
    /// at an unusual margin would otherwise raise hundreds of identical warnings and bury
    /// everything else in the import sheet. Each carries the range of the **first** line
    /// that triggered it, so the app can take the filmmaker to an example.
    private static func warnings(unclassified: UTF16Range?, dual: UTF16Range?) -> [ParseWarning] {
        var found: [ParseWarning] = []
        if let unclassified {
            found.append(
                ParseWarning(
                    code: .unclassifiedMargin,
                    message: "Some lines sit at a margin this PDF does not use elsewhere; "
                        + "they were imported as action.",
                    range: unclassified
                )
            )
        }
        if let dual {
            found.append(
                ParseWarning(
                    code: .dualDialogueColumnsDetected,
                    message: "Side-by-side dialogue columns were found; they were imported "
                        + "one after the other, not side by side.",
                    range: dual
                )
            )
        }
        return found.enumerated()
            .sorted { left, right in
                let leftStart = left.element.range?.start ?? Int.max
                let rightStart = right.element.range?.start ?? Int.max
                if leftStart != rightStart { return leftStart < rightStart }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    // MARK: - Page furniture (§5.4a)

    /// Furniture is **two rules with different guards** (§5.4a), because the two kinds
    /// differ in how self-identifying they are.
    ///
    /// 1. **A `(CONTINUED)`/`(MORE)` marker is always dropped, wherever it sits.** No
    ///    screenplay has a line of body text that is only `(MORE)` or `CONTINUED:`, so the
    ///    text alone is proof. A positional guard here is not merely redundant, it is
    ///    wrong: measurement on real material puts these markers at 0.89–0.92 of page
    ///    height — just *above* the one-inch bottom margin — so a bottom-8% band misses
    ///    two of every three and leaks them into the dialogue that precedes them.
    /// 2. **A page number keeps both guards**: top or bottom 8% of the page **and** a left
    ///    fraction above `0.75`. A bare number is not self-identifying — a `12` at the
    ///    dialogue margin in body text is dialogue, and real material contains such lines
    ///    — so position is what separates a page number from a spoken one.
    ///
    /// **Nothing else is ever dropped**: a centered footer that is neither marker nor page
    /// number is kept, and an unrecognized line becomes action.
    static func isPageFurniture(_ line: PDFLine) -> Bool {
        if isContinuedOrMore(line.text) { return true }
        guard line.topFraction < 0.08 || line.bottomFraction > 0.92 else { return false }
        return isPageNumber(line.text) && line.leftFraction > 0.75
    }

    /// `^\(?(CONTINUED|MORE)\)?:?$`, case-insensitively, hand-rolled so `FilmScript` keeps
    /// its regex-free line recognition.
    private static func isContinuedOrMore(_ text: String) -> Bool {
        var body = Substring(text)
        if body.hasPrefix("(") { body = body.dropFirst() }
        if body.hasSuffix(":") { body = body.dropLast() }
        if body.hasSuffix(")") { body = body.dropLast() }
        let upper = body.uppercased()
        return upper == "CONTINUED" || upper == "MORE"
    }

    /// `^\d+\.?$` over ASCII digits.
    private static func isPageNumber(_ text: String) -> Bool {
        var body = Substring(text)
        if body.hasSuffix(".") { body = body.dropLast() }
        guard !body.isEmpty else { return false }
        return body.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: - Canonical anchors (§5.4a)

    /// What a calibrated margin means. These four, in ascending order, are the whole
    /// element vocabulary geometry can supply; a fifth would be a design change (§5.4a),
    /// not a refactor.
    enum MarginKind: String, Equatable, Sendable {
        case action
        case dialogue
        case parenthetical
        case character
    }

    struct Anchor: Equatable, Sendable {
        let kind: MarginKind
        /// Left fraction on an 8.5" page.
        let position: Double
    }

    /// Ascending by `position`; the assignment rules below rely on that order.
    static let anchors: [Anchor] = [
        Anchor(kind: .action, position: 0.176),        // 1.5"
        Anchor(kind: .dialogue, position: 0.294),      // 2.5"
        Anchor(kind: .parenthetical, position: 0.353), // 3.0"
        Anchor(kind: .character, position: 0.435),     // 3.7"
    ]

    /// Histogram bucket width (§5.4a).
    static let bucketWidth = 0.01
    /// The share of surviving lines a bucket needs to seed a cluster (§5.4a).
    static let clusterShare = 0.02

    /// The 0.01 bucket a left fraction falls in. Boundary values land wherever binary
    /// floating point puts them, which is stable for identical input bytes — and harmless,
    /// because a cluster absorbs its immediate neighbours anyway.
    static func bucket(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded(.down))
    }

    // MARK: - Calibration (§5.4a)

    /// One calibrated margin: a contiguous bucket range, the lines in it, its
    /// line-count-weighted mean position, and the anchor it won (or `nil`).
    struct Cluster: Equatable, Sendable {
        let buckets: ClosedRange<Int>
        let lineCount: Int
        let position: Double
        let kind: MarginKind?
    }

    /// The document's own margin vocabulary, recovered from its own lines.
    struct Calibration: Equatable, Sendable {
        /// Ascending by `position`.
        let clusters: [Cluster]
        let kindsByBucket: [Int: MarginKind]

        /// `nil` for a line in no cluster, and for a cluster that won no anchor — both
        /// render as action and both feed the single `unclassifiedMargin` warning.
        func kind(for leftFraction: Double) -> MarginKind? {
            kindsByBucket[bucket(leftFraction)]
        }
    }

    /// Builds the histogram, grows the clusters, and assigns the anchors.
    ///
    /// A **cluster** is every bucket holding at least `clusterShare` of the lines, grown
    /// by exactly one bucket on each side and then merged where those grown ranges touch.
    /// Growing by one — rather than letting neighbours chain — is what keeps "a margin
    /// that straddles a bucket edge is one cluster and not two" from swallowing the whole
    /// histogram in a document with many small margins.
    static func calibrate(_ lines: [PDFLine]) -> Calibration {
        guard !lines.isEmpty else { return Calibration(clusters: [], kindsByBucket: [:]) }

        var counts: [Int: Int] = [:]
        var sums: [Int: Double] = [:]
        for line in lines {
            let index = bucket(line.leftFraction)
            counts[index, default: 0] += 1
            sums[index, default: 0] += line.leftFraction
        }

        let threshold = clusterShare * Double(lines.count)
        var members: Set<Int> = []
        for index in counts.keys.sorted() where Double(counts[index] ?? 0) >= threshold {
            members.insert(index - 1)
            members.insert(index)
            members.insert(index + 1)
        }

        var ranges: [ClosedRange<Int>] = []
        for index in members.sorted() {
            if let last = ranges.last, last.upperBound + 1 == index {
                ranges[ranges.count - 1] = last.lowerBound...index
            } else {
                ranges.append(index...index)
            }
        }

        var raw: [(buckets: ClosedRange<Int>, lineCount: Int, position: Double)] = []
        for range in ranges {
            var lineCount = 0
            var sum = 0.0
            for index in range {
                lineCount += counts[index] ?? 0
                sum += sums[index] ?? 0
            }
            guard lineCount > 0 else { continue }
            raw.append((range, lineCount, sum / Double(lineCount)))
        }
        raw.sort {
            $0.position != $1.position ? $0.position < $1.position
                : $0.buckets.lowerBound < $1.buckets.lowerBound
        }

        let assigned = assign(raw.map(\.position))
        var clusters: [Cluster] = []
        var kindsByBucket: [Int: MarginKind] = [:]
        for (index, entry) in raw.enumerated() {
            let kind = assigned[index]
            clusters.append(
                Cluster(buckets: entry.buckets, lineCount: entry.lineCount, position: entry.position, kind: kind)
            )
            guard let kind else { continue }
            for slot in entry.buckets { kindsByBucket[slot] = kind }
        }
        return Calibration(clusters: clusters, kindsByBucket: kindsByBucket)
    }

    /// Nearest-anchor assignment with the §5.4a collision rule.
    ///
    /// `positions` must be ascending. Each cluster proposes its nearest anchor; where
    /// several propose the same one the closest keeps it (an exact distance tie goes to
    /// the lower position); every loser then falls to the next **unclaimed** anchor in
    /// ascending margin order, scanning upward from the anchor it lost. A cluster with no
    /// anchor left — a document with more margins than the four the vocabulary has —
    /// renders as action and raises `unclassifiedMargin`, exactly like a line in no
    /// cluster at all. §5.4a supplies no fifth anchor and this renderer invents none.
    static func assign(_ positions: [Double]) -> [MarginKind?] {
        var result = [MarginKind?](repeating: nil, count: positions.count)
        guard !positions.isEmpty else { return result }

        let proposals = positions.map { nearestAnchorIndex(for: $0) }
        var claimed = [Bool](repeating: false, count: anchors.count)

        for anchorIndex in anchors.indices {
            var best: Int?
            for cluster in positions.indices where proposals[cluster] == anchorIndex {
                guard let current = best else { best = cluster; continue }
                let candidate = abs(positions[cluster] - anchors[anchorIndex].position)
                let incumbent = abs(positions[current] - anchors[anchorIndex].position)
                if candidate < incumbent || (candidate == incumbent && positions[cluster] < positions[current]) {
                    best = cluster
                }
            }
            guard let best else { continue }
            claimed[anchorIndex] = true
            result[best] = anchors[anchorIndex].kind
        }

        for cluster in positions.indices where result[cluster] == nil {
            var anchorIndex = proposals[cluster] + 1
            while anchorIndex < anchors.count, claimed[anchorIndex] { anchorIndex += 1 }
            guard anchorIndex < anchors.count else { continue }
            claimed[anchorIndex] = true
            result[cluster] = anchors[anchorIndex].kind
        }
        return result
    }

    /// Ties resolve to the lower anchor, which is "ascending margin order" applied to the
    /// proposal itself.
    static func nearestAnchorIndex(for position: Double) -> Int {
        var best = 0
        var bestDistance = abs(position - anchors[0].position)
        for index in 1..<anchors.count {
            let distance = abs(position - anchors[index].position)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    // MARK: - Blocks (§5.4a)

    /// The two document-wide modes the block rule is built on.
    struct BlockMetrics: Equatable, Sendable {
        /// The single-spaced baseline: the modal **positive** intra-page gap. Recorded
        /// because §5.4a names it; the threshold below is stated in line heights.
        let modalPositiveGap: Double?
        let modalLineHeight: Double?
        /// Half the modal line height, or `nil` when the document is too short to have a
        /// mode — then every line is its own block.
        let blockThreshold: Double?
    }

    /// Measures the document's modal gap and modal line height, both bucketed to three
    /// decimal places.
    ///
    /// "Positive" is load-bearing. In the reconnaissance document 1,759 same-block
    /// continuations report a gap of about `-1e-5` (PDFKit's line bounds bleed into each
    /// other by a rounding error) while genuine blank lines report `0.015`, so including
    /// the non-positive gaps would make the mode zero and split nothing. Cross-page gaps
    /// are never measured at all — a page boundary always starts a new block.
    static func blockMetrics(for lines: [PDFLine]) -> BlockMetrics {
        guard lines.count >= 2 else {
            return BlockMetrics(modalPositiveGap: nil, modalLineHeight: nil, blockThreshold: nil)
        }
        var gaps: [Double] = []
        var heights: [Double] = []
        heights.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            heights.append(line.bottomFraction - line.topFraction)
            guard index > 0, lines[index - 1].pageIndex == line.pageIndex else { continue }
            let gap = line.topFraction - lines[index - 1].bottomFraction
            if gap > 0 { gaps.append(gap) }
        }
        let modalHeight = mode(heights)
        return BlockMetrics(
            modalPositiveGap: mode(gaps),
            modalLineHeight: modalHeight,
            blockThreshold: modalHeight.map { $0 / 2 }
        )
    }

    /// Most frequent value after bucketing to three decimals; ties take the smaller value
    /// so the result never depends on dictionary order.
    static func mode(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        var counts: [Double: Int] = [:]
        for value in values { counts[((value * 1000).rounded()) / 1000, default: 0] += 1 }
        var best: (value: Double, count: Int)?
        for key in counts.keys.sorted() {
            let count = counts[key] ?? 0
            if best == nil || count > (best?.count ?? 0) { best = (key, count) }
        }
        return best?.value
    }

    /// A page boundary always breaks; otherwise a gap of at least half the modal line
    /// height does.
    static func startsNewBlock(previous: PDFLine, current: PDFLine, metrics: BlockMetrics) -> Bool {
        if current.pageIndex != previous.pageIndex { return true }
        guard let threshold = metrics.blockThreshold else { return true }
        return (current.topFraction - previous.bottomFraction) >= threshold
    }

    // MARK: - Dual dialogue columns (§5.4a)

    /// How many **consecutive** qualifying bands a real dual-dialogue block must span
    /// before the warning fires (§5.4a).
    ///
    /// Three, because a real block is a cue pair plus several dialogue lines stacked in
    /// the same region of one page. One isolated pair is an extraction artifact: on real
    /// material every such pair turned out to be a **single visual line that PDFKit split
    /// into two selections at a style-run change** — an action line whose last word is set
    /// in a different font returns as two selections sharing one baseline, separated by
    /// the width of the space between them, which satisfies "shares a vertical band" and
    /// "occupies disjoint horizontal ranges" perfectly. Scattered artifacts never stack,
    /// so requiring a *run* rather than a document-wide count is what separates them from
    /// a block.
    static let dualColumnBandRun = 3

    /// Document index of the first line of the first dual-dialogue block, or `nil`.
    ///
    /// Bands are built from vertical position and **not** from document order: PDFKit may
    /// return a page's two columns one after the other rather than interleaved by
    /// baseline, so consecutive-line grouping would put a cue and its facing cue in
    /// different bands and find nothing at all.
    ///
    /// "Shares a vertical band" is read as an overlap of at least **half the modal line
    /// height** rather than any overlap, and that threshold is not decoration: on real
    /// material a bare `overlap > 0` test fires on dozens of consecutive-line pairs whose
    /// bounds bleed into each other by about `1e-5` of the page — a cue at 3.7" followed
    /// by dialogue at 2.5" is horizontally disjoint. Half a line height separates the two
    /// populations by three orders of magnitude, and the quantity is the one §5.4a already
    /// defines for the block rule; no new signal is introduced.
    static func dualColumnWarningIndex(_ lines: [PDFLine], metrics: BlockMetrics) -> Int? {
        guard let height = metrics.modalLineHeight, height > 0 else { return nil }
        let minimumOverlap = height / 2

        var byPage: [Int: [Int]] = [:]
        for (index, line) in lines.enumerated() { byPage[line.pageIndex, default: []].append(index) }

        for page in byPage.keys.sorted() {
            var run: [Int] = []
            for band in bands(byPage[page] ?? [], lines: lines, minimumOverlap: minimumOverlap) {
                guard let start = firstDisjointLineIndex(in: band, lines: lines) else {
                    // A band with no facing pair ends the block; the run must be unbroken.
                    run = []
                    continue
                }
                run.append(start)
                if run.count >= dualColumnBandRun { return run[0] }
            }
        }
        return nil
    }

    /// Groups one page's line indices into vertical bands, ordered down the page.
    ///
    /// A line joins the open band when it overlaps that band's **first** member by at
    /// least `minimumOverlap`. Comparing against the first member rather than the last
    /// keeps a column of slightly drifting baselines from chaining into one giant band.
    static func bands(_ indices: [Int], lines: [PDFLine], minimumOverlap: Double) -> [[Int]] {
        let ordered = indices.sorted {
            lines[$0].topFraction != lines[$1].topFraction
                ? lines[$0].topFraction < lines[$1].topFraction
                : $0 < $1
        }
        var found: [[Int]] = []
        for index in ordered {
            if let open = found.last, let first = open.first,
               min(lines[index].bottomFraction, lines[first].bottomFraction)
                   - max(lines[index].topFraction, lines[first].topFraction) >= minimumOverlap {
                found[found.count - 1].append(index)
            } else {
                found.append([index])
            }
        }
        return found
    }

    /// The lower document index of the first horizontally disjoint pair in `band`, or
    /// `nil` when every line in the band overlaps every other horizontally.
    static func firstDisjointLineIndex(in band: [Int], lines: [PDFLine]) -> Int? {
        for first in band.indices {
            for second in (first + 1)..<band.count {
                let left = lines[band[first]]
                let right = lines[band[second]]
                if left.rightFraction < right.leftFraction || right.rightFraction < left.leftFraction {
                    return min(band[first], band[second])
                }
            }
        }
        return nil
    }

    // MARK: - One line

    /// What a line renders as. There is no geometric transition anchor — §5.4a supplies
    /// four — so a transition is recognized from the text of a line that renders as
    /// action, which is exactly how a right-aligned `CUT TO:` survives the round trip.
    enum RenderKind: Equatable, Sendable {
        case heading
        case action
        case character
        case parenthetical
        case dialogue
        case transition

        init(margin: MarginKind?, text: String) {
            switch margin {
            case .dialogue: self = .dialogue
            case .parenthetical: self = .parenthetical
            case .character: self = .character
            case .action, .none:
                if FountainLineClassifier.isPrefixedHeading(text) {
                    self = .heading
                } else if FountainLineClassifier.isTransitionCandidate(text) {
                    self = .transition
                } else {
                    self = .action
                }
            }
        }
    }

    private static func rendered(
        line: PDFLine,
        kind: RenderKind,
        precededByBlank: Bool,
        followedWithoutBlank: Bool
    ) -> String {
        let text = line.text
        switch kind {
        case .heading:
            // A prefixed heading already parses when a blank line precedes it. The dot is
            // only ever emitted for a heading the geometry found *inside* a block, where
            // the alternative is losing the scene entirely.
            return precededByBlank ? text : "." + text

        case .character:
            // `@` whenever the line would not parse as a cue where it lands: its own shape
            // disqualifies it, nothing precedes it as a blank line, or nothing follows it
            // to be dialogue.
            let parsesAsCue = FountainLineClassifier.isCueCandidate(text)
                && precededByBlank && followedWithoutBlank
            // No `^` is ever emitted: the renderer cannot tell which column is primary and
            // a guess would freeze a wrong `isDual` into persisted parser output (§5.4a).
            return parsesAsCue ? text : "@" + text

        case .parenthetical:
            // Some documents set a parenthetical without its parentheses; without them the
            // line reads as dialogue.
            return FountainLineClassifier.isParenthetical(text) ? text : "(" + text + ")"

        case .transition:
            let parsesAsTransition = precededByBlank && !followedWithoutBlank
            return parsesAsTransition ? text : "> " + text

        case .action, .dialogue:
            return text
        }
    }
}
