import Foundation
import GRDB

/// The §7.6 manifest reads (PHASE2_DESIGN §3.3, §3.5, §5.2, §5.3, §6.1, §6.4; Plan 009
/// contract C).
///
/// They live beside the Phase 1 reads in their own file for the same reason those do: Plan
/// 010's UI reads them, `ProjectSession` stays a thin actor, and Plan 010's operations touch
/// none of this.
///
/// **One implementation of each rule.** Qualification and §6.4's activity predicate are
/// `ManifestQualification`'s; nothing here re-spells either in SQL. The only SQL that knows
/// about §3.3 at all is the visible-role scene count, and its `IN (…)` list is generated
/// from `ManifestQualification.visibleRoles`.
extension ProjectRepository {
    // MARK: - The snapshot the derivations run over

    /// Every row the derived reads need, loaded once inside one read transaction.
    ///
    /// A manifest is bounded by one screenplay's entities, so loading it whole and deriving
    /// in Swift is both cheap and the only way to keep §6.4's predicate in exactly one
    /// place: a SQL `WHERE` would be a second implementation of it.
    struct ManifestGraph {
        var entities: [UUID: Entity] = [:]
        /// Distinct scenes per entity in a **visible** role (§3.3).
        var visibleSceneCounts: [UUID: Int] = [:]
        var requirements: [UUID: AssetRequirement] = [:]
        /// Requirement ids in list order: entity kind, entity name, canonical before
        /// variant, template `sort_order`, then requirement name.
        var order: [UUID] = []
        var types: [UUID: AssetRequirementType] = [:]
        /// Assets keyed by their requirement (`assets.requirement_id` is `UNIQUE`).
        var assetsByRequirement: [UUID: Asset] = [:]
        /// Asset ids holding an `approved` version row.
        var assetsWithApprovedVersion: Set<UUID> = []
        /// Stored scene links per **variant** requirement (§5.2), rejected links excluded.
        var variantSceneCounts: [UUID: Int] = [:]
        var dependencies: [AssetDependency] = []
        /// Requirement ids named by any `locks` row.
        var lockedRequirements: Set<UUID> = []
        /// Requirement ids with at least one basis row whose underlying fact is still
        /// `proposed` (§3.7).
        var requirementsWithProposedBasis: Set<UUID> = []

        // MARK: Derivations — every one of them through `ManifestQualification`

        func entity(of requirement: AssetRequirement) -> Entity? { entities[requirement.entityID] }

        /// §6.4's predicate. A requirement whose entity row is gone cannot be active.
        func isActive(_ requirement: AssetRequirement) -> Bool {
            guard let entity = entity(of: requirement) else { return false }
            return ManifestQualification.isActive(requirement: requirement, entity: entity)
        }

        /// §3.3 + §3.4, for the entity behind a requirement or for a badge.
        func qualifies(_ entity: Entity) -> Bool {
            ManifestQualification.qualifies(
                entity: entity,
                visibleSceneCount: visibleSceneCounts[entity.id] ?? 0
            )
        }

        /// §6.1: the asset's status, or Needed when there is no asset row at all.
        func displayStatus(_ requirement: AssetRequirement) -> AssetStatus {
            assetsByRequirement[requirement.id]?.status ?? .needed
        }

        func isStale(_ requirement: AssetRequirement) -> Bool {
            assetsByRequirement[requirement.id]?.isStale ?? false
        }

        /// §6.4's Missing: active, `required`, and the asset is absent or not Approved.
        func isMissing(_ requirement: AssetRequirement) -> Bool {
            isActive(requirement)
                && requirement.necessity == .required
                && displayStatus(requirement) != .approved
        }

        /// §3.5: a dependency is satisfied when its **target** holds an Approved asset
        /// version, or the target is inactive under the full §6.4 predicate — a slot the
        /// filmmaker retired, at either level, can never block downstream work forever.
        func isSatisfied(dependsOn targetID: UUID) -> Bool {
            guard let target = requirements[targetID] else {
                // The row is gone; nothing downstream can wait on it.
                return true
            }
            guard isActive(target) else { return true }
            guard let asset = assetsByRequirement[target.id] else { return false }
            return assetsWithApprovedVersion.contains(asset.id)
        }

        /// The unsatisfied dependency targets of one requirement, in row order.
        func unsatisfiedDependencies(of requirementID: UUID) -> [UUID] {
            dependencies
                .filter { $0.requirementID == requirementID }
                .map(\.dependsOnRequirementID)
                .filter { !isSatisfied(dependsOn: $0) }
        }

        /// §6.4's Blocked: **a missing requirement** with an unsatisfied dependency, so
        /// Blocked is a subset of Missing by construction.
        func isBlocked(_ requirement: AssetRequirement) -> Bool {
            isMissing(requirement) && !unsatisfiedDependencies(of: requirement.id).isEmpty
        }

