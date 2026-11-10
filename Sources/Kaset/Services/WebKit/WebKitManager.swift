import Foundation
import os
import Security
import WebKit

// MARK: - WebKitManager

/// Manages WebKit data store for persistent cookies and session management.
@MainActor
@Observable
final class WebKitManager: NSObject, WebKitManagerProtocol {
    /// Shared singleton instance.
    static let shared = WebKitManager(dataStore: .default(), restoresCookies: true)

    /// Creates an isolated manager for unit tests. The cookie archive queue is private to the
    /// instance and backed by in-memory storage, so parallel suites cannot clear or overwrite
    /// each other's archive through the process-wide `CookieArchiveWriteQueue.shared`.
    static func makeTestInstance(
        cookieArchiveStorage: CookieArchiveStorage = .inMemory()
    ) -> WebKitManager {
        WebKitManager(
            dataStore: .nonPersistent(),
            restoresCookies: false,
            cookieArchiveQueue: CookieArchiveWriteQueue(storage: cookieArchiveStorage)
        )
    }

    /// The persistent website data store used across all WebViews.
    let dataStore: WKWebsiteDataStore

    /// Serializes archive reads and writes for this manager's cookies. Defaults to the
    /// process-wide queue so production keeps a single archive; tests inject their own.
    let cookieArchiveQueue: CookieArchiveWriteQueue

    /// Timestamp of the last cookie change (for observation).
    private(set) var cookiesDidChange: Date = .distantPast

    func recordCookieChange() {
        self.cookiesDidChange = Date()
    }

    /// Flag to prevent cookie backups while restoring from Keychain.
    var isRestoringCookies = false

    /// Flag to prevent observer-driven backups while auth cookies are being cleared.
    var isClearingAuthCookies = false

    /// Serializes and coalesces every auth-cookie/data clearing operation.
    let authCookieClearCoordinator = AuthCookieClearCoordinator()

    /// Task for debouncing cookie change handling.
    var cookieDebounceTask: Task<Void, Never>?

    /// Coalesces callers that require the latest cookie snapshot to be persisted.
    var forcedCookieBackupTask: Task<Bool, Never>?

    /// Suppresses observer-driven persistence while a login baseline is captured.
    var isPreparingLoginCookieBackup = false

    /// Suppresses observer-driven persistence while a login backup is staged.
    var activeLoginCookieBackupTransaction: CookieBackupTransaction?

    /// Whether transaction setup failed to restore its prior durable state.
    var loginCookieBackupSetupRequiresCleanup = false

    /// Records cookie changes delivered while a forced snapshot is being persisted.
    var forcedCookieBackupDirty = false

    /// Coalesces startup restoration and retries after temporary storage failures.
    var initialCookieRestoreTask: Task<CookieRestoreResult, Never>?

    /// Authentication and archive writes stay blocked until restoration is resolved.
    var initialCookieRestoreResult: CookieRestoreResult = .ready

    /// Invalidates startup restores and backups that began before an auth-cookie clear.
    var authCookieOperationFence = AuthCookieOperationFence()

    /// Minimum interval between cookie backup operations (in seconds).
    static let cookieDebounceInterval: Duration = .seconds(5)

    /// The YouTube Music origin URL.
    static let origin = "https://music.youtube.com"

    /// Required cookie name for authentication.
    nonisolated static let authCookieName = "__Secure-3PAPISID"

    /// Fallback cookie name (non-secure version).
    nonisolated static let fallbackAuthCookieName = "SAPISID"

    /// Custom user agent to appear as Safari to avoid "browser not supported" errors.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    let logger = DiagnosticsLogger.webKit

    private init(
        dataStore: WKWebsiteDataStore,
        restoresCookies: Bool,
        cookieArchiveQueue: CookieArchiveWriteQueue = .shared
    ) {
        self.dataStore = dataStore
        self.cookieArchiveQueue = cookieArchiveQueue

        super.init()

        // Observe cookie changes
        self.dataStore.httpCookieStore.add(self)

        // Restore auth cookies on startup.
        // Keychain is the source of truth; in DEBUG builds we also export to cookies.dat for tooling.
        if restoresCookies, !UITestConfig.isRunningUnitTests {
            self.startInitialCookieRestore()
        }

        self.logger.info("WebKitManager initialized with persistent data store")
    }

