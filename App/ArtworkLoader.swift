import AppKit
import ImageIO
import NotchKit
import OSLog

/// Loads the current track's art without ever holding up the UI: the panel
/// draws an empty art slot straight away, and the image fades into it once
/// it's downloaded (or read from disk) and decoded, all off the main thread.
@MainActor
final class ArtworkLoader {
    /// Called with the decoded image, or nil and `failed` when there's none to show.
    var onChange: ((NSImage?, _ failed: Bool) -> Void)?

    private let store = ArtworkStore.standard()
    private var current: URL?
    private var loaded = false
    private var task: Task<Void, Never>?
    /// When art last failed to load. Last.fm answers 404 for a while on art
    /// for a track it has only just logged, so a failure is tried again later.
    private var failedAt: Date?
    private let retryAfter: TimeInterval = 60
    private let log = Logger(subsystem: "com.dantesmith.NowPlayingNotch", category: "artwork")

    init() {
        Task { [store] in await store.prune(keeping: 300) }
    }

    /// Called with every answer. Does nothing when that art is already
    /// showing or on its way.
    func show(_ url: URL?) {
        if url == current {
            let retrying = !loaded && task == nil && failedAt.map { Date.now.timeIntervalSince($0) > retryAfter } == true
            guard retrying, let url else { return }
            load(url)
            return
        }
        task?.cancel()
        task = nil
        current = url
        loaded = false
        failedAt = nil
        // The last track's art must not sit on the new one while this loads.
        onChange?(nil, false)
        if let url { load(url) }
    }

    private func load(_ url: URL) {
        task = Task { [store] in
            do {
                let data = try await store.data(for: url)
                let image = await Self.decode(data)
                guard !Task.isCancelled, self.current == url else { return }
                self.task = nil
                guard let image else { throw NowPlayingError.status(415) }
                self.loaded = true
                self.log.notice("art loaded")
                self.onChange?(NSImage(cgImage: image, size: .zero), false)
            } catch {
                guard !Task.isCancelled, self.current == url else { return }
                self.task = nil
                self.failedAt = .now
                self.log.error("art failed: \(String(describing: error), privacy: .public)")
                self.onChange?(nil, true)
            }
        }
    }

    /// Decodes at the size it's drawn: the open panel's 72pt art, at 2x,
    /// with some room. Off the main thread.
    @concurrent
    private nonisolated static func decode(_ data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