        /// §3.7's "based on unreviewed AI facts": the subject entity, or any basis row's
        /// underlying fact, is still `proposed`. Accepting the underlying fact clears it.
        func hasUnreviewedFacts(_ requirement: AssetRequirement) -> Bool {
            if entity(of: requirement)?.provenance.reviewState == .proposed { return true }
            return requirementsWithProposedBasis.contains(requirement.id)
        }

        /// §5.3's badges, as read-layer facts. Only canonical rows carry them: the 2+ rule
        /// and the template govern the canonical tier, never a variant's subset judgment.
        func drift(_ requirement: AssetRequirement) -> RequirementDrift {
            guard requirement.tier == .canonical, let entity = entity(of: requirement) else {
                return []
            }
            var drift: RequirementDrift = []
            if entity.manifestInclusion == .never {
                drift.insert(.suppressed)
            } else if !qualifies(entity) {
                drift.insert(.noLongerQualifies)
            }
            if let typeID = requirement.typeID, types[typeID]?.isEnabled == false {
                drift.insert(.templateEntryDisabled)
            }
            return drift
        }

        /// How many scenes a requirement is required by: derived from `scene_entities` for
        /// a canonical row, the stored links for a variant (§5.2).
        func requiredBySceneCount(_ requirement: AssetRequirement) -> Int {
            switch requirement.tier {
            case .canonical: visibleSceneCounts[requirement.entityID] ?? 0
            case .variant: variantSceneCounts[requirement.id] ?? 0
            }
        }

        func summary(of requirement: AssetRequirement) -> RequirementSummary {
            let entity = entity(of: requirement)
            let type = requirement.typeID.flatMap { types[$0] }
            return RequirementSummary(
                id: requirement.id,
                entityID: requirement.entityID,
                entityKind: entity?.kind ?? .object,
                entityName: entity?.name ?? "",
                tier: requirement.tier,
                typeID: requirement.typeID,
                typeCode: requirement.outfitSourceVersionID == nil ? type?.code : "full_body",
                name: requirement.name,
                necessity: requirement.necessity,
                reviewState: requirement.provenance.reviewState,
                isActive: isActive(requirement),
                displayStatus: displayStatus(requirement),
                isStale: isStale(requirement),
                isMissing: isMissing(requirement),
                isBlocked: isBlocked(requirement),
                isLocked: lockedRequirements.contains(requirement.id),
                hasUnreviewedFacts: hasUnreviewedFacts(requirement),
                requiredBySceneCount: requiredBySceneCount(requirement),
                drift: drift(requirement)
            )
        }
    }

    /// Loads `ManifestGraph` inside the caller's read transaction.
    static func manifestGraph(in db: Database) throws -> ManifestGraph {
        var graph = ManifestGraph()

        for row in try Row.fetchAll(db, sql: "SELECT * FROM entities") {
            let entity = try decodeEntity(row)
            graph.entities[entity.id] = entity
        }

        // The only SQL that knows §3.3's role filter, and its list is generated from
        // `ManifestQualification.visibleRoles`. Rejected appearance tombstones do not
        // count: a rejected row says the appearance is not real.
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT entity_id, COUNT(DISTINCT scene_id) AS scene_count
                FROM scene_entities
                WHERE role IN (\(ManifestQualification.visibleRoleSQLList))
                  AND review_state <> 'rejected'
                GROUP BY entity_id
                """
        ) {
            graph.visibleSceneCounts[try UUID.required(row["entity_id"])] = row["scene_count"]
        }

        for row in try Row.fetchAll(db, sql: "SELECT * FROM asset_requirement_types") {
            let type = try decodeAssetRequirementType(row)
            graph.types[type.id] = type
        }

        for row in try Row.fetchAll(db, sql: "SELECT * FROM asset_requirements") {
            let requirement = try decodeAssetRequirement(row)
            graph.requirements[requirement.id] = requirement
        }
        graph.order = Self.listOrder(of: graph)

        for row in try Row.fetchAll(db, sql: "SELECT * FROM assets") {
            let asset = try decodeAsset(row)
            graph.assetsByRequirement[asset.requirementID] = asset
        }
        for raw in try String.fetchAll(
            db,
            sql: "SELECT DISTINCT asset_id FROM asset_versions WHERE status = 'approved'"
        ) {
            graph.assetsWithApprovedVersion.insert(try UUID.required(raw))
        }

        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT requirement_id, COUNT(DISTINCT scene_id) AS scene_count
                FROM asset_requirement_scenes
                WHERE review_state <> 'rejected'
                GROUP BY requirement_id
                """
        ) {
            graph.variantSceneCounts[try UUID.required(row["requirement_id"])] = row["scene_count"]
        }

