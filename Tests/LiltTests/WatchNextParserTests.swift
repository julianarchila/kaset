import Foundation
import Testing
@testable import Lilt

// MARK: - Fixture Loading

/// Loads a captured YouTube API fixture from the test bundle.
private func loadYouTubeFixture(_ name: String) throws -> [String: Any] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
        throw YouTubeFixtureError.notFound(name)
    }
    let data = try Data(contentsOf: url)
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw YouTubeFixtureError.invalidJSON(name)
    }
    return dict
}

// MARK: - YouTubeFixtureError

private enum YouTubeFixtureError: Error {
    case notFound(String)
    case invalidJSON(String)
}

// MARK: - WatchNextParserTests

@Suite("WatchNextParser", .tags(.parser))
struct WatchNextParserTests {
    @Test("Parses the title and description from a captured next response")
    func parsesWatchNext() throws {
        let data = try loadYouTubeFixture("youtube_watch_next")

        let watchNext = WatchNextParser.parse(data)

        #expect(watchNext.videoTitle == "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)")

        let description = try #require(watchNext.descriptionText)
        #expect(description.hasPrefix("The official video for"))
    }

    @Test("Parses canonical chapters and merges macro-marker end bounds")
    func parsesPlayerOverlayChapters() throws {
        let watchNext = WatchNextParser.parse(Self.chapterRendererResponse())

        #expect(watchNext.chapters.count == 2)

        let first = try #require(watchNext.chapters.first)
        #expect(first.videoId == "video-1")
        #expect(first.title == "Introduction")
        #expect(first.startTime == 0)
        #expect(first.endTime == 197)

        let second = watchNext.chapters[1]
        #expect(second.title == "Single-threaded code")
        #expect(second.startTime == 197)
        #expect(second.endTime == 360)
    }

    @Test("Falls back to deduplicated macro marker chapter cards")
    func parsesMacroMarkerFallbackChapters() throws {
        let chapters = WatchNextParser.chapters(of: Self.macroMarkerOnlyResponse())

        #expect(chapters.count == 2)

        let first = try #require(chapters.first)
        #expect(first.videoId == "video-1")
        #expect(first.title == "Introduction")
        #expect(first.startTime == 0)
        #expect(first.endTime == 197)

        let second = chapters[1]
        #expect(second.title == "Single-threaded code")
        #expect(second.startTime == 197)
        #expect(second.endTime == 360)
    }

    @Test("Ignores heatmap replay markers when chapters are absent")
    func ignoresHeatmapMarkers() {
        let chapters = WatchNextParser.chapters(of: Self.heatmapOnlyResponse())

        #expect(chapters.isEmpty)
    }

    @Test("Parses the structured watch-page description")
    func parsesDescriptionText() {
        let description = "00:00 - Artist A - Track One\n03:15 - Artist B - Track Two"
        let parsed = WatchNextParser.parse(Self.descriptionResponse(description))

        #expect(parsed.descriptionText == description)
    }

    @Test("Falls back to the secondary-info description")
    func parsesSecondaryInfoDescription() {
        let parsed = WatchNextParser.parse(Self.secondaryInfoDescriptionResponse("Secondary description"))

        #expect(parsed.descriptionText == "Secondary description")
    }

    @Test("Prefers the structured description over secondary info")
    func structuredDescriptionTakesPriority() {
        var response = Self.descriptionResponse("Structured description")
        response["contents"] = Self.secondaryInfoDescriptionResponse("Secondary description")["contents"]

        let parsed = WatchNextParser.parse(response)

        #expect(parsed.descriptionText == "Structured description")
    }

    @Test("Parses the runs-based watch-page description")
    func parsesRunsDescriptionText() {
        let parsed = WatchNextParser.parse([
            "engagementPanels": [
                [
                    "descriptionBodyText": [
                        "runs": [
                            ["text": "00:00 Artist A - Track One\n"],
                            ["text": "03:00 Artist B - Track Two"],
                        ],
                    ],
                ],
            ],
        ])

        #expect(parsed.descriptionText == "00:00 Artist A - Track One\n03:00 Artist B - Track Two")
    }

