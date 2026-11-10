import SwiftUI

/// Sidebar navigation for the main window, styled like Apple Music.
///
/// Layout: the native search field, Home, and Explore at the top; the Library
/// destinations; pinned items; and every playlist in the user's library.
struct Sidebar: View {
    private enum SidebarSelection: Hashable {
        case navigation(NavigationItem)
        case pinned(SidebarPinnedItem)
        case libraryPlaylist(contentId: String)
    }

    /// Which section a playlist selection came from. Library playlists reuse the
    /// pinned-item detail route, so this keeps only the clicked row highlighted
    /// when a playlist is both pinned and in the Playlists list.
    private enum PinnedSelectionOrigin {
        case pinned
        case libraryPlaylists
    }

    @Binding var selection: NavigationItem?
    @Binding var pinnedSelection: SidebarPinnedItem?
    let client: any YTMusicClientProtocol
    var libraryViewModel: LibraryViewModel?
    var onReselectNavigationItem: ((NavigationItem) -> Void)?
    var onReselectPinnedItem: ((SidebarPinnedItem) -> Void)?
    @Environment(AuthService.self) private var authService
    @Environment(PlayerService.self) private var playerService
    @Environment(SidebarPinnedItemsManager.self) private var sidebarPinnedItemsManager
    @State private var isCreatingPlaylist = false
    @State private var isHoveringPlaylistsHeader = false
    @State private var pinnedSelectionOrigin: PinnedSelectionOrigin = .pinned
    @AppStorage("sidebar.libraryExpanded") private var isLibraryExpanded = true
    @AppStorage("sidebar.pinnedExpanded") private var isPinnedExpanded = true
    @AppStorage("sidebar.playlistsExpanded") private var isPlaylistsExpanded = true

    var body: some View {
        List {
            // Main navigation
            Section {
                self.navigationRow(.home)
                    .accessibilityIdentifier(AccessibilityID.Sidebar.homeItem)

                // Explore links to new releases, charts, and moods & genres.
                self.navigationRow(.explore)
                    .accessibilityIdentifier(AccessibilityID.Sidebar.exploreItem)
            }

            if self.hasPersonalAccount {
                Section(isExpanded: self.$isLibraryExpanded) {
                    self.navigationRow(.libraryArtists)
                        .accessibilityIdentifier(AccessibilityID.Sidebar.libraryArtistsItem)

                    self.navigationRow(.libraryAlbums)
                        .accessibilityIdentifier(AccessibilityID.Sidebar.libraryAlbumsItem)

                    self.navigationRow(.likedMusic)
                        .accessibilityIdentifier(AccessibilityID.Sidebar.likedMusicItem)

                    self.navigationRow(.history)
                        .accessibilityIdentifier(AccessibilityID.Sidebar.historyItem)

                    if self.hasSavedPodcasts {
                        self.navigationRow(.libraryPodcasts)
                            .accessibilityIdentifier(AccessibilityID.Sidebar.libraryPodcastsItem)
                    }
                } header: {
                    Text(String(localized: "Library"))
                }

                if !self.sidebarPinnedItemsManager.items.isEmpty {
                    Section(isExpanded: self.$isPinnedExpanded) {
                        ForEach(self.sidebarPinnedItemsManager.items) { item in
                            self.sidebarPinnedRow(item)
                        }
                        .onMove { source, destination in
                            self.sidebarPinnedItemsManager.move(from: source, to: destination)
                        }
                    } header: {
                        Text(String(localized: "Pinned"))
                    }
                }

                Section(isExpanded: self.$isPlaylistsExpanded) {
                    self.navigationRow(.libraryPlaylists)
                        .accessibilityIdentifier(AccessibilityID.Sidebar.libraryPlaylistsItem)

                    ForEach(self.libraryPlaylists) { playlist in
                        self.libraryPlaylistRow(playlist)
                    }
                } header: {
                    self.playlistsSectionHeader
                }
            }
        }
        .listStyle(.sidebar)
        .compatTranslucentSidebar()
        .accessibilityIdentifier(AccessibilityID.Sidebar.container)
        .compatBottomBar {
            // Profile section at bottom
            SidebarFooterView()
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    }

    private var hasPersonalAccount: Bool {
        self.authService.hasPersonalAccount
    }

    private var currentSidebarSelection: SidebarSelection? {
        if let pinnedSelection {
            switch self.pinnedSelectionOrigin {
            case .pinned:
                return .pinned(pinnedSelection)
            case .libraryPlaylists:
                return .libraryPlaylist(contentId: pinnedSelection.contentId)
            }
        }

        if let selection {
            return .navigation(selection)
        }

        return nil
    }

    private func navigationRow(_ item: NavigationItem) -> some View {
        LiltSidebarRow(
            title: item.displayName,
            systemImage: item.icon,
            isSelected: self.currentSidebarSelection == .navigation(item)
        ) {
            self.selectNavigationItem(item)
        }
    }

    private func selectNavigationItem(_ item: NavigationItem) {
        let newSelection = SidebarSelection.navigation(item)
        if self.currentSidebarSelection == newSelection {
            self.onReselectNavigationItem?(item)
            return
        }
        self.selection = item
        self.pinnedSelection = nil
    }

    private func selectPinnedItem(_ item: SidebarPinnedItem) {
        self.selectPlaylistRoute(item, newSelection: .pinned(item), origin: .pinned)
    }

    private func selectLibraryPlaylist(_ playlist: Playlist) {
        let item = SidebarPinnedItem.from(playlist)
        self.selectPlaylistRoute(
            item,
            newSelection: .libraryPlaylist(contentId: item.contentId),
            origin: .libraryPlaylists
        )
    }

    private func selectPlaylistRoute(
        _ item: SidebarPinnedItem,
        newSelection: SidebarSelection,
        origin: PinnedSelectionOrigin
    ) {
        if self.currentSidebarSelection == newSelection {
            self.onReselectPinnedItem?(item)
            return
        }
        self.pinnedSelectionOrigin = origin
        self.selection = nil
        self.pinnedSelection = item
    }

    /// Playlists saved in the user's library, minus Liked Music (it has its own row).
    private var libraryPlaylists: [Playlist] {
        guard let libraryViewModel else { return [] }
        return libraryViewModel.playlists.filter { !LikedMusicPlaylist.matches(id: $0.id) }
    }

    private var hasSavedPodcasts: Bool {
        !(self.libraryViewModel?.podcastShows.isEmpty ?? true)
    }

    private func libraryPlaylistRow(_ playlist: Playlist) -> some View {
        let item = SidebarPinnedItem.from(playlist)
        return LiltSidebarRow(
            title: playlist.title,
            systemImage: item.systemImage,
            isSelected: self.currentSidebarSelection == .libraryPlaylist(contentId: item.contentId),
            artworkURL: playlist.thumbnailURL
        ) {
            self.selectLibraryPlaylist(playlist)
        }
        .contextMenu {
            if !self.sidebarPinnedItemsManager.items.contains(where: { $0.contentId == item.contentId }) {
                Button {
                    self.sidebarPinnedItemsManager.add(item)
                } label: {
                    Label(String(localized: "Add to Sidebar"), systemImage: "pin")
                }
            }
        }
    }

    private var playlistsSectionHeader: some View {
        HStack {
            Text(String(localized: "Playlists"))

            Spacer()

            if self.isCreatingPlaylist {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            } else {
                Button {
                    self.presentCreatePlaylistDialog()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(self.isHoveringPlaylistsHeader ? 1 : 0)
                .padding(.trailing, 8)
                .help(String(localized: "Create Playlist"))
                .accessibilityLabel(String(localized: "Create Playlist"))
            }
        }
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                self.isHoveringPlaylistsHeader = hovering
            }
        }
    }

