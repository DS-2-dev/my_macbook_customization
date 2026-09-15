import NotchKit
import SwiftUI

/// Every value worth tuning, in one place.
enum NotchStyle {
    // MARK: Panel

    /// The panel is always this big and never resizes; only its content
    /// animates inside it. It has to hold the fully expanded state.
    static let canvas = CGSize(width: 480, height: 220)

    // MARK: Colour

    /// True black, never a material: anything that has to read as part of the
    /// hardware notch must match the bezel exactly.
    static let bezel = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.66)
    static let tertiaryText = Color.white.opacity(0.45)

    // MARK: Resting state

    /// Which side of the notch the resting state reaches out of. The art
    /// stays on this side when the panel expands.
    static let wingSide: NotchGeometry.Side = .trailing
    /// How far past the notch it reaches.
    static let wingWidth: CGFloat = 32
    /// The wing's outer bottom corner.
    static let wingCornerRadius: CGFloat = 10
    /// The concave curve where the wing's outer edge meets the top of the
    /// screen, so it flares into the bezel like the hardware does. 0 for square.
    static let shoulderRadius: CGFloat = 6

    /// The album art in the wing. 22 in a 32-tall notch and a 32-wide wing
    /// leaves 5pt of black all round.
    static let restingArtSize: CGFloat = 22
    static let restingArtCornerRadius: CGFloat = 4

    // MARK: Expanded state

    /// The whole expanded surface, including the strip hidden behind the notch.
    static let expandedSize = CGSize(width: 380, height: 132)
    static let expandedCornerRadius: CGFloat = 24
    static let expandedShoulderRadius: CGFloat = 8
    /// Inset from the surface's edges, below the notch.
    static let contentPadding: CGFloat = 14
    static let expandedArtSize: CGFloat = 72
    static let expandedArtCornerRadius: CGFloat = 8
    /// Between the art and the text.
    static let textGap: CGFloat = 14
    static let lineSpacing: CGFloat = 2

    static let statusFont = Font.system(size: 11, weight: .medium)
    static let titleFont = Font.system(size: 15, weight: .semibold)
    static let artistFont = Font.system(size: 13, weight: .regular)

    // MARK: Motion

    // Opening: out to the full width at the notch's height, then down, then
    // the text. Each step starts before the last has settled, so the three
    // read as one motion.

    /// Widening: quick and flat.
    static let widenSpring = Animation.spring(response: 0.3, dampingFraction: 0.88)
    /// After the widening starts, how long until the panel drops.
    static let dropDelay: TimeInterval = 0.14
    /// Dropping: the one flourish, with a little overshoot.
    static let dropSpring = Animation.spring(response: 0.42, dampingFraction: 0.74)
    /// After the drop starts, how long until the text comes in.
    static let textInDelay: TimeInterval = 0.12
    static let textIn = Animation.easeOut(duration: 0.2)

    // Closing: the same steps backwards, with the text gone first.

    static let textOut = Animation.easeIn(duration: 0.08)
    /// After the text starts fading, how long until the panel lifts.
    static let liftDelay: TimeInterval = 0.06
    static let liftSpring = Animation.spring(response: 0.28, dampingFraction: 0.95)
    /// After the lift starts, how long until it narrows back into the notch.
    static let narrowDelay: TimeInterval = 0.12
    static let narrowSpring = Animation.spring(response: 0.28, dampingFraction: 0.95)

    /// Sliding out of the notch when something starts playing, back in when
    /// nothing has for a while, and a new track arriving.
    static let appearSpring = Animation.spring(response: 0.45, dampingFraction: 0.86)

    // Changing track, the way the card on the site does it: the new art is
    // fetched first, the old art and words fade out with a little blur, the
    // new ones go in while nothing shows, and they fade back in.

    static let swapOut = Animation.easeIn(duration: 0.18)
    static let swapOutDuration: TimeInterval = 0.18
    static let swapIn = Animation.easeOut(duration: 0.32)
    static let swapBlur: CGFloat = 6
    /// How far the words drop as they go.
    static let swapDrop: CGFloat = 3
    /// How long a change waits for new art before going ahead without it.
    static let artPatience: Duration = .milliseconds(1500)

    // MARK: Playing bars

    /// The three bars before "Listening now", as on dantesmith.studio: 2pt
    /// wide and 2pt apart, each growing from 30% to full height and back,
    /// 0.9s each way, a third of a cycle apart. Only while playing.
    static let barWidth: CGFloat = 2
    static let barGap: CGFloat = 2
    /// The site's 0.6rem beside 12px type, scaled to the 11pt status line.
    static let barHeight: CGFloat = 9
    static let barMinScale: CGFloat = 0.3
    static let barPeriod: TimeInterval = 0.9
    static let barDelays: [TimeInterval] = [0, -0.3, -0.6]
    /// Between the bars and "Listening now".
    static let barSpacing: CGFloat = 5

    // MARK: Marquee

    /// A title or artist too long for its line scrolls instead of being cut
    /// off: set twice with a gap and drifting left at one steady pace.
    /// Points per second; the site's card uses 28px.
    static let marqueeSpeed: Double = 30
    /// Between the end of the text and its second copy.
    static let marqueeGap: CGFloat = 40
    /// How long it rests at its start: when it first appears, and again
    /// after every pass, the way Apple Music's titles do.
    static let marqueePause: TimeInterval = 2.0
    /// How long it takes to get up to speed leaving a rest, and to slow
    /// down into the next one.
    static let marqueeRamp: TimeInterval = 0.45
    /// The soft edges: the start only once it's moving, the end always.
    static let marqueeLeadingFade: CGFloat = 10
    static let marqueeTrailingFade: CGFloat = 18

    // MARK: No art

    /// Shown in the wing when a track has no art; the open panel is then
    /// text only.
    static let noArtSymbol = "music.note"
    static let noArtSymbolSize: CGFloat = 12
    /// How long the pointer has to stay before the panel opens or closes, so
    /// sweeping across the top of the screen doesn't set it off.
    static let hoverInDelay: TimeInterval = 0.08
    static let hoverOutDelay: TimeInterval = 0.12

    // MARK: Art

    /// The art slot before its image lands: there straight away, so the text
    /// never has to move over for it.
    static let artPlaceholder = Color.white.opacity(0.08)
    /// The image fading into the slot.
    static let artFade = Animation.easeOut(duration: 0.3)

    // MARK: No notch

    /// Stand-in for the notch on a display without one.
    static let pillSize = CGSize(width: 180, height: 32)
    /// Space between the menu bar and the pill.
    static let pillGap: CGFloat = 6

    // MARK: Debugging

    /// A faint outline of the whole panel, to see its reach.
    static let showsPanelBounds = false
}
