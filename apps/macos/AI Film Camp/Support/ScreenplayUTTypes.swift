import UniformTypeIdentifiers

/// The two screenplay types the app **imports** (Plan 004 contract E).
///
/// Both are declared under `UTImportedTypeDeclarations` in `Info.plist` and appear in no
/// `CFBundleDocumentTypes` entry: the app opens `.aifilm` projects, never screenplays.
/// `UTType(importedAs:)` traps when the declaration is missing, which is why the
/// regenerated `Info.plist` is committed alongside `project.yml`.
///
/// The open panel and the drop destination (Plan 004 Step 2/3) filter on file extensions
/// rather than on these types alone — an installed screenwriting app's *exported*
/// declaration outranks ours and would grey the file out.
extension UTType {
    static let fountainScreenplay = UTType(importedAs: "com.aifilmcamp.fountain")
    static let finalDraftScreenplay = UTType(importedAs: "com.finaldraft.fdx")
}
