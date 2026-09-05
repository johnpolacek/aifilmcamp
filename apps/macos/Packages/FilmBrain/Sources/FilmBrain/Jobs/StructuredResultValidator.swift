import Foundation
import JSONSchema

/// Why a model's result file was rejected (Plan 003 contract C).
///
/// Phase 0's nine semantic codes collapse into `semanticViolation`: the structural half
/// of validation is task-independent and lives here, while what a value *means* is the
/// task's business. Between Plans 003 and 007 no shipped task has semantic rules, which
/// is why the code has no producer inside this type.
public struct StructuredValidationFailure: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Sendable {
        case missingResult
        case oversizedResult
        case malformedJSON
        case schemaViolation
        case semanticViolation
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// The structural half of Phase 0's analyze-screenplay validator, kept verbatim in
/// behavior and made task-agnostic: a regular file, under the 16 MB safety limit, UTF-8,
/// and valid against the schema the task supplies.
///
/// A `StructuredTask` calls this first and then decodes the returned bytes into its own
/// `Output`, throwing `.semanticViolation` for anything the schema cannot express.
public struct StructuredResultValidator: Sendable {
    public static let maximumResultBytes = 16 * 1_024 * 1_024

    public init() {}

    /// Structural validation of the file the harness wrote, returning its bytes.
    ///
    /// The model's output is untrusted, so nothing here decodes before the schema has
    /// accepted the bytes.
    public func validatedData(
        resultFileAt resultURL: URL,
        schemaURL: URL,
        fileManager: FileManager = .default
    ) throws -> Data {
        let values: URLResourceValues
        do {
            values = try resultURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch {
            throw Self.failure(.missingResult, "The harness did not produce a regular result file.")
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw Self.failure(.missingResult, "The harness did not produce a regular result file.")
        }
        guard let size = values.fileSize, size <= Self.maximumResultBytes else {
            throw Self.failure(.oversizedResult, "The harness result exceeded the 16 MB safety limit.")
        }
        let data = try Data(contentsOf: resultURL, options: [.mappedIfSafe])
        try validate(data: data, schemaURL: schemaURL)
        return data
    }

    /// Validates raw bytes against `schemaURL` (draft 2020-12).
    public func validate(data: Data, schemaURL: URL) throws {
        guard data.count <= Self.maximumResultBytes else {
            throw Self.failure(.oversizedResult, "The harness result exceeded the 16 MB safety limit.")
        }
        guard let instance = String(data: data, encoding: .utf8) else {
            throw Self.failure(.malformedJSON, "The harness result is not UTF-8 JSON.")
        }
        let schemaText: String
        do {
            schemaText = try String(contentsOf: schemaURL, encoding: .utf8)
        } catch {
            throw Self.failure(.schemaViolation, "The bundled result schema could not be loaded.")
        }
        let schema: Schema
        do {
            schema = try Schema(instance: schemaText, dialect: .draft2020_12)
        } catch {
            throw Self.failure(.schemaViolation, "The bundled result schema is invalid.")
        }
        let structuralResult: ValidationResult
        do {
            structuralResult = try schema.validate(instance: instance)
        } catch {
            throw Self.failure(.malformedJSON, "The harness result is malformed JSON.")
        }
        guard structuralResult.isValid else {
            throw Self.failure(.schemaViolation, "The harness result does not match the task schema.")
        }
    }

    /// The one failure a task raises for itself, once the bytes are schema-valid.
    public static func semanticViolation(_ message: String) -> StructuredValidationFailure {
        failure(.semanticViolation, message)
    }

    private static func failure(
        _ code: StructuredValidationFailure.Code,
        _ message: String
    ) -> StructuredValidationFailure {
        StructuredValidationFailure(code: code, message: message)
    }
}
