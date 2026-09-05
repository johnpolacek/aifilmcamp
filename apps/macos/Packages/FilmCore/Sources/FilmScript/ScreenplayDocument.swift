import Foundation

// The value types of the deterministic parsing contract (PHASE1_DESIGN §5.1–§5.3,
// Plan 002 "Contracts (normative)"). Every type here is a frozen public contract:
// names, cases, raw values, stored properties, and their order are load-bearing for
// stable encoding and FilmCore's import mapper.
//
// `FilmScript` has no dependencies (§3.1). Foundation is used internally only and the
// public API is limited to `String`, `Data`, and `URL` among Foundation types.

// MARK: - Value enums

/// The source format a `ScreenplayDocument` was produced from (§5.1, §5.4, §5.4a).
public enum ScreenplayFormat: String, Codable, Sendable {
    case fountain
    case fdx
    case text
    case pdf
}

/// Interior/exterior classification derived from a heading prefix (§5.2).
///
/// `EST.` maps to `.ext`; `I/E`, `INT./EXT.`, and `INT/EXT` map to `.intExt`.
public enum IntExt: String, Codable, Sendable {
    case int
    case ext
    case intExt = "int_ext"
    case unknown
}

/// The Fountain element kinds the parser recognizes (§5.1).
public enum ElementKind: String, Codable, Sendable {
    case sceneHeading
    case action
    case character
    case parenthetical
    case dialogue
    case transition
    case centered
    case section
    case synopsis
    case note
    case boneyard
    case pageBreak
    case lyric
}

/// Structural warnings the parser reports without failing the import (§5.3, §5.4, §5.4a).
///
/// Existing raw values are persisted encoding contracts and must remain stable.
public enum WarningCode: String, Codable, Sendable {
    case noSceneHeadings
    case emptyDocument
    case unterminatedBoneyard
    case unterminatedNote
    case duplicateSceneNumber
    case dualDialogueWithoutPrimary
    case unsupportedParagraphType
    /// PDF only: at least one line sat at a margin no calibrated cluster covers, so it
    /// was rendered as action. Raised **once per document**, never once per line (§5.4a).
    case unclassifiedMargin
    /// PDF only: side-by-side dialogue columns were found and rendered sequentially,
    /// because column interleaving is not reconstructible from reading order alone.
    /// Raised **once per document** (§5.4a).
    case dualDialogueColumnsDetected
}

// MARK: - Ranges

/// A half-open UTF-16 range into `ScreenplayDocument.sourceText` (§3.3).
///
/// Offsets are always computed after `TextNormalization.normalize`.
public struct UTF16Range: Codable, Equatable, Hashable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

// MARK: - Document

/// The whole parse result: normalized source plus everything derived from it (§5.1–§5.3).
public struct ScreenplayDocument: Codable, Equatable, Sendable {
    public let format: ScreenplayFormat
    /// Always the normalized text; every range in this document indexes into it.
    public let sourceText: String
    public let titlePage: TitlePage
    /// `#` sections in document order; may be empty.
    public let sequences: [ParsedSequence]
    /// Optional scene 0 (preamble), then 1...n.
    public let scenes: [ParsedScene]
    public let warnings: [ParseWarning]

    public init(
        format: ScreenplayFormat,
        sourceText: String,
        titlePage: TitlePage,
        sequences: [ParsedSequence],
        scenes: [ParsedScene],
        warnings: [ParseWarning]
    ) {
        self.format = format
        self.sourceText = sourceText
        self.titlePage = titlePage
        self.sequences = sequences
        self.scenes = scenes
        self.warnings = warnings
    }
}

/// The Fountain title-page block (§5.1). FDX populates `lines` only.
public struct TitlePage: Codable, Equatable, Sendable {
    /// Fountain key/value pairs in document order; always empty for FDX.
    public let entries: [Entry]
    /// The block's non-blank source lines verbatim, in order (continuation lines separate).
    public let lines: [String]

    public init(entries: [Entry], lines: [String]) {
        self.entries = entries
        self.lines = lines
    }

    /// One title-page key and its value; `range` covers the key line through its last
    /// continuation line. Non-optional because FDX simply has no entries.
    public struct Entry: Codable, Equatable, Sendable {
        public let key: String
        public let value: String
        public let range: UTF16Range

        public init(key: String, value: String, range: UTF16Range) {
            self.key = key
            self.value = value
            self.range = range
        }
    }
}

/// A `#` section (§5.2). `ordinal` is contiguous from 1 across *all* depths.
public struct ParsedSequence: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let title: String
    /// Count of leading `#` characters: `#` = 1, `##` = 2, ...
    public let depth: Int
    public let range: UTF16Range

    public init(ordinal: Int, title: String, depth: Int, range: UTF16Range) {
        self.ordinal = ordinal
        self.title = title
        self.depth = depth
        self.range = range
    }
}

/// One scene (§5.2). Ordinal 0 is the preamble; 1...n follow in document order.
public struct ParsedScene: Codable, Equatable, Sendable {
    public let ordinal: Int
    /// The heading text with the forcing `.` and any `#12A#` number removed.
    public let heading: String
    public let intExt: IntExt
    public let locationText: String
    /// The authored time-of-day segment, or `""` when absent.
    public let timeOfDay: String
    /// The author's `#12A#` number; never used for ordering.
    public let sceneNumber: String?
    public let sequenceOrdinal: Int?
    public let range: UTF16Range
    public let elements: [ParsedElement]
    /// EVERY cue occurrence in document order — never deduplicated (§5.3).
    public let cues: [ParsedCue]
    public let isOmitted: Bool

