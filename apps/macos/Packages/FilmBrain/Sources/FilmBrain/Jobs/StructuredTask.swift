import FilmCore
import Foundation

/// One structured unit of model work (PHASE1_DESIGN §3.10).
///
/// A task supplies only what varies: its name, its schema, how to build the prompt, and
/// how to turn the result bytes into a validated Swift value. Everything else — the job
/// state machine, harness events, cancellation, and failure mapping — belongs to
/// `StructuredJobRunner` and is shared by every task.
public protocol StructuredTask: Sendable {
    associatedtype Output: Sendable

    /// Recorded in `jobs.task`.
    var taskName: String { get }
    /// Recorded in `jobs.schema_version`.
    var schemaVersion: Int { get }
    /// The checked-in JSON Schema handed to the harness as the output contract.
    var schemaURL: URL { get }

    func prompt(for input: StructuredTaskInput) throws -> String

    /// Reads and validates the file the harness wrote.
    ///
    /// Throw `StructuredValidationFailure` for anything wrong with the result; the
    /// runner maps its code onto the job's failure code unchanged.
    func validate(resultFileAt url: URL) throws -> Output
}

/// What a single job is given to work on.
///
/// The text travels with the input rather than being read from the project, so a task
/// can be run over a chunk, a scene, or any literal string, and a job needs no screenplay
/// in the bundle at all.
public struct StructuredTaskInput: Sendable {
    public let jobID: UUID
    public let text: String
    /// The script this input came from, when it came from one; recorded on the job so a
    /// run can detect a screenplay changing under it (§3.9).
    public let scriptID: UUID?
    public let scriptSHA256: String?
    public let chunkIndex: Int?
    public let chunkCount: Int?
    public let requestedModel: String?
    public let reasoningEffort: String?

    public init(
        jobID: UUID = UUID(),
        text: String,
        scriptID: UUID? = nil,
        scriptSHA256: String? = nil,
        chunkIndex: Int? = nil,
        chunkCount: Int? = nil,
        requestedModel: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.jobID = jobID
        self.text = text
        self.scriptID = scriptID
        self.scriptSHA256 = scriptSHA256
        self.chunkIndex = chunkIndex
        self.chunkCount = chunkCount
        self.requestedModel = requestedModel
        self.reasoningEffort = reasoningEffort
    }
}

/// What one finished job produced: the persisted job row, the validated value, and the
/// usage the harness reported.
public struct StructuredRunResult<Output: Sendable>: Sendable {
    public let job: Job
    public let output: Output
    public let usage: JobUsage

    public init(job: Job, output: Output, usage: JobUsage) {
        self.job = job
        self.output = output
        self.usage = usage
    }
}
