import AppKit
import FilmCore
import Foundation

/// The window's `UndoManager` (PHASE1_DESIGN §3.8, Plan 005's "Undo bridge").
///
/// Two things the stock manager cannot do for us:
///
/// 1. **Serialization is enforced where AppKit actually enters.** Exactly one inverse is
///    in flight at a time, and Edit ▸ Undo / Redo (and ⌘Z / ⇧⌘Z) must not start a second.
///    `NSUndoManager` does not participate in menu validation the way a responder does, so
///    a `canUndo` override alone cannot be relied on to grey the items out — AppKit calls
///    `undo()` / `redo()` on this object **directly**, bypassing `ProjectWindowModel.undo()`
///    entirely. Overriding those two to no-op while an inverse applies is therefore the
///    real gate; `canUndo` / `canRedo` still answer `false` so anything that *does* consult
///    them (SwiftUI's own commands, the model's command state) agrees.
/// 2. **One command is one undo step.** Run-loop grouping would merge two edits made in
///    the same turn into a single ⌘Z — and in a unit test, where no run-loop turn
///    necessarily ends between two awaited commands, it would merge *every* edit. So
///    `groupsByEvent` is off and grouping is opened and closed **synchronously around a
///    registration** (`registerUndoAction`), never held across an `await`: a group left
///    open across a suspension is a crash waiting for the first `removeAllActions()` or the
///    first direct `undo()` from the menu. A batch action needs no group of its own — a
///    `performGroup` returns exactly one `JournalEntry`, hence exactly one registration.
final class ProjectUndoManager: UndoManager {
    /// Mirrored from `ProjectWindowModel.isApplyingInverse`. Read and written only on the
    /// main thread — the model is `@MainActor` and this manager is never handed anywhere
    /// else — but `UndoManager`'s own members are not isolated, so the mirror cannot be.
    nonisolated(unsafe) var isApplyingInverse = false

    override init() {
        super.init()
        groupsByEvent = false
    }

    override var canUndo: Bool { !isApplyingInverse && super.canUndo }
    override var canRedo: Bool { !isApplyingInverse && super.canRedo }

    /// The door AppKit uses. A second ⌘Z that arrives while an inverse applies is refused
    /// here — before anything is popped and before any closure runs — so the stacks are
    /// genuinely untouched rather than "untouched apart from a re-registration".
    override func undo() {
        guard !isApplyingInverse else { return }
        super.undo()
    }

    override func redo() {
        guard !isApplyingInverse else { return }
        super.redo()
    }
}

/// The box an undo closure fills with the id of the entry its own apply journaled (§3.8).
///
/// Registration is synchronous, inside the undo closure, *before* the `await` — so the
/// flip side is on the other stack before the apply that gives it an entry id has even
/// started. The slot is how the two are joined afterwards; a closure over a slot that is
/// still `nil` refuses to run.
@MainActor
final class InverseSlot {
    var entryID: Int64?

    init(entryID: Int64? = nil) { self.entryID = entryID }
}

// MARK: - Registration

@MainActor
extension ProjectWindowModel {

    /// Called after **every** human edit (§3.8). A non-invertible entry (import, replace,
    /// an applied run, a revert) leaves nothing to undo, so it clears the stack instead.
    func didApply(_ entry: JournalEntry) {
        guard entry.inverse != nil else {
            undoManager.removeAllActions()
            syncUndoMenu()
            return
        }
        register(entryID: entry.seq, name: entry.op.displayName)
    }

