import Foundation
import GRDB

// The scene-package derivations (PHASE5_DESIGN §3.2, §3.3, §3.4; Plan 018 contract C).
//
// **One derivation, one authority**, the Phase 4 rule carried forward: the plan and the
// continuity context derive from one `ReadinessGraph` load; `assetReady(S)` is read from
// Plan 017's snapshot — re-deriving readiness here would be a contract STOP. Package
// staleness is the derived digest/format-version comparison (§3.4), never stored.

extension ProjectRepository {
    // MARK: - references(S) (§3.2)

    /// The §3.2 reference plan: Plan 017's two-branch inversion (canonical requirements
    /// through visible-role `scene_entities`, variant requirements through
    /// `asset_requirement_scenes`), minus human scene-specific exclusions, thinned to active, non-rejected,
    /// `necessity = 'required'` rows, each joined to its asset's approved version.
    ///
    /// Ordering is the inherited convention at scene scale: class rank → requirement name
    /// → requirement id — a total key ending in id, the house rule. Dense `@Image N`
    /// designators over the approved subset alone; unsatisfied rows appear un-designated.
    /// Optional requirements are excluded here — the Phase 4 shown-never-counted rule at
    /// reference scale; reads carry them greyed beside the plan.
    ///
    /// Per-reference attributes go through `ReferenceAttributeRules.sceneAttributes`.
    /// Scene use is narrower than asset-to-asset dependency use: a face sheet owns the
    /// head, while its paired body sheet owns only clothed physique, wardrobe, and rear hairstyle, and
    /// every sheet or plate excludes incidental layout/content that must not enter the
    /// generated shot.
    static func sceneReferencePlan(
        sceneID: UUID,
        graph: ReadinessGraph,
        in db: Database
    ) throws -> [ScenePlannedReference] {
        let manifest = graph.manifest

        var planned: [ScenePlannedReference] = []
        for requirementID in graph.linkedRequirements(of: sceneID).sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let requirement = manifest.requirements[requirementID],
                  manifest.isActive(requirement),
                  requirement.provenance.reviewState != .rejected,
                  requirement.necessity == .required,
                  let entity = manifest.entities[requirement.entityID]
            else { continue }

            let targetClass = ReferenceAttributeRules.referenceClass(
                tier: requirement.tier, entityKind: entity.kind
            )
            let templateCode = requirement.outfitSourceVersionID != nil ? "full_body" : requirement.typeID.flatMap { manifest.types[$0]?.code } ?? ""
            let attributes = ReferenceAttributeRules.sceneAttributes(
                targetTier: requirement.tier,
                targetEntityKind: entity.kind,
                targetEntityName: entity.name,
                targetRequirementName: requirement.name,
                targetTemplateCode: templateCode
            )

            // Satisfaction: the asset holds an approved version; the join takes that one
            // row through the shipped partial unique index — no ordering ambiguity.
            var approved: ScenePlannedReference.ApprovedVersion?
            if let asset = manifest.assetsByRequirement[requirement.id],
               manifest.assetsWithApprovedVersion.contains(asset.id) {
                approved = try Self.approvedVersion(of: asset.id, in: db)
            }

            planned.append(
                ScenePlannedReference(
                    id: requirement.id,
                    requirementID: requirement.id,
                    requirementName: requirement.name,
                    entityID: entity.id,
                    entityName: entity.name,
                    entityKind: entity.kind,
                    templateCode: templateCode,
                    class: targetClass,
                    attributes: attributes,
                    isSatisfied: approved != nil,
                    isStale: manifest.assetsByRequirement[requirement.id]?.isStale ?? false,
                    approvedVersion: approved,
                    designator: nil
                )
            )
        }

        // §3.2's order: class rank, then requirement name, then requirement id.
        planned.sort {
            ($0.class.rank, $0.requirementName.lowercased(), $0.requirementID.uuidString)
                < ($1.class.rank, $1.requirementName.lowercased(), $1.requirementID.uuidString)
        }