    private func presentCreatePlaylistDialog() {
        guard !self.isCreatingPlaylist else { return }
        let owner = self.playerService.currentAccountMutationOwner

        SongActionsHelper.presentCreatePlaylistDialog(
            informativeText: "Create a new playlist.",
            request: SongActionsHelper.PlaylistCreationRequest(
                client: self.client,
                videoIds: [],
                whileValid: { self.playerService.acceptsAccountMutationOwner(owner) }
            ),
            onWillCreate: {
                guard !self.isCreatingPlaylist else { return false }
                self.isCreatingPlaylist = true
                return true
            },
            completion: { result in
                self.isCreatingPlaylist = false
                guard self.playerService.acceptsAccountMutationOwner(owner) else { return }

                switch result {
                case let .success(playlist):
                    let pinnedItem = SidebarPinnedItem.from(playlist)
                    self.sidebarPinnedItemsManager.add(pinnedItem)
                    self.selectPinnedItem(pinnedItem)
                case let .failure(failure):
                    SongActionsHelper.presentPlaylistCreationError(failure)
                }
            }
        )
    }

    private func sidebarPinnedRow(_ item: SidebarPinnedItem) -> some View {
        LiltSidebarRow(
            title: item.title,
            systemImage: item.systemImage,
            isSelected: self.currentSidebarSelection == .pinned(item),
            artworkURL: item.playlistRoute.thumbnailURL
        ) {
            self.selectPinnedItem(item)
        }
        .contextMenu {
            Button {
                self.sidebarPinnedItemsManager.moveUp(contentId: item.contentId)
            } label: {
                Label(String(localized: "Move Up"), systemImage: "chevron.up")
            }

            Button {
                self.sidebarPinnedItemsManager.moveDown(contentId: item.contentId)
            } label: {
                Label(String(localized: "Move Down"), systemImage: "chevron.down")
            }

            Button {
                self.sidebarPinnedItemsManager.moveToTop(contentId: item.contentId)
            } label: {
                Label(String(localized: "Move to Top"), systemImage: "arrow.up.to.line")
            }

            Button {
                self.sidebarPinnedItemsManager.moveToEnd(contentId: item.contentId)
            } label: {
                Label(String(localized: "Move to End"), systemImage: "arrow.down.to.line")
            }

            Divider()

            Button(role: .destructive) {
                if self.pinnedSelection?.contentId == item.contentId {
                    self.pinnedSelection = nil
                }
                self.sidebarPinnedItemsManager.remove(contentId: item.contentId)
            } label: {
                Label(String(localized: "Remove from Sidebar"), systemImage: "sidebar.left")
            }
        }
    }
}

#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    Sidebar(selection: .constant(.home), pinnedSelection: .constant(nil), client: client)
        .frame(width: 220)
        .environment(authService)
        .environment(PlayerService())
        .environment(SidebarPinnedItemsManager(skipLoad: true))
}