    private static func chapterRendererResponse() -> [String: Any] {
        [
            "currentVideoEndpoint": [
                "watchEndpoint": ["videoId": "video-1"],
            ],
            "playerOverlays": [
                "playerOverlayRenderer": [
                    "decoratedPlayerBarRenderer": [
                        "decoratedPlayerBarRenderer": [
                            "playerBar": [
                                "multiMarkersPlayerBarRenderer": [
                                    "markersMap": [
                                        [
                                            "key": "DESCRIPTION_CHAPTERS",
                                            "value": [
                                                "chapters": [
                                                    ["chapterRenderer": self.chapterRenderer(title: "Introduction", startMs: 0, imageName: "intro")],
                                                    ["chapterRenderer": self.chapterRenderer(title: "Single-threaded code", startMs: 197_000, imageName: "single")],
                                                ],
                                            ],
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            // Matching macro markers provide end bounds that the canonical
            // chapterRenderer timeline omits.
            "engagementPanels": [
                [
                    "engagementPanelSectionListRenderer": [
                        "content": [
                            "macroMarkersListRenderer": [
                                "contents": [
                                    ["macroMarkersListItemRenderer": self.macroMarkerRenderer(title: "Introduction", startMs: 0, endMs: 197_000, imageName: "intro")],
                                    ["macroMarkersListItemRenderer": self.macroMarkerRenderer(title: "Single-threaded code", startMs: 197_000, endMs: 360_000, imageName: "single")],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func macroMarkerOnlyResponse() -> [String: Any] {
        [
            "currentVideoEndpoint": [
                "watchEndpoint": ["videoId": "video-1"],
            ],
            "engagementPanels": [
                [
                    "engagementPanelSectionListRenderer": [
                        "content": [
                            "macroMarkersListRenderer": [
                                "contents": [
                                    ["macroMarkersListItemRenderer": self.macroMarkerRenderer(title: "Introduction", startMs: 0, endMs: 197_000, imageName: "intro")],
                                    ["macroMarkersListItemRenderer": self.macroMarkerRenderer(title: "Introduction", startMs: 0, endMs: 197_000, imageName: "intro")],
                                    ["macroMarkersListItemRenderer": self.macroMarkerRenderer(title: "Other video chapter", startMs: 45000, endMs: 90000, imageName: "other", videoId: "other-video")],
                                    ["macroMarkersListItemRenderer": self.macroMarkerRenderer(title: "Single-threaded code", startMs: 197_000, endMs: 360_000, imageName: "single")],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func heatmapOnlyResponse() -> [String: Any] {
        [
            "frameworkUpdates": [
                "entityBatchUpdate": [
                    "mutations": [
                        [
                            "payload": [
                                "macroMarkersListEntity": [
                                    "markersList": [
                                        "markerType": "MARKER_TYPE_HEATMAP",
                                        "markers": [
                                            ["startMillis": "0", "durationMillis": "1000", "intensityScoreNormalized": 1],
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func secondaryInfoDescriptionResponse(_ description: String) -> [String: Any] {
        [
            "contents": [
                "twoColumnWatchNextResults": [
                    "results": [
                        "results": [
                            "contents": [
                                [
                                    "videoSecondaryInfoRenderer": [
                                        "attributedDescription": ["content": description],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func descriptionResponse(_ description: String) -> [String: Any] {
        [
            "engagementPanels": [
                [
                    "engagementPanelSectionListRenderer": [
                        "content": [
                            "structuredDescriptionContentRenderer": [
                                "items": [
                                    [
                                        "expandableVideoDescriptionBodyRenderer": [
                                            "attributedDescriptionBodyText": ["content": description],
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func chapterRenderer(title: String, startMs: Int, imageName: String) -> [String: Any] {
        [
            "timeRangeStartMillis": startMs,
            "title": ["simpleText": title],
            "thumbnail": self.thumbnail(imageName: imageName),
        ]
    }

    private static func macroMarkerRenderer(
        title: String,
        startMs: Int,
        endMs: Int,
        imageName: String,
        videoId: String = "video-1",
        includesExplicitStart: Bool = true
    ) -> [String: Any] {
        var renderer: [String: Any] = [
            "title": ["runs": [["text": title]]],
            "timeDescription": ["simpleText": self.timeText(seconds: startMs / 1000)],
            "thumbnail": self.thumbnail(imageName: imageName),
        ]

        renderer["onTap"] = [
            "watchEndpoint": includesExplicitStart ? [
                "videoId": videoId,
                "startTimeSeconds": startMs / 1000,
            ] : [
                "videoId": videoId,
            ],
        ]

        if includesExplicitStart {
            renderer["repeatButton"] = [
                "toggleButtonRenderer": [
                    "defaultServiceEndpoint": [
                        "repeatChapterCommand": [
                            "startTimeMs": "\(startMs)",
                            "endTimeMs": "\(endMs)",
                        ],
                    ],
                ],
            ]
        }

        return renderer
    }

    private static func thumbnail(imageName: String) -> [String: Any] {
        [
            "thumbnails": [
                ["url": "https://example.com/\(imageName)-168.jpg", "width": 168, "height": 94],
                ["url": "https://example.com/\(imageName)-336.jpg", "width": 336, "height": 188],
            ],
        ]
    }

    private static func timeText(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