    /// Registers the inverse of one journal entry, in the shape Plan 005's contract gives.
    ///
    /// The handler is **not** actor-isolated under strict concurrency: `UndoManager` calls
    /// it on the main thread, so it asserts isolation rather than hopping. A hop would move
    /// the registration out of the closure, onto the wrong stack, and after the `await`.
    func register(entryID: Int64, name: String) {
        // Filled with the flip's entry id on success.
        let flip = InverseSlot()
        registerUndoAction(name: name) { model in
            guard !model.isApplyingInverse else {
                // Defence in depth only: `ProjectUndoManager.undo()` / `redo()` already
                // refuse while an inverse applies, so no pop should ever reach this
                // closure. If one somehow did, the action is re-registered so it is not
                // swallowed by the drop — note that a registration made from inside
                // `undo()` lands on the **redo** stack, which is why the refusal upstream,
                // not this branch, is what keeps the stacks correct.
                model.register(entryID: entryID, name: name)
                return
            }
            model.isApplyingInverse = true
            // Synchronous, inside the closure → the other stack.
            model.register(slot: flip, name: name)
            Task { await model.applyInverse(entryID: entryID, filling: flip) }
        }
    }

    /// The flip side: the same shape over the slot's id once filled.
    func register(slot: InverseSlot, name: String) {
        let flip = InverseSlot()
        registerUndoAction(name: name) { model in
            // The apply that fills this slot has not finished (or failed outright); there
            // is no entry to invert, so the action refuses to run rather than guessing.
            guard let entryID = slot.entryID else { return }
            // Same defence in depth as `register(entryID:name:)`.
            guard !model.isApplyingInverse else {
                model.register(slot: slot, name: name)
                return
            }
            model.isApplyingInverse = true
            model.register(slot: flip, name: name)
            Task { await model.applyInverse(entryID: entryID, filling: flip) }
        }
    }

