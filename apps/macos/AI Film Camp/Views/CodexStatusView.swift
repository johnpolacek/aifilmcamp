import SwiftUI

struct CodexStatusView: View {
    enum Presentation {
        case compact
        case detailed
    }

    let coordinator: AppCoordinator
    var presentation: Presentation = .detailed

    var body: some View {
        switch presentation {
        case .compact:
            HStack(spacing: 7) {
                statusIcon
                Text(coordinator.codexStatusSummaryText)
                    .accessibilityIdentifier("codexStatusLabel")
                    .accessibilityLabel("Codex status")
            }
        case .detailed:
            GroupBox("Codex") {
                HStack(alignment: .top, spacing: 16) {
                    statusIcon
                    Text(coordinator.codexStatusText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("codexStatusLabel")
                        .accessibilityLabel("Codex status")
                    Button("Refresh") { Task { await coordinator.refreshCodex() } }
                        .accessibilityIdentifier("refreshCodexButton")
                        .accessibilityLabel("Refresh Codex Status")
                }
                .padding(4)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if coordinator.isCheckingCodex {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        } else {
            Image(
                systemName: coordinator.isCodexReady
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(coordinator.isCodexReady ? .green : .orange)
            .accessibilityHidden(true)
        }
    }
}
