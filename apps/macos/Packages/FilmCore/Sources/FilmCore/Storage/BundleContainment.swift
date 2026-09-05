import Darwin
import Foundation

/// A containment refusal, naming the component that caused it (PHASE2_DESIGN §4.1).
public enum BundleContainmentError: Error, Equatable, LocalizedError, Sendable {
    /// A component of the path — or the leaf itself — is a symbolic link.
    case symlinkedComponent(path: String, component: String)
    /// A component that must be a directory is a regular file.
    case notADirectory(path: String, component: String)
    /// A component the operation required does not exist.
    case missingComponent(path: String, component: String)
    /// The bundle root itself could not be opened as a directory.
    case unopenableRoot(path: String, code: Int32)
    /// Any other `openat`/`mkdirat`/`renameat`/`unlinkat` failure, with its `errno`.
    case operationFailed(path: String, component: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case let .symlinkedComponent(path, component):
            "“\(component)” in \(path) is a symbolic link, so the project refused the operation."
        case let .notADirectory(path, component):
            "“\(component)” in \(path) is not a folder."
        case let .missingComponent(path, component):
            "“\(component)” in \(path) is missing."
        case let .unopenableRoot(path, code):
            "The project bundle at \(path) could not be opened (error \(code))."
        case let .operationFailed(path, component, code):
            "The project could not use “\(component)” in \(path) (error \(code))."
        }
    }
}

/// Descriptor-relative containment for everything the app writes, reads, or removes inside
/// a bundle (PHASE2_DESIGN §4.1).
///
/// `RelativeProjectPath`'s checks are **lexical**: they stop `..` and absolute paths, but a
/// symlink planted inside the bundle defeats them. A `realpath` validation followed by a
/// separate path-based operation does not fix that either — it is check-then-operate, and
/// an intermediate directory swapped for a symlink in the window between the two redirects
/// the operation outside the project.
///
/// So nothing here validates a path and then re-traverses it. The bundle root is opened
/// **once** as a directory descriptor; every component is walked descriptor-relative with
/// `openat(O_NOFOLLOW | O_DIRECTORY)`, so a symlinked component fails the walk rather than
/// being followed; and the operation itself runs against the descriptor that walk produced
/// (`openat` / `renameat` / `unlinkat` forms), so no component can be swapped between the
/// check and the use. A not-yet-created leaf is created descriptor-relative under its
/// already-walked parent.
///
/// The two properties this buys, both test-asserted: a **planted** symlink (component or
/// leaf) is refused, and a symlink swapped in **after** validation cannot redirect the
/// operation, because there is no second traversal to redirect.
public struct BundleContainment: Sendable {
    /// What a leaf turned out to be. A symlink is never one of these — it throws.
    public enum EntryKind: Equatable, Sendable {
        case missing
        case file
        case directory
    }

    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    // MARK: - Operations

