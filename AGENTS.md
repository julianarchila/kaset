# AGENTS.md

Lilt is a native macOS client for YouTube Music, written in Swift 6 and SwiftUI. It targets macOS 15.4 and layers macOS 26 features such as Liquid Glass on top. Write idiomatic SwiftUI and Swift Concurrency code that follows Apple's Human Interface Guidelines.

## Project

- Lilt is a personal, minimal fork of [Kaset](https://github.com/sozercan/kaset), maintained in `julianarchila/kaset` (the GitHub repo kept its old name). Cherry-pick upstream fixes when useful and never merge upstream wholesale. Keep the upstream MIT notice in `LICENSE`.
- The scope is YouTube Music only. The fork removed regular YouTube (video mode, Ask Gemini), Apple Intelligence features, Last.fm scrobbling, web extensions, Sparkle updates, What's New, and the Charts, Moods & Genres, New Releases, and Podcasts pages. Ask before bringing any of them back. ADR-0042 records the fork's identity and removals, and later ADRs record its redesigns.
- The design target is a stock macOS app: native sidebar and search field, the system accent color, and Apple Music style layouts. Prefer system controls to custom chrome.
- Work lands on `main` by fast-forward from worktree branches. There are no pull requests.
- Push over SSH to `git@github.com:julianarchila/kaset.git`. The `gh` token lacks the `workflow` scope, so GitHub rejects HTTPS pushes that touch `.github/workflows/`.
- To install the user's copy, quit the running app (`com.julianarchila.Lilt`), move `/Applications/Lilt.app` to the Trash, then run `Scripts/build-app.sh release && ditto .build/app/Lilt.app /Applications/Lilt.app`.

## Rules

- **Keep real credentials out of everything.** Cookies, SAPISID values, auth tokens, and API keys must not appear in code, comments, logs, docs, test fixtures, or your output. Use placeholders such as `"REDACTED"`, `"mock-token"`, or `"test-cookie"`. The repo is public and the app holds signed-in Google sessions, so a leaked value compromises a real account.
- **Ask before running UI tests.** They launch the app and take over the desktop.
- **Ask before adding a third-party dependency.** The project has none.
- **Use the API client, not WebView, for data.** Call `YTMusicClient` whenever the endpoint exists. WebView is only for DRM playback and sign-in.
- **Extend the API explorer instead of writing one-off scripts.** API exploration and debugging tooling belongs in `Sources/APIExplorer/main.swift`.
- **Keep standard macOS shortcuts.** Rebind `⌘M`, `⌘W`, `⌘Q`, `⌘H`, or `⌘,` only when the human asks. Media shortcuts follow macOS and Apple Music conventions; update `docs/keyboard-shortcuts.md` when they change.
- **Record significant design changes** as an ADR in `docs/adr/`.
- Match existing implementations. A new detail view follows the existing detail views, and a new parser follows `Sources/Lilt/Services/API/Parsers/`. Adapt new code to existing signatures, protocols, and model types unless the task calls for changing them.

## Build & Code Quality

```bash
swift build                              # Build
swift test --skip LiltUITests            # Unit tests (UI tests live in a separate Xcode project)
swiftlint --strict && swiftformat .      # Lint & format
```

A code change is done when all three pass. The unit test suite passes with zero failures, so treat any failure as a regression. Stay CLI-first and use Xcode or `xcodebuild` only for UI tests and scheme-specific investigation.

Format with SwiftFormat 0.63.1, the version CI pins in `.github/workflows/lint.yml` (installed at `~/.local/bin/swiftformat`). Newer releases rewrite unrelated files. `.swiftformat` uses `--self insert`, so static methods call `Self.methodName()` and instance methods write `self.property`.

## Coding Rules

Project rules that differ from standard Swift/SwiftUI conventions and aren't mechanically checked:

| Avoid | Use | Why |
|-------|-----|-----|
| `.background(.ultraThinMaterial)` | `compatGlass(...)` helpers in `LiquidGlassCompat.swift`, or `.glassEffect()` behind `#available(macOS 26.0, *)` | Liquid Glass on macOS 26 with a macOS 15 fallback |
| Force unwraps (`!`) | Optional handling or `guard` | Project policy |

- Mark `@Observable` classes with `@MainActor`.
- Write new unit tests with Swift Testing (`@Test`, `#expect`).
- Swift Testing runs suites in parallel. Give tests that touch `SingletonPlayerWebView.shared` the `.singletonPlayerWebView` trait, and give each test its own `UserDefaults` suite instead of `.standard`.
- Throw `YTMusicError.authExpired` on HTTP 401/403.
- Use `.task` instead of `.onAppear { Task { } }`.

`swiftlint --strict` enforces the mechanically checkable bans (`print()`, `DispatchQueue`, `NavigationView`, `foregroundColor`, `cornerRadius`, `contentMargins`) and names the replacement in each message; see `.swiftlint.yml`.

## Localization

`Sources/Lilt/Resources/Localizable.xcstrings` is the source of truth. Packaged builds compile the catalog. SwiftPM and Xcode runtime builds read the checked-in `Sources/Lilt/Resources/*.lproj/Localizable.strings` mirrors, so the catalog and the mirrors must change together.

- Add or change a string in the catalog first, then in all 18 `.lproj/Localizable.strings` files in the same change.
- Run `swift test --skip LiltUITests --filter LocalizationCatalogParityTests` after localization changes.
- Siri phrases for App Shortcuts live in `Sources/Lilt/Resources/AppShortcuts.xcstrings`, which has no `.lproj` mirror. `Scripts/build-app.sh` fails if it drifts from `LiltShortcuts`.
- A new locale also needs its `.lproj` registered in `Package.swift`, a `SettingsManager.ContentLanguage` case, and updated localization tests.

## API Discovery

YouTube's response shapes are undocumented and change without notice, so a parser written from inference compiles and then returns nothing. Before you add or change an API call, request shape, or response parser, check the real request and response with `swift run api-explorer` (see the `api-exploration` skill). Prefer read-only probes, and get the human's approval before a live request that changes account data.

## Debugging & Measurement

For bugs about timing, lifecycle, or "why didn't this run/load/update", measure before fixing. Source reading alone is unreliable for SwiftUI lifecycle and async ordering. Add a timestamped trace, reproduce, fix what the data shows, measure again, and remove the trace before committing.

The app is sandboxed:

- `Logger`/`os_log` `.info` and `.debug` lines don't reliably reach `log stream` or `log show`.
- The sandbox blocks writes to hardcoded `/tmp/...` paths. Write traces to `NSTemporaryDirectory()`, call `synchronize()` after each line, and read them from `~/Library/Containers/com.julianarchila.Lilt/Data/tmp/` (`com.julianarchila.Lilt.debug` for packaged debug builds).

`docs/common-bug-patterns.md` has the trace template, the single-flight load pattern for the `.task`-restart cancellation deadlock, concurrency anti-patterns, and a pre-submit checklist.

Check UI changes in the running app with the `agent-desktop` CLI, using headless accessibility actions and window screenshots. `Scripts/compile_and_run.sh` packages and relaunches a debug build.

Media keys and Control Center reach WebKit's Now Playing session in the GPU process, not the app. The page forwards Media Session play, pause, next, and previous to Swift as `REMOTE_*` bridge messages. ADR-0045 has the measurements.

## Cookie Storage and Signing

Sandboxed builds without a Developer ID signature hang inside `SecItemCopyMatching` when they query the Keychain.

- `#if DEBUG` builds and release builds compiled with `LILT_FILE_COOKIE_STORAGE` store cookies in `Application Support/Lilt/cookies.dat` instead of the Keychain. `Scripts/build-app.sh` sets that flag unless `LILT_SIGNING=developer-id`, so `Scripts/build-app.sh release` produces an installable ad-hoc build.
- Packaged debug builds use the bundle ID `com.julianarchila.Lilt.debug`, with their own container, UserDefaults, and WebKit cookie jar. They start signed out, so signed-in UI (like, Dislike, Library) needs a login or the user's installed release build. Keep the `.debug` bundle ID: sharing the release ID makes each build overwrite the other's session.
- `LILT_DEBUG_COOKIE_STORAGE=keychain` tests the Keychain path. The Keychain is shared, so it reads and writes the release archive.
- The debug file backend has its own sign-out tombstone key (`authCookieBackupInvalidated.debugFileStorage`). Debug-only auth state writes only that key.

## Code Review

Run the `autoreview` skill after committing non-trivial code changes and before pushing them. Skip it for docs-only or trivial changes, or when the human opts out. Finish the focused tests first and run the review afterwards, because CPU contention makes timing-sensitive tests flaky.

```bash
python3 .agents/skills/autoreview/scripts/autoreview --mode branch --base origin/main --max-priority P3 \
  --engine claude --source-context-file AGENTS.md \
  --prompt "Also report changes that violate the repository rules in the AGENTS.md source context, such as credential handling, API-over-WebView, localization parity, and the Coding Rules table."
```

- Codex rejects the default models on this account, so the command passes `--engine claude`.
- `--max-priority P3` reports every priority; the helper's default shows only P0.
- `branch` mode reviews committed work only, so commit first. It also refuses modified binaries such as icons; review those changes per commit with `--mode commit --commit <sha>`.
- `--source-context-file` works only in `branch` and `commit` modes.

Check each finding against the real code path. Fix the ones that hold up and give a reason for each one you reject. After review-driven changes, rerun the focused tests and the review once. Report the command, the tests you ran, each finding's outcome, and the final result.

`.agents/skills/autoreview/` is an unmodified copy of [`sozercan/skills`](https://github.com/sozercan/skills/tree/main/skills/autoreview) (commit `1b8ef21`). Update it by replacing the whole directory from that repository, leaving out its `AGENTS.md` and `CLAUDE.md`.

## Skills

Repo-specific workflows live in `.agents/skills/` (also exposed as `.claude/skills/`). Add new workflows there so this file stays focused on repo-wide rules.
