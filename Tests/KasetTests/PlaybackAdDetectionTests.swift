import JavaScriptCore
import Testing
@testable import Kaset

@Suite("Playback ad detection", .tags(.service))
@MainActor
struct PlaybackAdDetectionTests {
    @Test("The music player identifies interrupting ads")
    func interruptingAds() throws {
        let context = try self.makeContext()
        try self.evaluate("moviePlayer.classes['ad-interrupting'] = true;", in: context)

        try self.installObserver(in: context)

        #expect(context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("The music player identifies ad media without a CSS marker")
    func presentingAdPlayer() throws {
        let context = try self.makeContext()
        try self.evaluate(
            "musicApi.presentingType = 2;",
            in: context
        )

        try self.installObserver(in: context)

        #expect(context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("The music player requests server-stitched ad state")
    func serverStitchedAdState() throws {
        let context = try self.makeContext()
        try self.evaluate(
            """
            musicApi.getPresentingPlayerType = function(includeStitchedAds) {
                return includeStitchedAds === true ? 2 : 1;
            };
            """,
            in: context
        )

        try self.installObserver(in: context)

        #expect(context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("Ordinary and remote playback do not become ads")
    func contentIsNotAnAd() throws {
        for presentingType in ["1", "3", "undefined", "null", "'2'"] {
            let context = try self.makeContext()
            try self.evaluate(
                "moviePlayer.presentingType = \(presentingType); musicApi.presentingType = \(presentingType);",
                in: context
            )

            try self.installObserver(in: context)

            #expect(!context.evaluateScript("lastState().isAd").toBool())
        }
    }

    @Test("A failing player API preserves CSS ad detection")
    func failingAPIKeepsDOMFallback() throws {
        let context = try self.makeContext()
        try self.evaluate(
            """
            moviePlayer.getPresentingPlayerType = function() { throw new Error('not ready'); };
            musicApi.getPresentingPlayerType = moviePlayer.getPresentingPlayerType;
            moviePlayer.classes['ad-showing'] = true;
            """,
            in: context
        )

        try self.installObserver(in: context)

        #expect(context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("A failed API probe does not interrupt state updates")
    func failedAPIProbe() throws {
        let context = try self.makeContext()
        try self.evaluate(
            """
            moviePlayer.getPresentingPlayerType = function() { throw new Error('not ready'); };
            musicApi.presentingType = 2;
            """,
            in: context
        )

        try self.installObserver(in: context)

        #expect(context.evaluateScript("lastState().isAd").toBool())
        #expect(context.evaluateScript("lastState().progress").toDouble() == 12)
    }

    @Test("Paused players report ad class changes without media events")
    func pausedAdTransitions() throws {
        let context = try self.makeContext()
        try self.installObserver(in: context)
        try self.evaluate(
            """
            postedMessages = [];
            moviePlayer.classes['ad-showing'] = true;
            notifyClassChange(moviePlayer);
            """,
            in: context
        )
        #expect(context.evaluateScript("stateCount()").toInt32() == 1)
        #expect(context.evaluateScript("lastState().isAd").toBool())

        try self.evaluate(
            """
            notifyClassChange(moviePlayer);
            delete moviePlayer.classes['ad-showing'];
            notifyClassChange(moviePlayer);
            """,
            in: context
        )
        #expect(context.evaluateScript("stateCount()").toInt32() == 2)
        #expect(!context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("Ad player events report transitions while paused", arguments: ["onAdStart", "onAdStateChange"])
    func playerAdEvents(event: String) throws {
        let context = try self.makeContext()
        try self.installObserver(in: context)
        try self.evaluate(
            """
            postedMessages = [];
            var activeApi = musicApi;
            activeApi.presentingType = 2;
            activeApi.fire('\(event)');
            """,
            in: context
        )
        #expect(context.evaluateScript("stateCount()").toInt32() == 1)
        #expect(context.evaluateScript("lastState().isAd").toBool())

        try self.evaluate("activeApi.presentingType = 1; activeApi.fire('onAdEnd');", in: context)
        #expect(context.evaluateScript("stateCount()").toInt32() == 2)
        #expect(!context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("Player replacement reconnects ad observation without stale listeners")
    func replacementPlayer() throws {
        let context = try self.makeContext()
        let playerAPI = "musicPlayer.playerApi"
        try self.installObserver(in: context)
        try self.evaluate(
            """
            var oldPlayer = \(playerAPI);
            var replacementPlayer = makePlayer();
            \(playerAPI) = replacementPlayer;
            replacementPlayer.presentingType = 2;
            notifyChildrenChanged();
            timers.splice(0).forEach(function(callback) { callback(); });
            notifyChildrenChanged();
            timers.splice(0).forEach(function(callback) { callback(); });
            """,
            in: context
        )
        #expect(context.evaluateScript("lastState().isAd").toBool())
        #expect(context.evaluateScript("replacementPlayer.listeners.onAdStart.length").toInt32() == 1)

        try self.evaluate("postedMessages = []; oldPlayer.fire('onAdStart');", in: context)
        #expect(context.evaluateScript("stateCount()").toInt32() == 0)
        try self.evaluate("replacementPlayer.presentingType = 1; replacementPlayer.fire('onAdEnd');", in: context)
        #expect(context.evaluateScript("stateCount()").toInt32() == 1)
        #expect(!context.evaluateScript("lastState().isAd").toBool())

        // Class observation must still follow the current movie-player element.
        try self.evaluate(
            "postedMessages = []; moviePlayer.classes['ad-showing'] = true; notifyClassChange(moviePlayer);",
            in: context
        )
        #expect(context.evaluateScript("stateCount()").toInt32() == 1)
        #expect(context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("Ad listeners attach when the player API initializes late", arguments: [false, true])
    func latePlayerAPI(notifiesChildren: Bool) throws {
        let context = try self.makeContext()
        try self.evaluate(
            """
            var activeApi = musicApi;
            var playerAddEventListener = activeApi.addEventListener;
            var presentingPlayerType = activeApi.getPresentingPlayerType;
            delete activeApi.getPresentingPlayerType;
            activeApi.addEventListener = function() {};
            """,
            in: context
        )
        try self.installObserver(in: context)
        try self.evaluate(
            """
            activeApi.getPresentingPlayerType = presentingPlayerType;
            activeApi.addEventListener = playerAddEventListener;
            if (\(notifiesChildren)) notifyChildrenChanged();
            timers.splice(0).forEach(function(callback) { callback(); });
            postedMessages = [];
            activeApi.presentingType = 2;
            activeApi.fire('onAdStart');
            """,
            in: context
        )

        #expect(context.evaluateScript("stateCount()").toInt32() == 1)
        #expect(context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("Music ad listeners attach when the API object appears without DOM changes")
    func lateMusicAPIObject() throws {
        let context = try self.makeContext()
        try self.evaluate("delete musicPlayer.playerApi;", in: context)
        try self.installObserver(in: context)

        try self.evaluate(
            """
            musicPlayer.playerApi = musicApi;
            timers.splice(0).forEach(function(callback) { callback(); });
            postedMessages = [];
            musicApi.presentingType = 2;
            musicApi.fire('onAdStart');
            """,
            in: context
        )

        #expect(context.evaluateScript("stateCount()").toInt32() == 1)
        #expect(context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("API hookup retries stop after readiness or the retry limit", arguments: [false, true])
    func apiAttachmentRetriesStop(apiBecomesReady: Bool) throws {
        let context = try self.makeContext()
        try self.evaluate(
            """
            var presentingPlayerType = moviePlayer.getPresentingPlayerType;
            delete moviePlayer.getPresentingPlayerType;
            \(PlaybackAdDetectionScript.detection)
            \(PlaybackAdDetectionScript.observation)
            var adChanges = 0;
            var refresh = observeAdStateChanges(function() { adChanges += 1; });
            refresh();
            var retryTurns = 0;
            while (timers.length && retryTurns < 100) {
                if (\(apiBecomesReady)) moviePlayer.getPresentingPlayerType = presentingPlayerType;
                timers.splice(0).forEach(function(callback) { callback(); });
                retryTurns += 1;
            }
            moviePlayer.presentingType = 2;
            moviePlayer.fire('onAdStart');
            """,
            in: context
        )

        #expect(context.evaluateScript("retryTurns").toInt32() > 0)
        #expect(context.evaluateScript("timers.length").toInt32() == 0)
        #expect(context.evaluateScript("adChanges").toInt32() == (apiBecomesReady ? 1 : 0))
    }

    @Test("Ad-end events clear ads first observed through media updates")
    func adEndAfterMediaSample() throws {
        let context = try self.makeContext()
        try self.installObserver(in: context)
        try self.evaluate(
            """
            var activeApi = musicApi;
            activeApi.presentingType = 2;
            fireVideoEvent('waiting');
            """,
            in: context
        )
        #expect(context.evaluateScript("lastState().isAd").toBool())

        try self.evaluate(
            """
            postedMessages = [];
            activeApi.presentingType = 1;
            activeApi.fire('onAdEnd');
            """,
            in: context
        )
        #expect(context.evaluateScript("stateCount()").toInt32() == 1)
        #expect(!context.evaluateScript("lastState().isAd").toBool())
    }

    @Test("Ended events retain ad classification", arguments: [false, true])
    func adEndsAreNotContentEnds(signalClearsFirst: Bool) throws {
        let context = try self.makeContext()
        try self.evaluate(
            "currentData = { video_id: 'creative', title: 'Advertisement' }; moviePlayer.presentingType = 2; musicApi.presentingType = 2;",
            in: context
        )
        try self.installObserver(in: context)
        if signalClearsFirst {
            try self.evaluate("moviePlayer.presentingType = 1; musicApi.presentingType = 1;", in: context)
        }
        try self.evaluate("postedMessages = []; video.ended = true; fireVideoEvent('ended');", in: context)

        #expect(context.evaluateScript(
            "postedMessages.filter(function(message) { return message.type === 'TRACK_ENDED'; })[0].isAd"
        ).toBool())
    }

    @Test("Music ad metadata does not consume the first content update")
    func musicMetadataWaitsForContent() throws {
        let context = try self.makeContext()
        try self.evaluate("moviePlayer.classes['ad-showing'] = true;", in: context)
        try self.installObserver(in: context)
        #expect(!context.evaluateScript("lastState().trackChanged").toBool())

        try self.evaluate(
            """
            delete moviePlayer.classes['ad-showing'];
            fireVideoEvent('waiting');
            """,
            in: context
        )
        #expect(!context.evaluateScript("lastState().isAd").toBool())
        #expect(context.evaluateScript("lastState().trackChanged").toBool())
    }

    @Test("Music ad creatives do not create content metadata transitions")
    func musicAdCreativeMetadata() throws {
        let context = try self.makeContext()
        try self.installObserver(in: context)
        try self.evaluate(
            """
            var contentData = currentData;
            currentData = { video_id: 'creative', title: 'Advertisement', author: 'Advertiser' };
            moviePlayer.classes['ad-showing'] = true;
            fireVideoEvent('waiting');
            """,
            in: context
        )
        #expect(context.evaluateScript("lastState().isAd").toBool())
        #expect(!context.evaluateScript("lastState().trackChanged").toBool())

        try self.evaluate(
            """
            currentData = contentData;
            delete moviePlayer.classes['ad-showing'];
            fireVideoEvent('waiting');
            """,
            in: context
        )
        #expect(!context.evaluateScript("lastState().isAd").toBool())
        #expect(!context.evaluateScript("lastState().trackChanged").toBool())
    }

    @Test("Music waits for content metadata after an early ad-end event", arguments: [false, true], [false, true])
    func musicAdEndBeforeMetadata(startsDuringAd: Bool, textReturnsFirst: Bool) throws {
        let context = try self.makeContext()
        if !startsDuringAd {
            try self.installObserver(in: context)
        }
        try self.evaluate(
            """
            var contentData = currentData;
            currentData = { video_id: 'creative', title: 'Advertisement', author: 'Advertiser' };
            video.currentSrc = 'https://media.example/creative';
            video.currentTime = 0;
            video.duration = 30;
            musicApi.presentingType = 2;
            musicApi.fire('onAdStart');
            """,
            in: context
        )
        if startsDuringAd {
            try self.installObserver(in: context)
        }
        #expect(context.evaluateScript("lastState().isAd").toBool())
        #expect(!context.evaluateScript("lastState().trackChanged").toBool())

        if textReturnsFirst {
            try self.evaluate(
                "currentData.title = contentData.title; currentData.author = contentData.author; fireVideoEvent('waiting');",
                in: context
            )
        }
        try self.evaluate("musicApi.presentingType = 1; musicApi.fire('onAdEnd');", in: context)

        #expect(context.evaluateScript("lastState().isAd").toBool())
        #expect(!context.evaluateScript("lastState().trackChanged").toBool())

        try self.evaluate(
            """
            currentData = contentData;
            video.currentSrc = 'https://media.example/content';
            video.currentTime = 12;
            video.duration = 180;
            fireVideoEvent('waiting');
            """,
            in: context
        )
        #expect(!context.evaluateScript("lastState().isAd").toBool())
        #expect(context.evaluateScript("lastState().trackChanged").toBool() == startsDuringAd)
        #expect(context.evaluateScript("lastState().videoId").toString() == "content")
        #expect(context.evaluateScript("lastState().title").toString() == "Song")
    }

    @Test("The music player accepts requested content when its metadata leads the watch URL during an ad")
    func requestedMetadataDuringAd() throws {
        let context = try self.makeContext()
        try self.installObserver(in: context)
        try self.evaluate(
            """
            currentData = { video_id: 'next', title: 'Next song', author: 'Artist' };
            var activeApi = musicApi;
            activeApi.presentingType = 2;
            activeApi.fire('onAdStart');
            window.location.href = 'https://music.youtube.com/watch?v=next';
            activeApi.presentingType = 1;
            activeApi.fire('onAdEnd');
            """,
            in: context
        )

        #expect(!context.evaluateScript("lastState().isAd").toBool())
        #expect(context.evaluateScript("lastState().trackChanged").toBool())
        #expect(context.evaluateScript("lastState().videoId").toString() == "next")
    }

    @Test("Early ad-end events preserve native content state", arguments: [false, true])
    func earlyAdEndPreservesNativeState(contentIDReturnsFirst: Bool) throws {
        let context = try self.makeContext()
        try self.installObserver(in: context)
        try self.evaluate(
            """
            var contentData = currentData;
            var activeApi = musicApi;
            currentData = { video_id: 'creative', title: 'Advertisement', author: 'Advertiser' };
            video.currentSrc = 'https://media.example/creative';
            video.currentTime = 0;
            video.duration = 30;
            activeApi.presentingType = 2;
            activeApi.fire('onAdStart');
            if (\(contentIDReturnsFirst)) currentData = contentData;
            activeApi.presentingType = 1;
            activeApi.fire('onAdEnd');
            """,
            in: context
        )
        let isAd = context.evaluateScript("lastState().isAd").toBool()
        let hasReadyMedia = context.evaluateScript("lastState().hasReadyMedia").toBool()
        #expect(context.evaluateScript("video.__kasetBoundVideoId").toString() == "creative")
        #expect(isAd)
        let standaloneDetection = """
        (function() {
            \(PlaybackAdDetectionScript.detection)
            return isAdShowing();
        })();
        """
        #expect(context.evaluateScript(standaloneDetection).toBool())
        #expect(!SingletonPlayerWebView.isAuthoritativePlaybackSample(
            hasReadyMedia: hasReadyMedia,
            isShowingAd: isAd
        ))

        try self.evaluate("currentData = null;", in: context)
        #expect(context.evaluateScript(standaloneDetection).toBool())
        try self.evaluate(
            """
            currentData = contentData;
            video.currentSrc = 'https://media.example/content';
            video.currentTime = 12;
            video.duration = 180;
            fireVideoEvent('waiting');
            """,
            in: context
        )
        #expect(!context.evaluateScript("lastState().isAd").toBool())
        #expect(context.evaluateScript("lastState().videoId").toString() == "content")
    }

    @Test("Consecutive creatives remain ads between player ad signals")
    func consecutiveAdCreatives() throws {
        let context = try self.makeContext()
        try self.installObserver(in: context)
        try self.evaluate(
            """
            var contentData = currentData;
            var activeApi = musicApi;
            currentData = { video_id: 'creative-one', title: 'First ad' };
            video.currentSrc = 'https://media.example/creative-one';
            video.currentTime = 0;
            video.duration = 30;
            activeApi.presentingType = 2;
            activeApi.fire('onAdStart');
            activeApi.presentingType = 1;
            currentData = { video_id: 'creative-two', title: 'Second ad' };
            video.currentSrc = 'https://media.example/creative-two';
            activeApi.fire('onAdEnd');
            """,
            in: context
        )

        #expect(context.evaluateScript("video.__kasetBoundVideoId").toString() == "creative-two")
        #expect(context.evaluateScript("lastState().isAd").toBool())
        #expect(!context.evaluateScript("lastState().trackChanged").toBool())

        try self.evaluate(
            """
            currentData = contentData;
            video.currentSrc = 'https://media.example/content';
            video.currentTime = 12;
            video.duration = 180;
            fireVideoEvent('waiting');
            """,
            in: context
        )
        #expect(!context.evaluateScript("lastState().isAd").toBool())
        #expect(context.evaluateScript("video.__kasetBoundVideoId").toString() == "content")
    }

    private func installObserver(in context: JSContext) throws {
        try self.evaluate(SingletonPlayerWebView.observerScript, in: context)
    }

    private func makeContext() throws -> JSContext {
        let context = try #require(JSContext())
        try self.evaluate(
            """
            var window = globalThis;
            var postedMessages = [];
            var videoListeners = {};
            var observers = [];
            var timers = [];
            var currentData = { video_id: 'content', title: 'Song', author: 'Artist' };
            var console = { log: function() {} };
            window.__kasetDocumentGeneration = 7;
            window.location = { href: 'https://music.youtube.com/watch?v=content' };
            // JavaScriptCore has no browser URL API.
            var URL = function(value) { this.searchParams = { get: key => value.match(new RegExp('[?&]' + key + '=([^&]*)'))?.[1] || null }; };
            var bridge = { postMessage: function(message) { postedMessages.push(message); } };
            window.webkit = { messageHandlers: { singletonPlayer: bridge, youtubePlayer: bridge } };
            function setTimeout(callback) { timers.push(callback); return timers.length; }
            function clearTimeout() {}
            function setInterval() { return 1; }
            function clearInterval() {}
            function lastState() {
                return postedMessages.filter(function(message) { return message.type === 'STATE_UPDATE'; }).pop() || {};
            }
            function stateCount() {
                return postedMessages.filter(function(message) { return message.type === 'STATE_UPDATE'; }).length;
            }
            function fireVideoEvent(name) {
                (videoListeners[name] || []).forEach(function(handler) { handler({ type: name, currentTarget: video }); });
            }
            function makePlayer() {
                var player = {
                    classes: {},
                    listeners: {},
                    presentingType: 1,
                    getPresentingPlayerType: function() { return this.presentingType; },
                    getVideoData: function() { return currentData; },
                    addEventListener: function(name, handler) {
                        if (!this.listeners[name]) this.listeners[name] = [];
                        this.listeners[name].push(handler);
                    },
                    removeEventListener: function(name, handler) {
                        this.listeners[name] = (this.listeners[name] || []).filter(function(item) { return item !== handler; });
                    },
                    fire: function(name) { (this.listeners[name] || []).slice().forEach(function(handler) { handler(); }); }
                };
                player.classList = { contains: function(name) { return player.classes[name] === true; } };
                return player;
            }
            var moviePlayer = makePlayer();
            var musicApi = makePlayer();
            var musicPlayer = { playerApi: musicApi };
            var playerBar = { querySelector: function() { return null; } };
            var video = {
                currentTime: 12, duration: 180, currentSrc: 'https://media.example/content',
                paused: true, ended: false, readyState: 4, volume: 1, muted: false,
                seekable: { length: 1, start: function() { return 0; }, end: function() { return 180; } },
                addEventListener: function(name, handler) {
                    if (!videoListeners[name]) videoListeners[name] = [];
                    videoListeners[name].push(handler);
                }
            };
            var document = {
                title: 'Song - YouTube', readyState: 'complete', body: {}, documentElement: {},
                getElementById: function(id) { return id === 'movie_player' ? moviePlayer : null; },
                querySelector: function(selector) {
                    if (selector === 'video' || selector === '#movie_player video') return video;
                    if (selector === 'ytmusic-player' && true) return musicPlayer;
                    if (selector === '[slot="player-bar"]' && true) return playerBar;
                    return null;
                },
                querySelectorAll: function() { return []; },
                addEventListener: function() {}
            };
            function MutationObserver(callback) {
                this.callback = callback;
                observers.push(this);
            }
            MutationObserver.prototype.observe = function(target, options) { this.target = target; this.options = options; };
            MutationObserver.prototype.disconnect = function() { this.target = null; };
            function notifyClassChange(target) {
                observers.slice().forEach(function(observer) {
                    if (observer.target === target && observer.options.attributes
                        && observer.options.attributeFilter.indexOf('class') !== -1) {
                        observer.callback([{ type: 'attributes', target: target, attributeName: 'class' }]);
                    }
                });
            }
            function notifyChildrenChanged() {
                observers.slice().forEach(function(observer) {
                    if ((observer.target === document.body || observer.target === document.documentElement)
                        && observer.options.childList) {
                        observer.callback([{ type: 'childList', target: observer.target }]);
                    }
                });
            }
            """,
            in: context
        )
        return context
    }

    private func evaluate(_ script: String, in context: JSContext) throws {
        context.exception = nil
        context.evaluateScript(script)
        try #require(context.exception == nil, "JavaScript exception: \(context.exception?.toString() ?? "")")
    }
}
