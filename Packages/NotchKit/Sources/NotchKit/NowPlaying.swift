import Foundation

/// What the now-playing service answers. Decoded leniently: a missing or
/// oddly typed field becomes nil or false rather than failing the whole answer.
public struct NowPlaying: Equatable, Sendable, Decodable {
    public var playing: Bool
    public var track: String?
    public var artist: String?
    public var album: String?
    public var url: URL?
    public var art: URL?
    /// When the last track was scrobbled; nil while one is playing.
    public var playedAt: Date?
    /// The service couldn't reach Last.fm and this is its last good answer.
    public var stale: Bool

    public init(
        playing: Bool,
        track: String?,
        artist: String?,
        album: String? = nil,
        url: URL? = nil,
        art: URL? = nil,
        playedAt: Date? = nil,
        stale: Bool = false
    ) {
        self.playing = playing
        self.track = track
        self.artist = artist
        self.album = album
        self.url = url
        self.art = art
        self.playedAt = playedAt
        self.stale = stale
    }

    enum CodingKeys: String, CodingKey {
        case playing, track, artist, album, url, art, playedAt, stale
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playing = (try? c.decodeIfPresent(Bool.self, forKey: .playing)) ?? false
        track = Self.text(c, .track)
        artist = Self.text(c, .artist)
        album = Self.text(c, .album)
        url = Self.text(c, .url).flatMap(URL.init(string:))
        art = Self.text(c, .art).flatMap(URL.init(string:))
        playedAt = Self.date(c, .playedAt)
        stale = (try? c.decodeIfPresent(Bool.self, forKey: .stale)) ?? false
    }

    private static func text(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// ISO 8601, which is what the service sends, or unix seconds, which is
    /// what its spec first described.
    private static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        if let seconds = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil {
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
        if let seconds = Double(string) {
            return Date(timeIntervalSince1970: seconds)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

extension NowPlaying {
    /// Which song this is, whatever its state: the same identity going from
    /// playing to stopped is news about one track, not a new one.
    public var identity: String {
        "\(track ?? "")\n\(artist ?? "")"
    }

    /// Worth showing: playing now, or played within `window`. Otherwise the
    /// notch is left alone.
    public func isRecent(at now: Date, within window: TimeInterval) -> Bool {
        guard track != nil else { return false }
        if playing { return true }
        guard let playedAt else { return false }
        return now.timeIntervalSince(playedAt) <= window
    }

    /// "Listening now", or "Last played 20 minutes ago".
    public func status(at now: Date) -> String {
        if playing { return "Listening now" }
        guard let playedAt else { return "Last played" }
        return "Last played \(RelativeTime.ago(playedAt, now: now))"
    }
}

public enum RelativeTime {
    /// In words, since the panel has the room: "just now", "20 minutes ago".
    public static func ago(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int((now.timeIntervalSince(date) / 60).rounded()))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return count(minutes, "minute") }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return count(hours, "hour") }
        let days = Int((Double(hours) / 24).rounded())
        return days == 1 ? "yesterday" : count(days, "day")
    }

    private static func count(_ n: Int, _ unit: String) -> String {
        "\(n) \(unit)\(n == 1 ? "" : "s") ago"
    }
}

public enum NowPlayingError: Error, Equatable, Sendable {
    case status(Int)
}

/// Fetches the service's answer. No keys or credentials: the service holds those.
public struct NowPlayingClient: Sendable {
    public var session: URLSession

    public init(session: URLSession = NowPlayingClient.session) {
        self.session = session
    }

    /// No URL cache: every poll should be a real question.
    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    public func fetch(from url: URL) async throws -> NowPlaying {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NowPlayingError.status(status) }
        return try JSONDecoder().decode(NowPlaying.self, from: data)
    }
}
