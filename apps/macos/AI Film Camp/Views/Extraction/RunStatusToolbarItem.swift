import SwiftUI

struct RunStatusToolbarItem: View {
    @Bindable var model: ProjectWindowModel
    @State private var showingCard = false

    var body: some View {
        Button { showingCard.toggle() } label: {
            HStack(spacing: 6) {
                if isActive { ProgressView().controlSize(.small) }
                Label(statusText, systemImage: statusImage)
                    .labelStyle(.titleAndIcon)
            }
        }
        .popover(isPresented: $showingCard) {
            RunCardView(model: model)
                .padding(16)
                .frame(width: 420)
        }
        .accessibilityIdentifier("runStatusToolbarItem")
        .accessibilityLabel("Analysis status: \(statusText)")
    }

    private var isActive: Bool {
        guard let stage = model.extractionProgress?.stage else { return false }
        return ![.completed, .failed, .cancelled, .paused].contains(stage)
    }

    private var statusText: String {
        if let progress = model.extractionProgress { return progress.message }
        return model.runs.last?.job.state.displayName ?? "Analyze Screenplay"
    }

    private var statusImage: String {
        switch model.extractionProgress?.stage {
        case .paused: "pause.circle"
        case .failed: "exclamationmark.triangle"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        default: "wand.and.stars"
        }
    }
}
