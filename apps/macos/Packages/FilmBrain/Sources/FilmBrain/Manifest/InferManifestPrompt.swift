import CryptoKit
import Foundation

/// The manifest-inference instructions and the delimiter that wraps the §8.2 input
/// (PHASE2_DESIGN §8.1).
///
/// Structurally identical to `ReconcilePrompt`, the pattern §8.1 names: the checked-in
/// instructions, a SHA-256 of them so a prompt change is visible in run history, and one
/// delimiter tag around the untrusted payload. The payload is the rendered
/// `ManifestInput` JSON — never screenplay text (§3.6).
public enum InferManifestPrompt: Sendable {
    public static let instructions: String = load("infer-manifest-v1")
    public static let instructionsSHA256 = digest(instructions)

    public static func render(payload: String) -> String {
        instructions + "\n\n<manifest-input>\n" + payload + "\n</manifest-input>\n"
    }

    private static func load(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Prompts")
            ?? Bundle.module.url(forResource: name, withExtension: "md")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
