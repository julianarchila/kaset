import SwiftUI

// MARK: - HomeFeaturedItem

/// A playlist or album promoted to a large card at the top of Home.
struct HomeFeaturedItem: Identifiable, Equatable {
    let item: HomeSectionItem
    /// Title of the Home shelf the item came from ("Listen again", "Mixed for you").
    let sourceTitle: String

    var id: String {
        self.item.id
    }
}

// MARK: - HomeFeaturedPicker

/// Chooses the featured cards for the top of Home.
enum HomeFeaturedPicker {
    static let defaultLimit = 3

    /// Picks up to `limit` items, preferring one per card shelf (in Home order)
    /// so the cards represent different shelves, then filling any remaining
    /// slots with further items from those shelves.
    ///
    /// Playlists and albums come before songs within a shelf (Listen again is
    /// often all songs). Song-row shelves (Quick picks), charts, artists, and
    /// music videos are never featured.
    static func pick(from sections: [HomeSection], limit: Int = defaultLimit) -> [HomeFeaturedItem] {
        let shelves = sections.filter { !$0.isListShelf && !$0.isChart }
        var picked: [HomeFeaturedItem] = []
        var seenIDs = Set<String>()

        func take(from section: HomeSection) -> Bool {
            let unseen = section.items.filter { !seenIDs.contains($0.id) && Self.isFeaturable($0) }
            let collection = unseen.first { item in
                switch item {
                case .playlist, .album: true
                case .song, .artist: false
                }
            }
            guard let candidate = collection ?? unseen.first else { return false }
            seenIDs.insert(candidate.id)
            picked.append(HomeFeaturedItem(item: candidate, sourceTitle: section.title))
            return true
        }

        // One per shelf first, then keep cycling through the shelves.
        var madeProgress = true
        while picked.count < limit, madeProgress {
            madeProgress = false
            for section in shelves where picked.count < limit {
                if take(from: section) {
                    madeProgress = true
                }
            }
        }

        return picked
    }

    private static func isFeaturable(_ item: HomeSectionItem) -> Bool {
        switch item {
        case .playlist, .album:
            true
        case .song:
            !item.isVideoSong
        case .artist:
            false
        }
    }
}

// MARK: - HomeFeaturedRow

/// Up to three large cards with Play and Shuffle buttons, shown below the
/// Home greeting. Drops trailing cards when the window is too narrow.
struct HomeFeaturedRow: View {
    let items: [HomeFeaturedItem]
    let open: (HomeSectionItem) -> Void
    let play: (HomeSectionItem) -> Void
    let shuffle: (HomeSectionItem) -> Void

    private static let spacing: CGFloat = 16

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: self.items.count, through: 1, by: -1)), id: \.self) { count in
                HStack(spacing: Self.spacing) {
                    ForEach(self.items.prefix(count)) { featured in
                        HomeFeaturedCard(
                            featured: featured,
                            open: { self.open(featured.item) },
                            play: { self.play(featured.item) },
                            shuffle: { self.shuffle(featured.item) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - HomeFeaturedCard

private struct HomeFeaturedCard: View {
    let featured: HomeFeaturedItem
    let open: () -> Void
    let play: () -> Void
    let shuffle: () -> Void

    @State private var isHovering = false

    /// Shuffle only applies to playlists and albums.
    private var canShuffle: Bool {
        switch self.featured.item {
        case .playlist, .album: true
        case .song, .artist: false
        }
    }

    private static let artworkSize: CGFloat = 104
    private static let minimumWidth: CGFloat = 250

    var body: some View {
        HStack(spacing: 16) {
            self.artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "From \(self.featured.sourceTitle)"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(self.featured.item.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(1)

                if let subtitle = self.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                self.controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.artworkSize)
        .padding(14)
        // ViewThatFits measures ideal widths; pin it so long titles do not
        // make three cards look too wide to fit.
        .frame(minWidth: Self.minimumWidth, idealWidth: Self.minimumWidth, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(self.isHovering ? 0.1 : 0.07))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: self.open)
        .onHover { self.isHovering = $0 }
        .animation(AppAnimation.quick, value: self.isHovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(self.featured.item.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { self.open() }
    }

    private var artwork: some View {
        CachedAsyncImage(
            url: self.featured.item.thumbnailURL?.highQualityThumbnailURL,
            targetSize: CGSize(width: Self.artworkSize * 2, height: Self.artworkSize * 2)
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
        }
        .frame(width: Self.artworkSize, height: Self.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button(action: self.play) {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Play"))
            .accessibilityLabel(String(localized: "Play"))

            if self.canShuffle {
                Button(action: self.shuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Shuffle"))
                .accessibilityLabel(String(localized: "Shuffle"))
            }
        }
    }

    private var subtitle: String? {
        switch self.featured.item {
        case let .album(album):
            let artists = album.artistsDisplay
            return artists.isEmpty ? String(localized: "Album") : "\(String(localized: "Album")) · \(artists)"
        case let .playlist(playlist):
            return playlist.author?.name
        case let .song(song):
            return "\(String(localized: "Song")) · \(song.artistsDisplay)"
        case .artist:
            return self.featured.item.subtitle
        }
    }
}
