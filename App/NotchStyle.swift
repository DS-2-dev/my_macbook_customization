import NotchKit
import SwiftUI

/// Every value worth tuning, in one place.
enum NotchStyle {
    // MARK: Panel

    /// The panel is always this big and never resizes; only its content
    /// animates inside it. It has to hold the fully expanded state.
    static let canvas = CGSize(width: 480, height: 220)

    // MARK: Resting state

    /// True black, never a material: anything that has to read as part of the
    /// hardware notch must match the bezel exactly.
    static let bezel = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)

    /// Which side of the notch the resting state reaches out of.
    static let wingSide: NotchGeometry.Side = .trailing
    /// How far past the notch it reaches.
    static let wingWidth: CGFloat = 32
    /// The wing's outer bottom corner.
    static let wingCornerRadius: CGFloat = 10
    /// The concave curve where the wing's outer edge meets the top of the
    /// screen, so it flares into the bezel like the hardware does. 0 for square.
    static let shoulderRadius: CGFloat = 6

    /// The indicator in the wing; album art from step 5.
    /// 22 in a 32-tall notch and a 32-wide wing leaves 5pt of black all round.
    static let indicatorSize = CGSize(width: 22, height: 22)
    static let indicatorCornerRadius: CGFloat = 5
    /// Until there's real art, something to see.
    static let placeholderArt = LinearGradient(
        colors: [Color(red: 0.95, green: 0.55, blue: 0.35), Color(red: 0.55, green: 0.25, blue: 0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: No notch

    /// Stand-in for the notch on a display without one.
    static let pillSize = CGSize(width: 180, height: 32)
    /// Space between the menu bar and the pill.
    static let pillGap: CGFloat = 6

    // MARK: Debugging

    /// A faint outline of the whole panel, to see its reach.
    static let showsPanelBounds = false
}
