import AppKit
import Darwin
import FilmCore
import SwiftUI

/// PHASE3_DESIGN §5.8's enablement rules and the workshop's window-model commands
/// (Plan 015 contracts B–C).
///
/// Enablement is decided by **reads**, never by a view guessing: accepted and active are
/// two separate checks (§13.10), locks come from `RequirementDetail.locks`, and the
/// generation gate is §3.3's `isGenerationBlocked` plus the run-gate condition Plan 016
/// owns — stubbed false-safe here, so Generate/Regenerate render disabled with their
/// reasons until that plan wires them.
extension ProjectWindowModel {

    // MARK: - The workshop's subject

    /// The requirement the workshop renders: the single selected row of the master pane.
    var workshopRequirementID: UUID? {
        guard !isClosed else { return nil }
        let selection = selection(in: .manifest)
        return selection.count == 1 ? selection.first : nil
    }

    // MARK: - Accepted / active / locked, separately (§5.8)

    var isWorkshopRequirementAccepted: Bool {
        requirementDetail?.requirement.provenance.reviewState == .accepted
    }

    var isWorkshopRequirementProposed: Bool {
        requirementDetail?.requirement.provenance.reviewState == .proposed
    }

    var isWorkshopRequirementWholeLocked: Bool {
        guard let detail = requirementDetail else { return false }
        return detail.locks.contains { $0.isWholeRecord }
    }

    /// §3.3's generation gate. Deliberately not the Missing-qualified `isBlocked`.
    var isWorkshopGenerationBlocked: Bool {
        !(requirementDetail?.generationBlockedBy.isEmpty ?? true)
    }

    /// The first unsatisfied dependency's name, for the blocked reason (§5.8).
    var workshopBlockedDependencyName: String? {
        guard let detail = requirementDetail, let first = detail.generationBlockedBy.first
        else { return nil }
        return detail.plannedDependencies.first { $0.requirementID == first }?.requirementName
    }

    // MARK: - Prompt panel enablement (§5.8's table)

    var canWritePrompt: Bool {
        guard !isClosed, isWorkshopRequirementAccepted,
              let detail = requirementDetail, detail.isActive
        else { return false }
        // Blockage does not gate it (§3.3); whole-lock does (§7.1).
        return !isWorkshopRequirementWholeLocked
    }

    var canEditPromptBody: Bool {
        // Current prompt only; history is a record, not a draft (§3.2). A current row
        // exists by definition when the panel shows one.
        canWritePrompt && requirementDetail?.currentPrompt != nil
    }

    var canCopyPrompt: Bool {
        requirementDetail?.currentPrompt != nil
    }

    var canCopyPromptWithGuidance: Bool {
        guard let guidance = requirementDetail?.currentPrompt?.guidance else { return false }
        return canCopyPrompt && !guidance.isEmpty
    }

    var canMarkInProgress: Bool {
        guard !isClosed, isWorkshopRequirementAccepted,
              let detail = requirementDetail, detail.isActive, detail.asset != nil
        else { return false }
        // Refused while any version row exists (§5.5); whole-lock refuses too.
        return detail.versions.isEmpty && !isWorkshopRequirementWholeLocked
    }

    var canClearInProgress: Bool {
        guard !isClosed, let detail = requirementDetail else { return false }
        return detail.inProgressSince != nil && !isWorkshopRequirementWholeLocked
    }

    /// §5.8's Generate/Regenerate enablement, decided by reads: every decided condition is
    /// evaluated by Plan 016's run gate (`+PromptRun.swift`) — accepted and active are two
    /// separate checks there, blockage names its first dependency, whole-locks refuse, and
    /// the §8.1 paused-run gate covers bootstraps. `nil` means enabled.

    // MARK: - Commands (§5.4–§5.6)

    /// Write Prompt: the human paste path (§14.5). Not blockage-gated (§3.3).
    func createWorkshopPrompt(body: String, targetModel: String) async {
        guard let id = workshopRequirementID else { return }
        await runEdit {
            try await self.session.createPrompt(
                requirementID: id, body: body, targetModel: targetModel, actor: .human
            )
        }
    }

    func setWorkshopPromptBody(promptID: UUID, body: String) async {
        await runEdit {
            try await self.session.setPromptBody(promptID: promptID, body: body, actor: .human)
        }
    }

