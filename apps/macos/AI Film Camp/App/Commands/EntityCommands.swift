import FilmCore
import SwiftUI

/// §3.11's **Entity menu**: every context-menu action of the entity list and inspector,
/// mirrored as a menu item with the shortcuts the design names.
///
/// Items route to the frontmost project window through `@FocusedValue(\.projectWindow)`
/// and are disabled when the action is not valid for the **whole** selection — the same
/// predicates the context menus and the inspector's multi-selection actions read, which is
/// why they live here beside the menu rather than being restated per view.
struct EntityCommands: Commands {
    @FocusedValue(\.projectWindow) private var project: ProjectWindowModel?

    var body: some Commands {
        CommandMenu("Entity") {
            Button("Rename") {
                project?.beginRename()
            }
            // Plain Return, as §3.11 specifies. `canRename` is false while any text
            // control has focus, and a **disabled** menu item does not consume its key
            // equivalent — which is what lets Return still reach the field editor.
            .keyboardShortcut(.return, modifiers: [])
            .disabled(project?.canRename != true || project?.allowsPlainKeyShortcuts != true)
            .accessibilityIdentifier("entityMenuRename")

            Divider()

            Button("Merge…") {
                project?.presentedSheet = .merge
            }
            .keyboardShortcut("m", modifiers: [.control, .command])
            .disabled(project?.canMergeSelection != true)
            .accessibilityIdentifier("entityMenuMerge")

            Button("Split…") {
                project?.presentedSheet = .split
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .disabled(project?.canSplitSelection != true)
            .accessibilityIdentifier("entityMenuSplit")

            Button("Move into…") {
                project?.presentedSheet = .moveInto
            }
            .disabled(project?.canMoveSelectionIntoLocation != true)
            .accessibilityIdentifier("entityMenuMoveInto")

            Divider()

            // One item whose title says which way it will go, exactly as §3.11 writes
            // "Lock/Unlock". It pins the whole record; the per-field locks are the
            // inspector's `LockButton`s.
            Button(project?.isSelectionWholeLocked == true ? "Unlock" : "Lock") {
                guard let project else { return }
                Task { await project.toggleWholeRecordLock() }
            }
            .keyboardShortcut("l", modifiers: [.control, .command])
            .disabled(project?.canToggleWholeRecordLock != true)
            .accessibilityIdentifier("entityMenuLock")

            Button("Mark Irrelevant") {
                guard let project else { return }
                Task { await project.setRelevance(ids: project.selectedEntityIDs, isRelevant: false) }
            }
            .disabled(project?.canMarkSelectionIrrelevant != true)
            .accessibilityIdentifier("entityMenuMarkIrrelevant")

            Divider()

            Button("Add Missing…") {
                guard let project else { return }
                Task { await project.addMissingEntity() }
            }
            .keyboardShortcut("n", modifiers: [.option, .command])
            .disabled(project?.section.entityKind == nil || project?.entityReviewFilter != .proposed)
            .accessibilityIdentifier("entityMenuAddMissing")

            Divider()

            Button("Accept") {
                guard let project else { return }
                Task { await project.acceptSelection() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(project?.canAcceptSelection != true)
            .accessibilityIdentifier("entityMenuAccept")

            // §3.11's "Reject/Delete": one command whose outcome §6 decides per row — a
            // `human` row (or one already rejected) is hard-deleted, a `parser` or `ai`
            // row is tombstoned instead, which is what "Reject" names. Confirmed either
            // way.
            Button("Delete") {
                guard let project else { return }
                project.confirmDeletion(of: project.selectedEntityIDs)
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(project?.canDeleteSelection != true || project?.allowsPlainKeyShortcuts != true)
            .accessibilityIdentifier("entityMenuDelete")

            // PHASE2_DESIGN §5–§8.6's requirement commands, mirroring the Manifest list's
            // context menu exactly as the items above mirror the entity list's. They are
            // disabled outside the Manifest section, because every predicate they gate on
            // reads that section's selection.
            Divider()

            Button("Build Asset Manifest") {
                guard let project else { return }
                Task { await project.buildAssetManifest() }
            }
            .keyboardShortcut("b", modifiers: [.option, .command])
            .disabled(project?.canBuildAssetManifest != true)
            .accessibilityIdentifier("entityMenuBuildManifest")

            Button("Rename Requirement") {
                project?.beginRequirementRename()
            }
            .disabled(project?.canRenameRequirement != true)
            .accessibilityIdentifier("entityMenuRenameRequirement")

            // Flat items rather than a submenu: each one is a plain menu command, which is
            // what both the operator and the UI suite reach for.
            ForEach(RequirementNecessity.allCases, id: \.self) { necessity in
                Button("Mark Requirement \(necessity.displayName)") {
                    guard let project else { return }
                    Task { await project.setSelectedRequirementNecessity(necessity) }
                }
                .disabled(project?.canSetRequirementNecessity != true)
                .accessibilityIdentifier("entityMenuNecessity_\(necessity.rawValue)")
            }

            Button("Combine Requirements…") {
                project?.presentedSheet = .combineRequirements
            }
            .disabled(project?.canCombineRequirementSelection != true)
            .accessibilityIdentifier("entityMenuCombineRequirements")

            Button("Reject Requirement") {
                guard let project, let id = project.selectedRequirementSummary?.id else { return }
                Task { await project.rejectRequirement(id: id) }
            }
            .disabled(project?.canRejectRequirementSelection != true
                || project?.selectedRequirementSummary == nil)
            .accessibilityIdentifier("entityMenuRejectRequirement")

            Button("Delete Requirement") {
                guard let project, let id = project.selectedRequirementSummary?.id else { return }
                Task { await project.deleteRequirement(id: id) }
            }
            .disabled(project?.selectedRequirementSummary == nil)
            .accessibilityIdentifier("entityMenuDeleteRequirement")
        }
    }
}

// MARK: - What the selection admits

/// The predicates §3.11's "only the actions valid for the whole selection" names, shared
/// by the Entity menu, the list's context menu, and the inspector's multi-selection bar.
@MainActor
extension ProjectWindowModel {

    /// The selected rows of the current entity section, in list order.
    var selectedEntitySummaries: [EntitySummary] {
        guard let kind = section.entityKind else { return [] }
        let ids = selection(in: section)
        return (entitySummaries[kind] ?? []).filter { ids.contains($0.id) }
    }

    var selectedEntityIDs: [UUID] { selectedEntitySummaries.map(\.id) }

    /// The one selected row, or `nil` for an empty or multiple selection.
    var selectedEntitySummary: EntitySummary? {
        let selected = selectedEntitySummaries
        return selected.count == 1 ? selected[0] : nil
    }

    /// Whether a whole-record lock pins this entity — the only lock that blocks a merge
    /// source outright (§3.7).
    func isWholeRecordLocked(entityID: UUID) -> Bool {
        isLocked(SubjectRef(kind: .entity, id: entityID), field: .whole)
    }

    /// Whether the Entity menu's two **plain-key** items (Rename on Return, Delete on
    /// ⌫) may stay enabled. They are real AppKit key equivalents, matched before the
    /// field editor sees the key, so they stand down whenever a text control has focus,
    /// an in-place rename is open, or a sheet is up. Nothing else gates on this: the
    /// actions' own validity is separate, so the inspector's buttons stay live.
    var allowsPlainKeyShortcuts: Bool {
        !isEditingText && renamingEntityID == nil && presentedSheet == nil
    }

    /// Return starts an in-place rename (§3.11): one row, whose name is not locked.
    var canRename: Bool {
        guard renamingEntityID == nil, let summary = selectedEntitySummary else { return false }
        return !isLocked(SubjectRef(kind: .entity, id: summary.id), field: .name)
    }

    /// Merge wants at least two rows of **one** kind and no lock anywhere in the
    /// selection: §3.5 refuses on a lock over a source or over one of its aliases, and a
    /// whole-record lock on the target, and the target is chosen inside the sheet.
    var canMergeSelection: Bool {
        let selected = selectedEntitySummaries
        guard selected.count >= 2, let kind = selected.first?.kind else { return false }
        return selected.allSatisfy { $0.kind == kind && !$0.isLocked }
    }

    /// Split takes exactly one entity and is refused by any lock on it (§3.5).
    var canSplitSelection: Bool {
        guard let summary = selectedEntitySummary else { return false }
        return !summary.isLocked
    }

    /// Move into… is locations only (§6).
    var canMoveSelectionIntoLocation: Bool {
        let selected = selectedEntitySummaries
        return !selected.isEmpty && selected.allSatisfy { $0.kind == .location }
    }

    /// Accept needs at least one `proposed` row in the selection; it flips those and
    /// nothing else (§6).
    var canAcceptSelection: Bool {
        selectedEntitySummaries.contains { $0.reviewState == .proposed }
    }

    var canDeleteSelection: Bool { !selectedEntitySummaries.isEmpty }

    var canToggleWholeRecordLock: Bool { selectedEntitySummary != nil }

    var isSelectionWholeLocked: Bool {
        guard let summary = selectedEntitySummary else { return false }
        return isWholeRecordLocked(entityID: summary.id)
    }

    var canMarkSelectionIrrelevant: Bool {
        let selected = selectedEntitySummaries
        guard !selected.isEmpty else { return false }
        return selected.allSatisfy {
            !isLocked(SubjectRef(kind: .entity, id: $0.id), field: .isRelevant)
        }
    }

    // MARK: - The actions the menu and the context menus share

    func beginRename() {
        guard canRename, let summary = selectedEntitySummary else { return }
        beginRename(entityID: summary.id)
    }

    /// Scene Data's focused inspector has an explicit subject rather than a legacy
    /// entity-section selection.
    func beginRename(entityID: UUID) {
        guard renamingEntityID == nil,
              !isLocked(SubjectRef(kind: .entity, id: entityID), field: .name) else { return }
        renamingEntityID = entityID
    }

    func cancelRename() {
        renamingEntityID = nil
    }

    /// Commits an in-place rename. An unchanged or empty name just closes the editor —
    /// journalling a rename to the same string would put an inert step on the undo stack.
    func commitRename(id: UUID, name: String) async {
        renamingEntityID = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entityNames[id] else { return }
        await renameEntity(id: id, name: trimmed)
    }

    /// ⌃⌘L over the whole record (§3.7).
    func toggleWholeRecordLock() async {
        guard let summary = selectedEntitySummary else { return }
        let subject = SubjectRef(kind: .entity, id: summary.id)
        if isWholeRecordLocked(entityID: summary.id) {
            await unlock(subject: subject, field: .whole)
        } else {
            await lock(subject: subject, field: .whole)
        }
    }

    /// Accepts exactly the `proposed` rows of the selection (§6: the payload lists the
    /// pairs it flipped, so an already-accepted row must not be in it).
    func acceptSelection() async {
        let refs = selectedEntitySummaries
            .filter { $0.reviewState == .proposed }
            .map { SubjectRef(kind: .entity, id: $0.id) }
        await acceptFacts(refs: refs)
    }
}

// MARK: - Keeping the plain-key shortcuts out of the field editor's way

/// Counts a text control in and out of `ProjectWindowModel.isEditingText` as focus moves.
///
/// It exists for one reason: the Entity menu's Return and ⌫ items are AppKit key
/// equivalents, and a key equivalent is matched **before** the focused field editor sees
/// the key. Disabling the two items while a field has focus is what keeps Return and
/// backspace typing into a text field rather than renaming or deleting behind it.
///
/// Sheet fields need no such tracking: `allowsPlainKeyShortcuts` is already false while a
/// sheet is presented.
private struct TextEditingFocus: ViewModifier {
    let model: ProjectWindowModel

    @FocusState private var isFocused: Bool
    /// Whether this field's focus is currently counted, so the count stays balanced when
    /// the view disappears mid-edit or SwiftUI repeats a change.
    @State private var counted = false

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, now in
                guard now != counted else { return }
                counted = now
                model.setTextEditing(now)
            }
            .onDisappear {
                guard counted else { return }
                counted = false
                model.setTextEditing(false)
            }
    }
}

extension View {
    /// Marks a text control that lives **outside** a sheet, so the Entity menu's
    /// plain-key shortcuts stand down while it is being typed into.
    func tracksTextEditing(_ model: ProjectWindowModel) -> some View {
        modifier(TextEditingFocus(model: model))
    }
}
