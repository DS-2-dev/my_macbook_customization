import Foundation

/// A block reduced to what a widget tile needs. Timeline entries get archived,
/// so this carries small encoded image data rather than an `NSImage`.
public struct Tile: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case image
        case text
    }

    public var id: Int
    public var kind: Kind
    public var title: String?
    public var text: String?
    public var imageData: Data?
    public var link: URL

    public init(id: Int, kind: Kind, title: String?, text: String?, imageData: Data?, link: URL) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.imageData = imageData
        self.link = link
    }
}

/// Everything the widget draws for one channel, as of `fetchedAt`.
public struct ChannelSnapshot: Codable, Hashable, Sendable {
    public var slug: String
    public var title: String
    public var blockCount: Int
    public var tiles: [Tile]
    public var fetchedAt: Date

    public init(slug: String, title: String, blockCount: Int, tiles: [Tile], fetchedAt: Date) {
        self.slug = slug
        self.title = title
        self.blockCount = blockCount
        self.tiles = tiles
        self.fetchedAt = fetchedAt
    }
}

public struct SnapshotBuilder: Sendable {
    public var client: ArenaClient
    public var images: ImagePipeline
    /// Caps how many images are being decoded at once, to keep peak memory low.
    public var maxConcurrentDownloads = 4

    public init(client: ArenaClient = ArenaClient(), images: ImagePipeline = ImagePipeline()) {
        self.client = client
        self.images = images
    }

    public func build(slug: String, limit: Int, pixelSize: CGSize) async throws -> ChannelSnapshot {
        async let channel = client.channel(slug)
        async let page = client.contents(slug, per: max(1, limit))
        let (meta, contents) = try await (channel, page)

        let blocks = Array(contents.blocks.prefix(limit))
        let tiles = await makeTiles(blocks, pixelSize: pixelSize)
        return ChannelSnapshot(
            slug: meta.slug ?? slug,
            title: meta.title ?? slug,
            blockCount: meta.counts?.contents ?? contents.totalCount ?? blocks.count,
            tiles: tiles,
            fetchedAt: .now
        )
    }

    private func makeTiles(_ blocks: [ArenaBlock], pixelSize: CGSize) async -> [Tile] {
        await withTaskGroup(of: (Int, Tile).self) { group in
            var tiles = [Tile?](repeating: nil, count: blocks.count)
            for (index, block) in blocks.enumerated() {
                if index >= maxConcurrentDownloads, let done = await group.next() {
                    tiles[done.0] = done.1
                }
                group.addTask { (index, await tile(for: block, pixelSize: pixelSize)) }
            }
            for await done in group {
                tiles[done.0] = done.1
            }
            return tiles.compactMap { $0 }
        }
    }

    private func tile(for block: ArenaBlock, pixelSize: CGSize) async -> Tile {
        let link = ArenaLink.widgetURL(for: block)
        let title = block.displayTitle
        // Image, Link, Embed and Attachment blocks usually carry an image; draw them all as images.
        if let url = block.image?.thumbnailURL(covering: pixelSize),
           let data = try? await images.thumbnail(from: url, pixelSize: pixelSize) {
            return Tile(id: block.id, kind: .image, title: title, text: nil, imageData: data, link: link)
        }
        let text = block.content?.markdown.map { PlainText.fromMarkdown($0) }.flatMap(\.nonEmpty)
        return Tile(id: block.id, kind: .text, title: title, text: text ?? title ?? block.type, imageData: nil, link: link)
    }
}

extension ArenaBlock {
    var displayTitle: String? {
        title?.nonEmpty ?? source?.title?.nonEmpty
    }
}

enum PlainText {
    /// Flattens block markdown into something a tiny tile can show.
    static func fromMarkdown(_ markdown: String, limit: Int = 400) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.drop { $0 == " " || $0 == "#" || $0 == ">" }
        }
        let joined = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var text = (try? AttributedString(markdown: joined, options: options)).map { String($0.characters) } ?? joined
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return String(text.prefix(limit))
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
