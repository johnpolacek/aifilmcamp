import Foundation

/// PHASE3_DESIGN §5.8's workshop confirm strings — the highest-stakes strings in the
/// workshop, so they get the `ManifestDisclosureText` treatment: one home, out of the
/// views, asserted character for character by `WorkshopCopyTests`. Plan 016 appends its
/// two (Regenerate-over-human-prompt, Batch); a §14.2 reversal swaps one string here.
enum WorkshopConfirmText {
    /// §14.2's decided behavior, stated plainly: prompts survive the gesture.
    static func emptySlot(versionCount: Int) -> String {
        versionCount == 1
            ? "Delete this slot's 1 version and its file permanently? Prompts are kept."
            : "Delete this slot's \(versionCount) versions and their files permanently? Prompts are kept."
    }

    /// Deleting the current prompt: the previous one becomes current (§3.2).
    static let deleteCurrentPrompt =
        "Delete the current prompt? The previous prompt becomes current."

    /// Deleting a history row.
    static func deleteHistoryPrompt(number: Int) -> String {
        "Delete prompt \(number) from history?"
    }

    /// Make Canonical with dependents (§5.7's consequence, moved to this block).
    static func makeCanonical(dependentCount: Int) -> String {
        dependentCount == 1
            ? "1 derived asset will be marked stale."
            : "\(dependentCount) derived assets will be marked stale."
    }

    // MARK: - Plan 016

    /// §8.7's regenerate-over-human-prompt confirm (§5.8): regeneration inserts above the
    /// human row without touching it — the confirm says where the edited prompt went.
    static let regenerateOverHumanPrompt =
        "Your edited prompt stays in history."

    /// §9's batch variant (contract D), pinned here so the copy ships with its contract.
    /// It renders **nothing** while §14.1's evidence gate is unmet — nothing batch-shaped
    /// renders on the recorded Plan 016 posture — and `<n>` names the exact request count:
    /// the non-skipped requirements after the skip taxonomy thins the non-Approved set,
    /// never the raw set size (§8.1).
    static func batch(requestCount: Int) -> String {
        "Generating missing prompts sends each asset's structured breakdown to Codex through your own Codex account, in \(requestCount) requests — not any screenplay text and not any image."
    }
}
