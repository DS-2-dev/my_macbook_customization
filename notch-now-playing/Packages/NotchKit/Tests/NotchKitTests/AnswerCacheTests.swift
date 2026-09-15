import Foundation
import Testing
@testable import NotchKit

@Suite struct AnswerCacheTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/last-answer.json")
    }

    @Test func roundTrips() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let cache = AnswerCache(file: file)
        let answer = NowPlaying(
            playing: false,
            track: "Victim Of Luck",
            artist: "Lil Lotus",
            album: "Nosebleeder",
            url: URL(string: "https://www.last.fm/music/Lil+Lotus/_/Victim+Of+Luck"),
            art: nil,
            playedAt: Date(timeIntervalSince1970: 1_789_159_872),
            stale: true
        )
        #expect(cache.load() == nil)
        cache.save(answer)
        #expect(cache.load() == answer)
    }

    @Test func unreadableFileIsNoAnswer() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(AnswerCache(file: file).load() == nil)
    }
}
