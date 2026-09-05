import Foundation
import Darwin

public struct FoundationProcessRunner: ProcessRunning, Sendable {
    private let escalationDelay: TimeInterval
    private let setProcessGroup: @Sendable (pid_t, pid_t) -> Int32
    private let sendSignal: @Sendable (pid_t, Bool, Int32) -> Void

    public init() {
        self.escalationDelay = 2
        self.setProcessGroup = { setpgid($0, $1) }
        self.sendSignal = { pid, useGroup, signal in
            if useGroup {
                _ = killpg(pid, signal)
            } else {
                _ = Darwin.kill(pid, signal)
            }
        }
    }

    init(
        escalationDelay: TimeInterval,
        setProcessGroup: @escaping @Sendable (pid_t, pid_t) -> Int32 = { setpgid($0, $1) },
        sendSignal: @escaping @Sendable (pid_t, Bool, Int32) -> Void
    ) {
        self.escalationDelay = escalationDelay
        self.setProcessGroup = setProcessGroup
        self.sendSignal = sendSignal
    }

    public func run(_ request: ProcessRequest) async throws -> ProcessResult {
        try await run(request, onChunk: { _ in })
    }

    public func run(
        _ request: ProcessRequest,
        onChunk: @escaping @Sendable (ProcessChunk) -> Void
    ) async throws -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = request.standardInput == nil ? nil : Pipe()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.environment = request.environment
        process.currentDirectoryURL = request.currentDirectoryURL
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe ?? FileHandle.nullDevice

        let state = ProcessState(
            process: process,
            stdout: BoundedData(limit: request.stdoutLimit, emit: { onChunk(.stdout($0)) }),
            stderr: BoundedData(limit: request.stderrLimit, emit: { onChunk(.stderr($0)) }),
            escalationDelay: escalationDelay,
            sendSignal: sendSignal
        )
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            state.stdout.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            state.stderr.append(handle.availableData)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation: continuation)
                process.terminationHandler = { _ in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    state.stdout.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                    state.stderr.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                    state.finish()
                }
                do {
                    try process.run()
                    let pid = process.processIdentifier
                    state.didLaunch(
                        pid: pid,
                        processGroupEstablished: setProcessGroup(pid, pid) == 0
                    )
                    if let inputPipe, let input = request.standardInput {
                        inputPipe.fileHandleForWriting.write(input)
                        try? inputPipe.fileHandleForWriting.close()
                    }
                    Task {
                        try? await Task.sleep(for: request.timeout)
                        state.timeout()
                    }
                } catch {
                    state.failToLaunch()
                }
            }
        } onCancel: {
            state.cancel()
        }
    }
}

private final class BoundedData: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage = Data()
    private var didExceed = false
    private let emit: @Sendable (Data) -> Void

    init(limit: Int, emit: @escaping @Sendable (Data) -> Void) {
        self.limit = max(0, limit)
        self.emit = emit
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let accepted = lock.withLock { () -> Data in
            let remaining = max(0, limit - storage.count)
            if data.count > remaining { didExceed = true }
            let accepted = Data(data.prefix(remaining))
            storage.append(accepted)
            return accepted
        }
        if !accepted.isEmpty { emit(accepted) }
    }

    func snapshot() -> (Data, Bool) {
        lock.withLock { (storage, didExceed) }
    }
}

private final class ProcessState: @unchecked Sendable {
    let process: Process
    let stdout: BoundedData
    let stderr: BoundedData
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessResult, any Error>?
    private var finished = false
    private var didTimeOut = false
    private var cancellationRequested = false
    private var launchedPID: pid_t?
    private var processGroupEstablished = false
    private var escalationStarted = false
    private let escalationDelay: TimeInterval
    private let sendSignal: @Sendable (pid_t, Bool, Int32) -> Void

    init(
        process: Process,
        stdout: BoundedData,
        stderr: BoundedData,
        escalationDelay: TimeInterval,
        sendSignal: @escaping @Sendable (pid_t, Bool, Int32) -> Void
    ) {
        self.process = process
        self.stdout = stdout
        self.stderr = stderr
        self.escalationDelay = escalationDelay
        self.sendSignal = sendSignal
    }

    func install(continuation: CheckedContinuation<ProcessResult, any Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func didLaunch(pid: pid_t, processGroupEstablished: Bool) {
        let shouldEscalate = lock.withLock { () -> Bool in
            launchedPID = pid
            self.processGroupEstablished = processGroupEstablished
            return (cancellationRequested || didTimeOut) && !escalationStarted
        }
        if shouldEscalate { startEscalation() }
    }

    func timeout() {
        let shouldTerminate = lock.withLock { () -> Bool in
            guard !finished else { return false }
            didTimeOut = true
            return launchedPID != nil && !escalationStarted
        }
        if shouldTerminate { startEscalation() }
    }

    func cancel() {
        let shouldTerminate = lock.withLock { () -> Bool in
            guard !finished else { return false }
            cancellationRequested = true
            return launchedPID != nil && !escalationStarted
        }
        if shouldTerminate { startEscalation() }
    }

    func failToLaunch() {
        let continuation = lock.withLock { () -> CheckedContinuation<ProcessResult, any Error>? in
            guard !finished else { return nil }
            finished = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(throwing: ProcessRunnerError.couldNotLaunch)
    }

    func finish() {
        let output = stdout.snapshot()
        let errors = stderr.snapshot()
        let completion = lock.withLock { () -> (CheckedContinuation<ProcessResult, any Error>?, Bool) in
            guard !finished else { return (nil, didTimeOut) }
            finished = true
            defer { continuation = nil }
            return (continuation, didTimeOut)
        }
        completion.0?.resume(returning: ProcessResult(
            exitCode: process.terminationStatus,
            stdout: output.0,
            stderr: errors.0,
            timedOut: completion.1,
            outputExceeded: output.1 || errors.1
        ))
    }

    private func startEscalation() {
        let target = lock.withLock { () -> (pid_t, Bool)? in
            guard !finished, !escalationStarted, let launchedPID else { return nil }
            escalationStarted = true
            return (launchedPID, processGroupEstablished)
        }
        guard let target else { return }
        signal(target, SIGINT)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + escalationDelay) { [self] in
            guard process.isRunning else { return }
            signal(target, SIGTERM)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + escalationDelay) { [self] in
                guard process.isRunning else { return }
                signal(target, SIGKILL)
            }
        }
    }

    private func signal(_ target: (pid_t, Bool), _ signal: Int32) {
        sendSignal(target.0, target.1, signal)
    }
}
