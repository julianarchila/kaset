import SwiftUI

// MARK: - SearchView

/// Search results for finding music.
///
/// The query is typed in the sidebar's native search field (see
/// `MainWindow`); this view shows the filter chips and results for it.
struct SearchView: View {
    @State var viewModel: SearchViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(AuthService.self) private var authService
    @State private var navigationPath = NavigationPath()
    @State private var networkMonitor = NetworkMonitor.shared

    init(viewModel: SearchViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            VStack(spacing: 0) {
                if self.viewModel.shouldShowFilters {
                    self.filterChips
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)

                    Divider()
                }

                self.contentView
            }
            .localizedNavigationTitle("Search")
            .navigationDestinations(client: self.viewModel.client)
            .playerBarMusicNavigation(path: self.$navigationPath)
        }
        .playerBarMusicNavigation(path: self.$navigationPath)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar()
                .playerBarMusicNavigation(path: self.$navigationPath)
        }
        .popsNavigationStackOnSidebarReselect(path: self.$navigationPath, for: .search)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchViewModel.SearchFilter.allCases) { filter in
                    self.filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: SearchViewModel.SearchFilter) -> some View {
        Button {
            withAnimation(AppAnimation.spring) {
                self.viewModel.selectedFilter = filter
            }
        } label: {
            Text(filter.displayName)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(self.viewModel.selectedFilter == filter ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundStyle(self.viewModel.selectedFilter == filter ? .white : .primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.chip(isSelected: self.viewModel.selectedFilter == filter))
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if !self.networkMonitor.isConnected {
            ErrorView(
                title: String(localized: "No Connection"),
                message: String(localized: "Please check your internet connection and try again.")
            ) {
                self.viewModel.search()
            }
        } else {
            switch self.viewModel.loadingState {
            case .idle:
                self.emptyStateView
            case .loading:
                LoadingView(String(localized: "Searching..."))
            case .loaded, .loadingMore:
                if self.viewModel.filteredItems.isEmpty {
                    self.noResultsView
                } else {
                    self.resultsView
                }
            case let .error(error):
                ErrorView(error: error) {
                    self.viewModel.search()
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(self.viewModel.query.isEmpty ? String(localized: "Search for your favorite music") : String(localized: "Press Enter to search"))
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(String(localized: "Find songs, albums, artists, and playlists"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(String(localized: "No results found"))
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(String(localized: "Try searching for something else"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(self.viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                    self.resultRow(item, index: index)
                    Divider()
                        .padding(.leading, 72)
                }

                // Load more indicator / button
                if self.viewModel.hasMoreResults {
                    self.loadMoreView
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// Load more view that triggers pagination when visible.
    @ViewBuilder
    private var loadMoreView: some View {
        if self.viewModel.loadingState == .loadingMore {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading more...", comment: "Shown while loading more search results")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            Button {
                Task { await self.viewModel.loadMore() }
            } label: {
                Text("Load More", comment: "Button to load more search results")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .onAppear {
                // Auto-load more when this view appears (infinite scroll)
                Task { await self.viewModel.loadMore() }
            }
        }
    }

    private func resultRow(_ item: SearchResultItem, index: Int) -> some View {
        HoverObservingRow { isHovered in
            Button {
                self.handleItemTap(item)
            } label: {
                HStack(spacing: 12) {
                    // Thumbnail
                    CachedAsyncImage(url: item.thumbnailURL?.highQualityThumbnailURL, targetSize: CGSize(width: 48, height: 48)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: self.iconForItem(item))
                                    .foregroundStyle(.secondary)
                            }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: item.usesCircularThumbnail ? 24 : 6))

                    // Info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 14))
                                .lineLimit(1)
                            if let song = self.songResultPayload(for: item), song.isExplicit == true {
                                ExplicitBadge()
                            }
                        }

                        HStack(spacing: 4) {
                            Text(item.resultType)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            if let subtitle = item.subtitle {
                                Text(String(localized: "•"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)

                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    // Favorite toggle for songs
                    if let song = self.songResultPayload(for: item) {
                        LikeButton(song: song, isRowHovered: isHovered, allowsActions: self.authService.hasPersonalAccount)
                    }

                    // Play indicator for songs
                    if item.videoId != nil {
                        Image(systemName: "play.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.interactiveRow(cornerRadius: 6))
            .accessibilityIdentifier(AccessibilityID.Search.resultRow(index: index))
        }
        .contextMenu {
            SearchResultItemContextMenu(
                item: item,
                client: self.viewModel.client,
                play: { self.handleItemTap(item) },
                navigate: { self.navigationPath.append($0) }
            )
        }
    }

    // MARK: - Helpers

    private func iconForItem(_ item: SearchResultItem) -> String {
        switch item {
        case .song:
            "music.note"
        case .video:
            "play.rectangle"
        case .album:
            "square.stack"
        case .audiobook:
            "books.vertical"
        case .artist:
            "person"
        case .profile:
            "person.crop.circle"
        case .playlist:
            "music.note.list"
        case .podcastShow:
            "mic.fill"
        case .podcastEpisode:
            "mic.badge.plus"
        }
    }

    private func handleItemTap(_ item: SearchResultItem) {
        switch item {
        case let .song(song), let .video(song):
            // Play the song and fetch similar songs (radio queue) in the background
            Task {
                await self.playerService.playWithRadio(song: song)
            }
        case let .artist(artist), let .profile(artist):
            self.navigationPath.append(artist)
        case let .album(album), let .audiobook(album):
            // Navigate as playlist for now
            let playlist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL,
                trackCount: album.trackCount,
                author: Artist.inline(name: album.artistsDisplay, namespace: "album-artist")
            )
            self.navigationPath.append(playlist)
        case let .playlist(playlist):
            self.navigationPath.append(playlist)
        case let .podcastShow(show):
            self.navigationPath.append(show)
        case let .podcastEpisode(episode):
            Task {
                await self.playerService.play(song: episode.playbackSong)
            }
        }
    }

    private func songResultPayload(for item: SearchResultItem) -> Song? {
        switch item {
        case let .song(song), let .video(song):
            song
        default:
            nil
        }
    }
}

#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    SearchView(viewModel: SearchViewModel(client: client))
        .environment(PlayerService())
        .environment(FavoritesManager.shared)
}
