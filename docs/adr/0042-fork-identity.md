# ADR-0042: Fork identity and scope

## Status

Accepted

## Context

This repository is a personal, independently maintained fork of
[sozercan/kaset](https://github.com/sozercan/kaset). The upstream app can stay
installed next to the fork (`/Applications/Kaset.app`), and the fork is built
and run locally without a paid Apple Developer account.

Several upstream settings tied a fork build to the upstream app:

- The bundle ID `com.sertacozercan.Kaset` gave both apps one sandbox
  container, one WebKit cookie jar, and shared preferences, so each launch
  overwrote the other's session.
- Sparkle checked the upstream appcast with the upstream signing key. A fork
  build could auto-update itself into the upstream release and lose every fork
  change.
- Both apps registered the `kaset://` URL scheme.
- "What's New" read release notes from the upstream GitHub repository.
- `Scripts/compile_and_run.sh` killed any process named `Kaset`, including the
  upstream app.

## Decision

- The fork has its own identity, set in `Scripts/build-app.sh`:
  - Display name and bundle file: `KasetFork` (temporary until a final name
    is chosen).
  - Bundle ID: `com.julianarchila.KasetFork`, and
    `com.julianarchila.KasetFork.debug` for packaged debug builds.
  - URL scheme: `kasetfork://`.
- The SwiftPM product, module, and executable keep the name `Kaset`. Renaming
  them would change hundreds of files without any user-visible benefit.
- Sparkle, the appcast, release signing scripts, the release, dev-build, Pages,
  and automerge workflows, the Homebrew Cask, and the marketing website are
  removed. The fork is built from source, so it has no update channel. This
  supersedes ADR-0007.
- "What's New" is removed, since the fork publishes no GitHub releases.
- The fork does not track upstream. Fixes are cherry-picked when useful.
- YouTube video mode removed. The fork is YouTube Music only: the video
  source and its sidebar toggle, the YouTube client, video player and its
  floating window, Ask Gemini, and the `YouTubeAskCore` target are gone. The
  YouTube Music video window stays. This
  supersedes ADR-0020, ADR-0022, and ADR-0032. Media keys, menus, and App
  Intents always control the music player. `www.youtube.com/watch` and
  `youtu.be` links play the video ID as a YouTube Music song. Mix tracklists
  still read chapters and descriptions from regular YouTube's `next` endpoint
  through the small `YouTubeWatchNextFetcher`, because the YouTube Music
  `next` endpoint omits them.
- AI features removed: the Command Bar (⌘K), lyrics explanations, playlist
  refinement, the Intelligence settings tab, and every Foundation Models
  dependency. This supersedes ADR-0004, ADR-0005, ADR-0015, and ADR-0016.
- Last.fm and web extensions removed: Last.fm scrobbling, its settings tab,
  and the Cloudflare Worker proxy; user-managed WebKit extensions and their
  settings tab. The playback WebViews no longer attach a
  `WKWebExtensionController`. Mix tracklists keep segmenting the seek bar
  through `MixTracklistParser` and `NowPlayingTracklistProvider`. This
  supersedes ADR-0011 and ADR-0014.
- The app follows the user's macOS accent color instead of Kaset's pink
  brand accent: the `AccentColor` asset and `NSAccentColorName` are gone, and
  `PackageResourceLookup.accent` is `NSColor.controlAccentColor`.

## Consequences

- Fork and upstream builds are fully isolated and can run side by side.
- Changing the bundle ID again later costs one sign-in and resets local
  preferences, because macOS keys the sandbox container on the bundle ID.
- Sparkle is no longer a dependency; the app has no third-party dependencies.
- Restoring auto-updates later requires a new EdDSA key, an appcast hosted by
  the fork, and Developer ID signing.
