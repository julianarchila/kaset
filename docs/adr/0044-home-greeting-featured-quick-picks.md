# ADR-0044: Home greeting, featured cards, and Quick picks grid

## Status

Accepted

## Context

Home was a vertical list of horizontal shelves under a "Home" toolbar title.
The fork's target design (Apple Music style) opens with a time-of-day greeting,
a row of large cards with Play and Shuffle, and Quick picks as a dense song
grid.

## Decision

- **Greeting.** `HomeView.greeting(for:)` returns "Good morning" (05–11),
  "Good afternoon" (12–17), or "Good evening". It is the page title; the
  toolbar title is removed on Home (`.toolbar(removing: .title)`), while the
  window title stays "Home" for the Window menu.
- **Featured cards.** `HomeFeaturedPicker` takes one item per card shelf in
  Home order (a playlist or album, else the first audio song), then fills up to
  three cards from the same shelves. Song-row shelves, charts, artists, and
  music videos are never featured. Shelf titles come from YouTube and are
  localized by YouTube, so selection uses structure, not titles. The picks are
  frozen once three are found so continuation pages loading below don't swap
  them; they are recomputed when Home reloads. Shuffle fetches the playlist or
  album tracks and plays them in random order; songs have no Shuffle button.
- **Quick picks grid.** YouTube Music sends Quick picks as a carousel of
  `musicResponsiveListItemRenderer` rows, unlike card shelves
  (`musicTwoRowItemRenderer`). `HomeResponseParser` marks such all-song
  carousels as `HomeSection.isListShelf`, verified against
  `Tests/LiltTests/Fixtures/home_response.json`. Home renders them as an
  adaptive grid of compact rows: four rows of as many 260 pt columns as fit,
  with Show All / Show Less. Durations show only when the response has them
  (Home rows usually don't).
- Other shelves keep the existing AppKit-backed carousels (ADR-0038).

## Consequences

- Featured cards duplicate items that also appear in their shelf below.
- When a library has no playlist/album shelves on the first Home page, all
  three cards can come from Listen again.
