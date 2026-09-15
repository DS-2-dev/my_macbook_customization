import AppKit
import NotchKit
import OSLog
import SwiftUI

/// Owns the panel, keeps it over the notch as displays come and go, and opens
/// it while the pointer is over it.
@MainActor
final class NotchController {
    private let panel = NotchPanel()
    private let layout = NotchLayout()
    private let content = TrackingView()
    private let feed = NowPlayingFeed()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var monitors: [Any] = []
    private let log = Logger(subsystem: "com.dantesmith.NowPlayingNotch", category: "geometry")

    /// Screen rects the pointer has to be in: the notch and the wing while
    /// collapsed, the whole surface while expanded.
    private var collapsedHotRect: CGRect = .zero
    private var expandedHotRect: CGRect = .zero
    /// A hover change waiting out its delay, and which way it's going.
    private var pendingHover: Task<Void, Never>?
    private var pendingTarget: Bool?

    func start() {
        let host = NSHostingView(rootView: NotchView(layout: layout))
        // The panel's size is fixed by us, not negotiated with SwiftUI.
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        content.addSubview(host)
        content.onPointerChange = { [weak self] in self?.pointerMoved() }
        panel.contentView = content
        host.frame = content.bounds

        relayout()
        panel.orderFrontRegardless()

        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        observe(NotificationCenter.default, NSWindow.didChangeScreenNotification, object: panel)
        // Waking and unlocking can bring displays back in a new arrangement.
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"))

        // Collapsed, the panel lets the mouse through, so only a monitor sees
        // the pointer arrive. Global for when it's over other apps, local for
        // when it's over the panel itself.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) {
            monitors.append(local)
        }

