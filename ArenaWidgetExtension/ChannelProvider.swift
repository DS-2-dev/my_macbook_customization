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
    var snapshot: ChannelSnapshot?
    var showTitles: Bool
    var status: Status

    static func placeholder(slug: String = ChannelSlug.fallback) -> ChannelEntry {
        ChannelEntry(date: .now, slug: slug, snapshot: nil, showTitles: false, status: .placeholder)
    }
}

struct ChannelProvider: AppIntentTimelineProvider {
    private static let refreshInterval: TimeInterval = 30 * 60
    private static let retryInterval: TimeInterval = 15 * 60
    private let cache = SnapshotCache.standard
    private let log = Logger(subsystem: "com.dantesmith.ArenaWidget", category: "provider")

    func placeholder(in context: Context) -> ChannelEntry {
        .placeholder()
    }

    func snapshot(for configuration: ChannelConfigurationIntent, in context: Context) async -> ChannelEntry {
        let request = FetchRequest(configuration, context)
        if let cached = cache.load(key: request.cacheKey) {
            return request.entry(cached)
        }
        // Nothing cached yet, typically the first time the gallery asks. Give the
        // network a short window, then fall back so the gallery never stalls.
        if let fresh = await withDeadline(seconds: 4, { try await fetch(request) }) {
            return request.entry(fresh)
        }
        return .placeholder(slug: request.slug)
    }

    func timeline(for configuration: ChannelConfigurationIntent, in context: Context) async -> Timeline<ChannelEntry> {
        let request = FetchRequest(configuration, context)
        do {
            let snapshot = try await fetch(request)
            return Timeline(entries: [request.entry(snapshot)], policy: .after(.now.addingTimeInterval(Self.refreshInterval)))
        } catch {
            log.error("fetch \(request.slug, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            // Stale beats broken: show the last blocks we saw for this channel.
            let entry = cache.load(key: request.cacheKey).map(request.entry)
                ?? request.entry(status: Self.status(for: error))
            return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(Self.retryInterval)))
        }
    }

    private func fetch(_ request: FetchRequest) async throws -> ChannelSnapshot {
        let builder = SnapshotBuilder(client: ArenaClient())
        let snapshot = try await builder.build(slug: request.slug, limit: request.grid.count, pixelSize: request.pixelSize)
        cache.save(snapshot, key: request.cacheKey)
        let bytes = snapshot.tiles.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
        log.notice("""
            fetched \(request.slug, privacy: .public) \(request.grid.columns)x\(request.grid.rows) \
            tiles=\(snapshot.tiles.count) px=\(Int(request.pixelSize.width))x\(Int(request.pixelSize.height)) \
            bytes=\(bytes) \
            peakMB=\(Diagnostics.peakFootprintMB(), format: .fixed(precision: 1))
            """)
        return snapshot
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

    var cacheKey: String { "\(slug)-\(grid.columns)x\(grid.rows)" }

    func entry(_ snapshot: ChannelSnapshot) -> ChannelEntry {
        ChannelEntry(date: .now, slug: slug, snapshot: snapshot, showTitles: showTitles, status: .loaded)
    }

    func entry(status: ChannelEntry.Status) -> ChannelEntry {
        ChannelEntry(date: .now, slug: slug, snapshot: nil, showTitles: showTitles, status: status)
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
