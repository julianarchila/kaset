import AppKit
import Foundation
import MediaPlayer
import Observation
import os

// MARK: - RemoteMusicCommandDirection

enum RemoteMusicCommandDirection: Equatable {
    case forward
    case backward
}

// MARK: - RemoteMusicCommandPayload

enum RemoteMusicCommandPayload: Equatable {
    case play
    case pause
    case togglePlayPause
    /// The next/previous media keys, which seek instead when the media control style says so.
    case nextPrevious(direction: RemoteMusicCommandDirection)
    /// An explicit track change (App Intents), regardless of the media control style.
    case trackNavigation(direction: RemoteMusicCommandDirection)
    case skip(interval: TimeInterval, direction: RemoteMusicCommandDirection)
    case absoluteSeek(position: TimeInterval)
}

// MARK: - CapturedRemoteMusicCommand

struct CapturedRemoteMusicCommand: Equatable {
    let sequence: UInt64
    let issuedAtMilliseconds: Double
    let admittedAt: ContinuousClock.Instant
    let payload: RemoteMusicCommandPayload
}

// MARK: - RemoteMusicCommandIngress

/// Thread-safe callback inbox for native media commands. Callback order and clocks
/// are captured synchronously before any MainActor scheduling can reorder delivery.
final class RemoteMusicCommandIngress: @unchecked Sendable {
    private struct State {
        var nextSequence: UInt64 = 0
        var pendingCommands: [CapturedRemoteMusicCommand] = []
        var isDrainScheduled = false
    }

    private let lock = NSLock()
    private var state = State()

    /// Returns `true` only when the caller must schedule the single MainActor drain.
    @discardableResult
    func capture(_ payload: RemoteMusicCommandPayload) -> Bool {
        self.lock.withLock {
            self.captureLocked(
                payload,
                issuedAtMilliseconds: Date().timeIntervalSince1970 * 1000,
                admittedAt: ContinuousClock.now
            )
        }
    }

    /// Deterministic clock injection for ingress ordering and stale-admission tests.
    @discardableResult
    func capture(
        _ payload: RemoteMusicCommandPayload,
        issuedAtMilliseconds: Double,
        admittedAt: ContinuousClock.Instant
    ) -> Bool {
        self.lock.withLock {
            self.captureLocked(
                payload,
                issuedAtMilliseconds: issuedAtMilliseconds,
                admittedAt: admittedAt
            )
        }
    }

    func takePendingCommands() -> [CapturedRemoteMusicCommand] {
        self.lock.withLock {
            let commands = self.state.pendingCommands
            self.state.pendingCommands.removeAll(keepingCapacity: true)
            return commands
        }
    }

    /// Returns `true` when callbacks arrived during the last batch and the existing
    /// drain must loop. Otherwise, it atomically rearms scheduling for the next callback.
    func finishDrainBatch() -> Bool {
        self.lock.withLock {
            guard self.state.pendingCommands.isEmpty else { return true }
            self.state.isDrainScheduled = false
            return false
        }
    }

    private func captureLocked(
        _ payload: RemoteMusicCommandPayload,
        issuedAtMilliseconds: Double,
        admittedAt: ContinuousClock.Instant
    ) -> Bool {
        let command = CapturedRemoteMusicCommand(
            sequence: self.state.nextSequence,
            issuedAtMilliseconds: issuedAtMilliseconds,
            admittedAt: admittedAt,
            payload: payload
        )
        self.state.nextSequence &+= 1
        self.state.pendingCommands.append(command)

        guard !self.state.isDrainScheduled else { return false }
        self.state.isDrainScheduled = true
        return true
    }
}

// MARK: - NowPlayingManager

/// Manages remote-command routing and the app's Now Playing ownership.
/// WebKit publishes the rich card from its GPU process, which macOS lists as its own Now Playing
/// client; it keeps that session while paused. Kaset publishes tagged minimal metadata only while
/// WebKit has no session (page loads, cold start) so media keys keep routing to Kaset, and
/// releases it as soon as WebKit's session exists so the two never appear side by side (ADR-0045).
@MainActor
@Observable
final class NowPlayingManager {
    /// Shared singleton instance. Must be configured with `configure(playerService:)` before use.
    static let shared = NowPlayingManager()

    private var playerService: PlayerService?
    private let logger = DiagnosticsLogger.player
    private var isConfigured = false
    /// True while Kaset is asserting a tagged native Now Playing claim.
    /// The tag lets release logic distinguish our metadata from a newer WebKit card.
    private var isAssertingNativeClaim = false
    /// Tracks WebKit's own Now Playing session so the native fallback never duplicates it.
    @ObservationIgnored private lazy var webKitSessionObserver = WebKitNowPlayingSessionObserver { [weak self] in
        self?.updateNowPlayingClaim()
    }

