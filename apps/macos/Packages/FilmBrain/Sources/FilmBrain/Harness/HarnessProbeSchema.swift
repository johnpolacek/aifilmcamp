import Foundation

/// The smallest schema that still exercises everything Codex's Structured Outputs path
/// can reject: an object closed by `additionalProperties: false`, an integer pinned by
/// both `type` and `const`, and one bounded string.
///
/// It exists so the live compatibility preflight has a schema that belongs to no task.
/// Plan 007's extraction schemas are checked in beside it.
public enum HarnessProbeSchema: Sendable {
    public static var url: URL {
        Bundle.module.url(forResource: "harness-probe-v1.schema", withExtension: "json")!
    }

    /// The preflight's instruction text. Deliberately inline and tiny: it must not
    /// depend on any task's prompt builder.
    public static let prompt = """
        Return only the JSON object described by the schema, echoing the word `ready`.
        """
}