        feed.onUpdate = { [weak self] answer in self?.show(answer) }
        feed.start()
    }

    // MARK: Data

    /// Puts an answer on the notch, or takes it off when nothing has played
    /// recently. How recent is checked on every poll, so an old track ages
    /// out even when the answer itself hasn't changed.
    private func show(_ answer: NowPlaying?) {
        let next = answer.flatMap { $0.isRecent(at: .now, within: NowPlayingFeed.recentWindow) ? $0 : nil }
        guard next != layout.track else { return }
        if next == nil, layout.expanded {
            // Nothing left to show under the pointer: close before going.
            pendingHover?.cancel()
            pendingTarget = nil
            layout.expanded = false
            close()
        }
        let animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : NotchStyle.appearSpring
        withAnimation(animation) { layout.track = next }
        log.notice("showing \(next.map { "\($0.track ?? "?") (\($0.playing ? "playing" : "last played"))" } ?? "nothing", privacy: .public)")
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        observers.append((center, token))
    }

    // MARK: Geometry

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

        let shape = NotchGeometry.rect(metrics.rect, inPanel: frame)
        layout.kind = metrics.kind
        layout.shape = shape

        // Hot zones: the whole notch plus the wing while collapsed, so hovering
        // the hardware notch itself opens it; the surface while expanded.
        var collapsed = shape
        if metrics.kind == .notch {
            collapsed = collapsed.union(NotchGeometry.restingBody(notch: shape, wing: NotchStyle.wingWidth, side: NotchStyle.wingSide))
        }
        let expanded = NotchGeometry.expandedSurface(around: shape, size: NotchStyle.expandedSize)
        collapsedHotRect = reachingTheTopEdge(NotchGeometry.rect(collapsed, fromPanel: frame), of: screen, kind: metrics.kind)
        expandedHotRect = reachingTheTopEdge(NotchGeometry.rect(expanded, fromPanel: frame), of: screen, kind: metrics.kind)
        content.trackedRect = CGRect(x: expanded.minX, y: frame.height - expanded.maxY, width: expanded.width, height: expanded.height)

        log.notice("""
            \(screen.localizedName, privacy: .public) \(metrics.kind == .notch ? "notch" : "pill", privacy: .public) \
            shape=\(NSStringFromRect(metrics.rect), privacy: .public) panel=\(NSStringFromRect(frame), privacy: .public)
            """)
    }

    /// The pointer pinned against the top of the screen can report the very
    /// last row, which a rect ending at the edge doesn't contain.
    private func reachingTheTopEdge(_ rect: CGRect, of screen: NSScreen, kind: NotchMetrics.Kind) -> CGRect {
        guard kind == .notch else { return rect }
        var tall = rect
        tall.size.height += 2
        return tall
    }

    /// The display with a notch if there is one, otherwise the one with the menu bar.
    private static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
            ?? NSScreen.screens.first
    }

    // MARK: Hover

    private func pointerMoved() {
        guard layout.hasSomethingToShow else { return setHovering(false) }
        let hot = layout.expanded ? expandedHotRect : collapsedHotRect
        setHovering(hot.contains(NSEvent.mouseLocation))
    }

    private func setHovering(_ hovering: Bool) {
        if hovering == layout.expanded {
            // Back where it already is: drop any change that was waiting.
            pendingHover?.cancel()
            pendingHover = nil
            pendingTarget = nil
            return
        }
        // Already on its way there; let the delay run.
        guard pendingTarget != hovering else { return }
        pendingHover?.cancel()
        pendingTarget = hovering
        let delay = hovering ? NotchStyle.hoverInDelay : NotchStyle.hoverOutDelay
        pendingHover = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.pendingTarget = nil
            self.layout.expanded = hovering
            hovering ? self.open() : self.close()
            self.log.notice("hover \(hovering ? "open" : "closed", privacy: .public)")
        }
    }

    // MARK: Opening and closing

    /// The steps currently running, cancelled when the pointer changes its mind.
    private var sequence: Task<Void, Never>?

    /// Out to the full width, then down, then the text. A step that's
    /// already done is skipped along with its wait, so coming back in
    /// halfway through a close picks up from wherever it got to.
    private func open() {
        sequence?.cancel()
        // Open, the panel takes the pointer so clicks land on it.
        panel.ignoresMouseEvents = false
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layout.widthOpen = true
            layout.heightOpen = true
            layout.showsDetails = true
            return
        }
        sequence = Task { [weak self] in
            guard let self else { return }
            if !self.layout.widthOpen {
                withAnimation(NotchStyle.widenSpring) { self.layout.widthOpen = true }
                guard await Self.wait(NotchStyle.dropDelay) else { return }
            }
            if !self.layout.heightOpen {
                withAnimation(NotchStyle.dropSpring) { self.layout.heightOpen = true }
                guard await Self.wait(NotchStyle.textInDelay) else { return }
            }
            withAnimation(NotchStyle.textIn) { self.layout.showsDetails = true }
        }
    }

    /// The same backwards, with the text gone before anything moves.
    private func close() {
        sequence?.cancel()
        // Closed, it lets everything through to what's underneath.
        panel.ignoresMouseEvents = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layout.showsDetails = false
            layout.heightOpen = false
            layout.widthOpen = false
            return
        }
        sequence = Task { [weak self] in
            guard let self else { return }
            if self.layout.showsDetails {
                withAnimation(NotchStyle.textOut) { self.layout.showsDetails = false }
                guard await Self.wait(NotchStyle.liftDelay) else { return }
            }
            if self.layout.heightOpen {
                withAnimation(NotchStyle.liftSpring) { self.layout.heightOpen = false }
                guard await Self.wait(NotchStyle.narrowDelay) else { return }
            }
            withAnimation(NotchStyle.narrowSpring) { self.layout.widthOpen = false }
        }
    }

    /// Sleeps; false if the sequence was cancelled meanwhile.
    private static func wait(_ seconds: TimeInterval) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

/// What the views need to know about where they are.
@MainActor
@Observable
final class NotchLayout {
    var kind: NotchMetrics.Kind = .notch
    /// The collapsed shape inside the panel, top-left origin.
    var shape: CGRect = .zero
    /// What's on the notch: the latest answer if it's recent, otherwise nil,
    /// and then nothing is drawn and the notch is left as it is.
    var track: NowPlaying?
    var hasSomethingToShow: Bool { track != nil }
    /// The pointer is over it, so it's opening or open.
    var expanded = false
    /// The steps of opening, each animated in turn by the controller.
    var widthOpen = false
    var heightOpen = false
    var showsDetails = false
}
