import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ArenaKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func contentsFixture() throws -> ArenaContentsPage {
    try JSONDecoder().decode(ArenaContentsPage.self, from: fixture("contents"))
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
}

/// SplitMix64, so shuffles in tests are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct Decoding {
    @Test func contentsDropsNullAndUndecodableBlocks() throws {
        let page = try contentsFixture()
        // 7 entries: one null, one with a non-numeric id.
        #expect(page.blocks.count == 5)
        #expect(page.totalCount == 74)
        #expect(page.hasMorePages == true)
    }

    @Test func oddFieldsDoNotSinkTheBlock() throws {
        let weird = try #require(try contentsFixture().blocks.first { $0.id == 5 })
        #expect(weird.title == nil)
        #expect(weird.image?.thumbnailURL(covering: CGSize(width: 100, height: 100)) == nil)
    }

    @Test func imagePicksSmallestRenditionThatCoversTheTile() throws {
        let block = try #require(try contentsFixture().blocks.first)
        let image = try #require(block.image)
        #expect(block.type == "Image")
        // Fixture's `small` is 400x267.
        #expect(image.thumbnailURL(covering: CGSize(width: 200, height: 200))?.absoluteString == image.small?.src)
        #expect(image.thumbnailURL(covering: CGSize(width: 470, height: 346))?.absoluteString == image.small?.src2x)
    }

    @Test func textAndLinkBlocks() throws {
        let page = try contentsFixture()
        let text = try #require(page.blocks.first { $0.type == "Text" })
        #expect(text.content?.markdown?.contains("Umberto Eco") == true)
        let link = try #require(page.blocks.first { $0.type == "Link" })
        #expect(link.source?.url != nil)
        #expect(link.image?.thumbnailURL(covering: CGSize(width: 100, height: 100)) != nil)
    }

    @Test func channel() throws {
        let channel = try JSONDecoder().decode(ArenaChannel.self, from: fixture("channel"))
        #expect(channel.title == "Inspo")
        #expect(channel.slug == "inspo-syd5sijpqmk")
        #expect(channel.counts?.contents == 74)
        #expect(channel.updatedAt != nil)
    }
}

@Suite struct Catalogs {
    @Test func blocksKeepWhatTilesNeed() throws {
        let blocks = try contentsFixture().blocks.map(CatalogBlock.init)
        let image = try #require(blocks.first)
        #expect(image.hasImage)
        #expect(image.link == ArenaLink.block(image.id))

        let text = try #require(blocks.first { $0.type == "Text" })
        #expect(!text.hasImage)
        #expect(text.text?.contains("Foucault’s Pendulum") == true)
        #expect(text.text?.contains("*") == false)

        let weird = try #require(blocks.first { $0.id == 5 })
        #expect(!weird.hasImage)
    }

    @Test func survivesDiskRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiskStore(directory: directory)
        let catalog = ChannelCatalog(
            slug: "inspo", title: "Inspo", updatedAt: "2026-09-15T00:00:00Z", totalCount: 74,
            blocks: try contentsFixture().blocks.map(CatalogBlock.init), fetchedAt: .now
        )
        #expect(store.load(ChannelCatalog.self, key: "catalog-inspo") == nil)
        store.save(catalog, key: "catalog-inspo")

        let loaded = try #require(store.load(ChannelCatalog.self, key: "catalog-inspo"))
        #expect(loaded.blocks.map(\.id) == catalog.blocks.map(\.id))
        let size = CGSize(width: 470, height: 346)
        #expect(loaded.blocks.map { $0.image?.thumbnailURL(covering: size) } == catalog.blocks.map { $0.image?.thumbnailURL(covering: size) })
    }
}

@Suite struct Decks {
    @Test(arguments: [1, 2, 3] as [UInt64])
    func dealsEveryBlockBeforeRepeating(seed: UInt64) {
        var generator = SeededGenerator(state: seed)
        var deck = Deck()
        let ids = Array(1...74)
        deck.sync(with: ids, using: &generator)

        let screens = deck.deal(screens: 13, perScreen: 6, using: &generator)
        #expect(screens.count == 13)
        #expect(screens.allSatisfy { $0.count == 6 && Set($0).count == 6 })
        #expect(Set(screens.prefix(12).joined()).count == 72)
        #expect(Set(screens.joined()) == Set(ids))
    }

    @Test func continuesWhereItLeftOffAfterSaving() throws {
        var generator = SeededGenerator(state: 9)
        var deck = Deck()
        deck.sync(with: Array(1...20), using: &generator)
        let first = deck.deal(screens: 2, perScreen: 5, using: &generator)

        let data = try PropertyListEncoder().encode(deck)
        var restored = try PropertyListDecoder().decode(Deck.self, from: data)
        restored.sync(with: Array(1...20), using: &generator)
        let second = restored.deal(screens: 2, perScreen: 5, using: &generator)

        #expect(Set((first + second).joined()) == Set(1...20))
    }

    @Test func syncDropsRemovedBlocksAndQueuesNewOnes() {
        var generator = SeededGenerator(state: 4)
        var deck = Deck()
        deck.sync(with: Array(1...10), using: &generator)
        let shown = Set(deck.deal(screens: 1, perScreen: 5, using: &generator)[0])

        deck.sync(with: Array(3...12), using: &generator)
        let upcoming = Set(3...12).subtracting(shown)
        let next = deck.deal(screens: 1, perScreen: upcoming.count, using: &generator)[0]
        #expect(Set(next) == upcoming)
        #expect(!deck.order.contains(1) && !deck.order.contains(2))
    }

