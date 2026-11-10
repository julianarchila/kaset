import SwiftUI

/// Home view displaying personalized content sections.
struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(AuthService.self) private var authService
    @State private var navigationPath = NavigationPath()
    @State private var networkMonitor = NetworkMonitor.shared
    /// Featured cards, frozen once full so continuation pages loading below
    /// don't swap them out; recomputed when Home reloads from its first page.
    @State private var featuredItems: [HomeFeaturedItem] = []

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            Group {
                if !self.networkMonitor.isConnected {
                    ErrorView(
                        title: String(localized: "No Connection"),
                        message: String(localized: "Please check your internet connection and try again.")
                    ) {
                        Task { await self.viewModel.refresh() }
                    }
                } else {
                    switch self.viewModel.loadingState {
                    case .idle, .loading:
                        HomeLoadingView()
                    case .loaded, .loadingMore:
                        self.contentView
                    case let .error(error):
                        ErrorView(error: error) {
                            Task { await self.viewModel.refresh() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .localizedNavigationTitle("Home")
            // The greeting is the page title; keep the window title for the
            // Window menu but don't repeat it in the toolbar.
            .toolbar(removing: .title)
            .navigationDestinations(client: self.viewModel.client)
            .playerBarMusicNavigation(path: self.$navigationPath)
        }
        .playerBarMusicNavigation(path: self.$navigationPath)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar()
                .playerBarMusicNavigation(path: self.$navigationPath)
        }
        .onAppear {
            if self.viewModel.loadingState == .idle {
                Task {
                    await self.viewModel.load()
                }
            }
        }
        .popsNavigationStackOnSidebarReselect(path: self.$navigationPath, for: .home)
    }

    // MARK: - Views

    private var contentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                Text(Self.greeting(for: Date()))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal, DetailContentLayout.horizontalInset)
                    .accessibilityAddTraits(.isHeader)

                if !self.featuredItems.isEmpty {
                    HomeFeaturedRow(
                        items: self.featuredItems,
                        open: { self.openItem($0) },
                        play: { self.playFeatured($0) },
                        shuffle: { self.shuffleFeatured($0) }
                    )
                    .padding(.horizontal, DetailContentLayout.horizontalInset)
                }

                // Favorites section (hidden when empty)
                if self.authService.hasPersonalAccount, self.favoritesManager.isVisible {
                    FavoritesSection(
                        onNavigate: { destination in
                            if let playlist = destination as? Playlist {
                                self.navigationPath.append(playlist)
                            } else if let artist = destination as? Artist {
                                self.navigationPath.append(artist)
                            } else if let podcastShow = destination as? PodcastShow {
                                self.navigationPath.append(podcastShow)
                            }
                        },
                        contentInset: DetailContentLayout.horizontalInset
                    )
                    .staggeredAppearance(index: 0)
                }

                // API sections
                ForEach(self.viewModel.sections) { section in
                    Group {
                        if section.isListShelf {
                            HomeQuickPicksSection(
                                section: section,
                                client: self.viewModel.client,
                                play: { item, index in self.playItem(item, in: section, at: index) },
                                navigate: { self.navigationPath.append($0) }
                            )
                            .padding(.horizontal, DetailContentLayout.horizontalInset)
                        } else {
                            self.sectionView(section)
                        }
                    }
                    .task {
                        await self.prefetchImagesAsync(for: section)
                    }
                }

                if self.viewModel.hasMoreSections || self.viewModel.loadingState == .loadingMore {
                    self.loadMoreControl
                }
            }
            // The ScrollView fills the detail column edge-to-edge so shelves
            // scroll under the floating glass sidebar; each shelf restores a
            // resting inset via `contentInset`. Only the vertical inset stays
            // on the stack.
            .padding(.vertical, 20)
        }
        .accessibilityIdentifier(AccessibilityID.Home.scrollView)
        .onChange(of: self.viewModel.sections.first?.id, initial: true) {
            // A new first section means Home reloaded: pick fresh cards.
            self.featuredItems = HomeFeaturedPicker.pick(from: self.viewModel.sections)
        }
        .onChange(of: self.viewModel.sections.count) {
            guard self.featuredItems.count < HomeFeaturedPicker.defaultLimit else { return }
            self.featuredItems = HomeFeaturedPicker.pick(from: self.viewModel.sections)
        }
        .pullToRefresh {
            await self.viewModel.refresh()
        }
    }

    private var loadMoreControl: some View {
        LoadMoreFooter(
            isLoading: self.viewModel.loadingState == .loadingMore,
            title: "Load More",
            loadingTitle: "Loading more...",
            autoLoad: true,
            autoLoadTrigger: self.viewModel.sections.count
        ) {
            await self.viewModel.loadMore()
        }
    }

    private func sectionView(_ section: HomeSection) -> some View {
        HomeItemShelfSection(
            accessibilityLabel: section.title,
            items: section.items,
            isChart: section.isChart,
            contentInset: DetailContentLayout.horizontalInset,
            action: { item, index in
                self.playItem(item, in: section, at: index)
            },
            playlistPlayAction: { item in
                self.playlistPlayAction(for: item)
            },
            header: {
                Text(section.title)
                    .font(.title2)
                    .fontWeight(.semibold)
            },
            contextMenu: { item, index in
                self.contextMenuItems(for: item, in: section, at: index)
            }
        )
    }

    // MARK: - Context Menu

    private func playlistPlayAction(for item: HomeSectionItem) -> (() -> Void)? {
        guard case let .playlist(playlist) = item,
              SongActionsHelper.canQuickPlayPlaylist(playlist)
        else {
            return nil
        }

        return {
            SongActionsHelper.playPlaylist(
                playlist,
                client: self.viewModel.client,
                playerService: self.playerService
            )
        }
    }

    private func contextMenuItems(for item: HomeSectionItem, in section: HomeSection, at index: Int) -> some View {
        HomeSectionItemContextMenu(
            item: item,
            client: self.viewModel.client,
            play: { self.playItem(item, in: section, at: index) },
            navigate: { self.navigationPath.append($0) }
        )
    }

    // MARK: - Image Prefetching

    private static let thumbnailDisplaySize = CGSize(width: 160, height: 160)

    private func prefetchImagesAsync(for section: HomeSection) async {
        // Early exit if task is cancelled
        guard !Task.isCancelled else { return }

        let urls = section.items.prefix(6).compactMap { $0.thumbnailURL?.highQualityThumbnailURL }
        guard !urls.isEmpty else { return }

        await ImageCache.shared.prefetch(
            urls: urls,
            targetSize: Self.thumbnailDisplaySize,
            maxConcurrent: 2
        )
    }

    // MARK: - Greeting

    /// Time-of-day greeting shown as the Home title.
    static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5 ..< 12:
            String(localized: "Good morning")
        case 12 ..< 18:
            String(localized: "Good afternoon")
        default:
            String(localized: "Good evening")
        }
    }

    // MARK: - Featured Actions

    private func openItem(_ item: HomeSectionItem) {
        self.playItem(item, in: nil, at: 0)
    }

    private func playFeatured(_ item: HomeSectionItem) {
        switch item {
        case let .playlist(playlist):
            SongActionsHelper.playPlaylist(playlist, client: self.viewModel.client, playerService: self.playerService)
        case let .album(album):
            AlbumPlaybackActions.playAlbum(album, client: self.viewModel.client, playerService: self.playerService)
        case .song, .artist:
            self.playItem(item, in: nil, at: 0)
        }
    }

    /// Plays a featured playlist or album in a random order, starting from a random track.
    private func shuffleFeatured(_ item: HomeSectionItem) {
        let client = self.viewModel.client
        let playerService = self.playerService
        let intent = playerService.beginMusicPlaybackIntent()
        Task { @MainActor in
            do {
                let songs: [Song]
                switch item {
                case let .playlist(playlist):
                    let response = try await client.getPlaylist(id: playlist.id)
                    songs = PlaylistPlaybackActions.playableSongsWithPlaylistArtwork(
                        response.detail.tracks,
                        playlist: playlist
                    )
                case let .album(album):
                    let response = try await client.getPlaylist(id: album.id)
                    songs = QueueSongMetadata.albumSongs(
                        response.detail.tracks,
                        album: album,
                        purpose: .playback(trackCount: response.detail.tracks.count)
                    )
                case .song, .artist:
                    return
                }
                let shuffled = songs.filter(\.isPlayable).shuffled()
                guard !shuffled.isEmpty, playerService.acceptsMusicPlaybackIntent(intent) else { return }
                await playerService.playQueue(
                    shuffled,
                    startingAt: 0,
                    deferringSmartShuffleFill: false,
                    intent: intent
                )
            } catch {
                DiagnosticsLogger.ui.error("Failed to shuffle-play featured item: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Actions

    private func playItem(_ item: HomeSectionItem, in _: HomeSection?, at _: Int) {
        switch item {
        case let .song(song):
            // Play the song and fetch similar songs (radio queue) in the background
            Task {
                await self.playerService.playWithRadio(song: song)
            }
        case let .playlist(playlist):
            // Navigate to playlist detail
            self.navigationPath.append(playlist)
        case let .album(album):
            // For now, we'll create a playlist-like navigation for albums
            // In a full implementation, we'd have an AlbumDetailView
            let playlist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL,
                trackCount: album.trackCount,
                author: Artist.inline(name: album.artistsDisplay, namespace: "album-artist")
            )
            self.navigationPath.append(playlist)
        case let .artist(artist):
            // Navigate to artist detail
            self.navigationPath.append(artist)
        }
    }
}

#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    HomeView(viewModel: HomeViewModel(client: client))
        .environment(PlayerService())
        .environment(authService)
        .environment(FavoritesManager.shared)
}
