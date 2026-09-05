import Foundation

/// The two deterministic manifest predicates, in one place (PHASE2_DESIGN §3.3, §3.4, §6.4;
/// Plan 009 contract C).
///
/// These are **pure functions over already-fetched facts**: nothing here opens a database,
/// and no read re-implements either rule in SQL. The reads load the rows they need — entity
/// PROV, `manifest_inclusion`, the distinct visible-role scene count, requirement PROV and
/// necessity — and ask this type the question, so a qualification list, a badge, a summary
/// count, and a missing-asset row can never disagree.
///
/// Two rules live here:
///
/// - **Qualification** (§3.3): who earns a canonical identity set. A visible character or
///   location qualifies immediately; production items qualify after recurring in two or
///   more *distinct* scenes. `manifest_inclusion` overrides in both directions, and §3.4's
///   prop exception keeps props out of the automatic rule entirely.
/// - **Activity** (§6.4): the single `active(requirement)` predicate every manifest,
///   blocked, stale, and summary read filters on.
public enum ManifestQualification {
    // MARK: - §3.3 qualification

    /// The roles an appearance must carry to count toward automatic qualification (§3.3).
    ///
    /// `mentioned` is deliberately absent: a character talked about in ten scenes and on
    /// screen in one needs no canonical identity bundle for the nine conversations.
    public static let visibleRoles: Set<SceneEntityRole> = [.speaking, .present, .setting, .used]

    /// §3.3's recurrence threshold for vehicles, creatures, and objects.
    public static let sceneThreshold = 2

    /// Characters and locations define the people and place visible in a generated scene,
    /// so their identity bundle is required from the first visible appearance. The
    /// recurrence threshold remains the noise filter for production-item kinds.
    public static let firstAppearanceKinds: Set<EntityKind> = [.character, .location]

    /// Whether one appearance role counts toward the rule.
    public static func countsAsVisible(_ role: SceneEntityRole) -> Bool {
        visibleRoles.contains(role)
    }

    /// `'speaking','present','setting','used'` — the `IN (…)` list a read builds its scene
    /// count with, generated from `visibleRoles` so the SQL cannot drift from the Swift set.
    public static var visibleRoleSQLList: String {
        visibleRoles
            .map(\.rawValue)
            .sorted()
            .map { "'\($0)'" }
            .joined(separator: ",")
    }

    /// Everything §3.3 and §3.4 need about one entity to answer "does it qualify?".
    ///
    /// `visibleSceneCount` is the count of **distinct scenes** in which the entity appears
    /// in a visible role — an entity `speaking` *and* `present` in one scene counts once —
    /// computed from `scene_entities` by the caller.
    public struct EntityFacts: Equatable, Hashable, Sendable {
        public let kind: EntityKind
        public let reviewState: ReviewState
        public let isRelevant: Bool
        public let manifestInclusion: ManifestInclusion
        public let visibleSceneCount: Int

        public init(
            kind: EntityKind,
            reviewState: ReviewState,
            isRelevant: Bool,
            manifestInclusion: ManifestInclusion,
            visibleSceneCount: Int
        ) {
            self.kind = kind
            self.reviewState = reviewState
            self.isRelevant = isRelevant
            self.manifestInclusion = manifestInclusion
            self.visibleSceneCount = visibleSceneCount
        }

        public init(entity: Entity, visibleSceneCount: Int) {
            self.init(
                kind: entity.kind,
                reviewState: entity.provenance.reviewState,
                isRelevant: entity.isRelevant,
                manifestInclusion: entity.manifestInclusion,
                visibleSceneCount: visibleSceneCount
            )
        }
    }

    /// §3.3's pool: `review_state != 'rejected'` and `is_relevant = 1`, of any kind.
    ///
    /// A still-`proposed` AI entity **is** eligible (§3.7); rejected tombstones and
    /// marked-irrelevant entities earn nothing, whatever their `manifest_inclusion`.
    public static func isEligible(_ facts: EntityFacts) -> Bool {
        facts.reviewState != .rejected && facts.isRelevant
    }

    /// Whether the entity earns a canonical identity set (§3.3, §3.4).
    ///
    /// Eligibility first, then the override, then the count:
    ///
    /// - `never` suppresses regardless of the count (existing rows are badged, never
    ///   deactivated — §5.3, §6.4).
    /// - `always` promotes regardless of the count **and regardless of kind**: it is the
    ///   only way a prop qualifies without an inference run (§3.4).
    /// - `automatic` qualifies characters and locations on their first visible scene, and
    ///   runs the 2+ recurrence rule for vehicles, creatures, and objects. Props remain
    ///   outside the automatic rule: their requirements come from the AI pass, a manual
    ///   add, or `always`.
    public static func qualifies(_ facts: EntityFacts) -> Bool {
        guard isEligible(facts) else { return false }
        switch facts.manifestInclusion {
        case .never:
            return false
        case .always:
            return true
        case .automatic:
            guard facts.kind != .prop else { return false }
            let threshold = firstAppearanceKinds.contains(facts.kind) ? 1 : sceneThreshold
            return facts.visibleSceneCount >= threshold
        }
    }

    /// The convenience overload the reads use once they have the entity row itself.
    public static func qualifies(entity: Entity, visibleSceneCount: Int) -> Bool {
        qualifies(EntityFacts(entity: entity, visibleSceneCount: visibleSceneCount))
    }

    // MARK: - §6.4 activity

    /// Everything §6.4's predicate needs about one requirement and its entity.
    public struct RequirementFacts: Equatable, Hashable, Sendable {
        public let reviewState: ReviewState
        public let necessity: RequirementNecessity
        public let entityReviewState: ReviewState
        public let entityIsRelevant: Bool

        public init(
            reviewState: ReviewState,
            necessity: RequirementNecessity,
            entityReviewState: ReviewState,
            entityIsRelevant: Bool
        ) {
            self.reviewState = reviewState
            self.necessity = necessity
            self.entityReviewState = entityReviewState
            self.entityIsRelevant = entityIsRelevant
        }

        public init(requirement: AssetRequirement, entity: Entity) {
            self.init(
                reviewState: requirement.provenance.reviewState,
                necessity: requirement.necessity,
                entityReviewState: entity.provenance.reviewState,
                entityIsRelevant: entity.isRelevant
            )
        }
    }

    /// §6.4's one predicate:
    ///
    /// > active(requirement) := requirement `review_state != 'rejected'`
    /// > AND `necessity != 'not_needed'`
    /// > AND its entity has `review_state != 'rejected'` and `is_relevant = 1`.
    ///
    /// Qualification drift and `manifest_inclusion = 'never'` do **not** appear here: they
    /// badge rows (§5.3), they never deactivate them. The filmmaker deactivates by rejecting
    /// or marking `not_needed`. `optional` rows stay active and are reported separately.
    public static func isActive(_ facts: RequirementFacts) -> Bool {
        facts.reviewState != .rejected
            && facts.necessity != .notNeeded
            && facts.entityReviewState != .rejected
            && facts.entityIsRelevant
    }

    /// The convenience overload the reads use once they have both rows.
    public static func isActive(requirement: AssetRequirement, entity: Entity) -> Bool {
        isActive(RequirementFacts(requirement: requirement, entity: entity))
    }
}
