import SwiftUI

struct WelcomeView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                CampSectionLabel("AI Film Camp / Desktop")
                Spacer()
                Image(systemName: "flame")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(CampAppearance.accent)
                    .accessibilityHidden(true)
            }
            Rectangle().fill(CampAppearance.rule).frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                Text("AI FILM CAMP")
                    .font(CampAppearance.title(56))
                    .tracking(-2)
                    .accessibilityAddTraits(.isHeader)
                Text("Prepare your film for generation.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

            HStack(spacing: 16) {
                Button {
                    Task { await coordinator.createProject() }
                } label: {
                    HStack(spacing: 24) {
                        Text("Import Project")
                        Image(systemName: "arrow.up.right")
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(CampPrimaryButtonStyle())
                .accessibilityIdentifier("createProjectButton")
                .accessibilityLabel("Import Project")

                Button("Create Empty Project") { Task { await coordinator.createEmptyProject() } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("createEmptyProjectButton")
                    .accessibilityLabel("Create Empty Project")
            }

            if !coordinator.recentURLs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    CampSectionLabel("Projects")
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(coordinator.recentURLs, id: \.self) { url in
                                Button {
                                    Task { await coordinator.open(url: url) }
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "film.stack")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(url.deletingPathExtension().lastPathComponent)
                                                .font(CampAppearance.title(18))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(CampProjectRowStyle())
                                .accessibilityIdentifier("recentProjectButton")
                                .accessibilityLabel("Open \(url.deletingPathExtension().lastPathComponent)")
                                Rectangle().fill(CampAppearance.rule).frame(height: 1)
                            }
                        }
                    }
                    .frame(maxHeight: 210)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
            Rectangle().fill(CampAppearance.rule).frame(height: 1)
            CodexStatusView(coordinator: coordinator, presentation: .compact)
        }
        .padding(40)
        .frame(minWidth: 720, minHeight: 560, alignment: .topLeading)
        .background(CampAppearance.canvas)
        .background {
            SceneWindowBridge(coordinator: coordinator, accessibilityIdentifier: "welcomeWindow")
        }
        // The v1 modal is hosted here: Welcome is the one scene that exists whether or not a
        // project window is open, and the coordinator reopens it before arming the modal.
        .sheet(item: $coordinator.pendingUpgrade) { pending in
            MigrationUpgradeSheet(
                url: pending.url,
                onCancel: { coordinator.upgradeCancelled() },
                onUpgrade: { Task { await coordinator.upgradeConfirmed(url: pending.url) } }
            )
        }
        .sheet(item: $coordinator.pendingCreation) { pending in
            NewProjectSheet(
                pending: pending,
                onCancel: { coordinator.cancelCreateProject() },
                onCreate: { title in Task { await coordinator.confirmCreateProject(named: title) } }
            )
        }
        .alert(item: $coordinator.error) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }
}

private struct CampProjectRowStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed || isHovered ? CampAppearance.inset : CampAppearance.surface)
            .onHover { isHovered = $0 }
    }
}
