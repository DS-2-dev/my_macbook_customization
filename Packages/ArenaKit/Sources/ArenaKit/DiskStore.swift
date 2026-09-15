import Foundation

/// Small Codable values (channel catalogs, rotation decks) kept as binary
/// plists. Inside the widget extension this is the extension's own container.
public struct DiskStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var standard: DiskStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DiskStore(directory: support.appending(path: "ArenaWidget", directoryHint: .isDirectory))
    }

    public func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? PropertyListDecoder().decode(type, from: data)
    }

    public func save(_ value: some Encodable, key: String) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func fileURL(for key: String) -> URL {
        directory.appending(path: "\(sanitized(key)).plist")
    }
}

/// Downsampled thumbnails, one file per block and tile size. Lives in Caches:
/// anything the system purges gets downloaded again.
public struct ImageCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var standard: ImageCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ImageCache(directory: caches.appending(path: "ArenaWidget/Thumbnails", directoryHint: .isDirectory))
    }

    public func fileURL(blockID: Int, pixelSize: CGSize) -> URL {
        directory.appending(path: "\(blockID)-\(Int(pixelSize.width))x\(Int(pixelSize.height))")
    }

    public func contains(blockID: Int, pixelSize: CGSize) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(blockID: blockID, pixelSize: pixelSize).path(percentEncoded: false))
    }

    /// Marks a thumbnail as recently used. Returns `false` if it isn't cached.
    func touch(_ file: URL) -> Bool {
        (try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path(percentEncoded: false))) != nil
    }

    func store(_ data: Data, at file: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    /// Deletes the least recently used thumbnails beyond `limit`.
    public func prune(keeping limit: Int) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)),
              files.count > limit
        else { return }
        let byAge = files
            .map { ($0, (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 < $1.1 }
        for (file, _) in byAge.prefix(files.count - limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

private func sanitized(_ key: String) -> String {
    String(key.unicodeScalars.map { scalar in
        CharacterSet.alphanumerics.contains(scalar) || scalar == "-" ? Character(scalar) : "_"
    })
}
