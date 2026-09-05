import FilmScript
import Foundation

/// An immutable preview of the exact text and screenplay revision the user will append.
public struct SceneAppendPreview: Sendable {
  public struct Scene: Identifiable, Sendable {
    public var id: Int { ordinal }
    public let ordinal: Int
    public let heading: String
  }

  public let scenes: [Scene]
  public let warnings: [String]
  let scriptID: UUID
  let scriptSHA256: String
  let text: String

  init(document: ScreenplayDocument, scriptID: UUID, scriptSHA256: String, lastOrdinal: Int) {
    self.scriptID = scriptID
    self.scriptSHA256 = scriptSHA256
    self.text = document.sourceText
    self.scenes = document.scenes.map {
      Scene(ordinal: lastOrdinal + $0.ordinal, heading: $0.heading)
    }
    self.warnings = document.warnings.map(\.message)
  }
}

enum SceneAppendError: Error, LocalizedError {
  case invalidText
  case noScript
  case stalePreview
  case activeRun
  case humanOnly

  var errorDescription: String? {
    switch self {
    case .invalidText:
      "Paste scene text with a heading for each scene, such as INT. HOUSE - DAY or EXT. ROAD - NIGHT. Remove any title page or text before the first scene heading."
    case .noScript:
      "Import a screenplay before adding scenes."
    case .stalePreview:
      "The screenplay has changed. Preview the scenes again before adding them."
    case .activeRun:
      "Finish or cancel the current run before adding scenes."
    case .humanOnly:
      "Scenes can only be added by the filmmaker."
    }
  }
}

enum SceneAppendParser {
  static func parse(_ text: String) throws -> ScreenplayDocument {
    let document = FountainParser.parse(text, format: .text)
    guard !document.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      document.titlePage.lines.isEmpty,
      !document.scenes.isEmpty,
      document.scenes.allSatisfy({ scene in
        scene.ordinal > 0 && scene.elements.contains { $0.kind == .sceneHeading }
      }),
      !document.warnings.contains(where: {
        $0.code == .noSceneHeadings || $0.code == .emptyDocument
      })
    else { throw SceneAppendError.invalidText }
    return document
  }
}