    /// Creates a WebView configuration using the shared persistent data store by default.
    func createWebViewConfiguration(websiteDataStore: WKWebsiteDataStore? = nil) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore ?? self.dataStore

        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Enable AirPlay for streaming to Apple TV, HomePod, etc.
        configuration.allowsAirPlayForMediaPlayback = true

        return configuration
    }

    /// Creates the minimal WebView configuration used for the login sheet and
    /// hidden account-switch navigations. It deliberately shares only the
    /// website data store (cookies). It also suppresses WebAuthn
    /// passkey detection so Google's sign-in falls back to flows that can
    /// succeed in an embedded WebView (ADR-0033).
    func createSessionSwitchWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = self.dataStore
        configuration.userContentController.addUserScript(LoginPasskeySuppression.makeUserScript())
        return configuration
    }

    /// Retrieves all cookies from the HTTP cookie store.
    func getAllCookies() async -> [HTTPCookie] {
        await self.dataStore.httpCookieStore.allCookies()
    }

    /// Gets cookies for a specific domain.
    /// Uses proper domain matching: exact match or cookie domain with leading dot matches subdomains.
    func getCookies(for domain: String) async -> [HTTPCookie] {
        let allCookies = await getAllCookies()
        return Self.cookies(allCookies, matching: domain)
    }

    /// Builds a Cookie header string for the given domain.
    func cookieHeader(for domain: String) async -> String? {
        let cookies = await getCookies(for: domain)
        guard !cookies.isEmpty else { return nil }

        let headerFields = HTTPCookie.requestHeaderFields(with: cookies)
        return headerFields["Cookie"]
    }

    /// Retrieves the SAPISID cookie value used for authentication.
    /// Checks both secure and non-secure cookie variants.
    func getSAPISID() async -> String? {
        let cookies = await getCookies(for: "youtube.com")
        let allCookies = await getAllCookies()
        self.logger.debug("Checking for SAPISID - total cookies: \(allCookies.count), youtube.com cookies: \(cookies.count)")

        // Try secure cookie first, then fallback to non-secure
        let secureCookie = cookies.first { $0.name == Self.authCookieName }
        let fallbackCookie = cookies.first { $0.name == Self.fallbackAuthCookieName }

        if let cookie = secureCookie ?? fallbackCookie {
            // Log cookie expiration for debugging session issues
            if let expiresDate = cookie.expiresDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                let expiresStr = formatter.string(from: expiresDate)
                let isExpired = expiresDate < Date()
                self.logger.debug("Found \(cookie.name) cookie, expires: \(expiresStr), expired: \(isExpired)")

                if isExpired {
                    self.logger.warning("Auth cookie has expired!")
                    return nil
                }
            } else if cookie.isSessionOnly {
                self.logger.debug("Found \(cookie.name) cookie (session-only, no expiration)")
            }
            return cookie.value
        }

        let cookieNames = cookies.map(\.name).joined(separator: ", ")
        self.logger.debug("No auth cookie found. Available cookies: \(cookieNames)")
        return nil
    }

    /// Checks if the required authentication cookies exist.
    func hasAuthCookies() async -> Bool {
        let sapisid = await getSAPISID()
        return sapisid != nil
    }

    /// Logs all authentication-related cookies for debugging.
    /// Call this when troubleshooting login persistence issues.
    func logAuthCookies() async {
        let cookies = await getCookies(for: "youtube.com")
        let authCookieNames = ["SAPISID", "__Secure-3PAPISID", "SID", "HSID", "SSID", "APISID", "__Secure-1PAPISID"]

        self.logger.info("=== Auth Cookie Diagnostic ===")
        self.logger.info("Total youtube.com cookies: \(cookies.count)")

        for name in authCookieNames {
            if let cookie = cookies.first(where: { $0.name == name }) {
                let expiry: String
                if let date = cookie.expiresDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    expiry = formatter.string(from: date)
                } else if cookie.isSessionOnly {
                    expiry = "session-only"
                } else {
                    expiry = "unknown"
                }
                self.logger.info("✓ \(name): expires \(expiry)")
            } else {
                self.logger.info("✗ \(name): not found")
            }
        }
        self.logger.info("==============================")
    }

    /// Clears only authentication cookies, preserving public WebKit cache/data.
    @discardableResult
    func clearAuthCookies() async -> Bool {
        await self.authCookieClearCoordinator.run(scope: .authenticationCookies) { [weak self] in
            guard let self else { return false }
            return await self.performAuthCookieClear()
        }
    }

    private func performAuthCookieClear() async -> Bool {
        self.logger.notice("Clearing WebKit auth cookies and the saved archive")
        self.isClearingAuthCookies = true
        defer { self.isClearingAuthCookies = false }

        await self.fenceAuthCookieOperationsAndInvalidateBackup()

        // Invalidate once more after the initial fence so no operation that was
        // already queued before it can leave a durable stale snapshot. All live
        // verification happens after this final persistence suspension.
        let didInvalidatePersistedCookies = await self.cookieArchiveQueue.invalidateAndDelete()

        let didClearLiveCookies = await self.deleteLiveLoginSessionCookies(allowsCookieStoreFallback: true)
        let didClear = didClearLiveCookies && didInvalidatePersistedCookies
        self.initialCookieRestoreResult = didClear ? .ready : .failed
        self.loginCookieBackupSetupRequiresCleanup = !didClear
        self.cookiesDidChange = Date()
        return didClear
    }

    /// Deletes live login-session cookies from WebKit without touching the
    /// persisted archive or its restore policy.
    func deleteLiveLoginSessionCookies(allowsCookieStoreFallback: Bool) async -> Bool {
        let result = await LiveAuthCookieStoreClearer.clear(
            allowsCookieStoreFallback: allowsCookieStoreFallback,
            operations: LiveAuthCookieStoreClearer.Operations(
                readCookies: {
                    await self.dataStore.httpCookieStore.allCookies()
                },
                deleteCookie: { cookie in
                    await self.dataStore.httpCookieStore.deleteCookie(cookie)
                },
                removeAllCookies: {
                    await self.dataStore.removeData(
                        ofTypes: [WKWebsiteDataTypeCookies],
                        modifiedSince: .distantPast
                    )
                }
            )
        )
        if result.usedCookieStoreFallback {
            self.logger.warning("Escalated authentication cleanup to the WebKit cookie data store")
        }
        if !result.didClear {
            self.logger.error("Could not clear live authentication cookies")
        }
        return result.didClear
    }

    /// Clears all website data (cookies, cache, etc.).
    @discardableResult
    func clearAllData() async -> Bool {
        await self.authCookieClearCoordinator.run(scope: .allWebsiteData) { [weak self] in
            guard let self else { return false }
            return await self.performAllWebsiteDataClear()
        }
    }

    private func performAllWebsiteDataClear() async -> Bool {
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date.distantPast

        self.logger.notice("Clearing all WebKit data and the saved archive")
        self.isClearingAuthCookies = true
        defer { self.isClearingAuthCookies = false }

        await self.fenceAuthCookieOperationsAndInvalidateBackup()
        await self.dataStore.removeData(ofTypes: allTypes, modifiedSince: dateFrom)

        // Repeat the invalidation after WebKit finishes clearing to close the
        // window for any already-enqueued observer or backup work.
        let didInvalidatePersistedCookies = await self.cookieArchiveQueue.invalidateAndDelete()
        let remainingCookies = await self.dataStore.httpCookieStore.allCookies()
        let didClearLiveCookies = !remainingCookies.contains(where: KeychainCookieStorage.isLoginDomainCookie)
        let didClear = didInvalidatePersistedCookies && didClearLiveCookies
        self.initialCookieRestoreResult = didClear ? .ready : .failed
        self.loginCookieBackupSetupRequiresCleanup = !didClear
        if didClear {
            self.logger.info("WebKit data cleared successfully")
        } else {
            self.logger.error("WebKit data or durable cookie invalidation could not be cleared")
        }
        self.cookiesDidChange = Date()
        return didClear
    }

    private func fenceAuthCookieOperationsAndInvalidateBackup() async {
        self.authCookieOperationFence.invalidate()
        self.activeLoginCookieBackupTransaction = nil
        self.cookieDebounceTask?.cancel()
        self.cookieDebounceTask = nil

        let restoreTask = self.initialCookieRestoreTask
        let backupTask = self.forcedCookieBackupTask
        restoreTask?.cancel()
        backupTask?.cancel()

        _ = await self.cookieArchiveQueue.invalidateAndDelete()
        _ = await restoreTask?.value
        _ = await backupTask?.value
    }
}

