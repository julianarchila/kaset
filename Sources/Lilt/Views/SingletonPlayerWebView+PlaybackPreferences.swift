import Foundation

// MARK: - SingletonPlayerWebView Media Controls

extension SingletonPlayerWebView {
    /// Updates the current page and the bootstrap state used by future page loads.
    func setMediaControlStyle(useNextPrev: Bool) {
        self.mediaControlUsesNextPrev = useNextPrev
        self.refreshInstalledUserScripts()

        guard let webView = self.webView else { return }
        let script = Self.mediaControlStyleSyncScript(useNextPrev: useNextPrev)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func mediaControlBootstrapScript() -> String {
        Self.mediaControlStyleBootstrapScript(useNextPrev: self.mediaControlUsesNextPrev)
    }

    /// Re-asserts Lilt's `nexttrack`/`previoustrack` media-session override immediately.
    ///
    /// The document-start `setActionHandler` wrapper keeps YouTube from overwriting
    /// Lilt-owned next/previous handlers, so normal operation relies on bounded
    /// event-driven refreshes instead of a steady animation-frame loop.
    func reassertMediaControlOverride() {
        guard self.mediaControlUsesNextPrev, let webView = self.webView else { return }
        webView.evaluateJavaScript(
            "if (typeof window.__liltRefreshMediaControlStyle === 'function') { window.__liltRefreshMediaControlStyle(); }",
            completionHandler: nil
        )
    }

    /// Performs a bounded re-assertion when the app enters the background.
    ///
    /// YouTube handler writes are blocked by the document-start wrapper while Lilt owns
    /// next/previous, so no steady background timer is needed.
    func beginBackgroundMediaControlReassertion() {
        guard self.mediaControlUsesNextPrev else { return }
        self.reassertMediaControlOverride()
        self.mediaControlReassertTimer?.invalidate()
        self.mediaControlReassertTimer = nil
    }

    /// Clears any legacy background re-assertion timer.
    func endBackgroundMediaControlReassertion() {
        self.mediaControlReassertTimer?.invalidate()
        self.mediaControlReassertTimer = nil
    }

    static func mediaControlStyleBootstrapScript(useNextPrev: Bool) -> String {
        let jsBoolean = useNextPrev ? "true" : "false"
        return """
            (function() {
                try {
                    localStorage.setItem('liltUseNextPrev', '\(jsBoolean)');
                } catch (e) {}
                window.__liltUseNextPrev = \(jsBoolean);
                // Wrap setActionHandler at document start so YouTube registrations cannot
                // steal remote-command ownership. Seek handlers always stay native-owned;
                // play/pause always, and next/previous in nextPrev mode, stay Lilt-owned
                // unless Lilt is installing its own handlers under the temporary install flag.
                try {
                    if (typeof window.__liltInstallingMediaControlHandlers !== 'boolean') {
                        window.__liltInstallingMediaControlHandlers = false;
                    }
                    var ms = navigator.mediaSession;
                    if (ms && !ms.__liltSetActionHandlerWrapped) {
                        var orig = ms.setActionHandler.bind(ms);
                        ms.setActionHandler = function(type, handler) {
                            var isSeekSkip = type === 'seekforward' || type === 'seekbackward';
                            var isNextPrevious = type === 'nexttrack' || type === 'previoustrack';
                            var isPlayPause = type === 'play' || type === 'pause';
                            if (isSeekSkip) {
                                return orig(type, null);
                            }
                            if (isPlayPause && !window.__liltInstallingMediaControlHandlers) {
                                return undefined;
                            }
                            if (isNextPrevious) {
                                if (window.__liltUseNextPrev) {
                                    if (!window.__liltInstallingMediaControlHandlers) {
                                        return undefined;
                                    }
                                } else {
                                    return orig(type, null);
                                }
                            }
                            return orig(type, handler);
                        };
                        ms.__liltSetActionHandlerWrapped = true;
                    }
                } catch (e) {}
            })();
        """
    }

    static func mediaControlStyleSyncScript(useNextPrev: Bool) -> String {
        let jsBoolean = useNextPrev ? "true" : "false"
        let clearWebViewSkipHandlers = if useNextPrev {
            ""
        } else {
            """
                try {
                    var ms = navigator.mediaSession;
                    ms.setActionHandler('nexttrack', null);
                    ms.setActionHandler('previoustrack', null);
                    ms.setActionHandler('seekforward', null);
                    ms.setActionHandler('seekbackward', null);
                } catch (e) {}
            """
        }

        return """
            (function() {
                try {
                    localStorage.setItem('liltUseNextPrev', '\(jsBoolean)');
                } catch (e) {}
                window.__liltUseNextPrev = \(jsBoolean);
                if (typeof window.__liltRefreshMediaControlStyle === 'function') {
                    window.__liltRefreshMediaControlStyle();
                }
                \(clearWebViewSkipHandlers)
            })();
        """
    }

    static var mediaControlOverrideScript: String {
        """
        (function() {
            \(eventTimestampFunctionJS)
            const observerEpoch = (window.performance && performance.timeOrigin)
                ? performance.timeOrigin : Date.now();
            const documentID = Number(window.__liltDocumentID || 0);
            if (typeof window.__liltUseNextPrev !== 'boolean') {
                try {
                    window.__liltUseNextPrev =
                        localStorage.getItem('liltUseNextPrev') === 'true';
                } catch (e) {
                    window.__liltUseNextPrev = false;
                }
            }

            function withLiltMediaControlInstall(action) {
                var previousFlag = window.__liltInstallingMediaControlHandlers === true;
                window.__liltInstallingMediaControlHandlers = true;
                try {
                    action();
                } finally {
                    window.__liltInstallingMediaControlHandlers = previousFlag;
                }
            }

            function postRemoteCommand(type) {
                window.webkit.messageHandlers.singletonPlayer
                    .postMessage({
                        type: type,
                        documentGeneration: window.__liltDocumentGeneration,
                        commandIssuedAtMilliseconds: __liltEventTimestampMilliseconds(),
                        observerEpoch: observerEpoch,
                        documentID: documentID
                    });
            }

            // Play/pause media keys reach WebKit's own Now Playing session. Route them through
            // the native player so its pause intent and the page's playback suppression are
            // cleared together; otherwise a key press after an in-app pause gets re-paused.
            function applyPlayPauseOverride() {
                try {
                    var ms = navigator.mediaSession;
                    withLiltMediaControlInstall(function() {
                        ms.setActionHandler('play', function() { postRemoteCommand('REMOTE_PLAY'); });
                        ms.setActionHandler('pause', function() { postRemoteCommand('REMOTE_PAUSE'); });
                    });
                } catch (e) {}
            }

            function applyOverride() {
                applyPlayPauseOverride();
                if (!window.__liltUseNextPrev) {
                    return;
                }
                try {
                    var ms = navigator.mediaSession;
                    withLiltMediaControlInstall(function() {
                        ms.setActionHandler('seekforward', null);
                        ms.setActionHandler('seekbackward', null);
                        ms.setActionHandler('nexttrack', function() { postRemoteCommand('REMOTE_NEXT'); });
                        ms.setActionHandler('previoustrack', function() { postRemoteCommand('REMOTE_PREVIOUS'); });
                    });
                } catch (e) {}
            }

            window.__liltRefreshMediaControlStyle = function() {
                applyOverride();
            };

            window.__liltRefreshMediaControlStyle();

            // Re-apply on bounded page lifecycle events where YouTube recreates the player.
            function attachVideoOverride() {
                var v = document.querySelector('video');
                if (!v || v.__liltOverrideAttached) return;
                v.__liltOverrideAttached = true;
                ['playing','loadedmetadata','loadeddata','canplay','seeked']
                    .forEach(function(e) { v.addEventListener(e, applyOverride); });
                applyOverride();
            }

            attachVideoOverride();
            new MutationObserver(attachVideoOverride)
                .observe(document.documentElement, {childList:true, subtree:true});
        })();
        """
    }

    // MARK: - Playback Audio Quality

    /// Updates the current page and the bootstrap state used by future page loads.
    func setPlaybackAudioQuality(_ quality: SettingsManager.PlaybackAudioQuality) {
        self.playbackAudioQuality = quality
        self.refreshInstalledUserScripts()

        guard let webView = self.webView else { return }
        let script = Self.playbackAudioQualitySyncScript(quality: quality)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func playbackAudioQualityBootstrapScript() -> String {
        Self.playbackAudioQualityBootstrapScript(quality: self.playbackAudioQuality)
    }
}
