import Foundation
import GRDB

/// PHASE4_DESIGN §7.5's readiness reads (Plan 017 contracts A–B): the scene-side
/// derivation over `ManifestGraph`, loaded once in one read transaction, plus §3.5's
/// deterministic impact ranking.
///
/// **One graph, one derivation.** Everything any readiness surface shows comes out of one
/// `readinessGraph(in:)` load through one derivation function — the summary is a fold of
/// the per-scene rows, never a second query (§3.3). The scene-link loads reuse the shipped
/// predicates by name: the visible-role list is `ManifestQualification.visibleRoleSQLList`
/// and the tombstone filters are the same ones the forward read carries; none of them is
/// re-spelled here.
extension ProjectRepository {
    // MARK: - The snapshot the derivation runs over

    /// `ManifestGraph` plus the two scene-side loads (§3.2): the current script's scenes,
    /// ordinal ascending, and the (sceneID, requirementID) link pairs of §3.2's two
    /// branches.
    struct ReadinessGraph {
        let manifest: ManifestGraph
        /// The current script's scenes, ordinal ascending — preamble row included (it is
        /// excluded by rule, not by omission from the load).
        var scenes: [Scene] = []
        /// Canonical branch: requirements whose entity holds a non-rejected
        /// `scene_entities` row for the scene in a **visible** role (§3.2).
        var canonicalLinks: [UUID: Set<UUID>] = [:]
        /// Variant branch: non-rejected stored `asset_requirement_scenes` rows (§3.2).
        var variantLinks: [UUID: Set<UUID>] = [:]
        /// Human scene-specific removals. These subtract from either link branch without
        /// rewriting screenplay appearances or requirement membership elsewhere.
        var excludedLinks: [UUID: Set<UUID>] = [:]

        func linkedRequirements(of sceneID: UUID) -> Set<UUID> {
            (canonicalLinks[sceneID] ?? [])
                .union(variantLinks[sceneID] ?? [])
                .subtracting(excludedLinks[sceneID] ?? [])
        }
    }