    @ObservationIgnored private var nowPlayingObservationGeneration: UInt64 = 0

    private let settings = SettingsManager.shared
    private let remoteMusicCommandIngress = RemoteMusicCommandIngress()
    private static let defaultSkipInterval: TimeInterval = 15
    nonisolated static let nativeClaimServiceIdentifier = "com.julianarchila.Lilt.native-now-playing-claim"

    private init() {}

    // MARK: - Now Playing Claim

    enum NativeClaimPlaybackState: Equatable, Sendable {
        case playing
        case paused
    }

    /// What Kaset should tell the system Now Playing center for the current player state.
    /// `handsOff` keeps an existing fallback during active playback until WebKit reports its own
    /// session, while `release` clears the native claim when WebKit has a session or no resumable
    /// media remains.
    enum NowPlayingClaim: Equatable {
        case handsOff
        case release
        case claim(title: String, artist: String, playbackState: NativeClaimPlaybackState)
    }

    /// Pure decision: given the music player's state, what claim do we want?
    /// Active playback stays hands-off so WebKit owns the rich Control Center card, while
    /// inactive music keeps a minimal claim so the Play key resumes Kaset instead of Apple Music.
    /// WebKit publishes from its GPU process, which macOS lists as a separate Now Playing entry,
    /// so the claim is released whenever WebKit reports its own session (`webKitHasSession`).
    /// `nil` means WebKit's state is unknown and keeps the fallback.
    nonisolated static func desiredClaim(
        state: PlayerService.PlaybackState,
        track: (title: String, artist: String)?,
        webKitHasSession: Bool? = nil
    ) -> NowPlayingClaim {
        if webKitHasSession == true {
            return .release
        }
        switch state {
        case .playing, .buffering, .loading:
            return .handsOff
        case .idle, .paused, .ended, .error:
            guard let track else { return .release }
            return .claim(title: track.title, artist: track.artist, playbackState: .paused)
        }
    }

    /// Reads current player state and pushes the desired claim to the system center.
    private func updateNowPlayingClaim() {
        guard let player = self.playerService else { return }
        let track = player.currentTrack.map { song in
            (title: song.title, artist: song.artists.map(\.name).joined(separator: ", "))
        }
        let claim = Self.desiredClaim(
            state: player.state,
            track: track,
            webKitHasSession: self.webKitSessionObserver.hasActiveSession
        )
        self.applyNowPlayingClaim(claim)
    }

