import Foundation
import GRDB

/// Canonical schema-v9 prompt-set mutations. Every public gesture becomes one call to
/// `EditPrimitives.perform`; this layer opens no transaction of its own.
enum ScenePromptSetOperations {
    struct RequiredSet {
        let set: ScenePromptSet
        let profile: TargetProfile
    }

    static func create(
        setID: UUID,
        sceneID: UUID,
        cards: [ScenePromptCardDraft],
        restoring: [RowSnapshot],
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        if !restoring.isEmpty {
            try RowGraph.restore(restoring, in: db)
            return MutationEffect(
                inverse: .deleteScenePromptSet(setID: setID),
                affected: affected(setID: setID, sceneID: sceneID, rows: restoring)
            )
        }
        try RequirementOperations.requireHuman(
            actor, subject: SubjectRef(kind: .scene, id: sceneID)
        )
        let flight = try ScenePromptOperations.preFlight(sceneID: sceneID, in: db)
        try validate(cards: cards, profile: flight.profile)
        let snapshot = try ScenePromptInputBuilder.snapshot(sceneID: sceneID, in: db)
        try ScenePromptInputBudget.check(text: snapshot.text)
        let number = try nextSetNumber(
            sceneID: sceneID, profileID: flight.profile.id, in: db
        )
        let now = UTCDate.string(from: Date())
        var arguments: StatementArguments = [
            setID.uuidString, flight.projectID.uuidString, sceneID.uuidString,
            flight.profile.id, number, snapshot.digest,
            ScenePromptInputBuilder.schemaVersion,
        ]
        arguments += RequirementOperations.insertProvenance(actor, timestamp: now)
        try db.execute(
            sql: """
                INSERT INTO scene_prompt_sets (
                    id, project_id, scene_id, target_profile, set_number,
                    skill_id, skill_entry_path, skill_entry_sha256,
                    input_digest, input_format_version, human_edited,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, '', '', '', ?, ?, 1,
                          ?, NULL, ?, ?, ?, ?, ?, ?)
                """,
            arguments: arguments
        )
        let plan = try resolvedPlan(sceneID: sceneID, in: db)
        for (offset, card) in cards.enumerated() {
            try insertCard(
                id: offset == 0 ? setID : UUID(), setID: setID, order: offset + 1, draft: card,
                plan: plan, source: .human, jobID: nil, timestamp: now, in: db
            )
        }
        let rows = try captureGraph(setID: setID, in: db)
        return MutationEffect(
            inverse: .deleteScenePromptSet(setID: setID),
            affected: affected(setID: setID, sceneID: sceneID, rows: rows)
        )
    }

