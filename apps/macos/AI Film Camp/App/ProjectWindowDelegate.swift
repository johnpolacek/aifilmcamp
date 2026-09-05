import AppKit
import SwiftUI

/// The single AppKit bridge per project window (contract A, §3.11).
///
/// SwiftUI installs its own `NSWindowDelegate` on every scene window; replacing it outright
/// breaks window-group membership, `dismissWindow`, and restoration. So this delegate keeps
/// SwiftUI's as `next` and forwards everything it does not implement itself through
/// `responds(to:)` / `forwardingTarget(for:)`.
///
/// Plan 005 adds `windowWillReturnUndoManager(_:)` here rather than installing a second
/// delegate.
@MainActor
final class ProjectWindowDelegate: NSObject, NSWindowDelegate {
    /// The delegate SwiftUI installed. Held **strongly**: `NSWindow.delegate` is a weak
    /// reference, and this object is owned by the coordinator rather than by the window,
    /// so nothing else guarantees SwiftUI's delegate outlives the swap. There is no cycle —
    /// SwiftUI's delegate has no reference back to this one.
    ///
    /// `nonisolated(unsafe)` so the two `NSObject` forwarding overrides, which are not
    /// main-actor isolated, can read it. Every access is on the main thread.
    private nonisolated(unsafe) let next: (any NSWindowDelegate)?

    /// The model this window currently shows.
    var model: ProjectWindowModel?

    private let onWillClose: @MainActor (ProjectWindowModel) -> Void

    init(
        next: (any NSWindowDelegate)?,
        model: ProjectWindowModel?,
        onWillClose: @escaping @MainActor (ProjectWindowModel) -> Void
    ) {
        self.next = next
        self.model = model
        self.onWillClose = onWillClose
    }

    func windowWillClose(_ notification: Notification) {
        if let model {
            self.model = nil
            onWillClose(model)
        }
        next?.windowWillClose?(notification)
    }

    override nonisolated func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return next?.responds(to: aSelector) ?? false
    }

    override nonisolated func forwardingTarget(for aSelector: Selector!) -> Any? {
        guard let next, next.responds(to: aSelector) else { return nil }
        return next
    }
}

/// The host that hands a SwiftUI scene its `NSWindow`.
///
/// `NSWindow` is reachable only from AppKit, and SwiftUI's `.accessibilityIdentifier` names
/// a view, never a window — so the window identifiers the UI tests scope their queries to
/// (`welcomeWindow` / `projectWindow`) are set here.
struct WindowBridge: NSViewRepresentable {
    let accessibilityIdentifier: String
    /// Called once the view is in a window, and again if it moves to another one.
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowCaptureView {
        WindowCaptureView(accessibilityIdentifier: accessibilityIdentifier, onWindow: onWindow)
    }

    func updateNSView(_ nsView: WindowCaptureView, context: Context) {}
}

final class WindowCaptureView: NSView {
    private let windowAccessibilityIdentifier: String
    private let onWindow: @MainActor (NSWindow) -> Void

    init(accessibilityIdentifier: String, onWindow: @escaping @MainActor (NSWindow) -> Void) {
        self.windowAccessibilityIdentifier = accessibilityIdentifier
        self.onWindow = onWindow
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.setAccessibilityIdentifier(windowAccessibilityIdentifier)
        if windowAccessibilityIdentifier == "projectWindow" {
            Self.applyAutomationWindowFrameIfRequested(to: window)
        }
        onWindow(window)
    }

    /// Automation-only: `FILMCAMP_AUTOMATION_WINDOW_FRAME=X,Y,W,H` sizes a project window
    /// at birth, so a suite that needs a wide split view — sidebar, manifest header, and
    /// inspector side by side — gets one. It travels in the launch **environment**, not the
    /// argument list: bare numeric tokens there are treated by AppKit as documents to open,
    /// which wedges the app before its first window idles. Production never sets it.
    private static func applyAutomationWindowFrameIfRequested(to window: NSWindow) {
        guard
            let spec = ProcessInfo.processInfo.environment["FILMCAMP_AUTOMATION_WINDOW_FRAME"]
        else { return }
        let values = spec.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return }
        // Deferred: resizing during scene presentation breaks the Welcome flow.
        DispatchQueue.main.async {
            window.setFrame(
                NSRect(
                    x: values[0], y: values[1], width: values[2], height: values[3]
                ),
                display: true
            )
        }
    }
}
