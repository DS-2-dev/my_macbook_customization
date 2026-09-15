/// The motion of a scrolling line, the way Apple Music's titles move: rest at
/// the start, one pass of `distance`, rest again. A pass eases up to `speed`
/// over `ramp` seconds and down into the next rest the same way. With the
/// text set twice, `distance` is one copy plus the gap, so a pass ends with
/// the second copy exactly where the first began and every rest looks alike.
public enum Marquee {
    /// How far the text has scrolled, `elapsed` seconds after it appeared.
    public static func offset(
        after elapsed: Double,
        distance: Double,
        speed: Double,
        pause: Double,
        ramp maxRamp: Double
    ) -> Double {
        guard distance > 0, speed > 0 else { return 0 }
        // A pass too short to reach full speed eases for half of it each way.
        let ramp = max(0, min(maxRamp, distance / speed))
        // Easing in and out costs half a ramp's worth of distance each end.
        let travel = distance / speed + ramp
        let t = max(0, elapsed).truncatingRemainder(dividingBy: pause + travel) - pause
        guard t > 0 else { return 0 }
        guard ramp > 0 else { return min(distance, speed * t) }
        if t < ramp {
            return speed * t * t / (2 * ramp)
        }
        if t > travel - ramp {
            let left = travel - t
            return distance - speed * left * left / (2 * ramp)
        }
        return speed * ramp / 2 + speed * (t - ramp)
    }

    /// How long one rest and one pass take together.
    public static func period(distance: Double, speed: Double, pause: Double, ramp maxRamp: Double) -> Double {
        let ramp = max(0, min(maxRamp, distance / speed))
        return pause + distance / speed + ramp
    }
}
