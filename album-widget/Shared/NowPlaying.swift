import Foundation

/// The album of the last track played, as the now-playing Worker reports it.
struct Album: Codable, Equatable, Sendable {
    var title: String
    var artist: String
    var art: URL?

    /// Changes when the album or its artwork does, and not from one track to
    /// the next on the same album.
    var key: String {
        "\(artist.lowercased())|\(title.lowercased())|\(art?.absoluteString ?? "")"
    }

    /// Artwork URLs to try, largest first. Last.fm sizes art in the path and
    /// the Worker hands out 300x300, which is soft on a Retina display.
    var artCandidates: [URL] {
        guard let art else { return [] }
        let larger = URL(string: art.absoluteString.replacingOccurrences(of: "/i/u/300x300/", with: "/i/u/770x0/"))
        return larger.map { $0 == art ? [art] : [$0, art] } ?? [art]
    }
}

enum NowPlaying {
    static let endpoint = URL(string: "https://now-playing.ds2dev.workers.dev/")!
    static let site = URL(string: "https://dantesmith.studio")!
    static let widgetKind = "LastAlbumWidget"
    /// Widget clicks use a custom scheme that the app turns into the site,
    /// because https links in a macOS widget route through the containing app
    /// inconsistently.
    static let widgetURL = URL(string: "album-widget://open")!
    static let logSubsystem = "com.dantesmith.AlbumWidget"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// The last album played, or `nil` when nothing has been played yet.
    static func latest() async throws -> Album? {
        let (data, response) = try await session.data(from: endpoint)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return album(from: try JSONDecoder().decode(Payload.self, from: data))
    }

    private struct Payload: Decodable {
        var track: String?
        var artist: String?
        var album: String?
        var art: String?
    }

    /// A track with no album (a single, a loose upload) stands in as its own.
    private static func album(from payload: Payload) -> Album? {
        guard let title = [payload.album, payload.track].compactMap(nonEmpty).first else { return nil }
        return Album(
            title: title,
            artist: nonEmpty(payload.artist) ?? "",
            art: nonEmpty(payload.art).flatMap(URL.init(string:))
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
