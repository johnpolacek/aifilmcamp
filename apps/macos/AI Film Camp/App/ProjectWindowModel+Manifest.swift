import FilmCore
import Foundation

/// The Manifest section's state and commands on the **window model** (PHASE2_DESIGN §5,
/// §6.1, §6.4, §8.6 — Plan 010 contract D).
///
/// Every filter, predicate, and action lives here rather than in a view, for the reason
/// Plan 010's maintenance note gives: Plan 012's proposal review reuses this grammar, and
/// a rule restated inside a `View` body cannot be reused or unit-tested. The views read
/// these values and call these methods; they never construct an `EditOperation`, never
/// query the store, and never decide what a selection admits.
///
/// Each command has the same four beats as the Phase 1 editing commands — perform as
/// `.human`, `didApply` the entry, `refresh()`, surface FilmCore's refusal verbatim — and
/// runs through the same `runEdit` body.
@MainActor
extension ProjectWindowModel {

    // MARK: - Selection

    /// The selected requirement rows, in list order.
    var selectedRequirementSummaries: [RequirementSummary] {
        let ids = selection(in: .manifest)
        return requirementSummaries.filter { ids.contains($0.id) }
    }

    var selectedRequirementIDs: [UUID] { selectedRequirementSummaries.map(\.id) }

    /// The one selected requirement, or `nil` for an empty or multiple selection.
    var selectedRequirementSummary: RequirementSummary? {
        let selected = selectedRequirementSummaries
        return selected.count == 1 ? selected[0] : nil
    }

    var selectedRequirementID: UUID? { selectedRequirementSummary?.id }

    // MARK: - Reads

    /// §7.6's inspector read for the current selection.
    func loadRequirementDetail() async {
        guard !isClosed, let id = selectedRequirementID else {
            requirementDetail = nil
            return
        }
        do {
            requirementDetail = try await session.requirement(id: id)
        } catch {
            requirementDetail = nil
            self.error = .project(error)
        }
    }

    /// §8.6's Proposed / Accepted / Rejected grammar. Like the entity filter this drives
    /// the read itself — `.rejected` is the only way to see a requirement tombstone at all.
    func setRequirementReviewFilter(_ filter: RequirementReviewFilter) async {
        guard filter != requirementReviewFilter, !isClosed else { return }
        requirementReviewFilter = filter
        renamingRequirementID = nil
        await refresh()
    }

    /// The list, grouped by entity (§5.1's "requirement list grouped by entity"), in entity
    /// kind then name order, canonical rows before variants inside each group.
    var requirementGroups: [RequirementEntityGroup] {
        var order: [UUID] = []
        var rows: [UUID: [RequirementSummary]] = [:]
        // The scope filter (§6.4's Missing) narrows the same rows the review filter read;
        // it is not a second query, and it is applied here so the list, the context menu,
        // and the selection all see one set.
        for summary in scopedRequirementSummaries {
            if rows[summary.entityID] == nil {
                rows[summary.entityID] = []
                order.append(summary.entityID)
            }
            rows[summary.entityID]?.append(summary)
        }
        return order.compactMap { entityID in
            guard let requirements = rows[entityID], let first = requirements.first else { return nil }
            return RequirementEntityGroup(
                id: entityID,
                entityName: first.entityName,
                entityKind: first.entityKind,
                requirements: requirements
            )
        }
        .sorted { left, right in
            if left.entityKind != right.entityKind {
                return left.entityKind.rawValue < right.entityKind.rawValue
            }
            if left.entityName != right.entityName { return left.entityName < right.entityName }
            return left.id.uuidString < right.id.uuidString
        }
    }

    /// §5.3's entity-level badge: qualifies under §3.3, but at least one enabled template
    /// entry has no row yet — "Build to add".
    var entitiesMissingCanonicalSet: [QualifyingEntity] {
        manifestSummary?.entitiesMissingCanonicalSet ?? []
    }

    /// §6.4's dashboard numbers as one line, for the section header.
    var manifestCountsLine: String {
        let counts = manifestSummary?.overall ?? ManifestCounts()
        return [
            "\(counts.total) active",
            "\(counts.canonical) canonical",
            "\(counts.variant) variant",
            "\(counts.approved) approved",
            "\(counts.needsReview) needs review",
            "\(counts.missing) missing",
            "\(counts.blocked) blocked",
            "\(counts.stale) stale",
            "\(counts.optional) optional",
        ].joined(separator: " · ")
    }

    /// What the last Build did, in the section's own words; `nil` before the first Build.
    var lastBuildMessage: String? {
        guard let result = lastBuildResult else { return nil }
        let created = result.created
        let noun = created == 1 ? "canonical requirement" : "canonical requirements"
        if created == 0, result.collisions.isEmpty {
            return "Build added nothing: every canonical slot already has a requirement."
        }
        return "Build added \(created) \(noun)."
    }

