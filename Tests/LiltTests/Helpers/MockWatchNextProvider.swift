import Foundation
@testable import Lilt

/// Configurable mock `WatchNextProviding` for mix-tracklist tests.
@MainActor
final class MockWatchNextProvider: WatchNextProviding {
    var watchNextData = WatchNextData.empty

    /// Thrown from `getWatchNext(videoId:)` when set.
    var error: Error?

    private(set) var getWatchNextCallCount = 0
    private(set) var getWatchNextCompletionCount = 0
    private(set) var requestedWatchNextVideoIds: [String] = []

    /// Awaited before returning so tests can gate by requested video identity.
    var beforeWatchNextReturn: (@Sendable (String) async -> Void)?

    /// Awaited before returning so playback tests can gate a specific call ordinal.
    var beforeWatchNextReturnByCallCount: (@Sendable (Int) async -> Void)?

    func getWatchNext(videoId: String) async throws -> WatchNextData {
        self.getWatchNextCallCount += 1
        self.requestedWatchNextVideoIds.append(videoId)
        if let error {
            throw error
        }
        if let beforeWatchNextReturn {
            await beforeWatchNextReturn(videoId)
        }
        if let beforeWatchNextReturnByCallCount {
            await beforeWatchNextReturnByCallCount(self.getWatchNextCallCount)
        }
        try Task.checkCancellation()
        self.getWatchNextCompletionCount += 1
        return self.watchNextData
    }
}
