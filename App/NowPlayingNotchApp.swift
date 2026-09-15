import AppKit
import SwiftUI

@main
struct NowPlayingNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The notch panel itself is built by hand in NotchController; SwiftUI's
        // scenes can't make a borderless, non-activating panel over the menu bar.
        MenuBarExtra("Now Playing", systemImage: "music.note") {
            MenuContent(layout: appDelegate.controller.layout)
        }
        Settings {
            PreferencesView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = NotchController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}
