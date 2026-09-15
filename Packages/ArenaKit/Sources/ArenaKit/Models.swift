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

    public struct Counts: Decodable, Sendable {
        public var contents: Int?
        public var blocks: Int?
    }

    enum CodingKeys: String, CodingKey { case id, title, slug, counts, owner }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(Int.self, .id)
        title = c.lenient(String.self, .title)
        slug = c.lenient(String.self, .slug)
        counts = c.lenient(Counts.self, .counts)
        owner = c.lenient(ArenaUser.self, .owner)
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

    enum CodingKeys: String, CodingKey { case data, meta }
    struct Meta: Decodable { var total_count: Int? }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([Lossy<ArenaBlock>].self, forKey: .data) ?? []
        blocks = raw.compactMap(\.value)
        totalCount = c.lenient(Meta.self, .meta)?.total_count
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

public struct ArenaImage: Decodable, Sendable {
    public var small: Variant?
    public var square: Variant?
    public var medium: Variant?
    public var large: Variant?

    public struct Variant: Decodable, Sendable {
        public var src: String?
        public var width: Double?
        public var height: Double?

        enum CodingKeys: String, CodingKey { case src, width, height }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            src = c.lenient(String.self, .src)
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

    /// The smallest rendition that still covers a widget tile. `small` is the
    /// v3 equivalent of v2's `thumb` (400px on the long edge). Never the original.
    public var thumbnailURL: URL? {
        [small, square, medium]
            .lazy
            .compactMap { $0?.src.flatMap(URL.init(string:)) }
            .first
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