    /// Writes `data` at `path`, replacing whatever is there, without ever following a
    /// symlink.
    ///
    /// Atomicity is the `importScreenplay` discipline done descriptor-relative: the bytes
    /// go to a temporary name in the **already-walked** parent directory and are then
    /// `renameat`-ed onto the leaf. `renameat` never follows a symlink at its final
    /// component, so even a leaf swapped mid-operation is replaced rather than written
    /// through — and a leaf that is *already* a symlink is refused outright, so the
    /// caller hears about the planted link instead of silently clobbering it.
    public func write(
        _ data: Data,
        to path: RelativeProjectPath,
        createIntermediates: Bool = true
    ) throws {
        let components = Self.components(of: path)
        let leaf = components[components.count - 1]
        try withParentDescriptor(
            of: components,
            createIntermediates: createIntermediates,
            path: path
        ) { parent in
            // Refuse a planted symlinked leaf explicitly (the `renameat` below would
            // replace it safely, but silence is the wrong answer to a planted link).
            _ = try Self.leafStat(parent: parent, leaf: leaf, path: path)

            let temporaryName = ".\(leaf).staging-\(UUID().uuidString)"
            let descriptor = openat(
                parent, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644
            )
            guard descriptor >= 0 else {
                throw BundleContainmentError.operationFailed(
                    path: path.rawValue, component: temporaryName, code: errno
                )
            }
            var written = false
            defer {
                close(descriptor)
                if !written { unlinkat(parent, temporaryName, 0) }
            }
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(
                        descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset
                    )
                    guard count > 0 else {
                        throw BundleContainmentError.operationFailed(
                            path: path.rawValue, component: temporaryName, code: errno
                        )
                    }
                    offset += count
                }
            }
            guard renameat(parent, temporaryName, parent, leaf) == 0 else {
                throw BundleContainmentError.operationFailed(
                    path: path.rawValue, component: leaf, code: errno
                )
            }
            written = true
        }
    }

    /// What sits at `path` — without following a symlink anywhere along it. A symlinked
    /// leaf throws rather than reporting a kind: "there is a link here" is a refusal, not
    /// an answer a caller should route around.
    public func entryKind(at path: RelativeProjectPath) throws -> EntryKind {
        let components = Self.components(of: path)
        let leaf = components[components.count - 1]
        return try withParentDescriptor(
            of: components,
            createIntermediates: false,
            path: path,
            allowMissingParent: true
        ) { parent in
            guard let status = try Self.leafStat(parent: parent, leaf: leaf, path: path) else {
                return .missing
            }
            return (status.st_mode & S_IFMT) == S_IFDIR ? .directory : .file
        } ?? .missing
    }

    /// Removes the leaf at `path` if it is there, following nothing. `unlinkat` removes the
    /// directory entry itself, so a symlink is unlinked rather than resolved.
    @discardableResult
    public func removeIfPresent(at path: RelativeProjectPath) throws -> Bool {
        let components = Self.components(of: path)
        let leaf = components[components.count - 1]
        return try withParentDescriptor(
            of: components,
            createIntermediates: false,
            path: path,
            allowMissingParent: true
        ) { parent in
            if unlinkat(parent, leaf, 0) == 0 { return true }
            let code = errno
            if code == ENOENT { return false }
            throw BundleContainmentError.operationFailed(
                path: path.rawValue, component: leaf, code: code
            )
        } ?? false
    }

    /// Removes the **empty** directory at `path` if it is there (`AT_REMOVEDIR`), following
    /// nothing. The orphaned-skill-tree sweep's bottom-up step; a non-empty or symlinked
    /// leaf refuses rather than recursing here.
    @discardableResult
    public func removeDirectoryIfPresent(at path: RelativeProjectPath) throws -> Bool {
        let components = Self.components(of: path)
        let leaf = components[components.count - 1]
        return try withParentDescriptor(
            of: components,
            createIntermediates: false,
            path: path,
            allowMissingParent: true
        ) { parent in
            if unlinkat(parent, leaf, AT_REMOVEDIR) == 0 { return true }
            let code = errno
            if code == ENOENT { return false }
            throw BundleContainmentError.operationFailed(
                path: path.rawValue, component: leaf, code: code
            )
        } ?? false
    }

    /// Removes the directory **tree** at `path` leaf-wise, following nothing, and returns
    /// the regular-file bytes freed (`-1` when the root was already gone).
    ///
    /// This is the one recursive deletion in FilmCore, and every unlink below runs through
    /// the same descriptor-relative discipline as everything else here: the walk is the
    /// path-based enumerator (symlinks are neither followed nor descended), files go by
    /// `unlinkat` deepest-first, and emptied directories go bottom-up by `AT_REMOVEDIR`.
    /// Callers: the orphaned-skill-tree sweep and the exporter's staging/trash cleanup.
    @discardableResult
    public func removeDirectoryTree(at path: RelativeProjectPath) throws -> Int64 {
        guard try entryKind(at: path) == .directory else { return -1 }
        let absoluteRoot = rootURL.appending(path: path.rawValue)
        let fileManager = FileManager.default

        var bytes: Int64 = 0
        var files: [RelativeProjectPath] = []
        var directories: [RelativeProjectPath] = []
        if let walker = fileManager.enumerator(atPath: absoluteRoot.path) {
            while let subpath = walker.nextObject() as? String {
                let relative = try RelativeProjectPath(path.rawValue + "/" + subpath)
                let full = absoluteRoot.appending(path: subpath).path
                let item = (try? fileManager.attributesOfItem(atPath: full)) ?? [:]
                switch item[.type] as? FileAttributeType {
                case .some(.typeRegular):
                    bytes += Int64((item[.size] as? NSNumber)?.int64Value ?? 0)
                    files.append(relative)
                case .some(.typeDirectory):
                    directories.append(relative)
                default:
                    continue
                }
            }
        }
        func depthFirst(_ lhs: RelativeProjectPath, _ rhs: RelativeProjectPath) -> Bool {
            let lhsDepth = lhs.rawValue.split(separator: "/").count
            let rhsDepth = rhs.rawValue.split(separator: "/").count
            return lhsDepth > rhsDepth || (lhsDepth == rhsDepth && lhs.rawValue > rhs.rawValue)
        }
        for file in files.sorted(by: depthFirst) {
            _ = try removeIfPresent(at: file)
        }
        for directory in directories.sorted(by: depthFirst) {
            try removeDirectoryIfPresent(at: directory)
        }
        try removeDirectoryIfPresent(at: path)
        return bytes
    }

    /// Renames one entry to a sibling name **within the same walked parent directory**
    /// (`renameat`, never following a symlink at either component). The exporter's staged
    /// replace runs through this: staging and destination are siblings under
    /// `exports/scenes/`, so one descriptor-relative rename moves a fully verified
    /// directory onto its destination.
    public func renameEntry(at path: RelativeProjectPath, to sibling: RelativeProjectPath) throws {
        let fromComponents = Self.components(of: path)
        let toComponents = Self.components(of: sibling)
        guard fromComponents.dropLast() == toComponents.dropLast() else {
            throw BundleContainmentError.operationFailed(
                path: sibling.rawValue, component: sibling.rawValue, code: EXDEV
            )
        }
        try withParentDescriptor(
            of: toComponents,
            createIntermediates: false,
            path: sibling
        ) { parent in
            guard renameat(parent, fromComponents.last!, parent, toComponents.last!) == 0 else {
                throw BundleContainmentError.operationFailed(
                    path: sibling.rawValue, component: toComponents.last!, code: errno
                )
            }
        }
    }

    /// Hands `body` a descriptor for the file at `path`, opened `O_NOFOLLOW` under its
    /// walked parent — the door Plan 011's reads (preview, hash verification) use rather
    /// than re-resolving a path.
    public func withReadDescriptor<T>(
        at path: RelativeProjectPath,
        _ body: (Int32) throws -> T
    ) throws -> T {
        let components = Self.components(of: path)
        let leaf = components[components.count - 1]
        let value = try withParentDescriptor(
            of: components,
            createIntermediates: false,
            path: path
        ) { parent -> T in
            let descriptor = openat(parent, leaf, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else {
                throw Self.walkError(
                    code: errno, parent: parent, path: path.rawValue, component: leaf
                )
            }
            defer { close(descriptor) }
            return try body(descriptor)
        }
        // `allowMissingParent` is false above, so the walk either threw or ran the body.
        guard let value else {
            throw BundleContainmentError.missingComponent(
                path: path.rawValue, component: components[0]
            )
        }
        return value
    }

    // MARK: - The walk

    /// Opens the bundle root once, walks every component but the last with
    /// `O_NOFOLLOW | O_DIRECTORY`, and runs `body` against the parent descriptor.
    ///
    /// Returns `nil` only when `allowMissingParent` is set and an intermediate directory
    /// does not exist — "nothing is there" rather than a refusal.
    @discardableResult
    private func withParentDescriptor<T>(
        of components: [String],
        createIntermediates: Bool,
        path: RelativeProjectPath,
        allowMissingParent: Bool = false,
        _ body: (Int32) throws -> T
    ) throws -> T? {
        // The root is opened by path — it is the boundary itself, and the user reached the
        // bundle through it. Every component *inside* is walked no-follow from here.
        let root = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard root >= 0 else {
            throw BundleContainmentError.unopenableRoot(path: rootURL.path, code: errno)
        }
        var parent = root
        defer { close(parent) }

        for component in components.dropLast() {
            var next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0 {
                let code = errno
                if code == ENOENT, createIntermediates {
                    guard mkdirat(parent, component, 0o755) == 0 || errno == EEXIST else {
                        throw BundleContainmentError.operationFailed(
                            path: path.rawValue, component: component, code: errno
                        )
                    }
                    next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                if next < 0 {
                    let code = errno
                    if code == ENOENT, allowMissingParent {
                        return nil
                    }
                    throw Self.walkError(
                        code: code, parent: parent, path: path.rawValue, component: component
                    )
                }
            }
            close(parent)
            parent = next
        }
        return try body(parent)
    }

    /// `fstatat(… AT_SYMLINK_NOFOLLOW)` on the leaf: `nil` when it is not there, a refusal
    /// when it is a symlink, its status otherwise.
    private static func leafStat(
        parent: Int32,
        leaf: String,
        path: RelativeProjectPath
    ) throws -> stat? {
        var status = stat()
        guard fstatat(parent, leaf, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            let code = errno
            if code == ENOENT { return nil }
            throw BundleContainmentError.operationFailed(
                path: path.rawValue, component: leaf, code: code
            )
        }
        guard (status.st_mode & S_IFMT) != S_IFLNK else {
            throw BundleContainmentError.symlinkedComponent(path: path.rawValue, component: leaf)
        }
        return status
    }

    /// `errno` as the refusal it means.
    ///
    /// The refusal has already happened by the time this runs — the `openat` failed — so
    /// this only classifies it. `ELOOP` is unambiguous, but Darwin reports
    /// `O_DIRECTORY | O_NOFOLLOW` over a **symlink to a directory** as `ENOTDIR`, which is
    /// also what a plain file yields; the two are told apart with an
    /// `fstatat(AT_SYMLINK_NOFOLLOW)` against the same pinned parent descriptor, so the
    /// message can name a planted link as one. That stat re-traverses nothing: it is
    /// descriptor-relative like everything else here, and it never gates the operation.
    private static func walkError(
        code: Int32,
        parent: Int32,
        path: String,
        component: String
    ) -> BundleContainmentError {
        if code == ELOOP { return .symlinkedComponent(path: path, component: component) }
        if code == ENOTDIR {
            var status = stat()
            let isLink = fstatat(parent, component, &status, AT_SYMLINK_NOFOLLOW) == 0
                && (status.st_mode & S_IFMT) == S_IFLNK
            return isLink
                ? .symlinkedComponent(path: path, component: component)
                : .notADirectory(path: path, component: component)
        }
        if code == ENOENT { return .missingComponent(path: path, component: component) }
        return .operationFailed(path: path, component: component, code: code)
    }

    /// `RelativeProjectPath` has already rejected `..`, `.`, empty components, and absolute
    /// paths, so splitting is all that is left to do.
    private static func components(of path: RelativeProjectPath) -> [String] {
        path.rawValue.split(separator: "/").map(String.init)
    }
}
