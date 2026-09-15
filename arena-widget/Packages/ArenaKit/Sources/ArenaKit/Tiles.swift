import Foundation

/// A block reduced to what a widget tile draws. Timeline entries get archived,
/// so this carries small downsampled image data rather than an `NSImage`.
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

/// Turns blocks into tiles, downloading and downsampling their thumbnails.
public struct TileMaker: Sendable {
    public var images: ImagePipeline
    /// Caps how many images are being decoded at once, to keep peak memory low.
    public var maxConcurrentDownloads = 4

    public init(images: ImagePipeline = ImagePipeline()) {
        self.images = images
    }

    /// Tiles keyed by block id. An image that fails to download falls back to text.
    public func tiles(for blocks: [CatalogBlock], pixelSize: CGSize) async -> [Int: Tile] {
        await withTaskGroup(of: Tile.self) { group in
            var tiles: [Int: Tile] = [:]
            for (index, block) in blocks.enumerated() {
                if index >= maxConcurrentDownloads, let tile = await group.next() {
                    tiles[tile.id] = tile
                }
                group.addTask { await tile(for: block, pixelSize: pixelSize) }
            }
            for await tile in group {
                tiles[tile.id] = tile
            }
            return tiles
        }
    }

    private func tile(for block: CatalogBlock, pixelSize: CGSize) async -> Tile {
        if let url = block.image?.thumbnailURL(covering: pixelSize),
           let data = try? await images.thumbnail(from: url, pixelSize: pixelSize) {
            return Tile(id: block.id, kind: .image, title: block.title, text: nil, imageData: data, link: block.link)
        }
        let text = block.text ?? block.title ?? block.type ?? ""
        return Tile(id: block.id, kind: .text, title: block.title, text: text, imageData: nil, link: block.link)
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
