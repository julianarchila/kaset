import Testing
import WebKit
@testable import Lilt

@Suite("Playback WebView teardown", .serialized, .tags(.service))
@MainActor
struct PlaybackWebViewTeardownTests {
    @Test("Music teardown releases its coordinator while the WebView remains retained")
    func musicTeardownReleasesCoordinator() {
        let singleton = SingletonPlayerWebView.makeTestInstance()

        let webKitManager = WebKitManager.makeTestInstance()
        let playerService = PlayerService()
        let retainedWebView = singleton.getWebView(
            webKitManager: webKitManager,
            playerService: playerService
        )
        weak var coordinator = singleton.coordinator

        #expect(coordinator != nil)
        playerService.updateAirPlayStatus(isConnected: true)
        singleton.tearDown()

        #expect(!playerService.isAirPlayConnected)
        #expect(retainedWebView.navigationDelegate == nil)
        #expect(coordinator == nil)
    }

    @Test("Only the current music WebContent process can clear its AirPlay connection")
    func musicContentProcessLossClearsCurrentConnection() {
        let singleton = SingletonPlayerWebView.makeTestInstance()
        let playerService = PlayerService()
        let webView = singleton.getWebView(
            webKitManager: WebKitManager.makeTestInstance(),
            playerService: playerService
        )
        defer { singleton.tearDown() }
        let unrelatedWebView = WKWebView()
        playerService.updateAirPlayStatus(isConnected: true)

        singleton.recoverFromContentProcessTermination(webView: unrelatedWebView)
        #expect(playerService.isAirPlayConnected)

        singleton.recoverFromContentProcessTermination(webView: webView)
        #expect(!playerService.isAirPlayConnected)
    }
}
