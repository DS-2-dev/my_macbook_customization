import Foundation

/// What a tile needs to know about a block.
public struct CatalogBlock: Sendable, Identifiable {
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
        image = block.image.flatMap { $0.hasThumbnail ? $0 : nil }
        link = ArenaLink.widgetURL(for: block)
    }
}

/// Lists every block in a channel so the widget can rotate through all of them.
public struct CatalogLoader: Sendable {
    public var client: ArenaClient

    /// Blocks per contents request; the API maximum.
    static let pageSize = 100
    /// Bounds each refresh to 10 requests for very large channels.
    public static let maxBlocks = 1000

    public init(client: ArenaClient = ArenaClient()) {
        self.client = client
    }

    public func load(slug: String) async throws -> [CatalogBlock] {
        var blocks: [CatalogBlock] = []
        var seen = Set<Int>()
        var page = 1
        while true {
            let contents = try await client.contents(slug, per: Self.pageSize, page: page)
            // A block connected to a channel twice shows up twice; keep one.
            for block in contents.blocks where seen.insert(block.id).inserted {
                blocks.append(CatalogBlock(block))
            }
            guard contents.hasMorePages == true, page * Self.pageSize < Self.maxBlocks else { break }
            page += 1
        }
        return blocks
    }
}
