import SwiftUI

// MARK: - HomeQuickPicksSection

/// A song-row shelf (YouTube Music's "Quick picks") laid out as a multi-column
/// grid of compact rows instead of a horizontal carousel.
struct HomeQuickPicksSection: View {
    let section: HomeSection
    let client: any YTMusicClientProtocol
    let play: (HomeSectionItem, Int) -> Void
    let navigate: ContextMenuNavigate

    @State private var isExpanded = false
    @State private var columnCount = 3

    /// Rows shown before "Show All".
    static let collapsedRowCount = 4
    private static let minimumColumnWidth: CGFloat = 260
    private static let columnSpacing: CGFloat = 24

    /// Number of adaptive grid columns that fit in `width`.
    static func columnCount(forWidth width: CGFloat) -> Int {
        max(1, Int((width + self.columnSpacing) / (self.minimumColumnWidth + self.columnSpacing)))
    }

    private var collapsedItemCount: Int {
        self.columnCount * Self.collapsedRowCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header

            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: Self.minimumColumnWidth),
                    spacing: Self.columnSpacing,
                    alignment: .leading
                )],
                alignment: .leading,
                spacing: 2
            ) {
                ForEach(Array(self.visibleItems.enumerated()), id: \.element.id) { index, item in
                    if case let .song(song) = item {
                        HomeQuickPickRow(
                            song: song,
                            play: { self.play(item, index) },
                            menuContent: {
                                HomeSectionItemContextMenu(
                                    item: item,
                                    client: self.client,
                                    play: { self.play(item, index) },
                                    navigate: self.navigate
                                )
                            }
                        )
                    }
                }
            }
            .onGeometryChange(for: Int.self) { proxy in
                Self.columnCount(forWidth: proxy.size.width)
            } action: { newCount in
                self.columnCount = newCount
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(self.section.title)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            if self.section.items.count > self.collapsedItemCount {
                Button(self.isExpanded ? String(localized: "Show Less") : String(localized: "Show All")) {
                    withAnimation(AppAnimation.quick) {
                        self.isExpanded.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var visibleItems: [HomeSectionItem] {
        self.isExpanded ? self.section.items : Array(self.section.items.prefix(self.collapsedItemCount))
    }
}

// MARK: - HomeQuickPickRow

private struct HomeQuickPickRow<MenuContent: View>: View {
    let song: Song
    let play: () -> Void
    @ViewBuilder let menuContent: () -> MenuContent

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            SongThumbnailView(song: self.song, size: 44, cornerRadius: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.song.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(self.song.artistsDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                self.menuContent()
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(self.isHovering ? 1 : 0.6)
            .accessibilityLabel(String(localized: "More"))

            if self.song.duration != nil {
                Text(self.song.durationDisplay)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(self.isHovering ? 0.07 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: self.play)
        .onHover { self.isHovering = $0 }
        .contextMenu { self.menuContent() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: String(localized: "Play"), self.play)
    }
}
