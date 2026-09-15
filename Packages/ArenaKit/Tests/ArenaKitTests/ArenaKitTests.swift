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

@Suite struct Decoding {
    @Test func contentsDropsNullAndUndecodableBlocks() throws {
        let page = try JSONDecoder().decode(ArenaContentsPage.self, from: fixture("contents"))
        // 7 entries: one null, one with a non-numeric id.
        #expect(page.blocks.count == 5)
        #expect(page.totalCount == 74)
    }

    @Test func oddFieldsDoNotSinkTheBlock() throws {
        let page = try JSONDecoder().decode(ArenaContentsPage.self, from: fixture("contents"))
        let weird = try #require(page.blocks.first { $0.id == 5 })
        #expect(weird.title == nil)
        #expect(weird.image?.thumbnailURL(covering: CGSize(width: 100, height: 100)) == nil)
    }

    @Test func imagePicksSmallestRenditionThatCoversTheTile() throws {
        let page = try JSONDecoder().decode(ArenaContentsPage.self, from: fixture("contents"))
        let block = try #require(page.blocks.first)
        let image = try #require(block.image)
        #expect(block.type == "Image")
        // Fixture's `small` is 400x267.
        #expect(image.thumbnailURL(covering: CGSize(width: 200, height: 200))?.absoluteString == image.small?.src)
        #expect(image.thumbnailURL(covering: CGSize(width: 470, height: 346))?.absoluteString == image.small?.src2x)
    }

    @Test func textAndLinkBlocks() throws {
        let page = try JSONDecoder().decode(ArenaContentsPage.self, from: fixture("contents"))
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

@Suite struct Markdown {
    @Test func stripsInlineSyntaxAndHeadings() {
        #expect(PlainText.fromMarkdown("# Title\n\n― Umberto Eco, *Foucault’s Pendulum*") == "Title\n\n― Umberto Eco, Foucault’s Pendulum")
        #expect(PlainText.fromMarkdown("> [a link](https://example.com)") == "a link")
    }
}

@Suite struct Cache {
    @Test func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(directory: directory)
        let snapshot = ChannelSnapshot(
            slug: "inspo", title: "Inspo", blockCount: 1,
            tiles: [Tile(id: 1, kind: .image, title: nil, text: nil, imageData: Data([1, 2, 3]), link: ArenaLink.block(1))],
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(cache.load(key: "inspo-4x1") == nil)
        cache.save(snapshot, key: "inspo-4x1")
        #expect(cache.load(key: "inspo-4x1") == snapshot)
    }
}
