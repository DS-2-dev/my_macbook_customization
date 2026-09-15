import CryptoKit
import Foundation

/// Album art on disk, keyed by URL, so each image is downloaded once. Lives
/// in the app's Caches folder: anything macOS purges is fetched again.
public actor ArtworkStore {
    public let directory: URL
    private let session: URLSession
    /// Downloads under way, so two asks for the same art share one.
    private var inFlight: [URL: Task<Data, any Error>] = [:]

    public init(directory: URL, session: URLSession = NowPlayingClient.session) {
        self.directory = directory
        self.session = session
    }

    public static func standard() -> ArtworkStore {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ArtworkStore(directory: caches.appending(path: "Artwork", directoryHint: .isDirectory))
    }

    /// The image's bytes: from disk if it's been fetched before, otherwise
    /// downloaded and kept.
    public func data(for url: URL) async throws -> Data {
        let file = fileURL(for: url)
        if let data = try? Data(contentsOf: file) {
            // Recently used, as far as pruning is concerned.
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path(percentEncoded: false))
            return data
        }
        if let running = inFlight[url] {
            return try await running.value
        }

        let task = Task { [session] () throws -> Data in
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw NowPlayingError.status(http.statusCode)
            }
            guard !data.isEmpty else { throw NowPlayingError.status(204) }
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }

        let data = try await task.value
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }

    /// Where `url`'s art is kept: a hash of the URL, since URLs make poor
    /// file names.
    public nonisolated func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return directory.appending(path: digest.map { String(format: "%02x", $0) }.joined())
    }

    /// Deletes the least recently used art beyond `limit` files.
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
