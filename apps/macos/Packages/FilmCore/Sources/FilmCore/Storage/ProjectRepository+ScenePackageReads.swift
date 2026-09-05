import Foundation
import GRDB

// The §7.5 scene-package reads (PHASE5_DESIGN §7.5; Plan 018 contract D).
//
// One graph, one derivation, one transaction — the Phase 4 posture: the asset-ready axis
// is read from Plan 017's derivation over the same graph load, never re-derived, and the
// package states always read against the project's active target profile P (§3.3).

extension ProjectRepository {
    /// `ProjectReading.scenePackages()` — every counted scene in ordinal order. Excluded
    /// scenes carry no summary; surfaces that list them take them from the readiness
    /// snapshot (§3.3).
    func scenePackages() throws -> [ScenePackageSummary] {
        try database.queue.read { db in
            let graph = try Self.readinessGraph(in: db)
            let readiness = Self.deriveReadiness(graph)

            let profileID = try String.fetchOne(
                db, sql: "SELECT generation_target_profile FROM projects"
            ) ?? TargetProfileCatalog.defaultProfileID
            let profile = TargetProfileCatalog.profile(id: profileID)
            let limit = profile?.imageReferenceLimit ?? 0

            var summaries: [ScenePackageSummary] = []
            for row in readiness.scenes where !row.isExcluded {
                let currentSet = try Self.currentScenePromptSet(
                    sceneID: row.sceneID, profileID: profileID, in: db
                )
                let staleReason = try currentSet.map {
                    try Self.scenePromptSetStaleReason($0, in: db)
                } ?? nil
                let plan = try Self.sceneReferencePlan(
                    sceneID: row.sceneID, graph: graph, in: db
                )
                summaries.append(
                    ScenePackageSummary(
                        sceneID: row.sceneID,
                        ordinal: row.ordinal,
                        heading: row.heading,
                        assetReadyState: row.state,
                        packageState: Self.scenePackageState(
                            assetReady: row.state == .assetReady,
                            activeProfile: profile,
                            currentPrompt: currentSet == nil ? nil : try Self.currentScenePrompt(
                                sceneID: row.sceneID, profileID: profileID, in: db
                            ),
                            staleReason: staleReason
                        ),
                        activeProfileID: profileID,
                        satisfiedCount: plan.count(where: \.isSatisfied),
                        plannedCount: plan.count,
                        referenceLimit: limit,
                        currentPromptNumber: currentSet?.setNumber
                    )
                )
            }
            return summaries
        }
    }

    /// `ProjectReading.scenePackageDetail(sceneID:)` — the §5.2 payload.
    func scenePackageDetail(sceneID: UUID) throws -> ScenePackageDetail {
        try database.queue.read { db in
            let graph = try Self.readinessGraph(in: db)
            guard let scene = graph.scenes.first(where: { $0.id == sceneID }) else {
                throw ProjectStoreError.sceneNotFound
            }

            // The asset-ready axis comes from Plan 017's derivation over this same load.
            let readiness = Self.deriveReadiness(graph)
            guard let readyRow = readiness.scenes.first(where: { $0.sceneID == sceneID }) else {
                throw ProjectStoreError.sceneNotFound
            }

            let profileID = try String.fetchOne(
                db, sql: "SELECT generation_target_profile FROM projects"
            ) ?? TargetProfileCatalog.defaultProfileID
            let profile = TargetProfileCatalog.profile(id: profileID)
            let creativeDirection = try String.fetchOne(
                db,
                sql: "SELECT prompt_direction FROM scenes WHERE id = ?",
                arguments: [sceneID.uuidString]
            ) ?? ""

            let plan = try Self.sceneReferencePlan(sceneID: sceneID, graph: graph, in: db)
            let continuity = try Self.sceneContinuityContext(
                sceneID: sceneID, graph: graph, in: db
            )

            let history = try Self.scenePromptSetRows(
                sceneID: sceneID, profileID: profileID, in: db
            )
            let current = history.last
            let staleReason = try current.map {
                try Self.scenePromptSetStaleReason($0, in: db)
            } ?? nil
            let currentSetDetail = try current.map { set in
                try Self.scenePromptSetDetail(set, staleReason: staleReason, in: db)
            }
            let currentDetail = try current.flatMap { set -> ScenePromptDetail? in
                guard let card = try Self.scenePromptCards(setID: set.id, in: db).first else {
                    return nil
                }
                let prompt = Self.legacyPromptForRead(set: set, card: card)
                return try Self.scenePromptDetail(
                    prompt, citations: Self.sceneCitationRows(promptID: card.id, in: db),
                    staleReason: staleReason
                )
            }

            return ScenePackageDetail(
                sceneID: scene.id,
                ordinal: scene.ordinal,
                heading: scene.heading,
                synopsis: scene.synopsis,
                creativeDirection: creativeDirection,
                assetReadyState: readyRow.state,
                packageState: Self.scenePackageState(
                    assetReady: readyRow.state == .assetReady,
                    activeProfile: profile,
                    currentSet: current,
                    staleReason: staleReason
                ),
                activeProfile: profile ?? TargetProfile(
                    id: profileID, displayName: profileID, imageReferenceLimit: 0,
                    durationRange: nil, aspectRatios: [], resolutions: []
                ),
                plan: plan,
                optionalRequirements: Self.sceneOptionalRequirements(
                    sceneID: sceneID, graph: graph
                ),
                referencesExceedProfileLimit: plan.count(where: \.isSatisfied)
                    > (profile?.imageReferenceLimit ?? 0),
                continuity: continuity,
                currentSet: currentSetDetail,
                currentPrompt: currentDetail,
                historyNumbers: history.map(\.setNumber)
            )
        }
    }

