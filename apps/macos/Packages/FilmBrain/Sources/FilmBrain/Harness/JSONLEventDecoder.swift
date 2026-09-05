import FilmCore
import Foundation

public enum JSONLDecoderError: Error, Equatable, Sendable {
    case oversizedOutput
}

public struct JSONLEventDecoder: Sendable {
    private var buffer = Data()
    private var totalBytes = 0
    private let maximumBytes: Int

    public init(maximumBytes: Int = 32 * 1_024 * 1_024) {
        self.maximumBytes = maximumBytes
    }

    public mutating func append(_ chunk: Data) throws -> [HarnessEvent] {
        totalBytes += chunk.count
        guard totalBytes <= maximumBytes else { throw JSONLDecoderError.oversizedOutput }
        buffer.append(chunk)
        var events: [HarnessEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            if !line.isEmpty { events.append(decode(line)) }
        }
        return events
    }

    public mutating func finish() -> [HarnessEvent] {
        guard !buffer.isEmpty else { return [] }
        defer { buffer.removeAll(keepingCapacity: false) }
        var line = buffer
        if line.last == 0x0D { line.removeLast() }
        return line.isEmpty ? [] : [decode(line)]
    }

    private func decode(_ line: Data) -> HarnessEvent {
        guard let value = try? JSONSerialization.jsonObject(with: line),
              let object = value as? [String: Any],
              let type = object["type"] as? String
        else { return .decodeWarning("Malformed JSONL event ignored.") }

        switch type {
        case "thread.started":
            return .started(
                threadID: object["thread_id"] as? String,
                effectiveModel: object["model"] as? String
            )
        case "turn.started":
            return .progress("Codex is analyzing the screenplay.")
        case "item.started", "item.updated":
            return .progress("Codex is working.")
        case "item.completed":
            if let item = object["item"] as? [String: Any], item["type"] as? String == "error" {
                return .diagnostic("Codex reported a nonterminal diagnostic item.")
            }
            return .progress("Codex produced analysis output.")
        case "turn.completed":
            let usageObject = object["usage"] as? [String: Any] ?? [:]
            let usage = (try? JobUsage(
                inputTokens: nonnegativeInteger(usageObject["input_tokens"]),
                cachedInputTokens: nonnegativeInteger(usageObject["cached_input_tokens"]),
                cacheWriteInputTokens: nonnegativeInteger(usageObject["cache_write_input_tokens"]),
                outputTokens: nonnegativeInteger(usageObject["output_tokens"]),
                reasoningOutputTokens: nonnegativeInteger(usageObject["reasoning_output_tokens"])
            )) ?? .empty
            return .completed(usage)
        case "turn.failed":
            let error = object["error"] as? [String: Any]
            // The decoder classifies nothing: it emits `.fatal` and `CodexHarnessAdapter`
            // re-maps the kind through `CodexFailureClassifier` (§8.4).
            return .failed(
                code: "turn_failed",
                message: safeMessage(error?["message"] as? String),
                kind: .fatal
            )
        case "error":
            return .failed(
                code: "codex_error",
                message: safeMessage(object["message"] as? String),
                kind: .fatal
            )
        default:
            return .unknown(type: type)
        }
    }
}

private func nonnegativeInteger(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else { return nil }
    let integer = number.intValue
    return integer >= 0 ? integer : nil
}

private func safeMessage(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "Codex reported a terminal error." }
    let singleLine = raw.replacingOccurrences(of: "\n", with: " ")
    return String(singleLine.prefix(512))
}

