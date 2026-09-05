import Foundation

/// PHASE2_DESIGN §9's two manifest-inference copy blocks, **verbatim**.
///
/// They live here rather than in a view for the reason the extraction text does: the copy is
/// a contract, `ManifestRunModelTests` asserts both strings character for character, and a
/// sentence restated inside a `View` body cannot be asserted at all.
///
/// `firstRun` is shown only when `projects.disclosure_acknowledged_at` is nil — a project can
/// legitimately reach its first manifest run without ever running extraction (bare import +
/// Build + inference), and acceptance stores the acknowledgement through the same door
/// extraction uses. `everyRun` is the compact confirm sheet, shown before **every** run.
enum ManifestDisclosureText {
    static let firstRun = """
    Building the manifest sends this project's structured breakdown — entity names, descriptions, states, and scene synopses, not the screenplay text — to Codex through your own Codex account. Codex may include your global Codex instructions and the descriptions of your installed Codex skills or plugins in the same request; AI Film Camp does not read or store those. Nothing is sent until you choose Continue.
    """

    static let everyRun = """
    Building the manifest sends this project's structured breakdown — entity names, descriptions, states, and scene synopses, not the screenplay text — to Codex through your own Codex account, in about 1 request. This runs once; afterward you edit the manifest directly.
    """
}
