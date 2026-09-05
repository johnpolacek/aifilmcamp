import Foundation
import GRDB

/// §8.4's apply, in one transaction (PHASE2_DESIGN §8.4, §8.5; Plan 012 contract C).
///
/// `ExtractionApplier`'s pattern, member for member: the parent job is already
/// `committing`, every change is its own `SAVEPOINT` so a policy refusal demotes one
/// proposal instead of the run, each applied change journals one row under the fixed
/// `.ai(runJobID)` actor, and the parent is completed **inside** the same transaction with
/// its usage and its report — so report, usage, and completion are atomic with the rows
/// they describe.
///
/// What is new here is step 0: the run's input digest is re-verified against a rebuild of
/// `ManifestInputBuilder` inside this transaction. Equal ⟹ every predicate the validator
/// checked still holds, references included, which is why no step below performs a
/// per-reference existence check and why `ManifestApplyReport` carries no dangling counter.
enum ManifestApplier {
    static func apply(
        _ proposal: ManifestProposal,
        runJobID: UUID,
        usage: JobUsage,
        in db: Database
    ) throws -> ManifestApplyReport {
        let actor = MutationActor.ai(jobID: runJobID)
        let started = ContinuousClock.now

        // The parent, its task, and the digest it recorded at launch.
        guard let jobRow = try Row.fetchOne(
            db,
            sql: "SELECT state, parent_job_id, task, input_sha256 FROM jobs WHERE id = ?",
            arguments: [runJobID.uuidString]
        ) else { throw ProjectStoreError.jobNotFound }
        let task: String = jobRow["task"]
        guard task == Job.manifestTask else {
            throw ProjectStoreError.wrongJobTask(expected: Job.manifestTask, found: task)
        }
        let state = Job.State(rawValue: jobRow["state"]) ?? .failed
        let parentID: String? = jobRow["parent_job_id"]
        guard parentID == nil, state == .committing else {
            throw ProjectStoreError.illegalJobTransition(from: state, to: .completed)
        }

        // §8.4 step 5's pinned script, the same guard extraction applies.
        guard let scriptRow = try Row.fetchOne(
            db,
            sql: "SELECT id, sha256 FROM scripts WHERE id = ? AND id = (SELECT current_script_id FROM projects)",
            arguments: [proposal.scriptID.uuidString]
        ), (scriptRow["sha256"] as String) == proposal.scriptSHA256 else {
            throw ProjectStoreError.scriptChangedDuringRun
        }

        // §8.4 step 0. The script-hash guard above covers the screenplay; this covers
        // everything else — a deleted state, a rejected entity, a flipped override, a
        // disabled template entry — in one comparison rather than in a dozen predicates
        // that would inevitably miss one.
        let recordedDigest: String = jobRow["input_sha256"]
        let rebuilt = try ManifestInputBuilder.snapshot(in: db)
        guard rebuilt.text.sha256HexOfUTF8 == recordedDigest else {
            throw ProjectStoreError.manifestInputChangedDuringRun
        }

        var report = ManifestApplyReport(
            // §8.4 step 4: persisted in full, applied never.
            suggestions: proposal.inclusionSuggestions,
            settings: proposal.settings
        )
        var savepointIndex = 0
        let context = try Context(in: db)

        try applyImportantProps(
            proposal.importantProps,
            actor: actor,
            runJobID: runJobID,
            context: context,
            report: &report,
            savepointIndex: &savepointIndex,
            in: db
        )
        try applyVariants(
            proposal.variants,
            actor: actor,
            runJobID: runJobID,
            context: context,
            report: &report,
            savepointIndex: &savepointIndex,
            in: db
        )

        // Validated inference results are active immediately; users correct or reject the
        // exceptions instead of approving every ordinary result.
        try ReviewOperations.activateValidatedAIOutput(jobID: runJobID, in: db)

        report.durationMs = Int((ContinuousClock.now - started).components.seconds * 1_000)
        // §8.4 step 6's summary row: non-invertible, `compoundChildren = nil`, skipped by
        // selective revert.
        _ = try EditPrimitives.perform(
            .applyManifestRun(report), actor: actor, jobID: runJobID, in: db
        )
        // §8.5: the post-apply report lands through the internal `in db:` primitive, inside
        // this transaction — the public `setManifestReport` opens its own and refuses a
        // completed job, so it can only ever be the pre-apply zero-counter write.
        try ProjectRepository.writeManifestReport(report, jobID: runJobID, in: db)
        try completeParent(runJobID: runJobID, usage: usage, in: db)
        return report
    }

