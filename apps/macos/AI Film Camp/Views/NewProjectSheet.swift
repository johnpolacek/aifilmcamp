import FilmCore
import SwiftUI

/// Step 4 of the screenplay-first Create Project flow: the file is already
/// parsed and validated, and this sheet is where the operator confirms or edits
/// the derived title before any bundle exists.
struct NewProjectSheet: View {
    let pending: AppCoordinator.PendingProjectCreation
    let onCancel: () -> Void
    let onCreate: (String) -> Void

    @State private var title: String
    @FocusState private var titleFocused: Bool

    init(
        pending: AppCoordinator.PendingProjectCreation,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (String) -> Void
    ) {
        self.pending = pending
        self.onCancel = onCancel
        self.onCreate = onCreate
        _title = State(initialValue: pending.preview.suggestedTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Project")
                    .font(.title2.weight(.semibold))
                Text(pending.preview.fileName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Format", value: formatName, identifier: "previewFormat")
                row("Scenes", value: "\(pending.preview.sceneCount)", identifier: "previewSceneCount")
            }

            warnings

            TextField("Project Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onAppear { titleFocused = true }
                .accessibilityIdentifier("projectTitleField")

            Text("The project will be created beside the selected screenplay.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelCreateProjectButton")
                Button("Create") { onCreate(title) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("confirmCreateProjectButton")
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newProjectSheet")
        .accessibilityLabel("New Project")
    }

    private var warnings: some View {
        Group {
            if pending.preview.warnings.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parser Warnings")
                        .font(.headline)
                    ForEach(Array(pending.preview.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var formatName: String {
        switch pending.preview.format {
        case .fountain: "Fountain"
        case .fdx: "Final Draft"
        case .text: "Plain Text"
        case .pdf: "PDF"
        }
    }

    private func row(_ label: String, value: String, identifier: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
        }
    }
}
