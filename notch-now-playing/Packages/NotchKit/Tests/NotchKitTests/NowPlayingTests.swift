import Foundation
import Testing
@testable import NotchKit

@Suite struct NowPlayingTests {
    private func decode(_ json: String) throws -> NowPlaying {
        try JSONDecoder().decode(NowPlaying.self, from: Data(json.utf8))
    }

    @Test func decodesTheServicesAnswer() throws {
        // Verbatim from the live Worker.
        let answer = try decode("""
            {"playing":false,"track":"All Comes Crashing","artist":"Metric","album":"Formentera",
             "url":"https://www.last.fm/music/Metric/_/All+Comes+Crashing",
             "art":"https://lastfm-img.freetls.fastly.net/i/u/300x300/6453396011984921d86b3435ccf953a7.jpg",
             "playedAt":"2026-09-11T20:51:12.000Z","stale":false}
            """)
        #expect(answer.playing == false)
        #expect(answer.track == "All Comes Crashing")
        #expect(answer.artist == "Metric")
        #expect(answer.url?.absoluteString == "https://www.last.fm/music/Metric/_/All+Comes+Crashing")
        #expect(answer.art != nil)
        #expect(answer.playedAt == Date(timeIntervalSince1970: 1_789_159_872))
    }

    @Test(arguments: ["1789159872", "\"1789159872\"", "\"2026-09-11T20:51:12Z\""])
    func playedAtAsUnixSecondsOrISO(_ value: String) throws {
        let answer = try decode(#"{"playing":false,"track":"x","playedAt":\#(value)}"#)
        #expect(answer.playedAt == Date(timeIntervalSince1970: 1_789_159_872))
    }

    @Test func nullAndEmptyFieldsAreNil() throws {
        let answer = try decode(#"{"playing":true,"track":"Nights","artist":"","art":null,"playedAt":null}"#)
        #expect(answer.playing)
        #expect(answer.artist == nil)
        #expect(answer.art == nil)
        #expect(answer.playedAt == nil)
        #expect(answer.stale == false)
    }

    @Test func recentMeansPlayingOrPlayedWithinTheWindow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let window: TimeInterval = 30 * 60
        #expect(NowPlaying(playing: true, track: "a", artist: "b").isRecent(at: now, within: window))
        #expect(NowPlaying(playing: false, track: "a", artist: "b", playedAt: now - 29 * 60).isRecent(at: now, within: window))
        #expect(!NowPlaying(playing: false, track: "a", artist: "b", playedAt: now - 31 * 60).isRecent(at: now, within: window))
        #expect(!NowPlaying(playing: false, track: "a", artist: "b").isRecent(at: now, within: window))
        #expect(!NowPlaying(playing: true, track: nil, artist: nil).isRecent(at: now, within: window))
    }

    @Test func identityIgnoresState() {
        let playing = NowPlaying(playing: true, track: "Nights", artist: "Frank Ocean")
        let stopped = NowPlaying(playing: false, track: "Nights", artist: "Frank Ocean", playedAt: .now)
        #expect(playing.identity == stopped.identity)
        #expect(playing.identity != NowPlaying(playing: true, track: "Ivy", artist: "Frank Ocean").identity)
        #expect(playing.identity != NowPlaying(playing: true, track: "Nights", artist: "Someone Else").identity)
    }

    @Test func statusLine() {
        let now = Date(timeIntervalSince1970: 100_000)
        #expect(NowPlaying(playing: true, track: "a", artist: "b").status(at: now) == "Listening now")
        #expect(NowPlaying(playing: false, track: "a", artist: "b", playedAt: now - 20 * 60).status(at: now) == "Last played 20 minutes ago")
    }

    /// Seconds ago, and what that reads as.
    private static let ages: [(TimeInterval, String)] = [
        (10, "just now"),
        (60, "1 minute ago"),
        (1_200, "20 minutes ago"),
        (3_600, "1 hour ago"),
        (18_000, "5 hours ago"),
        (108_000, "yesterday"),
        (259_200, "3 days ago"),
    ]

    @Test(arguments: ages)
    func relativeTime(_ seconds: TimeInterval, _ expected: String) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(RelativeTime.ago(now - seconds, now: now) == expected)
    }
}
