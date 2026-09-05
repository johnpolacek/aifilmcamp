import Foundation

public struct EvidencePiece: Equatable, Hashable, Sendable {
    public let modelStart: Int
    public let originalStart: Int
    public let length: Int

    public init(modelStart: Int, originalStart: Int, length: Int) {
        self.modelStart = modelStart
        self.originalStart = originalStart
        self.length = length
    }
}

public struct EvidenceText: Equatable, Sendable {
    public let text: String
    public let pieces: [EvidencePiece]

    public init(text: String, pieces: [EvidencePiece]) {
        self.text = text
        self.pieces = pieces
    }
}

public struct AnchoredSpan: Codable, Equatable, Hashable, Sendable {
    public let startUTF16: Int
    public let endUTF16: Int

    public init(startUTF16: Int, endUTF16: Int) {
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
    }
}

public struct EvidenceAnchor: Sendable {
    private let project: any ProjectReading

    public init(project: any ProjectReading) {
        self.project = project
    }

    public func locate(quote: String, sceneID: UUID) async throws -> AnchoredSpan? {
        guard let scene = try await project.scenes().first(where: { $0.id == sceneID }) else {
            throw ProjectStoreError.sceneNotFound
        }
        let text = try await project.sceneText(id: sceneID)
        let exclusions = try await project.sceneExclusions(id: sceneID)
        return Self.locate(
            quote: quote,
            in: Self.redact(
                sceneText: text,
                exclusions: exclusions,
                sceneStartUTF16: scene.range.start
            )
        )
    }

    /// FilmCore's byte-identical counterpart to FilmBrain's `ChunkTextBuilder`.
    public static func redact(
        sceneText: String,
        exclusions: [SceneExclusion],
        sceneStartUTF16: Int = 0
    ) -> EvidenceText {
        let length = sceneText.utf16.count
        var ranges: [(Int, Int)] = []
        for exclusion in exclusions {
            let start = max(0, min(length, exclusion.range.start - sceneStartUTF16))
            let end = max(0, min(length, exclusion.range.end - sceneStartUTF16))
            if start < end { ranges.append((start, end)) }
        }
        ranges.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        var merged: [(Int, Int)] = []
        for range in ranges {
            if let last = merged.last, range.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, range.1)
            } else {
                merged.append(range)
            }
        }
        var cursor = 0
        var modelStart = 0
        var output = ""
        var pieces: [EvidencePiece] = []
        for range in merged + [(length, length)] {
            if cursor < range.0 {
                let fragment = utf16Slice(sceneText, start: cursor, end: range.0)
                let count = fragment.utf16.count
                output += fragment
                pieces.append(EvidencePiece(
                    modelStart: modelStart,
                    originalStart: sceneStartUTF16 + cursor,
                    length: count
                ))
                modelStart += count
            }
            cursor = max(cursor, range.1)
        }
        return EvidenceText(text: output, pieces: pieces)
    }

    static func locate(quote: String, in redacted: EvidenceText) -> AnchoredSpan? {
        guard !quote.isEmpty else { return nil }
        let source = redacted.text as NSString
        let exact = source.range(of: quote)
        if exact.location != NSNotFound,
           let mapped = map(modelRange: exact.location..<(exact.location + exact.length), pieces: redacted.pieces) {
            return mapped
        }

        let normalizedSource = normalized(redacted.text)
        let normalizedQuote = normalized(quote).text
        guard !normalizedQuote.isEmpty else { return nil }
        let hit = (normalizedSource.text as NSString).range(of: normalizedQuote)
        guard hit.location != NSNotFound, hit.length > 0,
              hit.location < normalizedSource.originalOffsets.count,
              hit.location + hit.length - 1 < normalizedSource.originalOffsets.count
        else { return nil }
        let start = normalizedSource.originalOffsets[hit.location]
        let last = normalizedSource.originalOffsets[hit.location + hit.length - 1]
        return map(modelRange: start..<(last + 1), pieces: redacted.pieces)
    }

    private static func map(modelRange: Range<Int>, pieces: [EvidencePiece]) -> AnchoredSpan? {
        guard !modelRange.isEmpty else { return nil }
        for piece in pieces where modelRange.lowerBound >= piece.modelStart {
            let pieceEnd = piece.modelStart + piece.length
            guard modelRange.upperBound <= pieceEnd else { continue }
            let start = piece.originalStart + modelRange.lowerBound - piece.modelStart
            return AnchoredSpan(startUTF16: start, endUTF16: start + modelRange.count)
        }
        return nil
    }

    private static func normalized(_ text: String) -> (text: String, originalOffsets: [Int]) {
        var result = ""
        var offsets: [Int] = []
        var offset = 0
        var previousWasWhitespace = false
        for character in text {
            let originalLength = String(character).utf16.count
            if character.isWhitespace {
                if !previousWasWhitespace, !result.isEmpty {
                    result.append(" ")
                    offsets.append(offset)
                }
                previousWasWhitespace = true
            } else {
                let lowered = String(character).lowercased()
                result += lowered
                offsets.append(contentsOf: repeatElement(offset, count: lowered.utf16.count))
                previousWasWhitespace = false
            }
            offset += originalLength
        }
        return (result.trimmingCharacters(in: .whitespaces), offsets)
    }

    private static func utf16Slice(_ text: String, start: Int, end: Int) -> String {
        let utf16 = text.utf16
        return String(decoding: utf16[
            utf16.index(utf16.startIndex, offsetBy: start)..<utf16.index(utf16.startIndex, offsetBy: end)
        ], as: UTF16.self)
    }
}
