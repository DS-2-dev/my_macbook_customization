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

/// Rotates through every block in the channel, a new screen every three
/// minutes. Once an hour it lists the channel, works out the next 20 screens
/// from the clock (see `Rotation`), and downloads just those images. Nothing is
/// written to disk; scheduled entries don't wake the extension, so the
/// rotation costs one refresh an hour.
struct ChannelProvider: AppIntentTimelineProvider {
    private static let rotationInterval: TimeInterval = 3 * 60
    private static let screensPerTimeline = 20
    private static let retryInterval: TimeInterval = 5 * 60

    private let log = Logger(subsystem: "com.dantesmith.ArenaWidget", category: "provider")

    func placeholder(in context: Context) -> ChannelEntry {
        .placeholder()
    }

    func snapshot(for configuration: ChannelConfigurationIntent, in context: Context) async -> ChannelEntry {
        let request = FetchRequest(configuration, context)
        // The gallery calls this, so answer within a few seconds no matter what.
        let entry = await withDeadline(seconds: 4) { try await entries(for: request, screens: 1).first }
        return (entry ?? nil) ?? .placeholder(slug: request.slug)
    }

    func timeline(for configuration: ChannelConfigurationIntent, in context: Context) async -> Timeline<ChannelEntry> {
        let request = FetchRequest(configuration, context)
        removeFilesFromEarlierVersions()
        do {
            let entries = try await entries(for: request, screens: Self.screensPerTimeline)
            return Timeline(entries: entries, policy: .atEnd)
        } catch {
            log.error("fetch \(request.slug, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            let entry = request.entry(status: Self.status(for: error))
            return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(Self.retryInterval)))
        }
    }

    private func entries(for request: FetchRequest, screens count: Int) async throws -> [ChannelEntry] {
        let blocks = try await CatalogLoader().load(slug: request.slug)
        let first = Rotation.screenIndex(at: .now, interval: Self.rotationInterval)
        let seed = Rotation.seed(for: request.slug)
        let screens = (first..<first + count).map {
            Rotation.screen($0, of: blocks.map(\.id), perScreen: request.grid.count, seed: seed)
        }

        let byID = Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Int>()
        let needed = screens.joined().filter { seen.insert($0).inserted }.compactMap { byID[$0] }
        let tiles = await TileMaker().tiles(for: needed, pixelSize: request.pixelSize)

        let bytes = tiles.values.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
        log.notice("""
            timeline \(request.slug, privacy: .public) \(request.grid.columns)x\(request.grid.rows) \
            blocks=\(blocks.count) screens=\(screens.count) images=\(tiles.count) \
            px=\(Int(request.pixelSize.width))x\(Int(request.pixelSize.height)) \
            imageMB=\(Double(bytes) / 1_048_576, format: .fixed(precision: 1)) \
            peakMB=\(Diagnostics.peakFootprintMB(), format: .fixed(precision: 1))
            """)

        guard screens.contains(where: { !$0.isEmpty }) else {
            return [ChannelEntry(date: .now, slug: request.slug, tiles: [], showTitles: request.showTitles, status: .loaded)]
        }
        // Entries land on the 3-minute marks, so every widget on the channel turns over together.
        return screens.enumerated().map { offset, screen in
            ChannelEntry(
                date: offset == 0 ? .now : Date(timeIntervalSince1970: Double(first + offset) * Self.rotationInterval),
                slug: request.slug,
                tiles: screen.compactMap { tiles[$0] },
                showTitles: request.showTitles,
                status: .loaded
            )
        }
    }

    private static func status(for error: any Error) -> ChannelEntry.Status {
        switch error as? ArenaError {
        case .notFound: .notFound
        case .unauthorized: .unauthorized
        default: .placeholder
        }
    }

    /// Earlier builds kept a catalog and thumbnails in the extension's container.
    private func removeFilesFromEarlierVersions() {
        let files = FileManager.default
        for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory] {
            guard let base = files.urls(for: directory, in: .userDomainMask).first else { continue }
            try? files.removeItem(at: base.appending(path: "ArenaWidget"))
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

    func entry(status: ChannelEntry.Status) -> ChannelEntry {
        ChannelEntry(date: .now, slug: slug, tiles: [], showTitles: showTitles, status: status)
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
