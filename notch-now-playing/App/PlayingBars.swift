import SwiftUI

/// Three bars that move while a track is playing, the way the listening card
/// on dantesmith.studio does it: CSS `ease-in-out`, `alternate`, `infinite`,
/// with the same negative delays so they ripple rather than move together.
/// Drawn only while the panel is open; still with Reduce Motion on.
struct PlayingBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            // Where each bar starts, which staggers them without moving.
            bars(at: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func bars(at time: TimeInterval) -> some View {
        HStack(alignment: .bottom, spacing: NotchStyle.barGap) {
            ForEach(Array(NotchStyle.barDelays.enumerated()), id: \.offset) { _, delay in
                RoundedRectangle(cornerRadius: NotchStyle.barWidth / 2)
                    .frame(width: NotchStyle.barWidth, height: NotchStyle.barHeight)
                    // A negative CSS delay starts the bar partway through.
                    .scaleEffect(x: 1, y: Self.scale(at: time - delay), anchor: .bottom)
            }
        }
        .frame(height: NotchStyle.barHeight)
        .accessibilityHidden(true)
    }

    /// The bar's height, as a fraction of full, `time` seconds in.
    static func scale(at time: TimeInterval) -> CGFloat {
        let cycle = time / NotchStyle.barPeriod
        let pass = cycle.rounded(.down)
        let fraction = cycle - pass
        // `alternate`: forwards on even passes, backwards on odd.
        let progress = pass.truncatingRemainder(dividingBy: 2) == 0 ? fraction : 1 - fraction
        return NotchStyle.barMinScale + (1 - NotchStyle.barMinScale) * easeInOut(progress)
    }

    /// CSS `ease-in-out`, cubic-bezier(0.42, 0, 0.58, 1): solves x(t) = p
    /// for t, then returns y(t).
    private static func easeInOut(_ p: Double) -> Double {
        let (x1, y1, x2, y2) = (0.42, 0.0, 0.58, 1.0)
        func curve(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        func slope(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
        }
        var t = p
        for _ in 0..<6 {
            let dx = slope(t, x1, x2)
            guard abs(dx) > 1e-6 else { break }
            t = min(max(t - (curve(t, x1, x2) - p) / dx, 0), 1)
        }
        return curve(t, y1, y2)
    }
}
