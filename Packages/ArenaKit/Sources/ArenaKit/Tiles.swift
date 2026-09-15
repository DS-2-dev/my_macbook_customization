import Foundation

/// A block reduced to what a widget tile draws. Timeline entries get archived,
/// so an image tile points at a small downsampled file instead of carrying the
/// image itself.
public struct Tile: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case image
        case text
    }

    public var id: Int
    public var kind: Kind
    public var title: String?
    public var text: String?
    public var imageFile: URL?
    public var link: URL

    public init(id: Int, kind: Kind, title: String?, text: String?, imageFile: URL?, link: URL) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.imageFile = imageFile
        self.link = link
    }
}

/// Turns catalog blocks into tiles. Thumbnails are downloaded once, written
/// to the thumbnail cache, and never held in memory beyond one decode.
public struct TileMaker: Sendable {
    public var images: ImagePipeline
    public var cache: ImageCache
    /// Caps how many images are being decoded at once, to keep peak memory low.
    public var maxConcurrentDownloads = 4

    public init(images: ImagePipeline = ImagePipeline(), cache: ImageCache = .standard) {
        self.images = images
        self.cache = cache
    }

    /// Tiles keyed by block id. With `allowDownloads` off, image blocks without
    /// a cached thumbnail fall back to text.
    public func tiles(for blocks: [CatalogBlock], pixelSize: CGSize, allowDownloads: Bool) async -> [Int: Tile] {
        await withTaskGroup(of: Tile.self) { group in
            var tiles: [Int: Tile] = [:]
            for (index, block) in blocks.enumerated() {
                if index >= maxConcurrentDownloads, let tile = await group.next() {
                    tiles[tile.id] = tile
                }
                group.addTask { await tile(for: block, pixelSize: pixelSize, allowDownloads: allowDownloads) }
            }
            for await tile in group {
                tiles[tile.id] = tile
            }
            return tiles
        }
    }

    private func tile(for block: CatalogBlock, pixelSize: CGSize, allowDownloads: Bool) async -> Tile {
        if let image = block.image {
            let file = cache.fileURL(blockID: block.id, pixelSize: pixelSize)
            if cache.touch(file) {
                return Tile(id: block.id, kind: .image, title: block.title, text: nil, imageFile: file, link: block.link)
            }
            if allowDownloads,
               let url = image.thumbnailURL(covering: pixelSize),
               let data = try? await images.thumbnail(from: url, pixelSize: pixelSize),
               (try? cache.store(data, at: file)) != nil {
                return Tile(id: block.id, kind: .image, title: block.title, text: nil, imageFile: file, link: block.link)
            }
        }
        let text = block.text ?? block.title ?? block.type ?? ""
        return Tile(id: block.id, kind: .text, title: block.title, text: text, imageFile: nil, link: block.link)
    }
}

enum PlainText {
    /// Flattens block markdown into something a tile can show.
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