    /// §5.3's collision badges, one per slot the last Build could not create, in its exact
    /// wording — delete, not reject, because a tombstone keeps the normalized name (§5.2).
    var buildCollisionBadges: [String] {
        (lastBuildResult?.collisions ?? []).map { collision in
            "canonical slot '\(collision.templateDisplayName)' blocked by an existing "
                + "requirement name — rename or delete it, then Build"
        }
    }

    // MARK: - What the selection admits (shared by the menu and the context menu)

    /// Build is offered whenever a project is open; it is idempotent and journals nothing
    /// when there is nothing to create (§5.2).
    var canBuildAssetManifest: Bool { !isClosed && project != nil }

    /// Rename needs one row whose `name` is not locked (§7.5's lock fields).
    var canRenameRequirement: Bool {
        guard renamingRequirementID == nil, let summary = selectedRequirementSummary else {
            return false
        }
        return !isRequirementLocked(summary.id, field: .name)
    }

    /// Necessity is human-only (§7.1) and refused by a lock on `necessity` or the record.
    var canSetRequirementNecessity: Bool {
        let selected = selectedRequirementSummaries
        guard selected.count == 1, let summary = selected.first else { return false }
        return !isRequirementLocked(summary.id, field: .necessity)
    }

    /// Accept flips the `proposed` rows of the selection and nothing else (§8.6).
    var canAcceptRequirementSelection: Bool {
        selectedRequirementSummaries.contains { $0.reviewState == .proposed }
    }

    /// Reject is offered for any selected row that is not already a tombstone.
    var canRejectRequirementSelection: Bool {
        selectedRequirementSummaries.contains { $0.reviewState != .rejected }
    }

    var canRestoreRequirementSelection: Bool {
        selectedRequirementSummaries.contains { $0.reviewState == .rejected }
    }

    var canDeleteRequirementSelection: Bool { !selectedRequirementSummaries.isEmpty }

    /// §7.2: combine is **variant tier only**, at least two rows, and any lock on any
    /// participant blocks it. Cross-entity sources are permitted, so the group is not part
    /// of the predicate.
    var canCombineRequirementSelection: Bool {
        let selected = selectedRequirementSummaries
        guard selected.count >= 2 else { return false }
        return selected.allSatisfy { $0.tier == .variant && !$0.isLocked }
    }

    var canToggleRequirementLock: Bool { selectedRequirementSummary != nil }

    var isSelectedRequirementWholeLocked: Bool {
        guard let summary = selectedRequirementSummary else { return false }
        return hasLock(SubjectRef(kind: .requirement, id: summary.id), field: .whole)
    }

    /// Whether a `locks` row pins this requirement's field, or its whole record (§3.7).
    func isRequirementLocked(_ id: UUID, field: LockField) -> Bool {
        isLocked(SubjectRef(kind: .requirement, id: id), field: field)
    }

    // MARK: - Build (§5.2)

    /// **Build Asset Manifest**: idempotent, repeatable, and journaling nothing when there
    /// is nothing to create — which is why the entry is optional and only a real one
    /// reaches the undo stack. A name collision is a counted skip surfaced as a §5.3 badge,
    /// never an error.
    func buildAssetManifest() async {
        guard !isClosed else { return }
        do {
            let result = try await session.refreshCanonicalRequirements(actor: .human)
            if let entry = result.entry { didApply(entry) }
            lastBuildResult = result
            await refresh()
        } catch {
            self.error = .project(error)
        }
    }

    // MARK: - Requirement commands (§7.2)

    /// A human variant requirement on one entity, named like the entity list's `+` names a
    /// new entity: a placeholder, disambiguated first because `name_normalized` is unique
    /// per entity across tiers and a second "New Variant" would be refused rather than
    /// created.
    @discardableResult
    func addVariantRequirement(entityID: UUID) async -> UUID? {
        guard !isClosed else { return nil }
        let taken = Set(
            requirementSummaries.filter { $0.entityID == entityID }.map { $0.name.lowercased() }
        )
        var name = "New Variant"
        var suffix = 2
        while taken.contains(name.lowercased()) {
            name = "New Variant \(suffix)"
            suffix += 1
        }
        let created = name
        let id: UUID? = await runEdit {
            let result = try await self.session.createRequirement(
                entityID: entityID, tier: .variant, typeID: nil, name: created,
                reason: "", actor: .human
            )
            return (entry: result.entry, value: result.requirementID)
        }
        guard let id else { return nil }
        // A human addition is born `accepted`, so a filter other than All would hide the
        // row the operator just made.
        if requirementReviewFilter != .all { await setRequirementReviewFilter(.all) }
        section = .manifest
        setSelection([id], in: .manifest)
        await loadRequirementDetail()
        return id
    }

    func renameRequirement(id: UUID, name: String) async {
        await runEdit {
            try await self.session.renameRequirement(id: id, name: name, actor: .human)
        }
    }

    /// Commits an in-place rename. An unchanged or empty name just closes the editor —
    /// journalling a rename to the same string would put an inert step on the undo stack.
    func commitRequirementRename(id: UUID, name: String) async {
        renamingRequirementID = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = requirementSummaries.first { $0.id == id }?.name
        guard !trimmed.isEmpty, trimmed != current else { return }
        await renameRequirement(id: id, name: trimmed)
    }

