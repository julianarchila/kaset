<h1 align="center">Lilt</h1>

<p align="center">A native macOS client for YouTube Music, built with Swift and SwiftUI. Lilt is a personal fork of <a href="https://github.com/sozercan/kaset">Kaset</a>.</p>

<p align="center">
  <a href="https://trendshift.io/repositories/16570?utm_source=repository-badge&amp;utm_medium=badge&amp;utm_campaign=badge-repository-16570"><img src="https://trendshift.io/api/badge/repositories/16570" alt="sozercan/kaset | Trendshift" width="200" height="44"/></a>
</p>

<p align="center"><img src="docs/screenshot-ytm.png" alt="Lilt YouTube Music screenshot"></p>

## Features

### Music

- 🎵 **Native macOS Experience** — Apple Music-style UI with Liquid Glass player bars, and clean sidebar navigation
- 🎧 **YouTube Music Support** — Full playback of DRM-protected YouTube Music content via your existing Premium subscription

### Playback

- 🎚️ **Equalizer** — System-wide 6-band parametric EQ with Spotify-style presets, applied to WebKit playback output
- 📜 **Lyrics** — View plain and synced lyrics with line-by-line highlighting when timing data is available
- 📃 **Queue Management** — View, reorder, shuffle, and clear your playback queue
- 🔀 **Smart Shuffle** — Beyond plain shuffle: blends suggested tracks into the queue based on what you're playing, with cadence and how many are queued ahead configurable in Settings
- 🔊 **Background Audio** — Music continues playing when the window is closed; stops on quit
- 🎶 **Track Notifications** — Get notified when a new track starts playing

### Library & Discovery

- 📚 **Library Access** — Browse playlists, liked songs, and subscribed podcasts; create playlists, add songs to playlists, and delete your own playlists
- 🧭 **Explore** — Discover new releases, charts, and moods & genres
- 🎙️ **Podcasts** — Listen to your saved podcasts with episode progress tracking
- 🔍 **Search** — Find songs, albums, artists, playlists, and podcasts
- 🕓 **History** — Revisit recently played tracks

### macOS Integration

- 🎛️ **System Integration** — Now Playing in Control Center, media key support, Dock menu controls
- ⌨️ **[Keyboard Shortcuts](docs/keyboard-shortcuts.md)** — Full keyboard control for playback, navigation, and more
- 📳 **Haptic Feedback** — Tactile feedback on Force Touch trackpads for player controls and navigation
- 📣 **Share** — Share songs, playlists, albums, and artists via the native macOS share sheet
- 🌍 **Localized** — UI available in 18 languages (Arabic, Chinese (Simplified), Chinese (Traditional), Dutch, English, French, German, Indonesian, Italian, Japanese, Korean, Polish, Portuguese, Russian, Spanish, Swedish, Turkish, Ukrainian); change under Settings → General → Language

### Automation & Extensibility

- 🔗 **[URL Scheme](docs/url-scheme.md)** — Open songs directly with `lilt://play?v=VIDEO_ID`; app-targeted YouTube watch and `youtu.be` links play through YouTube Music
- ⚡️ **[Shortcuts, Siri & Spotlight](docs/shortcuts.md)** — Native actions to play music, playlists, and albums, control playback, and rate songs; Siri phrases; Library playlists and albums in Spotlight
- 🤖 **[AppleScript Support](docs/applescript.md)** — Automate playback with scripts, Raycast, Alfred, and Shortcuts

## Requirements

- macOS 15.4 or later
- [Google](https://accounts.google.com) account for YouTube Music personalization

## Installation

Lilt has no published releases. Build it from source with Xcode 26 or later:

```bash
git clone https://github.com/julianarchila/kaset.git
cd kaset
Scripts/build-app.sh release
cp -R .build/app/Lilt.app /Applications/
```

The build is signed ad hoc rather than with a Developer ID, so it stores sign-in cookies in a file inside its sandbox container instead of the Keychain.

### Opening Lilt for the First Time

If macOS warns that the app can't be verified the first time you open it, allow it once:

1. Try to open Lilt, then close the warning by clicking **Done**.
2. Open **System Settings** and go to **Privacy & Security**.
3. Scroll down to the **Security** section and click **Open Anyway** next to Lilt.
4. Click **Open Anyway** again in the pop-up, then enter your password or use Touch ID.

Or remove the quarantine flag from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Lilt.app
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, architecture, and coding guidelines.

We welcome AI-assisted contributions! You can submit traditional PRs or **prompt requests** — share the AI prompt that generates your changes, and maintainers can review the intent before running the code. See the [AI-Assisted Contributions](CONTRIBUTING.md#ai-assisted-contributions--prompt-requests) section for details.

## Disclaimer

Lilt is an unofficial application and not affiliated with YouTube or Google Inc. in any way. "YouTube", "YouTube Music" and the "YouTube Logo" are registered trademarks of Google Inc.
