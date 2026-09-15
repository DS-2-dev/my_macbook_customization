import AppKit

/// The panel's content view: hosts the SwiftUI view and tells the controller
/// when the pointer enters, leaves or moves over the expanded surface.
///
/// A tracking area only sees the pointer while the panel takes mouse events,
/// and the panel only does that once it's expanded; the controller's event
/// monitors cover the collapsed state and the top edge of the screen, where
/// tracking areas on borderless panels are known to miss.
final class TrackingView: NSView {
    var onPointerChange: (() -> Void)?

    /// In this view's own coordinates (origin bottom-left).
    var trackedRect: CGRect = .zero {
        didSet {
            if trackedRect != oldValue { updateTrackingAreas() }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard !trackedRect.isEmpty else { return }
        addTrackingArea(NSTrackingArea(
            rect: trackedRect,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onPointerChange?() }
    override func mouseExited(with event: NSEvent) { onPointerChange?() }
    override func mouseMoved(with event: NSEvent) { onPointerChange?() }
}
