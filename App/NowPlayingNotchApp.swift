import AppKit
import SwiftUI

@main
struct NowPlayingNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The notch panel is built by hand in NotchController; SwiftUI's
        // scenes can't make a borderless, non-activating panel over the menu bar.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = NotchController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}
