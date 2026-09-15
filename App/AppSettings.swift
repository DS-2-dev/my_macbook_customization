import Foundation

/// Preferences, kept in the app's own defaults.
enum AppSettings {
    static let defaultServiceURL = URL(string: "https://now-playing.now-playing.workers.dev/")!
    private static let serviceURLKey = "serviceURL"

    /// The now-playing service to ask.
    static var serviceURL: URL {
        UserDefaults.standard.string(forKey: serviceURLKey).flatMap(URL.init(string:)) ?? defaultServiceURL
    }

    /// Saves the service to ask, and tells the feed to ask it now.
    static func setServiceURL(_ url: URL) {
        if url == defaultServiceURL {
            UserDefaults.standard.removeObject(forKey: serviceURLKey)
        } else {
            UserDefaults.standard.set(url.absoluteString, forKey: serviceURLKey)
        }
        NotificationCenter.default.post(name: .serviceURLDidChange, object: nil)
    }
}

extension Notification.Name {
    static let serviceURLDidChange = Notification.Name("com.dantesmith.NowPlayingNotch.serviceURLDidChange")
}
