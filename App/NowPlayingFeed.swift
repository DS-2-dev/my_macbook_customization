import AppKit
import NotchKit
import OSLog

/// Asks the now-playing service every 20 seconds, but only while someone
/// could be looking: polling stops while the Mac sleeps, the displays sleep
/// or the screen is locked, and asks once straight away on the way back. A
/// background agent that keeps the radio warm all night drains the battery.
@MainActor
final class NowPlayingFeed {
    static let interval: Duration = .seconds(20)
    /// Nothing played for longer than this, and the notch is left alone.
    static let recentWindow: TimeInterval = 30 * 60

    /// Called after every question with the latest good answer, or with the
    /// previous one again when the question failed.
    var onUpdate: ((NowPlaying?) -> Void)?
    private(set) var latest: NowPlaying?

    private enum Pause: Hashable {
        case systemAsleep
        case displaysAsleep
        case locked
    }

    private let client = NowPlayingClient()
    private var loop: Task<Void, Never>?
    private var pauses: Set<Pause> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let log = Logger(subsystem: "com.dantesmith.NowPlayingNotch", category: "feed")

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.pause(.systemAsleep) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.resume(.systemAsleep) }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.pause(.displaysAsleep) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.resume(.displaysAsleep) }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.pause(.locked) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.resume(.locked) }
        run()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (NowPlayingFeed) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func pause(_ reason: Pause) {
        pauses.insert(reason)
        guard loop != nil else { return }
        loop?.cancel()
        loop = nil
        log.notice("polling paused (\(String(describing: reason), privacy: .public))")
    }

    private func resume(_ reason: Pause) {
        pauses.remove(reason)
        // Waking can arrive before unlocking; only start once nothing is holding it.
        guard pauses.isEmpty, loop == nil else { return }
        log.notice("polling resumed")
        run()
    }

    /// Asks now, then every `interval` until paused.
    private func run() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetch()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func fetch() async {
        do {
            let answer = try await client.fetch(from: AppSettings.serviceURL)
            guard !Task.isCancelled else { return }
            // Only when it changes: once every 20 seconds all day is noise.
            if answer != latest {
                let art = answer.art == nil ? ", no art" : ""
                let stale = answer.stale ? ", stale" : ""
                log.notice("""
                    answer: \(answer.playing ? "playing" : "not playing", privacy: .public) \
                    \(answer.track ?? "no track", privacy: .public)\(art, privacy: .public)\(stale, privacy: .public)
                    """)
            }
            latest = answer
            onUpdate?(answer)
        } catch {
            guard !Task.isCancelled else { return }
            log.error("fetch failed: \(String(describing: error), privacy: .public)")
            // Keep showing what we had; how recent it is gets checked again
            // each time, so an old track still ages out.
            onUpdate?(latest)
        }
    }
}
