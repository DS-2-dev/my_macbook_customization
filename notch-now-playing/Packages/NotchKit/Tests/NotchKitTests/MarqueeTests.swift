import Testing
@testable import NotchKit

@Suite struct MarqueeTests {
    private let speed = 30.0, pause = 2.0, ramp = 0.45

    private func offset(_ elapsed: Double, _ distance: Double) -> Double {
        Marquee.offset(after: elapsed, distance: distance, speed: speed, pause: pause, ramp: ramp)
    }

    @Test func restsAtTheStartFirst() {
        #expect(offset(0, 138) == 0)
        #expect(offset(1.99, 138) == 0)
    }

    @Test func aPassEndsExactlyOneLoopAlong() {
        let distance = 138.0
        let period = Marquee.period(distance: distance, speed: speed, pause: pause, ramp: ramp)
        #expect(abs(offset(period - 1e-9, distance) - distance) < 1e-3)
        // …and the next rest starts from nothing, which looks the same.
        #expect(offset(period + 0.5, distance) == 0)
    }

    @Test(arguments: [138.0, 404.0, 6.0])
    func neverJumps(_ distance: Double) {
        // Sampled at 240fps across three periods: no step is bigger than full
        // speed allows, including where the ramps meet the steady part.
        let period = Marquee.period(distance: distance, speed: speed, pause: pause, ramp: ramp)
        let step = 1.0 / 240
        var previous = offset(0, distance)
        var time = step
        while time < period * 3 {
            let current = offset(time, distance)
            let wrapped = previous > distance * 0.9 && current == 0
            if !wrapped {
                #expect(current >= previous - 1e-9, "went backwards at \(time)")
                #expect(current - previous <= speed * step + 1e-6, "jumped at \(time)")
            }
            previous = current
            time += step
        }
    }

    @Test func reachesFullSpeedInTheMiddle() {
        let distance = 300.0
        let middle = pause + (distance / speed + ramp) / 2
        let moved = offset(middle + 0.01, distance) - offset(middle, distance)
        #expect(abs(moved - speed * 0.01) < 1e-6)
    }

    @Test func startsFromRestAndSettlesIntoRest() {
        let distance = 300.0
        // Barely moving just after leaving the rest.
        #expect(offset(pause + 0.01, distance) < 0.01)
        let period = Marquee.period(distance: distance, speed: speed, pause: pause, ramp: ramp)
        #expect(distance - offset(period - 0.01, distance) < 0.01)
    }
}
