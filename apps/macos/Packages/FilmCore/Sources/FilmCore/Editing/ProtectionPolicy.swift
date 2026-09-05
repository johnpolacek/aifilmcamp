import Foundation
import GRDB

/// PHASE1_DESIGN §3.6's protection rules, as one policy every operation consults.
///
/// The three refusals, in the order they are checked:
///
/// 1. `.locked(subject:field:)` — §3.7, for **both** actors; the human path clears it with
///    an explicit `unlock`. Checked first because a lock is the more specific answer: a
///    locked parser row refuses with the lock, not with the parser.
/// 2. `.parserOwned(subject:field:)` — §3.6's parser-owned fields, for `.ai` only.
/// 3. `.protectedFact(subject:)` — a `human` row, or an `ai` row a person has accepted,
///    for `.ai` only.
///
/// A `.human` actor is never refused by 2 or 3: protection is a rule about what the
/// **analysis** may do to the operator's work, not the other way round.
enum ProtectionPolicy {

    /// One row as the protection rules see it.
    struct Subject {
        let ref: SubjectRef
        let source: FactSource
        let reviewState: ReviewState

        /// §3.6: AI may neither modify nor delete a protected row.
        var isProtected: Bool { source == .human || (source == .ai && reviewState == .accepted) }
        /// §3.6: parser rows are authoritative for the fields the parser owns.
        var isParserRow: Bool { source == .parser }
    }

    /// The fields the parser owns on a row of that kind (§3.6).
    ///
    /// `entity`: `kind`, `name`, `is_relevant`, and the record itself (delete or reject) —
    /// `description` is deliberately absent, because AI may fill an **empty** parser
    /// description; `checkEntityEdit` carries that exception.
    /// `alias`: the record — a parser cue or heading alias may not be removed or edited.
    /// `appearance`: the record — the parser's `speaking`/`setting` rows are authoritative.
    static func parserOwnedFields(of kind: SubjectKind) -> Set<LockField> {
        switch kind {
        case .entity: [.name, .kind, .isRelevant, .whole]
        case .alias, .appearance: [.whole]
        // PHASE2_DESIGN §3.7, §7.5: on a `parser`-sourced canonical requirement — where
        // `parser` reads as "deterministic app pipeline" — the parser owns the **name**
        // and the **record itself**: "AI may never rename one … and AI may never delete
        // one; the human may". `.whole` therefore sits here exactly as it does for
        // `entity`, and for the same two operations — `deleteRequirement` and
        // `rejectRequirement` both ask with `.whole`. The scene links and dependency rows
        // of such a requirement are separate kinds with their own (empty) entries, so
        // nothing here touches an AI tombstone-removal of one.
        case .requirement: [.name, .whole]
        // The parser writes no state, event, relationship, or synopsis (§5.3), and no
        // scene link, basis row, dependency, asset, version, or template entry, so nothing
        // of those kinds is ever parser-owned.
        case .scene, .state, .event, .relationship, .synopsis, .script: []
        case .requirementScene, .basis, .dependency, .asset, .version, .templateEntry: []
        // PHASE3_DESIGN §7.4: the parser writes no prompt or citation row.
        case .prompt, .promptReference: []
        // PHASE3_DESIGN §7.4: the parser writes no prompt or citation row, so nothing of
        // those kinds is ever parser-owned.
        }
    }

    // MARK: - The general guard

    /// §3.6 + §3.7 for a change to one field of one row.
    ///
    /// `field` is `.whole` for a delete, a reject, or any other change to the record
    /// itself, which §3.7 puts under the whole-record lock alone — a `description` lock
    /// pins the description, not the row's existence. Merge and split are the operations
    /// that *any* lock refuses, and they ask `LockPolicy.checkFree` instead.
    static func checkEdit(
        _ subject: Subject,
        field: LockField,
        actor: MutationActor,
        in db: Database
    ) throws {
        try LockPolicy.checkUnlocked(subject: subject.ref, field: field, in: db)
        guard actor != .human else { return }
        if subject.isParserRow, parserOwnedFields(of: subject.ref.kind).contains(field) {
            throw ProjectStoreError.parserOwned(subject: subject.ref, field: field)
        }
        if subject.isProtected {
            throw ProjectStoreError.protectedFact(subject: subject.ref)
        }
    }

    // MARK: - Entities

    /// The entity-shaped guard, carrying §3.6's one exception: `.ai` may fill a parser
    /// entity's **empty** description, and may not overwrite a description that has text
    /// in it.
    static func checkEntityEdit(
        _ entity: EntityOperations.EntityRow,
        field: LockField,
        actor: MutationActor,
        in db: Database
    ) throws {
        if field == .description, actor != .human, entity.source == .parser {
            try LockPolicy.checkUnlocked(subject: entity.ref, field: field, in: db)
            guard entity.description.isEmpty else {
                throw ProjectStoreError.parserOwned(subject: entity.ref, field: .description)
            }
            return
        }
        try checkEdit(subject(of: entity), field: field, actor: actor, in: db)
    }

    /// "Move into…". §3.7 enumerates no `parent_id` lock, so only a **whole-record** lock
    /// pins the link — a name lock leaves it free — and the parser owns no parent, so a
    /// parser location may be moved by either actor.
    static func checkLocationParentEdit(
        _ entity: EntityOperations.EntityRow,
        actor: MutationActor,
        in db: Database
    ) throws {
        if try LockPolicy.hasWholeLock(subject: entity.ref, in: db) {
            throw ProjectStoreError.locked(subject: entity.ref, field: .whole)
        }
        guard actor != .human else { return }
        if subject(of: entity).isProtected {
            throw ProjectStoreError.protectedFact(subject: entity.ref)
        }
    }

