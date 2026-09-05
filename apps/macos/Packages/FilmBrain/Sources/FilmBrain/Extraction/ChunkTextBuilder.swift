import FilmCore
import Foundation

public struct RedactedPiece: Equatable, Sendable {
    public let modelStart: Int
    public let originalStart: Int
    public let length: Int

    public init(modelStart: Int, originalStart: Int, length: Int) {
        self.modelStart = modelStart
        self.originalStart = originalStart
        self.length = length
    }
}

public struct RedactedScene: Equatable, Sendable {
    public let text: String
    public let pieces: [RedactedPiece]

    public init(text: String, pieces: [RedactedPiece]) {
        self.text = text
        self.pieces = pieces
    }

    public func originalUTF16Offset(forModelOffset offset: Int) -> Int? {
        guard offset >= 0 else { return nil }
        for piece in pieces where offset >= piece.modelStart && offset <= piece.modelStart + piece.length {
            return piece.originalStart + (offset - piece.modelStart)
        }
        return nil
    }
}

public enum ChunkTextBuilder {
    /// Removes parser-recorded note and boneyard spans. With the default scene start,
    /// exclusion ranges are interpreted relative to `sceneText`; production callers pass
    /// `Scene.range.start` because stored exclusions are script-relative.
    public static func redact(
        sceneText: String,
        exclusions: [SceneExclusion],
        sceneStartUTF16: Int = 0
    ) -> RedactedScene {
        let length = sceneText.utf16.count
        var ranges: [(Int, Int)] = []
        for exclusion in exclusions {
            let relativeStart = exclusion.range.start - sceneStartUTF16
            let relativeEnd = exclusion.range.end - sceneStartUTF16
            let start = max(0, min(length, relativeStart))
            let end = max(0, min(length, relativeEnd))
            if start < end { ranges.append((start, end)) }
        }
        ranges.sort { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }

        var merged: [(Int, Int)] = []
        for range in ranges {
            if let last = merged.last, range.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, range.1)
            } else {
                merged.append(range)
            }
        }

        var cursor = 0
        var modelCursor = 0
        var text = ""
        var pieces: [RedactedPiece] = []
        for range in merged {
            appendPiece(
                sceneText: sceneText,
                relativeStart: cursor,
                relativeEnd: range.0,
                sceneStartUTF16: sceneStartUTF16,
                modelCursor: &modelCursor,
                text: &text,
                pieces: &pieces
            )
            cursor = max(cursor, range.1)
        }
        appendPiece(
            sceneText: sceneText,
            relativeStart: cursor,
            relativeEnd: length,
            sceneStartUTF16: sceneStartUTF16,
            modelCursor: &modelCursor,
            text: &text,
            pieces: &pieces
        )
        return RedactedScene(text: text, pieces: pieces)
    }

    private static func appendPiece(
        sceneText: String,
        relativeStart: Int,
        relativeEnd: Int,
        sceneStartUTF16: Int,
        modelCursor: inout Int,
        text: inout String,
        pieces: inout [RedactedPiece]
    ) {
        guard relativeStart < relativeEnd else { return }
        let utf16 = sceneText.utf16
        let start = utf16.index(utf16.startIndex, offsetBy: relativeStart)
        let end = utf16.index(utf16.startIndex, offsetBy: relativeEnd)
        let fragment = String(decoding: utf16[start..<end], as: UTF16.self)
        let fragmentLength = fragment.utf16.count
        text += fragment
        pieces.append(RedactedPiece(
            modelStart: modelCursor,
            originalStart: sceneStartUTF16 + relativeStart,
            length: fragmentLength
        ))
        modelCursor += fragmentLength
    }
}