    // MARK: - What the transaction reads once

    /// The per-transaction lookups every step shares, all read **after** the digest guard,
    /// so they describe exactly the state the validator saw.
    private struct Context {
        /// Scene ordinal → id, over the run's pinned script (§8.4 step 5).
        let sceneIDsByOrdinal: [Int: UUID]
        /// Entity id → kind, for the props channel.
        let entityKinds: [UUID: EntityKind]
        /// Entity kind → its **enabled** `reference` template entry (§8.4 step 1).
        let referenceEntries: [EntityKind: (id: UUID, displayName: String)]

        init(in db: Database) throws {
            var ordinals: [Int: UUID] = [:]
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT scenes.id, scenes.ordinal FROM scenes
                    JOIN projects ON projects.current_script_id = scenes.script_id
                    """
            ) {
                ordinals[row["ordinal"]] = try UUID.required(row["id"])
            }
            sceneIDsByOrdinal = ordinals

            var kinds: [UUID: EntityKind] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, kind FROM entities") {
                guard let kind = EntityKind(rawValue: row["kind"]) else { continue }
                kinds[try UUID.required(row["id"])] = kind
            }
            entityKinds = kinds

            var entries: [EntityKind: (id: UUID, displayName: String)] = [:]
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT id, entity_kind, display_name FROM asset_requirement_types
                    WHERE is_enabled = 1 AND code = ?
                    """,
                arguments: [referenceTemplateCode]
            ) {
                guard let kind = EntityKind(rawValue: row["entity_kind"]) else { continue }
                entries[kind] = (try UUID.required(row["id"]), row["display_name"])
            }
            referenceEntries = entries
        }
    }

    /// The frozen template `code` an `importantProps` proposal fills (§3.2, §8.4 step 1).
    /// FilmBrain's validator refuses a proposal whose kind has no enabled entry with this
    /// code; the spelling is the same constant on both sides of the seam.
    static let referenceTemplateCode = "reference"

    // MARK: - Step 1: importantProps (§3.4, §8.4 step 1)

    private static func applyImportantProps(
        _ props: [ProposedPropRequirement],
        actor: MutationActor,
        runJobID: UUID,
        context: Context,
        report: inout ManifestApplyReport,
        savepointIndex: inout Int,
        in db: Database
    ) throws {
        for prop in props {
            // Unreachable behind the digest guard (the validator refused a prop whose kind
            // has no enabled reference entry, and the guard froze that state); counted
            // rather than dropped so nothing can vanish silently.
            guard let kind = context.entityKinds[prop.entityID],
                  let entry = context.referenceEntries[kind]
            else {
                report.skippedExisting += 1
                continue
            }

            // The match key is `(entity_id, enabled reference type_id)`. A tombstoned slot
            // counts as filled, which is what stops re-proposal.
            if let holderID = try RequirementOperations.canonicalSlotHolder(
                entityID: prop.entityID, typeID: entry.id, in: db
            ) {
                let holder = try RequirementOperations.require(id: holderID, in: db)
                if holder.reviewState == .rejected {
                    report.skippedRejected += 1
                } else if try isWhollyReplaceable(holder, in: db) {
                    try updateInPlace(
                        holder,
                        name: nil,
                        reason: prop.reason,
                        confidence: prop.confidence,
                        basis: prop.basis,
                        sceneIDs: nil,
                        actor: actor,
                        runJobID: runJobID,
                        report: &report,
                        savepointIndex: &savepointIndex,
                        in: db
                    )
                } else {
                    report.skippedExisting += 1
                }
                continue
            }

            // §5.2-style name collision with another requirement of the entity: a counted
            // skip, never a raw error.
            let requirementID = UUID()
            if try RequirementOperations.conflictingRequirementID(
                entityID: prop.entityID,
                normalized: EntityNormalization.normalize(entry.displayName),
                excluding: requirementID,
                in: db
            ) != nil {
                report.skippedExisting += 1
                continue
            }

            var createdRows = 0
            let applied = try applyChange(
                report: &report, savepointIndex: &savepointIndex, in: db
            ) {
                // Canonical tier, `ai`-sourced, born `proposed` (§3.7's row-source table);
                // scene links stay derived, as for every canonical requirement (§5.2).
                let outcome = try EditPrimitives.performDetailed(
                    .createRequirement(
                        id: requirementID,
                        entityID: prop.entityID,
                        tier: .canonical,
                        typeID: entry.id,
                        name: entry.displayName,
                        reason: prop.reason
                    ),
                    actor: actor, jobID: runJobID, in: db
                )
                try stampConfidence(prop.confidence, requirementID: requirementID, in: db)
                let basisRows = try insertBasis(
                    prop.basis, requirementID: requirementID, runJobID: runJobID, in: db
                )
                createdRows = 1 + basisRows + dependencyCount(of: outcome.entry)
            }
            if applied { report.created += createdRows }
        }
    }

    // MARK: - Step 2: variants (§8.4 step 2)

    private static func applyVariants(
        _ variants: [ProposedVariantRequirement],
        actor: MutationActor,
        runJobID: UUID,
        context: Context,
        report: inout ManifestApplyReport,
        savepointIndex: inout Int,
        in db: Database
    ) throws {
        for variant in variants {
            let normalized = EntityNormalization.normalize(variant.name)
            // §8.4 step 5: ordinals resolve to ids against the pinned script. The digest
            // guard means every ordinal the validator accepted still names a scene.
            let sceneIDs = variant.sceneOrdinals.compactMap { context.sceneIDsByOrdinal[$0] }

            // The match key is `(entity_id, name_normalized)` — the unique spans tiers, so
            // a canonical row of the same normalized name matches here too and lands in the
            // "anything else" arm rather than being rewritten across tiers.
            if let matchID = try RequirementOperations.conflictingRequirementID(
                entityID: variant.entityID, normalized: normalized, excluding: UUID(), in: db
            ) {
                let match = try RequirementOperations.require(id: matchID, in: db)
                if match.reviewState == .rejected {
                    report.skippedRejected += 1
                } else if match.tier == .variant, try isWhollyReplaceable(match, in: db) {
                    try updateInPlace(
                        match,
                        name: variant.name,
                        reason: variant.reason,
                        confidence: variant.confidence,
                        basis: variant.basis,
                        sceneIDs: sceneIDs,
                        actor: actor,
                        runJobID: runJobID,
                        report: &report,
                        savepointIndex: &savepointIndex,
                        in: db
                    )
                } else {
                    report.skippedExisting += 1
                }
                continue
            }

            let requirementID = UUID()
            var createdRows = 0
            let applied = try applyChange(
                report: &report, savepointIndex: &savepointIndex, in: db
            ) {
                // One change: the requirement, its scene links, its basis rows, and §3.5's
                // seeded dependencies (tombstoned pairs respected by `create` itself).
                var children: [EditOperation] = [
                    .createRequirement(
                        id: requirementID,
                        entityID: variant.entityID,
                        tier: .variant,
                        typeID: nil,
                        name: variant.name,
                        reason: variant.reason
                    ),
                ]
                children.append(contentsOf: sceneIDs.map { sceneID in
                    EditOperation.addRequirementScene(
                        requirementID: requirementID,
                        sceneID: sceneID,
                        linkID: UUID(),
                        restoring: []
                    )
                })
                let groupEntry = try EditPrimitives.performGroup(
                    children, as: .batch(children), actor: actor, jobID: runJobID, in: db
                )
                try stampConfidence(variant.confidence, requirementID: requirementID, in: db)
                let basisRows = try insertBasis(
                    variant.basis, requirementID: requirementID, runJobID: runJobID, in: db
                )
                createdRows = 1 + sceneIDs.count + basisRows + dependencyCount(of: groupEntry)
            }
            if applied { report.created += createdRows }
        }
    }

    // MARK: - The wholly-replaceable rule and the update branch (§8.4 steps 2, 3)

    /// §8.4 step 2's "wholly replaceable": the requirement and **every owned scene-link and
    /// dependency row** are still `ai`/`proposed`, and no `assets` row fills it — importing
    /// accepts implicitly (§7.3), so an asset implies accepted. Basis rows carry no review
    /// state and follow their requirement (§3.7), so they are not consulted.
    private static func isWhollyReplaceable(
        _ requirement: RequirementOperations.RequirementRow,
        in db: Database
    ) throws -> Bool {
        guard requirement.source == .ai, requirement.reviewState == .proposed else { return false }
        guard try !RequirementOperations.hasAsset(requirementID: requirement.id, in: db) else {
            return false
        }
        for table in ["asset_requirement_scenes", "asset_dependencies"] {
            let unreplaceable = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM \(table)
                    WHERE requirement_id = ?
                      AND NOT (source = 'ai' AND review_state = 'proposed')
                    """,
                arguments: [requirement.id.uuidString]
            ) ?? 0
            if unreplaceable > 0 { return false }
        }
        return true
    }

    /// §8.4 step 2's update-in-place, reconciling children by their stable keys (scene id;
    /// basis subject).
    ///
    /// **Defensive only** (§8.4 step 3): inference is run-once, so on the one real run no
    /// prior `ai`/`proposed` requirement exists to match, and a retry after a failure finds
    /// nothing applied because apply is one transaction. The branch is implemented because
    /// the design enumerates it, not because Phase 2 depends on it. `ManifestApplyReport`
    /// has no update counter by design (§8.5); rows the update *creates* are counted in
    /// `created`, and an update that changes nothing counts nothing.
    private static func updateInPlace(
        _ requirement: RequirementOperations.RequirementRow,
        name: String?,
        reason: String,
        confidence: Double,
        basis: ProposedRequirementBasis,
        sceneIDs: [UUID]?,
        actor: MutationActor,
        runJobID: UUID,
        report: inout ManifestApplyReport,
        savepointIndex: inout Int,
        in db: Database
    ) throws {
        var createdRows = 0
        let applied = try applyChange(
            report: &report, savepointIndex: &savepointIndex, in: db
        ) {
            var children: [EditOperation] = []
            if let name, name != requirement.name {
                children.append(.renameRequirement(id: requirement.id, name: name))
            }
            if reason != requirement.reason {
                children.append(.setRequirementReason(id: requirement.id, text: reason))
            }
            if let sceneIDs {
                var existing: [UUID: UUID] = [:]
                for row in try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, scene_id FROM asset_requirement_scenes
                        WHERE requirement_id = ? AND review_state <> 'rejected'
                        """,
                    arguments: [requirement.id.uuidString]
                ) {
                    existing[try UUID.required(row["scene_id"])] = try UUID.required(row["id"])
                }
                let desired = Set(sceneIDs)
                for sceneID in sceneIDs where existing[sceneID] == nil {
                    children.append(.addRequirementScene(
                        requirementID: requirement.id,
                        sceneID: sceneID,
                        linkID: UUID(),
                        restoring: []
                    ))
                    createdRows += 1
                }
                for (sceneID, linkID) in existing.sorted(by: { $0.value.uuidString < $1.value.uuidString })
                where !desired.contains(sceneID) {
                    children.append(.removeRequirementScene(linkID: linkID))
                }
            }
            if !children.isEmpty {
                _ = try EditPrimitives.performGroup(
                    children, as: .batch(children), actor: actor, jobID: runJobID, in: db
                )
            }
            try stampConfidence(confidence, requirementID: requirement.id, in: db)
            createdRows += try reconcileBasis(
                basis, requirementID: requirement.id, runJobID: runJobID, in: db
            )
        }
        if applied { report.created += createdRows }
    }

    // MARK: - Basis rows (§3.7's immutable citations)

    /// Inserts one basis row per cited subject and returns how many were written.
    @discardableResult
    private static func insertBasis(
        _ basis: ProposedRequirementBasis,
        requirementID: UUID,
        runJobID: UUID,
        in db: Database
    ) throws -> Int {
        let timestamp = UTCDate.string(from: Date())
        var written = 0
        var seen: Set<SubjectRef> = []
        for subject in basis.subjects where seen.insert(subject).inserted {
            try db.execute(
                sql: """
                    INSERT INTO asset_requirement_basis (
                        id, requirement_id, subject_kind, subject_id, source, job_id, created_at
                    ) VALUES (?, ?, ?, ?, 'ai', ?, ?)
                    """,
                arguments: [
                    UUID().uuidString, requirementID.uuidString, subject.kind.rawValue,
                    subject.id.uuidString, runJobID.uuidString, timestamp,
                ]
            )
            written += 1
        }
        return written
    }

    /// The update branch's basis reconciliation, keyed by `(subject_kind, subject_id)`.
    private static func reconcileBasis(
        _ basis: ProposedRequirementBasis,
        requirementID: UUID,
        runJobID: UUID,
        in db: Database
    ) throws -> Int {
        var existing: [SubjectRef: UUID] = [:]
        for row in try Row.fetchAll(
            db,
            sql: "SELECT id, subject_kind, subject_id FROM asset_requirement_basis WHERE requirement_id = ?",
            arguments: [requirementID.uuidString]
        ) {
            guard let kind = SubjectKind(rawValue: row["subject_kind"]) else { continue }
            existing[SubjectRef(kind: kind, id: try UUID.required(row["subject_id"]))] =
                try UUID.required(row["id"])
        }
        let desired = Set(basis.subjects)
        for (subject, id) in existing where !desired.contains(subject) {
            try db.execute(
                sql: "DELETE FROM asset_requirement_basis WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
        let missing = ProposedRequirementBasis(
            stateIDs: basis.stateIDs.filter { existing[SubjectRef(kind: .state, id: $0)] == nil },
            eventIDs: basis.eventIDs.filter { existing[SubjectRef(kind: .event, id: $0)] == nil },
            appearanceIDs: basis.appearanceIDs.filter {
                existing[SubjectRef(kind: .appearance, id: $0)] == nil
            }
        )
        return try insertBasis(missing, requirementID: requirementID, runJobID: runJobID, in: db)
    }

    // MARK: - Safe changes (`ExtractionApplier`'s pattern)

    private static func applyChange(
        report: inout ManifestApplyReport,
        savepointIndex: inout Int,
        in db: Database,
        body: () throws -> Void
    ) throws -> Bool {
        do {
            return try withSavepoint(index: &savepointIndex, in: db, body)
        } catch let error as ProjectStoreError {
            switch error {
            case .locked: report.skippedLocked += 1
            case .protectedFact, .parserOwned: report.skippedProtected += 1
            case .rejected: report.skippedRejected += 1
            // §8.4 steps 1 and 2: a name collision is a counted skip, never a raw error.
            case .requirementNameConflict, .requirementOperationRefused:
                report.skippedExisting += 1
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
        let name = "manifest_\(index)"
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

    // MARK: - Small shared pieces

    /// The §3.5 dependency rows an entry's create seeded, counted off its affected set —
    /// the operation owns the seeding, so this is the only honest place to count it.
    private static func dependencyCount(of entry: JournalEntry) -> Int {
        entry.affected.filter { $0.kind == .dependency }.count
    }

    private static func stampConfidence(
        _ confidence: Double,
        requirementID: UUID,
        in db: Database
    ) throws {
        try db.execute(
            sql: "UPDATE asset_requirements SET confidence = ? WHERE id = ?",
            arguments: [confidence, requirementID.uuidString]
        )
    }

    /// The parent's completion, in this transaction, with its usage (§8.1).
    private static func completeParent(
        runJobID: UUID,
        usage: JobUsage,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE jobs SET state = 'completed', progress_stage = 'Completed',
                    input_tokens = ?, cached_input_tokens = ?, cache_write_input_tokens = ?,
                    output_tokens = ?, reasoning_output_tokens = ?, ended_at = ?
                WHERE id = ? AND state = 'committing'
                """,
            arguments: [
                usage.inputTokens, usage.cachedInputTokens, usage.cacheWriteInputTokens,
                usage.outputTokens, usage.reasoningOutputTokens,
                UTCDate.string(from: Date()), runJobID.uuidString,
            ]
        )
        guard db.changesCount == 1 else {
            throw ProjectStoreError.databaseCommit("Parent completion failed.")
        }
    }
}
