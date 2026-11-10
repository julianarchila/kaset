import Foundation
import Testing
@testable import Lilt

/// Play/pause media keys reach WebKit's Now Playing session; the page forwards them to the
/// native player so an in-app pause can be resumed with the Play key (ADR-0045).
@Suite("Media Session play/pause routing", .tags(.service))
@MainActor
struct MediaSessionPlayPauseRoutingTests {
    @Test("Media Session bridge messages map to native transport commands")
    func mediaSessionMessagesMapToTransportCommands() {
        typealias Coordinator = SingletonPlayerWebView.Coordinator
        #expect(Coordinator.remoteTransportCommand(forMessageType: "REMOTE_PLAY") == .play)
        #expect(Coordinator.remoteTransportCommand(forMessageType: "REMOTE_PAUSE") == .pause)
        #expect(Coordinator.remoteTransportCommand(forMessageType: "REMOTE_NEXT") == .next)
        #expect(Coordinator.remoteTransportCommand(forMessageType: "REMOTE_PREVIOUS") == .previous)
        #expect(Coordinator.remoteTransportCommand(forMessageType: "STATE_UPDATE") == nil)
    }

    @Test("YouTube cannot register its own play/pause handlers")
    func bootstrapBlocksPagePlayPauseHandlers() {
        for useNextPrev in [false, true] {
            let bootstrap = SingletonPlayerWebView.mediaControlStyleBootstrapScript(useNextPrev: useNextPrev)
            #expect(bootstrap.contains("var isPlayPause = type === 'play' || type === 'pause';"))
            #expect(bootstrap.contains("if (isPlayPause && !window.__liltInstallingMediaControlHandlers)"))
        }
    }

    @Test("Lilt installs play/pause handlers in every media-control style")
    func overrideInstallsPlayPauseHandlers() {
        let script = SingletonPlayerWebView.mediaControlOverrideScript
        #expect(script.contains("ms.setActionHandler('play', function() { postRemoteCommand('REMOTE_PLAY'); });"))
        #expect(script.contains("ms.setActionHandler('pause', function() { postRemoteCommand('REMOTE_PAUSE'); });"))
        // Installed before the next/previous style check, so it applies in seek mode too.
        let applyOverride = script.components(separatedBy: "function applyOverride() {").last ?? ""
        let playPause = applyOverride.range(of: "applyPlayPauseOverride();")
        let styleCheck = applyOverride.range(of: "if (!window.__liltUseNextPrev)")
        #expect(playPause != nil)
        #expect(styleCheck != nil)
        if let playPause, let styleCheck {
            #expect(playPause.lowerBound < styleCheck.lowerBound)
        }
    }
}
