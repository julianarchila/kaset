import SwiftUI

// MARK: - LiltSidebarRow

/// A stable Apple-Music-style sidebar row.
///
/// SwiftUI's source-list `NavigationLink` chrome changes when the sidebar list
/// becomes the active control: selected rows switch to the system accent fill
/// and symbols become selected-text colored. Lilt drives detail content from
/// explicit selection state, so use a plain button row with our own selected
/// background and system-accent symbol instead of relying on `NavigationLink`'s
/// active/inactive source-list styling.
struct LiltSidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    /// Optional artwork (playlist or album cover) shown instead of the symbol.
    var artworkURL: URL?
    let action: () -> Void

    private static let artworkSize: CGFloat = 20

    var body: some View {
        Button(action: self.action) {
            Label {
                Text(self.title)
                    .lineLimit(1)
                    .fontWeight(self.isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)
            } icon: {
                if let artworkURL {
                    self.artwork(url: artworkURL)
                } else {
                    Image(systemName: self.systemImage)
                        .foregroundStyle(PackageResourceLookup.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
        .listRowBackground(self.selectionBackground)
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
    }

    private func artwork(url: URL) -> some View {
        CachedAsyncImage(
            url: url,
            targetSize: CGSize(width: Self.artworkSize * 2, height: Self.artworkSize * 2)
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image(systemName: self.systemImage)
                .foregroundStyle(PackageResourceLookup.accent)
        }
        .frame(width: Self.artworkSize, height: Self.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if self.isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.22))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        }
    }
}

#Preview {
    List {
        LiltSidebarRow(
            title: "Home",
            systemImage: "house",
            isSelected: true,
            action: {}
        )
        LiltSidebarRow(
            title: "Search",
            systemImage: "magnifyingglass",
            isSelected: false,
            action: {}
        )
    }
    .listStyle(.sidebar)
    .frame(width: 220)
}