    static func subject(of entity: EntityOperations.EntityRow) -> Subject {
        Subject(ref: entity.ref, source: entity.source, reviewState: entity.reviewState)
    }

    // MARK: - Aliases (§3.5: append-only for AI)

    /// Adding an alias. For `.ai` this is refused **only** by a whole-record lock on the
    /// entity (§3.5: "A whole-record lock additionally forbids AI alias addition"); a
    /// protected or parser entity still accepts new aliases, which is what makes a run's
    /// normalization possible.
    ///
    /// A whole-record lock refuses the human path too — the record is pinned, and the UI
    /// shows it read-only with an Unlock control (§3.7).
    static func checkAliasAddition(
        toEntity ref: SubjectRef,
        actor _: MutationActor,
        in db: Database
    ) throws {
        if try LockPolicy.hasWholeLock(subject: ref, in: db) {
            throw ProjectStoreError.locked(subject: ref, field: .whole)
        }
    }

    /// Removing an alias. Any lock on the alias itself — an **alias lock** pins that
    /// surface form to its entity — or a whole-record lock on its entity refuses for both
    /// actors; `.ai` is refused outright, because for the AI actor aliases are
    /// append-only "whatever the entity's review state" (§3.5).
    static func checkAliasRemoval(
        _ alias: AliasOperations.AliasRow,
        actor: MutationActor,
        in db: Database
    ) throws {
        try LockPolicy.checkUnlocked(subject: alias.ref, field: .whole, in: db)
        let entityRef = SubjectRef(kind: .entity, id: alias.entityID)
        if try LockPolicy.hasWholeLock(subject: entityRef, in: db) {
            throw ProjectStoreError.locked(subject: entityRef, field: .whole)
        }
        guard actor != .human else { return }
        // The parser owns its cue and heading aliases; every other alias is refused as a
        // protected fact, because append-only admits no removal at all.
        if alias.source == .parser {
            throw ProjectStoreError.parserOwned(subject: alias.ref, field: .whole)
        }
        throw ProjectStoreError.protectedFact(subject: alias.ref)
    }

    // MARK: - Merge (§3.5's AI exception)

    /// The merge-source rule. Any lock over the source or one of its aliases refuses for
    /// both actors; for `.ai`, a **protected** source — one a human edited, or an AI
    /// proposal a human accepted — refuses with `.protectedFact`.
    ///
    /// A `parser` source is deliberately **allowed** for `.ai`: §3.5's exception exists
    /// because `SARAH` and `SARAH MORGAN` both arrive as parser cues, and without it no
    /// run could normalize them.
    static func checkMergeSource(
        _ source: EntityOperations.EntityRow,
        aliasIDs: [UUID],
        actor: MutationActor,
        in db: Database
    ) throws {
        if let lock = try LockPolicy.firstLock(entity: source.id, aliases: aliasIDs, in: db) {
            throw ProjectStoreError.locked(subject: lock.subject, field: lock.field)
        }
        guard actor != .human else { return }
        if subject(of: source).isProtected {
            throw ProjectStoreError.protectedFact(subject: source.ref)
        }
    }

    /// The merge-target rule: a **whole-record** lock refuses the merge for both actors,
    /// because the merge adds an alias to the target; a field lock does not (§3.5).
    ///
    /// A merely protected target — one a human renamed, say — still receives the alias:
    /// §3.5 makes AI aliases append-only rather than forbidden, and §3.6 states that AI
    /// "may still add new appearance/evidence rows that reference a protected entity". The
    /// merge adds to the target and changes nothing that was there.
    static func checkMergeTarget(
        _ target: EntityOperations.EntityRow,
        actor _: MutationActor,
        in db: Database
    ) throws {
        if try LockPolicy.hasWholeLock(subject: target.ref, in: db) {
            throw ProjectStoreError.locked(subject: target.ref, field: .whole)
        }
    }

    // MARK: - Appearances, states, events, relationships, synopses

    /// Adding an appearance, a state, an event, a relationship, or evidence that
    /// references an entity: §3.7 says locks never block those, and §3.6 says AI may add
    /// rows that reference a protected entity — so there is nothing to refuse.
    ///
    /// The function exists so the rule is stated once, in the policy, rather than as an
    /// absent check in five operations.
    static func checkReferenceAddition(toEntity _: SubjectRef, actor _: MutationActor) {}

    /// A scene synopsis. The **lock** lives on the scene (`scene`/`synopsis`, §3.7) while
    /// the protected subject is the synopsis itself (`synopsis`/`sceneID`, §4.3's PROV
    /// column set) — the one place where the two subjects of a rule differ.
    ///
    /// The parser writes no synopsis, so nothing here is ever parser-owned.
    static func checkSynopsisEdit(
        sceneID: UUID,
        source: FactSource?,
        reviewState: ReviewState?,
        actor: MutationActor,
        in db: Database
    ) throws {
        try LockPolicy.checkUnlocked(
            subject: SubjectRef(kind: .scene, id: sceneID), field: .synopsis, in: db
        )
        guard actor != .human, let source else { return }
        let subject = Subject(
            ref: SubjectRef(kind: .synopsis, id: sceneID),
            source: source,
            reviewState: reviewState ?? .proposed
        )
        if subject.isProtected { throw ProjectStoreError.protectedFact(subject: subject.ref) }
    }

    /// A change to a fact row that carries its own PROV columns.
    static func checkFactEdit(
        ref: SubjectRef,
        source: FactSource,
        reviewState: ReviewState,
        field: LockField = .whole,
        actor: MutationActor,
        in db: Database
    ) throws {
        try checkEdit(
            Subject(ref: ref, source: source, reviewState: reviewState),
            field: field,
            actor: actor,
            in: db
        )
    }
}
