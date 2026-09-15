import AppKit
import ImageIO
import NotchKit
import OSLog

/// Loads the current track's art without ever holding up the UI: downloaded
/// (or read from disk) and decoded off the main thread.
///
/// Two ways in. `show` is for a track appearing and for every poll after:
/// the slot draws empty and the image fades in when it lands. `prepare` is
/// for a change of track: it waits a moment for the new art so the old track
/// can hand over to the new one in a single motion.
@MainActor
final class ArtworkLoader {
    /// Art that lands, or fails, after nobody is waiting for it.
    var onChange: ((NSImage?, _ failed: Bool) -> Void)?

    private let store = ArtworkStore.standard()
    private var current: URL?
    private var loaded = false
    private var loading: Task<CGImage?, Never>?
    /// When art last failed to load. Last.fm answers 404 for a while on art
    /// for a track it has only just logged, so a failure is tried again later.
    private var failedAt: Date?
    private let retryAfter: TimeInterval = 60
    /// `prepare` is waiting on the load, or has already handed it over.
    private var waiting = false
    private var handedOver = false
    private let log = Logger(subsystem: "com.dantesmith.NowPlayingNotch", category: "artwork")

    init() {
        Task { [store] in await store.prune(keeping: 300) }
    }

    /// Called with every answer for the track on screen. New art empties the
    /// slot and loads; the same art does nothing unless it failed a while ago.
    func show(_ url: URL?) {
        if url == current {
            guard let url, !loaded, loading == nil,
                  let failedAt, Date.now.timeIntervalSince(failedAt) > retryAfter
            else { return }
            load(url)
            return
        }
        reset(to: url)
        // The last track's art must not sit on the new one while this loads.
        onChange?(nil, false)
        if let url { load(url) }
    }

    /// For a change of track: switches to `url`'s art and waits up to
    /// `patience` for it. Art already on disk is back almost at once; art that
    /// takes longer arrives through `onChange` when it lands.
    func prepare(_ url: URL?, patience: Duration) async -> (image: NSImage?, failed: Bool) {
        reset(to: url)
        guard let url else { return (nil, false) }
        load(url)
        guard let loading else { return (nil, false) }

        waiting = true
        defer { waiting = false }
        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask { .done(await loading.value) }
            group.addTask {
                try? await Task.sleep(for: patience)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
        switch outcome {
        case .done(let image):
            handedOver = true
            return (image.map { NSImage(cgImage: $0, size: .zero) }, image == nil)
        case .timedOut:
            return (nil, false)
        }
    }

    private enum Outcome: Sendable {
        case done(CGImage?)
        case timedOut
    }

    private func reset(to url: URL?) {
        loading?.cancel()
        loading = nil
        current = url
        loaded = false
        failedAt = nil
        handedOver = false
    }

    private func load(_ url: URL) {
        let task = Task { [store] () -> CGImage? in
            guard let data = try? await store.data(for: url) else { return nil }
            return await Self.decode(data)
        }
        loading = task
        Task { [weak self] in
            let image = await task.value
            guard let self, self.current == url, self.loading == task else { return }
            self.loading = nil
            if image != nil {
                self.loaded = true
                self.log.notice("art loaded")
            } else {
                self.failedAt = .now
                self.log.error("art failed: \(url.absoluteString, privacy: .public)")
            }
            // `prepare` delivers it itself when it's still waiting, or already has.
            guard !self.waiting, !self.handedOver else { return }
            self.onChange?(image.map { NSImage(cgImage: $0, size: .zero) }, image == nil)
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
