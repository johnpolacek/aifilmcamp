import FilmScript
import Foundation
import GRDB

enum SceneAppendOperations {
  static func append(
    scriptID: UUID, expectedSHA256: String, text: String,
    actor: MutationActor, in db: Database
  ) throws -> MutationEffect {
    guard actor == .human else { throw SceneAppendError.humanOnly }
    guard try SceneOperations.currentScriptID(in: db) == scriptID,
      let script = try Row.fetchOne(
        db, sql: "SELECT * FROM scripts WHERE id = ?", arguments: [scriptID.uuidString]),
      (script["sha256"] as String) == expectedSHA256
    else { throw SceneAppendError.stalePreview }
    guard
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM jobs WHERE state NOT IN ('completed','failed','cancelled')")
        == 0
    else { throw SceneAppendError.activeRun }

    let parsed = try SceneAppendParser.parse(text)
    let priorText: String = script["source_text"]
    // Never reparse or extend the previous last scene: its bounds and evidence stay exact.
    let prefix = priorText + "\n\n"
    let sourceText = prefix + parsed.sourceText
    let offset = prefix.utf16.count
    let lastScene =
      try Int.fetchOne(
        db, sql: "SELECT MAX(ordinal) FROM scenes WHERE script_id = ?",
        arguments: [scriptID.uuidString]) ?? 0
    let lastSequence =
      try Int.fetchOne(
        db, sql: "SELECT MAX(ordinal) FROM sequences WHERE script_id = ?",
        arguments: [scriptID.uuidString]) ?? 0
    func shift(_ range: FilmScript.UTF16Range) -> FilmScript.UTF16Range {
      FilmScript.UTF16Range(start: range.start + offset, end: range.end + offset)
    }
    let document = ScreenplayDocument(
      format: .text, sourceText: sourceText, titlePage: parsed.titlePage,
      sequences: parsed.sequences.map {
        ParsedSequence(
          ordinal: lastSequence + $0.ordinal, title: $0.title, depth: $0.depth,
          range: shift($0.range))
      },
      scenes: parsed.scenes.map { scene in
        ParsedScene(
          ordinal: lastScene + scene.ordinal, heading: scene.heading, intExt: scene.intExt,
          locationText: scene.locationText, timeOfDay: scene.timeOfDay,
          sceneNumber: scene.sceneNumber,
          sequenceOrdinal: scene.sequenceOrdinal.map { lastSequence + $0 },
          range: shift(scene.range),
          elements: scene.elements.map {
            ParsedElement(kind: $0.kind, range: shift($0.range), text: $0.text)
          },
          cues: scene.cues.map {
            ParsedCue(
              raw: $0.raw, normalized: $0.normalized, extensions: $0.extensions,
              range: shift($0.range), isDual: $0.isDual)
          },
          isOmitted: scene.isOmitted
        )
      },
      warnings: parsed.warnings.map {
        ParseWarning(code: $0.code, message: $0.message, range: $0.range.map(shift))
      }
    )
    let now = Date()
    let projectID = try UUID.required(script["project_id"])
    let written = try ScreenplayWriter.write(
      document: document, projectID: projectID, scriptID: scriptID, jobID: nil,
      now: now, matchExistingAliases: true, in: db
    )
    let previousWarnings: String = script["parse_warnings_json"]
    let warnings =
      try JSONDecoder().decode([ParseWarning].self, from: Data(previousWarnings.utf8))
      + document.warnings
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try db.execute(
      sql: "UPDATE scripts SET source_text = ?, sha256 = ?, parse_warnings_json = ? WHERE id = ?",
      arguments: [
        sourceText, sourceText.sha256HexOfUTF8,
        String(decoding: try encoder.encode(warnings), as: UTF8.self), scriptID.uuidString,
      ]
    )
    try db.execute(
      sql: "UPDATE projects SET updated_at = ? WHERE id = ?",
      arguments: [UTCDate.string(from: now), projectID.uuidString])

    var affected: Set<SubjectRef> = [SubjectRef(kind: .script, id: scriptID)]
    affected.formUnion(written.sceneIDsByOrdinal.values.map { SubjectRef(kind: .scene, id: $0) })
    affected.formUnion(written.entityIDs.map { SubjectRef(kind: .entity, id: $0) })
    affected.formUnion(written.aliasIDs.map { SubjectRef(kind: .alias, id: $0) })
    affected.formUnion(written.appearanceIDs.map { SubjectRef(kind: .appearance, id: $0) })
    // Include reused entities as dependencies so an older analysis cannot be reverted
    // through these new appearances and cascade away their referenced characters.
    for sceneID in written.sceneIDsByOrdinal.values {
      for raw in try String.fetchAll(
        db, sql: "SELECT entity_id FROM scene_entities WHERE scene_id = ?",
        arguments: [sceneID.uuidString])
      {
        affected.insert(SubjectRef(kind: .entity, id: try UUID.required(raw)))
      }
    }
    var snapshots = [RowSnapshot(table: "scripts", row: script)]
    for operation in try RequirementOperations.buildPlan(in: db).children {
      let effect = try EditPrimitives.mutate(operation, actor: actor, in: db)
      affected.formUnion(effect.affected)
      snapshots.append(contentsOf: effect.snapshots)
    }
    return MutationEffect(
      inverse: nil, affected: affected, snapshots: snapshots, screenplayWrite: written)
  }
}
