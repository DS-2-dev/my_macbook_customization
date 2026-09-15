import Foundation

// Are.na v3 API models. Are.na channels hold heterogeneous blocks, so every
// field we don't strictly need is optional and decoded leniently: a block with
// one oddly-shaped field keeps the rest of its data, and a block that can't be
// decoded at all is dropped instead of failing the whole page.

public struct ArenaChannel: Decodable, Sendable {
    public var id: Int?
    public var title: String?
    public var slug: String?
    public var counts: Counts?
    public var owner: ArenaUser?
    /// Changes whenever blocks are added, removed, or reordered.
    public var updatedAt: String?

    public struct Counts: Decodable, Sendable {
        public var contents: Int?
        public var blocks: Int?
    }

    enum CodingKeys: String, CodingKey {
        case id, title, slug, counts, owner
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(Int.self, .id)
        title = c.lenient(String.self, .title)
        slug = c.lenient(String.self, .slug)
        counts = c.lenient(Counts.self, .counts)
        owner = c.lenient(ArenaUser.self, .owner)
        updatedAt = c.lenient(String.self, .updatedAt)
    }
}

public struct ArenaUser: Decodable, Sendable {
    public var slug: String?
    public var name: String?
}

/// One page of `GET /v3/channels/{slug}/contents`.
public struct ArenaContentsPage: Decodable, Sendable {
    public var blocks: [ArenaBlock]
    public var totalCount: Int?
    public var hasMorePages: Bool?

    enum CodingKeys: String, CodingKey { case data, meta }

    struct Meta: Decodable {
        var total_count: Int?
        var has_more_pages: Bool?
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([Lossy<ArenaBlock>].self, forKey: .data) ?? []
        blocks = raw.compactMap(\.value)
        let meta = c.lenient(Meta.self, .meta)
        totalCount = meta?.total_count
        hasMorePages = meta?.has_more_pages
    }
}

public struct ArenaBlock: Decodable, Sendable, Identifiable {
    public var id: Int
    /// `Image`, `Text`, `Link`, `Attachment`, `Embed`, or `Channel`.
    public var type: String?
    public var title: String?
    /// Only present on nested `Channel` entries.
    public var slug: String?
    public var content: RichText?
    public var image: ArenaImage?
    public var source: Source?

    public struct Source: Decodable, Sendable {
        public var url: String?
        public var title: String?
    }

    enum CodingKeys: String, CodingKey { case id, type, title, slug, content, image, source }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = c.lenient(String.self, .type)
        title = c.lenient(String.self, .title)
        slug = c.lenient(String.self, .slug)
        content = c.lenient(RichText.self, .content)
        image = c.lenient(ArenaImage.self, .image)
        source = c.lenient(Source.self, .source)
    }
}

/// Text fields come back as `{ "markdown": ..., "html": ... }`; accept a bare string too.
public struct RichText: Decodable, Sendable {
    public var markdown: String?

    enum CodingKeys: String, CodingKey { case markdown, plain }

    public init(from decoder: any Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            markdown = string
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        markdown = c.lenient(String.self, .markdown) ?? c.lenient(String.self, .plain)
    }
}

/// Codable (not just Decodable) because the widget keeps it in its on-disk catalog.
public struct ArenaImage: Codable, Sendable {
    public var small: Variant?
    public var square: Variant?
    public var medium: Variant?
    public var large: Variant?

    public struct Variant: Codable, Sendable {
        public var src: String?
        /// Same rendition at twice the pixel dimensions (never upscaled past the original).
        public var src2x: String?
        public var width: Double?
        public var height: Double?

        enum CodingKeys: String, CodingKey {
            case src, width, height
            case src2x = "src_2x"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            src = c.lenient(String.self, .src)
            src2x = c.lenient(String.self, .src2x)
            width = c.lenient(Double.self, .width)
            height = c.lenient(Double.self, .height)
        }
    }

    enum CodingKeys: String, CodingKey { case small, square, medium, large }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        small = c.lenient(Variant.self, .small)
        square = c.lenient(Variant.self, .square)
        medium = c.lenient(Variant.self, .medium)
        large = c.lenient(Variant.self, .large)
    }

    /// The smallest rendition that fills a tile of `size` pixels without upscaling.
    /// `small` is the v3 equivalent of v2's `thumb` (400px on the long edge) and
    /// its `src_2x` is 800px; `medium` is only used when `small` is missing. Never
    /// the original.
    public func thumbnailURL(covering size: CGSize) -> URL? {
        let candidates: [(src: String?, width: Double?, height: Double?)] = [
            (small?.src, small?.width, small?.height),
            (small?.src2x, small?.width.map { $0 * 2 }, small?.height.map { $0 * 2 }),
            (medium?.src, medium?.width, medium?.height),
        ]
        let covering = candidates.first { candidate in
            guard candidate.src != nil, let width = candidate.width, let height = candidate.height,
                  width > 0, height > 0 else { return false }
            // Aspect-fill scale; allow a hair of upscaling rather than jumping a size.
            return max(size.width / width, size.height / height) <= 1.05
        }
        return (covering?.src ?? small?.src2x ?? small?.src ?? square?.src ?? medium?.src)
            .flatMap(URL.init(string:))
    }

    var hasThumbnail: Bool {
        thumbnailURL(covering: CGSize(width: 1, height: 1)) != nil
    }
}

/// Decodes a value, turning any failure into `nil` so the surrounding array keeps going.
struct Lossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
