import FilmCore
import Foundation

/// The checked-in output contract of the manifest-inference job (PHASE2_DESIGN §8.3).
public enum InferManifestSchema: Sendable {
    public static let version = 1
    public static var url: URL {
        Bundle.module.url(forResource: "infer-manifest-v1.schema", withExtension: "json")!
    }
}

/// The one manifest-inference task (PHASE2_DESIGN §8.1).
///
/// **One request, no chunking and no reconcile pass**: the §8.2 input for a feature-length
/// project is compact structured JSON, and the model needs the whole project at once —
/// which is exactly what variant grouping needs. The size bound is explicit rather than
/// implied: `ManifestInputBudget` (FilmCore) refuses an over-budget project pre-flight,
/// naming the size, so nothing is ever silently truncated.
///
/// Nothing here is task machinery: the job state machine, harness events, cancellation,
/// and failure mapping stay `StructuredJobRunner`'s, unchanged.
public struct InferManifestTask: StructuredTask {
    public typealias Output = InferManifestResult
    public let taskName = "inferAssetManifest"
    public let schemaVersion = InferManifestSchema.version
    public let schemaURL = InferManifestSchema.url
    private let validator: InferManifestValidator

    /// - Parameter input: the §8.2 snapshot this run was launched from. Every semantic
    ///   rule of §8.3 is checked against it, and §8.4 step 0 later proves it still holds
    ///   by rebuilding the same input inside the apply transaction.
    public init(input: ManifestInput) {
        self.validator = InferManifestValidator(input: input)
    }

    public func prompt(for input: StructuredTaskInput) throws -> String {
        InferManifestPrompt.render(payload: input.text)
    }

    public func validate(resultFileAt url: URL) throws -> InferManifestResult {
        try validator.validate(resultFileAt: url)
    }
}
