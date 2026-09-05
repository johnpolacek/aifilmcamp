import FilmCore
import Foundation

/// The coordinator-side twin of FilmCore's §8.1 pre-flight (PHASE5_DESIGN §8.1; Plan 021
/// contract A) — the shipped `AssetPromptRunGate` pattern: this type never enforces
/// anything, it asks the same questions **ahead of launching** so the coordinator
/// declines without creating a job row and the UI greys Generate/Regenerate out with the
/// store's own refusal sentence attached, never a paraphrase.
///
/// The pre-flight questions of §8.1 at scene scale: the scene is counted, Asset Ready per
/// Plan 017's snapshot read, the run targets the active cataloged profile P (generating
/// for an inactive profile is deliberately not a surface), the reference plan is within
/// the profile's limit — plus §8.1's bootstrap-idle gate (refused while any extraction or
/// manifest run is non-terminal **or paused**). When a custom skill is selected its
/// imported tree re-verifies against the stored `tree_sha256` here for early feedback;
/// that check is not the authority — the materialiser's staging walk is (§8.6). Budget
/// is checked at run start against the rendered snapshot itself.
public enum ScenePromptRunGate: Sendable {
    public enum Refusal: Error, Equatable, Sendable {
        /// An extraction or manifest run is non-terminal or paused.
        case bootstrapsBusy
        /// The scene is excluded — it carries no package state at all (§3.3).
        case sceneNotCounted
        /// The scene is not Asset Ready per Plan 017's snapshot.
        case sceneNotAssetReady
        /// The persisted profile id is no longer in the catalog.
        case profileMissing(id: String)
        /// The satisfied reference plan exceeds the profile's image limit.
        case overLimit(count: Int, limit: Int)
        /// A custom skill is selected and its imported tree is missing or altered.
        case importedSkillTreeMissing

        public var error: ProjectStoreError {
            switch self {
            case .bootstrapsBusy: .promptRunRequiresIdleBootstraps
            case .sceneNotCounted: .sceneOperationRefused(
                reason: "Excluded scenes are not prepared for generation."
            )
            case .sceneNotAssetReady: .scenePromptRequiresAssetReady
            case let .profileMissing(id): .generationTargetProfileMissing(id: id)
            case let .overLimit(count, limit): .sceneReferencesExceedProfileLimit(
                count: count, limit: limit
            )
            case .importedSkillTreeMissing: .importedSkillTreeMissing
            }
        }
    }

    /// Everything the gate asks about, resolved once by the caller from the shipped
    /// reads — this type performs no database access of its own.
    public struct Questions: Equatable, Sendable {
        public var sceneCounted: Bool
        public var assetReady: Bool
        /// The persisted active profile P resolved against the catalog; `nil` when the
        /// id the project names is no longer carried (§3.5's removed-id edge).
        public var activeProfile: TargetProfile?
        /// The raw persisted id, for the missing-profile refusal to name.
        public var activeProfileID: String
        public var satisfiedReferenceCount: Int
        public var customSkillTreeVerified: Bool
        public var bootstrapsIdle: Bool

        public init(
            sceneCounted: Bool,
            assetReady: Bool,
            activeProfile: TargetProfile?,
            activeProfileID: String,
            satisfiedReferenceCount: Int,
            customSkillTreeVerified: Bool,
            bootstrapsIdle: Bool
        ) {
            self.sceneCounted = sceneCounted
            self.assetReady = assetReady
            self.activeProfile = activeProfile
            self.activeProfileID = activeProfileID
            self.satisfiedReferenceCount = satisfiedReferenceCount
            self.customSkillTreeVerified = customSkillTreeVerified
            self.bootstrapsIdle = bootstrapsIdle
        }
    }

    /// `nil` when a scene-prompt run may be launched for this scene right now.
    public static func refusal(_ questions: Questions) -> Refusal? {
        guard questions.bootstrapsIdle else { return .bootstrapsBusy }
        guard questions.sceneCounted else { return .sceneNotCounted }
        guard questions.assetReady else { return .sceneNotAssetReady }
        guard let profile = questions.activeProfile else {
            return .profileMissing(id: questions.activeProfileID)
        }
        guard questions.satisfiedReferenceCount <= profile.imageReferenceLimit else {
            return .overLimit(
                count: questions.satisfiedReferenceCount,
                limit: profile.imageReferenceLimit
            )
        }
        guard questions.customSkillTreeVerified else { return .importedSkillTreeMissing }
        return nil
    }
}
