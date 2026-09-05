import Foundation
import GRDB

extension ProjectSession {
  public func previewSceneAppend(text: String) throws -> SceneAppendPreview {
    guard let database else { throw ProjectStoreError.sessionClosed }
    let document = try SceneAppendParser.parse(text)
    return try database.queue.read { db in
      guard let id = try SceneOperations.currentScriptID(in: db),
        let hash = try String.fetchOne(
          db, sql: "SELECT sha256 FROM scripts WHERE id = ?", arguments: [id.uuidString]
        )
      else { throw SceneAppendError.noScript }
      let last =
        try Int.fetchOne(
          db, sql: "SELECT MAX(ordinal) FROM scenes WHERE script_id = ?", arguments: [id.uuidString]
        ) ?? 0
      return SceneAppendPreview(
        document: document, scriptID: id, scriptSHA256: hash, lastOrdinal: last)
    }
  }

  @discardableResult
  public func appendScenes(_ preview: SceneAppendPreview, actor: MutationActor) throws
    -> JournalEntry
  {
    guard let database else { throw ProjectStoreError.sessionClosed }
    return try database.queue.write { db in
      try EditPrimitives.perform(
        .appendScenes(
          scriptID: preview.scriptID, expectedSHA256: preview.scriptSHA256,
          text: preview.text
        ),
        actor: actor, jobID: actor.jobID, in: db
      )
    }
  }
}
