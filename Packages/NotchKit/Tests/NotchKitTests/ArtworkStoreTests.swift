import Foundation
import Testing
@testable import NotchKit

@Suite struct ArtworkStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    @Test func downloadsOnceThenServesFromDisk() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A file URL stands in for the art server.
        let source = root.appending(path: "cover.jpg")
        try Data([1, 2, 3]).write(to: source)
        let store = ArtworkStore(directory: root.appending(path: "cache"))

        #expect(try await store.data(for: source) == Data([1, 2, 3]))
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: source).path(percentEncoded: false)))

        // With the original gone, the second ask can only have come from the cache.
        try FileManager.default.removeItem(at: source)
        #expect(try await store.data(for: source) == Data([1, 2, 3]))
    }

    @Test func missingArtThrows() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ArtworkStore(directory: root)
        await #expect(throws: (any Error).self) {
            try await store.data(for: root.appending(path: "nothing-here.jpg"))
        }
    }

    @Test func keysAreStableAndDistinct() {
        let store = ArtworkStore(directory: URL(filePath: "/tmp/art"))
        let a = URL(string: "https://lastfm-img.freetls.fastly.net/i/u/300x300/a.jpg")!
        let b = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/b/600x600bb.jpg")!
        #expect(store.fileURL(for: a) == store.fileURL(for: a))
        #expect(store.fileURL(for: a) != store.fileURL(for: b))
        #expect(store.fileURL(for: a).lastPathComponent.count == 64)
    }

    @Test func pruneKeepsTheMostRecentlyUsed() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 1...5 {
            let file = root.appending(path: "art-\(index)")
            try Data([UInt8(index)]).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(index) * 1000)],
                ofItemAtPath: file.path(percentEncoded: false)
            )
        }
        let store = ArtworkStore(directory: root)
        await store.prune(keeping: 2)
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).sorted()
        #expect(left == ["art-4", "art-5"])
    }
}