    /// `registerUndo` plus the grouping the action name needs — **synchronously**, and
    /// nowhere else in this file or in the commands.
    ///
    /// With `groupsByEvent` off there is no ambient group, so a registration that arrives
    /// outside one opens and closes its own, here, with no suspension in between. A
    /// registration that arrives inside a group `UndoManager` itself opened (the redo side,
    /// from within `undo()`) joins it. Nothing holds a group across an `await`: that is what
    /// makes `removeAllActions()` — from an AI clear, a refused inverse, or an import —
    /// safe at any moment, and what stops a direct `undo()` from nesting groups.
    private func registerUndoAction(
        name: String,
        _ body: @escaping @MainActor @Sendable (ProjectWindowModel) -> Void
    ) {
        let opensGroup = !undoManager.groupsByEvent && undoManager.groupingLevel == 0
        if opensGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { body(model) }
        }
        undoManager.setActionName(name)
        if opensGroup { undoManager.endUndoGrouping() }
        syncUndoMenu()
    }

    /// Copies the manager's titles and availability into the observable mirror the Edit
    /// menu reads. Called from every point that can change either.
    func syncUndoMenu() {
        undoMenu = UndoMenuState(
            undoTitle: undoManager.undoMenuItemTitle,
            redoTitle: undoManager.redoMenuItemTitle,
            canUndo: canUndo,
            canRedo: canRedo
        )
    }

    // MARK: - Applying

    /// Applies one entry's inverse and joins the flip's entry id to the action already
    /// registered on the other stack.
    ///
    /// `applyInverse(entryID:actor:)` is the **only** door: the window model never builds
    /// an `EditOperation` (§3.8). A refusal — `.inverseNoLongerApplicable(reason:)` when
    /// the rows moved under the stack — clears **both** stacks, reloads from the store,
    /// and surfaces the reason verbatim.
    func applyInverse(entryID: Int64, filling slot: InverseSlot) async {
        // The mirror carries `canUndo` / `canRedo`, and both go false for the duration.
        syncUndoMenu()
        defer {
            isApplyingInverse = false
            if !isClosed { syncUndoMenu() }
        }
        do {
            let entry = try await session.applyInverse(entryID: entryID, actor: .human)
            // A closed model no longer owns the manager, so it must not touch it — the
            // `defer` above still unsticks the shared flag.
            guard !isClosed else { return }
            slot.entryID = entry.seq
            await refresh()
        } catch {
            guard !isClosed else { return }
            undoManager.removeAllActions()
            syncUndoMenu()
            await refresh()
            self.error = .project(error)
        }
    }

    // MARK: - Commands

    /// Disabled while an inverse applies, so a second ⌘Z cannot race the first (§3.8).
    var canUndo: Bool { !isApplyingInverse && undoManager.canUndo }
    var canRedo: Bool { !isApplyingInverse && undoManager.canRedo }

    /// What Edit ▸ Undo reads: `EditOperation.displayName` is the only source of it.
    var undoActionName: String { undoManager.undoActionName }
    var redoActionName: String { undoManager.redoActionName }

    func undo() {
        guard canUndo else { return }
        undoManager.undo()
        syncUndoMenu()
    }

    func redo() {
        guard canRedo else { return }
        undoManager.redo()
        syncUndoMenu()
    }

    // MARK: - The journal's own clearing rule

    /// §3.8: **on a successful AI apply or revert the undo stack is cleared** ("Undo
    /// history was cleared by this run"), because an AI run is reversed through Revert
    /// last run, never through ⌘Z.
    ///
    /// The journal is the only signal the window model has — a run applied by Plan 007
    /// writes its rows through the session, not through a command here — so every refresh
    /// compares the newest entries against the newest one already accounted for. The first
    /// read of a project only adopts (a project reopened after a run has no stack to
    /// clear).
    func noteJournal(_ entries: [JournalEntry]) {
        let newest = entries.map(\.seq).max() ?? lastSeenJournalSeq
        let firstRead = !hasReadJournal
        // PHASE3_DESIGN §13.11's stated deviation rides here: the prompt run's apply is
        // **invertible** by design, and its one `.ai` entry is this window's to register —
        // so it is exactly the arrival that must NOT clear the stack ("⌘Z reads Undo
        // Generate Prompt"). Every other AI arrival still does.
        let arrived = entries.contains {
            $0.seq > lastSeenJournalSeq && $0.actor != .human
                && !$0.op.isAttachGeneratedPrompt
                && !$0.op.isAttachGeneratedScenePrompt
        }
        // Straight-line, and the watermark moves **last**: a scan that never ran (because
        // an earlier read in `refresh()` threw) leaves the watermark where it was, so the
        // pending clear is still found on the next refresh rather than skipped over.
        if arrived, !firstRead {
            undoManager.removeAllActions()
            syncUndoMenu()
        }
        lastSeenJournalSeq = max(lastSeenJournalSeq, newest)
        hasReadJournal = true
    }

    /// §3.8: `importScreenplay` and `replaceScreenplay` are **non-invertible**, so a
    /// successful import leaves nothing on the stack to undo.
    func clearUndoAfterNonInvertibleChange() {
        undoManager.removeAllActions()
        syncUndoMenu()
    }
}

// MARK: - AppKit

extension ProjectWindowDelegate {
    /// The one hook that puts the window model's `UndoManager` into the responder chain.
    ///
    /// Plan 004's Edit menu keeps the **system** Undo / Redo items (SwiftUI's
    /// `CommandGroup(.undoRedo)`); they are `undo:` / `redo:` sent down the responder
    /// chain, and AppKit resolves the manager for them by asking the first responder, then
    /// the window, then — here — the window's delegate. So this single method is what
    /// makes ⌘Z / ⇧⌘Z fire, what makes the items validate against `canUndo` / `canRedo`
    /// (see `ProjectUndoManager`), and what makes them read "Undo Rename Character" from
    /// `setActionName`. There is no second delegate: this is the same `NSWindowDelegate`
    /// bridge Plan 004 installs for window identifiers and ⌘W teardown.
    ///
    /// It is also how SwiftUI's `@Environment(\.undoManager)` resolves inside this window:
    /// that environment value is **get-only** in SwiftUI's public API, so it cannot be
    /// written with `.environment(\.undoManager, model.undoManager)` as Plan 005's prose
    /// suggests — SwiftUI reads it from exactly this AppKit path instead.
    @objc
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        model?.undoManager
    }
}
