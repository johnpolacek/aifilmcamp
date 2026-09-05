import Foundation

/// The asset-prompt instructions and the delimiter that wraps the narrowed creative context
/// derived from §8.2's complete input (Plan 024's 2026-08-27 amendment).
///
/// Structurally `InferManifestPrompt`: the checked-in instructions, one delimiter tag
/// around the untrusted creative context. The runner still digests the complete
/// `AssetPromptInput` as `input.text`, so `jobs.input_sha256` remains the apply-time drift
/// guard even though screenplay-derived story context is withheld from prompt composition.
///
/// Unlike the manifest prompt, the instructions name two files by **absolute path** — the
/// materialised skill's entry and its routing table, arm-B clones inside this run's
/// workspace (§3.5). Those paths are parameters: nothing here resolves a bundle or a cache
/// location on its own.
public enum AssetPromptPrompt: Sendable {
    static let instructions: String = load("asset-prompt-v1")

    public static func render(
        payload: String,
        skillEntryPath: String,
        skillRoutingPath: String?
    ) -> String {
        var header = "Skill entry: \(skillEntryPath)\n"
        header += skillRoutingPath.map { "Still-image routing table: \($0)\n" }
            ?? "This skill carries no still-image routing table; choose `targetModel` from the entry's own guidance.\n"
        return header + "\n" + instructions
            + "\n\n<asset-prompt-input>\n" + payload + "\n</asset-prompt-input>\n"
    }

    private static func load(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Prompts")
            ?? Bundle.module.url(forResource: name, withExtension: "md")!
        return try! String(contentsOf: url, encoding: .utf8)
    }
}
