import Foundation

/// Widget links use a custom scheme (`arena-widget://block/<id>`) that the app
/// turns into an are.na page, because https links in a macOS widget route
/// through the containing app inconsistently.
public enum ArenaLink {
    public static let scheme = "arena-widget"
    static let web = URL(string: "https://www.are.na")!

    public static func block(_ id: Int) -> URL {
        URL(string: "\(scheme)://block/\(id)")!
    }

    public static func channel(_ slug: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "channel"
        components.path = "/\(slug)"
        return components.url ?? URL(string: "\(scheme)://channel")!
    }

    static func widgetURL(for block: ArenaBlock) -> URL {
        if block.type == "Channel", let slug = block.slug {
            return channel(slug)
        }
        return self.block(block.id)
    }

    /// The are.na page for a widget link, or `nil` if the URL isn't one of ours.
    public static func webURL(for url: URL) -> URL? {
        guard url.scheme == scheme, let host = url.host() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1 else { return nil }

        switch host {
        case "block":
            guard let id = Int(parts[0]), id > 0 else { return nil }
            return web.appending(path: "block/\(id)")
        case "channel":
            let slug = parts[0]
            guard ChannelSlug.isValid(slug) else { return nil }
            return web.appending(path: "channel/\(slug)")
        default:
            return nil
        }
    }
}

public enum ChannelSlug {
    /// Shown until a channel is picked in the widget's edit panel. Must match
    /// the literal default on the widget's configuration intent.
    public static let fallback = "inspo-syd5sijpqmk"

    /// Accepts a bare slug or a pasted channel URL (`https://www.are.na/user/slug`,
    /// with or without the scheme) and returns just the slug.
    public static func normalize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), url.host() != nil {
            text = url.pathComponents.last { $0 != "/" } ?? ""
        } else if text.contains("/") {
            let path = text.split(separator: "?").first.map(String.init) ?? text
            text = path.split(separator: "/").last.map(String.init) ?? ""
        }
        return text.lowercased()
    }

    static func isValid(_ slug: String) -> Bool {
        !slug.isEmpty && slug.unicodeScalars.allSatisfy {
            CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "-" || $0 == "_"
        }
    }
}
