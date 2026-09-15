import Foundation

public enum ArenaError: Error, Equatable, Sendable {
    case notFound
    /// The channel is private; this widget only reads public channels.
    case unauthorized
    case http(Int)
    case badResponse
}

/// Minimal client for the public Are.na v3 API. Public channels need no token.
public struct ArenaClient: Sendable {
    public static let baseURL = URL(string: "https://api.are.na/v3")!

    public var session: URLSession

    public init(session: URLSession = .arena) {
        self.session = session
    }

    /// Newest-first by the owner's manual order, which is how the channel reads on are.na.
    public func contents(_ slug: String, per: Int, page: Int = 1) async throws -> ArenaContentsPage {
        try await get("channels/\(slug)/contents", query: [
            URLQueryItem(name: "per", value: String(per)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "position_desc"),
        ])
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ArenaError.badResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw ArenaError.unauthorized
        case 404: throw ArenaError.notFound
        default: throw ArenaError.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension URLSession {
    /// No URL cache: the widget keeps nothing on disk, and the extension has a small memory ceiling.
    public static let arena: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
}
