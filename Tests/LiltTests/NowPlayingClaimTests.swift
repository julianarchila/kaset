import Foundation
import MediaPlayer
import Testing
@testable import Lilt

@Suite("Now playing claim", .serialized, .tags(.service))
struct NowPlayingClaimTests {
    @Test("Actively playing or starting yields hands-off (WebKit owns the card)")
    func activePlaybackIsHandsOff() {
        let track = (title: "Song", artist: "Artist")
        #expect(NowPlayingManager.desiredClaim(state: .playing, track: track) == .handsOff)
        #expect(NowPlayingManager.desiredClaim(state: .buffering, track: track) == .handsOff)
        #expect(NowPlayingManager.desiredClaim(state: .loading, track: track) == .handsOff)
    }

    @Test("Not playing with a track yields a minimal claim")
    func pausedWithTrackClaims() {
        let track = (title: "Song", artist: "Artist")
        let expected = NowPlayingManager.NowPlayingClaim.claim(
            title: "Song",
            artist: "Artist",
            playbackState: .paused
        )
        #expect(NowPlayingManager.desiredClaim(state: .paused, track: track) == expected)
        #expect(NowPlayingManager.desiredClaim(state: .ended, track: track) == expected)
        #expect(NowPlayingManager.desiredClaim(state: .idle, track: track) == expected)
        #expect(NowPlayingManager.desiredClaim(state: .error("boom"), track: track) == expected)
    }

    @Test("Not playing with no track releases the native claim")
    func idleWithoutTrackReleasesClaim() {
        #expect(NowPlayingManager.desiredClaim(state: .idle, track: nil) == .release)
        #expect(NowPlayingManager.desiredClaim(state: .paused, track: nil) == .release)
    }

    @Test("Only tagged native metadata is treated as Lilt's claim")
    func nativeClaimOwnershipTag() {
        let nativeInfo: [String: Any] = [
            MPNowPlayingInfoPropertyServiceIdentifier: NowPlayingManager.nativeClaimServiceIdentifier,
        ]
        let webKitInfo: [String: Any] = [MPMediaItemPropertyTitle: "Song"]

        #expect(NowPlayingManager.isNativeClaim(nativeInfo))
        #expect(NowPlayingManager.isNativeClaim(webKitInfo) == false)
        #expect(NowPlayingManager.isNativeClaim(nil) == false)
    }

    @Test("An active WebKit Now Playing session releases the native claim in every state")
    func webKitSessionReleasesClaim() {
        let track = (title: "Song", artist: "Artist")
        let states: [PlayerService.PlaybackState] = [.idle, .loading, .buffering, .playing, .paused, .ended, .error("boom")]
        for state in states {
            #expect(NowPlayingManager.desiredClaim(state: state, track: track, webKitHasSession: true) == .release)
        }
    }

    @Test("Without a WebKit session, or when unknown, the paused fallback claim is kept")
    func missingOrUnknownWebKitSessionKeepsClaim() {
        let track = (title: "Song", artist: "Artist")
        let expected = NowPlayingManager.NowPlayingClaim.claim(
            title: "Song",
            artist: "Artist",
            playbackState: .paused
        )
        #expect(NowPlayingManager.desiredClaim(state: .paused, track: track, webKitHasSession: false) == expected)
        #expect(NowPlayingManager.desiredClaim(state: .paused, track: track, webKitHasSession: nil) == expected)
        #expect(NowPlayingManager.desiredClaim(state: .loading, track: track, webKitHasSession: false) == .handsOff)
    }
}
