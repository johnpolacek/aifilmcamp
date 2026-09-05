import Foundation
import GRDB

enum ExtractionApplier {
    static func apply(
        _ proposal: ExtractionProposal,
        runJobID: UUID,
        usage: JobUsage,
        in db: Database
    ) throws -> ApplyReport {
        let actor = MutationActor.ai(jobID: runJobID)
        let started = ContinuousClock.now
        guard let jobRow = try Row.fetchOne(
            db,
            sql: "SELECT state, parent_job_id FROM jobs WHERE id = ?",
            arguments: [runJobID.uuidString]
        ) else { throw ProjectStoreError.jobNotFound }
        let state = Job.State(rawValue: jobRow["state"]) ?? .failed
        let parentID: String? = jobRow["parent_job_id"]
        guard parentID == nil, state == .committing else {
            throw ProjectStoreError.illegalJobTransition(from: state, to: .completed)
        }
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT id, sha256 FROM scripts WHERE id = ? AND id = (SELECT current_script_id FROM projects)",
            arguments: [proposal.scriptID.uuidString]
        ), (row["sha256"] as String) == proposal.scriptSHA256 else {
            throw ProjectStoreError.scriptChangedDuringRun
        }

        var report = ApplyReport(
            mergesSuggested: proposal.mergeSuggestions.count,
            chunksFailed: proposal.chunksFailed,
            uncoveredSceneOrdinals: proposal.uncoveredSceneOrdinals,
            settings: proposal.settings
        )
        var savepointIndex = 0

        // Reconcile merge candidates run first. One candidate is one savepoint, so a
        // protected participant demotes the whole candidate instead of partly merging it.
        for candidate in proposal.mergeCandidates {
            let ids = try resolvedEntityIDs(
                kind: candidate.kind,
                forms: [candidate.name] + candidate.aliases,
                explicit: candidate.existingID,
                in: db
            )
            guard ids.count > 1 else { continue }
            let target = try preferredMergeTarget(ids, in: db)
            let sources = ids.filter { $0 != target }
            let merged: Bool
            do {
                merged = try withSavepoint(index: &savepointIndex, in: db) {
                    let aliasIDs = sources.map { _ in UUID() }
                    let compound = EditOperation.mergeEntities(
                        sourceIDs: sources,
                        into: target,
                        nameAliasIDs: aliasIDs
                    )
                    let outcome: (entry: JournalEntry, effect: MutationEffect)
                    if sources.count == 1 {
                        outcome = try EditPrimitives.performDetailed(
                            compound, actor: actor, jobID: runJobID, in: db
                        )
                    } else {
                        let children = zip(sources, aliasIDs).map { source, aliasID in
                            EditOperation.mergeEntities(
                                sourceIDs: [source], into: target, nameAliasIDs: [aliasID]
                            )
                        }
                        outcome = try EditPrimitives.performGroupDetailed(
                            children, as: compound, actor: actor, jobID: runJobID, in: db
                        )
                    }
                    report.aliasConflicts += outcome.effect.skippedAliases.count
                }
            } catch let error as ProjectStoreError {
                switch error {
                case .locked, .protectedFact, .parserOwned:
                    merged = false
                default:
                    throw error
                }
            }
            if merged {
                report.mergesApplied += sources.count
            } else {
                report.mergesSuggested += 1
            }
        }

        let preservedEntityIDs = try Set(proposal.entities.compactMap {
            try resolveEntity(kind: $0.kind, name: $0.name, in: db)?.id
        })
        try removeStaleProposals(
            preserving: preservedEntityIDs,
            runJobID: runJobID,
            actor: actor,
            report: &report,
            savepointIndex: &savepointIndex,
            in: db
        )

