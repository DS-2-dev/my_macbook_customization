import Foundation

/// The last good answer on disk, so the notch can show it the moment the app
/// starts instead of waiting on the first poll.
public struct AnswerCache: Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// In the app's own container.
    public static func standard() -> AnswerCache {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AnswerCache(file: support.appending(path: "NowPlayingNotch/last-answer.json"))
    }

    public func load() -> NowPlaying? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(NowPlaying.self, from: data)
    }

    public func save(_ answer: NowPlaying) {
        guard let data = try? JSONEncoder().encode(answer) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// Written in the same shape the service sends, so the cache reads back
/// through the same decoder.
extension NowPlaying: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(playing, forKey: .playing)
        try c.encodeIfPresent(track, forKey: .track)
        try c.encodeIfPresent(artist, forKey: .artist)
        try c.encodeIfPresent(album, forKey: .album)
        try c.encodeIfPresent(url?.absoluteString, forKey: .url)
        try c.encodeIfPresent(art?.absoluteString, forKey: .art)
        try c.encodeIfPresent(playedAt.map { ISO8601DateFormatter().string(from: $0) }, forKey: .playedAt)
        try c.encode(stale, forKey: .stale)
    }
}
