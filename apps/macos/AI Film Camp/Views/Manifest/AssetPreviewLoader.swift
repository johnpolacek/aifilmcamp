import CryptoKit
import Darwin
import FilmCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The version preview (PHASE2_DESIGN §4.1), and the damaged-asset warning that replaces it.
///
/// Three rules from §4.1, all of them load-bearing:
///
/// * **The file is opened through `BundleContainment`**, never through a path resolved and
///   then re-traversed. A symlinked `assets/` component or a symlinked leaf therefore
///   refuses the read, and the refusal is FilmCore's own sentence, shown as the warning.
/// * **Integrity is checked before anything is rendered.** The byte count is verified
///   cheaply from `fstat` on the descriptor the walk produced, and the SHA-256 over the
///   bytes already read is compared with the version row's. A mismatch is a damaged-asset
///   **warning**, never a crash and never a silently substituted image.
/// * **Never a full-size decode.** Every preview comes from
///   `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`, so a
///   16,384-pixel import costs at most the fixed 256/512/2048-pixel tier its surface chose.
///
/// It hands back PNG bytes rather than a `CGImage` so the whole read can run off the main
/// actor under strict concurrency; the view turns them into an `NSImage`.
enum AssetPreviewLoader {
    /// Fixed decode tiers. Callers choose intent rather than an arbitrary pixel budget,
    /// so no presentation can accidentally turn a project image into an unbounded decode.
    enum PreviewSize: Int, CaseIterable, Sendable {
        case thumbnail = 256
        case card = 512
        case expanded = 2_048

        var maximumPixelSize: Int { rawValue }
    }

    /// Compatibility for the original thumbnail contract.
    static let maximumPixelSize = PreviewSize.thumbnail.maximumPixelSize

    struct Preview: Sendable, Equatable {
        /// PNG bytes of the capped thumbnail; `nil` whenever `damage` is set.
        var thumbnailPNG: Data?
        /// §4.1's damaged-asset warning, or `nil` when the file verified and decoded.
        var damage: String?

        static let empty = Preview(thumbnailPNG: nil, damage: nil)
    }

    private enum PreviewFailure: Error {
        case unreadable
        case sizeMismatch(expected: Int, found: Int)
        case contentMismatch
        case undecodable
    }

    /// Reads, verifies, and decodes one version. Never throws: every failure becomes the
    /// warning the inspector renders in the thumbnail's place.
    static func load(
        containment: BundleContainment,
        version: AssetVersion,
        size: PreviewSize = .thumbnail
    ) -> Preview {
        do {
            let data = try containment.withReadDescriptor(at: version.relativePath) { descriptor in
                try read(descriptor: descriptor, expecting: version.byteCount)
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == version.sha256 else { throw PreviewFailure.contentMismatch }
            guard let thumbnail = thumbnail(of: data, size: size) else {
                throw PreviewFailure.undecodable
            }
            return Preview(thumbnailPNG: thumbnail, damage: nil)
        } catch {
            return Preview(thumbnailPNG: nil, damage: message(for: error))
        }
    }

    static func load(
        containment: BundleContainment,
        reference: ScenePromptCardReference,
        size: PreviewSize = .thumbnail
    ) -> Preview {
        do {
            let path = try RelativeProjectPath(reference.relativePath)
            let data = try containment.withReadDescriptor(at: path) { descriptor in
                try read(descriptor: descriptor)
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == reference.sha256 else { throw PreviewFailure.contentMismatch }
            guard let thumbnail = thumbnail(of: data, size: size) else {
                throw PreviewFailure.undecodable
            }
            return Preview(thumbnailPNG: thumbnail, damage: nil)
        } catch {
            return Preview(thumbnailPNG: nil, damage: message(for: error))
        }
    }

    // MARK: - Reading

    private static func read(descriptor: Int32, expecting byteCount: Int) throws -> Data {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw PreviewFailure.unreadable }
        let size = Int(status.st_size)
        guard size == byteCount else {
            throw PreviewFailure.sizeMismatch(expected: byteCount, found: size)
        }
        // `dup` because the handle closes what it owns and the walk owns the original.
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else { throw PreviewFailure.unreadable }
        let handle = FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
        guard let data = try handle.readToEnd() else { throw PreviewFailure.unreadable }
        return data
    }

    private static func read(descriptor: Int32) throws -> Data {
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else { throw PreviewFailure.unreadable }
        let handle = FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
        guard let data = try handle.readToEnd() else { throw PreviewFailure.unreadable }
        return data
    }

    // MARK: - Decoding, capped

    private static func thumbnail(of data: Data, size: PreviewSize) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: size.maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return encoded as Data
    }

    // MARK: - Wording

    private static func message(for error: any Error) -> String {
        switch error {
        case let failure as PreviewFailure:
            switch failure {
            case .unreadable:
                "This image could not be read from the project."
            case let .sizeMismatch(expected, found):
                "This image changed on disk: \(expected) bytes were imported, \(found) are there now."
            case .contentMismatch:
                "This image changed on disk: its contents no longer match what was imported."
            case .undecodable:
                "This image could not be previewed."
            }
        default:
            (error as? LocalizedError)?.errorDescription
                ?? "This image could not be read from the project."
        }
    }
}
