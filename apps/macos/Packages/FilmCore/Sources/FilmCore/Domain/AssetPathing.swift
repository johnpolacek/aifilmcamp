import Foundation
import ImageIO

/// Why an import was refused before a single byte was staged (PHASE2_DESIGN §4.1).
///
/// Every case **names the measured value**, because "that image is too big" is not an
/// answer a filmmaker can act on and "16,412 pixels wide, and the limit is 16,384" is.
public enum MediaImportError: Error, Equatable, LocalizedError, Sendable {
    /// The file's bytes do not begin with any of the five supported image signatures.
    case unsupportedMediaType(fileName: String)
    /// The bytes sniff as one supported type and the file name claims another — a `.jpg`
    /// that is really a PNG. Content decides; the extension is not evidence.
    case mediaTypeMismatch(fileName: String, declared: String, detected: String)
    /// Neither ImageIO nor the format's own header yielded pixel dimensions.
    case unreadableImageHeader(fileName: String)
    case fileTooLarge(fileName: String, byteCount: Int, limit: Int)
    case pixelDimensionTooLarge(fileName: String, width: Int, height: Int, limit: Int)
    case pixelCountTooLarge(fileName: String, pixelCount: Int, limit: Int)
    /// A zero-byte file, or one too short to hold a header.
    case emptyFile(fileName: String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedMediaType(fileName):
            "“\(fileName)” is not a PNG, JPEG, WebP, HEIC, or TIFF image."
        case let .mediaTypeMismatch(fileName, declared, detected):
            "“\(fileName)” is named as \(declared) but its contents are \(detected)."
        case let .unreadableImageHeader(fileName):
            "“\(fileName)” does not have a readable image header."
        case let .fileTooLarge(fileName, byteCount, limit):
            "“\(fileName)” is \(byteCount) bytes; the limit is \(limit) bytes."
        case let .pixelDimensionTooLarge(fileName, width, height, limit):
            "“\(fileName)” is \(width)×\(height) pixels; each side must be at most \(limit)."
        case let .pixelCountTooLarge(fileName, pixelCount, limit):
            "“\(fileName)” holds \(pixelCount) pixels; the limit is \(limit)."
        case let .emptyFile(fileName):
            "“\(fileName)” is empty."
        }
    }
}

/// PHASE2_DESIGN §4.1's import budget, as FilmCore constants.
///
/// The dimensions these bound are read from the image **header**, never from a decode, so a
/// decompression bomb — a small file whose header declares 100,000 × 100,000 — is refused
/// before any pixel is produced.
public enum MediaImportLimits: Sendable {
    /// 256 MB.
    public static let maximumByteCount = 256 * 1024 * 1024
    /// 16,384 on each side.
    public static let maximumPixelDimension = 16_384
    /// 128 megapixels decoded.
    public static let maximumPixelCount = 128_000_000

    /// Refuses an over-budget file, naming the measured value.
    static func check(byteCount: Int, fileName: String) throws {
        guard byteCount > 0 else { throw MediaImportError.emptyFile(fileName: fileName) }
        guard byteCount <= maximumByteCount else {
            throw MediaImportError.fileTooLarge(
                fileName: fileName, byteCount: byteCount, limit: maximumByteCount
            )
        }
    }

    /// Refuses over-budget **declared** dimensions, naming them.
    static func check(width: Int, height: Int, fileName: String) throws {
        guard width > 0, height > 0 else {
            throw MediaImportError.unreadableImageHeader(fileName: fileName)
        }
        guard width <= maximumPixelDimension, height <= maximumPixelDimension else {
            throw MediaImportError.pixelDimensionTooLarge(
                fileName: fileName, width: width, height: height, limit: maximumPixelDimension
            )
        }
        let pixels = width * height
        guard pixels <= maximumPixelCount else {
            throw MediaImportError.pixelCountTooLarge(
                fileName: fileName, pixelCount: pixels, limit: maximumPixelCount
            )
        }
    }
}

/// The five MVP image types and their magic signatures, in **one** place (§4.1; Plan 011's
/// maintenance note: Phase 3's generation import reuses them).
public enum ImageFormat: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case png
    case jpeg
    case webp
    case heic
    case tiff

    /// The extensions a file of this format may carry, lowercased.
    public var acceptedExtensions: [String] {
        switch self {
        case .png: ["png"]
        case .jpeg: ["jpg", "jpeg"]
        case .webp: ["webp"]
        case .heic: ["heic"]
        case .tiff: ["tiff", "tif"]
        }
    }

    /// Every extension the importer accepts, for an open panel's content-type list.
    public static var acceptedExtensions: [String] {
        allCases.flatMap(\.acceptedExtensions)
    }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .webp: "WebP"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        }
    }
}