    /// Maps a claim onto `MPNowPlayingInfoCenter`. Hands-off only clears info we still own.
    private func applyNowPlayingClaim(_ claim: NowPlayingClaim) {
        let center = MPNowPlayingInfoCenter.default()
        switch claim {
        case .handsOff:
            guard self.isAssertingNativeClaim else { return }
            guard Self.isNativeClaim(center.nowPlayingInfo) else {
                self.isAssertingNativeClaim = false
                return
            }
            // Keep the fallback until WebKit reports its own session (then the claim is released):
            // WebKit's card belongs to a separate GPU-process client and never replaces ours.
            center.playbackState = .playing
        case .release:
            guard self.isAssertingNativeClaim else { return }
            self.isAssertingNativeClaim = false
            guard Self.isNativeClaim(center.nowPlayingInfo) else { return }
            center.playbackState = .stopped
            center.nowPlayingInfo = nil
        case let .claim(title, artist, playbackState):
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: title,
                MPNowPlayingInfoPropertyServiceIdentifier: Self.nativeClaimServiceIdentifier,
            ]
            if !artist.isEmpty {
                info[MPMediaItemPropertyArtist] = artist
            }
            center.nowPlayingInfo = info
            center.playbackState = switch playbackState {
            case .playing: .playing
            case .paused: .paused
            }
            self.isAssertingNativeClaim = true
        }
    }

    /// Returns whether the current center metadata is the tagged native claim Kaset published.
    nonisolated static func isNativeClaim(_ info: [String: Any]?) -> Bool {
        info?[MPNowPlayingInfoPropertyServiceIdentifier] as? String == self.nativeClaimServiceIdentifier
    }

    /// Replaces the current one-shot observation loop with one that tracks the latest dependencies.
    private func restartNowPlayingObservation() {
        self.nowPlayingObservationGeneration &+= 1
        self.observePlaybackState(generation: self.nowPlayingObservationGeneration)
    }

    /// Re-runs the claim whenever music state or track metadata changes.
    private func observePlaybackState(generation: UInt64) {
        withObservationTracking {
            _ = self.playerService?.state
            _ = self.playerService?.currentTrack
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.nowPlayingObservationGeneration == generation
                else { return }

                self.updateNowPlayingClaim()
                self.observePlaybackState(generation: generation)
            }
        }
    }

    /// Configures the singleton with a player service. Only configures once; subsequent calls are ignored.
    func configure(playerService: PlayerService) {
        guard !self.isConfigured else {
            self.logger.debug("NowPlayingManager already configured, skipping")
            return
        }
        self.isConfigured = true
        self.playerService = playerService
        self.setupRemoteCommands()
        self.syncMediaControlSetting()
        self.syncPlaybackAudioQualitySetting()
        self.logger.info("NowPlayingManager configured")

        self.observeSettingsChanges()

        SingletonPlayerWebView.shared.onWebViewChange = { [weak self] webView in
            self?.webKitSessionObserver.observe(webView)
        }
        self.webKitSessionObserver.observe(SingletonPlayerWebView.shared.webView)

        self.updateNowPlayingClaim()
        self.restartNowPlayingObservation()
    }

    private func observeSettingsChanges() {
        withObservationTracking {
            _ = self.settings.mediaControlStyle
            _ = self.settings.playbackAudioQuality
        } onChange: {
            Task { @MainActor [weak self] in
                self?.syncMediaControlSetting()
                self?.syncPlaybackAudioQualitySetting()
                self?.observeSettingsChanges()
            }
        }
    }

    /// Syncs the media control style setting to the singleton WebView and its bootstrap state.
    private func syncMediaControlSetting() {
        let useNextPrev = self.settings.mediaControlStyle == .nextPreviousTrack
        SingletonPlayerWebView.shared.setMediaControlStyle(useNextPrev: useNextPrev)
        self.syncSkipCommandAvailability(useNextPrev: useNextPrev)
    }

    private func syncSkipCommandAvailability(useNextPrev: Bool) {
        let commandCenter = MPRemoteCommandCenter.shared()
        let enableSkipCommands = !useNextPrev
        commandCenter.skipForwardCommand.isEnabled = enableSkipCommands
        commandCenter.skipBackwardCommand.isEnabled = enableSkipCommands
    }

    /// Syncs the preferred playback audio quality setting to the singleton WebView and its bootstrap state.
    private func syncPlaybackAudioQualitySetting() {
        SingletonPlayerWebView.shared.setPlaybackAudioQuality(self.settings.playbackAudioQuality)
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        guard self.playerService != nil else { return }
        let commandCenter = MPRemoteCommandCenter.shared()
        let ingress = self.remoteMusicCommandIngress
        let captureCommand: @Sendable (RemoteMusicCommandPayload) -> Void = { [weak self] payload in
            guard ingress.capture(payload) else { return }
            Task { @MainActor [weak self] in
                self?.drainRemoteMusicCommandIngress()
            }
        }

        // Remove any existing targets to prevent duplicates
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            captureCommand(.play)
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            captureCommand(.pause)
            return .success
        }

        // Toggle play/pause command
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            captureCommand(.togglePlayPause)
            return .success
        }

        // Next track command
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            captureCommand(.nextPrevious(direction: .forward))
            return .success
        }

        // Previous track command
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            captureCommand(.nextPrevious(direction: .backward))
            return .success
        }

        // Skip forward command (Control Center skip buttons or media keys)
        commandCenter.skipForwardCommand.isEnabled = self.settings.mediaControlStyle == .skipForwardBackward
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.defaultSkipInterval)]
        commandCenter.skipForwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.defaultSkipInterval
            captureCommand(.skip(interval: interval, direction: .forward))
            return .success
        }

        // Skip backward command (Control Center skip buttons or media keys)
        commandCenter.skipBackwardCommand.isEnabled = self.settings.mediaControlStyle == .skipForwardBackward
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.defaultSkipInterval)]
        commandCenter.skipBackwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.defaultSkipInterval
            captureCommand(.skip(interval: interval, direction: .backward))
            return .success
        }

        // Change playback position command
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            captureCommand(.absoluteSeek(position: positionEvent.positionTime))
            return .success
        }

        self.logger.info("Remote commands configured")
    }

    /// Admits a transport command from App Intents through the media-key ingress, so Shortcuts
    /// and Siri control the player the same way the media keys do.
    /// Returns false when there is nothing to control: before `configure(playerService:)`, or when
    /// the music player has no track, pending load, or queue.
    @discardableResult
    func handleAppIntentCommand(_ payload: RemoteMusicCommandPayload) -> Bool {
        guard let player = self.playerService,
              Self.hasTransportTarget(player: player)
        else { return false }
        if self.remoteMusicCommandIngress.capture(payload) {
            self.drainRemoteMusicCommandIngress()
        }
        return true
    }

    static func hasTransportTarget(player: PlayerService) -> Bool {
        player.currentTrack != nil || player.currentEpisode != nil
            || player.pendingPlayVideoId != nil || !player.queueEntries.isEmpty
    }

    private func drainRemoteMusicCommandIngress() {
        while true {
            let commands = self.remoteMusicCommandIngress.takePendingCommands()
            if let player = self.playerService {
                for command in commands {
                    self.handleCapturedRemoteMusicCommand(command, player: player)
                }
            }
            guard self.remoteMusicCommandIngress.finishDrainBatch() else { return }
        }
    }

    private func handleCapturedRemoteMusicCommand(
        _ capturedCommand: CapturedRemoteMusicCommand,
        player: PlayerService
    ) {
        switch capturedCommand.payload {
        case .play:
            self.enqueueMusicRemoteCommand(.play, capturedCommand: capturedCommand, player: player)
        case .pause:
            self.enqueueMusicRemoteCommand(.pause, capturedCommand: capturedCommand, player: player)
        case .togglePlayPause:
            self.enqueueMusicRemoteCommand(.togglePlayPause, capturedCommand: capturedCommand, player: player)
        case let .nextPrevious(direction):
            self.handleNextPreviousMediaKey(
                direction: direction,
                capturedCommand: capturedCommand,
                player: player
            )
        case let .trackNavigation(direction):
            self.handleTrackChange(
                direction: direction,
                capturedCommand: capturedCommand,
                player: player
            )
        case let .skip(interval, direction):
            self.handleSkipCommand(
                interval: interval,
                direction: direction,
                capturedCommand: capturedCommand,
                player: player
            )
        case let .absoluteSeek(position):
            guard position.isFinite else { return }
            self.enqueueMusicRemoteCommand(
                .absoluteSeek(position: position),
                capturedCommand: capturedCommand,
                player: player
            )
        }
    }

    private func handleNextPreviousMediaKey(
        direction: RemoteMusicCommandDirection,
        capturedCommand: CapturedRemoteMusicCommand,
        player: PlayerService
    ) {
        guard self.settings.mediaControlStyle == .skipForwardBackward else {
            self.handleTrackChange(
                direction: direction,
                capturedCommand: capturedCommand,
                player: player
            )
            return
        }

        self.handleSkipCommand(
            interval: Self.defaultSkipInterval,
            direction: direction,
            capturedCommand: capturedCommand,
            player: player
        )
    }

    /// Moves to the next or previous item.
    private func handleTrackChange(
        direction: RemoteMusicCommandDirection,
        capturedCommand: CapturedRemoteMusicCommand,
        player: PlayerService
    ) {
        self.handleTrackNavigation(
            direction: direction,
            capturedCommand: capturedCommand,
            player: player
        )
    }

    private func handleSkipCommand(
        interval: TimeInterval,
        direction: RemoteMusicCommandDirection,
        capturedCommand: CapturedRemoteMusicCommand,
        player: PlayerService
    ) {
        guard interval.isFinite,
              player.currentTrack != nil || player.pendingPlayVideoId != nil || !player.queue.isEmpty
        else { return }

        if self.settings.mediaControlStyle == .nextPreviousTrack {
            self.handleTrackNavigation(
                direction: direction,
                capturedCommand: capturedCommand,
                player: player
            )
            return
        }

        let delta = direction == .forward ? interval : -interval
        self.enqueueMusicRemoteCommand(
            .relativeSeek(delta: delta, admittedAt: capturedCommand.admittedAt),
            capturedCommand: capturedCommand,
            player: player
        )
    }

    private func handleTrackNavigation(
        direction: RemoteMusicCommandDirection,
        capturedCommand: CapturedRemoteMusicCommand,
        player: PlayerService
    ) {
        self.enqueueMusicRemoteCommand(
            direction == .forward ? .next : .previous,
            capturedCommand: capturedCommand,
            player: player
        )
    }

    private func enqueueMusicRemoteCommand(
        _ command: MusicRemoteTransportCommand,
        capturedCommand: CapturedRemoteMusicCommand,
        player: PlayerService
    ) {
        player.enqueueRemoteMusicTransportCommand(
            command,
            issuedAtMilliseconds: capturedCommand.issuedAtMilliseconds
        )
    }
}
