import CoreGraphics

/// Every value worth tuning, in one place.
enum NotchStyle {
    /// The panel is always this big and never resizes; only its content
    /// animates inside it. It has to hold the fully expanded state.
    static let canvas = CGSize(width: 480, height: 220)

    /// Stand-in for the notch on a display without one.
    static let pillSize = CGSize(width: 180, height: 32)
    /// Space between the menu bar and the pill.
    static let pillGap: CGFloat = 6

    /// Milestone 1: a faint outline of the whole panel, to see its reach.
    static let showsPanelBounds = true
}
