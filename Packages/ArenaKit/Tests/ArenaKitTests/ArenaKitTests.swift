import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ArenaKit

private func contentsFixture() throws -> ArenaContentsPage {
    let url = try #require(Bundle.module.url(forResource: "contents", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(ArenaContentsPage.self, from: Data(contentsOf: url))
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
}

@Suite struct Catalogs {
    @Test func blocksKeepWhatTilesNeed() throws {
        let blocks = try contentsFixture().blocks.map(CatalogBlock.init)
        let image = try #require(blocks.first)
        #expect(image.image != nil)
        #expect(image.link == ArenaLink.block(image.id))

        let text = try #require(blocks.first { $0.type == "Text" })
        #expect(text.image == nil)
        #expect(text.text?.contains("Foucault’s Pendulum") == true)
        #expect(text.text?.contains("*") == false)

        let weird = try #require(blocks.first { $0.id == 5 })
        #expect(weird.image == nil)
    }
}

@Suite struct Rotations {
    private let ids = Array(1...74)

    @Test func screensAreFullAndDistinct() {
        for index in 9_000_000..<9_000_200 {
            let screen = Rotation.screen(index, of: ids, perScreen: 6, seed: 42)
            #expect(screen.count == 6)
            #expect(Set(screen).count == 6)
        }
    }

    @Test func everyBlockShowsOnceBeforeRepeating() {
        // 74 blocks, 6 per screen: the first 12 screens are positions 0..<72, all in the first pass.
        let screens = (0..<12).map { Rotation.screen($0, of: ids, perScreen: 6, seed: 42) }
        #expect(Set(screens.joined()).count == 72)
        let small = (0..<74).map { Rotation.screen($0, of: ids, perScreen: 1, seed: 42) }
        #expect(Set(small.joined()) == Set(ids))
    }

    @Test func sameScreenEveryTime() {
        #expect(Rotation.screen(123, of: ids, perScreen: 6, seed: 7) == Rotation.screen(123, of: ids, perScreen: 6, seed: 7))
        #expect(Rotation.screen(0, of: ids, perScreen: 6, seed: 1) != Rotation.screen(0, of: ids, perScreen: 6, seed: 2))
    }

    @Test func seedIsStableAcrossLaunches() {
        // Published FNV-1a 64-bit value for "a".
        #expect(Rotation.seed(for: "a") == 0xAF63_DC4C_8601_EC8C)
        #expect(Rotation.seed(for: "inspo-syd5sijpqmk") != Rotation.seed(for: "inspo"))
    }

    @Test func screenIndexFollowsTheClock() {
        #expect(Rotation.screenIndex(at: Date(timeIntervalSince1970: 359), interval: 180) == 1)
        #expect(Rotation.screenIndex(at: Date(timeIntervalSince1970: 360), interval: 180) == 2)
    }

    @Test func fewerBlocksThanTiles() {
        #expect(Set(Rotation.screen(5, of: [7, 8, 9], perScreen: 6, seed: 1)) == [7, 8, 9])
    }

    @Test func emptyChannel() {
        #expect(Rotation.screen(5, of: [], perScreen: 6, seed: 1).isEmpty)
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
