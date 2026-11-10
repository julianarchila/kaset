import Foundation
import WebKit

/// Observes whether a `WKWebView` currently publishes its own system Now Playing session.
///
/// WebKit publishes the page's media session from its GPU process, which macOS treats as a
/// Now Playing client separate from the app process. When both it and Lilt's native
/// `MPNowPlayingInfoCenter` fallback hold metadata, Control Center shows two entries for Lilt.
/// `_hasActiveNowPlayingSession` is WebKit SPI on `WKWebView` that changes with KVO; when it is
/// unavailable, `hasActiveSession` stays `nil` and callers keep the native fallback.
@MainActor
final class WebKitNowPlayingSessionObserver: NSObject {
    nonisolated static let keyPath = "_hasActiveNowPlayingSession"

    private weak var webView: WKWebView?
    private let onChange: @MainActor () -> Void

    /// `true` or `false` when WebKit reports its Now Playing session; `nil` when not observable.
    private(set) var hasActiveSession: Bool?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        super.init()
    }

    /// Starts observing `webView`, replacing any previously observed instance.
    func observe(_ webView: WKWebView?) {
        guard webView !== self.webView else { return }
        self.stopObserving()
        if let webView, webView.responds(to: NSSelectorFromString(Self.keyPath)) {
            self.webView = webView
            webView.addObserver(self, forKeyPath: Self.keyPath, options: [.initial, .new], context: nil)
        } else {
            self.updateValue(nil)
        }
    }

    private func stopObserving() {
        self.webView?.removeObserver(self, forKeyPath: Self.keyPath)
        self.webView = nil
    }

    private func updateValue(_ value: Bool?) {
        guard value != self.hasActiveSession else { return }
        self.hasActiveSession = value
        self.onChange()
    }

    // swiftlint:disable:next block_based_kvo
    override nonisolated func observeValue(
        forKeyPath keyPath: String?,
        of _: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context _: UnsafeMutableRawPointer?
    ) {
        guard keyPath == Self.keyPath else { return }
        let value = change?[.newKey] as? Bool
        if Thread.isMainThread {
            MainActor.assumeIsolated { self.updateValue(value) }
        } else {
            Task { @MainActor in self.updateValue(value) }
        }
    }
}
