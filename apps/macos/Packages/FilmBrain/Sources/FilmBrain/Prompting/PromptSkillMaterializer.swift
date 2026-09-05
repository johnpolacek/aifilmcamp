import CryptoKit
import FilmCore
import Foundation

/// Why materialisation refused (PHASE3_DESIGN §3.5's containment rules). Every case is a
/// refusal, never a sanitised fallback.
public enum PromptSkillMaterializerError: Error, Equatable, LocalizedError, Sendable {
    /// A descriptor path or a tree-relative path failed `RelativeProjectPath`'s rules
    /// (§3.5 rule 1).
    case unsafeRelativePath(String)
    /// A symlink — component or leaf — was found in the source tree or the resident copy
    /// (§3.5 rule 2): rejected, never followed.
    case symlinkInSkillTree(path: String)
    /// The 12-character digest prefix could not be lengthened into a distinct unused path
    /// (§3.5 rule 3) — unrepresentable in practice, refused rather than guessed at.
    case digestPrefixExhausted(digest: String)
    /// The source tree could not be read at all.
    case unreadableTree(path: String, code: Int32)
    /// A non-degradable `clonefile` failure (§3.5's arm B degrades only on
    /// `ENOTSUP`/`EXDEV`, which fall back to a plain copy instead of throwing).
    case cloneFailed(source: String, destination: String, code: Int32)
    /// An imported skill's on-disk tree no longer matches its recorded digest
    /// (PHASE5_DESIGN §8.6): the comparison happens before any copy or clone, so a tree
    /// modified under `skills/` after import can never stage, let alone execute.
    case treeDigestMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case let .unsafeRelativePath(path):
            "The prompt skill names an unsafe path and was not used: \(path)"
        case let .symlinkInSkillTree(path):
            "The prompt skill contains a symbolic link at \(path) and was not used."
        case let .digestPrefixExhausted(digest):
            "The prompt skill cache could not resolve a distinct folder for \(digest)."
        case let .unreadableTree(path, code):
            "The prompt skill tree at \(path) could not be read (error \(code))."
        case let .cloneFailed(source, destination, code):
            "The prompt skill could not be staged for the run (\(source) → \(destination), error \(code))."
        case let .treeDigestMismatch(expected, actual):
            """
            The imported skill's files changed since it was imported \
            (expected \(expected.prefix(12)), found \(actual.prefix(12))). \
            Import the skill again to reuse it.
            """
        }
    }
}

/// What one materialisation produced. The absolute URLs exist **only** for the live
/// invocation's rendered instructions — nothing here is ever persisted to a row (§3.5
/// rule 4: only descriptor-relative provenance is stored).
public struct MaterializedSkill: Equatable, Sendable {
    /// The shared copy under `cache/skills/<skill_id>/<tree-digest-prefix>/`.
    public let sharedCopyURL: URL
    /// The entry file the instructions name — arm B: inside the run's own workspace clone.
    public let entryURL: URL
    /// The routing file beside it, when the descriptor carries one and the tree has it.
    public let routingURL: URL?
    /// SHA-256 over the sorted relative-path/file-SHA manifest of the whole tree — the
    /// cache key (§3.5), never persisted as such.
    public let treeDigest: String
    /// The entry file's digest at materialisation — this is what a prompt row records as
    /// `skill_entry_sha256` (provenance, not the cache key).
    public let entrySHA256: String
}

