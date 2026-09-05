import Foundation

/// PHASE5_DESIGN §3.8/§5.3's export doors (Plan 020), on `ProjectSession`.
///
/// Export is **not** an `EditOperation`: it writes no canonical row, appears in no
/// journal, and is not undoable (§3.8) — so these doors are plain reads-plus-writes, not
/// `runEdit` material. The exporter itself is staged-verified-atomic and deterministic to
/// the byte (§3.8); the UI reaches it only through these doors — never constructed ad hoc.
public extension ProjectSession {
    /// One scene. A stale single-scene export is permitted only through the §14.7 confirm,
    /// which names the stale reason verbatim from the refusal; without it the refusal
    /// carries the reason so the confirm copy can quote it (`scenePackageStaleExportRequiresConfirm`).
    @discardableResult
    func exportScenePackage(
        sceneID: UUID, confirmingStaleReason: String? = nil
    ) throws -> ScenePackageExport {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try ScenePackageExporter(database: database, bundleURL: bundleURL)
            .exportScene(sceneID: sceneID, confirmingStaleReason: confirmingStaleReason)
    }

    /// Every Generation Ready scene of one sequence, ordinal order (§5.3's Export
    /// Sequence grain). Batch grains skip non-ready scenes rather than refusing.
    @discardableResult
    func exportSequencePackages(sequenceID: UUID) throws -> [ScenePackageExport] {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try ScenePackageExporter(database: database, bundleURL: bundleURL)
            .exportSequence(sequenceID: sequenceID)
    }

    /// Every Generation Ready scene under the active profile P (§5.3's Export All
    /// Generation Ready grain). Batch grains skip non-ready scenes rather than refusing.
    @discardableResult
    func exportAllGenerationReadyPackages() throws -> [ScenePackageExport] {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try ScenePackageExporter(database: database, bundleURL: bundleURL)
            .exportAllGenerationReady()
    }


    /// Exact, card-local numbered files for Reveal Images and multi-file dragging.
    func materializeScenePromptCardReferences(
        cardID: UUID
    ) throws -> ScenePromptCardMaterialization {
        guard let database else { throw ProjectStoreError.sessionClosed }
        return try ScenePackageExporter(database: database, bundleURL: bundleURL)
            .materializeCardReferences(cardID: cardID)
    }
}
