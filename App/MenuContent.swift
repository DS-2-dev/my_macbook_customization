import AppKit
import SwiftUI

/// The menu bar item's menu: what's on, preferences, quit.
struct MenuContent: View {
    let layout: NotchLayout
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let track = layout.track {
            Text(track.track ?? "Unknown track")
            if let artist = track.artist {
                Text(artist)
            }
            if let url = track.url {
                Button("Open on Last.fm") { NSWorkspace.shared.open(url) }
            }
        } else {
            Text("Nothing played recently")
        }
        Divider()
        Button("Preferences…") {
            // An agent app has to come forward for its window to.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit Now Playing") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