/// Copies the vendored skill into the project cache so a harness session can read it
/// (PHASE3_DESIGN §3.5; Plan 016 contract A).
///
/// The built Codex invocation disables every ambient-context channel (`skills.include_
/// instructions=false`, `mcp_servers={}`, `web_search="disabled"`), so a skill reaches a
/// session **only as ordinary files the prompt names by path**. This type is that file
/// mover, with four pinned containment rules:
///
/// 1. Every relative path — `skill_id`, entry, routing, and each copied tree path — is
///    validated by `RelativeProjectPath`'s rules, reused by name; a violation refuses.
/// 2. Symlinks are rejected at materialise time, never followed: the source walk reports
///    links instead of descending, and every destination write goes through
///    `BundleContainment`'s no-follow discipline.
/// 3. A 12-character digest-prefix collision never silently reuses a tree: before reusing
///    a resident directory its **full** tree digest is compared, and on disagreement the
///    prefix lengthens until the paths are distinct or the materialiser errs.
/// 4. Only descriptor-relative provenance is persisted (by the caller, onto the prompt
///    row); absolute cache paths live only in the rendered instructions.
///
/// **Arm B** (the probe-deferred design, recorded in `docs/IMPLEMENTATION_NOTES.md`): the
/// shared copy per (descriptor, tree digest) is cloned with `clonefile(2)` into each run's
/// `workspace/skill/`, so unique bytes per run are near zero and the growth bound is
/// stated in bytes of unique data — one skill tree per concurrent run. When `clonefile`
/// returns `ENOTSUP`/`EXDEV` (a bundle on a non-APFS volume), the materialiser falls back
/// to a plain per-run copy under the same path — the bound degrades to one tree per live
/// run, swept by Clear Job Cache either way. Arm B degrades; it never dead-ends.
///
/// The walk, digest, and copy primitives live in FilmCore's `SkillTreeOperations`
/// (PHASE5_DESIGN §3.7 — one validation authority for both run staging and Plan 019's
/// import); this type owns only the staging machinery around them.
public struct PromptSkillMaterializer: Sendable {
    private let descriptor: PromptSkillDescriptor
    /// The project bundle root — `cache/skills/…` lives inside it, under the same
    /// containment rules as everything else the app writes (§4.1).
    private let bundleRoot: URL
    private static let minimumPrefixLength = 12

    /// - Parameters:
    ///   - descriptor: the skill to materialise (untrusted input; validated first).
    ///   - bundleRoot: the project bundle root URL.
    public init(descriptor: PromptSkillDescriptor, bundleRoot: URL) {
        self.descriptor = descriptor
        self.bundleRoot = bundleRoot
    }

    /// Ensures the shared copy exists (idempotent, keyed on the full tree digest), then
    /// stages the run's own clone under `<workspace>/skill/` and returns what the
    /// rendered instructions name.
    ///
    /// - Parameters:
    ///   - workspaceURL: the run's `cache/jobs/<run-id>/workspace/` directory;
    ///     it need not exist yet — the clone creates it.
    ///   - expectedTreeSHA256: for an **imported** skill, the digest recorded on its
    ///     `imported_skills` row (PHASE5_DESIGN §8.6). The exact manifest this call walks
    ///     produces the actual digest, and the comparison happens **before any copy or
    ///     clone** — there is no gap between check and use: the digest that admits the
    ///     tree is computed from the same walk that stages it. A mismatch refuses via
    ///     `.treeDigestMismatch` with nothing staged. The bundled default carries no row,
    ///     passes `nil`, and is exempt.
    public func materialize(
        workspaceURL: URL, expectedTreeSHA256: String? = nil
    ) throws -> MaterializedSkill {
        let manifest = try Self.manifest(of: descriptor.rootURL)
        guard !manifest.entries.isEmpty else {
            throw PromptSkillMaterializerError.unreadableTree(
                path: descriptor.rootURL.path, code: ENOENT
            )
        }
        let digest = manifest.treeDigest()

        // §8.6's authoritative boundary: compare before any copy or clone. Nothing has
        // been staged yet, so a refusal leaves no residue anywhere under the cache.
        if let expected = expectedTreeSHA256, expected != digest {
            throw PromptSkillMaterializerError.treeDigestMismatch(
                expected: expected, actual: digest
            )
        }

        // Rule 3: resolve the shared-copy directory against the full digest, never the
        // prefix alone.
        let sharedCopy = try resolveSharedCopy(digest: digest)
        if !sharedCopy.existed {
            try Self.copyTree(manifest, from: descriptor.rootURL, to: sharedCopy.url)
        }

        // Arm B: the run reads its own clone, never the shared copy.
        let workspaceSkill = workspaceURL.appending(path: "skill", directoryHint: .isDirectory)
        try stageRunClone(from: sharedCopy.url, to: workspaceSkill)

        let entryURL = workspaceSkill.appending(path: descriptor.entryRelativePath)
        guard FileManager.default.fileExists(atPath: entryURL.path) else {
            throw PromptSkillMaterializerError.unreadableTree(
                path: descriptor.entryRelativePath, code: ENOENT
            )
        }
        var routingURL: URL?
        if let routing = descriptor.stillImageRoutingRelativePath,
           FileManager.default.fileExists(
               atPath: workspaceSkill.appending(path: routing).path
           ) {
            routingURL = workspaceSkill.appending(path: routing)
        }
        let entrySHA = manifest.sha256[descriptor.entryRelativePath]
            ?? Self.fileSHA256(at: entryURL.path)
        return MaterializedSkill(
            sharedCopyURL: sharedCopy.url,
            entryURL: entryURL,
            routingURL: routingURL,
            treeDigest: digest,
            entrySHA256: entrySHA ?? ""
        )
    }

