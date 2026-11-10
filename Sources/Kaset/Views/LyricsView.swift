import SwiftUI

// MARK: - LyricsPollLease

/// Lyrics views can be on screen at the same time (main window sidebar, Now Playing, mini
/// player) and share the playback WebView's lyrics poll, so only the last one to disappear
/// stops it.
@MainActor
enum LyricsPollLease {
    private static var holders = 0

    static func acquire() {
        self.holders += 1
    }

    static func release() {
        self.holders = max(0, self.holders - 1)
        if self.holders == 0 {
            SingletonPlayerWebView.shared.stopLyricsPoll()
        }
    }
}

// MARK: - LyricsView

/// Right sidebar panel displaying lyrics for the current track.
@available(macOS 26.0, *)
struct LyricsView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(SyncedLyricsService.self) private var syncedLyricsService

    let client: any YTMusicClientProtocol
    var showsHeader = true
    var preferredWidth: CGFloat? = 280
    /// Draws the glass panel behind the lyrics; the Now Playing view turns it off.
    var showsPanel = true

    @State private var lastLoadedVideoId: String?
    @State private var isLoadingFallback = false

    /// Namespace for glass effect morphing.
    @Namespace private var lyricsNamespace

    var body: some View {
        CompatGlassContainer(spacing: 0) {
            VStack(spacing: 0) {
                if self.showsHeader {
                    self.headerView

                    Divider()
                        .opacity(0.3)
                }

                // Content
                self.contentView
            }
            .frame(width: self.preferredWidth)
            .compatGlass(interactive: true, in: .rect(cornerRadius: 20), isEnabled: self.showsPanel)
            .compatGlassID("lyricsPanel", in: self.lyricsNamespace)
        }
        .compatGlassTransition(.materialize)
        .onChange(of: self.playerService.currentTrack?.videoId) { _, newVideoId in
            if let videoId = newVideoId, videoId != lastLoadedVideoId {
                Task {
                    await self.loadLyrics(for: videoId)
                }
            }
        }
        .task {
            if let videoId = playerService.currentTrack?.videoId {
                await self.loadLyrics(for: videoId)
            }
        }
        .onChange(of: self.syncedLyricsService.currentLyrics) { _, newLyrics in
            self.updateLyricsPolling(for: newLyrics)
        }
        .onDisappear {
            LyricsPollLease.release()
        }
        .onAppear {
            LyricsPollLease.acquire()
            self.updateLyricsPolling(for: self.syncedLyricsService.currentLyrics)
        }
    }

    private func updateLyricsPolling(for result: LyricResult) {
        if case let .synced(synced) = result {
            self.playerService.currentLyricsLineIndex = nil
            self.playerService.currentLyricsDisplayTimeMs = nil
            SingletonPlayerWebView.shared.startLyricsPoll(lineRanges: synced.bridgeLineRanges)
        } else {
            SingletonPlayerWebView.shared.stopLyricsPoll()
            self.playerService.currentLyricsLineIndex = nil
            self.playerService.currentLyricsDisplayTimeMs = nil
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(String(localized: "Lyrics"))
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if self.playerService.currentTrack == nil {
            self.noTrackPlayingView
        } else if self.syncedLyricsService.isLoading || self.isLoadingFallback {
            self.loadingView
        } else {
            switch self.syncedLyricsService.currentLyrics {
            case let .synced(synced):
                self.syncedLyricsContentView(synced)
            case let .plain(plain):
                self.plainLyricsContentView(plain)
            case .unavailable:
                self.noLyricsView
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .frame(width: 20, height: 20)
            Text("Loading lyrics...", comment: "Lyrics panel loading state")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncedLyricsContentView(_ synced: SyncedLyrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SyncedLyricsDisplayView(
                lyrics: synced,
                currentLineIndex: self.playerService.currentLyricsLineIndex,
                displayTimeMs: self.playerService.currentLyricsDisplayTimeMs,
                onSeek: { timeMs in
                    Task { await self.playerService.seek(to: Double(timeMs) / 1000.0) }
                }
            )
            .background(Color.clear)
        }
    }

    private func plainLyricsContentView(_ lyrics: Lyrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Lyrics text. Without the panel (Now Playing), match the synced lyrics'
                // centered type; plain lyrics have no timing, so no line is highlighted.
                Text(lyrics.text)
                    .font(.system(size: self.showsPanel ? 15 : 20, weight: self.showsPanel ? .medium : .semibold))
                    .lineSpacing(self.showsPanel ? 8 : 12)
                    .foregroundStyle(self.showsPanel ? .primary : .secondary)
                    .multilineTextAlignment(self.showsPanel ? .leading : .center)
                    .frame(maxWidth: .infinity, alignment: self.showsPanel ? .leading : .center)
                    .textSelection(.enabled)
                    .padding(.horizontal, self.showsPanel ? 16 : 24)
                    .padding(.vertical, 20)

                // Source attribution
                if let source = lyrics.source {
                    Divider()
                        .padding(.horizontal, 16)

                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var noLyricsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text(String(localized: "No Lyrics Available"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("There aren't any lyrics available for this song.", comment: "Lyrics unavailable message")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noTrackPlayingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text(String(localized: "No Song Playing"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Play a song to view its lyrics here.", comment: "No song playing lyrics message")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    @MainActor
    private func loadLyrics(for videoId: String) async {
        self.lastLoadedVideoId = videoId
        self.isLoadingFallback = false

        guard let track = playerService.currentTrack else { return }

        // Don't search if it's not the current track anymore
        guard track.videoId == videoId else { return }

        let info = LyricsSearchInfo(
            title: track.title,
            artist: track.artistsDisplay,
            album: track.album?.title,
            duration: track.duration,
            videoId: track.videoId
        )

        if SettingsManager.shared.syncedLyricsEnabled {
            await self.syncedLyricsService.fetchLyrics(for: info)
        } else {
            self.syncedLyricsService.currentLyrics = .unavailable
            self.syncedLyricsService.activeProvider = nil
        }

        guard self.lastLoadedVideoId == videoId else { return }
        guard self.playerService.currentTrack?.videoId == videoId else { return }

        // As a fallback to provide plain lyrics
        if case .unavailable = self.syncedLyricsService.currentLyrics {
            self.isLoadingFallback = true
            defer {
                if self.lastLoadedVideoId == videoId {
                    self.isLoadingFallback = false
                }
            }

            do {
                let fetchedLyrics = try await client.getLyrics(videoId: videoId)
                if self.lastLoadedVideoId == videoId,
                   self.playerService.currentTrack?.videoId == videoId
                {
                    self.syncedLyricsService.fallbackToPlainLyrics(fetchedLyrics, videoId: videoId)
                }
            } catch {
                DiagnosticsLogger.api.error("Failed to load plain lyrics fallback: \(error.localizedDescription)")
            }
        }
    }
}

@available(macOS 26.0, *)
#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    LyricsView(client: client)
        .environment(PlayerService())
        .frame(height: 600)
}
