import Foundation

/// Prompt-run privacy copy, narrowed by Plan 024's 2026-08-27 creative-context amendment.
///
/// They live beside the extraction and manifest texts so privacy wording remains one
/// reviewable contract instead of being restated inside multiple view bodies.
///
/// `firstRun` is shown only when `projects.disclosure_acknowledged_at` is nil — reachable
/// without either bootstrap acknowledged — and acceptance stores the acknowledgement through
/// the shared door. `everyRun` remains the compact confirmation copy for prompt-entry points
/// that require it; reference-image creation intentionally starts immediately after the shared
/// disclosure has been accepted.
enum PromptDisclosureText {
    static let firstRun = """
    Generating a prompt sends this asset's visual brief — its requirement type, entity names, aliases and description, relevant variant states, and reference labels and positive roles — to Codex through your own Codex account, together with the prompt-writing skill files included with AI Film Camp. It does not send screenplay text, scene summaries, continuity events, image data, or generation exclusions. Codex may include your global Codex instructions and the descriptions of your installed Codex skills or plugins in the same request; AI Film Camp does not read or store those. Nothing is sent until you choose Continue.
    """

    static let everyRun = """
    Generating this prompt sends this asset's narrowed visual brief — not screenplay text, scene summaries, continuity events, image data, or generation exclusions — to Codex through your own Codex account, in about 1 request. You can regenerate at any time.
    """
}
