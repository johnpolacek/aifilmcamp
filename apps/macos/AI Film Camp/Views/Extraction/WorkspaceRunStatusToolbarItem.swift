import SwiftUI

/// One toolbar status/cancel surface for every explicitly started preparation or prompt
/// run. Detailed completion reports remain in their existing sheets.
struct WorkspaceRunStatusToolbarItem: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        Menu {
            Text(model.workspaceRunMessage)
            Divider()
            Button("Cancel Run", role: .destructive) {
                Task { await model.cancelWorkspaceRun() }
            }
            .disabled(model.activeReferenceImageJobIsCommitting)
            .accessibilityIdentifier("workspaceRun.cancel")
        } label: {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(model.workspaceRunMessage).lineLimit(1)
            }
        }
        .accessibilityIdentifier("workspaceRun.status")
        .accessibilityLabel("Run status: \(model.workspaceRunMessage)")
    }
}
