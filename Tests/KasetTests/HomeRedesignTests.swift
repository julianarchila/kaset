import Foundation
import Testing
@testable import Kaset

/// Tests for the redesigned Home: featured cards, greeting, and Quick picks grid.
@Suite(.tags(.model))
struct HomeRedesignTests {
    // MARK: - Fixtures

    private static func audioSong(_ id: String) -> HomeSectionItem {
        .song(Song(
            id: id,
            title: "Song \(id)",
            artists: [Artist(id: "UC-\(id)", name: "Artist \(id)")],
            videoId: id,
            musicVideoType: .atv
        ))
    }

    private static func videoSong(_ id: String) -> HomeSectionItem {
        .song(Song(
            id: id,
            title: "Video \(id)",
            artists: [Artist(id: "UC-\(id)", name: "Artist \(id)")],
            videoId: id,
            musicVideoType: .omv
        ))
    }

    private static func playlist(_ id: String) -> HomeSectionItem {
        .playlist(Playlist(id: id, title: "Playlist \(id)", description: nil, thumbnailURL: nil, trackCount: 10))
    }

    private static func album(_ id: String) -> HomeSectionItem {
        .album(Album(id: id, title: "Album \(id)", artists: nil, thumbnailURL: nil, year: nil, trackCount: 10))
    }

    private static func section(
        _ title: String,
        _ items: [HomeSectionItem],
        isChart: Bool = false,
        isListShelf: Bool = false
    ) -> HomeSection {
        HomeSection(id: title, title: title, items: items, isChart: isChart, isListShelf: isListShelf)
    }

    // MARK: - HomeFeaturedPicker

    @Test("Takes one item per shelf, preferring playlists and albums over songs")
    func onePerShelfPreferringCollections() {
        let sections = [
            Self.section("Listen again", [Self.audioSong("s1"), Self.album("a1")]),
            Self.section("Mixed for you", [Self.playlist("p1"), Self.playlist("p2")]),
            Self.section("Recommended", [Self.audioSong("s2")]),
        ]

        let picked = HomeFeaturedPicker.pick(from: sections)

        #expect(picked.map(\.item.id) == ["album-a1", "playlist-p1", "song-s2"])
        #expect(picked.map(\.sourceTitle) == ["Listen again", "Mixed for you", "Recommended"])
    }

    @Test("Fills remaining cards from earlier shelves when there are fewer than three")
    func fillsFromSameShelf() {
        let sections = [
            Self.section("Listen again", [Self.audioSong("s1"), Self.audioSong("s2"), Self.audioSong("s3")]),
        ]

        let picked = HomeFeaturedPicker.pick(from: sections)

        #expect(picked.map(\.item.id) == ["song-s1", "song-s2", "song-s3"])
    }

    @Test("Skips Quick picks, charts, artists, and music videos")
    func skipsIneligibleContent() {
        let sections = [
            Self.section("Quick picks", [Self.audioSong("q1")], isListShelf: true),
            Self.section("Top songs", [Self.playlist("chart")], isChart: true),
            Self.section("Listen together", [Self.videoSong("v1")]),
            Self.section("Artists", [.artist(Artist(id: "UC1", name: "Someone"))]),
        ]

        #expect(HomeFeaturedPicker.pick(from: sections).isEmpty)
    }

    @Test("Never features the same item twice")
    func noDuplicates() {
        let sections = [
            Self.section("A", [Self.playlist("p1")]),
            Self.section("B", [Self.playlist("p1"), Self.playlist("p2")]),
        ]

        let picked = HomeFeaturedPicker.pick(from: sections)

        #expect(picked.map(\.item.id) == ["playlist-p1", "playlist-p2"])
    }

    // MARK: - Greeting

    @Test(
        "Greeting follows the time of day",
        arguments: [
            (4, "Good evening"),
            (5, "Good morning"),
            (11, "Good morning"),
            (12, "Good afternoon"),
            (17, "Good afternoon"),
            (18, "Good evening"),
            (23, "Good evening"),
        ]
    )
    func greetingByHour(hour: Int, expectedKey: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour)))

        #expect(HomeView.greeting(for: date, calendar: calendar) == String(localized: String.LocalizationValue(expectedKey)))
    }

    // MARK: - Quick picks grid

    @Test(
        "Quick picks column count matches the adaptive grid",
        arguments: [(200.0, 1), (543.0, 1), (544.0, 2), (827.0, 2), (828.0, 3), (1200.0, 4)]
    )
    func quickPicksColumnCount(width: Double, expected: Int) {
        #expect(HomeQuickPicksSection.columnCount(forWidth: CGFloat(width)) == expected)
    }
}
