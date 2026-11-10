# Keyboard Shortcuts

Kaset provides keyboard control for playback and navigation while preserving standard macOS window shortcuts.

## Playback

| Shortcut | Action                              |
| -------- | ----------------------------------- |
| `Space`  | Play / Pause                        |
| `⌘→`     | Next track                          |
| `⌘←`     | Previous track                      |
| `⌘↑`     | Volume up                           |
| `⌘↓`     | Volume down                         |
| `⌘S`     | Toggle shuffle (off/on; the player-bar control also cycles to Smart Shuffle) |
| `⌘R`     | Cycle repeat mode (Off → All → One) |
| `⇧⌘M`    | Switch to Mini Player               |
| `Esc`    | Close the full screen Now Playing view |

Mute is still available from the Playback menu and AppleScript, but Kaset intentionally does not assign a default mute shortcut so the native macOS minimize shortcut (`⌘M`) continues to work.

## Navigation

| Shortcut | Action           |
| -------- | ---------------- |
| `⌘1`     | Go to Home       |
| `⌘2`     | Go to Explore    |
| `⌘3`     | Go to Library    |
| `⌘F`     | Go to Search     |
| `⌘K`     | Open Command Bar |
| `⇧⌘R`    | Refresh Home suggestions |

`⇧⌘R` refreshes the Home feed and bypasses its cached suggestions.

With macOS Keyboard navigation enabled, `Tab` moves between shelf cards and each
song's Like/Unlike control. `⇧Tab` moves in reverse. `Return` or `Space` activates
the focused card or toggles the focused Like/Unlike control.
