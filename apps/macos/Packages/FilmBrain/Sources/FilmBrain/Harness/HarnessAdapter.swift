import Foundation

public struct HarnessRequest: Sendable {
    public let jobID: UUID
    public let prompt: String
    public let workspaceURL: URL
    public let schemaURL: URL
    public let resultURL: URL
    public let logURL: URL
    public let model: String?
    public let reasoningEffort: String?

    public init(
        jobID: UUID,
        prompt: String,
        workspaceURL: URL,
        schemaURL: URL,
        resultURL: URL,
        logURL: URL,
        model: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.jobID = jobID
        self.prompt = prompt
        self.workspaceURL = workspaceURL
        self.schemaURL = schemaURL
        self.resultURL = resultURL
        self.logURL = logURL
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

public protocol HarnessAdapter: Actor {
    nonisolated var capabilities: HarnessCapabilities { get }
    func events(for request: HarnessRequest) -> AsyncThrowingStream<HarnessEvent, any Error>
    func cancel(jobID: UUID) async
}
