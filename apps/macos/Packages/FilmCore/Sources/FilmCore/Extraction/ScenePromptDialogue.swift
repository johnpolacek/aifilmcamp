import FilmScript
import Foundation

/// A source dialogue occurrence, not a distinct phrase: identical lines may recur.
/// FilmScript stays behind FilmCore; no parser types enter the prompt task's API.
public struct ScenePromptDialogueLine: Equatable, Sendable {
    public let speaker: String
    public let text: String

    public init(speaker: String, text: String) {
        self.speaker = speaker
        self.text = text
    }
}

public enum ScenePromptDialogue: Sendable {
    /// Reuses the import parser on the resolved scene text (including human overrides).
    /// This is a read-only derivation; neither the input encoding nor its digest changes.
    public static func lines(in input: ScenePromptInput) -> [ScenePromptDialogueLine] {
        let names = input.entities.flatMap { entity in
            ([entity.name] + entity.aliases).map {
                (cue: CueNormalizer.normalize($0).name, canonical: entity.name)
            }
        }
        let document = FountainParser.parse(input.sceneText, format: .fountain)
        var result: [ScenePromptDialogueLine] = []
        for scene in document.scenes {
            var speaker: String?
            var fragments: [String] = []
            func flush() {
                if let speaker, !fragments.isEmpty {
                    result.append(.init(speaker: speaker, text: fragments.joined(separator: " ")))
                }
                fragments.removeAll()
            }
            for element in scene.elements {
                switch element.kind {
                case .character:
                    flush()
                    let cue = CueNormalizer.normalize(element.text).name
                    speaker = names.first { $0.cue == cue }?.canonical
                        ?? DisplayCase.titleCased(cue)
                case .dialogue:
                    if speaker != nil { fragments.append(element.text) }
                case .parenthetical, .note, .boneyard:
                    // Parentheticals direct delivery, not speech. Notes never become lines.
                    break
                default:
                    flush()
                    speaker = nil
                }
            }
            flush()
        }
        return result
    }
}
