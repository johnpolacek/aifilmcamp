import FilmCore
import Foundation

/// PHASE4_DESIGN §5's readiness state on the window model (Plan 017 contract C).
///
/// The snapshot is read on the standard refresh beat and consumed by the Dashboard
/// section, the Scenes table's readiness column, and the scene detail's Required Assets
/// panel — one read, no view-side derivation (`AGENTS.md`: SwiftUI is presentation only).
/// The surfaces observe the design-pinned area set `[.scenes, .entities, .requirements,
/// .assets]` through the shipped `changes()` consumer; the hub's table→area map already
/// covers every input table, so no new entry exists to add.
extension ProjectWindowModel {
    // MARK: The snapshot

    /// One `readinessGraph` load per refresh — every readiness number on any surface
    /// comes from here, never a second query (§3.3's consistency rule). Storage lives on
    /// the class; this is the read-side accessor.
    var readinessSnapshot: ReadinessSnapshot? { _readinessSnapshot }

    /// Per scene id, for the two scene surfaces.
    func readinessRow(forSceneID id: UUID) -> SceneReadiness? {
        readinessSnapshot?.scenes.first { $0.sceneID == id }
    }

    // MARK: The Scenes-section readiness filter

    /// The Scenes list's readiness filter, a view-model filter in the shipped
    /// `ManifestScopeFilter` style: it narrows the derived rows the table shows. Not a
    /// store query — readiness is derived, never stored (§3.1) — so there is no new read
    /// behind it.
    var sceneReadinessFilter: SceneReadinessFilter { _sceneReadinessFilter }

    func setSceneReadinessFilter(_ filter: SceneReadinessFilter) {
        guard filter != _sceneReadinessFilter else { return }
        _sceneReadinessFilter = filter
    }

    /// §5.3 panel 1's drill-down: navigate to `.scenes` with the readiness filter preset.
    /// Clicking a dashboard state lands the operator on exactly those scenes.
    func showScenesFiltered(by state: SceneReadinessState) async {
        setSceneReadinessFilter(SceneReadinessFilter(matching: state))
        section = .scenes
        await refresh()
    }

    /// Clears the preset (the All scope) when the operator leaves it or asks for everything.
    func clearSceneReadinessFilter() {
        setSceneReadinessFilter(.all)
    }
}

/// The Scenes list's readiness scopes. `.all` shows every listed scene, including the
/// excluded ones with their existing labels in place of a state (§3.4).
enum SceneReadinessFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case assetReady
    case partial
    case blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .assetReady: "Asset Ready"
        case .partial: "Partial"
        case .blocked: "Blocked"
        }
    }

    init(matching state: SceneReadinessState) {
        self = switch state {
        case .assetReady: .assetReady
        case .partial: .partial
        case .blocked: .blocked
        }
    }

    func admits(_ row: SceneReadiness) -> Bool {
        switch self {
        case .all: true
        case .assetReady: !row.isExcluded && row.state == .assetReady
        case .partial: !row.isExcluded && row.state == .partial
        case .blocked: !row.isExcluded && row.state == .blocked
        }
    }
}
