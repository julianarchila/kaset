import Foundation

/// Parses the regular YouTube `next` (watch-next) response for the data
/// YouTube Music mixes need: title, chapters, and description.
enum WatchNextParser {
    static func parse(_ data: [String: Any]) -> WatchNextData {
        let results = (data["contents"] as? [String: Any])?["twoColumnWatchNextResults"]
            as? [String: Any]

        var videoTitle: String?
        var secondaryDescriptionText: String?

        let primaryContents = (
            (results?["results"] as? [String: Any])?["results"] as? [String: Any]
        )?["contents"] as? [[String: Any]] ?? []

        for content in primaryContents {
            if let primaryInfo = content["videoPrimaryInfoRenderer"] as? [String: Any] {
                videoTitle = Self.text(from: primaryInfo["title"])
            }

            if let secondaryInfo = content["videoSecondaryInfoRenderer"] as? [String: Any],
               let content = (secondaryInfo["attributedDescription"] as? [String: Any])?["content"]
               as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                secondaryDescriptionText = content
            }
        }

        return WatchNextData(
            videoTitle: videoTitle,
            chapters: Self.chapters(of: data),
            descriptionText: Self.descriptionText(of: data) ?? secondaryDescriptionText
        )
    }

    /// Navigation chapters exposed by YouTube's watch-next response.
    ///
    /// Prefer the player bar's `chapterRenderer` markers because they are the
    /// canonical watch-page timeline source. Fall back to
    /// `macroMarkersListItemRenderer`, which can appear in the chapters panel,
    /// structured description, and search previews, and therefore needs
    /// de-duplication.
    static func chapters(of data: [String: Any]) -> [YouTubeChapter] {
        let videoId = self.currentVideoId(of: data)
        var chapterRenderers: [YouTubeChapter] = []
        self.collectChapterRenderers(in: data, videoId: videoId, chapters: &chapterRenderers)
        let canonical = self.deduplicateChapters(chapterRenderers)

        var macroMarkers: [YouTubeChapter] = []
        self.collectMacroMarkerRenderers(in: data, fallbackVideoId: videoId, chapters: &macroMarkers)
        let deduplicatedMacroMarkers = self.deduplicateChapters(macroMarkers)
        guard !canonical.isEmpty else {
            return deduplicatedMacroMarkers
        }
        return self.mergingEndTimes(in: canonical, from: deduplicatedMacroMarkers)
    }

    /// Full watch-page description carried by the structured-description engagement panel.
    static func descriptionText(of data: [String: Any]) -> String? {
        guard let panels = data["engagementPanels"] as? [Any] else { return nil }
        return self.findDescriptionText(in: panels)
    }

    private static func findDescriptionText(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let attributed = dict["attributedDescriptionBodyText"] as? [String: Any],
               let content = attributed["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return content
            }
            if let descriptionBody = dict["descriptionBodyText"] as? [String: Any],
               let content = Self.text(from: descriptionBody),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return content
            }
            for nested in dict.values {
                if let description = self.findDescriptionText(in: nested) {
                    return description
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let description = self.findDescriptionText(in: element) {
                    return description
                }
            }
        }
        return nil
    }

    private static func currentVideoId(of data: [String: Any]) -> String? {
        if let endpoint = data["currentVideoEndpoint"] as? [String: Any],
           let watchEndpoint = endpoint["watchEndpoint"] as? [String: Any],
           let videoId = watchEndpoint["videoId"] as? String,
           !videoId.isEmpty
        {
            return videoId
        }

        return nil
    }

    private static func collectChapterRenderers(
        in value: Any,
        videoId: String?,
        chapters: inout [YouTubeChapter]
    ) {
        if let dict = value as? [String: Any] {
            if let renderer = dict["chapterRenderer"] as? [String: Any],
               let chapter = self.chapter(fromChapterRenderer: renderer, videoId: videoId)
            {
                chapters.append(chapter)
            }

            for nested in dict.values {
                self.collectChapterRenderers(in: nested, videoId: videoId, chapters: &chapters)
            }
        } else if let array = value as? [Any] {
            for element in array {
                self.collectChapterRenderers(in: element, videoId: videoId, chapters: &chapters)
            }
        }
    }

    private static func collectMacroMarkerRenderers(
        in value: Any,
        fallbackVideoId: String?,
        chapters: inout [YouTubeChapter]
    ) {
        if let dict = value as? [String: Any] {
            if let renderer = dict["macroMarkersListItemRenderer"] as? [String: Any],
               let chapter = self.chapter(fromMacroMarkerRenderer: renderer, fallbackVideoId: fallbackVideoId)
            {
                chapters.append(chapter)
            }

            for nested in dict.values {
                self.collectMacroMarkerRenderers(
                    in: nested,
                    fallbackVideoId: fallbackVideoId,
                    chapters: &chapters
                )
            }
        } else if let array = value as? [Any] {
            for element in array {
                self.collectMacroMarkerRenderers(
                    in: element,
                    fallbackVideoId: fallbackVideoId,
                    chapters: &chapters
                )
            }
        }
    }

    private static func chapter(
        fromChapterRenderer renderer: [String: Any],
        videoId: String?
    ) -> YouTubeChapter? {
        guard let title = text(from: renderer["title"]),
              let startMillis = self.intValue(from: renderer["timeRangeStartMillis"])
        else {
            return nil
        }

        return YouTubeChapter(
            videoId: videoId,
            title: title,
            startTime: TimeInterval(startMillis) / 1000,
            endTime: nil
        )
    }

    private static func chapter(
        fromMacroMarkerRenderer renderer: [String: Any],
        fallbackVideoId: String?
    ) -> YouTubeChapter? {
        guard let title = text(from: renderer["title"]) else {
            return nil
        }

        let repeatCommand = self.findRepeatChapterCommand(in: renderer["repeatButton"])
        let watchEndpoint = self.watchEndpoint(from: renderer)
        let endpointVideoId = watchEndpoint?["videoId"] as? String
        if let fallbackVideoId, let endpointVideoId, endpointVideoId != fallbackVideoId {
            return nil
        }
        let timeText = Self.text(from: renderer["timeDescription"])
        let startMillis = self.intValue(from: repeatCommand?["startTimeMs"])
            ?? self.intValue(from: watchEndpoint?["startTimeSeconds"]).map { $0 * 1000 }
            ?? timeText.flatMap(self.milliseconds(fromTimeText:))

        guard let startMillis else { return nil }

        return YouTubeChapter(
            videoId: endpointVideoId ?? fallbackVideoId,
            title: title,
            startTime: TimeInterval(startMillis) / 1000,
            endTime: self.intValue(from: repeatCommand?["endTimeMs"]).map { TimeInterval($0) / 1000 }
        )
    }

    private static func milliseconds(fromTimeText text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else {
            return nil
        }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else {
            return nil
        }

        let seconds: Int = if values.count == 3 {
            values[0] * 3600 + values[1] * 60 + values[2]
        } else {
            values[0] * 60 + values[1]
        }
        return seconds * 1000
    }

    private static func watchEndpoint(from renderer: [String: Any]) -> [String: Any]? {
        guard let onTap = renderer["onTap"] as? [String: Any] else { return nil }
        return onTap["watchEndpoint"] as? [String: Any]
    }

    private static func findRepeatChapterCommand(in value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if let command = dict["repeatChapterCommand"] as? [String: Any] {
                return command
            }

            for nested in dict.values {
                if let command = self.findRepeatChapterCommand(in: nested) {
                    return command
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let command = self.findRepeatChapterCommand(in: element) {
                    return command
                }
            }
        }

        return nil
    }

    private static func intValue(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            int
        case let double as Double:
            Int(double)
        case let number as NSNumber:
            Int(number.int64Value)
        case let string as String:
            Int(string)
        default:
            nil
        }
    }

    private static func deduplicateChapters(_ chapters: [YouTubeChapter]) -> [YouTubeChapter] {
        var indexByKey: [String: Int] = [:]
        var result: [YouTubeChapter] = []

        for chapter in chapters {
            let key = self.chapterKey(chapter)
            if let index = indexByKey[key] {
                if result[index].endTime == nil, chapter.endTime != nil {
                    result[index] = self.mergingEndTime(in: result[index], from: chapter)
                }
                continue
            }
            indexByKey[key] = result.count
            result.append(chapter)
        }

        return result.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            return lhs.title < rhs.title
        }
    }

    private static func mergingEndTimes(
        in chapters: [YouTubeChapter],
        from boundedChapters: [YouTubeChapter]
    ) -> [YouTubeChapter] {
        let boundsByKey = Dictionary(uniqueKeysWithValues: boundedChapters.map {
            (self.chapterKey($0), $0)
        })
        return chapters.map { chapter in
            guard chapter.endTime == nil, let boundedChapter = boundsByKey[self.chapterKey(chapter)] else {
                return chapter
            }
            return self.mergingEndTime(in: chapter, from: boundedChapter)
        }
    }

    private static func mergingEndTime(
        in chapter: YouTubeChapter,
        from boundedChapter: YouTubeChapter
    ) -> YouTubeChapter {
        YouTubeChapter(
            videoId: chapter.videoId,
            title: chapter.title,
            startTime: chapter.startTime,
            endTime: boundedChapter.endTime
        )
    }

    private static func chapterKey(_ chapter: YouTubeChapter) -> String {
        "\(chapter.videoId ?? "")|\(Int((chapter.startTime * 1000).rounded()))|\(chapter.title)"
    }

    // MARK: - Text

    /// Reads a YouTube text node (`simpleText`, `content`, or `runs`).
    static func text(from value: Any?) -> String? {
        guard let dict = value as? [String: Any] else {
            return value as? String
        }

        if let simple = dict["simpleText"] as? String {
            return simple
        }

        if let content = dict["content"] as? String {
            return content
        }

        if let runs = dict["runs"] as? [[String: Any]] {
            let joined = ParsingHelpers.joinedRunText(runs)
            return joined.isEmpty ? nil : joined
        }

        return nil
    }
}