// MARK: - SessionSwitchError

/// Errors raised while switching the WebView session's active delegated identity.
enum SessionSwitchError: LocalizedError {
    /// The page loaded but its `DATASYNC_ID` did not reflect the expected identity.
    case identityNotApplied(expectedBrandId: String?)
    /// The switch navigation failed to load.
    case navigationFailed(underlying: String)
    /// The switch did not complete within the allotted time.
    case timedOut

    var errorDescription: String? {
        switch self {
        case .identityNotApplied:
            "The account session could not be switched. Please try again."
        case .navigationFailed:
            "Failed to load the account switch page."
        case .timedOut:
            "Switching accounts timed out. Please try again."
        }
    }
}

extension WebKitManager {
    /// Switches the shared cookie session's active delegated identity by
    /// navigating a transient WebView to a server-issued account-switch URL.
    ///
    /// History is recorded by the playback page's own stats pings, which
    /// attribute to the identity baked into the served document's
    /// `ytcfg.DATASYNC_ID` (`"<delegatedSessionId>||<userSessionId>"` for a brand,
    /// `"<userSessionId>||"` for primary). Navigating the brand's `signinUrl`
    /// (which carries `&pageid=<brandId>`) re-points that identity for the single
    /// shared `WKWebsiteDataStore`, so subsequent watch loads — and their history
    /// pings — attribute to the brand.
    ///
    /// The method is verification-gated: it reads `DATASYNC_ID` after the
    /// navigation settles and throws ``SessionSwitchError/identityNotApplied(expectedBrandId:)``
    /// unless the result matches `expectedBrandId` (or, for `nil`, an empty
    /// delegated half indicating the primary identity). Callers should perform
    /// this switch *before* committing the new account so a failure can be
    /// surfaced and reverted rather than silently recording to the wrong account.
    ///
    /// - Parameters:
    ///   - signinURL: The server-issued `accountSigninToken.signinUrl`.
    ///   - expectedBrandId: The brand pageId to verify, or `nil` for the primary.
    func switchSessionIdentity(to signinURL: URL, expectedBrandId: String?) async throws {
        self.logger.info("Switching session identity (expecting \(expectedBrandId ?? "primary"))")
        guard AccountsListParser.isAllowedSigninURL(signinURL) else {
            throw SessionSwitchError.navigationFailed(underlying: "Refusing non-YouTube signin URL")
        }

        let configuration = self.createSessionSwitchWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.userAgent

        // Keep the navigation driver alive for the lifetime of the load.
        let driver = SessionSwitchNavigationDriver()
        webView.navigationDelegate = driver

        defer {
            webView.navigationDelegate = nil
            webView.stopLoading()
        }

        // Bail before mutating the shared cookie session if already cancelled
        // (e.g. a stale launch pin superseded by a newer switch).
        try Task.checkCancellation()

        do {
            try await driver.load(signinURL, in: webView, timeout: .seconds(20))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SessionSwitchError {
            throw error
        } catch {
            throw SessionSwitchError.navigationFailed(underlying: error.localizedDescription)
        }

        // The page's ytcfg may be emitted slightly after didFinish; poll briefly.
        // Note: the navigation above is the session MUTATION; this poll is
        // read-only verification. Correctness across concurrent pins relies on
        // ordering (the surviving navigation runs last), not on cancellation —
        // stopLoading() cannot revert cookies already set mid-redirect.
        for attempt in 0 ..< 5 {
            if let dataSyncId = try? await Self.readDataSyncId(from: webView),
               Self.dataSyncId(dataSyncId, matches: expectedBrandId)
            {
                self.logger.info("Session identity switch verified")
                return
            }
            if attempt < 4 {
                // Use a throwing sleep so cancellation breaks the poll loop.
                try await Task.sleep(for: .milliseconds(400))
            }
        }

        self.logger.error("Session identity switch could not be verified")
        throw SessionSwitchError.identityNotApplied(expectedBrandId: expectedBrandId)
    }

    /// Reads `ytcfg.DATASYNC_ID` from a loaded WebView.
    private static func readDataSyncId(from webView: WKWebView) async throws -> String? {
        let script = """
        (function() {
            try {
                if (window.ytcfg && typeof window.ytcfg.get === 'function') {
                    return window.ytcfg.get('DATASYNC_ID') || '';
                }
                if (window.ytcfg && window.ytcfg.data_) {
                    return window.ytcfg.data_['DATASYNC_ID'] || '';
                }
            } catch (e) {}
            return '';
        })();
        """
        let result = try await webView.evaluateJavaScript(script)
        return result as? String
    }

    /// Returns `true` when a `DATASYNC_ID` reflects the expected identity.
    ///
    /// `DATASYNC_ID` is `"<delegatedSessionId>||<userSessionId>"` for a brand
    /// (delegated/secondary channel) and `"<userSessionId>||"` for the primary
    /// account — i.e. the primary has a non-empty first half and an empty second
    /// half. A blank or malformed value (e.g. `""` or `"||"`, which the page JS
    /// returns when `ytcfg` has not populated yet) is treated as *no match* for
    /// either identity, so an unread page never falsely "verifies" as primary.
    static func dataSyncId(_ dataSyncId: String, matches expectedBrandId: String?) -> Bool {
        // A well-formed value has exactly two "||"-separated halves with a
        // non-empty first half (the user/delegated session id).
        let parts = dataSyncId.components(separatedBy: "||")
        guard parts.count == 2, !parts[0].isEmpty else {
            return false
        }
        let firstHalf = parts[0]
        let hasUserSessionSuffix = !parts[1].isEmpty
        // delegatedSessionId is present only for a secondary (brand) identity:
        // "<delegated>||<user>". Primary is "<user>||" (empty second half).
        let delegatedSessionId: String? = hasUserSessionSuffix ? firstHalf : nil
        if let expectedBrandId {
            return delegatedSessionId == expectedBrandId
        }
        return delegatedSessionId == nil
    }
}

// MARK: - SessionSwitchNavigationDriver

/// Drives a one-shot navigation to completion for ``WebKitManager/switchSessionIdentity(to:expectedBrandId:)``.
///
/// Bridges `WKNavigationDelegate` callbacks into a single awaitable result and
/// enforces a timeout so a hung redirect chain cannot block the switch forever.
@MainActor
private final class SessionSwitchNavigationDriver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private var timeoutTask: Task<Void, Never>?

    func load(_ url: URL, in webView: WKWebView, timeout: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // The enclosing Task may have been cancelled between the call and
                // this body running; bail out immediately if so.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard let self, !self.finished else { return }
                    self.complete(with: .failure(SessionSwitchError.timedOut))
                }
                webView.load(URLRequest(url: url))
            }
        } onCancel: {
            // Cooperative cancellation: resolve promptly with CancellationError so
            // a stale pin does not block a newer switch for the full navigation.
            Task { @MainActor [weak self] in
                self?.complete(with: .failure(CancellationError()))
            }
        }
    }

    private func complete(with result: Result<Void, Error>) {
        guard !self.finished else { return }
        self.finished = true
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        self.complete(with: .success(()))
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        self.complete(with: .failure(SessionSwitchError.navigationFailed(underlying: error.localizedDescription)))
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        self.complete(with: .failure(SessionSwitchError.navigationFailed(underlying: error.localizedDescription)))
    }
}