        // Dense @Image numbering over the satisfied subset alone.
        var designator = 0
        return planned.map { row in
            guard row.isSatisfied else { return row }
            designator += 1
            return ScenePlannedReference(
                id: row.id,
                requirementID: row.requirementID,
                requirementName: row.requirementName,
                entityID: row.entityID,
                entityName: row.entityName,
                entityKind: row.entityKind,
                templateCode: row.templateCode,
                class: row.class,
                attributes: row.attributes,
                isSatisfied: row.isSatisfied,
                isStale: row.isStale,
                approvedVersion: row.approvedVersion,
                designator: designator
            )
        }
    }

    /// The approved version of an asset, when one exists — with its stored dimensions.
    static func approvedVersion(of assetID: UUID, in db: Database) throws
        -> ScenePlannedReference.ApprovedVersion? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM asset_versions WHERE asset_id = ? AND status = 'approved'",
            arguments: [assetID.uuidString]
        ) else { return nil }
        return ScenePlannedReference.ApprovedVersion(
            versionID: try UUID.required(row["id"]),
            sha256: row["sha256"],
            relativePath: row["relative_path"],
            pixelWidth: row["pixel_width"],
            pixelHeight: row["pixel_height"]
        )
    }

    /// The optional linked requirements of a scene — shown, greyed, never counted (§3.2).
    /// Active and non-rejected like the plan; no designator, no plan membership.
    static func sceneOptionalRequirements(
        sceneID: UUID,
        graph: ReadinessGraph
    ) -> [SceneOptionalRequirement] {
        let manifest = graph.manifest
        return graph.linkedRequirements(of: sceneID)
            .sorted(by: { $0.uuidString < $1.uuidString })
            .compactMap { requirementID in
                guard let requirement = manifest.requirements[requirementID],
                      manifest.isActive(requirement),
                      requirement.provenance.reviewState != .rejected,
                      requirement.necessity == .optional
                else { return nil }
                return SceneOptionalRequirement(
                    requirementID: requirement.id,
                    entityName: manifest.entities[requirement.entityID]?.name ?? "",
                    requirementName: requirement.name,
                    tier: requirement.tier,
                    displayStatus: manifest.displayStatus(requirement),
                    hasUnreviewedFacts: manifest.hasUnreviewedFacts(requirement)
                )
            }
            .sorted {
                (
                    $0.entityName.lowercased(), $0.requirementName.lowercased(),
                    $0.requirementID.uuidString
                ) < (
                    $1.entityName.lowercased(), $1.requirementName.lowercased(),
                    $1.requirementID.uuidString
                )
            }
    }

    // MARK: - continuity(S) (§3.2)

    /// The §3.2 continuity context: for each entity appearing in S (any visible role,
    /// tombstones excluded), the `entity_states` rows whose scene interval covers S —
    /// started at an ordinal ≤ S's and not ended before it, open intervals included —
    /// ordered by entity name, category, then state id. An empty context is a valid one.
    static func sceneContinuityContext(
        sceneID: UUID,
        graph: ReadinessGraph,
        in db: Database
    ) throws -> ContinuityContext {
        guard let scene = graph.scenes.first(where: { $0.id == sceneID }) else {
            throw ProjectStoreError.sceneNotFound
        }
        let manifest = graph.manifest

        // Ordinals resolve against the current script's scenes, as everywhere else.
        var ordinalOfScene: [UUID: Int] = [:]
        for row in graph.scenes {
            ordinalOfScene[row.id] = row.ordinal
        }

        struct StateRow {
            let entityID: UUID
            let entityName: String
            let category: StateCategory
            let description: String
            let start: Int
            let end: Int?
            let id: UUID
        }
        var rows: [StateRow] = []
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT DISTINCT entities.id AS entity_id FROM entities
                JOIN scene_entities ON scene_entities.entity_id = entities.id
                WHERE scene_entities.scene_id = ?
                  AND scene_entities.role IN (\(ManifestQualification.visibleRoleSQLList))
                  AND scene_entities.review_state <> 'rejected'
                """,
            arguments: [sceneID.uuidString]
        ) {
            let entityID = try UUID.required(row["entity_id"])
            for stateRow in try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM entity_states
                    WHERE entity_id = ? AND review_state <> 'rejected'
                    """,
                arguments: [entityID.uuidString]
            ) {
                let state = try decodeEntityState(stateRow)
                guard let start = ordinalOfScene[state.startSceneID] else { continue }
                let end = state.endSceneID.flatMap { ordinalOfScene[$0] }
                // Covers S: started at or before it and not ended before it. Open
                // intervals (end == nil) cover everything from their start on.
                let covers = start <= scene.ordinal && (end.map { $0 >= scene.ordinal } ?? true)
                guard covers else { continue }
                rows.append(
                    StateRow(
                        entityID: entityID,
                        entityName: manifest.entities[entityID]?.name ?? "",
                        category: state.category,
                        description: state.description,
                        start: start,
                        end: end,
                        id: state.id
                    )
                )
            }
        }

        rows.sort {
            (
                $0.entityName.lowercased(), $0.category.rawValue, $0.id.uuidString
            ) < (
                $1.entityName.lowercased(), $1.category.rawValue, $1.id.uuidString
            )
        }
        return ContinuityContext(
            entries: rows.map { row in
                ContinuityContext.Entry(
                    entityID: row.entityID,
                    entityName: row.entityName,
                    category: row.category,
                    description: row.description,
                    stateID: row.id
                )
            }
        )
    }

    // MARK: - Staleness and package states (§3.3, §3.4)

    /// The current set of `(scene, profile)` — highest `set_number`.
    static func currentScenePromptSet(
        sceneID: UUID, profileID: String, in db: Database
    ) throws -> ScenePromptSet? {
        try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM scene_prompt_sets
                WHERE scene_id = ? AND target_profile = ?
                ORDER BY set_number DESC LIMIT 1
                """,
            arguments: [sceneID.uuidString, profileID]
        ).map(decodeScenePromptSet).first
    }

    static func scenePromptSetRows(
        sceneID: UUID, profileID: String, in db: Database
    ) throws -> [ScenePromptSet] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM scene_prompt_sets
                WHERE scene_id = ? AND target_profile = ?
                ORDER BY set_number
                """,
            arguments: [sceneID.uuidString, profileID]
        ).map(decodeScenePromptSet)
    }

    static func scenePromptSet(id: UUID, in db: Database) throws -> ScenePromptSet? {
        try Row.fetchOne(
            db, sql: "SELECT * FROM scene_prompt_sets WHERE id = ?",
            arguments: [id.uuidString]
        ).map(decodeScenePromptSet)
    }

    static func scenePromptCards(setID: UUID, in db: Database) throws -> [ScenePromptCard] {
        try Row.fetchAll(
            db,
            sql: "SELECT * FROM scene_prompt_cards WHERE set_id = ? ORDER BY card_order",
            arguments: [setID.uuidString]
        ).map(decodeScenePromptCard)
    }

    static func scenePromptCardReferences(
        cardID: UUID, in db: Database
    ) throws -> [ScenePromptCardReference] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM scene_prompt_card_references
                WHERE card_id = ? ORDER BY position
                """,
            arguments: [cardID.uuidString]
        ).map(decodeScenePromptCardReference)
    }

    static func scenePromptSetDetail(
        _ set: ScenePromptSet, staleReason: ScenePromptStaleReason?, in db: Database
    ) throws -> ScenePromptSetDetail {
        let cards = try scenePromptCards(setID: set.id, in: db).map { card in
            ScenePromptSetDetail.Card(
                card: card,
                references: try scenePromptCardReferences(cardID: card.id, in: db)
            )
        }
        return ScenePromptSetDetail(set: set, cards: cards, staleReason: staleReason)
    }

    static func scenePromptSetStaleReason(
        _ set: ScenePromptSet, in db: Database
    ) throws -> ScenePromptStaleReason? {
        if set.inputFormatVersion != ScenePromptInputBuilder.schemaVersion {
            return .olderInputFormat
        }
        let rebuilt = try ScenePromptInputBuilder.snapshot(sceneID: set.sceneID, in: db)
        return rebuilt.digest == set.inputDigest ? nil : .inputsChanged
    }

    /// Compatibility projection for the old one-prompt package view. Canonical reads use
    /// `currentScenePromptSet`; this returns the first card only.
    static func currentScenePrompt(
        sceneID: UUID, profileID: String, in db: Database
    ) throws -> ScenePrompt? {
        guard let set = try currentScenePromptSet(sceneID: sceneID, profileID: profileID, in: db),
              let card = try scenePromptCards(setID: set.id, in: db).first
        else { return nil }
        return legacyPrompt(set: set, card: card)
    }

    /// Every prompt row of `(scene, profile)`, by number ascending (§7.5).
    static func scenePromptRows(
        sceneID: UUID, profileID: String, in db: Database
    ) throws -> [ScenePrompt] {
        try scenePromptSetRows(sceneID: sceneID, profileID: profileID, in: db).compactMap { set in
            guard let card = try scenePromptCards(setID: set.id, in: db).first else { return nil }
            return legacyPrompt(set: set, card: card)
        }
    }

    /// The citation rows of one scene prompt, by position (§3.2's @Image order).
    static func sceneCitationRows(promptID: UUID, in db: Database) throws -> [ScenePromptReference] {
        try scenePromptCardReferences(cardID: promptID, in: db).map { reference in
            ScenePromptReference(
                id: reference.id, promptID: reference.cardID, position: reference.position,
                requirementID: reference.requirementID, versionID: reference.versionID,
                class: reference.class, role: reference.role, exclusion: reference.exclusion,
                fidelity: reference.fidelity, sha256: reference.sha256,
                displayName: reference.displayName, source: reference.source,
                jobID: reference.jobID, createdAt: reference.createdAt
            )
        }
    }

    /// §3.4's derived staleness: stale when the recorded format version differs from the
    /// builder's ("older input format"), or a fresh §8.2 render's digest differs
    /// ("inputs changed"). Never stored, never blocking — it informs.
    static func scenePromptStaleReason(
        _ prompt: ScenePrompt, in db: Database
    ) throws -> ScenePromptStaleReason? {
        guard let set = try Row.fetchAll(
            db,
            sql: "SELECT * FROM scene_prompt_sets WHERE id = ?",
            arguments: [prompt.id.uuidString]
        ).map(decodeScenePromptSet).first else {
            if prompt.inputFormatVersion != ScenePromptInputBuilder.schemaVersion {
                return .olderInputFormat
            }
            let rebuilt = try ScenePromptInputBuilder.snapshot(sceneID: prompt.sceneID, in: db)
            return rebuilt.digest == prompt.inputDigest ? nil : .inputsChanged
        }
        return try scenePromptSetStaleReason(set, in: db)
    }

    private static func legacyPrompt(set: ScenePromptSet, card: ScenePromptCard) -> ScenePrompt {
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

    /// §3.3's predicate, verbatim, always against the active profile P:
    ///
    ///     generationReady(S) := assetReady(S) ∧ currentPrompt(S, P) exists ∧ ¬stale
    ///     stale(S)          := currentPrompt(S, P) exists ∧ stale(currentPrompt(S, P))
    ///     needsPreparation(S) := otherwise
    ///
    /// A profile id the catalog no longer carries (`activeProfile == nil`) reads
    /// `needsPreparation` with the refusal naming the missing profile — never a crash.
    static func scenePackageState(
        assetReady: Bool,
        activeProfile: TargetProfile?,
        currentPrompt: ScenePrompt?,
        staleReason: ScenePromptStaleReason?
    ) -> ScenePackageState {
        guard activeProfile != nil else { return .needsPreparation }
        guard currentPrompt != nil else { return .needsPreparation }
        if staleReason != nil { return .stale }
        return assetReady ? .generationReady : .needsPreparation
    }

    static func scenePackageState(
        assetReady: Bool,
        activeProfile: TargetProfile?,
        currentSet: ScenePromptSet?,
        staleReason: ScenePromptStaleReason?
    ) -> ScenePackageState {
        guard activeProfile != nil, currentSet != nil else { return .needsPreparation }
        if staleReason != nil { return .stale }
        return assetReady ? .generationReady : .needsPreparation
    }
}