/// §4.1's slug and destination rules, the magic-byte sniff, and the header-only dimension
/// read — the whole "where does this file go, and may it come in at all" surface.
///
/// **Slugs are path material, not identity.** They are computed once, at the moment a
/// version's destination is chosen; the stored `relative_path` is the truth afterwards, and
/// renaming an entity or a requirement never moves a file.
public enum AssetPathing: Sendable {

    // MARK: - Slugs

    /// §4.1's slug: lowercase, runs of non-alphanumerics collapsed to a single `-`,
    /// trimmed, truncated to 64 characters, empty → `"unnamed"`.
    ///
    /// The input is the row's `name_normalized`, which `EntityNormalization` has already
    /// case-folded and whitespace-collapsed; this adds the filesystem's half of the rule.
    public static func slug(_ raw: String) -> String {
        var out = ""
        var pendingSeparator = false
        for character in raw.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSeparator, !out.isEmpty { out.append("-") }
                pendingSeparator = false
                out.append(character)
            } else {
                pendingSeparator = true
            }
        }
        if out.count > 64 { out = String(out.prefix(64)) }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "unnamed" : out
    }

    // MARK: - Destinations

    /// `assets/<entity kind>/<entity slug>/<requirement slug>/v<n>.<ext>` (§4.1).
    ///
    /// The extension is taken **lowercased from the imported file**; the version number is
    /// the one assigned inside the import transaction.
    public static func destination(
        entityKind: EntityKind,
        entityNameNormalized: String,
        requirementNameNormalized: String,
        versionNumber: Int,
        fileExtension: String
    ) throws -> RelativeProjectPath {
        try RelativeProjectPath(
            "assets/\(entityKind.rawValue)/\(slug(entityNameNormalized))"
                + "/\(slug(requirementNameNormalized))/\(versionFileName(versionNumber: versionNumber, fileExtension: fileExtension, collisionIndex: 1))"
        )
    }

    /// `v3.png`, then `v3-2.png`, `v3-3.png`, … — the screenplay importer's collision rule,
    /// applied to the **stem** so the extension keeps sniffing (§4.1).
    ///
    /// `collisionIndex` is 1 for the first candidate; a suffix appears from 2 on.
    public static func versionFileName(
        versionNumber: Int,
        fileExtension: String,
        collisionIndex: Int
    ) -> String {
        let stem = collisionIndex <= 1 ? "v\(versionNumber)" : "v\(versionNumber)-\(collisionIndex)"
        return fileExtension.isEmpty ? stem : "\(stem).\(fileExtension.lowercased())"
    }

    /// The same destination with the stem's collision suffix applied.
    public static func destination(
        entityKind: EntityKind,
        entityNameNormalized: String,
        requirementNameNormalized: String,
        versionNumber: Int,
        fileExtension: String,
        collisionIndex: Int
    ) throws -> RelativeProjectPath {
        let name = versionFileName(
            versionNumber: versionNumber,
            fileExtension: fileExtension,
            collisionIndex: collisionIndex
        )
        return try RelativeProjectPath(
            "assets/\(entityKind.rawValue)/\(slug(entityNameNormalized))"
                + "/\(slug(requirementNameNormalized))/\(name)"
        )
    }

    // MARK: - Magic bytes

    /// The image type `data` really is, by its leading bytes — `nil` for anything else.
    ///
    /// Imported media is untrusted input like everything else that crosses the bundle
    /// boundary (§4.1), so the file's **content** decides its type and the extension is
    /// checked against that answer rather than believed.
    public static func sniff(_ data: Data) -> ImageFormat? {
        let bytes = [UInt8](data.prefix(32))
        func matches(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            guard bytes.count >= offset + signature.count else { return false }
            return Array(bytes[offset..<(offset + signature.count)]) == signature
        }

        if matches([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if matches([0xFF, 0xD8, 0xFF]) { return .jpeg }
        // WebP is a RIFF container: "RIFF" ␣␣␣␣ "WEBP" — both halves, or a plain RIFF wave
        // file would pass.
        if matches(Array("RIFF".utf8)), matches(Array("WEBP".utf8), at: 8) { return .webp }
        // HEIC is ISO-BMFF: a `ftyp` box whose **brand** is one of the HEIF still ones.
        if matches(Array("ftyp".utf8), at: 4), bytes.count >= 12 {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            let heifBrands: Set<String> = [
                "heic", "heix", "heim", "heis", "hevc", "hevx", "hevm", "hevs", "mif1", "msf1",
            ]
            if heifBrands.contains(brand) { return .heic }
        }
        // TIFF, both byte orders.
        if matches([0x49, 0x49, 0x2A, 0x00]) || matches([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        return nil
    }

    /// The sniffed format, refusing an unsupported file and one whose extension disagrees
    /// with its bytes (§4.1's "refuses a file whose content does not match").
    public static func inspect(_ data: Data, fileName: String) throws -> ImageFormat {
        guard !data.isEmpty else { throw MediaImportError.emptyFile(fileName: fileName) }
        guard let format = sniff(data) else {
            throw MediaImportError.unsupportedMediaType(fileName: fileName)
        }
        let declared = (fileName as NSString).pathExtension.lowercased()
        guard format.acceptedExtensions.contains(declared) else {
            throw MediaImportError.mediaTypeMismatch(
                fileName: fileName,
                declared: declared.isEmpty ? "no type" : declared,
                detected: format.displayName
            )
        }
        return format
    }

    // MARK: - Header-only dimensions

    public struct PixelSize: Equatable, Hashable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// The **declared** pixel dimensions, read from the header and never from a decode
    /// (§4.1: `CGImageSourceCopyPropertiesAtIndex`, no full decode).
    ///
    /// PNG and JPEG are parsed natively first, deliberately: ImageIO *declines to report*
    /// dimensions for an absurd header — a PNG whose IHDR claims 100,000 × 100,000 comes
    /// back with no properties at all — and a bomb must be refused by `MediaImportLimits`
    /// **naming the measured value**, not by a vague "unreadable header". For the other
    /// three formats ImageIO's own header read is the answer, and its refusal to report is
    /// itself a refusal.
    public static func headerDimensions(of data: Data, format: ImageFormat) -> PixelSize? {
        switch format {
        case .png:
            return pngDimensions(data) ?? imageIODimensions(data)
        case .jpeg:
            return jpegDimensions(data) ?? imageIODimensions(data)
        case .webp, .heic, .tiff:
            return imageIODimensions(data)
        }
    }

    /// ImageIO's header read. `kCGImageSourceShouldCache: false` keeps it a header read.
    private static func imageIODimensions(_ data: Data) -> PixelSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return PixelSize(width: width, height: height)
    }

    /// IHDR: the first chunk of every PNG, width and height as big-endian `UInt32` at a
    /// fixed offset.
    private static func pngDimensions(_ data: Data) -> PixelSize? {
        let bytes = [UInt8](data.prefix(24))
        guard bytes.count == 24, Array(bytes[12..<16]) == Array("IHDR".utf8) else { return nil }
        let width = Int(bigEndian32(bytes, at: 16))
        let height = Int(bigEndian32(bytes, at: 20))
        guard width > 0, height > 0 else { return nil }
        return PixelSize(width: width, height: height)
    }

    /// The first SOF marker of a JPEG carries the frame's height and width.
    private static func jpegDimensions(_ data: Data) -> PixelSize? {
        let bytes = [UInt8](data)
        var index = 2
        while index + 9 < bytes.count {
            guard bytes[index] == 0xFF else { index += 1; continue }
            let marker = bytes[index + 1]
            // Padding, and the standalone markers that carry no length.
            if marker == 0xFF { index += 1; continue }
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) {
                index += 2
                continue
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let isStartOfFrame = (0xC0...0xCF).contains(marker)
                && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if isStartOfFrame {
                let height = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
                let width = Int(bytes[index + 7]) << 8 | Int(bytes[index + 8])
                guard width > 0, height > 0 else { return nil }
                return PixelSize(width: width, height: height)
            }
            if marker == 0xDA { return nil }  // Scan data begins; no frame header was found.
            guard length >= 2 else { return nil }
            index += 2 + length
        }
        return nil
    }

    private static func bigEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    // MARK: - The whole gate

    /// What an accepted import measured: the type, the size, and the declared dimensions.
    public struct MediaFacts: Equatable, Hashable, Sendable {
        public let format: ImageFormat
        public let byteCount: Int
        public let pixelWidth: Int
        public let pixelHeight: Int

        public init(format: ImageFormat, byteCount: Int, pixelWidth: Int, pixelHeight: Int) {
            self.format = format
            self.byteCount = byteCount
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }
    }

    /// §4.1's whole import gate over bytes already in memory: sniff, match the extension,
    /// enforce every `MediaImportLimits` bound, and report what was measured.
    ///
    /// Nothing here touches the bundle — it runs **before** a single byte is staged.
    public static func inspectForImport(_ data: Data, fileName: String) throws -> MediaFacts {
        try MediaImportLimits.check(byteCount: data.count, fileName: fileName)
        let format = try inspect(data, fileName: fileName)
        guard let size = headerDimensions(of: data, format: format) else {
            throw MediaImportError.unreadableImageHeader(fileName: fileName)
        }
        try MediaImportLimits.check(width: size.width, height: size.height, fileName: fileName)
        return MediaFacts(
            format: format,
            byteCount: data.count,
            pixelWidth: size.width,
            pixelHeight: size.height
        )
    }
}
