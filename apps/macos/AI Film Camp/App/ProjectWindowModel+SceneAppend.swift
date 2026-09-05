import FilmCore
import Foundation

extension ProjectWindowModel {
  var canAddScenes: Bool {
    script != nil && !isClosed && !isImporting && !isAppendingScenes && !isApplyingInverse
      && !jobs.contains { !$0.state.isTerminal }
  }

  @discardableResult
  func appendScenes(text: String) async throws -> Bool {
    guard canAddScenes else { return false }
    isAppendingScenes = true
    defer { isAppendingScenes = false }
    let preview = try await session.previewSceneAppend(text: text)
    let entry = try await session.appendScenes(preview, actor: .human)
    didApply(entry)
    await refresh()
    workspaceSearchText = ""
    if let ordinal = preview.scenes.first?.ordinal,
      let scene = scenes.first(where: { $0.ordinal == ordinal })
    {
      await selectWorkspaceScene(scene.id)
    }
    return true
  }
}