    public init(
        ordinal: Int,
        heading: String,
        intExt: IntExt,
        locationText: String,
        timeOfDay: String,
        sceneNumber: String?,
        sequenceOrdinal: Int?,
        range: UTF16Range,
        elements: [ParsedElement],
        cues: [ParsedCue],
        isOmitted: Bool
    ) {
        self.ordinal = ordinal
        self.heading = heading
        self.intExt = intExt
        self.locationText = locationText
        self.timeOfDay = timeOfDay
        self.sceneNumber = sceneNumber
        self.sequenceOrdinal = sequenceOrdinal
        self.range = range
        self.elements = elements
        self.cues = cues
        self.isOmitted = isOmitted
    }
}

/// One classified line block inside a scene (§5.1).
public struct ParsedElement: Codable, Equatable, Sendable {
    public let kind: ElementKind
    public let range: UTF16Range
    public let text: String

    public init(kind: ElementKind, range: UTF16Range, text: String) {
        self.kind = kind
        self.range = range
        self.text = text
    }
}

/// One character-cue occurrence (§5.1, §5.3).
public struct ParsedCue: Codable, Equatable, Sendable {
    public let raw: String
    public let normalized: String
    public let extensions: [String]
    public let range: UTF16Range
    public let isDual: Bool

    public init(raw: String, normalized: String, extensions: [String], range: UTF16Range, isDual: Bool) {
        self.raw = raw
        self.normalized = normalized
        self.extensions = extensions
        self.range = range
        self.isDual = isDual
    }
}

/// The decomposition of a single heading line (§5.2), as produced by `HeadingParser`.
public struct ParsedHeading: Codable, Equatable, Sendable {
    public let heading: String
    public let intExt: IntExt
    public let locationText: String
    public let timeOfDay: String
    public let sceneNumber: String?
    public let isOmitted: Bool

    public init(
        heading: String,
        intExt: IntExt,
        locationText: String,
        timeOfDay: String,
        sceneNumber: String?,
        isOmitted: Bool
    ) {
        self.heading = heading
        self.intExt = intExt
        self.locationText = locationText
        self.timeOfDay = timeOfDay
        self.sceneNumber = sceneNumber
        self.isOmitted = isOmitted
    }
}

/// A non-fatal structural warning (§5.3).
public struct ParseWarning: Codable, Equatable, Sendable {
    public let code: WarningCode
    public let message: String
    public let range: UTF16Range?

    public init(code: WarningCode, message: String, range: UTF16Range?) {
        self.code = code
        self.message = message
        self.range = range
    }
}

// MARK: - Errors

/// Failures raised while loading a screenplay file (§5.1).
public enum ScreenplayLoadError: Error, Equatable, Sendable {
    case unreadable
    case unsupportedEncoding
}

/// Failures raised while reading Final Draft XML (§5.4).
public enum FDXReadError: Error, Equatable, Sendable {
    case malformed(line: Int, column: Int)
}

/// Failures raised while reading a PDF (§5.4a).
///
/// Never raw-valued: these are conditions the app explains in its own words, and none of
/// them is ever written to a database column.
public enum PDFReadError: Error, Equatable, LocalizedError, Sendable {
    /// The bytes are not a PDF, or are damaged past the point PDFKit will open them.
    case unreadable
    /// The document is locked or encrypted; Film Camp never asks for or stores a password.
    case encrypted
    /// Under 200 characters of extractable text — a scanned page image. Refused, never
    /// OCR'd (§11).
    ///
    /// The two counts exist so the refusal can report **how** the file failed ("no
    /// selectable text in 0 of 91 pages") rather than only that it did. Whether OCR is
    /// ever worth building is a question about how often real material lands here, and a
    /// refusal that reports its own shape is the only honest way to answer it (§5.4a).
    /// `pagesWithText` counts pages that yielded at least one non-empty line, so a
    /// part-scanned document is distinguishable from a wholly scanned one.
    case noTextLayer(pagesTotal: Int, pagesWithText: Int)

    /// What the filmmaker is shown. It lives here, beside the diagnostics, because only
    /// this module knows the counts — the app is presentation and never parses (§3.1) —
    /// and because `ProjectStoreError` sets the precedent that a refusal owns its wording.
    ///
    /// `.noTextLayer` reports **its own shape**: the two counts are the whole point of the
    /// case, and a generic "this PDF could not be read" would throw away the one number
    /// that says how common scanned screenplays actually are.
    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "This file could not be opened as a PDF. It may be damaged, or it may not be a "
                + "PDF at all despite its name."
        case .encrypted:
            "This PDF is password-protected or restricts copying its text. AI Film Camp "
                + "never asks for or stores a PDF password — remove the protection in a PDF "
                + "app and import the unprotected copy."
        case let .noTextLayer(pagesTotal, pagesWithText):
            "Only \(pagesWithText) of \(pagesTotal) \(pagesTotal == 1 ? "page" : "pages") in "
                + "this PDF carry selectable text, so it looks like a scan rather than an "
                + "exported screenplay. AI Film Camp reads a PDF's text layer and never runs "
                + "text recognition — export a text-based PDF from the original, or import "
                + "the Fountain or Final Draft file instead."
        }
    }
}

// MARK: - Version

/// The parser contract version Plan 003 writes to `scripts.parser_version` (§5.5).
///
/// Any parsing change that can alter persisted results must bump this in the same commit.
/// The spelling is frozen: no `version`/`parserVersion` alias.
public enum FilmScriptVersion: Sendable {
    public static let parser: String = "1"
}
