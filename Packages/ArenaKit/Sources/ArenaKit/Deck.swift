/// A persistent shuffled order of block ids. Dealing walks the deck and only
/// reshuffles once it runs out, so every block is shown before any repeats.
public struct Deck: Codable, Equatable, Sendable {
    public private(set) var order: [Int] = []
    public private(set) var cursor = 0

    public init() {}

    /// Matches the deck to the channel's current blocks: removed blocks are
    /// dropped, and new ones are shuffled into the part not yet shown.
    public mutating func sync(with ids: [Int], using generator: inout some RandomNumberGenerator) {
        var seen = Set<Int>()
        let unique = ids.filter { seen.insert($0).inserted }
        let known = Set(order)
        let split = min(cursor, order.count)
        let shown = order[..<split].filter(seen.contains)
        let upcoming = order[split...].filter(seen.contains)
        let added = unique.filter { !known.contains($0) }

        order = shown + (added.isEmpty ? upcoming : (upcoming + added).shuffled(using: &generator))
        cursor = shown.count
    }

    /// The next `count` screens of up to `perScreen` distinct ids each.
    public mutating func deal(
        screens count: Int,
        perScreen: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [[Int]] {
        guard !order.isEmpty, perScreen > 0, count > 0 else { return [] }
        let size = min(perScreen, order.count)
        var screens: [[Int]] = []

        for _ in 0..<count {
            var screen: [Int] = []
            while screen.count < size {
                if cursor >= order.count {
                    order.shuffle(using: &generator)
                    cursor = 0
                }
                // Around a reshuffle the next id can already be on this screen;
                // pull the next unused one forward, or start a new pass.
                guard let next = order[cursor...].firstIndex(where: { !screen.contains($0) }) else {
                    cursor = order.count
                    continue
                }
                order.swapAt(cursor, next)
                screen.append(order[cursor])
                cursor += 1
            }
            screens.append(screen)
        }
        return screens
    }
}
