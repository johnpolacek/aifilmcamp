import SwiftUI

/// The one `Commands` block of contract C.
///
/// Window-scoped items route to the **frontmost** project window through
/// `@FocusedValue(\.projectWindow)` and are disabled when there is none. The Entity menu is
/// its own `Commands` block (`EntityCommands`); there is no AI action anywhere.
struct AppCommands: Commands {
    let coordinator: AppCoordinator

    @FocusedValue(\.projectWindow) private var project: ProjectWindowModel?

    var body: some Commands {
        // `WindowGroup` would otherwise contribute its own New Window ⌘N.
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                Task { await coordinator.createProject() }
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Empty Project…") {
                Task { await coordinator.createEmptyProject() }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open…") {
                Task { await coordinator.openProject() }
            }
            .keyboardShortcut("o", modifiers: .command)

            // Without `DocumentGroup` there is no automatic Open Recent, and
            // `NSDocumentController.recentDocumentURLs` is not observable — so the menu is
            // built from the coordinator's mirror.
            Menu("Open Recent") {
                ForEach(coordinator.recentURLs, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) {
                        Task { await coordinator.open(url: url) }
                    }
                }
                Divider()
                Button("Clear Menu") { coordinator.clearRecentDocuments() }
                    .disabled(coordinator.recentURLs.isEmpty)
            }
        }

        CommandGroup(after: .newItem) {
            Divider()

            Button("Import Screenplay…") {
                guard let project else { return }
                Task {
                    guard let url = await coordinator.services.panels.screenplayToImport() else { return }
                    await project.importScreenplay(from: url)
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(project == nil || project?.isImporting == true)

            Button("Add Scenes…") {
                project?.presentedSheet = .addScenes
            }
            .disabled(project?.canAddScenes != true)

            Button("Reveal in Finder") {
                guard let project else { return }
                coordinator.reveal(project.bundleURL)
            }
            .disabled(project == nil)

            Divider()

            Button("Delete Project…") {
                project?.requestDeleteProject()
            }
            .disabled(project == nil)

            Divider()
            // Close ⌘W is AppKit's own File-menu item for the frontmost window.
        }

        // §3.8 requires Edit ▸ Undo / Redo to **show the action name**, and SwiftUI's
        // stock items do not: they are titled a bare "Undo" / "Redo" whatever the
        // manager's `setActionName` says. So they are replaced by items that read
        // `undoMenuItemTitle` / `redoMenuItemTitle` off the frontmost window's
        // `ProjectUndoManager` — which is still the manager AppKit resolves through
        // `ProjectWindowDelegate.windowWillReturnUndoManager(_:)`, and still the one
        // SwiftUI's `@Environment(\.undoManager)` sees.
        //
        // The titles come from an **observable mirror** on the window model:
        // `UndoManager` is not `@Observable`, so a body reading it directly would render
        // once and never update. Both items are disabled while an inverse applies, so a
        // second ⌘Z cannot race the first; `ProjectUndoManager.undo()` refuses as well,
        // for any path that does not come through here.
        CommandGroup(replacing: .undoRedo) {
            Button(project?.undoMenu.undoTitle ?? "Undo") {
                project?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(project?.undoMenu.canUndo != true)

            Button(project?.undoMenu.redoTitle ?? "Redo") {
                project?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(project?.undoMenu.canRedo != true)
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            // §3.11: the edit journal is a **sheet**, not a sidebar section.
            Button("Show Edit Journal…") {
                project?.presentedSheet = .journal
            }
            .disabled(project == nil)

            // Entity ▸ Delete is the entity command and owns ⌫; AppKit's own Edit ▸
            // Delete stays where SwiftUI put it. Two items cannot share one key
            // equivalent, and a second item titled "Delete" in the same menu would only
            // read as a duplicate.
        }

        // Plan 023: the scene rail is the only primary navigation surface. The legacy
        // section shortcuts are intentionally absent; correction actions are contextual.
        SidebarCommands()
        CommandGroup(after: .sidebar) {
            Button("Scene Workspace") { project?.section = .scenes }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(project == nil)
        }
    }
}
