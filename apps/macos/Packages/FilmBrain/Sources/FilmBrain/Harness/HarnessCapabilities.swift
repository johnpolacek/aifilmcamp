import Foundation

public enum HarnessCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case structuredResultDelivery
    case progressEvents
    case cancellation
    case nonInteractiveExecution
}

public struct HarnessCapabilities: Codable, Equatable, Sendable {
    public let values: Set<HarnessCapability>
    public let recommendedConcurrency: Int
    public let prefersWarmUp: Bool

    public init(
        _ values: Set<HarnessCapability>,
        recommendedConcurrency: Int = 3,
        prefersWarmUp: Bool = true
    ) {
        self.values = values
        self.recommendedConcurrency = max(1, recommendedConcurrency)
        self.prefersWarmUp = prefersWarmUp
    }

    public static let phase0Required = HarnessCapabilities(Set(HarnessCapability.allCases))

    private enum CodingKeys: String, CodingKey {
        case values
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(Set<HarnessCapability>.self, forKey: .values))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(values, forKey: .values)
    }
}
