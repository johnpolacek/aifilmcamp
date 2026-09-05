import Foundation

public actor CodexHarnessAdapter: HarnessAdapter {
    public nonisolated let capabilities = HarnessCapabilities(
        Set(HarnessCapability.allCases),
        recommendedConcurrency: 3,
        prefersWarmUp: true
    )
    private let context: CodexLaunchContext
    private let processRunner: any ProcessRunning
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(
        context: CodexLaunchContext,
        processRunner: any ProcessRunning = FoundationProcessRunner()
    ) {
        self.context = context
        self.processRunner = processRunner
    }

    public func events(for request: HarnessRequest) -> AsyncThrowingStream<HarnessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.execute(request: request, continuation: continuation)
            }
            tasks[request.jobID] = task
        }
    }

    public func cancel(jobID: UUID) {
        tasks[jobID]?.cancel()
    }

    private func execute(
        request: HarnessRequest,
        continuation: AsyncThrowingStream<HarnessEvent, any Error>.Continuation
    ) async {
        defer {
            continuation.finish()
            tasks[request.jobID] = nil
        }
        do {
            try FileManager.default.createDirectory(
                at: request.logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: request.logURL.path, contents: nil)
            let collector = try LiveEventCollector(
                logURL: request.logURL,
                continuation: continuation
            )
            let processRequest = ProcessRequest(
                executableURL: context.executableURL,
                arguments: CodexInvocationBuilder.arguments(for: CodexRunRequest(
                    workspaceURL: request.workspaceURL,
                    schemaURL: request.schemaURL,
                    resultURL: request.resultURL,
                    model: request.model,
                    effort: request.reasoningEffort
                )),
                environment: context.environment,
                standardInput: Data(request.prompt.utf8),
                timeout: .seconds(600),
                stdoutLimit: 32 * 1_024 * 1_024,
                stderrLimit: 1 * 1_024 * 1_024
            )
            let result = try await processRunner.run(processRequest) { chunk in
                collector.consume(chunk)
            }
            collector.finish()

            if Task.isCancelled {
                continuation.yield(.cancelled)
                return
            }
            if let collectorError = collector.error {
                continuation.yield(.failed(code: "jsonl_output", message: collectorError, kind: .fatal))
                return
            }
            if result.timedOut {
                continuation.yield(.failed(
                    code: "timeout",
                    message: "Codex analysis timed out after 10 minutes.",
                    kind: .fatal
                ))
                return
            }
            if result.outputExceeded {
                continuation.yield(.failed(
                    code: "output_limit",
                    message: "Codex output exceeded the safe diagnostic limit.",
                    kind: .fatal
                ))
                return
            }
            if !result.stderr.isEmpty {
                continuation.yield(.diagnostic("Codex wrote diagnostic stderr."))
            }
            if result.exitCode != 0 {
                if !collector.sawTerminalFailure {
                    continuation.yield(.failed(
                        code: "process_exit",
                        message: networkSafeExitMessage(result),
                        kind: .fatal
                    ))
                }
                return
            }
            guard collector.sawTerminalSuccess else {
                continuation.yield(.failed(
                    code: "missing_terminal_success",
                    message: "Codex exited without a successful terminal event.",
                    kind: .fatal
                ))
                return
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: request.resultURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                continuation.yield(.failed(
                    code: "missing_result",
                    message: "Codex exited successfully but did not write a result file.",
                    kind: .fatal
                ))
                return
            }
        } catch is CancellationError {
            continuation.yield(.cancelled)
        } catch {
            continuation.yield(.failed(
                code: "process_launch",
                message: "Codex could not be launched safely.",
                kind: .fatal
            ))
        }
    }

    private func networkSafeExitMessage(_ result: ProcessResult) -> String {
        let lowercased = result.stderrString.lowercased()
        if lowercased.contains("network") || lowercased.contains("connect") || lowercased.contains("proxy") {
            return MinimalLaunchEnvironment.omittedProxyNetworkMessage()
        }
        return "Codex exited unsuccessfully."
    }
}

private final class LiveEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var decoder = JSONLEventDecoder()
    private let logHandle: FileHandle
    private let continuation: AsyncThrowingStream<HarnessEvent, any Error>.Continuation
    private var terminalSuccess = false
    private var terminalFailure = false
    private var storedError: String?

    init(
        logURL: URL,
        continuation: AsyncThrowingStream<HarnessEvent, any Error>.Continuation
    ) throws {
        self.logHandle = try FileHandle(forWritingTo: logURL)
        self.continuation = continuation
    }

    var sawTerminalSuccess: Bool { lock.withLock { terminalSuccess } }
    var sawTerminalFailure: Bool { lock.withLock { terminalFailure } }
    var error: String? { lock.withLock { storedError } }

    func consume(_ chunk: ProcessChunk) {
        lock.withLock {
            switch chunk {
            case let .stdout(data):
                do {
                    try logHandle.write(contentsOf: data)
                    for event in try decoder.append(data) { yield(event) }
                } catch {
                    storedError = "Codex emitted malformed or oversized JSONL output."
                }
            case .stderr:
                break
            }
        }
    }

    func finish() {
        lock.withLock {
            for event in decoder.finish() { yield(event) }
            try? logHandle.close()
        }
    }

    private func yield(_ rawEvent: HarnessEvent) {
        // The decoder emits `.fatal`; classification of the provider's own terminal
        // wording belongs to the adapter (§8.4), so re-map it here — the one place a
        // Codex-produced failure message meets `CodexFailureClassifier`.
        var event = rawEvent
        if case let .failed(code, message, _) = rawEvent {
            event = .failed(
                code: code,
                message: message,
                kind: CodexFailureClassifier.kind(code: code, message: message)
            )
        }
        if event.isTerminalSuccess { terminalSuccess = true }
        if event.isTerminalFailure { terminalFailure = true }
        continuation.yield(event)
    }
}
