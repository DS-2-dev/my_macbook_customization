import AppKit
import ArenaKit
import SwiftUI
import WidgetKit

@main
struct ArenaWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Are.na Widget", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

/// Forwards `arena-widget://` links from the widget to are.na in the browser.
///
/// This uses a GetURL Apple Event handler rather than SwiftUI's `onOpenURL`:
/// on macOS, `onOpenURL` opens a window for every incoming URL, and when the
/// widget cold-launches the app we want to hand off to the browser and quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didFinishLaunching = false
    private var launchedForURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        if launchedForURL {
            NSApp.terminate(nil)
        } else {
            // Pick up layout changes right away after installing a new build.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string),
              let destination = ArenaLink.webURL(for: url)
        else { return }

        if !didFinishLaunching {
            launchedForURL = true
        }
        NSWorkspace.shared.open(destination)
    }
}