    func beginRequirementRename() {
        guard canRenameRequirement, let summary = selectedRequirementSummary else { return }
        renamingRequirementID = summary.id
    }

    func cancelRequirementRename() {
        renamingRequirementID = nil
    }

    func setRequirementReason(id: UUID, text: String) async {
        await runEdit {
            try await self.session.setRequirementReason(id: id, text: text, actor: .human)
        }
    }

    func setRequirementNecessity(id: UUID, necessity: RequirementNecessity) async {
        await runEdit {
            try await self.session.setRequirementNecessity(
                id: id, necessity: necessity, actor: .human
            )
        }
    }

    /// The menu's necessity commands act on the one selected row; FilmCore has no batch
    /// necessity wrapper for requirements, and issuing one operation per row would be one
    /// undo step per row rather than the single step §3.8 requires — so the commands are
    /// single-selection and `canSetRequirementNecessity` says so.
    func setSelectedRequirementNecessity(_ necessity: RequirementNecessity) async {
        guard let summary = selectedRequirementSummary else { return }
        await setRequirementNecessity(id: summary.id, necessity: necessity)
    }

    func rejectRequirement(id: UUID) async {
        await runEdit { try await self.session.rejectRequirement(id: id, actor: .human) }
    }

    func unrejectRequirement(id: UUID) async {
        await runEdit { try await self.session.unrejectRequirement(id: id, actor: .human) }
    }

    /// §7.2's delete: FilmCore routes it — a `human` row (or one already rejected) is hard
    /// deleted, a `parser` or `ai` row is tombstoned instead, and a row with media is
    /// refused with "Delete its asset before deleting the requirement" (Plan 011's media).
    func deleteRequirement(id: UUID) async {
        await runEdit { try await self.session.deleteRequirement(id: id, actor: .human) }
    }

    /// Accepts exactly the `proposed` rows of the selection (§8.6; the payload lists the
    /// pairs it flipped, so an already-accepted row must not be in it).
    func acceptRequirementSelection() async {
        let refs = selectedRequirementSummaries
            .filter { $0.reviewState == .proposed }
            .map { SubjectRef(kind: .requirement, id: $0.id) }
        await acceptFacts(refs: refs)
    }

    func acceptRequirement(id: UUID) async {
        await acceptFacts(refs: [SubjectRef(kind: .requirement, id: id)])
    }

    /// §7.2's combine, one operation and therefore **one undo step** over the whole
    /// selection: sources are tombstoned, assets merge, and the survivor keeps its name.
    func combineRequirements(sourceIDs: [UUID], into targetID: UUID) async {
        guard !sourceIDs.isEmpty else { return }
        let applied = await runEdit {
            try await self.session.combineRequirements(
                sourceIDs: sourceIDs, into: targetID, actor: .human
            )
        }
        guard applied else { return }
        setSelection([targetID], in: .manifest)
        await loadRequirementDetail()
    }

    /// The whole-record lock over the selected requirement (§3.7, §7.5).
    func toggleSelectedRequirementLock() async {
        guard let summary = selectedRequirementSummary else { return }
        let subject = SubjectRef(kind: .requirement, id: summary.id)
        if hasLock(subject, field: .whole) {
            await unlock(subject: subject, field: .whole)
        } else {
            await lock(subject: subject, field: .whole)
        }
    }

    /// Selects a requirement and shows the Manifest section — the dependency rows' and the
    /// collision badges' jump target.
    func revealRequirement(id: UUID) async {
        section = .manifest
        setSelection([id], in: .manifest)
        await loadRequirementDetail()
    }
}

/// One entity's requirement rows, as the Manifest list groups them (§5.1).
struct RequirementEntityGroup: Identifiable, Equatable, Sendable {
    let id: UUID
    let entityName: String
    let entityKind: EntityKind
    let requirements: [RequirementSummary]
}

/// The Manifest list's review filter — PHASE2_DESIGN §8.6's grammar, which is Phase 1's
/// entity grammar over requirement rows: Proposed / Accepted / Rejected, with All as the
/// default that shows everything except tombstones.
///
/// It deliberately does not carry Phase 1's Unanchored case: evidence anchoring is an
/// entity-side signal, and a requirement's citations are basis rows (§3.7).
enum RequirementReviewFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case proposed
    case accepted
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .proposed: "Proposed"
        case .accepted: "Accepted"
        case .rejected: "Rejected"
        }
    }

    /// What `requirementSummaries(reviewState:)` is asked for.
    var reviewState: ReviewState? {
        switch self {
        case .all: nil
        case .proposed: .proposed
        case .accepted: .accepted
        case .rejected: .rejected
        }
    }

    /// Only the Rejected filter opts into tombstones (§7.6: default reads exclude them).
    var includesRejected: Bool { self == .rejected }
}
