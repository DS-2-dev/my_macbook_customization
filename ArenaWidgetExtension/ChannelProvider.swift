import ArenaKit
import OSLog
import WidgetKit

struct ChannelEntry: TimelineEntry {
    enum Status {
        case loaded
        case placeholder
        case notFound
        case unauthorized
    }

    var date: Date
    var slug: String
    var tiles: [Tile]
    var showTitles: Bool
    var status: Status

    static func placeholder(slug: String = ChannelSlug.fallback) -> ChannelEntry {
        ChannelEntry(date: .now, slug: slug, tiles: [], showTitles: false, status: .placeholder)
    }
}

/// Rotates through every block in the channel. Each timeline deals the next
/// 20 screens from a persistent shuffled deck, one every three minutes, then
/// asks for a new timeline. Scheduled entries don't wake the extension, so the
/// rotation costs about one refresh an hour.
struct ChannelProvider: AppIntentTimelineProvider {
    private static let rotationInterval: TimeInterval = 3 * 60
    private static let screensPerTimeline = 20
    /// When the network is down, rotate what's on disk for this many screens, then retry.
    private static let screensBeforeRetry = 5
    private static let thumbnailLimit = 1000

    private let store = DiskStore.standard
    private let thumbnails = ImageCache.standard
    private let log = Logger(subsystem: "com.dantesmith.ArenaWidget", category: "provider")

    func placeholder(in context: Context) -> ChannelEntry {
        .placeholder()
    }

    func snapshot(for configuration: ChannelConfigurationIntent, in context: Context) async -> ChannelEntry {
        let request = FetchRequest(configuration, context)
        // The gallery calls this, so answer within a few seconds no matter what.
        let entry = await withDeadline(seconds: 4) { try await preview(request) }
        return entry ?? .placeholder(slug: request.slug)
    }

    func timeline(for configuration: ChannelConfigurationIntent, in context: Context) async -> Timeline<ChannelEntry> {
        let request = FetchRequest(configuration, context)
        let auth = TokenStore.load()
        let cached = store.load(ChannelCatalog.self, key: request.catalogKey)

        let catalog: ChannelCatalog
        let online: Bool
        do {
            let loader = CatalogLoader(client: ArenaClient(token: auth.token))
            catalog = try await loader.load(slug: request.slug, cached: cached)
            store.save(catalog, key: request.catalogKey)
            online = true
        } catch {
            log.error("fetch \(request.slug, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            guard let cached else {
                let retry = Date.now.addingTimeInterval(Self.rotationInterval * Double(Self.screensBeforeRetry))
                return Timeline(entries: [request.entry(status: Self.status(for: error))], policy: .after(retry))
            }
            // Stale beats broken: keep rotating through what's already on disk.
            catalog = cached
            online = false
        }

        var generator = SystemRandomNumberGenerator()
        var deck = store.load(Deck.self, key: request.deckKey) ?? Deck()
        let drawable = online ? catalog.blocks : catalog.blocks.filter {
            !$0.hasImage || thumbnails.contains(blockID: $0.id, pixelSize: request.pixelSize)
        }
        deck.sync(with: drawable.map(\.id), using: &generator)
        let screens = deck.deal(
            screens: online ? Self.screensPerTimeline : Self.screensBeforeRetry,
            perScreen: request.grid.count,
            using: &generator
        )
        // Offline the deck was synced to a subset; don't let that drop blocks for good.
        if online {
            store.save(deck, key: request.deckKey)
        }

        let tiles = await tiles(for: screens, in: catalog, request: request, allowDownloads: online)
        thumbnails.prune(keeping: Self.thumbnailLimit)
        log.notice("""
            timeline \(request.slug, privacy: .public) \(request.grid.columns)x\(request.grid.rows) \
            blocks=\(catalog.blocks.count) screens=\(screens.count) tiles=\(tiles.count) \
            px=\(Int(request.pixelSize.width))x\(Int(request.pixelSize.height)) online=\(online) \
            auth=\(auth.logDescription, privacy: .public) \
            peakMB=\(Diagnostics.peakFootprintMB(), format: .fixed(precision: 1))
            """)

        let entries = request.entries(screens.map { $0.compactMap { tiles[$0] } }, interval: Self.rotationInterval)
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// One random screen, preferring what's on disk; used for the gallery preview.
    private func preview(_ request: FetchRequest) async throws -> ChannelEntry {
        let catalog: ChannelCatalog
        if let cached = store.load(ChannelCatalog.self, key: request.catalogKey) {
            catalog = cached
        } else {
            let loader = CatalogLoader(client: ArenaClient(token: TokenStore.load().token))
            catalog = try await loader.load(slug: request.slug, cached: nil)
            store.save(catalog, key: request.catalogKey)
        }
        let picks = Array(catalog.blocks.shuffled().prefix(request.grid.count))
        let tiles = await TileMaker(cache: thumbnails).tiles(for: picks, pixelSize: request.pixelSize, allowDownloads: true)
        return request.entries([picks.compactMap { tiles[$0.id] }], interval: 0)[0]
    }

    private func tiles(
        for screens: [[Int]],
        in catalog: ChannelCatalog,
        request: FetchRequest,
        allowDownloads: Bool
    ) async -> [Int: Tile] {
        let blocks = Dictionary(catalog.blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Int>()
        let needed = screens.joined().filter { seen.insert($0).inserted }.compactMap { blocks[$0] }
        return await TileMaker(cache: thumbnails).tiles(for: needed, pixelSize: request.pixelSize, allowDownloads: allowDownloads)
    }

    private static func status(for error: any Error) -> ChannelEntry.Status {
        switch error as? ArenaError {
        case .notFound: .notFound
        case .unauthorized: .unauthorized
        default: .placeholder
        }
    }
}

private struct FetchRequest {
    let slug: String
    let showTitles: Bool
    let grid: GridSpec
    let pixelSize: CGSize

    init(_ configuration: ChannelConfigurationIntent, _ context: TimelineProviderContext) {
        slug = configuration.slug
        showTitles = configuration.showTitles
        grid = GridSpec(context.family)
        pixelSize = grid.pixelSize(for: context.displaySize)
    }

    var catalogKey: String { "catalog-\(slug)" }
    var deckKey: String { "deck-\(slug)-\(grid.columns)x\(grid.rows)" }

    /// One entry per screen, `interval` apart, starting now.
    func entries(_ screens: [[Tile]], interval: TimeInterval) -> [ChannelEntry] {
        guard !screens.isEmpty else {
            return [ChannelEntry(date: .now, slug: slug, tiles: [], showTitles: showTitles, status: .loaded)]
        }
        let start = Date.now
        return screens.enumerated().map { index, tiles in
            ChannelEntry(
                date: start.addingTimeInterval(interval * Double(index)),
                slug: slug,
                tiles: tiles,
                showTitles: showTitles,
                status: .loaded
            )
        }
    }

    func entry(status: ChannelEntry.Status) -> ChannelEntry {
        ChannelEntry(date: .now, slug: slug, tiles: [], showTitles: showTitles, status: status)
    }
}

private extension TokenStore.State {
    var logDescription: String {
        switch self {
        case .missing: "none"
        case .saved: "token"
        case .inaccessible: "inaccessible"
        }
    }
}

/// Runs `operation`, giving up with `nil` after `seconds`.
private func withDeadline<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { try? await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
