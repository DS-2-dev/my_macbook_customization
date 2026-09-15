import NotchKit
import SwiftUI

/// One line of text that scrolls when it's too long for its line, the way
/// the listening card on dantesmith.studio does it: set twice with a gap and
/// scrolled one pass at a time, so the second copy arrives exactly where the
/// first began and the loop has no seam. Between passes it rests at the
/// start, the way Apple Music's titles do. Text that fits, and anything with
/// Reduce Motion on, stays still; the latter ends in "…".
///
/// The font and colour come from the environment, like a Text's.
struct MarqueeText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The text's natural width on one line.
    @State private var textWidth: CGFloat = 0
    /// When this text appeared; the hold and the scroll are timed from here.
    @State private var appearedAt = Date.now

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // A hidden copy sets the line's height and takes the width offered;
        // the text that's seen is drawn over it.
        Text(text)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    line(width: geometry.size.width)
                }
            }
            .background(alignment: .leading) {
                Text(text)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
            }
            .onChange(of: text) { appearedAt = .now }
            .onAppear { appearedAt = .now }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    @ViewBuilder
    private func line(width: CGFloat) -> some View {
        if textWidth > width + 0.5, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
                let loop = textWidth + NotchStyle.marqueeGap
                let x = CGFloat(Self.offset(after: context.date.timeIntervalSince(appearedAt), loop: Double(loop)))
                HStack(spacing: NotchStyle.marqueeGap) {
                    Text(text)
                    Text(text)
                }
                .fixedSize()
                .offset(x: -x)
                .frame(width: width, alignment: .leading)
                // The leading edge is soft only while the text moves, so it
                // rests with a crisp first letter at the start.
                .mask(edges(width: width, leading: min(NotchStyle.marqueeLeadingFade, x, loop - x)))
            }
        } else {
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width, alignment: .leading)
        }
    }

    /// How far the text has scrolled `elapsed` seconds after appearing:
    /// NotchKit's `Marquee`, with the tunable pace, rest and ramp.
    static func offset(after elapsed: TimeInterval, loop distance: Double) -> Double {
        Marquee.offset(
            after: elapsed,
            distance: distance,
            speed: NotchStyle.marqueeSpeed,
            pause: NotchStyle.marqueePause,
            ramp: NotchStyle.marqueeRamp
        )
    }

    /// Opaque in the middle, fading out over `leading` points at the start
    /// and the trailing fade at the end.
    private func edges(width: CGFloat, leading: CGFloat) -> some View {
        let start = max(0, min(leading / max(width, 1), 0.5))
        let end = max(0.5, 1 - NotchStyle.marqueeTrailingFade / max(width, 1))
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: start),
                .init(color: .black, location: end),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
