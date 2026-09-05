import Foundation
import GRDB

/// A reusable bundle is a character's shared facial identity plus one selected body.
public struct CharacterOutfitBundle: Identifiable, Sendable {
    public var id: UUID { bodyRequirementID }
    public let entityID: UUID
    public let entityName: String
    public let name: String
    public let faceRequirementID: UUID
    public let bodyRequirementID: UUID
    public let faceVersion: AssetVersion
    public let bodyVersion: AssetVersion
}

public struct CharacterOutfitCreation: Sendable {
    public let requirementID: UUID
    public let entry: JournalEntry
}

public extension ProjectSession {
    func characterOutfitBundles() throws -> [CharacterOutfitBundle] {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.read { db in
            let graph = try ProjectRepository.manifestGraph(in: db)
            return try graph.requirements.values.compactMap { body in
                guard let face = Self.outfitFace(for: body, graph: graph),
                      let bodyVersion = try Self.outfitVersion(for: body.id, graph: graph, in: db),
                      let faceVersion = try Self.outfitVersion(for: face.id, graph: graph, in: db)
                else { return nil }
                return CharacterOutfitBundle(
                    entityID: body.entityID,
                    entityName: graph.entities[body.entityID]?.name ?? "",
                    name: body.outfitSourceVersionID == nil ? "Original Outfit" : body.name,
                    faceRequirementID: face.id, bodyRequirementID: body.id,
                    faceVersion: faceVersion, bodyVersion: bodyVersion
                )
            }.sorted {
                ($0.entityName, $0.name, $0.id.uuidString)
                    < ($1.entityName, $1.name, $1.id.uuidString)
            }
        }
    }

    /// Copy, source provenance, prompt, scene links, and scene-only replacement are one
    /// journal group. The source image is verified and copied, never moved or overwritten.
    func createCharacterOutfit(
        sceneID: UUID,
        sourceRequirementID: UUID,
        name: String
    ) throws -> CharacterOutfitCreation {
        guard let database else { throw ProjectStoreError.sessionClosed }
        let repository = ProjectRepository(database: database)
        let detail = try repository.requirementDetail(id: sourceRequirementID)
        guard detail.entity.kind == .character, detail.referenceTypeCode == "full_body",
              detail.isActive,
              let version = detail.versions.first(where: { $0.status == .approved })
        else { throw Self.outfitRefusal("Choose a current character body reference.") }
        let data = try AssetOperations.verifiedMediaData(
            at: version.relativePath, sha256: version.sha256,
            byteCount: version.byteCount, using: mediaContainment
        )
        let facts = try AssetPathing.inspectForImport(data, fileName: version.originalFileName)
        let requirementID = UUID(), assetID = UUID(), versionID = UUID(), promptID = UUID()
        let ext = (version.relativePath.rawValue as NSString).pathExtension
        let path = try RelativeProjectPath("assets/outfits/\(requirementID.uuidString)/\(versionID.uuidString).\(ext)")
        try mediaContainment.write(data, to: path)
        do {
            let entry = try database.queue.write { db in
                let graph = try ProjectRepository.readinessGraph(in: db)
                guard graph.linkedRequirements(of: sceneID).contains(sourceRequirementID),
                      let source = graph.manifest.requirements[sourceRequirementID],
                      let face = Self.outfitFace(for: source, graph: graph.manifest),
                      try Self.outfitVersion(for: face.id, graph: graph.manifest, in: db) != nil,
                      try Self.outfitVersion(for: source.id, graph: graph.manifest, in: db)?.id == version.id
                else { throw Self.outfitRefusal("The source bundle changed. Reopen it and try again.") }
                var ops: [EditOperation] = [
                    .createRequirement(
                        id: requirementID, entityID: source.entityID, tier: .variant,
                        typeID: nil, name: name, reason: "Scene-specific character outfit.",
                        outfitSourceVersionID: version.id
                    ),
                    .addRequirementScene(requirementID: requirementID, sceneID: sceneID,
                                         linkID: UUID(), restoring: []),
                    .createAsset(id: assetID, requirementID: requirementID, restoring: []),
                    .createPrompt(
                        id: promptID, requirementID: requirementID,
                        body: detail.currentPrompt?.body
                            ?? "Character body reference sheet: headless front view and complete rear view, side by side.",
                        targetModel: detail.currentPrompt?.targetModel ?? "", restoring: []
                    ),
                    .importAssetVersion(
                        versionID: versionID, assetID: assetID, versionNumber: 1,
                        relativePath: path, sha256: version.sha256, byteCount: facts.byteCount,
                        originalFileName: version.originalFileName, mediaKind: .image,
                        pixelWidth: facts.pixelWidth, pixelHeight: facts.pixelHeight,
                        promptID: promptID, restoring: []
                    ),
                    .approveVersion(assetID: assetID, versionID: versionID)
                ]
                ops += Self.excludeOtherBodies(entityID: source.entityID, except: requirementID,
                                               sceneID: sceneID, graph: graph)
                if let excluded = try Self.outfitExclusion(sceneID: sceneID, requirementID: face.id, in: db) {
                    ops.append(.includeReferenceInScene(exclusionID: excluded))
                }
                return try EditPrimitives.performGroup(ops, as: .batch(ops), actor: .human,
                                                       jobID: nil, media: mediaContainment, in: db)
            }
            return CharacterOutfitCreation(requirementID: requirementID, entry: entry)
        } catch {
            _ = try? mediaContainment.removeIfPresent(at: path)
            throw error
        }
    }

