<h1 align="center">Lilt</h1>

<p align="center">My custom, minimal fork of <a href="https://github.com/sozercan/kaset">Kaset</a>: a native macOS client for YouTube Music, built with Swift and SwiftUI, that tries to look and feel like a default Mac app.</p>

> [!NOTE]
> Lilt is a personal project built on top of **[Kaset](https://github.com/sozercan/kaset)** by [Sertaç Özercan](https://github.com/sozercan) and contributors. Almost everything that makes it work — the YouTube Music API client, DRM playback through WebKit, the queue, lyrics, the equalizer, and macOS integration — comes from Kaset. If you want the full-featured, maintained app, use Kaset.

## Why a fork

I like Kaset, but I only use YouTube Music and wanted a smaller app with a more "stock macOS" look. Lilt removes what I don't use and reworks the main screens, while staying close to Kaset's architecture.

### Removed

- Regular YouTube (video) mode, including Ask Gemini
- Apple Intelligence features (command bar, lyrics explanations, playlist refinement)
- Last.fm scrobbling and its Cloudflare Worker
- WebKit web extensions (uBlock Origin Lite, SponsorBlock)
- Sparkle auto-updates, What's New, and the Charts, Moods & Genres, New Releases, and Podcasts pages (Explore covers them)

### Changed

- **Sidebar**: native search field, Home and Explore at the top, Library (Artists, Albums, Liked Music, History, Saved Podcasts), Pinned items, and every playlist in your library with its artwork
- **Home**: a time-of-day greeting, three featured cards with Play and Shuffle, and Quick picks as a song grid
- **System accent color** everywhere instead of Kaset's pink
- **One Now Playing card** in Control Center instead of two
- New name, bundle ID (`com.julianarchila.Lilt`), URL scheme (`lilt://`), and icon, so Lilt and Kaset can be installed side by side

Design decisions are recorded in [`docs/adr/`](docs/adr/), starting with [ADR-0042](docs/adr/0042-fork-identity.md).

## Features

- 🎧 **YouTube Music playback** — DRM-protected content through your existing Premium subscription
- 📚 **Library** — Playlists, albums, artists, liked music, saved podcasts, and history; create playlists, add songs, and pin anything to the sidebar
- 🔍 **Search** — Songs, albums, artists, playlists, and podcasts, with suggestions
- 📃 **Queue** — View, reorder, shuffle, clear, and Smart Shuffle
- 📜 **Lyrics** — Plain and synced lyrics with line-by-line highlighting
- 🎚️ **Equalizer** — 6-band parametric EQ applied to playback output
- 🎛️ **macOS integration** — Now Playing, media keys, Dock menu, notifications, haptics, and the share sheet
- ⌨️ **[Keyboard shortcuts](docs/keyboard-shortcuts.md)**, **[URL scheme](docs/url-scheme.md)**, **[Shortcuts, Siri & Spotlight](docs/shortcuts.md)**, and **[AppleScript](docs/applescript.md)**
- 🌍 **Localized** in 18 languages

## Requirements

- macOS 15.4 or later (Liquid Glass on macOS 26)
- A Google account with YouTube Music (Premium for full playback)
- Xcode 26 or later to build

## Build and install

Lilt has no published releases. Build it from source:

```bash
git clone https://github.com/julianarchila/kaset.git lilt
cd lilt
Scripts/build-app.sh release
ditto .build/app/Lilt.app /Applications/Lilt.app
```

The build is signed ad hoc rather than with a Developer ID, so it stores its sign-in cookies in a file inside its sandbox container instead of the Keychain.

If macOS says the app can't be verified the first time you open it, open **System Settings → Privacy & Security** and click **Open Anyway** next to Lilt, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Lilt.app
```

## Development

```bash
swift build                              # Build
swift test --skip LiltUITests            # Unit tests
swiftlint --strict && swiftformat .      # Lint and format (SwiftFormat 0.63.1)
Scripts/compile_and_run.sh               # Package a debug build and relaunch it
```

See [AGENTS.md](AGENTS.md) for project rules and [CONTRIBUTING.md](CONTRIBUTING.md) for architecture notes.

## Credits

Lilt exists because of **[Kaset](https://github.com/sozercan/kaset)**, created by [Sertaç Özercan](https://github.com/sozercan) with many contributors, and released under the MIT License. The original copyright notice is kept in [LICENSE](LICENSE), as the license requires. Changes made in this fork are also available under the MIT License.

## Disclaimer

Lilt is an unofficial application and is not affiliated with Kaset's maintainers, YouTube, or Google Inc. "YouTube", "YouTube Music", and the "YouTube Logo" are registered trademarks of Google Inc.
