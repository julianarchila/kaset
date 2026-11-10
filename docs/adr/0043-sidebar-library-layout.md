# ADR-0043: Sidebar layout with Library destinations

## Status

Accepted

## Context

The sidebar listed Search and Home, an always-open Discover section, a
Collection section with a combined Library page (filter chips for playlists,
albums, uploads, artists, and podcasts), and manually pinned items under a
"Playlists" header. Reaching albums or artists took two clicks, and the user's
own playlists only appeared after pinning them by hand.

## Decision

- Top: Search, Home, and New Releases.
- Discover (Explore, Charts, Moods & Genres, Podcasts) is a collapsible section,
  collapsed by default. Sections use the native sidebar disclosure control:
  a custom header button cannot toggle `Section(isExpanded:)` reliably,
  because the binding it receives inside a sidebar `List` header never updates
  the real state (measured with a trace).
- Library: Artists, Albums, Liked Music, History, and Saved Podcasts (only when
  the library has podcast shows). The combined `NavigationItem.library` is
  replaced by `libraryArtists`, `libraryAlbums`, `libraryPodcasts`, and
  `libraryPlaylists`. `LibraryView` takes a `Scope` that fixes the filter and
  hides the chips; the All Playlists scope also shows the Uploads tile.
- Pinned: manually pinned items, shown only when there are any.
- Playlists: All Playlists, then every playlist in the library except Liked
  Music, with artwork. Library playlists reuse the pinned-item detail route;
  the sidebar remembers which section the selection came from so only the
  clicked row is highlighted.
- The profile footer uses `compatBottomBar` (`safeAreaBar` on macOS 26) so
  rows scrolling beneath it are blurred.
- ⌘3 now opens All Playlists.

Recently Added and Songs are planned for a follow-up after their endpoints are
verified with the API explorer.

## Consequences

- Section expansion persists in `@AppStorage` (`sidebar.*Expanded`). UI tests
  launch with `-sidebar.discoverExpanded YES` to reach Discover rows.
- The combined Library page with chips is no longer reachable from the
  sidebar; `LibraryView` without a scope still supports it.
