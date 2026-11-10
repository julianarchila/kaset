---
name: playback-webview-debugging
description: Use when playback, auth recovery, queue sync, or hidden WebView state diverges from native Swift state and you need to debug the DRM playback WebView, bridge events, or cookie/auth behavior.
metadata:
  short-description: Debug playback WebView state
---

# Playback WebView Debugging

Typical symptoms: playback starts, stops, or advances unexpectedly; API calls return 401/403 because auth looks stale; WebView metadata drifts from the native queue; or you need to see JavaScript bridge events or DOM/player state.

## Runtime Workflow

1. Reproduce with the packaged app or `Scripts/compile_and_run.sh` (see the `dev-loop-packaging` skill).
2. Watch runtime logs in the Xcode Console with the filters `subsystem:com.julianarchila.Lilt category:Player` and `subsystem:com.julianarchila.Lilt category:Auth` (see `DiagnosticsLogger`). `.info`/`.debug` lines don't reliably surface from the sandbox, so for timing or ordering questions use a file trace as described under Debugging & Measurement in `AGENTS.md`.
3. In debug builds, confirm `webView.isInspectable = true`, then inspect the player WebView with Safari Web Inspector.
4. To simulate auth expiry, delete both `__Secure-3PAPISID` and `SAPISID` with Safari Web Inspector's storage tools, then trigger an authenticated API call. `WebKitManager.getSAPISID()` falls back to `SAPISID`, so deleting only one keeps the session alive.
5. If auth cookies or headers look wrong, run `swift run api-explorer auth` and compare against the exported cookie state.

## Landmarks

- `docs/testing.md`
- `docs/playback.md`
- `Sources/Lilt/Views/MiniPlayerWebView.swift`
- `Sources/Lilt/Views/SingletonPlayerWebView+ObserverScript.swift`
- `Sources/Lilt/Views/SingletonPlayerWebView+NavigationState.swift`
- `Sources/Lilt/Views/SingletonPlayerWebView+QueueInjection.swift`
- `Sources/Lilt/Services/Player/PlayerService.swift`
- `Sources/Lilt/Services/Player/PlayerService+WebPlaybackIdentity.swift`
- `Sources/Lilt/Services/Player/PlayerService+WebQueueSync.swift`
- `Sources/Lilt/Services/Player/PlayerService+QueueNavigationRecovery.swift`
- `Sources/Lilt/Services/WebKit/WebKitManager.swift`
