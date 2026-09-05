import AppKit
import FilmCore
import SwiftUI

/// §3.11's Jobs section: **runs** only, one row each, expandable to their chunk rows, with
/// the read-only affordances Plan 004 builds — Show Log in Finder and a copyable job UUID.
/// The run card and apply report arrive in Plan 007, so this section is empty until then.
struct RunsListView: View {
    @Bindable var model: ProjectWindowModel
    /// The coordinator's Finder reveal; the view never touches `NSWorkspace` itself.
    let revealInFinder: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Task-agnostic (§7.5): the newest completed run of **either** task, routed
                // through the one `revertRun` door.
                Button("Revert last run…") {
                    Task { await model.revertNewestRunAndPresentReport() }
                }
                .disabled(!model.canRevertLastRun)
                .accessibilityIdentifier("revertLastRunButton")
                Button("Clear Job Cache…") {
                    Task { await model.clearJobCache() }
                }
                .disabled(model.activeExtractionRun != nil)
                .accessibilityIdentifier("clearJobCacheButton")
                // PHASE2_DESIGN §4.1: **next to Clear Job Cache**, and the same shape —
                // it lists what it would remove, confirms, and reports the freed bytes.
                // It journals nothing and touches no row.
                Button("Clear Orphaned Media…") {
                    Task { await model.beginOrphanSweep() }
                }
                .accessibilityIdentifier("clearOrphanedMediaButton")
                .accessibilityLabel("Clear Orphaned Media")
                Spacer()
            }
            .padding(8)
            Divider()
            if model.runs.isEmpty {
                ContentUnavailableView(
                    ProjectSection.jobs.emptyStateText,
                    systemImage: ProjectSection.jobs.systemImage
                )
            } else {
                List(selection: selectionBinding) {
                    ForEach(model.runs) { run in
                        DisclosureGroup {
                            // Childless for an `inferAssetManifest` run (§8.1: one request,
                            // no fan-out), so this renders nothing rather than "0 chunks".
                            ForEach(model.runChildren(of: run)) { child in
                                jobRow(title: model.childRowTitle(child), job: child)
                            }
                            // Whichever report the run's task wrote — extraction's
                            // `applyReport` or §8.5's `manifestReport`.
                            if let line = model.runReportLine(run) {
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("runReportLine")
                                    .accessibilityLabel(line)
                            }
                        } label: {
                            jobRow(title: model.runRowTitle(run), job: run.job)
                        }
                        .tag(run.id)
                        // Identifier lookup over a label sweep: an outline holding a
                        // chunked extraction run is too big a subtree for predicate-based
                        // AX queries to evaluate under automation.
                        .accessibilityIdentifier("runRow_\(run.job.task)")
                    }
                }
                .accessibilityIdentifier("runsList")
                .accessibilityLabel("Analysis runs")
            }
        }
        // §4.1: the sweep **lists** what it would delete and deletes only after the
        // operator confirms. It hangs here, on the section that offers it, because the two
        // dialogs `ProjectSplitView` already hosts occupy their own views' slots.
        .confirmationDialog(
            orphanSweepTitle,
            isPresented: orphanSweepBinding,
            titleVisibility: .visible,
            presenting: model.pendingOrphanSweep
        ) { pending in
            Button("Delete", role: .destructive) {
                Task { await model.performOrphanSweep(pending) }
            }
            .accessibilityIdentifier("confirmClearOrphanedMediaButton")
            Button("Cancel", role: .cancel) { model.cancelPendingOrphanSweep() }
        } message: { pending in
            Text(
                "No version references these files, so nothing in the project points at them:\n"
                    + pending.paths.prefix(10).map(\.rawValue).joined(separator: "\n")
                    + (pending.paths.count > 10 ? "\n… and \(pending.paths.count - 10) more." : "")
            )
        }
    }

    private var orphanSweepTitle: String {
        let count = model.pendingOrphanSweep?.paths.count ?? 0
        return count == 1
            ? "Delete 1 orphaned image file?"
            : "Delete \(count) orphaned image files?"
    }

    private var orphanSweepBinding: Binding<Bool> {
        Binding(
            get: { model.pendingOrphanSweep != nil },
            set: { if !$0 { model.cancelPendingOrphanSweep() } }
        )
    }

    @ViewBuilder
    private func jobRow(title: String, job: Job) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            HStack(spacing: 12) {
                Text(job.id.uuidString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Job identifier \(job.id.uuidString)")
                Button("Copy Job ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(job.id.uuidString, forType: .string)
                }
                .accessibilityIdentifier("copyJobIDButton")
                .accessibilityLabel("Copy Job ID")
                Button("Show Log in Finder") {
                    Task {
                        if let url = await model.logURL(for: job) { revealInFinder(url) }
                    }
                }
                .accessibilityIdentifier("showLogButton")
                .accessibilityLabel("Show Log in Finder")
            }
            .buttonStyle(.link)
        }
    }

    // The row labels, the report line, and the child ordering live on the window model
    // (`ProjectWindowModel+ManifestRun.swift`): they are task-aware rules the headless twins
    // assert, and a rule restated inside a `View` body cannot be tested.

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { model.selection(in: .jobs) },
            set: { model.setSelection($0, in: .jobs) }
        )
    }
}

extension Job.State {
    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .discoveringHarness: "Discovering Harness"
        case .running: "Running"
        case .validating: "Validating"
        case .committing: "Committing"
        case .paused: "Paused"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}
