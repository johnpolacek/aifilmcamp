import FilmCore
import Foundation

public struct CompletedChunkExtraction: Equatable, Sendable {
    public let chunkIndex: Int
    public let result: ExtractChunkResult

    public init(chunkIndex: Int, result: ExtractChunkResult) {
        self.chunkIndex = chunkIndex
        self.result = result
    }
}

public enum ExtractionProposalBuilder {
    public static func build(
        scriptID: UUID,
        scriptSHA256: String,
        settings: ExtractionSettings,
        chunks: [CompletedChunkExtraction],
        reconcile: ReconcileResult,
        chunksFailed: Int,
        uncoveredSceneOrdinals: [Int]
    ) throws -> ExtractionProposal {
        let orderedChunks = chunks.sorted { $0.chunkIndex < $1.chunkIndex }
        let allScenes = orderedChunks.flatMap { chunk in
            chunk.result.scenes.map { (chunk.chunkIndex, $0) }
        }
        var extractedByKey: [String: [(Int, ExtractedScene, ExtractedEntity)]] = [:]
        for (chunkIndex, scene) in allScenes {
            for entity in scene.entities {
                extractedByKey[key(entity.kind, entity.name), default: []].append((chunkIndex, scene, entity))
            }
        }

        var entities: [ProposedEntity] = []
        for canonical in reconcile.canonicalEntities {
            let forms = [canonical.name] + canonical.aliases + canonical.mergedFrom
            var matches: [(Int, ExtractedScene, ExtractedEntity)] = []
            for form in forms {
                matches.append(contentsOf: extractedByKey[key(canonical.kind, form)] ?? [])
            }
            // A canonical entity can be mentioned by multiple aliases in one scene.
            // Emit one appearance for that scene, deterministically retaining the
            // strongest anchored mention.
            let unique = Dictionary(grouping: matches, by: { $0.1.sceneId })
                .values.compactMap { candidates in
                    candidates.sorted {
                        if $0.2.confidence != $1.2.confidence { return $0.2.confidence > $1.2.confidence }
                        if $0.0 != $1.0 { return $0.0 < $1.0 }
                        return $0.2.name < $1.2.name
                    }.first
                }
                .sorted { lhs, rhs in
                    if lhs.1.sceneOrdinal != rhs.1.sceneOrdinal { return lhs.1.sceneOrdinal < rhs.1.sceneOrdinal }
                    return lhs.0 < rhs.0
                }
            guard let best = unique.max(by: {
                if $0.2.confidence != $1.2.confidence { return $0.2.confidence < $1.2.confidence }
                return $0.0 > $1.0
            }) else { continue }
            let appearances = unique.map { _, scene, entity in
                ProposedAppearance(
                    sceneID: scene.sceneId,
                    role: entity.role,
                    evidence: .init(
                        sceneID: scene.sceneId,
                        quote: entity.evidenceQuote,
                        confidence: entity.confidence
                    )
                )
            }
            entities.append(ProposedEntity(
                kind: canonical.kind,
                name: canonical.name,
                aliases: Array(Set(canonical.aliases + canonical.mergedFrom)).sorted(),
                description: canonical.description.isEmpty ? best.2.description : canonical.description,
                evidence: .init(
                    sceneID: best.1.sceneId,
                    quote: best.2.evidenceQuote,
                    confidence: best.2.confidence
                ),
                appearances: appearances
            ))
        }

        let synopses = allScenes.map { _, scene in
            ProposedSynopsis(
                sceneID: scene.sceneId,
                text: scene.synopsis.text,
                evidence: .init(
                    sceneID: scene.sceneId,
                    quote: scene.synopsis.evidenceQuote,
                    confidence: scene.synopsis.confidence
                )
            )
        }.sorted { $0.sceneID.uuidString < $1.sceneID.uuidString }

        var states: [ProposedState] = []
        var events: [ProposedEvent] = []
        var relationships: [ProposedRelationship] = []
        for (_, scene) in allScenes.sorted(by: { $0.1.sceneOrdinal < $1.1.sceneOrdinal }) {
            let kinds = Dictionary(grouping: scene.entities, by: { EntityNormalization.normalize($0.name) })
                .compactMapValues { $0.count == 1 ? $0[0].kind : nil }
            for state in scene.states {
                guard let kind = kinds[EntityNormalization.normalize(state.entityName)] else { continue }
                states.append(.init(
                    entityKind: kind,
                    entityName: canonicalName(kind: kind, surface: state.entityName, reconcile: reconcile),
                    category: state.category,
                    description: state.description,
                    startSceneID: scene.sceneId,
                    evidence: .init(sceneID: scene.sceneId, quote: state.evidenceQuote, confidence: state.confidence)
                ))
            }
            for event in scene.events {
                let kind = event.entityName.flatMap { kinds[EntityNormalization.normalize($0)] }
                events.append(.init(
                    sceneID: scene.sceneId,
                    entityKind: kind,
                    entityName: event.entityName.map { surface in
                        kind.map { canonicalName(kind: $0, surface: surface, reconcile: reconcile) } ?? surface
                    },
                    description: event.description,
                    evidence: .init(sceneID: scene.sceneId, quote: event.evidenceQuote, confidence: event.confidence)
                ))
            }
            for relationship in scene.relationships {
                guard let fromKind = kinds[EntityNormalization.normalize(relationship.fromEntityName)],
                      let toKind = kinds[EntityNormalization.normalize(relationship.toEntityName)]
                else { continue }
                relationships.append(.init(
                    fromKind: fromKind,
                    fromName: canonicalName(kind: fromKind, surface: relationship.fromEntityName, reconcile: reconcile),
                    toKind: toKind,
                    toName: canonicalName(kind: toKind, surface: relationship.toEntityName, reconcile: reconcile),
                    kind: relationship.kind,
                    description: relationship.description,
                    evidence: .init(sceneID: scene.sceneId, quote: relationship.evidenceQuote, confidence: relationship.confidence)
                ))
            }
        }

        return try ExtractionProposal(
            scriptID: scriptID,
            scriptSHA256: scriptSHA256,
            settings: settings,
            mergeCandidates: reconcile.canonicalEntities.map {
                .init(existingID: $0.existingId, kind: $0.kind, name: $0.name, aliases: $0.aliases)
            },
            mergeSuggestions: reconcile.proposedMerges.map {
                .init(sourceID: $0.sourceId, targetID: $0.targetId, reason: $0.reason)
            },
            entities: entities,
            synopses: synopses,
            states: states,
            events: events,
            relationships: relationships,
            chunksFailed: chunksFailed,
            uncoveredSceneOrdinals: uncoveredSceneOrdinals
        )
    }

    private static func key(_ kind: EntityKind, _ name: String) -> String {
        "\(kind.rawValue):\(EntityNormalization.normalize(name))"
    }

    private static func canonicalName(kind: EntityKind, surface: String, reconcile: ReconcileResult) -> String {
        let normalized = EntityNormalization.normalize(surface)
        return reconcile.canonicalEntities.first { entity in
            entity.kind == kind && ([entity.name] + entity.aliases + entity.mergedFrom)
                .contains { EntityNormalization.normalize($0) == normalized }
        }?.name ?? surface
    }
}
