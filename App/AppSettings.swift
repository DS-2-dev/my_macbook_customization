import Foundation

/// Preferences, kept in the app's own defaults.
enum AppSettings {
    static let defaultServiceURL = URL(string: "https://now-playing.now-playing.workers.dev/")!

    /// The now-playing service to ask.
    static var serviceURL: URL {
        UserDefaults.standard.string(forKey: "serviceURL").flatMap(URL.init(string:)) ?? defaultServiceURL
    }
}