        // PHASE3_DESIGN §3.3's Phase 2 defect repair: `removeDependency` *tombstones*
        // `ai`/`parser` edges rather than deleting them, so the unfiltered load counted
        // dependencies the filmmaker removed — in `dependsOn`, `dependents`,
        // `unsatisfiedDependencies`, and therefore Blocked. The sibling scene-link load
        // above and `RequirementOperations.activeEdges` both already filter.
        graph.dependencies = try Row
            .fetchAll(
                db,
                sql: """
                    SELECT * FROM asset_dependencies
                    WHERE review_state <> 'rejected'
                    ORDER BY rowid
                    """
            )
            .map(decodeAssetDependency)

        for raw in try String.fetchAll(
            db,
            sql: "SELECT DISTINCT subject_id FROM locks WHERE subject_kind = 'requirement'"
        ) {
            graph.lockedRequirements.insert(try UUID.required(raw))
        }

        // §3.7's flag, resolved through the three citable fact tables. Basis rows carry no
        // foreign key (§4.3), so the join is on `(subject_kind, subject_id)`.
        for raw in try String.fetchAll(db, sql: Self.proposedBasisSQL) {
            graph.requirementsWithProposedBasis.insert(try UUID.required(raw))
        }

        return graph
    }

    /// Requirement ids whose basis cites a still-`proposed` fact.
    private static let proposedBasisSQL = """
        SELECT DISTINCT basis.requirement_id FROM asset_requirement_basis AS basis
        LEFT JOIN entity_states AS state
            ON basis.subject_kind = 'state' AND state.id = basis.subject_id
        LEFT JOIN continuity_events AS event
            ON basis.subject_kind = 'event' AND event.id = basis.subject_id
        LEFT JOIN scene_entities AS appearance
            ON basis.subject_kind = 'appearance' AND appearance.id = basis.subject_id
        WHERE COALESCE(state.review_state, event.review_state, appearance.review_state) = 'proposed'
        """

    /// The list order every requirement read returns: entity kind, entity name, canonical
    /// before variant, the template entry's `sort_order`, then the requirement's name.
    private static func listOrder(of graph: ManifestGraph) -> [UUID] {
        func key(_ requirement: AssetRequirement) -> (Int, String, Int, Int, String, String) {
            let entity = graph.entities[requirement.entityID]
            let kindIndex = entity.map { EntityKind.allCases.firstIndex(of: $0.kind) ?? 0 } ?? 0
            let sortOrder = requirement.typeID.flatMap { graph.types[$0]?.sortOrder } ?? 0
            return (
                kindIndex,
                (entity?.name ?? "").lowercased(),
                requirement.tier == .canonical ? 0 : 1,
                sortOrder,
                requirement.nameNormalized,
                requirement.id.uuidString
            )
        }
        return graph.requirements.values
            .sorted { key($0) < key($1) }
            .map(\.id)
    }

    // MARK: - §7.6 reads

    /// One entity's requirement rows, in list order.
    func requirements(entityID: UUID, includeRejected: Bool) throws -> [AssetRequirement] {
        try database.queue.read { db in
            let graph = try Self.manifestGraph(in: db)
            return graph.order
                .compactMap { graph.requirements[$0] }
                .filter { $0.entityID == entityID }
                .filter { includeRejected || $0.provenance.reviewState != .rejected }
        }
    }

    /// The manifest list (§7.6). `kind` filters on the **entity's** kind, `reviewState` on
    /// the requirement's own PROV state; rejected rows are excluded unless asked for,
    /// exactly as the entity reads do.
    func requirementSummaries(
        kind: EntityKind?,
        tier: AssetRequirementTier?,
        reviewState: ReviewState?,
        includeRejected: Bool
    ) throws -> [RequirementSummary] {
        try database.queue.read { db in
            let graph = try Self.manifestGraph(in: db)
            return graph.order
                .compactMap { graph.requirements[$0] }
                .filter { requirement in
                    if let tier, requirement.tier != tier { return false }
                    if let reviewState, requirement.provenance.reviewState != reviewState {
                        return false
                    }
                    if !includeRejected, requirement.provenance.reviewState == .rejected {
                        return false
                    }
                    if let kind, graph.entities[requirement.entityID]?.kind != kind { return false }
                    return true
                }
                .map(graph.summary(of:))
        }
    }

    /// The inspector shape (§7.6): scene links stored or derived per tier, basis rows joined
    /// to their facts' evidence, dependencies both directions, the asset and its versions,
    /// locks, and the derived flags.
    func requirementDetail(id: UUID) throws -> RequirementDetail {
        try database.queue.read { db in
            let graph = try Self.manifestGraph(in: db)
            guard let requirement = graph.requirements[id],
                  let entity = graph.entities[requirement.entityID]
            else { throw ProjectStoreError.requirementNotFound }

            let requiredBy = try Self.requiredByScenes(requirement, in: db)
            let basis = try Self.basisDetails(of: requirement.id, in: db)

            func edge(_ dependency: AssetDependency, otherID: UUID, targetID: UUID)
                -> RequirementDependencyEdge
            {
                let other = graph.requirements[otherID]
                let otherEntity = other.flatMap { graph.entities[$0.entityID] }
                return RequirementDependencyEdge(
                    dependency: dependency,
                    otherRequirementID: otherID,
                    otherRequirementName: other?.name ?? "",
                    otherEntityName: otherEntity?.name ?? "",
                    isOtherActive: other.map(graph.isActive) ?? false,
                    isSatisfied: graph.isSatisfied(dependsOn: targetID)
                )
            }
            let dependsOn = graph.dependencies
                .filter { $0.requirementID == id }
                .map { edge($0, otherID: $0.dependsOnRequirementID, targetID: $0.dependsOnRequirementID) }
            let dependents = graph.dependencies
                .filter { $0.dependsOnRequirementID == id }
                .map { edge($0, otherID: $0.requirementID, targetID: id) }

            let asset = graph.assetsByRequirement[id]
            let versions = try asset.map { try Self.versions(of: $0.id, in: db) } ?? []
            let locks = try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT * FROM locks
                        WHERE subject_kind = 'requirement' AND subject_id = ?
                        ORDER BY field
                        """,
                    arguments: [id.uuidString]
                )
                .map(decodeLock)

            // PHASE3_DESIGN §3.3/§4.4 (Plan 013 contract C): the generation gate, the
            // planned dependencies with their dense designators, and the prompt surface.
            let unsatisfied = graph.unsatisfiedDependencies(of: id)
            let planned = try AssetPromptInputBuilder.plannedDependencies(
                of: requirement, graph: graph, in: db
            )
            let prompts = try Self.promptRows(requirementID: id, in: db)
            let current = prompts.last
            let currentDetail = try current.map { prompt in
                try Self.promptDetail(
                    prompt,
                    citations: Self.citationRows(promptID: prompt.id, in: db),
                    in: db
                )
            }

            return RequirementDetail(
                requirement: requirement,
                entity: entity,
                type: requirement.typeID.flatMap { graph.types[$0] },
                requiredBy: requiredBy,
                basis: basis,
                dependsOn: dependsOn,
                dependents: dependents,
                asset: asset,
                versions: versions,
                locks: locks,
                isActive: graph.isActive(requirement),
                isMissing: graph.isMissing(requirement),
                isBlocked: graph.isBlocked(requirement),
                displayStatus: graph.displayStatus(requirement),
                isStale: graph.isStale(requirement),
                hasUnreviewedFacts: graph.hasUnreviewedFacts(requirement),
                drift: graph.drift(requirement),
                generationBlockedBy: unsatisfied,
                plannedDependencies: planned,
                currentPrompt: currentDetail,
                promptCount: prompts.count,
                inProgressSince: try asset.map { try Self.inProgressSince(of: $0.id, in: db) } ?? nil,
                visualAmendments: try Self.activeVisualAmendments(
                    for: requirement,
                    entity: entity,
                    graph: graph,
                    in: db
                )
            )
        }
    }

    func referenceImageGenerationContext(
        requirementID: UUID,
        generationPromptBody: String? = nil,
        includeCurrentImage: Bool = false
    ) throws -> ReferenceImageGenerationContext {
        try database.queue.read { db in
            try Self.referenceImageGenerationContext(
                requirementID: requirementID,
                generationPromptBodySHA256: generationPromptBody.map {
                    Data($0.utf8).sha256Hex
                },
                includeCurrentImage: includeCurrentImage,
                in: db
            )
        }
    }

    func referenceImageCreationRefusals(
        requirementIDs: [UUID]
    ) throws -> [UUID: String] {
        try database.queue.read { db in
            let graph = try Self.manifestGraph(in: db)
            var result: [UUID: String] = [:]
            for requirementID in requirementIDs {
                guard let requirement = graph.requirements[requirementID],
                      graph.isActive(requirement),
                      requirement.tier == .variant
                else { continue }
                let planned = try AssetPromptInputBuilder.plannedDependencies(
                    of: requirement, graph: graph, in: db
                )
                guard let missing = planned.first(where: { $0.isSatisfied == false }) else {
                    continue
                }
                result[requirementID] = ProjectStoreError.promptRequirementBlocked(
                    dependencyName: missing.requirementName
                ).errorDescription
            }
            return result
        }
    }

    /// Transaction-scoped form used both by the launch read and by the grouped import's
    /// commit-token revalidation.
    static func referenceImageGenerationContext(
        requirementID: UUID,
        generationPromptBodySHA256: String? = nil,
        includeCurrentImage: Bool = false,
        in db: Database
    ) throws -> ReferenceImageGenerationContext {
        let graph = try manifestGraph(in: db)
        guard let requirement = graph.requirements[requirementID],
              let entity = graph.entities[requirement.entityID]
        else { throw ProjectStoreError.requirementNotFound }
        guard graph.isActive(requirement) else {
            throw ProjectStoreError.requirementInactive(requirementID: requirementID)
        }
        guard let prompt = try promptRows(requirementID: requirementID, in: db).last else {
            throw ProjectStoreError.promptNotFound
        }

        let planned = try AssetPromptInputBuilder.plannedDependencies(
            of: requirement, graph: graph, in: db
        )
        let firstMissing = planned.first(where: { $0.isSatisfied == false })
        let refusalReason = firstMissing.flatMap {
            ProjectStoreError.promptRequirementBlocked(
                dependencyName: $0.requirementName
            ).errorDescription
        }
        var dependencies = try planned.compactMap { dependency
            -> ReferenceImageGenerationDependency? in
            guard let approved = dependency.approvedVersion else { return nil }
            guard let byteCount = try Int.fetchOne(
                db,
                sql: "SELECT byte_count FROM asset_versions WHERE id = ?",
                arguments: [approved.versionID.uuidString]
            ) else { throw ProjectStoreError.assetVersionNotFound }
            return ReferenceImageGenerationDependency(
                requirementID: dependency.requirementID,
                requirementName: dependency.requirementName,
                entityKind: graph.requirements[dependency.requirementID]
                    .flatMap { graph.entities[$0.entityID] }?.kind ?? .object,
                versionID: approved.versionID,
                sha256: approved.sha256,
                byteCount: byteCount,
                relativePath: try RelativeProjectPath(approved.relativePath),
                promptBody: try promptRows(
                    requirementID: dependency.requirementID,
                    in: db
                ).last?.body
            )
        }
        let currentVersionID: UUID?
        if let asset = graph.assetsByRequirement[requirementID] {
            currentVersionID = try AssetOperations.approvedVersionID(assetID: asset.id, in: db)
        } else {
            currentVersionID = nil
        }
        if includeCurrentImage {
            guard let currentVersionID,
                  let current = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM asset_versions WHERE id = ?",
                    arguments: [currentVersionID.uuidString]
                  )
            else {
                throw ProjectStoreError.assetOperationRefused(
                    reason: "This reference has no current image to include. Add or restore one first."
                )
            }
            dependencies.insert(
                ReferenceImageGenerationDependency(
                    requirementID: requirementID,
                    requirementName: requirement.name,
                    entityKind: entity.kind,
                    versionID: currentVersionID,
                    sha256: current["sha256"],
                    byteCount: current["byte_count"],
                    relativePath: try RelativeProjectPath(current["relative_path"]),
                    promptBody: prompt.body
                ),
                at: 0
            )
        }
        let sourcePromptBodySHA256 = Data(prompt.body.utf8).sha256Hex
        let activeVisualAmendments = try activeVisualAmendments(
            for: requirement,
            entity: entity,
            graph: graph,
            in: db
        )
        return ReferenceImageGenerationContext(
            requirementID: requirementID,
            promptID: prompt.id,
            sourcePromptBodySHA256: sourcePromptBodySHA256,
            promptBodySHA256: generationPromptBodySHA256 ?? sourcePromptBodySHA256,
            expectedCurrentVersionID: currentVersionID,
            includesCurrentImage: includeCurrentImage,
            tier: requirement.tier,
            entityKind: entity.kind,
            orderedDependencies: dependencies,
            activeVisualAmendments: activeVisualAmendments,
            refusalReason: refusalReason
        )
    }

    /// Derives amendments only through currently approved image lineages. Character-wide
    /// amendments from active canonical siblings join the target's own local lineage;
    /// requirement-scoped edits never escape their source slot.
    private static func activeVisualAmendments(
        for requirement: AssetRequirement,
        entity: Entity,
        graph: ManifestGraph,
        in db: Database
    ) throws -> [ReferenceVisualAmendment] {
        var sourceIDs: Set<UUID> = [requirement.id]
        if entity.kind == .character {
            sourceIDs.formUnion(graph.requirements.values.compactMap { candidate in
                candidate.entityID == entity.id
                    && candidate.tier == .canonical
                    && (requirement.outfitSourceVersionID == nil
                        || candidate.typeID.flatMap { graph.types[$0]?.code } == "face_closeup")
                    && graph.isActive(candidate)
                    ? candidate.id
                    : nil
            })
        }

        var amendments: [ReferenceVisualAmendment] = []
        for sourceID in sourceIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let asset = graph.assetsByRequirement[sourceID],
                  let currentVersionID = try AssetOperations.approvedVersionID(
                    assetID: asset.id, in: db
                  )
            else { continue }

            guard let currentRun = try Row.fetchOne(
                db,
                sql: """
                    SELECT run.*, version.id AS version_id
                    FROM asset_versions version
                    JOIN image_generation_runs run
                      ON run.id = version.image_generation_run_id
                    WHERE version.id = ?
                    """,
                arguments: [currentVersionID.uuidString]
            ) else { continue }
            let currentRunID: String = currentRun["id"]

            if let instruction: String = currentRun["visual_amendment"] {
                guard let scope = VisualAmendmentScope(
                    rawValue: currentRun["visual_amendment_scope"]
                ) else { throw ProjectStoreError.invalidBundle }
                if sourceID == requirement.id || scope == .characterBundle {
                    amendments.append(ReferenceVisualAmendment(
                        runID: try UUID.required(currentRunID),
                        requirementID: try UUID.required(currentRun["requirement_id"]),
                        versionID: try UUID.required(currentRun["version_id"]),
                        instruction: instruction,
                        scope: scope,
                        createdAt: try UTCDate.date(from: currentRun["created_at"])
                    ))
                }
            }

            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT amendment.*
                    FROM image_generation_amendments amendment
                    WHERE amendment.run_id = ?
                    ORDER BY amendment.position
                    """,
                arguments: [currentRunID]
            ) {
                guard let scope = VisualAmendmentScope(rawValue: row["scope"])
                else { throw ProjectStoreError.invalidBundle }
                if sourceID != requirement.id, scope != .characterBundle { continue }
                amendments.append(ReferenceVisualAmendment(
                    runID: try UUID.required(row["amendment_run_id"]),
                    requirementID: try UUID.required(row["requirement_id"]),
                    versionID: try UUID.required(row["version_id"]),
                    instruction: row["instruction"],
                    scope: scope,
                    createdAt: try UTCDate.date(from: row["created_at"])
                ))
            }
        }
        var seen: Set<UUID> = []
        return amendments.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.runID.uuidString < $1.runID.uuidString
        }.filter { seen.insert($0.runID).inserted }
    }

    /// Every prompt row of one requirement, by number (§3.2) — current last.
    static func promptRows(requirementID: UUID, in db: Database) throws -> [AssetPrompt] {
        try Row
            .fetchAll(
                db,
                sql: "SELECT * FROM asset_prompts WHERE requirement_id = ? ORDER BY prompt_number",
                arguments: [requirementID.uuidString]
            )
            .map(decodeAssetPrompt)
    }

    /// A prompt's citation rows, by position (§3.3's @Image order).
    static func citationRows(promptID: UUID, in db: Database) throws -> [AssetPromptReference] {
        try Row
            .fetchAll(
                db,
                sql: "SELECT * FROM asset_prompt_references WHERE prompt_id = ? ORDER BY position",
                arguments: [promptID.uuidString]
            )
            .map(decodeAssetPromptReference)
    }

    /// The §6.1 marker on an asset row.
    static func inProgressSince(of assetID: UUID, in db: Database) throws -> Date? {
        guard let raw = try String.fetchOne(
            db,
            sql: "SELECT in_progress_since FROM assets WHERE id = ?",
            arguments: [assetID.uuidString]
        ) else { return nil }
        return try UTCDate.date(from: raw)
    }

    /// Builds a detail from a prompt row, deriving §3.4's staleness: stale when the
    /// rebuilt digest differs **or** the recorded input format is older than the
    /// builder's — the mismatch reading stale with the "older input format" reason
    /// rather than as a false fresh.
    static func promptDetail(
        _ prompt: AssetPrompt,
        citations: [AssetPromptReference],
        in db: Database
    ) throws -> AssetPromptDetail {
        var isStale = prompt.inputFormatVersion != AssetPromptInputBuilder.schemaVersion
        if !isStale {
            let rebuilt = try AssetPromptInputBuilder.snapshot(
                requirementID: prompt.requirementID, in: db
            )
            isStale = rebuilt.digest != prompt.inputDigest
        }
        return AssetPromptDetail(
            id: prompt.id,
            requirementID: prompt.requirementID,
            promptNumber: prompt.promptNumber,
            body: prompt.body,
            targetModel: prompt.targetModel,
            guidance: prompt.guidance,
            skillID: prompt.skillID,
            skillEntryPath: prompt.skillEntryPath,
            skillEntrySHA256: prompt.skillEntrySHA256,
            source: prompt.provenance.source,
            createdSource: prompt.provenance.createdSource,
            createdAt: prompt.provenance.createdAt,
            citations: citations.map { citation in
                AssetPromptDetail.Citation(
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
            isStale: isStale
        )
    }

    /// `ProjectReading.promptHistory(requirementID:)` — every prompt row of the
    /// requirement, current included (§7.5: prompt reads exclude nothing), by number.
    func promptHistory(requirementID: UUID) throws -> [AssetPrompt] {
        try database.queue.read { db in
            try Self.promptRows(requirementID: requirementID, in: db)
        }
    }

    /// §6.4's dashboard numbers, per kind and overall, plus §5.3's entity-level badge.
    func manifestSummary() throws -> ManifestSummary {
        try database.queue.read { db in
            let graph = try Self.manifestGraph(in: db)
            var perKind: [EntityKind: [RequirementSummary]] = [:]
            var all: [RequirementSummary] = []
            for id in graph.order {
                guard let requirement = graph.requirements[id] else { continue }
                // Every count in §6.4 is over the **active** set.
                guard graph.isActive(requirement) else { continue }
                let summary = graph.summary(of: requirement)
                all.append(summary)
                perKind[summary.entityKind, default: []].append(summary)
            }
            return ManifestSummary(
                overall: Self.counts(all),
                byKind: perKind.mapValues(Self.counts),
                entitiesMissingCanonicalSet: Self.entitiesMissingCanonicalSet(graph)
            )
        }
    }

    /// §6.4's "what assets are still missing?", in creation order: canonical first, then
    /// variants in dependency order.
    func missingAssets() throws -> [MissingAsset] {
        try database.queue.read { db in
            let graph = try Self.manifestGraph(in: db)
            let missing = graph.order
                .compactMap { graph.requirements[$0] }
                .filter(graph.isMissing)
            let rank = Self.dependencyRanks(of: missing.map(\.id), in: graph)
            return missing
                .enumerated()
                .sorted { left, right in
                    let leftKey = (
                        left.element.tier == .canonical ? 0 : 1,
                        rank[left.element.id] ?? 0,
                        left.offset
                    )
                    let rightKey = (
                        right.element.tier == .canonical ? 0 : 1,
                        rank[right.element.id] ?? 0,
                        right.offset
                    )
                    return leftKey < rightKey
                }
                .map { _, requirement in
                    let entity = graph.entities[requirement.entityID]
                    let unsatisfied = graph.unsatisfiedDependencies(of: requirement.id)
                    return MissingAsset(
                        requirementID: requirement.id,
                        entityID: requirement.entityID,
                        entityKind: entity?.kind ?? .object,
                        entityName: entity?.name ?? "",
                        tier: requirement.tier,
                        requirementName: requirement.name,
                        displayStatus: graph.displayStatus(requirement),
                        isBlocked: !unsatisfied.isEmpty,
                        blockedBy: unsatisfied
                    )
                }
        }
    }

    /// The per-project template (§3.2), by kind then `sort_order`. Disabled entries are
    /// included: the template editor shows them, and §5.3 badges rows behind them.
    func requirementTemplate() throws -> [AssetRequirementType] {
        try database.queue.read { db in
            try Row
                .fetchAll(
                    db,
                    sql: "SELECT * FROM asset_requirement_types ORDER BY entity_kind, sort_order, code"
                )
                .map(decodeAssetRequirementType)
        }
    }

    /// Every `asset_versions.relative_path` — the referenced-media set `orphanedMedia()`
    /// subtracts the files under `assets/` from.
    func referencedMediaPaths() throws -> Set<String> {
        try database.queue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT relative_path FROM asset_versions"))
        }
    }

    // MARK: - Detail helpers

    /// §5.2: a canonical requirement's scenes are **derived** from `scene_entities` at read
    /// time; a variant's are its stored rows.
    private static func requiredByScenes(
        _ requirement: AssetRequirement,
        in db: Database
    ) throws -> [Scene] {
        switch requirement.tier {
        case .canonical:
            return try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT scenes.* FROM scenes
                        JOIN scene_entities ON scene_entities.scene_id = scenes.id
                        WHERE scene_entities.entity_id = ?
                          AND scene_entities.role IN (\(ManifestQualification.visibleRoleSQLList))
                          AND scene_entities.review_state <> 'rejected'
                        ORDER BY scenes.ordinal
                        """,
                    arguments: [requirement.entityID.uuidString]
                )
                .map(decodeScene)
        case .variant:
            return try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT scenes.* FROM scenes
                        JOIN asset_requirement_scenes AS links ON links.scene_id = scenes.id
                        WHERE links.requirement_id = ? AND links.review_state <> 'rejected'
                        ORDER BY scenes.ordinal
                        """,
                    arguments: [requirement.id.uuidString]
                )
                .map(decodeScene)
        }
    }

    private static func basisDetails(
        of requirementID: UUID,
        in db: Database
    ) throws -> [RequirementBasisDetail] {
        let rows = try Row
            .fetchAll(
                db,
                sql: """
                    SELECT * FROM asset_requirement_basis
                    WHERE requirement_id = ? ORDER BY rowid
                    """,
                arguments: [requirementID.uuidString]
            )
            .map(decodeAssetRequirementBasis)
        return try rows.map { basis in
            let table = switch basis.subjectKind {
            case .state: "entity_states"
            case .event: "continuity_events"
            default: "scene_entities"
            }
            let raw = try String.fetchOne(
                db,
                sql: "SELECT review_state FROM \(table) WHERE id = ?",
                arguments: [basis.subjectID.uuidString]
            )
            // The cited fact's evidence, joined on the polymorphic subject key the basis
            // row and the `evidence` table share.
            let evidence = try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT * FROM evidence
                        WHERE subject_kind = ? AND subject_id = ?
                        ORDER BY rowid
                        """,
                    arguments: [basis.subjectKind.rawValue, basis.subjectID.uuidString]
                )
                .map(decodeEvidence)
            return RequirementBasisDetail(
                basis: basis,
                factReviewState: raw.flatMap(ReviewState.init(rawValue:)),
                evidence: evidence
            )
        }
    }

    private static func versions(of assetID: UUID, in db: Database) throws -> [AssetVersion] {
        try Row
            .fetchAll(
                db,
                sql: "SELECT * FROM asset_versions WHERE asset_id = ? ORDER BY version_number",
                arguments: [assetID.uuidString]
            )
            .map(decodeAssetVersion)
    }

    // MARK: - Summary helpers

    private static func counts(_ summaries: [RequirementSummary]) -> ManifestCounts {
        ManifestCounts(
            canonical: summaries.count { $0.tier == .canonical },
            variant: summaries.count { $0.tier == .variant },
            approved: summaries.count { $0.displayStatus == .approved },
            needsReview: summaries.count { $0.displayStatus == .needsReview },
            missing: summaries.count(where: \.isMissing),
            blocked: summaries.count(where: \.isBlocked),
            stale: summaries.count { $0.displayStatus == .approved && $0.isStale },
            optional: summaries.count { $0.necessity == .optional }
        )
    }

    /// §5.3's "qualifies but has no canonical set — Build to add", computed for every
    /// qualifying entity against the **enabled** template entries of its kind. A slot any
    /// row already fills — a tombstone included, since Build skips those (§5.2) — is not
    /// reported.
    private static func entitiesMissingCanonicalSet(_ graph: ManifestGraph) -> [QualifyingEntity] {
        var filled: [UUID: Set<UUID>] = [:]
        for requirement in graph.requirements.values {
            guard let typeID = requirement.typeID else { continue }
            filled[requirement.entityID, default: []].insert(typeID)
        }
        return graph.entities.values
            .filter(graph.qualifies)
            .compactMap { entity in
                let missing = graph.types.values
                    .filter { $0.entityKind == entity.kind && $0.isEnabled }
                    .filter { !(filled[entity.id]?.contains($0.id) ?? false) }
                    .sorted { ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code) }
                    .map(\.code)
                guard !missing.isEmpty else { return nil }
                return QualifyingEntity(
                    id: entity.id,
                    kind: entity.kind,
                    name: entity.name,
                    missingTemplateCodes: missing
                )
            }
            .sorted {
                (
                    EntityKind.allCases.firstIndex(of: $0.kind) ?? 0,
                    $0.name.lowercased(),
                    $0.id.uuidString
                ) < (
                    EntityKind.allCases.firstIndex(of: $1.kind) ?? 0,
                    $1.name.lowercased(),
                    $1.id.uuidString
                )
            }
    }

    /// Longest dependency chain within the given set — the "variants in dependency order"
    /// §6.4 asks the reads to expose. Cycles cannot be written (§3.5 refuses them), and the
    /// visited guard here keeps a hand-seeded one from recursing forever.
    ///
    /// Internal so the readiness derivation (Plan 017 contract B) reuses the shipped rank
    /// rather than re-spelling it.
    static func dependencyRanks(
        of ids: [UUID],
        in graph: ManifestGraph
    ) -> [UUID: Int] {
        let inSet = Set(ids)
        var targets: [UUID: [UUID]] = [:]
        for dependency in graph.dependencies where inSet.contains(dependency.requirementID) {
            guard inSet.contains(dependency.dependsOnRequirementID) else { continue }
            targets[dependency.requirementID, default: []].append(dependency.dependsOnRequirementID)
        }
        var ranks: [UUID: Int] = [:]
        func rank(_ id: UUID, visiting: Set<UUID>) -> Int {
            if let known = ranks[id] { return known }
            guard !visiting.contains(id) else { return 0 }
            let value = (targets[id] ?? [])
                .map { rank($0, visiting: visiting.union([id])) + 1 }
                .max() ?? 0
            ranks[id] = value
            return value
        }
        for id in ids { _ = rank(id, visiting: []) }
        return ranks
    }
}
