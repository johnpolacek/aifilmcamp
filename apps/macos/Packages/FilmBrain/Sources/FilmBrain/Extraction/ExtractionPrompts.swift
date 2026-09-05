import CryptoKit
import Foundation

public enum ExtractChunkPrompt: Sendable {
    public static let instructions: String = load("extract-chunk-v1")
    public static let instructionsSHA256 = digest(instructions)

    public static func render(payload: String) -> String {
        instructions + "\n\n<screenplay-chunk>\n" + payload + "\n</screenplay-chunk>\n"
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

public enum ReconcilePrompt: Sendable {
    public static let instructions: String = load("reconcile-entities-v1")
    public static let instructionsSHA256 = digest(instructions)

    public static func render(payload: String) -> String {
        instructions + "\n\n<reconcile-input>\n" + payload + "\n</reconcile-input>\n"
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
