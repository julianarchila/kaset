import Foundation

/// Parser for podcast responses from YouTube Music API.
enum PodcastParser {
    // MARK: - Item Parsing

    /// Parses an episode item. Show cards and unrecognized renderers return `nil`.
    private static func parseEpisodeItem(_ data: [String: Any]) -> PodcastEpisode? {
        // Try musicTwoRowItemRenderer (episode cards; show cards are skipped)
        if let twoRowRenderer = data["musicTwoRowItemRenderer"] as? [String: Any] {
            return self.parseTwoRowItem(twoRowRenderer)
        }

        // Try musicMultiRowListItemRenderer (podcast episodes with progress)
        if let multiRowRenderer = data["musicMultiRowListItemRenderer"] as? [String: Any] {
            return Self.parseMultiRowListItem(multiRowRenderer)
        }

        // Try musicResponsiveListItemRenderer (fallback for some episodes)
        if let responsiveRenderer = data["musicResponsiveListItemRenderer"] as? [String: Any] {
            return Self.parseResponsiveListItem(responsiveRenderer)
        }

        return nil
    }

    /// Parses a two-row item. Podcast show cards (MPSPP browse IDs) return `nil`.
    private static func parseTwoRowItem(_ data: [String: Any]) -> PodcastEpisode? {
        let thumbnailURL = ParsingHelpers.extractThumbnailURL(from: data)

        guard let title = ParsingHelpers.extractTitle(from: data) else {
            return nil
        }

        guard let navigationEndpoint = data["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String
        else {
            return nil
        }

        // Podcast show cards (MPSPP prefix) are not episodes
        if browseId.hasPrefix("MPSPP") {
            return nil
        }

        // Otherwise it might be an episode with watchEndpoint
        if let watchEndpoint = navigationEndpoint["watchEndpoint"] as? [String: Any],
           let videoId = watchEndpoint["videoId"] as? String
        {
            return PodcastEpisode(
                id: videoId,
                title: title,
                showTitle: ParsingHelpers.extractSubtitle(from: data),
                showBrowseId: nil,
                description: nil,
                thumbnailURL: thumbnailURL,
                publishedDate: nil,
                duration: nil,
                durationSeconds: nil,
                playbackProgress: 0,
                isPlayed: false
            )
        }

        return nil
    }

    /// Parses a multi-row list item (podcast episodes with playback progress).
    private static func parseMultiRowListItem(_ data: [String: Any]) -> PodcastEpisode? {
        // Extract video ID from navigation
        guard let onTap = data["onTap"] as? [String: Any],
              let watchEndpoint = onTap["watchEndpoint"] as? [String: Any],
              let videoId = watchEndpoint["videoId"] as? String
        else {
            return nil
        }

        // Extract title from title field
        let title = Self.extractMultiRowTitle(from: data) ?? "Unknown Episode"

        // Extract thumbnail
        let thumbnailURL = ParsingHelpers.extractThumbnailURL(from: data)

        // Extract subtitle (show name)
        let showTitle = Self.extractMultiRowSubtitle(from: data)

        // Extract show browse ID for navigation
        let showBrowseId = Self.extractShowBrowseId(from: data)

        // Extract playback progress (0-100 or 0.0-1.0)
        var playbackProgress: Double = 0
        var isPlayed = false

        if let playbackProgressPercent = data["playbackProgress"] as? [String: Any],
           let percentage = playbackProgressPercent["playbackProgressPercentage"] as? Int
        {
            playbackProgress = Double(percentage) / 100.0
            isPlayed = percentage >= 95
        }

        // Check for "Played" text in played text field
        if let playedTextRuns = data["playedText"] as? [String: Any],
           let runs = playedTextRuns["runs"] as? [[String: Any]],
           let text = runs.first?["text"] as? String,
           text.lowercased() == "played"
        {
            isPlayed = true
            playbackProgress = 1.0
        }

        // Extract duration
        var duration: String?
        var durationSeconds: Int?

        if let durationText = data["durationText"] as? [String: Any],
           let runs = durationText["runs"] as? [[String: Any]],
           let durationStr = runs.first?["text"] as? String
        {
            duration = durationStr
            durationSeconds = Self.parseDurationToSeconds(durationStr)
        }

        // Extract published date
        var publishedDate: String?
        if let publishedTimeText = data["publishedTimeText"] as? [String: Any],
           let runs = publishedTimeText["runs"] as? [[String: Any]],
           let dateStr = runs.first?["text"] as? String
        {
            publishedDate = dateStr
        }

        // Extract description
        var description: String?
        if let descriptionData = data["description"] as? [String: Any],
           let runs = descriptionData["runs"] as? [[String: Any]]
        {
            description = ParsingHelpers.joinedRunText(runs)
        }

        return PodcastEpisode(
            id: videoId,
            title: title,
            showTitle: showTitle,
            showBrowseId: showBrowseId,
            description: description,
            thumbnailURL: thumbnailURL,
            publishedDate: publishedDate,
            duration: duration,
            durationSeconds: durationSeconds,
            playbackProgress: playbackProgress,
            isPlayed: isPlayed
        )
    }

    /// Parses a responsive list item (fallback for some episodes).
    private static func parseResponsiveListItem(_ data: [String: Any]) -> PodcastEpisode? {
        // Items without a video ID (e.g. podcast show rows) are not episodes
        guard let videoId = ParsingHelpers.extractVideoId(from: data) else {
            return nil
        }

        let title = ParsingHelpers.extractTitleFromFlexColumns(data) ?? "Unknown Episode"
        let thumbnailURL = ParsingHelpers.extractThumbnailURL(from: data)
        let showTitle = ParsingHelpers.extractSubtitleFromFlexColumns(data)

        return PodcastEpisode(
            id: videoId,
            title: title,
            showTitle: showTitle,
            showBrowseId: nil,
            description: nil,
            thumbnailURL: thumbnailURL,
            publishedDate: nil,
            duration: nil,
            durationSeconds: nil,
            playbackProgress: 0,
            isPlayed: false
        )
    }

    // MARK: - Podcast Show Detail Parsing

    /// Parses a podcast show detail page (MPSPP{id}).
    static func parseShowDetail( // swiftlint:disable:this function_body_length cyclomatic_complexity
        _ data: [String: Any],
        showId: String
    ) -> PodcastShowDetail {
        var showTitle = ""
        var author: String?
        var description: String?
        var thumbnailURL: URL?
        var episodes: [PodcastEpisode] = []
        var continuationToken: String?
        var isSubscribed = false

        // Parse header from old format (musicDetailHeaderRenderer)
        if let header = data["header"] as? [String: Any],
           let musicDetailHeaderRenderer = header["musicDetailHeaderRenderer"] as? [String: Any]
        {
            showTitle = ParsingHelpers.extractTitle(from: musicDetailHeaderRenderer) ?? ""
            author = ParsingHelpers.extractSubtitle(from: musicDetailHeaderRenderer)
            description = Self.extractDescription(from: musicDetailHeaderRenderer)

            thumbnailURL = ParsingHelpers.extractThumbnailURL(from: musicDetailHeaderRenderer)
        }

        // Parse from twoColumnBrowseResultsRenderer (current format)
        if let contents = data["contents"] as? [String: Any],
           let twoColumnResults = contents["twoColumnBrowseResultsRenderer"] as? [String: Any]
        {
            // Parse header from tabs → sectionListRenderer → musicResponsiveHeaderRenderer
            if let tabs = twoColumnResults["tabs"] as? [[String: Any]],
               let firstTab = tabs.first,
               let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
               let tabContent = tabRenderer["content"] as? [String: Any],
               let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
               let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
            {
                for sectionData in sectionContents {
                    if let headerRenderer = sectionData["musicResponsiveHeaderRenderer"] as? [String: Any] {
                        showTitle = ParsingHelpers.extractTitle(from: headerRenderer) ?? showTitle
                        author = ParsingHelpers.extractSubtitle(from: headerRenderer) ?? author
                        description = Self.extractDescription(from: headerRenderer) ?? description

                        if let headerThumbnailURL = ParsingHelpers.extractThumbnailURL(from: headerRenderer) {
                            thumbnailURL = headerThumbnailURL
                        }

                        // Extract subscription status from buttons
                        if let buttons = headerRenderer["buttons"] as? [[String: Any]] {
                            for button in buttons {
                                if let toggleButton = button["toggleButtonRenderer"] as? [String: Any],
                                   let toggled = toggleButton["isToggled"] as? Bool
                                {
                                    isSubscribed = toggled
                                    break
                                }
                            }
                        }
                    }
                }
            }

            // Parse episodes from secondaryContents
            if let secondaryContents = twoColumnResults["secondaryContents"] as? [String: Any],
               let sectionListRenderer = secondaryContents["sectionListRenderer"] as? [String: Any],
               let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
            {
                for sectionData in sectionContents {
                    if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
                       let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
                    {
                        for itemData in shelfContents {
                            if let episode = Self.parseEpisodeItem(itemData) {
                                episodes.append(episode)
                            }
                        }

                        // Extract continuation token
                        if let continuations = shelfRenderer["continuations"] as? [[String: Any]],
                           let firstContinuation = continuations.first,
                           let nextContinuationData = firstContinuation["nextContinuationData"] as? [String: Any],
                           let token = nextContinuationData["continuation"] as? String
                        {
                            continuationToken = token
                        }
                    }
                }
            }
        }

        // Fallback: Parse episodes from singleColumnBrowseResultsRenderer (old format)
        if episodes.isEmpty,
           let contents = data["contents"] as? [String: Any],
           let singleColumnBrowseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumnBrowseResults["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
           let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        {
            for sectionData in sectionContents {
                if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
                   let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
                {
                    for itemData in shelfContents {
                        if let episode = Self.parseEpisodeItem(itemData) {
                            episodes.append(episode)
                        }
                    }

                    if continuationToken == nil,
                       let continuations = shelfRenderer["continuations"] as? [[String: Any]],
                       let firstContinuation = continuations.first,
                       let nextContinuationData = firstContinuation["nextContinuationData"] as? [String: Any],
                       let token = nextContinuationData["continuation"] as? String
                    {
                        continuationToken = token
                    }
                }
            }
        }

        let show = PodcastShow(
            id: showId,
            title: showTitle,
            author: author,
            description: description,
            thumbnailURL: thumbnailURL,
            episodeCount: episodes.count
        )

        return PodcastShowDetail(
            show: show,
            episodes: episodes,
            continuationToken: continuationToken,
            isSubscribed: isSubscribed
        )
    }

    /// Parses a continuation response for more episodes.
    static func parseEpisodesContinuation(_ data: [String: Any]) -> PodcastEpisodesContinuation {
        var episodes: [PodcastEpisode] = []
        var continuationToken: String?

        if let continuationContents = data["continuationContents"] as? [String: Any],
           let shelfContinuation = continuationContents["musicShelfContinuation"] as? [String: Any],
           let contents = shelfContinuation["contents"] as? [[String: Any]]
        {
            for itemData in contents {
                if let episode = Self.parseEpisodeItem(itemData) {
                    episodes.append(episode)
                }
            }

            // Extract next continuation token
            if let continuations = shelfContinuation["continuations"] as? [[String: Any]],
               let firstContinuation = continuations.first,
               let nextContinuationData = firstContinuation["nextContinuationData"] as? [String: Any],
               let token = nextContinuationData["continuation"] as? String
            {
                continuationToken = token
            }
        }

        return PodcastEpisodesContinuation(
            episodes: episodes,
            continuationToken: continuationToken
        )
    }

    // MARK: - Helper Methods

    private static func extractMultiRowTitle(from data: [String: Any]) -> String? {
        if let title = data["title"] as? [String: Any],
           let runs = title["runs"] as? [[String: Any]],
           let text = runs.first?["text"] as? String
        {
            return text
        }
        return nil
    }

    private static func extractMultiRowSubtitle(from data: [String: Any]) -> String? {
        if let subtitle = data["subtitle"] as? [String: Any],
           let runs = subtitle["runs"] as? [[String: Any]],
           let text = runs.first?["text"] as? String
        {
            return text
        }
        return nil
    }

    private static func extractShowBrowseId(from data: [String: Any]) -> String? {
        // Look for browse endpoint in subtitle runs
        if let subtitle = data["subtitle"] as? [String: Any],
           let runs = subtitle["runs"] as? [[String: Any]]
        {
            for run in runs {
                if let navigationEndpoint = run["navigationEndpoint"] as? [String: Any],
                   let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
                   let browseId = browseEndpoint["browseId"] as? String,
                   browseId.hasPrefix("MPSPP")
                {
                    return browseId
                }
            }
        }
        return nil
    }

    private static func extractDescription(from data: [String: Any]) -> String? {
        if let description = data["description"] as? [String: Any],
           let runs = description["runs"] as? [[String: Any]]
        {
            return ParsingHelpers.joinedRunText(runs)
        }
        return nil
    }

    /// Parses duration string like "36 min" or "1:11:19" to seconds.
    private static func parseDurationToSeconds(_ string: String) -> Int? {
        // Try "X min" format
        if string.hasSuffix(" min") {
            let numberPart = string.dropLast(4)
            if let minutes = Int(numberPart) {
                return minutes * 60
            }
        }

        // Try "X:XX" or "X:XX:XX" format
        let components = string.split(separator: ":").compactMap { Int($0) }
        if components.count == 2 {
            return components[0] * 60 + components[1]
        } else if components.count == 3 {
            return components[0] * 3600 + components[1] * 60 + components[2]
        }

        return nil
    }

    // MARK: - Podcast Detection Helpers

    /// Checks if a browse ID is a podcast show.
    static func isPodcastShow(_ browseId: String) -> Bool {
        browseId.hasPrefix("MPSPP")
    }

    /// Checks if content data contains podcast indicators.
    static func isPodcastContent(_ data: [String: Any]) -> Bool {
        // Check for multiRowListItemRenderer (podcast-specific)
        if data["musicMultiRowListItemRenderer"] != nil {
            return true
        }

        // Check for playbackProgress field
        if let multiRow = data["musicMultiRowListItemRenderer"] as? [String: Any],
           multiRow["playbackProgress"] != nil
        {
            return true
        }

        // Check for MPSPP browse ID
        if let navigationEndpoint = data["navigationEndpoint"] as? [String: Any],
           let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
           let browseId = browseEndpoint["browseId"] as? String,
           browseId.hasPrefix("MPSPP")
        {
            return true
        }

        return false
    }
}