    /// Loads `ReadinessGraph` inside the caller's read transaction.
    static func readinessGraph(in db: Database) throws -> ReadinessGraph {
        var graph = ReadinessGraph(manifest: try manifestGraph(in: db))

        guard let scriptRaw = try String.fetchOne(
            db, sql: "SELECT current_script_id FROM projects"
        ) else { return graph }

        graph.scenes = try Row
            .fetchAll(
                db,
                sql: "SELECT * FROM scenes WHERE script_id = ? ORDER BY ordinal",
                arguments: [scriptRaw]
            )
            .map(decodeScene)

        // Both loads scope to the current script's scenes and carry exactly the shipped
        // predicates: the role list is generated from `ManifestQualification.visibleRoles`,
        // and both tombstone filters match the forward read's (`requiredByScenes`).
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT scene_entities.scene_id AS scene_id,
                       asset_requirements.id AS requirement_id
                FROM scene_entities
                JOIN scenes ON scenes.id = scene_entities.scene_id
                JOIN asset_requirements ON asset_requirements.entity_id = scene_entities.entity_id
                WHERE scenes.script_id = ?
                  AND asset_requirements.tier = 'canonical'
                  AND scene_entities.role IN (\(ManifestQualification.visibleRoleSQLList))
                  AND scene_entities.review_state <> 'rejected'
                """,
            arguments: [scriptRaw]
        ) {
            let sceneID = try UUID.required(row["scene_id"])
            let requirementID = try UUID.required(row["requirement_id"])
            graph.canonicalLinks[sceneID, default: []].insert(requirementID)
        }

        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT asset_requirement_scenes.scene_id AS scene_id,
                       asset_requirement_scenes.requirement_id AS requirement_id
                FROM asset_requirement_scenes
                JOIN scenes ON scenes.id = asset_requirement_scenes.scene_id
                WHERE scenes.script_id = ?
                  AND asset_requirement_scenes.review_state <> 'rejected'
                """,
            arguments: [scriptRaw]
        ) {
            let sceneID = try UUID.required(row["scene_id"])
            let requirementID = try UUID.required(row["requirement_id"])
            graph.variantLinks[sceneID, default: []].insert(requirementID)
        }

        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT exclusion.scene_id, exclusion.requirement_id
                FROM scene_reference_exclusions exclusion
                JOIN scenes ON scenes.id = exclusion.scene_id
                WHERE scenes.script_id = ?
                """,
            arguments: [scriptRaw]
        ) {
            let sceneID = try UUID.required(row["scene_id"])
            let requirementID = try UUID.required(row["requirement_id"])
            graph.excludedLinks[sceneID, default: []].insert(requirementID)
        }

        return graph
    }

    // MARK: - The derivation (§3.3–§3.5)

    /// One scene's membership before the ranking pass orders its checklist.
    private struct SceneMembership {
        let scene: Scene
        let isExcluded: Bool
        let countedIDs: [UUID]
        let missingIDs: [UUID]
        let optionalRequirements: [SceneOptionalRequirement]
        let hasUnreviewedFacts: Bool

        var isAssetReady: Bool { missingIDs.isEmpty }
    }

    /// The one derivation function every readiness number flows through. Pure over the
    /// graph; no SQL ordering is trusted — every collection is ordered in Swift by a total
    /// key ending in a row id.
    static func deriveReadiness(_ graph: ReadinessGraph) -> ReadinessSnapshot {
        let manifest = graph.manifest

        func reference(_ requirementID: UUID) -> RequirementReference {
            let requirement = manifest.requirements[requirementID]
            return RequirementReference(
                requirementID: requirementID,
                entityName: requirement.flatMap { manifest.entities[$0.entityID]?.name } ?? "",
                requirementName: requirement?.name ?? ""
            )
        }

        // Pass 1 — per-scene membership under §3.4's rules.
        var memberships: [SceneMembership] = []
        // linked⁻¹(M): M's own scenes by the §3.2 branches — a blocker's reach covers its
        // own linked scenes, never its dependents' (§3.5).
        var linkedSceneIDsByRequirement: [UUID: [UUID]] = [:]

        for scene in graph.scenes {
            let excluded = scene.isOmitted || scene.ordinal == 0
            let linked = graph.linkedRequirements(of: scene.id)
                .sorted(by: { $0.uuidString < $1.uuidString })

            var countedIDs: [UUID] = []
            var optionalRows: [SceneOptionalRequirement] = []
            for requirementID in linked {
                guard let requirement = manifest.requirements[requirementID],
                      manifest.isActive(requirement)
                else { continue }
                if requirement.necessity == .optional {
                    optionalRows.append(
                        SceneOptionalRequirement(
                            requirementID: requirement.id,
                            entityName: manifest.entities[requirement.entityID]?.name ?? "",
                            requirementName: requirement.name,
                            tier: requirement.tier,
                            displayStatus: manifest.displayStatus(requirement),
                            hasUnreviewedFacts: manifest.hasUnreviewedFacts(requirement)
                        )
                    )
                } else {
                    countedIDs.append(requirement.id)
                    if manifest.isMissing(requirement) {
                        linkedSceneIDsByRequirement[requirement.id, default: []].append(scene.id)
                    }
                }
            }
            let missingIDs = countedIDs.filter { id in
                manifest.displayStatus(manifest.requirements[id]!) != .approved
            }

            memberships.append(
                SceneMembership(
                    scene: scene,
                    isExcluded: excluded,
                    countedIDs: countedIDs,
                    missingIDs: missingIDs,
                    optionalRequirements: optionalRows.sorted {
                        (
                            $0.entityName.lowercased(), $0.requirementName.lowercased(),
                            $0.requirementID.uuidString
                        ) < (
                            $1.entityName.lowercased(), $1.requirementName.lowercased(),
                            $1.requirementID.uuidString
                        )
                    },
                    hasUnreviewedFacts: countedIDs.contains { id in
                        guard let requirement = manifest.requirements[id] else { return false }
                        return requirement.provenance.reviewState == .proposed
                            || manifest.hasUnreviewedFacts(requirement)
                    }
                )
            )
        }

        // Pass 2 — contract B's figures over the project Missing set, then the five-key
        // order: unfinishedSceneCount descending, unblocks count descending, canonical
        // tier first, the shipped dependency rank, requirement id — total and stable.
        let missingRequirements = manifest.order
            .compactMap { manifest.requirements[$0] }
            .filter(manifest.isMissing)
        let unsatisfiedEdgesByRequirement: [UUID: [AssetDependency]] = Dictionary(
            uniqueKeysWithValues:
                missingRequirements.map { requirement in
                    (
                        requirement.id,
                        manifest.dependencies
                            .filter { $0.requirementID == requirement.id }
                            .filter { !manifest.isSatisfied(dependsOn: $0.dependsOnRequirementID) }
                            .sorted {
                                ($0.provenance.createdAt, $0.id.uuidString)
                                    < ($1.provenance.createdAt, $1.id.uuidString)
                            }
                    )
                }
        )
        // The sole-unsatisfied rule (§14.1), literal by owner decision: a dependent whose
        // unsatisfied set holds M **and something else** is not unblocked by approving M,
        // so it counts for neither blocker until only one remains.
        let unblocksCount: [UUID: Int] = Dictionary(
            uniqueKeysWithValues:
                missingRequirements.map { requirement in
                    (
                        requirement.id,
                        missingRequirements.count { other in
                            Set(
                                unsatisfiedEdgesByRequirement[other.id]?
                                    .map(\.dependsOnRequirementID) ?? []
                            ) == Set([requirement.id])
                        }
                    )
                }
        )
        let rank = dependencyRanks(of: missingRequirements.map(\.id), in: manifest)

        let impacts: [UnblockerImpact] = missingRequirements
            .map { requirement -> (impact: UnblockerImpact, key: (Int, Int, Int, Int, String)) in
                let unfinished = (linkedSceneIDsByRequirement[requirement.id] ?? [])
                    .compactMap { id in memberships.first { $0.scene.id == id } }
                    .filter { !$0.isExcluded && !$0.isAssetReady }
                    .map(\.scene.id)
                    .sorted { $0.uuidString < $1.uuidString }
                let impact = UnblockerImpact(
                    requirementID: requirement.id,
                    entityName: manifest.entities[requirement.entityID]?.name ?? "",
                    requirementName: requirement.name,
                    tier: requirement.tier,
                    unfinishedSceneCount: unfinished.count,
                    unfinishedSceneIDs: unfinished,
                    unblocksRequirementCount: unblocksCount[requirement.id] ?? 0
                )
                return (
                    impact,
                    (
                        -impact.unfinishedSceneCount,
                        -impact.unblocksRequirementCount,
                        requirement.tier == .canonical ? 0 : 1,
                        rank[requirement.id] ?? 0,
                        requirement.id.uuidString
                    )
                )
            }
            .sorted { $0.key < $1.key }
            .map(\.impact)
        let impactIndex = Dictionary(
            uniqueKeysWithValues:
                impacts.enumerated().map { ($0.element.requirementID, $0.offset) }
        )

        // Pass 3 — assemble the rows: checklist rows in ranking order, state per §3.3,
        // blocked references named from the snapshot alone.
        let rows: [SceneReadiness] = memberships.map { membership in
            let orderedMissing = membership.missingIDs.sorted { left, right in
                let leftIndex = impactIndex[left] ?? Int.max
                let rightIndex = impactIndex[right] ?? Int.max
                return leftIndex != rightIndex
                    ? leftIndex < rightIndex
                    : left.uuidString < right.uuidString
            }
            let missingRows = orderedMissing.map { requirementID in
                let requirement = manifest.requirements[requirementID]!
                return SceneMissingRequirement(
                    requirementID: requirement.id,
                    entityName: manifest.entities[requirement.entityID]?.name ?? "",
                    requirementName: requirement.name,
                    tier: requirement.tier,
                    necessity: requirement.necessity,
                    displayStatus: manifest.displayStatus(requirement),
                    isBlocked: manifest.isBlocked(requirement),
                    blockedBy: (unsatisfiedEdgesByRequirement[requirement.id] ?? []).compactMap {
                        edge in
                        manifest.requirements[edge.dependsOnRequirementID].map { target in
                            RequirementReference(
                                requirementID: target.id,
                                entityName: manifest.entities[target.entityID]?.name ?? "",
                                requirementName: target.name
                            )
                        }
                    }
                )
            }
            let state: SceneReadinessState =
                missingRows.isEmpty
                ? .assetReady
                : (missingRows.contains(where: \.isBlocked) ? .blocked : .partial)
            return SceneReadiness(
                sceneID: membership.scene.id,
                ordinal: membership.scene.ordinal,
                heading: membership.scene.heading,
                isOmitted: membership.scene.isOmitted,
                isExcluded: membership.isExcluded,
                state: state,
                requiredCount: membership.countedIDs.count,
                readyCount: membership.countedIDs.count - membership.missingIDs.count,
                missing: missingRows,
                optionalRequirements: membership.optionalRequirements,
                hasUnreviewedFacts: membership.hasUnreviewedFacts
            )
        }

        // The summary is the fold (§3.3); the asset figures ride the same graph in the
        // ManifestCounts frame — active requirements, all necessities (§5.3).
        var assetReadyCount = 0
        var partialCount = 0
        var blockedCount = 0
        var excludedCount = 0
        for row in rows {
            if row.isExcluded {
                excludedCount += 1
            } else {
                switch row.state {
                case .assetReady: assetReadyCount += 1
                case .partial: partialCount += 1
                case .blocked: blockedCount += 1
                }
            }
        }
        let active = manifest.order
            .compactMap { manifest.requirements[$0] }
            .filter(manifest.isActive)
        let summary = ReadinessSummary(
            assetReady: assetReadyCount,
            partial: partialCount,
            blocked: blockedCount,
            excluded: excludedCount,
            sceneTotal: rows.count,
            requirementsApproved: active.count { manifest.displayStatus($0) == .approved },
            requirementsTotal: active.count,
            hasUnreviewedFacts: rows.contains { !$0.isExcluded && $0.hasUnreviewedFacts }
        )

        return ReadinessSnapshot(scenes: rows, summary: summary, impacts: impacts)
    }

    // MARK: - §7.5's read

    /// `ProjectReading.readinessSnapshot()` — per-scene rows, summary fold, and impact
    /// ranking, from one `readinessGraph` load in one read transaction (§7.5). The current
    /// script's scenes, ordinal ascending.
    func readinessSnapshot() throws -> ReadinessSnapshot {
        try database.queue.read { db in
            Self.deriveReadiness(try Self.readinessGraph(in: db))
        }
    }
}
