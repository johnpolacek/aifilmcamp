import Foundation
import GRDB

/// Selective revert of one extraction run (PHASE1_DESIGN §3.8).
///
/// The walk is `edit_journal WHERE job_id = ? ORDER BY seq DESC`, newest change first, and
/// every eligible entry's inverse is applied through the **`mutate`** level: §3.8 gives the
/// whole revert *one* journal row — `perform(.revertExtractionRun)` writes it — so the
/// per-entry inverses must journal nothing of their own. The rows they restore travel into
/// that single entry's payload and their subjects into its `affected` set, which keeps the
/// journal an honest record of what the revert actually did.
///
/// Like everything under `Editing/`, this assumes an **open transaction** and never opens
/// one: the revert is one transaction (§3.8), and `DatabaseQueue` is not reentrant.
enum RevertOperations {

    /// Applies the run's inverses that are still safe to apply and reports the rest.
    ///
    /// Three reasons an entry is skipped, all of them "a person has been here since":
    ///
    /// 1. its `affected` set meets a later **uncancelled** `human` entry's — §3.8's shared
    ///    conflict rule, the same one undo uses;
    /// 2. a person has already inverted it, so the entry is no longer live and its change
    ///    is not in the project to undo twice;
    /// 3. it is **transitively** behind one of those: an earlier entry of the run whose
    ///    `affected` meets a skipped entry's — otherwise inverting the run's `createEntity`
    ///    would cascade-delete the human-edited alias the first skip just preserved.
    static func revert(
        jobID: UUID,
        actor: MutationActor,
        in db: Database
    ) throws -> MutationEffect {
        precondition(db.isInsideTransaction, "revert must run inside an open transaction (§3.8)")
        try requireNewestRun(jobID: jobID, in: db)

        let entries = try JournalStore.entries(jobID: jobID, in: db)
        let ledger = try JournalStore.ledger(in: db)
        let live = InverseApplication.liveSeqs(ledger)

        var reverted = 0
        var skippedSubjects: Set<SubjectRef> = []
        var skipped = 0
        // What the skips protect: every subject a skipped entry touched **plus the entity
        // each of those rows hangs off**, because deleting an entity cascades its aliases,
        // appearances, states, events, and relationships away with it.
        var protectedSubjects: Set<SubjectRef> = []
        var affected: Set<SubjectRef> = []
        var snapshots: [RowSnapshot] = []

        for entry in entries {
            // The trailing summary row carries the run's report and nothing else: it is
            // skipped, never inverted, and counts as neither reverted nor skipped (§3.8).
            // PHASE2_DESIGN §7.5 adds the manifest run's summary case beside extraction's.
            if case .applyExtractionRun = entry.op { continue }
            if case .applyManifestRun = entry.op { continue }

            guard let inverse = entry.inverse,
                  live.contains(entry.seq),
                  entry.affected.isDisjoint(with: protectedSubjects),
                  try !InverseApplication.conflictsWithLaterHumanEdit(
                      entry, ledger: ledger, live: live, in: db
                  )
            else {
                skipped += 1
                skippedSubjects.formUnion(entry.affected)
                protectedSubjects.formUnion(try protectedRows(of: entry, in: db))
                continue
            }

            // `.inverting(of: entry)` is what makes an inverse restore the snapshotted
            // timestamps and review columns instead of stamping "now", and what lets it
            // delete a row §3.6 would otherwise tombstone — the row was the run's own.
            let effect = try EditPrimitives.mutate(
                inverse, actor: actor, mode: .inverting(of: entry), in: db
            )
            reverted += 1
            affected.formUnion(effect.affected)
            snapshots.append(contentsOf: effect.snapshots)
        }

        return MutationEffect(
            // Non-invertible by contract (§3.8): a revert is not itself undoable.
            inverse: nil,
            affected: affected,
            snapshots: snapshots,
            revertReport: RevertReport(
                jobID: jobID,
                reverted: reverted,
                skipped: skipped,
                skippedSubjects: skippedSubjects.sorted(by: ReviewOperations.order)
            )
        )
    }

    // MARK: - Only the newest run is revertible (§3.8)

    /// Refuses with `.newerRunExists(jobID:)` when a **completed** parentless run of any
    /// revertible task has journal entries newer than this run's.
    ///
    /// The task filter is widened per PHASE2_DESIGN §7.5: it once hard-coded
    /// `extractScreenplay`, so without this a manifest run could never be reverted (any
    /// completed extraction run would read as newer) and a newer manifest run would fail to
    /// block an extraction revert. Both tasks are ordered in **one** journal-sequence
    /// ordering, so newest-run-only holds across run types.
    ///
    /// The id in the error is the run that blocks — the one the UI's "Revert last run"
    /// would revert instead.
    private static func requireNewestRun(jobID: UUID, in db: Database) throws {
        var ownNewest: Int64?
        var blocking: (jobID: UUID, seq: Int64)?
        for row in try Row.fetchAll(
            db,
            sql: """
                SELECT jobs.id AS run_id, MAX(edit_journal.seq) AS newest
                FROM jobs
                JOIN edit_journal ON edit_journal.job_id = jobs.id
                WHERE jobs.task IN (?, ?)
                  AND jobs.parent_job_id IS NULL
                  AND jobs.state = 'completed'
                GROUP BY jobs.id
                """,
            arguments: [Job.extractionTask, Job.manifestTask]
        ) {
            let runID = try UUID.required(row["run_id"])
            let newest: Int64 = row["newest"]
            if runID == jobID {
                ownNewest = newest
            } else if newest > (blocking?.seq ?? Int64.min) {
                blocking = (runID, newest)
            }
        }
        guard let blocking, blocking.seq > (ownNewest ?? Int64.min) else { return }
        throw ProjectStoreError.newerRunExists(jobID: blocking.jobID)
    }

    // MARK: - Transitive skips

    /// The subjects a skipped entry protects: the rows it touched, and the entity each of
    /// those rows belongs to.
    ///
    /// The owner is what makes the skip transitive in the case §3.8 names — a person edits
    /// an **alias** or an **appearance** the run created, so the run's `createEntity` of
    /// its entity must be skipped as well or the delete cascades the edited row away.
    private static func protectedRows(
        of entry: JournalEntry,
        in db: Database
    ) throws -> Set<SubjectRef> {
        var subjects = entry.affected
        for ref in entry.affected where ref.kind != .entity {
            guard let owner = try InverseApplication.owningEntityID(of: ref, entry: entry, in: db)
            else { continue }
            subjects.insert(SubjectRef(kind: .entity, id: owner))
        }
        return subjects
    }
}
