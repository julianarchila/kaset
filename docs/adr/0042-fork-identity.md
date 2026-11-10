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

## Consequences

- Fork and upstream builds are fully isolated and can run side by side.
- Changing the bundle ID again later costs one sign-in and resets local
  preferences, because macOS keys the sandbox container on the bundle ID.
- Sparkle is no longer a dependency; the app has no third-party dependencies.
- Restoring auto-updates later requires a new EdDSA key, an appcast hosted by
  the fork, and Developer ID signing.
