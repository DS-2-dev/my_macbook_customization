import ImageIO
import OSLog
import UniformTypeIdentifiers
import WidgetKit

struct AlbumEntry: TimelineEntry, Codable {
    var date: Date
    var album: Album?
    /// Encoded cover, already shrunk to the size it's drawn at.
    var cover: Data?
    /// Long edge of `cover` in pixels.
    var coverSide = 0
}

/// One entry per refresh: whatever album the Worker reports now. The app
/// reloads the timeline when the album changes; the 15-minute policy here is
/// the fallback for when the app isn't running.
struct AlbumProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 15 * 60
    private let log = Logger(subsystem: NowPlaying.logSubsystem, category: "provider")

    func placeholder(in context: Context) -> AlbumEntry {
        AlbumEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (AlbumEntry) -> Void) {
        let side = Self.coverSide(for: context)
        Task {
            // The gallery calls this, so the saved entry is enough when there is one.
            if let saved = Store.load() {
                completion(saved)
            } else {
                completion(await entry(coverSide: side))
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<AlbumEntry>) -> Void) {
        let side = Self.coverSide(for: context)
        Task {
            let entry = await entry(coverSide: side)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(Self.refreshInterval))))
        }
    }

    /// Wide sizes draw the cover as a square as tall as the widget; the others
    /// fill the whole widget with it, so the longer edge has to be covered.
    private static func coverSide(for context: Context) -> Int {
        let size = context.displaySize
        return Int((context.family.isWide ? size.height : max(size.width, size.height)) * 2)
    }

    /// The current album with its cover. Falls back to the last entry that
    /// loaded, so a dropped connection never blanks the widget.
    private func entry(coverSide side: Int) async -> AlbumEntry {
        let saved = Store.load()
        do {
            guard let album = try await NowPlaying.latest() else {
                return saved ?? AlbumEntry(date: .now)
            }
            var entry = AlbumEntry(date: .now, album: album)
            if let saved, saved.album == album, saved.cover != nil, saved.coverSide >= side {
                entry.cover = saved.cover
                entry.coverSide = saved.coverSide
            } else if let cover = await cover(for: album, side: side) {
                entry.cover = cover
                entry.coverSide = side
            } else if saved?.album == album {
                // Same album, download failed: a smaller cover beats none.
                entry.cover = saved?.cover
                entry.coverSide = saved?.coverSide ?? 0
            }
            Store.save(entry)
            return entry
        } catch {
            log.error("fetch failed: \(String(describing: error), privacy: .public)")
            return saved.map { AlbumEntry(date: .now, album: $0.album, cover: $0.cover, coverSide: $0.coverSide) }
                ?? AlbumEntry(date: .now)
        }
    }

    private func cover(for album: Album, side: Int) async -> Data? {
        for url in album.artCandidates {
            guard let (data, response) = try? await NowPlaying.session.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let cover = Self.downsample(data, side: side)
            else { continue }
            return cover
        }
        log.error("no cover for \(album.title, privacy: .public)")
        return nil
    }

    /// Decodes straight to `side` pixels on the long edge and re-encodes as
    /// JPEG, so a full-size cover never sits decoded in the extension's memory.
    private static func downsample(_ data: Data, side: Int) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard side > 0, let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// The last entry that loaded, kept in the extension's own container.
private enum Store {
    private static var file: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "last-album.json")
    }

    static func load() -> AlbumEntry? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(AlbumEntry.self, from: data)
    }

    static func save(_ entry: AlbumEntry) {
        guard let file, let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