        var resolved: [String: UUID] = [:]
        for proposed in proposal.entities {
            let key = entityKey(kind: proposed.kind, name: proposed.name)
            let existing = try resolveEntity(kind: proposed.kind, name: proposed.name, in: db)
            if existing?.reviewState == .rejected {
                report.skippedRejected += 1
                continue
            }
            var entityID = existing?.id
            var touchedEntity = false
            if entityID == nil {
                let id = UUID()
                if try applyChange(
                    report: &report,
                    savepointIndex: &savepointIndex,
                    in: db,
                    body: {
                        _ = try EditPrimitives.perform(
                            .createEntity(
                                id: id,
                                kind: proposed.kind,
                                name: proposed.name,
                                description: proposed.description
                            ),
                            actor: actor,
                            jobID: runJobID,
                            in: db
                        )
                        try stampConfidence(proposed.evidence.confidence, ref: .init(kind: .entity, id: id), in: db)
                        try insertEvidence(proposed.evidence, ref: .init(kind: .entity, id: id), ownerEntityID: id, runJobID: runJobID, in: db)
                    }
                ) {
                    entityID = id
                    touchedEntity = true
                }
            } else if let id = entityID,
                      !proposed.description.isEmpty,
                      proposed.description != existing?.description {
                touchedEntity = try applyChange(
                    report: &report,
                    savepointIndex: &savepointIndex,
                    in: db,
                    body: {
                        _ = try EditPrimitives.perform(
                            .setDescription(id: id, text: proposed.description),
                            actor: actor, jobID: runJobID, in: db
                        )
                        try stampConfidence(proposed.evidence.confidence, ref: .init(kind: .entity, id: id), in: db)
                        try insertEvidence(proposed.evidence, ref: .init(kind: .entity, id: id), ownerEntityID: id, runJobID: runJobID, in: db)
                    }
                )
            }
            guard let entityID else { continue }
            resolved[key] = entityID

            for alias in proposed.aliases where !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if try aliasExists(entityID: entityID, alias: alias, in: db) { continue }
                _ = try applyChange(report: &report, savepointIndex: &savepointIndex, in: db) {
                    _ = try EditPrimitives.perform(
                        .addAlias(entityID: entityID, alias: alias, aliasID: UUID(), restoring: []),
                        actor: actor, jobID: runJobID, in: db
                    )
                }
            }
            for appearance in proposed.appearances {
                if try appearanceExists(sceneID: appearance.sceneID, entityID: entityID, role: appearance.role, in: db) {
                    continue
                }
                let appearanceID = UUID()
                _ = try applyChange(report: &report, savepointIndex: &savepointIndex, in: db) {
                    _ = try EditPrimitives.perform(
                        .setSceneEntity(
                            sceneID: appearance.sceneID,
                            entityID: entityID,
                            role: appearance.role,
                            appearanceID: appearanceID
                        ),
                        actor: actor, jobID: runJobID, in: db
                    )
                    try stampConfidence(appearance.evidence.confidence, ref: .init(kind: .appearance, id: appearanceID), in: db)
                    try insertEvidence(appearance.evidence, ref: .init(kind: .appearance, id: appearanceID), ownerEntityID: entityID, runJobID: runJobID, in: db)
                }
            }
            if !touchedEntity,
               try !evidenceExists(ref: .init(kind: .entity, id: entityID), quote: proposed.evidence.quote, jobID: runJobID, in: db) {
                try insertEvidence(proposed.evidence, ref: .init(kind: .entity, id: entityID), ownerEntityID: entityID, runJobID: runJobID, in: db)
            }
        }

        for synopsis in proposal.synopses {
            _ = try applyChange(report: &report, savepointIndex: &savepointIndex, in: db) {
                _ = try EditPrimitives.perform(
                    .setSynopsis(sceneID: synopsis.sceneID, text: synopsis.text),
                    actor: actor, jobID: runJobID, in: db
                )
                try stampConfidence(synopsis.evidence.confidence, ref: .init(kind: .synopsis, id: synopsis.sceneID), in: db)
                try insertEvidence(synopsis.evidence, ref: .init(kind: .synopsis, id: synopsis.sceneID), ownerEntityID: nil, runJobID: runJobID, in: db)
            }
        }

        for state in proposal.states {
            guard let entityID = try entityID(kind: state.entityKind, name: state.entityName, resolved: resolved, in: db) else {
                report.skippedRejected += 1
                continue
            }
            let id = UUID()
            _ = try applyChange(report: &report, savepointIndex: &savepointIndex, in: db) {
                _ = try EditPrimitives.perform(
                    .addState(
                        id: id, entityID: entityID, category: state.category,
                        description: state.description, startSceneID: state.startSceneID,
                        endSceneID: state.endSceneID, restoring: []
                    ),
                    actor: actor, jobID: runJobID, in: db
                )
                try stampConfidence(state.evidence.confidence, ref: .init(kind: .state, id: id), in: db)
                try insertEvidence(state.evidence, ref: .init(kind: .state, id: id), ownerEntityID: entityID, runJobID: runJobID, in: db)
            }
        }

        for event in proposal.events {
            let owner: UUID?
            if let name = event.entityName, let kind = event.entityKind {
                owner = try entityID(kind: kind, name: name, resolved: resolved, in: db)
            } else {
                owner = nil
            }
            if event.entityName != nil, owner == nil {
                report.skippedRejected += 1
                continue
            }
            let id = UUID()
            _ = try applyChange(report: &report, savepointIndex: &savepointIndex, in: db) {
                _ = try EditPrimitives.perform(
                    .addEvent(
                        id: id, sceneID: event.sceneID, entityID: owner,
                        description: event.description, resultingStateID: nil, restoring: []
                    ),
                    actor: actor, jobID: runJobID, in: db
                )
                try stampConfidence(event.evidence.confidence, ref: .init(kind: .event, id: id), in: db)
                try insertEvidence(event.evidence, ref: .init(kind: .event, id: id), ownerEntityID: owner, runJobID: runJobID, in: db)
            }
        }

        for relationship in proposal.relationships {
            guard let from = try entityID(kind: relationship.fromKind, name: relationship.fromName, resolved: resolved, in: db),
                  let to = try entityID(kind: relationship.toKind, name: relationship.toName, resolved: resolved, in: db)
            else {
                report.skippedRejected += 1
                continue
            }
            let id = UUID()
            _ = try applyChange(report: &report, savepointIndex: &savepointIndex, in: db) {
                _ = try EditPrimitives.perform(
                    .addRelationship(
                        id: id, fromEntityID: from, toEntityID: to,
                        kind: relationship.kind, description: relationship.description, restoring: []
                    ),
                    actor: actor, jobID: runJobID, in: db
                )
                try stampConfidence(relationship.evidence.confidence, ref: .init(kind: .relationship, id: id), in: db)
                try insertEvidence(relationship.evidence, ref: .init(kind: .relationship, id: id), ownerEntityID: from, runJobID: runJobID, in: db)
            }
        }

        // Canonical requirements are deterministic pipeline output, not a second task the
        // operator should have to discover and run after analysis. Build them in this same
        // transaction, after every extracted appearance is present, and tag the group with
        // the extraction run so Revert removes the requirements before it removes their
        // supporting facts. The internal mutation mode permits this deterministic
        // post-processing step without opening the public AI Build path; the requirements
        // themselves retain fixed `parser` provenance.
        let manifestPlan = try RequirementOperations.buildPlan(in: db)
        if manifestPlan.children.isEmpty == false {
            _ = try EditPrimitives.performGroup(
                manifestPlan.children,
                as: .refreshCanonicalRequirements,
                actor: actor,
                jobID: runJobID,
                mode: .refreshingCanonicalRequirements,
                in: db
            )
        }

        // The model output has already passed schema and semantic validation. Make every
        // fact created by this run immediately usable without claiming a human reviewed it.
        try ReviewOperations.activateValidatedAIOutput(jobID: runJobID, in: db)

        report.unanchoredEvidence = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM evidence WHERE job_id = ? AND anchored = 0",
            arguments: [runJobID.uuidString]
        ) ?? 0
        report.durationMs = Int((ContinuousClock.now - started).components.seconds * 1_000)
        _ = try EditPrimitives.perform(
            .applyExtractionRun(report), actor: actor, jobID: runJobID, in: db
        )
        let reportJSON = String(decoding: try JournalCoding.encoder.encode(report), as: UTF8.self)
        try db.execute(
            sql: """
                UPDATE jobs SET state = 'completed', progress_stage = 'Completed',
                    input_tokens = ?, cached_input_tokens = ?, cache_write_input_tokens = ?,
                    output_tokens = ?, reasoning_output_tokens = ?, apply_report = ?, ended_at = ?
                WHERE id = ? AND state = 'committing'
                """,
            arguments: [
                usage.inputTokens, usage.cachedInputTokens, usage.cacheWriteInputTokens,
                usage.outputTokens, usage.reasoningOutputTokens, reportJSON,
                UTCDate.string(from: Date()), runJobID.uuidString,
            ]
        )
        guard db.changesCount == 1 else { throw ProjectStoreError.databaseCommit("Parent completion failed.") }
        return report
    }

    // MARK: - Safe changes

    private static func applyChange(
        report: inout ApplyReport,
        savepointIndex: inout Int,
        in db: Database,
        body: () throws -> Void
    ) throws -> Bool {
        do {
            let applied = try withSavepoint(index: &savepointIndex, in: db, body)
            if applied { report.applied += 1 }
            return applied
        } catch let error as ProjectStoreError {
            switch error {
            case .locked: report.skippedLocked += 1
            case .protectedFact: report.skippedProtected += 1
            case .parserOwned: report.skippedParserOwned += 1
            case .rejected: report.skippedRejected += 1
            case .aliasConflict, .nameConflict: report.aliasConflicts += 1
            default: throw error
            }
            return false
        }
    }

    private static func withSavepoint(
        index: inout Int,
        in db: Database,
        _ body: () throws -> Void
    ) throws -> Bool {
        index += 1
        let name = "extraction_\(index)"
        try db.execute(sql: "SAVEPOINT \(name)")
        do {
            try body()
            try db.execute(sql: "RELEASE SAVEPOINT \(name)")
            return true
        } catch {
            try? db.execute(sql: "ROLLBACK TO SAVEPOINT \(name)")
            try? db.execute(sql: "RELEASE SAVEPOINT \(name)")
            throw error
        }
    }

    // MARK: - Replacement

    private static func removeStaleProposals(
        preserving entityIDs: Set<UUID>,
        runJobID: UUID,
        actor: MutationActor,
        report: inout ApplyReport,
        savepointIndex: inout Int,
        in db: Database
    ) throws {
        let staleEntities = try String.fetchAll(
            db,
            sql: "SELECT id FROM entities WHERE source = 'ai' AND review_state = 'proposed' AND (job_id IS NULL OR job_id <> ?)",
            arguments: [runJobID.uuidString]
        ).compactMap(UUID.init(uuidString:)).filter { !entityIDs.contains($0) }
        for id in staleEntities {
            if try applyChange(report: &report, savepointIndex: &savepointIndex, in: db, body: {
                guard let entity = try EntityOperations.fetch(id: id, in: db) else { return }
                _ = try EditPrimitives.perform(
                    .deleteEntity(id: id, kind: entity.kind), actor: actor, jobID: runJobID,
                    mode: .replacingAIProposal, in: db
                )
            }) {
                report.applied -= 1
                report.replaced += 1
            }
        }
        let staleAppearances = try String.fetchAll(
            db,
            sql: "SELECT id FROM scene_entities WHERE source = 'ai' AND review_state = 'proposed' AND (job_id IS NULL OR job_id <> ?)",
            arguments: [runJobID.uuidString]
        ).compactMap(UUID.init(uuidString:))
        for id in staleAppearances {
            if try applyChange(report: &report, savepointIndex: &savepointIndex, in: db, body: {
                _ = try EditPrimitives.perform(
                    .removeSceneEntity(appearanceID: id),
                    actor: actor, jobID: runJobID, in: db
                )
            }) {
                report.applied -= 1
                report.replaced += 1
            }
        }
        let scalarTables: [(String, SubjectKind, (UUID) -> EditOperation)] = [
            ("entity_states", .state, { .removeState(id: $0) }),
            ("continuity_events", .event, { .removeEvent(id: $0) }),
            ("entity_relationships", .relationship, { .removeRelationship(id: $0) }),
        ]
        for (table, _, operation) in scalarTables {
            let ids = try String.fetchAll(
                db,
                sql: "SELECT id FROM \(table) WHERE source = 'ai' AND review_state = 'proposed' AND (job_id IS NULL OR job_id <> ?)",
                arguments: [runJobID.uuidString]
            ).compactMap(UUID.init(uuidString:))
            for id in ids {
                if try applyChange(report: &report, savepointIndex: &savepointIndex, in: db, body: {
                    _ = try EditPrimitives.perform(
                        operation(id), actor: actor, jobID: runJobID,
                        mode: .replacingAIProposal, in: db
                    )
                }) {
                    report.applied -= 1
                    report.replaced += 1
                }
            }
        }
        let staleSynopses = try String.fetchAll(
            db,
            sql: "SELECT id FROM scenes WHERE synopsis_source = 'ai' AND synopsis_review_state = 'proposed' AND (synopsis_job_id IS NULL OR synopsis_job_id <> ?)",
            arguments: [runJobID.uuidString]
        ).compactMap(UUID.init(uuidString:))
        for sceneID in staleSynopses {
            if try applyChange(report: &report, savepointIndex: &savepointIndex, in: db, body: {
                _ = try EditPrimitives.perform(
                    .setSynopsis(sceneID: sceneID, text: ""),
                    actor: actor, jobID: runJobID, mode: .replacingAIProposal, in: db
                )
                try db.execute(
                    sql: "DELETE FROM evidence WHERE subject_kind = 'synopsis' AND subject_id = ?",
                    arguments: [sceneID.uuidString]
                )
                try db.execute(
                    sql: """
                        UPDATE scenes SET synopsis = '', synopsis_source = NULL,
                            synopsis_created_source = NULL, synopsis_confidence = NULL,
                            synopsis_review_state = NULL, synopsis_reviewed_at = NULL,
                            synopsis_job_id = NULL, synopsis_updated_at = NULL
                        WHERE id = ?
                        """,
                    arguments: [sceneID.uuidString]
                )
            }) {
                report.applied -= 1
                report.replaced += 1
            }
        }
    }

    // MARK: - Resolution and metadata

    private struct EntityMatch {
        let id: UUID
        let description: String
        let reviewState: ReviewState
    }

    private static func resolveEntity(kind: EntityKind, name: String, in db: Database) throws -> EntityMatch? {
        let normalized = EntityNormalization.normalize(name)
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT entities.id, entities.description, entities.review_state
                FROM entities
                LEFT JOIN entity_aliases ON entity_aliases.entity_id = entities.id
                WHERE entities.kind = ?
                  AND (entities.name_normalized = ? OR entity_aliases.normalized = ?)
                ORDER BY CASE WHEN entities.name_normalized = ? THEN 0 ELSE 1 END, entities.created_at, entities.id
                LIMIT 1
                """,
            arguments: [kind.rawValue, normalized, normalized, normalized]
        ) else { return nil }
        return EntityMatch(
            id: try UUID.required(row["id"]),
            description: row["description"],
            reviewState: ReviewState(rawValue: row["review_state"]) ?? .proposed
        )
    }

    private static func entityID(
        kind: EntityKind,
        name: String,
        resolved: [String: UUID],
        in db: Database
    ) throws -> UUID? {
        if let id = resolved[entityKey(kind: kind, name: name)] { return id }
        return try resolveEntity(kind: kind, name: name, in: db)?.id
    }

    private static func entityKey(kind: EntityKind, name: String) -> String {
        "\(kind.rawValue):\(EntityNormalization.normalize(name))"
    }

    private static func resolvedEntityIDs(
        kind: EntityKind,
        forms: [String],
        explicit: UUID?,
        in db: Database
    ) throws -> [UUID] {
        var ids: [UUID] = []
        if let explicit { ids.append(explicit) }
        for form in forms {
            if let id = try resolveEntity(kind: kind, name: form, in: db)?.id, !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    private static func preferredMergeTarget(_ ids: [UUID], in db: Database) throws -> UUID {
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT id, source, review_state, created_at FROM entities WHERE id IN (\(placeholders))",
            arguments: StatementArguments(ids.map(\.uuidString))
        )
        let ranked = try rows.map { row -> (UUID, Int, String) in
            let source = FactSource(rawValue: row["source"]) ?? .ai
            let state = ReviewState(rawValue: row["review_state"]) ?? .proposed
            let rank = source == .human ? 3 : (source == .ai && state == .accepted ? 2 : (source == .parser ? 1 : 0))
            return (try UUID.required(row["id"]), rank, row["created_at"])
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            return lhs.0.uuidString < rhs.0.uuidString
        }
        guard let target = ranked.first?.0 else { throw ProjectStoreError.entityNotFound }
        return target
    }

    private static func aliasExists(entityID: UUID, alias: String, in db: Database) throws -> Bool {
        (try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM entity_aliases WHERE entity_id = ? AND normalized = ?",
            arguments: [entityID.uuidString, EntityNormalization.normalize(alias)]
        ) ?? 0) > 0
    }

    private static func appearanceExists(
        sceneID: UUID, entityID: UUID, role: SceneEntityRole, in db: Database
    ) throws -> Bool {
        (try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM scene_entities WHERE scene_id = ? AND entity_id = ? AND role = ?",
            arguments: [sceneID.uuidString, entityID.uuidString, role.rawValue]
        ) ?? 0) > 0
    }

    private static func stampConfidence(_ confidence: Double, ref: SubjectRef, in db: Database) throws {
        let table: String
        switch ref.kind {
        case .entity: table = "entities"
        case .alias: table = "entity_aliases"
        case .appearance: table = "scene_entities"
        case .state: table = "entity_states"
        case .event: table = "continuity_events"
        case .relationship: table = "entity_relationships"
        case .synopsis:
            try db.execute(
                sql: "UPDATE scenes SET synopsis_confidence = ? WHERE id = ?",
                arguments: [confidence, ref.id.uuidString]
            )
            return
        case .scene, .script: return
        // Extraction proposes no manifest row — those are the manifest run's (Plan 012's)
        // and reach `confidence` through their own applier — so the v4 kinds land in the
        // same no-op arm `scene` and `script` already take. Not a §7.5 switch point: this
        // arm is widened only because the switch is exhaustive over `SubjectKind`. The
        // prompt kinds join it for the same reason (PHASE3_DESIGN §7.4): extraction
        // proposes no prompt row.
        case .requirement, .requirementScene, .basis, .dependency, .asset, .version,
             .templateEntry, .prompt, .promptReference:
            return
        }
        try db.execute(sql: "UPDATE \(table) SET confidence = ? WHERE id = ?", arguments: [confidence, ref.id.uuidString])
    }

    private static func insertEvidence(
        _ evidence: ProposedEvidence,
        ref: SubjectRef,
        ownerEntityID: UUID?,
        runJobID: UUID,
        in db: Database
    ) throws {
        let anchor = try anchoredSpan(quote: evidence.quote, sceneID: evidence.sceneID, in: db)
        if anchor == nil {
            try stampConfidence(min(evidence.confidence, 0.5), ref: ref, in: db)
        }
        let timestamp = UTCDate.string(from: Date())
        try db.execute(
            sql: """
                INSERT INTO evidence (
                    id, subject_kind, subject_id, owner_entity_id, scene_id, matched_alias_id,
                    start_utf16, end_utf16, anchored, quote, source, job_id, created_at
                ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, 'ai', ?, ?)
                """,
            arguments: [
                UUID().uuidString, ref.kind.rawValue, ref.id.uuidString,
                ownerEntityID?.uuidString, evidence.sceneID.uuidString,
                anchor?.startUTF16, anchor?.endUTF16, anchor == nil ? 0 : 1,
                evidence.quote, runJobID.uuidString, timestamp,
            ]
        )
    }

    private static func evidenceExists(
        ref: SubjectRef, quote: String, jobID: UUID, in db: Database
    ) throws -> Bool {
        (try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM evidence WHERE subject_kind = ? AND subject_id = ? AND quote = ? AND job_id = ?",
            arguments: [ref.kind.rawValue, ref.id.uuidString, quote, jobID.uuidString]
        ) ?? 0) > 0
    }

    private static func anchoredSpan(quote: String, sceneID: UUID, in db: Database) throws -> AnchoredSpan? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT scenes.start_utf16, scenes.end_utf16, scripts.source_text
                FROM scenes JOIN scripts ON scripts.id = scenes.script_id
                WHERE scenes.id = ?
                """,
            arguments: [sceneID.uuidString]
        ) else { throw ProjectStoreError.sceneNotFound }
        let start: Int = row["start_utf16"]
        let end: Int = row["end_utf16"]
        let source: String = row["source_text"]
        let sceneText = String(decoding: Array(source.utf16)[start..<end], as: UTF16.self)
        let exclusions = try Row.fetchAll(
            db,
            sql: "SELECT * FROM scene_exclusions WHERE scene_id = ? ORDER BY start_utf16, end_utf16",
            arguments: [sceneID.uuidString]
        ).compactMap { row -> SceneExclusion? in
            guard let kind = SceneExclusionKind(rawValue: row["kind"]) else { return nil }
            return SceneExclusion(
                id: try UUID.required(row["id"]), sceneID: sceneID, kind: kind,
                range: .init(start: row["start_utf16"], end: row["end_utf16"])
            )
        }
        return EvidenceAnchor.locate(
            quote: quote,
            in: EvidenceAnchor.redact(
                sceneText: sceneText, exclusions: exclusions, sceneStartUTF16: start
            )
        )
    }
}
