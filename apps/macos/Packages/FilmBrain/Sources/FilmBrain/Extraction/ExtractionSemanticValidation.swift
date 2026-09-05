import FilmCore
import Foundation

public enum ExtractionSemanticCode: String, Equatable, Sendable {
    case wrongSchemaVersion = "wrong_schema_version"
    case controlCharacter = "control_character"
    case overlongQuote = "overlong_evidence_quote"
    case invalidConfidence = "invalid_confidence"
    case sceneOutsideChunk = "scene_outside_chunk"
    case duplicateFact = "duplicate_fact"
    case danglingEntityReference = "dangling_entity_reference"
    case danglingExistingID = "dangling_existing_id"
    case danglingMergedFrom = "dangling_merged_from"
    case invalidMerge = "invalid_merge"
}

enum ExtractionSemanticValidation {
    static func reject(_ code: ExtractionSemanticCode) -> StructuredValidationFailure {
        StructuredResultValidator.semanticViolation(code.rawValue)
    }

    static func validateText(_ values: String...) throws {
        for value in values where value.unicodeScalars.contains(where: { $0.value < 0x20 }) {
            throw reject(.controlCharacter)
        }
    }

    static func validateQuote(_ quote: String) throws {
        // Evidence is a verbatim excerpt from normalized screenplay text. A useful quote
        // can span a cue and its dialogue, so the normalized line feed is data here rather
        // than an unsafe control character. Every other C0 control remains rejected.
        if quote.unicodeScalars.contains(where: { $0.value < 0x20 && $0.value != 0x0A }) {
            throw reject(.controlCharacter)
        }
        guard quote.utf16.count <= 240 else { throw reject(.overlongQuote) }
    }

    static func validateConfidence(_ confidence: Double) throws {
        guard confidence.isFinite, (0 ... 1).contains(confidence) else {
            throw reject(.invalidConfidence)
        }
    }

    static func normalized(_ value: String) -> String {
        EntityNormalization.normalize(value)
    }
}

extension ExtractionSemanticCode {
    var failureMessage: String {
        switch self {
        case .wrongSchemaVersion:
            "Codex returned a result for an unsupported extraction schema version."
        case .controlCharacter:
            "Codex returned text containing an unsupported control character."
        case .overlongQuote:
            "Codex returned an evidence quote longer than the 240-character limit."
        case .invalidConfidence:
            "Codex returned a confidence value outside the allowed 0–1 range."
        case .sceneOutsideChunk:
            "Codex returned analysis for a scene outside the screenplay chunk it received."
        case .duplicateFact:
            "Codex returned duplicate facts for the same scene."
        case .danglingEntityReference:
            "Codex returned a state, event, or relationship that references an unknown entity."
        case .danglingExistingID:
            "Codex returned an entity identifier that is not in this project."
        case .danglingMergedFrom:
            "Codex returned a merge whose source name was not present in the chunk results."
        case .invalidMerge:
            "Codex returned an invalid entity merge."
        }
    }
}