    func deleteWorkshopPrompt(promptID: UUID) async {
        await runEdit {
            try await self.session.deletePrompt(promptID: promptID, actor: .human)
        }
    }

    func markWorkshopInProgress() async {
        guard let id = workshopRequirementID else { return }
        await runEdit {
            try await self.session.markAssetInProgress(requirementID: id, actor: .human)
        }
    }

    func clearWorkshopInProgress() async {
        guard let assetID = requirementDetail?.asset?.id else { return }
        await runEdit {
            try await self.session.clearAssetInProgress(assetID: assetID, actor: .human)
        }
    }

    /// §5.5: Copy Prompt writes the current body to the pasteboard — a **pure read**: no
    /// mutation, no journal entry, no status change (§14.7). With guidance appends under a
    /// `---` separator.
    func copyWorkshopPrompt(includeGuidance: Bool) {
        guard let current = requirementDetail?.currentPrompt else { return }
        var text = current.body
        if includeGuidance, !current.guidance.isEmpty {
            text += "\n---\n" + current.guidance
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// §5.6: Import Result through the shipped single import door, passing the current
    /// prompt's id as the explicit lineage stamp — **the one non-nil call site** (§7.3).
    func importWorkshopResult(requirementID: UUID, from url: URL) async {
        let stamp = requirementDetail?.currentPrompt?.id
        await runEdit {
            try await self.session.importAssetVersion(
                requirementID: requirementID, from: url, actor: .human, promptID: stamp
            ).entry
        }
    }

    /// The chooser + stamped import behind Add Image… in the workshop.
    func chooseAndImportWorkshopResult(requirementID: UUID) async {
        guard !isClosed, let url = await imageChooser() else { return }
        await importWorkshopResult(requirementID: requirementID, from: url)
    }

    /// §5.3: remove via the shipped `removeDependency` (tombstoned for ai/parser rows).
    func removeWorkshopReference(dependencyID: UUID) async {
        await runEdit {
            try await self.session.removeDependency(id: dependencyID, actor: .human)
        }
    }

    // MARK: - Confirm copy (contract C — the views render these verbatim)

    func workshopEmptySlotConfirm() -> String {
        WorkshopConfirmText.emptySlot(versionCount: requirementDetail?.versions.count ?? 0)
    }

    func workshopDeletePromptConfirm(number: Int, isCurrent: Bool) -> String {
        isCurrent
            ? WorkshopConfirmText.deleteCurrentPrompt
            : WorkshopConfirmText.deleteHistoryPrompt(number: number)
    }

    func workshopMakeCanonicalConfirm() -> String {
        WorkshopConfirmText.makeCanonical(
            dependentCount: requirementDetail?.dependents.count ?? 0
        )
    }
}

extension ProjectWindowModel {
    func loadWorkshopPromptHistory() async {
        guard !isClosed, let id = workshopRequirementID else { return }
        workshopPromptHistory = (try? await session.promptHistory(requirementID: id)) ?? []
    }

    /// §5.3's Add Reference picker action: `addDependency` underneath, cycle check and
    /// whole-lock guard inside the engine.
    func addWorkshopReference(dependencyRequirementID: UUID) async {
        guard let owner = workshopRequirementID else { return }
        await runEdit {
            try await self.session.addDependency(
                requirementID: owner, dependsOnID: dependencyRequirementID, actor: .human
            )
        }
    }

    /// §5.3: every satisfied reference's file in one Finder window.
    func revealAllReferences(detail: RequirementDetail) async {
        for dependency in detail.plannedDependencies where dependency.isSatisfied {
            guard let version = dependency.approvedVersion,
                  let relative = try? RelativeProjectPath(version.relativePath)
            else { continue }
            let containment = mediaContainment
            _ = try? containment.withReadDescriptor(at: relative) { descriptor in
                var status = stat()
                guard fstat(descriptor, &status) == 0 else { return }
                // /dev/fd/N resolves through the containment's O_NOFOLLOW open; the
                // selected path is what Finder fronts.
                let url = URL(fileURLWithPath: "/dev/fd/\(descriptor)")
                NSWorkspace.shared.activateFileViewerSelecting(
                    [url.resolvingSymlinksInPath()]
                )
            }
        }
    }

    /// Empty Slot's destructive half: the shipped rows-first/files-second path.
    func deleteAssetAndClose(assetID: UUID) async {
        await performDestructiveAssetDeletion(assetID: assetID)
    }
}