    @Test func fewerBlocksThanTiles() {
        var generator = SeededGenerator(state: 3)
        var deck = Deck()
        deck.sync(with: [7, 8, 9], using: &generator)
        let screens = deck.deal(screens: 2, perScreen: 6, using: &generator)
        #expect(screens.map { Set($0) } == [[7, 8, 9], [7, 8, 9]])
    }

    @Test func duplicateIdsAreIgnored() {
        var generator = SeededGenerator(state: 2)
        var deck = Deck()
        deck.sync(with: [1, 2, 2, 3, 1], using: &generator)
        #expect(deck.order.sorted() == [1, 2, 3])
    }

    @Test func emptyDeck() {
        var generator = SeededGenerator(state: 1)
        var deck = Deck()
        deck.sync(with: [], using: &generator)
        #expect(deck.deal(screens: 20, perScreen: 6, using: &generator).isEmpty)
    }
}

@Suite struct Slugs {
    @Test(arguments: [
        ("inspo-syd5sijpqmk", "inspo-syd5sijpqmk"),
        ("  inspo-syd5sijpqmk\n", "inspo-syd5sijpqmk"),
        ("https://www.are.na/dante-smith/inspo-syd5sijpqmk", "inspo-syd5sijpqmk"),
        ("https://www.are.na/dante-smith/inspo-syd5sijpqmk/", "inspo-syd5sijpqmk"),
        ("are.na/dante-smith/inspo-syd5sijpqmk?view=grid", "inspo-syd5sijpqmk"),
        ("", ""),
    ])
    func normalize(input: String, expected: String) {
        #expect(ChannelSlug.normalize(input) == expected)
    }
}

@Suite struct Links {
    @Test func blockRoundTrip() {
        let url = ArenaLink.block(35243538)
        #expect(url.absoluteString == "arena-widget://block/35243538")
        #expect(ArenaLink.webURL(for: url)?.absoluteString == "https://www.are.na/block/35243538")
    }

    @Test func channelRoundTrip() {
        let url = ArenaLink.channel("inspo-syd5sijpqmk")
        #expect(ArenaLink.webURL(for: url)?.absoluteString == "https://www.are.na/channel/inspo-syd5sijpqmk")
    }

    @Test(arguments: [
        "https://www.are.na/block/1",
        "arena-widget://block/abc",
        "arena-widget://block/1/2",
        "arena-widget://elsewhere/1",
        "arena-widget://channel/..%2Fsettings",
    ])
    func rejectsForeignURLs(_ string: String) throws {
        #expect(ArenaLink.webURL(for: try #require(URL(string: string))) == nil)
    }
}

@Suite struct Thumbnails {
    private func encodedImage(width: Int, height: Int, type: UTType) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func decodedSize(_ data: Data) throws -> (width: Int, height: Int, type: String?) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height, CGImageSourceGetType(source) as String?)
    }

    @Test(arguments: [(120, 120), (200, 100), (100, 160)])
    func downsampledAndCroppedToTileShape(width: Int, height: Int) throws {
        let input = try encodedImage(width: 900, height: 600, type: .png)
        let output = try #require(ImagePipeline.thumbnail(from: input, filling: CGSize(width: width, height: height)))
        let decoded = try decodedSize(output)
        #expect(decoded.width == width)
        #expect(decoded.height == height)
        #expect(decoded.type == UTType.jpeg.identifier)
        #expect(output.count < input.count)
    }

    @Test func smallSourceIsCroppedButNotUpscaled() throws {
        let input = try encodedImage(width: 90, height: 60, type: .png)
        let output = try #require(ImagePipeline.thumbnail(from: input, filling: CGSize(width: 200, height: 200)))
        let decoded = try decodedSize(output)
        #expect(decoded.width == 60)
        #expect(decoded.height == 60)
    }

    @Test func garbageReturnsNil() {
        #expect(ImagePipeline.thumbnail(from: Data("nope".utf8), filling: CGSize(width: 100, height: 100)) == nil)
    }
}

@Suite struct ThumbnailCache {
    @Test func pruneKeepsMostRecentlyUsed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ImageCache(directory: directory)
        let size = CGSize(width: 10, height: 10)
        for id in 1...5 {
            let file = cache.fileURL(blockID: id, pixelSize: size)
            try cache.store(Data([UInt8(id)]), at: file)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(id) * 1000)],
                ofItemAtPath: file.path(percentEncoded: false)
            )
        }

        #expect(cache.touch(cache.fileURL(blockID: 1, pixelSize: size)))
        cache.prune(keeping: 3)

        #expect((1...5).filter { cache.contains(blockID: $0, pixelSize: size) } == [1, 4, 5])
        #expect(!cache.touch(cache.fileURL(blockID: 2, pixelSize: size)))
    }
}

@Suite struct Markdown {
    @Test func stripsInlineSyntaxAndHeadings() {
        #expect(PlainText.fromMarkdown("# Title\n\n― Umberto Eco, *Foucault’s Pendulum*") == "Title\n\n― Umberto Eco, Foucault’s Pendulum")
        #expect(PlainText.fromMarkdown("> [a link](https://example.com)") == "a link")
    }
}
