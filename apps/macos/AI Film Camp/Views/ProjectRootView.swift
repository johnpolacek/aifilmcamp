import SwiftUI

/// The root of a project window: the window lifecycle (restoration adoption, the AppKit
/// bridge, title, subtitle, proxy icon) around §3.11's `NavigationSplitView`.
struct ProjectRootView: View {
    let coordinator: AppCoordinator
    let url: URL?

    var body: some View {
        Group {
            if let url {
                projectBody(url: url)
            } else {
                ContentUnavailableView(
                    "No Project",
                    systemImage: "film",
                    description: Text("This window has no project to show.")
                )
            }
        }
        // The scene-first workspace needs room for its rail and a useful two-card
        // reference grid. `AIFilmCampApp` uses `.contentMinSize`, so this is also the
        // project window's native minimum size rather than just a layout preference.
        .frame(minWidth: 1_100, minHeight: 600)
    }

    @ViewBuilder
    private func projectBody(url: URL) -> some View {
        let model = coordinator.model(for: url)
        Group {
            if let model {
                ProjectSplitView(coordinator: coordinator, model: model)
                    // The frontmost project window is what the File and View menu items
                    // act on; the commands read this back with `@FocusedValue`.
                    .focusedSceneValue(\.projectWindow, model)
                    // Undo (Plan 005 §3.8) needs no modifier here: SwiftUI's
                    // `EnvironmentValues.undoManager` is get-only and is resolved from
                    // AppKit's responder chain, which
                    // `ProjectWindowDelegate.windowWillReturnUndoManager(_:)` answers with
                    // `model.undoManager` — the same path the system Edit ▸ Undo / Redo
                    // items validate through.
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            SceneWindowBridge(
                coordinator: coordinator,
                accessibilityIdentifier: "projectWindow"
            ) { window in
                coordinator.attach(window: window, for: url)
            }
        }
        .navigationTitle(model?.title ?? url.deletingPathExtension().lastPathComponent)
        .navigationSubtitle(model?.subtitle ?? "No screenplay")
        .navigationDocument(url)
        // File ▸ Delete Project…'s confirm, hosted on the window it would close. The
        // destructive path runs after dismissal: close session → drop model → dismiss
        // window → Trash the bundle (the Trash is the undo story; nothing hard-deletes).
        .confirmationDialog(
            "Delete “\(model?.title ?? url.deletingPathExtension().lastPathComponent)”?",
            isPresented: Binding(
                get: { model?.pendingProjectDeletion ?? false },
                set: { model?.pendingProjectDeletion = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                Task { await coordinator.deleteProject(for: url) }
            }
            .accessibilityIdentifier("confirmDeleteProjectButton")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project and its files move to the Trash. You can recover them from there.")
        }
        // Restoration: SwiftUI re-presents this window without the coordinator, so the
        // window adopts its own URL through the same inspect → upgrade → open path.
        .task(id: url) {
            await coordinator.adopt(url: url)
        }
    }
}

/// The frontmost project window, for the `Commands` block (contract C).
struct ProjectWindowFocusedValueKey: FocusedValueKey {
    typealias Value = ProjectWindowModel
}

extension FocusedValues {
    var projectWindow: ProjectWindowModel? {
        get { self[ProjectWindowFocusedValueKey.self] }
        set { self[ProjectWindowFocusedValueKey.self] = newValue }
    }
}
