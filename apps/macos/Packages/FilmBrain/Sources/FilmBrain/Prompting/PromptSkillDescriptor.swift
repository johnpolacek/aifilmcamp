import FilmCore
import Foundation

/// Which prompt skill a run uses (PHASE3_DESIGN §3.5) — the swappability seam.
///
/// The descriptor is **data, never a hardcoded path**: Phase 5 swaps the skill by handing
/// a different descriptor to the run, with no app change. `rootURL` is a parameter because
/// FilmBrain never resolves the app bundle.
///
/// The descriptor is **untrusted input** (§3.5): every path it names is validated by
/// `RelativeProjectPath`'s rules before anything is opened, and a violation refuses
/// materialisation and therefore the run — it never falls back to a sanitised path.
public struct PromptSkillDescriptor: Sendable {
    /// Cache-path component and persisted provenance (`asset_prompts.skill_id`).
    public let id: String
    /// Display name for run history.
    public let displayName: String
    /// The vendored tree's root on disk (the app resolves its bundled copy).
    public let rootURL: URL
    /// Descriptor-relative entry file (`SKILL.md` for the default).
    public let entryRelativePath: String
    /// Descriptor-relative still-image routing table, when the skill carries one. Carried
    /// separately because the vendored entry never references it — "read the entry" alone
    /// would not reach the routing table the model choice depends on (§3.5).
    public let stillImageRoutingRelativePath: String?

    public init(
        id: String,
        displayName: String,
        rootURL: URL,
        entryRelativePath: String,
        stillImageRoutingRelativePath: String? = nil
    ) throws {
        guard (try? RelativeProjectPath(id)) != nil else {
            throw PromptSkillMaterializerError.unsafeRelativePath(id)
        }
        // A single-component id is what the cache layout assumes; a nested id would make
        // `cache/skills/<id>/<digest>` ambiguous with the tree itself.
        guard !id.contains("/") else {
            throw PromptSkillMaterializerError.unsafeRelativePath(id)
        }
        guard (try? RelativeProjectPath(entryRelativePath)) != nil else {
            throw PromptSkillMaterializerError.unsafeRelativePath(entryRelativePath)
        }
        if let routing = stillImageRoutingRelativePath {
            guard (try? RelativeProjectPath(routing)) != nil else {
                throw PromptSkillMaterializerError.unsafeRelativePath(routing)
            }
        }
        self.id = id
        self.displayName = displayName
        self.rootURL = rootURL
        self.entryRelativePath = entryRelativePath
        self.stillImageRoutingRelativePath = stillImageRoutingRelativePath
    }
}
