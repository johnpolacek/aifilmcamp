import Foundation

/// What one **Build Asset Manifest** did (PHASE2_DESIGN §5.2).
///
/// `refreshCanonicalRequirements` is idempotent and repeatable, so the interesting answer is
/// not "did it work" but "how many slots did it add, and which ones could it not add". A
/// name collision is a **counted skip, never a throw**: `UNIQUE(entity_id, name_normalized)`
/// spans tiers, so an existing requirement of any tier whose normalized name equals the
/// template entry's display name blocks that one creation, and Build carries on.
///
/// `entry` is `nil` for the idempotent no-op Build: `performGroup` always journals when it
/// is invoked, so the engine **guards before it** and an empty refresh writes no journal row.
public struct ManifestBuildResult: Equatable, Sendable {

    /// One template slot Build could not create, naming both halves so §5.3's badge can say
    /// "canonical slot '<entry>' blocked by an existing requirement name — rename or delete
    /// it, then Build".
    public struct Collision: Equatable, Hashable, Sendable {
        public let entityID: UUID
        /// The template entry that was blocked.
        public let typeID: UUID
        /// That entry's frozen `code` (§3.2).
        public let templateCode: String
        /// That entry's display name — the name the canonical row would have taken.
        public let templateDisplayName: String
        /// The requirement row already holding the normalized form, of either tier.
        public let existingRequirementID: UUID

        public init(
            entityID: UUID,
            typeID: UUID,
            templateCode: String,
            templateDisplayName: String,
            existingRequirementID: UUID
        ) {
            self.entityID = entityID
            self.typeID = typeID
            self.templateCode = templateCode
            self.templateDisplayName = templateDisplayName
            self.existingRequirementID = existingRequirementID
        }
    }

    /// How many canonical requirement rows this Build created.
    public let created: Int
    /// The slots it skipped on a §5.2 name collision, in build order.
    public let collisions: [Collision]
    /// The one journal row the group wrote, or `nil` when there was nothing to create.
    public let entry: JournalEntry?

    public init(created: Int, collisions: [Collision], entry: JournalEntry?) {
        self.created = created
        self.collisions = collisions
        self.entry = entry
    }
}
