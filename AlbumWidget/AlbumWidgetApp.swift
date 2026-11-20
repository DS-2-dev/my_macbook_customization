import AppKit
import OSLog
import ServiceManagement
import WidgetKit

/// A background app with no windows. macOS decides when a widget may refresh
/// and can leave it a quarter of an hour behind, so this app watches the
/// now-playing Worker and tells the widget to reload when the album changes.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let delegate = AppDelegate()
    private let poller = Poller()
    private let log = Logger(subsystem: NowPlaying.logSubsystem, category: "app")

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        poller.start()

        // Only on the first launch, so turning it off in System Settings sticks.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didSetUp") {
            defaults.set(true, forKey: "didSetUp")
            do {
                try SMAppService.mainApp.register()
            } catch {
                log.error("login item: \(String(describing: error), privacy: .public)")
            }
            showStatus()
        }
    }

    /// Opening the app again while it's running is the only way to reach it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showStatus()
        return false
    }

    private func showStatus() {
        let alert = NSAlert()
        alert.messageText = "Album Widget is running"
        alert.informativeText = """
            It stays in the background and keeps the Last Album widget up to date. \
            To add the widget, right-click the desktop, choose Edit Widgets, and search for Last Album.
            """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              URL(string: string)?.scheme == NowPlaying.widgetURL.scheme
        else { return }
        NSWorkspace.shared.open(NowPlaying.site)
    }
}

/// Asks the Worker for the last album every half minute while the display is
/// awake, and reloads the widget when the answer changes. Each check is one
/// small request, and the timer is loose so macOS can batch it with other work.
@MainActor
private final class Poller {
    private var timer: Timer?
    private var lastKey: String?
    private let log = Logger(subsystem: NowPlaying.logSubsystem, category: "poller")

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        pause()
        // Low Power Mode: check a quarter as often.
        let interval: TimeInterval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 120 : 30
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        next.tolerance = interval / 3
        RunLoop.main.add(next, forMode: .common)
        timer = next

        Task {
            // A failed check changes nothing; the widget keeps its last cover.
            guard let album = try? await NowPlaying.latest(), album.key != lastKey else { return }
            lastKey = album.key
            log.notice("now \(album.artist, privacy: .public) – \(album.title, privacy: .public)")
            WidgetCenter.shared.reloadTimelines(ofKind: NowPlaying.widgetKind)
        }
    }
}
