import WebKit

// MARK: - SingletonPlayerWebView Playback Controls Extension

extension SingletonPlayerWebView {
    /// Enables/disables startup autoplay blocking inside the observer script.
    func setAutoplayBlocked(_ blocked: Bool) {
        guard let webView else { return }
        let script = """
            (function() {
                window.__liltBlockAutoplay = \(blocked ? "true" : "false");
                if (window.__liltAutoplayBlockTimer) {
                    clearInterval(window.__liltAutoplayBlockTimer);
                    window.__liltAutoplayBlockTimer = null;
                }
                if (!window.__liltBlockAutoplay) return 'autoplay-allowed';
                window.__liltAutoplayPending = false;
                \(WebPlaybackAudioOutput.stopScript)
                var ticks = 0;
                const timer = setInterval(function() {
                    if (!window.__liltBlockAutoplay) {
                        clearInterval(timer);
                        if (window.__liltAutoplayBlockTimer === timer) window.__liltAutoplayBlockTimer = null;
                        return;
                    }
                    const video = document.querySelector('video');
                    if (video && !video.paused) {
                        try { video.pause(); } catch (_) {}
                    }
                    ticks += 1;
                    if (ticks >= 20) {
                        clearInterval(timer);
                        if (window.__liltAutoplayBlockTimer === timer) window.__liltAutoplayBlockTimer = null;
                    }
                }, 150);
                window.__liltAutoplayBlockTimer = timer;
                return 'autoplay-blocked';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    struct PlaybackSnapshot {
        let progress: TimeInterval
        let duration: TimeInterval
        let videoId: String?
    }

    nonisolated static let playbackSnapshotScript = """
        (function() {
            const video = document.querySelector('video');
            if (!video || video.readyState < 1 || !video.__liltBoundVideoId
                || !(video.__liltMediaGeneration > 0)) return null;
            const source = video.currentSrc || video.src || '';
            if (!source || source !== video.__liltBoundMediaSource) return null;
            return {
                progress: Number.isFinite(video.currentTime) ? video.currentTime : 0,
                duration: Number.isFinite(video.duration) ? video.duration : 0,
                videoId: video.__liltBoundVideoId
            };
        })();
    """

    /// Reads playback time from the live WebView video element.
    func currentPlaybackSnapshot() async -> PlaybackSnapshot? {
        guard let webView else { return nil }

        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(Self.playbackSnapshotScript) { result, error in
                if let error {
                    self.logger.error("currentPlaybackSnapshot error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let dictionary = result as? [String: Any] else {
                    continuation.resume(returning: nil)
                    return
                }

                let progress = Self.timeInterval(from: dictionary["progress"])
                let duration = Self.timeInterval(from: dictionary["duration"])
                let videoId = (dictionary["videoId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                continuation.resume(returning: PlaybackSnapshot(
                    progress: progress,
                    duration: duration,
                    videoId: videoId
                ))
            }
        }
    }

    private static func timeInterval(from value: Any?) -> TimeInterval {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let double as Double:
            double
        case let string as String:
            Double(string) ?? 0
        default:
            0
        }
    }

    nonisolated static var playPauseCommandScript: String {
        """
        (function() {
            \(playerBarLookupFunctionJS)
            const playBtn = __liltPlayerBarElement('playPause');
            if (playBtn) {
                const video = document.querySelector('video');
                const wantsPlay = !video || video.paused;
                window.__liltAutoplayPending = wantsPlay;
                window.__liltPlaybackSuppressed = !wantsPlay;
                if (wantsPlay) {
                    window.__liltBlockAutoplay = false;
                    \(WebPlaybackAudioOutput.prepareScript)
                    window.__liltAutoplayAttempts = 0;
                    window.__liltAutoplayRetryScheduled = false;
                    if (video && typeof window.__liltAttemptAutoplayRecovery === 'function') {
                        return window.__liltAttemptAutoplayRecovery(video, playBtn);
                    }
                } else {
                    \(WebPlaybackAudioOutput.stopScript)
                }
                playBtn.click();
                return 'clicked';
            }
            const video = document.querySelector('video');
            if (video) {
                if (video.paused) {
                    window.__liltAutoplayPending = true;
                    window.__liltPlaybackSuppressed = false;
                    window.__liltBlockAutoplay = false;
                    \(WebPlaybackAudioOutput.prepareScript)
                    window.__liltAutoplayAttempts = 0;
                    window.__liltAutoplayRetryScheduled = false;
                    if (typeof window.__liltAttemptAutoplayRecovery === 'function') {
                        return window.__liltAttemptAutoplayRecovery(video, null);
                    }
                    video.play();
                    return 'played';
                } else {
                    window.__liltAutoplayPending = false;
                    window.__liltPlaybackSuppressed = true;
                    \(WebPlaybackAudioOutput.stopScript)
                    video.pause();
                    return 'paused';
                }
            }
            return 'no-element';
        })();
        """
    }

    /// Toggle play/pause.
    func playPause() {
        guard let webView else { return }
        let generation = self.documentGeneration.currentGeneration
        guard self.documentGeneration.accepts(generation: generation) else { return }

        let script = """
            if (window.__liltDocumentGeneration === \(generation)) {
                \(Self.playPauseCommandScript)
            }
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("playPause error: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static var playCommandScript: String {
        """
        (function() {
            window.__liltAutoplayPending = true;
            window.__liltPlaybackSuppressed = false;
            window.__liltBlockAutoplay = false;
            window.__liltResumeAdOnly = false;
            window.__liltAutoplayAttempts = 0;
            window.__liltAutoplayRetryScheduled = false;
            const video = document.querySelector('video');
            if (video && video.paused) {
                \(WebPlaybackAudioOutput.prepareScript)
                if (typeof window.__liltAttemptAutoplayRecovery === 'function') {
                    return window.__liltAttemptAutoplayRecovery(video, null);
                }
                video.play();
                return 'played';
            }
            return video ? 'already-playing' : 'pending-media';
        })();
        """
    }

    /// Play (resume).
    func play() {
        guard let webView else { return }
        let generation = self.documentGeneration.currentGeneration
        guard self.documentGeneration.accepts(generation: generation) else { return }
        webView.evaluateJavaScript("""
            if (window.__liltDocumentGeneration === \(generation)) {
                \(Self.playCommandScript)
            }
        """, completionHandler: nil)
    }

    /// During restored playback, a paused preroll ad must advance before the
    /// content seek can be reconciled. Never unsuppress ordinary content here.
    func resumeReadyAdvertisementIfPresent() {
        guard let webView else { return }
        let generation = self.documentGeneration.currentGeneration
        guard self.documentGeneration.accepts(generation: generation) else { return }
        webView.evaluateJavaScript("""
            (function() {
                if (window.__liltDocumentGeneration !== \(generation)) return 'stale';
                window.__liltBlockAutoplay = false;
                if (window.__liltAutoplayBlockTimer) {
                    clearInterval(window.__liltAutoplayBlockTimer);
                    window.__liltAutoplayBlockTimer = null;
                }
                \(PlaybackAdDetectionScript.detection)
                const isAd = isAdShowing();
                const video = document.querySelector('video');
                if (!isAd || !video || !video.currentSrc || video.readyState < 1) return 'not-ready-ad';
                window.__liltPlaybackSuppressed = false;
                window.__liltAutoplayPending = true;
                window.__liltResumeAdOnly = true;
                if (video.paused) {
                    if (typeof window.__liltAttemptAutoplayRecovery === 'function') {
                        window.__liltAttemptAutoplayRecovery(video, null);
                    } else {
                        video.play();
                    }
                }
                return 'playing-ad';
            })();
        """, completionHandler: nil)
    }

    /// Pause.
    func pause() {
        guard let webView else { return }

        let script = """
            (function() {
            window.__liltAutoplayPending = false;
            window.__liltPlaybackSuppressed = true;
            \(WebPlaybackAudioOutput.stopScript)
                const video = document.querySelector('video');
                if (video && !video.paused) { video.pause(); return 'paused'; }
                return 'already-paused';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Skip to next track.
    func next() {
        guard let webView else { return }

        let script = """
            (function() {
                \(Self.playerBarLookupFunctionJS)
                const nextBtn = __liltPlayerBarElement('next');
                if (nextBtn) { nextBtn.click(); return 'clicked'; }
                return 'no-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("next error: \(error.localizedDescription)")
            }
        }
    }

    /// Go to previous track.
    func previous() {
        guard let webView else { return }

        let script = """
            (function() {
                \(Self.playerBarLookupFunctionJS)
                const prevBtn = __liltPlayerBarElement('previous');
                if (prevBtn) { prevBtn.click(); return 'clicked'; }
                return 'no-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("previous error: \(error.localizedDescription)")
            }
        }
    }

    /// Seek to a specific time in seconds.
    func seek(to time: Double) {
        guard let webView else { return }

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (video) { video.currentTime = \(time); return 'seeked'; }
                return 'no-video';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Pure script for atomically pausing and seeking the underlying video.
    nonisolated static func seekAndPauseScript(to time: Double) -> String {
        let safeTime = time.isFinite ? max(time, 0) : 0
        return """
            (function() {
                \(WebPlaybackAudioOutput.stopScript)
                const video = document.querySelector('video');
                if (!video) { return 'no-video'; }
                video.pause();
                video.currentTime = \(safeTime);
                video.pause();
                return 'seeked-paused';
            })();
        """
    }

    /// Atomically pause and seek the underlying video.
    func seekAndPause(to time: Double) {
        guard let webView else { return }
        webView.evaluateJavaScript(Self.seekAndPauseScript(to: time), completionHandler: nil)
    }

    /// Seeks to the start and resumes playback without a full page load (repeat-one, same-URL recovery).
    func restartInPlaceFromBeginning() {
        guard let webView else { return }
        if let nativeGeneration = self.coordinator?.playerService.currentMusicPlaybackOccurrence?.nativeGeneration {
            self.setNativePlaybackGeneration(nativeGeneration)
        }
        let documentGeneration = self.documentGeneration.currentGeneration
        guard self.documentGeneration.accepts(generation: documentGeneration) else { return }
        let script = """
            (function() {
                if (window.__liltDocumentGeneration !== \(documentGeneration)) return 'stale';
                window.__liltBlockAutoplay = false;
                if (window.__liltAutoplayBlockTimer) {
                    clearInterval(window.__liltAutoplayBlockTimer);
                    window.__liltAutoplayBlockTimer = null;
                }
                window.__liltAutoplayPending = true;
                window.__liltPlaybackSuppressed = false;
                window.__liltResumeAdOnly = false;
                window.__liltAutoplayAttempts = 0;
                window.__liltAutoplayRetryScheduled = false;
                const video = document.querySelector('video');
                if (!video) return 'no-video';
                video.currentTime = 0;
                if (typeof window.__liltAdvanceMediaGeneration === 'function') {
                    window.__liltAdvanceMediaGeneration();
                }
                if (typeof window.__liltAttemptAutoplayRecovery === 'function') {
                    window.__liltAttemptAutoplayRecovery(video, null);
                } else {
                    video.play();
                }
                return 'restarted';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Set volume (0.0 - 1.0).
    func setVolume(_ volume: Double) {
        guard let webView else { return }
        let clampedVolume = max(0, min(1, volume))

        // Update target volume and set video volume directly
        // Also try to set YouTube's internal player volume via their API
        let script = """
            (function() {
                window.__liltTargetVolume = \(clampedVolume);
                const video = document.querySelector('video');
                let result = [];

                if (video) {
                    // Set flag to prevent volumechange listener from reverting
                    window.__liltIsSettingVolume = true;
                    video.volume = \(clampedVolume);
                    result.push('video.volume=' + video.volume);
                    setTimeout(() => { window.__liltIsSettingVolume = false; }, 50);
                } else {
                    result.push('no-video');
                }

                // Also try YouTube Music's internal player API
                const player = document.querySelector('ytmusic-player');
                if (player && player.playerApi) {
                    const ytVolume = Math.round(\(clampedVolume) * 100);
                    player.playerApi.setVolume(ytVolume);
                    result.push('ytapi.setVolume=' + ytVolume);
                }

                // Try movie_player API as fallback
                const moviePlayer = document.getElementById('movie_player');
                if (moviePlayer && moviePlayer.setVolume) {
                    const ytVolume = Math.round(\(clampedVolume) * 100);
                    moviePlayer.setVolume(ytVolume);
                    result.push('movie_player.setVolume=' + ytVolume);
                }

                return result.join(', ');
            })();
        """
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                self.logger.error("setVolume error: \(error.localizedDescription)")
            }
        }
    }

    /// Show the native AirPlay picker for the WebView's video element.
    func showAirPlayPicker(at screenPoint: CGPoint? = nil) {
        guard let webView else {
            DiagnosticsLogger.airplay.warning("showAirPlayPicker called but webView is nil")
            return
        }

        AirPlayPickerAnchor.preparePicker(in: webView, at: screenPoint)

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (!video) return 'no-video';
                if (typeof video.webkitShowPlaybackTargetPicker !== 'function') return 'unsupported';

                video.webkitShowPlaybackTargetPicker();
                return 'picker-shown';
            })();
        """
        webView.evaluateJavaScript(script) { result, error in
            if let error {
                DiagnosticsLogger.airplay.error("showAirPlayPicker error: \(error.localizedDescription)")
            } else if let status = result as? String {
                switch status {
                case "no-video":
                    DiagnosticsLogger.airplay.warning("showAirPlayPicker: no video element available")
                case "unsupported":
                    DiagnosticsLogger.airplay.warning("showAirPlayPicker: webkitShowPlaybackTargetPicker not supported")
                default:
                    DiagnosticsLogger.airplay.debug("showAirPlayPicker: \(status)")
                }
            }
        }
    }
}
