import FilmCore
import SwiftUI

// The Manifest section's display vocabulary (PHASE2_DESIGN §5.3, §6.1), in one place so a
// list badge and an inspector badge can never word the same fact differently.

extension AssetRequirementTier {
    var displayName: String {
        switch self {
        case .canonical: "Canonical"
        case .variant: "Variant"
        }
    }
}

extension RequirementNecessity {
    var displayName: String {
        switch self {
        case .required: "Required"
        case .optional: "Optional"
        case .notNeeded: "Not Needed"
        }
    }
}

extension AssetStatus {
    /// `docs/OVERVIEW.md#asset-states`, verbatim. `needed` is also the *derived* display
    /// state of a requirement with no asset row (§6.1) — the axis the UI keeps visually
    /// distinct from the requirement's own review state.
    var displayName: String {
        switch self {
        case .needed: "Needed"
        case .promptReady: "Prompt Ready"
        case .inProgress: "In Progress"
        case .needsReview: "Needs Review"
        case .approved: "Approved"
        case .rejected: "Rejected"
        case .deprecated: "Deprecated"
        }
    }
}

extension RequirementDrift {
    /// §5.3's badge wording, verbatim. `sceneCount` fills the "appears in 1 scene" half of
    /// the no-longer-qualifies badge.
    func badges(sceneCount: Int) -> [String] {
        var badges: [String] = []
        if contains(.noLongerQualifies) {
            badges.append(
                "no longer qualifies (appears in \(sceneCount) scene\(sceneCount == 1 ? "" : "s"))"
            )
        }
        if contains(.suppressed) { badges.append("suppressed") }
        if contains(.templateEntryDisabled) { badges.append("template entry disabled") }
        return badges
    }
}

/// One small capsule badge, the same shape the entity list's review badge uses.
struct ManifestBadge: View {
    let text: String
    /// What VoiceOver reads; the visible text is often a fragment of a longer sentence.
    let label: String
    var tint: Color = .secondary
    var identifier: String?

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .accessibilityIdentifier(identifier ?? "manifestBadge")
            .accessibilityLabel(label)
    }
}