    /// Select an existing bundle only for this scene, with one undo step. Membership is
    /// stored through the same operations that readiness, prompt input, and export read.
    func useCharacterOutfit(bodyRequirementID: UUID, sceneID: UUID) throws -> JournalEntry {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try database.queue.write { db in
            try SceneOperations.requireScene(sceneID, in: db)
            let graph = try ProjectRepository.readinessGraph(in: db)
            guard let body = graph.manifest.requirements[bodyRequirementID],
                  let face = Self.outfitFace(for: body, graph: graph.manifest),
                  try Self.outfitVersion(for: body.id, graph: graph.manifest, in: db) != nil,
                  try Self.outfitVersion(for: face.id, graph: graph.manifest, in: db) != nil
            else { throw Self.outfitRefusal("This bundle needs a current face and body image.") }
            var ops: [EditOperation] = []
            if graph.canonicalLinks[sceneID]?.contains(face.id) != true {
                ops.append(.setSceneEntity(sceneID: sceneID, entityID: body.entityID, role: .present, appearanceID: nil))
            }
            if body.tier == .variant, graph.variantLinks[sceneID]?.contains(body.id) != true {
                ops.append(.addRequirementScene(requirementID: body.id, sceneID: sceneID,
                                                 linkID: UUID(), restoring: []))
            }
            for id in [face.id, body.id] {
                if let exclusion = try Self.outfitExclusion(sceneID: sceneID, requirementID: id, in: db) {
                    ops.append(.includeReferenceInScene(exclusionID: exclusion))
                }
            }
            // Include all canonical bodies introduced by a new entity appearance too.
            var selectingGraph = graph
            selectingGraph.canonicalLinks[sceneID, default: []].formUnion(
                graph.manifest.requirements.values.filter {
                    $0.entityID == body.entityID && $0.tier == .canonical
                }.map(\.id)
            )
            ops += Self.excludeOtherBodies(entityID: body.entityID, except: body.id,
                                           sceneID: sceneID, graph: selectingGraph)
            guard !ops.isEmpty else { throw Self.outfitRefusal("This bundle is already used in this scene.") }
            return try EditPrimitives.performGroup(ops, as: .batch(ops), actor: .human,
                                                   jobID: nil, media: mediaContainment, in: db)
        }
    }
}

private extension ProjectSession {
    static func outfitFace(for body: AssetRequirement, graph: ProjectRepository.ManifestGraph) -> AssetRequirement? {
        guard graph.entities[body.entityID]?.kind == .character, graph.isActive(body), body.necessity == .required,
              body.outfitSourceVersionID != nil
                || body.typeID.flatMap({ graph.types[$0]?.code }) == "full_body"
        else { return nil }
        return graph.requirements.values.first {
            $0.entityID == body.entityID && $0.tier == .canonical && graph.isActive($0) && $0.necessity == .required
                && $0.typeID.flatMap { graph.types[$0]?.code } == "face_closeup"
        }
    }

    static func outfitVersion(for id: UUID, graph: ProjectRepository.ManifestGraph, in db: Database) throws -> AssetVersion? {
        guard let asset = graph.assetsByRequirement[id],
              let row = try Row.fetchOne(db, sql: "SELECT * FROM asset_versions WHERE asset_id = ? AND status = 'approved'",
                                        arguments: [asset.id.uuidString]) else { return nil }
        return try decodeAssetVersion(row)
    }

    static func excludeOtherBodies(entityID: UUID, except selectedID: UUID, sceneID: UUID,
                                   graph: ProjectRepository.ReadinessGraph) -> [EditOperation] {
        graph.linkedRequirements(of: sceneID).sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            guard id != selectedID, let r = graph.manifest.requirements[id], r.entityID == entityID,
                  r.outfitSourceVersionID != nil
                    || r.typeID.flatMap({ graph.manifest.types[$0]?.code }) == "full_body"
            else { return nil }
            return .excludeReferenceFromScene(sceneID: sceneID, requirementID: id,
                                               exclusionID: UUID(), restoring: [])
        }
    }

    static func outfitExclusion(sceneID: UUID, requirementID: UUID, in db: Database) throws -> UUID? {
        try String.fetchOne(db, sql: "SELECT id FROM scene_reference_exclusions WHERE scene_id = ? AND requirement_id = ?",
                            arguments: [sceneID.uuidString, requirementID.uuidString]).map(UUID.required)
    }

    static func outfitRefusal(_ reason: String) -> ProjectStoreError {
        .requirementOperationRefused(reason: reason)
    }
}
