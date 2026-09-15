import AppKit
import NotchKit
import OSLog
import SwiftUI

/// Owns the panel and keeps it over the notch as displays come and go.
@MainActor
final class NotchController {
    private let panel = NotchPanel()
    private let layout = NotchLayout()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let log = Logger(subsystem: "com.dantesmith.NowPlayingNotch", category: "geometry")

    func start() {
        let host = NSHostingView(rootView: NotchView(layout: layout))
        // The panel's size is fixed by us, not negotiated with SwiftUI.
        host.sizingOptions = []
        panel.contentView = host

        relayout()
        panel.orderFrontRegardless()

        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        observe(NotificationCenter.default, NSWindow.didChangeScreenNotification, object: panel)
        // Waking and unlocking can bring displays back in a new arrangement.
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"))
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        observers.append((center, token))
    }

    private func relayout() {
        guard let screen = Self.preferredScreen() else {
            log.notice("no screen; hiding")
            panel.orderOut(nil)
            return
        }
        let metrics = NotchGeometry.metrics(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeft: screen.auxiliaryTopLeftArea,
            auxiliaryRight: screen.auxiliaryTopRightArea,
            pillSize: NotchStyle.pillSize,
            pillGap: NotchStyle.pillGap
        )
        let frame = NotchGeometry.panelFrame(for: metrics, canvas: NotchStyle.canvas)
        panel.setFrame(frame, display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        layout.kind = metrics.kind
        layout.shape = NotchGeometry.rect(metrics.rect, inPanel: frame)
        log.notice("""
            \(screen.localizedName, privacy: .public) \(metrics.kind == .notch ? "notch" : "pill", privacy: .public) \
            shape=\(NSStringFromRect(metrics.rect), privacy: .public) panel=\(NSStringFromRect(frame), privacy: .public)
            """)
    }

    /// The display with a notch if there is one, otherwise the one with the menu bar.
    private static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
            ?? NSScreen.screens.first
    }
}

/// What the views need to know about where they are.
@MainActor
@Observable
final class NotchLayout {
    var kind: NotchMetrics.Kind = .notch
    /// The collapsed shape inside the panel, top-left origin.
    var shape: CGRect = .zero
}