    // MARK: - Rule 3: collision-safe shared copy

    private struct ResolvedCopy {
        let url: URL
        let existed: Bool
    }

    /// Finds the directory for `digest`: reuse only on **full-digest** equality of the
    /// resident tree; lengthen the prefix on disagreement; refuse when exhausted.
    private func resolveSharedCopy(digest: String) throws -> ResolvedCopy {
        let skillsRoot = bundleRoot.appending(
            path: "cache/skills/\(descriptor.id)", directoryHint: .isDirectory
        )
        var length = min(Self.minimumPrefixLength, digest.count)
        while true {
            let candidate = skillsRoot.appending(
                path: String(digest.prefix(length)), directoryHint: .isDirectory
            )
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                try FileManager.default.createDirectory(
                    at: candidate, withIntermediateDirectories: true
                )
                return ResolvedCopy(url: candidate, existed: false)
            }
            // Resident tree: reuse only if its full digest matches ours (rule 3).
            if try Self.manifest(of: candidate).treeDigest() == digest {
                return ResolvedCopy(url: candidate, existed: true)
            }
            length += 1
            guard length <= digest.count else {
                throw PromptSkillMaterializerError.digestPrefixExhausted(digest: digest)
            }
        }
    }

    // MARK: - Arm B staging

    /// Clones the shared copy into the run's workspace; degrades to a plain copy exactly
    /// when the volume cannot clone (`ENOTSUP`/`EXDEV`) and refuses anything else.
    private func stageRunClone(from source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if clonefile(source.path, destination.path, 0) == 0 { return }
        let code = errno
        if code == ENOTSUP || code == EXDEV {
            // Non-APFS volume: plain per-run copy under the same path. The growth bound
            // degrades to one tree per live run; the degradation is recorded in
            // docs/IMPLEMENTATION_NOTES.md.
            let manifest = try Self.manifest(of: source)
            try FileManager.default.createDirectory(
                at: destination, withIntermediateDirectories: true
            )
            try Self.copyTree(manifest, from: source, to: destination)
            return
        }
        throw PromptSkillMaterializerError.cloneFailed(
            source: source.path, destination: destination.path, code: code
        )
    }

    // MARK: - The primitives, consumed from FilmCore (§3.7)

    /// The moved-down manifest walk, with its errors mapped 1:1 into this type's public
    /// cases so every caller sees identical refusals.
    static func manifest(of rawRoot: URL) throws -> TreeManifest {
        do {
            return try SkillTreeOperations.manifest(of: rawRoot)
        } catch let error as SkillTreeOperations.OperationError {
            switch error {
            case let .unsafeRelativePath(path):
                throw PromptSkillMaterializerError.unsafeRelativePath(path)
            case let .symlinkInTree(path):
                throw PromptSkillMaterializerError.symlinkInSkillTree(path: path)
            case let .unreadableTree(path, code):
                throw PromptSkillMaterializerError.unreadableTree(path: path, code: code)
            }
        }
    }

    /// The moved-down file digest.
    static func fileSHA256(at path: String) -> String? {
        SkillTreeOperations.fileSHA256(at: path)
    }

    /// The moved-down contained copy.
    static func copyTree(_ manifest: TreeManifest, from sourceRoot: URL, to destinationRoot: URL)
        throws {
        try SkillTreeOperations.copyTree(manifest, from: sourceRoot, to: destinationRoot)
    }
}

/// The manifest type is the moved-down one — one spelling, two consumers (§3.7).
extension PromptSkillMaterializer {
    typealias TreeManifest = SkillTreeOperations.TreeManifest
}
