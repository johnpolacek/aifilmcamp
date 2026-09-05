import Foundation

/// PHASE5_DESIGN §9's one-time scene-prompt disclosure, kept outside the View so the
/// copy has one source of truth.
///
/// `firstRun` is shown only when `projects.disclosure_acknowledged_at` is nil for this
/// surface — reachable through the shared acknowledgement door — and acceptance stores
/// the acknowledgement through that door. Later Generate/Update/Regenerate gestures
/// start immediately; §9's batch variant stays evidence-gated.
enum ScenePromptDisclosureText {
    static let firstRun = """
    Preparing a scene prompt sends this scene's text — including action and dialogue — \
    plus your style bible and the scene's production context to the engine you chose, \
    using your own account. Film Camp never sends your images. Standard makes one request \
    that writes and checks the final prompt. High Quality adds an independent second request \
    that reviews and rewrites it. After \
    this one-time acknowledgement, choosing Generate, Update, or Regenerate starts the run \
    immediately.
    """
}
