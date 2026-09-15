import Foundation

/// Picks the blocks for each screen from the clock alone, with nothing stored.
///
/// Screens walk an endless sequence made of shuffles of the channel, one
/// shuffle per pass, so every block appears once before any repeats. Each
/// shuffle is seeded from the channel slug and the pass number, so the same
/// screen index always gives the same blocks.
public enum Rotation {
    /// Index of the screen showing at `date` when screens change every `interval`.
    public static func screenIndex(at date: Date, interval: TimeInterval) -> Int {
        Int(date.timeIntervalSince1970 / interval)
    }

    /// FNV-1a of the slug: stable across launches, unlike `hashValue`.
    public static func seed(for slug: String) -> UInt64 {
        slug.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }

    /// Up to `perScreen` distinct ids for screen `index`.
    public static func screen(_ index: Int, of ids: [Int], perScreen: Int, seed: UInt64) -> [Int] {
        guard !ids.isEmpty, perScreen > 0, index >= 0 else { return [] }
        let size = min(perScreen, ids.count)
        var screen: [Int] = []
        var position = index * perScreen
        var pass = -1
        var order: [Int] = []

        while screen.count < size {
            if position / ids.count != pass {
                pass = position / ids.count
                var generator = SplitMix64(state: seed ^ (UInt64(pass) &* 0x9E37_79B9_7F4A_7C15))
                order = ids.shuffled(using: &generator)
            }
            // A screen that straddles two passes can meet a block twice; skip the repeat.
            let id = order[position % ids.count]
            if !screen.contains(id) {
                screen.append(id)
            }
            position += 1
        }
        return screen
    }
}

/// Small seedable generator, so a shuffle can be reproduced from its seed.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
