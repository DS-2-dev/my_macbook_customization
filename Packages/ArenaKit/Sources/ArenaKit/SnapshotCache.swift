import Foundation

/// Last successful fetch per channel and widget size, kept on disk so a network
/// failure shows slightly old blocks instead of nothing. Inside the widget
/// extension this resolves to the extension's own sandbox container.
public struct SnapshotCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var standard: SnapshotCache {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SnapshotCache(directory: support.appending(path: "ArenaWidget", directoryHint: .isDirectory))
    }

    public func load(key: String) -> ChannelSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? PropertyListDecoder().decode(ChannelSnapshot.self, from: data)
    }

    public func save(_ snapshot: ChannelSnapshot, key: String) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func fileURL(for key: String) -> URL {
        let safe = String(key.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" ? Character(scalar) : "_"
        })
        return directory.appending(path: "\(safe).plist")
    }
}
