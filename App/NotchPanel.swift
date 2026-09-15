import AppKit

/// The borderless panel every notch app draws with: above the menu bar, on
/// every Space and over full-screen apps, never taking focus.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the menu bar. Not `isFloatingPanel`: setting that quietly
        // drops the level back to .floating, underneath the menu bar.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        // The panel is much bigger than what it draws; until something in it
        // wants the pointer, clicks go through to whatever is underneath.
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit nudges windows down out of the menu bar; this one belongs in it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