    static func attachGenerated(
        setID: UUID,
        sceneID: UUID,
        cards: [ScenePromptCardDraft],
        inputDigest: String,
        inputFormatVersion: Int,
        skillIdentity: AssetPromptSkillIdentity,
        actor: MutationActor,
        mode: MutationMode,
        in db: Database
    ) throws -> MutationEffect {
        if let entry = mode.invertedEntry {
            try RowGraph.restore(entry.snapshots, in: db)
            try consumeCreativeDirection(sceneID: sceneID, in: db)
            return MutationEffect(
                inverse: .removeAttachedScenePromptSet(
                    payload: ScenePromptSetSnapshotPayload(
                        setID: setID, sceneID: sceneID, rows: entry.snapshots
                    )
                ),
                affected: affected(setID: setID, sceneID: sceneID, rows: entry.snapshots)
            )
        }
        guard case .ai = actor else {
            throw ProjectStoreError.protectedFact(subject: SubjectRef(kind: .scene, id: sceneID))
        }
        let flight = try ScenePromptOperations.preFlight(sceneID: sceneID, in: db)
        try validate(cards: cards, profile: flight.profile)
        let number = try nextSetNumber(
            sceneID: sceneID, profileID: flight.profile.id, in: db
        )
        let now = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO scene_prompt_sets (
                    id, project_id, scene_id, target_profile, set_number,
                    skill_id, skill_entry_path, skill_entry_sha256,
                    input_digest, input_format_version, human_edited,
                    source, confidence, review_state, reviewed_at, job_id,
                    created_source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0,
                          'ai', NULL, 'accepted', NULL, ?, 'ai', ?, ?)
                """,
            arguments: [
                setID.uuidString, flight.projectID.uuidString, sceneID.uuidString,
                flight.profile.id, number, skillIdentity.id, skillIdentity.entryPath,
                skillIdentity.entrySHA256, inputDigest, inputFormatVersion,
                actor.jobID?.uuidString, now, now,
            ]
        )
        let plan = try resolvedPlan(sceneID: sceneID, in: db)
        for (offset, card) in cards.enumerated() {
            try insertCard(
                id: offset == 0 ? setID : UUID(), setID: setID, order: offset + 1, draft: card,
                plan: plan, source: .ai, jobID: actor.jobID, timestamp: now, in: db
            )
        }
        let rows = try captureGraph(setID: setID, in: db)
        try consumeCreativeDirection(sceneID: sceneID, in: db)
        return MutationEffect(
            inverse: .removeAttachedScenePromptSet(
                payload: ScenePromptSetSnapshotPayload(
                    setID: setID, sceneID: sceneID, rows: rows
                )
            ),
            affected: affected(setID: setID, sceneID: sceneID, rows: rows)
        )
    }

    static func editCard(
        cardID: UUID, draft: ScenePromptCardDraft, actor: MutationActor, in db: Database
    ) throws -> MutationEffect {
        let required = try requireCurrentSet(cardID: cardID, in: db)
        try RequirementOperations.requireHuman(actor, subject: SubjectRef(kind: .prompt, id: cardID))
        let old = try captureGraph(setID: required.set.id, in: db)
        var cards = try ProjectRepository.scenePromptCards(setID: required.set.id, in: db)
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else {
            throw ProjectStoreError.promptNotFound
        }
        let allReferences = try ProjectRepository.scenePromptCardReferences(cardID: cardID, in: db)
        let effective = ScenePromptCardDraft(
            title: draft.title, body: draft.body, guidance: draft.guidance,
            durationSeconds: draft.durationSeconds, aspectRatio: draft.aspectRatio,
            resolution: draft.resolution,
            referencePositions: allReferences.map(\.position)
        )
        cards[index] = ScenePromptCard(
            id: cardID, setID: required.set.id, order: cards[index].order,
            title: effective.title, body: effective.body, guidance: effective.guidance,
            durationSeconds: effective.durationSeconds, aspectRatio: effective.aspectRatio,
            resolution: effective.resolution
        )
        try validateExisting(cards: cards, profile: required.profile)
        try db.execute(
            sql: """
                UPDATE scene_prompt_cards SET title = ?, body = ?, guidance = ?,
                    duration_seconds = ?, aspect_ratio = ?, resolution = ? WHERE id = ?
                """,
            arguments: [
                effective.title, effective.body, effective.guidance,
                effective.durationSeconds, effective.aspectRatio, effective.resolution,
                cardID.uuidString,
            ]
        )
        try markHumanEdited(setID: required.set.id, in: db)
        return restoreInverse(set: required.set, oldRows: old)
    }

    static func addCard(
        cardID: UUID, setID: UUID, draft: ScenePromptCardDraft,
        actor: MutationActor, in db: Database
    ) throws -> MutationEffect {
        let required = try requireCurrentSet(setID: setID, in: db)
        try RequirementOperations.requireHuman(actor, subject: SubjectRef(kind: .prompt, id: setID))
        let old = try captureGraph(setID: setID, in: db)
        let count = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM scene_prompt_cards WHERE set_id = ?",
            arguments: [setID.uuidString]
        ) ?? 0
        let plan = try resolvedPlan(sceneID: required.set.sceneID, in: db)
        let normalizedDraft = draft.referencePositions.isEmpty
            ? ScenePromptCardDraft(
                title: draft.title, body: draft.body, guidance: draft.guidance,
                durationSeconds: draft.durationSeconds, aspectRatio: draft.aspectRatio,
                resolution: draft.resolution,
                referencePositions: plan.map(\.designator)
            ) : draft
        try validate(
            cards: try existingDrafts(setID: setID, in: db) + [normalizedDraft],
            profile: required.profile
        )
        try insertCard(
            id: cardID, setID: setID, order: count + 1, draft: normalizedDraft,
            plan: plan, source: .human, jobID: nil,
            timestamp: UTCDate.string(from: Date()), in: db
        )
        try markHumanEdited(setID: setID, in: db)
        return restoreInverse(set: required.set, oldRows: old)
    }

    static func deleteCard(
        cardID: UUID, actor: MutationActor, in db: Database
    ) throws -> MutationEffect {
        let required = try requireCurrentSet(cardID: cardID, in: db)
        try RequirementOperations.requireHuman(actor, subject: SubjectRef(kind: .prompt, id: cardID))
        let old = try captureGraph(setID: required.set.id, in: db)
        let count = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM scene_prompt_cards WHERE set_id = ?",
            arguments: [required.set.id.uuidString]
        ) ?? 0
        guard count > 1 else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "A prompt set must contain at least one card."
            )
        }
        try db.execute(
            sql: "DELETE FROM scene_prompt_cards WHERE id = ?", arguments: [cardID.uuidString]
        )
        try densify(setID: required.set.id, in: db)
        try markHumanEdited(setID: required.set.id, in: db)
        return restoreInverse(set: required.set, oldRows: old)
    }

    static func reorder(
        setID: UUID, orderedCardIDs: [UUID], actor: MutationActor, in db: Database
    ) throws -> MutationEffect {
        let required = try requireCurrentSet(setID: setID, in: db)
        try RequirementOperations.requireHuman(actor, subject: SubjectRef(kind: .prompt, id: setID))
        let cards = try ProjectRepository.scenePromptCards(setID: setID, in: db)
        guard orderedCardIDs.count == cards.count,
              Set(orderedCardIDs) == Set(cards.map(\.id)) else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "The prompt-card order must include every card exactly once."
            )
        }
        let old = try captureGraph(setID: setID, in: db)
        // Move out of the UNIQUE range before assigning the dense final order.
        try db.execute(
            sql: "UPDATE scene_prompt_cards SET card_order = card_order + 1000 WHERE set_id = ?",
            arguments: [setID.uuidString]
        )
        for (offset, id) in orderedCardIDs.enumerated() {
            try db.execute(
                sql: "UPDATE scene_prompt_cards SET card_order = ? WHERE id = ?",
                arguments: [offset + 1, id.uuidString]
            )
        }
        try markHumanEdited(setID: setID, in: db)
        return restoreInverse(set: required.set, oldRows: old)
    }

    static func deleteSet(
        setID: UUID, actor: MutationActor, requireCurrent: Bool = true, in db: Database
    ) throws -> MutationEffect {
        let required: RequiredSet
        if requireCurrent {
            required = try requireCurrentSet(setID: setID, in: db)
        } else {
            guard let set = try ProjectRepository.scenePromptSet(id: setID, in: db),
                  let profile = TargetProfileCatalog.profile(id: set.targetProfile) else {
                throw ProjectStoreError.promptNotFound
            }
            required = RequiredSet(set: set, profile: profile)
        }
        try RequirementOperations.requireHuman(actor, subject: SubjectRef(kind: .prompt, id: setID))
        let rows = try captureGraph(setID: setID, in: db)
        try db.execute(
            sql: "DELETE FROM scene_prompt_sets WHERE id = ?", arguments: [setID.uuidString]
        )
        return MutationEffect(
            inverse: .restoreScenePromptSet(
                payload: ScenePromptSetSnapshotPayload(
                    setID: setID, sceneID: required.set.sceneID, rows: rows
                )
            ),
            affected: affected(setID: setID, sceneID: required.set.sceneID, rows: rows),
            snapshots: rows
        )
    }

    static func restore(
        payload: ScenePromptSetSnapshotPayload, in db: Database
    ) throws -> MutationEffect {
        let current = try captureGraph(setID: payload.setID, in: db)
        try db.execute(
            sql: "DELETE FROM scene_prompt_sets WHERE id = ?",
            arguments: [payload.setID.uuidString]
        )
        try RowGraph.restore(payload.rows, in: db)
        let inverse: EditOperation = current.isEmpty
            ? .deleteScenePromptSet(setID: payload.setID)
            : .restoreScenePromptSet(
                payload: ScenePromptSetSnapshotPayload(
                    setID: payload.setID, sceneID: payload.sceneID, rows: current
                )
            )
        return MutationEffect(
            inverse: inverse,
            affected: affected(setID: payload.setID, sceneID: payload.sceneID, rows: payload.rows),
            snapshots: current
        )
    }

    static func removeAttached(
        payload: ScenePromptSetSnapshotPayload, mode: MutationMode, in db: Database
    ) throws -> MutationEffect {
        if case .inverting = mode {
            try db.execute(
                sql: "DELETE FROM scene_prompt_sets WHERE id = ?",
                arguments: [payload.setID.uuidString]
            )
        } else {
            try RowGraph.restore(payload.rows, in: db)
        }
        return MutationEffect(
            inverse: .attachGeneratedScenePromptSet(
                setID: payload.setID, sceneID: payload.sceneID,
                cards: drafts(from: payload.rows),
                inputDigest: string("input_digest", in: payload.rows) ?? "",
                inputFormatVersion: int("input_format_version", in: payload.rows) ?? 1,
                skillIdentity: AssetPromptSkillIdentity(
                    id: string("skill_id", in: payload.rows) ?? "",
                    entryPath: string("skill_entry_path", in: payload.rows) ?? "",
                    entrySHA256: string("skill_entry_sha256", in: payload.rows) ?? ""
                )
            ),
            affected: affected(
                setID: payload.setID, sceneID: payload.sceneID, rows: payload.rows
            ),
            snapshots: payload.rows
        )
    }

    // MARK: Helpers

    /// A successfully attached generated set consumes the pending one-run direction.
    /// This mutation shares the attach transaction, so any later error restores the note
    /// for retry. Undo removes the result without reviving an already-used instruction.
    private static func consumeCreativeDirection(sceneID: UUID, in db: Database) throws {
        try db.execute(
            sql: "UPDATE scenes SET prompt_direction = '' WHERE id = ?",
            arguments: [sceneID.uuidString]
        )
    }

    static func captureGraph(setID: UUID, in db: Database) throws -> [RowSnapshot] {
        var rows: [RowSnapshot] = []
        if let set = try RowSnapshotStore.capture(table: "scene_prompt_sets", id: setID, in: db) {
            rows.append(set)
        }
        let cards = try RowSnapshotStore.captureAll(
            table: "scene_prompt_cards", where: "set_id = ?",
            arguments: [setID.uuidString], in: db
        )
        rows += cards
        for card in cards {
            guard case let .string(cardID)? = card.columns["id"] else { continue }
            rows += try RowSnapshotStore.captureAll(
                table: "scene_prompt_card_references", where: "card_id = ?",
                arguments: [cardID], in: db
            )
        }
        return rows
    }

    static func requireCurrentSet(setID: UUID, in db: Database) throws -> RequiredSet {
        guard let set = try Row.fetchAll(
            db, sql: "SELECT * FROM scene_prompt_sets WHERE id = ?",
            arguments: [setID.uuidString]
        ).map(decodeScenePromptSet).first else { throw ProjectStoreError.promptNotFound }
        return try requireCurrent(set, in: db)
    }

    static func requireCurrentSet(cardID: UUID, in db: Database) throws -> RequiredSet {
        guard let raw = try String.fetchOne(
            db, sql: "SELECT set_id FROM scene_prompt_cards WHERE id = ?",
            arguments: [cardID.uuidString]
        ), let id = UUID(uuidString: raw) else { throw ProjectStoreError.promptNotFound }
        return try requireCurrentSet(setID: id, in: db)
    }

    private static func requireCurrent(_ set: ScenePromptSet, in db: Database) throws -> RequiredSet {
        let current = try String.fetchOne(
            db,
            sql: """
                SELECT id FROM scene_prompt_sets
                WHERE scene_id = ? AND target_profile = ?
                ORDER BY set_number DESC LIMIT 1
                """,
            arguments: [set.sceneID.uuidString, set.targetProfile]
        )
        guard current == set.id.uuidString else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "Only the current prompt set can be edited; earlier sets are history."
            )
        }
        guard let profile = TargetProfileCatalog.profile(id: set.targetProfile) else {
            throw ProjectStoreError.generationTargetProfileMissing(id: set.targetProfile)
        }
        return RequiredSet(set: set, profile: profile)
    }

    private static func nextSetNumber(
        sceneID: UUID, profileID: String, in db: Database
    ) throws -> Int {
        try Int.fetchOne(
            db,
            sql: """
                SELECT COALESCE(MAX(set_number), 0) + 1 FROM scene_prompt_sets
                WHERE scene_id = ? AND target_profile = ?
                """,
            arguments: [sceneID.uuidString, profileID]
        ) ?? 1
    }

    struct PlanReference {
        let designator: Int
        let value: ScenePlannedReference
    }

    private static func resolvedPlan(sceneID: UUID, in db: Database) throws -> [PlanReference] {
        let graph = try ProjectRepository.readinessGraph(in: db)
        return try ProjectRepository.sceneReferencePlan(
            sceneID: sceneID, graph: graph, in: db
        ).compactMap { item in
            guard item.isSatisfied, let designator = item.designator,
                  item.approvedVersion != nil else { return nil }
            return PlanReference(designator: designator, value: item)
        }
    }

    private static func insertCard(
        id: UUID, setID: UUID, order: Int, draft: ScenePromptCardDraft,
        plan: [PlanReference], source: FactSource, jobID: UUID?, timestamp: String,
        in db: Database
    ) throws {
        let positions = draft.referencePositions.isEmpty ? plan.map(\.designator) : draft.referencePositions
        guard Set(positions).count == positions.count else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "A prompt card cannot attach the same reference twice."
            )
        }
        let byPosition = Dictionary(uniqueKeysWithValues: plan.map { ($0.designator, $0.value) })
        guard positions.allSatisfy({ byPosition[$0] != nil }) else {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "A prompt card referenced an image that is not approved for this scene."
            )
        }
        try db.execute(
            sql: """
                INSERT INTO scene_prompt_cards (
                    id, set_id, card_order, title, body, guidance,
                    duration_seconds, aspect_ratio, resolution
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString, setID.uuidString, order, draft.title, draft.body,
                draft.guidance, draft.durationSeconds, draft.aspectRatio, draft.resolution,
            ]
        )
        for (localOffset, sourcePosition) in positions.enumerated() {
            guard let planned = byPosition[sourcePosition],
                  let approved = planned.approvedVersion else { continue }
            try db.execute(
                sql: """
                    INSERT INTO scene_prompt_card_references (
                        id, card_id, position, requirement_id, version_id,
                        class, role, exclusion, fidelity, sha256, relative_path,
                        pixel_width, pixel_height, display_name, source, job_id, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString, id.uuidString, localOffset + 1,
                    planned.requirementID.uuidString, approved.versionID.uuidString,
                    planned.class.rawValue, planned.attributes.role,
                    planned.attributes.exclusion, planned.attributes.fidelity.rawValue,
                    approved.sha256, approved.relativePath, approved.pixelWidth,
                    approved.pixelHeight,
                    "\(planned.entityName) — \(planned.requirementName)",
                    source.rawValue, jobID?.uuidString, timestamp,
                ]
            )
        }
    }

    private static func validate(cards: [ScenePromptCardDraft], profile: TargetProfile) throws {
        _ = try ScenePromptSetProposal(
            sceneID: UUID(), cards: cards, settings: ScenePromptSettings()
        )
        for card in cards where !profile.accepts(
            durationSeconds: card.durationSeconds,
            aspectRatio: card.aspectRatio,
            resolution: card.resolution
        ) {
            throw ProjectStoreError.sceneOperationRefused(
                reason: "\(profile.displayName) does not accept a prompt card's settings."
            )
        }
    }

    private static func validateExisting(
        cards: [ScenePromptCard], profile: TargetProfile
    ) throws {
        let drafts = cards.map {
            ScenePromptCardDraft(
                title: $0.title, body: $0.body, guidance: $0.guidance,
                durationSeconds: $0.durationSeconds, aspectRatio: $0.aspectRatio,
                resolution: $0.resolution
            )
        }
        try validate(cards: drafts, profile: profile)
    }

    private static func existingDrafts(setID: UUID, in db: Database) throws -> [ScenePromptCardDraft] {
        try ProjectRepository.scenePromptCards(setID: setID, in: db).map {
            ScenePromptCardDraft(
                title: $0.title, body: $0.body, guidance: $0.guidance,
                durationSeconds: $0.durationSeconds, aspectRatio: $0.aspectRatio,
                resolution: $0.resolution,
                referencePositions: try ProjectRepository.scenePromptCardReferences(
                    cardID: $0.id, in: db
                ).map(\.position)
            )
        }
    }

    private static func markHumanEdited(setID: UUID, in db: Database) throws {
        try db.execute(
            sql: """
                UPDATE scene_prompt_sets
                SET human_edited = 1, source = 'human', updated_at = ? WHERE id = ?
                """,
            arguments: [UTCDate.string(from: Date()), setID.uuidString]
        )
    }

    private static func densify(setID: UUID, in db: Database) throws {
        let ids = try String.fetchAll(
            db,
            sql: "SELECT id FROM scene_prompt_cards WHERE set_id = ? ORDER BY card_order",
            arguments: [setID.uuidString]
        )
        try db.execute(
            sql: "UPDATE scene_prompt_cards SET card_order = card_order + 1000 WHERE set_id = ?",
            arguments: [setID.uuidString]
        )
        for (offset, id) in ids.enumerated() {
            try db.execute(
                sql: "UPDATE scene_prompt_cards SET card_order = ? WHERE id = ?",
                arguments: [offset + 1, id]
            )
        }
    }

    private static func restoreInverse(
        set: ScenePromptSet, oldRows: [RowSnapshot]
    ) -> MutationEffect {
        MutationEffect(
            inverse: .restoreScenePromptSet(
                payload: ScenePromptSetSnapshotPayload(
                    setID: set.id, sceneID: set.sceneID, rows: oldRows
                )
            ),
            affected: affected(setID: set.id, sceneID: set.sceneID, rows: oldRows),
            snapshots: oldRows
        )
    }

    private static func affected(
        setID: UUID, sceneID: UUID, rows: [RowSnapshot]
    ) -> Set<SubjectRef> {
        Set([
            SubjectRef(kind: .prompt, id: setID),
            SubjectRef(kind: .scene, id: sceneID),
        ]).union(RowGraph.subjects(of: rows))
    }

    private static func drafts(from rows: [RowSnapshot]) -> [ScenePromptCardDraft] {
        rows.filter { $0.table == "scene_prompt_cards" }
            .sorted { (int("card_order", in: [$0]) ?? 0) < (int("card_order", in: [$1]) ?? 0) }
            .map { row in
                let cardID = string("id", in: [row]) ?? ""
                let positions = rows.filter {
                    $0.table == "scene_prompt_card_references"
                        && string("card_id", in: [$0]) == cardID
                }.sorted {
                    (int("position", in: [$0]) ?? 0) < (int("position", in: [$1]) ?? 0)
                }.map { int("position", in: [$0]) ?? 0 }
                return ScenePromptCardDraft(
                    title: string("title", in: [row]) ?? "",
                    body: string("body", in: [row]) ?? "",
                    guidance: string("guidance", in: [row]) ?? "",
                    durationSeconds: int("duration_seconds", in: [row]),
                    aspectRatio: string("aspect_ratio", in: [row]) ?? "",
                    resolution: string("resolution", in: [row]) ?? "",
                    referencePositions: positions
                )
            }
    }

    private static func string(_ column: String, in rows: [RowSnapshot]) -> String? {
        for row in rows where row.table == "scene_prompt_sets" || rows.count == 1 {
            if case let .string(value)? = row.columns[column] { return value }
        }
        return nil
    }

    private static func int(_ column: String, in rows: [RowSnapshot]) -> Int? {
        for row in rows where row.table == "scene_prompt_sets" || rows.count == 1 {
            if case let .int(value)? = row.columns[column] { return value }
        }
        return nil
    }
}
