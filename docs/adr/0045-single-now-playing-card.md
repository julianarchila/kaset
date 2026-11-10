# ADR-0045: One Now Playing card (release the native claim while WebKit has a session)

## Status

Accepted

## Context

On macOS 26, Control Center's Now Playing menu showed two KasetFork entries
while paused: WebKit's rich card and the app's minimal "native claim"
(title + artist) added upstream in PR #387 so the Play key would resume
Kaset instead of Apple Music after a pause.

Measured with a MediaRemote probe (MediaRemote's private API, read-only):

- WebKit publishes Now Playing from its **GPU process**
  (`com.apple.WebKit.GPU/<bundle id>`), which macOS lists as a client separate
  from the app process. The two never replace each other, contrary to the
  assumption in the original claim code.
- WebKit keeps its session while paused (measured 15+ minutes) and stays the
  elected Now Playing client; it only lacks one while a page loads (about 4 s
  at cold start, about 1 s per track change).
- The menu bar Now Playing list shows every client with metadata, including
  ones marked `NeverVisible`.

## Decision

`NowPlayingManager` releases the native claim whenever WebKit reports its own
Now Playing session, read from the `WKWebView._hasActiveNowPlayingSession` SPI
through KVO (`WebKitNowPlayingSessionObserver`). The claim still covers the
gaps where WebKit has no session. If the SPI is unavailable, the observed value
is `nil` and the previous behavior applies.

Verified in a debug build with the probe and screenshots of the menu bar Now
Playing list: one KasetFork entry while paused, playing, and after a track
change.

### Rejected: native-only card

Making the app's `MPNowPlayingInfoCenter` card the only one would allow
like/dislike, shuffle, and repeat buttons (macOS 26 registers those commands
for a native client). WebKit has no public API, SPI, or feature flag to stop
publishing; page-side changes that make the media element ineligible also
silence it. Hosting the WebView in an always-key offscreen window makes WebKit
mark its client `NeverVisible`, which hides it from Control Center's module but
**not** from the menu bar Now Playing list, so two cards remained.

## Consequences

- Customizing the card is limited to what the web Media Session API exposes
  (metadata, artwork, and play/pause/next/previous/seek actions).
- Depends on a WebKit SPI; if it disappears, the duplicate card returns while
  paused, and nothing else breaks.
- Known pre-existing issue, unchanged: after pausing from the app's own
  controls, the Play media key does not resume playback (it does after a pause
  made with the media key).