    /// Archived images for the scene's required references. The outer order is exactly the
    /// reference-plan order; versions are newest first so the most recent clear/replacement
    /// is the first restore target shown by presentation.
    func sceneReferenceArchives(sceneID: UUID) throws -> [SceneReferenceArchive] {
        try database.queue.read { db in
            let graph = try Self.readinessGraph(in: db)
            guard graph.scenes.contains(where: { $0.id == sceneID }) else {
                throw ProjectStoreError.sceneNotFound
            }
            let plan = try Self.sceneReferencePlan(sceneID: sceneID, graph: graph, in: db)
            return try plan.compactMap { reference in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT v.*
                        FROM assets a
                        JOIN asset_versions v ON v.asset_id = a.id
                        WHERE a.requirement_id = ? AND v.status = 'needs_review'
                        ORDER BY v.version_number DESC, v.id
                        """,
                    arguments: [reference.requirementID.uuidString]
                )
                let versions = try rows.map(decodeAssetVersion)
                guard !versions.isEmpty else { return nil }
                return SceneReferenceArchive(
                    requirementID: reference.requirementID,
                    requirementName: reference.requirementName,
                    entityName: reference.entityName,
                    class: reference.class,
                    versions: versions
                )
            }
        }
    }

    /// Builds a detail from a prompt row — the staleness reason arrives already derived
    /// by the caller, who needed it for the headline predicate too.
    static func scenePromptDetail(
        _ prompt: ScenePrompt,
        citations: [ScenePromptReference],
        staleReason: ScenePromptStaleReason?
    ) -> ScenePromptDetail {
        ScenePromptDetail(
            id: prompt.id,
            sceneID: prompt.sceneID,
            targetProfile: prompt.targetProfile,
            promptNumber: prompt.promptNumber,
            body: prompt.body,
            guidance: prompt.guidance,
            durationSeconds: prompt.durationSeconds,
            aspectRatio: prompt.aspectRatio,
            resolution: prompt.resolution,
            skillID: prompt.skillID,
            skillEntryPath: prompt.skillEntryPath,
            skillEntrySHA256: prompt.skillEntrySHA256,
            source: prompt.provenance.source,
            createdSource: prompt.provenance.createdSource,
            createdAt: prompt.provenance.createdAt,
            citations: citations.map { citation in
                ScenePromptDetail.Citation(
                    id: citation.id,
                    position: citation.position,
                    requirementID: citation.requirementID,
                    versionID: citation.versionID,
                    class: citation.class,
                    role: citation.role,
                    exclusion: citation.exclusion,
                    fidelity: citation.fidelity,
                    sha256: citation.sha256,
                    displayName: citation.displayName
                )
            },
            staleReason: staleReason
        )
    }

    /// `ProjectReading.scenePromptHistory(sceneID:targetProfile:)` — every prompt row of
    /// the pair, current included, by number ascending (§7.5).
    func scenePromptHistory(sceneID: UUID, targetProfile: String) throws -> [ScenePrompt] {
        try database.queue.read { db in
            try Self.scenePromptRows(sceneID: sceneID, profileID: targetProfile, in: db)
        }
    }

    /// Canonical Phase 5c history API.
    func scenePromptSetHistory(
        sceneID: UUID, targetProfile: String
    ) throws -> [ScenePromptSetDetail] {
        try database.queue.read { db in
            try Self.scenePromptSetRows(
                sceneID: sceneID, profileID: targetProfile, in: db
            ).map { set in
                try Self.scenePromptSetDetail(
                    set,
                    staleReason: Self.scenePromptSetStaleReason(set, in: db),
                    in: db
                )
            }
        }
    }

    private static func legacyPromptForRead(
        set: ScenePromptSet, card: ScenePromptCard
    ) -> ScenePrompt {
        ScenePrompt(
            id: set.id, projectID: set.projectID, sceneID: set.sceneID,
            targetProfile: set.targetProfile, promptNumber: set.setNumber,
            body: card.body, guidance: card.guidance,
            durationSeconds: card.durationSeconds, aspectRatio: card.aspectRatio,
            resolution: card.resolution, skillID: set.skillID,
            skillEntryPath: set.skillEntryPath, skillEntrySHA256: set.skillEntrySHA256,
            inputDigest: set.inputDigest, inputFormatVersion: set.inputFormatVersion,
            provenance: set.provenance
        )
    }

    /// `ProjectReading.styleBible()` — the project document; `''` when never set (§3.6).
    func styleBible() throws -> String {
        try database.queue.read { db in
            try String.fetchOne(db, sql: "SELECT style_bible FROM projects") ?? ""
        }
    }
}
