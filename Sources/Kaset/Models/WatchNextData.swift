import Foundation

// MARK: - YouTubeChapter

/// A navigation chapter exposed by YouTube's watch-next `next` response.
struct YouTubeChapter: Identifiable, Hashable {
    /// The video this chapter belongs to, when the renderer includes it.
    let videoId: String?
    let title: String
    /// Chapter start time in seconds.
    let startTime: TimeInterval
    /// Chapter end time in seconds, when YouTube exposes chapter bounds.
    let endTime: TimeInterval?

    var id: String {
        "\(self.videoId ?? "")-\(Int((self.startTime * 1000).rounded()))-\(self.title)"
    }
}

// MARK: - WatchNextData

/// The parts of a regular YouTube `next` response that YouTube Music mixes need:
/// the video title, chapters, and full description. `MixTracklistParser` builds
/// seek-bar segments and per-track scrobbles from them.
struct WatchNextData {
    let videoTitle: String?
    /// Navigation chapters for the current video, when YouTube exposes them.
    let chapters: [YouTubeChapter]
    /// Full watch-page description text, from the structured panel or secondary-info fallback.
    let descriptionText: String?

    init(
        videoTitle: String?,
        chapters: [YouTubeChapter] = [],
        descriptionText: String? = nil
    ) {
        self.videoTitle = videoTitle
        self.chapters = chapters
        self.descriptionText = descriptionText
    }

    static let empty = WatchNextData(videoTitle: nil)
}
