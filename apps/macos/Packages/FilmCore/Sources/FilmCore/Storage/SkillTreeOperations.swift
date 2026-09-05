import CryptoKit
import Foundation

/// The pure skill-tree primitives (PHASE5_DESIGN §3.7, §4.4; Plan 018 contract F) —
/// moved down from FilmBrain's `PromptSkillMaterializer` so FilmCore's `importSceneSkill`
/// (Plan 019) and the materialiser share **one validation authority**: no reversed
/// dependency, no duplicated security rules.
///
/// Three primitives, byte-for-byte the materialiser's shipped behavior:
///
/// 1. **The manifest walk** — every relative path validated by `RelativeProjectPath`'s
///    rules; symlinks (component or leaf) refused, never followed or sanitised.
/// 2. **The sorted-manifest tree digest** — SHA-256 over the sorted
///    relative-path/file-SHA listing; the cache key and the imported-skill integrity
///    anchor (`imported_skills.tree_sha256`).
/// 3. **The contained tree copy** — same relative layout, every destination write through
///    `BundleContainment`'s no-follow discipline.
///
/// What deliberately stays in FilmBrain: the staging machinery (shared-copy cache layout,
/// `clonefile` cloning, digest-prefix lengthening) — those are run-staging behavior the
/// primitives do not own (§10's suite split).
public enum SkillTreeOperations {
    /// Why a primitive refused. Every case is a refusal, never a sanitised fallback.
    public enum OperationError: Error, Equatable, LocalizedError, Sendable {
        /// A tree-relative path failed `RelativeProjectPath`'s rules.
        case unsafeRelativePath(String)
        /// A symlink — component or leaf — was found in the tree: rejected, never followed.
        case symlinkInTree(path: String)
        /// The tree could not be read at all.
        case unreadableTree(path: String, code: Int32)

        public var errorDescription: String? {
            switch self {
            case let .unsafeRelativePath(path):
                "The skill tree names an unsafe path and was not used: \(path)"
            case let .symlinkInTree(path):
                "The skill tree contains a symbolic link at \(path) and was not used."
            case let .unreadableTree(path, code):
                "The skill tree at \(path) could not be read (error \(code))."
            }
        }
    }

    /// The sorted relative-path/file-SHA manifest of one tree — the walk's output and the
    /// digest's input.
    public struct TreeManifest: Equatable, Sendable {
        /// Relative paths of regular files, with their SHA-256 digests.
        public let sha256: [String: String]

        public init(sha256: [String: String]) {
            self.sha256 = sha256
        }

        /// Sorted relative paths — determinism rule 1's total ordering for the digest.
        public var entries: [String] {
            sha256.keys.sorted()
        }

        /// SHA-256 over the sorted relative-path/file-SHA manifest of the whole tree.
        public func treeDigest() -> String {
            var text = ""
            for entry in entries {
                text += entry + "\n" + (sha256[entry] ?? "") + "\n"
            }
            return SHA256.hash(data: Data(text.utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Walks the tree without following symlinks, hashing every regular file. A symlink —
    /// component or leaf — throws; paths are validated as they are produced.
    ///
    /// The **path-based** enumerator yields subpaths relative to its root — no prefix
    /// arithmetic against a possibly differently-spelled absolute path (/var vs
    /// /private/var), and it neither follows nor descends into symlinks, exactly the
    /// posture `ProjectSession.orphanedMedia()` walks with.
    public static func manifest(of rawRoot: URL) throws -> TreeManifest {
        let root = rawRoot.standardizedFileURL
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw OperationError.unreadableTree(path: root.path, code: errno)
        }
        var digests: [String: String] = [:]
        while let subpath = walker.nextObject() as? String {
            guard !subpath.isEmpty else { continue }
            let full = root.appending(path: subpath).path
            // `attributesOfItem` does not resolve a symlink: it reports the link itself.
            let attributes = try FileManager.default.attributesOfItem(atPath: full)
            switch attributes[.type] as? FileAttributeType {
            case .some(.typeSymbolicLink):
                throw OperationError.symlinkInTree(path: full)
            case .some(.typeRegular):
                guard (try? RelativeProjectPath(subpath)) != nil else {
                    throw OperationError.unsafeRelativePath(subpath)
                }
                guard let sha = fileSHA256(at: full) else {
                    throw OperationError.unreadableTree(path: full, code: EIO)
                }
                digests[subpath] = sha
            default:
                continue
            }
        }
        return TreeManifest(sha256: digests)
    }

    /// SHA-256 over one file's bytes, lowercase hex; `nil` when unreadable.
    public static func fileSHA256(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Copies the walked manifest verbatim — same relative layout, because skills address
    /// each other by relative path (`PromptSkills/README.md`). Every write goes through
    /// `BundleContainment`, so a link planted in the destination after validation
    /// redirects nothing.
    public static func copyTree(
        _ manifest: TreeManifest, from sourceRoot: URL, to destinationRoot: URL
    ) throws {
        for entry in manifest.entries {
            let data = try Data(
                contentsOf: sourceRoot.appending(path: entry),
                options: .mappedIfSafe
            )
            let containment = BundleContainment(rootURL: destinationRoot)
            try containment.write(data, to: RelativeProjectPath(entry))
        }
    }
}
