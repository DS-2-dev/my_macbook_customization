import Foundation

/// What the widget remembers about one block between refreshes.
public struct CatalogBlock: Codable, Sendable, Identifiable {
    public var id: Int
    public var type: String?
    public var title: String?
    public var text: String?
    /// Only set when there's a rendition to show; Image, Link, Embed and
    /// Attachment blocks usually have one, and all of them are drawn as images.
    public var image: ArenaImage?
    public var link: URL

    public init(_ block: ArenaBlock) {
        id = block.id
        type = block.type
        title = block.title?.nonEmpty ?? block.source?.title?.nonEmpty
        text = block.content?.markdown.map { PlainText.fromMarkdown($0) }.flatMap(\.nonEmpty)
        image = block.image?.hasThumbnail == true ? block.image : nil
        link = ArenaLink.widgetURL(for: block)
    }

    public var hasImage: Bool { image != nil }
}

/// Every block in a channel (up to `CatalogLoader.maxBlocks`), so the widget
/// can rotate through all of them.
public struct ChannelCatalog: Codable, Sendable {
    public var slug: String
    public var title: String
    public var updatedAt: String?
    public var totalCount: Int
    public var blocks: [CatalogBlock]
    public var fetchedAt: Date
}

public struct CatalogLoader: Sendable {
    public var client: ArenaClient

    /// Blocks per contents request; the API maximum.
    static let pageSize = 100
    /// Bounds a refresh to 30 requests for very large channels.
    public static let maxBlocks = 3000
    /// Refetch at least this often even when the channel looks unchanged, to pick up edited blocks.
    static let maxAge: TimeInterval = 24 * 60 * 60

    public init(client: ArenaClient = ArenaClient()) {
        self.client = client
    }

    /// Returns `cached` if the channel hasn't changed since it was fetched
    /// (one small request), otherwise fetches every page of contents.
    public func load(slug: String, cached: ChannelCatalog?) async throws -> ChannelCatalog {
        let meta = try await client.channel(slug)
        let total = meta.counts?.contents ?? 0
        if let cached, let updatedAt = meta.updatedAt, cached.updatedAt == updatedAt, cached.totalCount == total,
           Date.now.timeIntervalSince(cached.fetchedAt) < Self.maxAge {
            return cached
        }

        var blocks: [CatalogBlock] = []
        var page = 1
        while true {
            let contents = try await client.contents(slug, per: Self.pageSize, page: page)
            blocks += contents.blocks.map(CatalogBlock.init)
            let hasMore = contents.hasMorePages ?? (page * Self.pageSize < total)
            guard hasMore, page * Self.pageSize < Self.maxBlocks else { break }
            page += 1
        }
        return ChannelCatalog(
            slug: meta.slug ?? slug,
            title: meta.title ?? slug,
            updatedAt: meta.updatedAt,
            totalCount: total,
            blocks: blocks,
            fetchedAt: .now
        )
    }
}
