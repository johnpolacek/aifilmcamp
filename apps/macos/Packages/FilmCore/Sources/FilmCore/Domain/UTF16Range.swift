import Foundation

/// A half-open UTF-16 range into `Script.sourceText` (PHASE1_DESIGN §3.3).
///
/// FilmCore owns this type deliberately, shadowing `FilmScript.UTF16Range`: the storage
/// and app layers must never have to import the parser to read a span (§3.1). The import
/// mapper qualifies the FilmScript spelling where both are in scope.
public struct UTF16Range: Codable, Equatable, Hashable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}
