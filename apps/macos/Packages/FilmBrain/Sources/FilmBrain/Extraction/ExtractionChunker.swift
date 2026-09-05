import FilmCore
import Foundation

public struct ChunkScene: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let ordinal: Int

    public init(id: UUID, ordinal: Int) {
        self.id = id
        self.ordinal = ordinal
    }
}

public struct ExtractionChunk: Equatable, Sendable {
    public let index: Int
    public let scenes: [ChunkScene]
    public let text: String

    public init(index: Int, scenes: [ChunkScene], text: String) {
        self.index = index
        self.scenes = scenes
        self.text = text
    }
}

public enum ExtractionChunker {
    public static func chunks(
        scenes: [Scene],
        modelText: (UUID) -> String,
        budgetUTF16: Int = 32_000
    ) -> [ExtractionChunk] {
        guard !scenes.isEmpty else { return [] }
        let budget = max(1, budgetUTF16)
        let ordered = scenes.sorted {
            $0.ordinal == $1.ordinal ? $0.id.uuidString < $1.id.uuidString : $0.ordinal < $1.ordinal
        }
        var groups: [[(Scene, String)]] = []
        var current: [(Scene, String)] = []
        var currentLength = 0
        for scene in ordered {
            let text = modelText(scene.id)
            let length = text.utf16.count
            if !current.isEmpty, currentLength + length > budget {
                groups.append(current)
                current = []
                currentLength = 0
            }
            current.append((scene, text))
            currentLength += length
        }
        if !current.isEmpty { groups.append(current) }

        return groups.enumerated().map { index, group in
            let text = group.map { scene, text in
                """
                <scene id="\(scene.id.uuidString)" ordinal="\(scene.ordinal)">
                \(text)
                </scene>
                """
            }.joined(separator: "\n")
            return ExtractionChunk(
                index: index,
                scenes: group.map { ChunkScene(id: $0.0.id, ordinal: $0.0.ordinal) },
                text: text
            )
        }
    }
}
