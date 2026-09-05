import FilmCore

extension FactSource {
    var displayName: String {
        switch self {
        case .parser: "Parser"
        case .ai: "AI"
        case .human: "Human"
        }
    }
}

extension ReviewState {
    var displayName: String {
        switch self {
        case .proposed: "Proposed"
        case .accepted: "Accepted"
        case .rejected: "Rejected"
        }
    }
}

extension ConfidenceBand {
    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

extension SceneEntityRole {
    var displayName: String {
        switch self {
        case .speaking: "Speaking"
        case .present: "Present"
        case .mentioned: "Mentioned"
        case .setting: "Setting"
        case .used: "Used"
        }
    }
}

extension EntityKind {
    var displayName: String {
        switch self {
        case .character: "Character"
        case .location: "Location"
        case .prop: "Prop"
        case .vehicle: "Vehicle"
        case .creature: "Creature"
        case .object: "Object"
        }
    }
}

extension StateCategory {
    var displayName: String {
        switch self {
        case .timeOfDay: "Time of Day"
        default: rawValue.capitalized
        }
    }
}

extension RelationshipKind {
    var displayName: String { rawValue.capitalized }
}

extension SceneIntExt {
    /// The Scenes table's INT/EXT column.
    var displayName: String {
        switch self {
        case .int: "INT."
        case .ext: "EXT."
        case .intExt: "INT./EXT."
        case .unknown: ""
        }
    }
}
