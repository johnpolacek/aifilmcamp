import Foundation

/// Text a scene contains that the model must never see (PHASE1_DESIGN §4.3).
public enum SceneExclusionKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case note
    case boneyard
}

/// One excluded range inside a scene's span.
///
/// FilmBrain reads these to build model-facing text and map offsets back **without**
/// importing `FilmScript` (§3.1).
public struct SceneExclusion: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let sceneID: UUID
    public let kind: SceneExclusionKind
    public let range: UTF16Range

    public init(id: UUID, sceneID: UUID, kind: SceneExclusionKind, range: UTF16Range) {
        self.id = id
        self.sceneID = sceneID
        self.kind = kind
        self.range = range
    }
}
