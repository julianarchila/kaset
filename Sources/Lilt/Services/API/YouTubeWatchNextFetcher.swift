import Foundation
import os

// MARK: - WatchNextProviding

/// Supplies the regular YouTube watch-next data that YouTube Music mixes need.
///
/// The YouTube Music `next` endpoint does not return chapters or the video
/// description, so mix tracklists come from the regular YouTube `next`
/// endpoint instead (confirmed via API exploration, 2026-07-10).
@MainActor
protocol WatchNextProviding: Sendable {
    func getWatchNext(videoId: String) async throws -> WatchNextData
}

// MARK: - YouTubeWatchNextFetcher

/// Calls regular YouTube's InnerTube `next` endpoint (`www.youtube.com`, `WEB`
/// client) for mix chapters and descriptions.
///
/// This is the only request the app sends to the regular YouTube origin. It
/// mirrors `YTMusicClient`'s auth scaffolding, but SAPISIDHASH and the
/// `Origin`/`Referer`/`X-Origin` headers must use `https://www.youtube.com`.
/// Responses are not cached; `MixTracklistParser` caches parsed tracklists.
@MainActor
final class YouTubeWatchNextFetcher: WatchNextProviding {
    private let authService: AuthService
    private let webKitManager: WebKitManager
    private let session: URLSession
    private let logger = DiagnosticsLogger.api

    /// Provider for the current brand account ID (mirrors `YTMusicClient`).
    var brandIdProvider: (() -> String?)?

    private static let endpointURL = "https://www.youtube.com/youtubei/v1/next"

    /// Request origin, which is also the SAPISIDHASH input origin.
    private static let origin = "https://www.youtube.com"

    /// `WEB` client version observed June 2026. InnerTube accepts moderately stale versions.
    private static let clientVersion = "2.20260611.01.00"

    init(
        authService: AuthService,
        webKitManager: WebKitManager = .shared,
        session: URLSession? = nil
    ) {
        self.authService = authService
        self.webKitManager = webKitManager
        self.session = session ?? URLSession(configuration: APISessionConfiguration.make())
    }

    func getWatchNext(videoId: String) async throws -> WatchNextData {
        self.logger.info("Fetching watch-next data")

        let json = try await RetryPolicy.default.execute { [self] in
            try await self.performRequest(body: ["videoId": videoId])
        }
        return WatchNextParser.parse(json)
    }

    // MARK: - Request

    private struct RequestAuth {
        let headers: [String: String]
        let authenticated: Bool
        let identityGeneration: UInt64?
    }

    private func performRequest(body: [String: Any]) async throws -> [String: Any] {
        let auth = try await self.requestAuth()

        var fullBody = body
        fullBody["context"] = self.buildContext(authenticated: auth.authenticated)

        guard var components = URLComponents(string: Self.endpointURL) else {
            throw YTMusicError.unknown(message: "Invalid watch-next URL")
        }
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        guard let url = components.url else {
            throw YTMusicError.unknown(message: "Invalid watch-next URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = auth.authenticated
        for (key, value) in auth.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: fullBody)

        let result = try await Self.performNetworkRequest(request: request, session: self.session)
        try self.validateAuthIdentity(auth)

        switch result {
        case let .success(data):
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw YTMusicError.parseError(message: "Response is not a JSON object")
            }
            return json
        case let .authError(statusCode):
            self.logger.error("YouTube watch-next auth error: HTTP \(statusCode)")
            guard auth.authenticated else { throw YTMusicError.notAuthenticated }
            if let generation = auth.identityGeneration {
                self.authService.sessionExpired(ifIdentityGenerationMatches: generation)
            }
            throw YTMusicError.authExpired
        case let .httpError(statusCode):
            self.logger.error("YouTube watch-next error: HTTP \(statusCode)")
            throw YTMusicError.apiError(message: "HTTP \(statusCode)", code: statusCode)
        case let .networkError(error):
            throw YTMusicError.networkError(underlying: error)
        }
    }

    /// Authenticated headers for signed-in users; plain headers otherwise.
    private func requestAuth() async throws -> RequestAuth {
        guard self.authService.hasPersonalAccount else {
            return RequestAuth(
                headers: [
                    "Origin": Self.origin,
                    "Referer": Self.origin,
                    "Content-Type": "application/json",
                ],
                authenticated: false,
                identityGeneration: nil
            )
        }

        let generation = self.authService.accountIdentityGeneration
        let authMaterial = await self.webKitManager.authMaterial(for: "youtube.com")
        guard generation == self.authService.accountIdentityGeneration,
              self.authService.hasPersonalAccount
        else {
            throw CancellationError()
        }
        guard let cookieHeader = authMaterial.cookieHeader else {
            throw YTMusicError.notAuthenticated
        }
        guard let sapisid = authMaterial.sapisid else {
            self.authService.sessionExpired(ifIdentityGenerationMatches: generation)
            throw YTMusicError.authExpired
        }

        let sapisidhash = InnerTubeSupport.sapisidHash(
            sapisid: sapisid,
            origin: Self.origin,
            timestamp: Int(Date().timeIntervalSince1970)
        )
        return RequestAuth(
            headers: [
                "Cookie": cookieHeader,
                "Authorization": "SAPISIDHASH \(sapisidhash)",
                "Origin": Self.origin,
                "Referer": Self.origin,
                "Content-Type": "application/json",
                // Account selection uses context.user.onBehalfOfUser, like YTMusicClient.
                "X-Goog-AuthUser": "0",
                "X-Origin": Self.origin,
            ],
            authenticated: true,
            identityGeneration: generation
        )
    }

    /// Rejects responses that arrive after a sign-out or account switch.
    private func validateAuthIdentity(_ auth: RequestAuth) throws {
        guard auth.authenticated else { return }
        guard let generation = auth.identityGeneration,
              generation == self.authService.accountIdentityGeneration,
              self.authService.hasPersonalAccount
        else {
            throw CancellationError()
        }
    }

    /// Builds the standard `WEB` client context payload.
    private func buildContext(authenticated: Bool) -> [String: Any] {
        var user: [String: Any] = ["lockedSafetyMode": false]
        if authenticated, let brandId = self.brandIdProvider?() {
            user["onBehalfOfUser"] = brandId
        }

        return [
            "client": [
                "clientName": "WEB",
                "clientVersion": Self.clientVersion,
                "hl": SettingsManager.shared.contentLanguage.apiLanguageCode,
                "gl": "US",
                "browserName": "Safari",
                "browserVersion": "17.0",
                "osName": "Macintosh",
                "osVersion": "10_15_7",
                "platform": "DESKTOP",
                "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                "utcOffsetMinutes": InnerTubeSupport.utcOffsetMinutes(for: .current),
            ],
            "user": user,
        ]
    }

    // MARK: - Nonisolated Network Helper

    /// Result type for network requests to avoid throwing across actor boundaries.
    private enum NetworkResult {
        case success(Data)
        case authError(statusCode: Int)
        case httpError(statusCode: Int)
        case networkError(Error)
    }

    // swiftformat:disable:next modifierOrder
    nonisolated private static func performNetworkRequest(
        request: URLRequest,
        session: URLSession
    ) async throws -> NetworkResult {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkError(URLError(.badServerResponse))
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return .authError(statusCode: httpResponse.statusCode)
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                return .httpError(statusCode: httpResponse.statusCode)
            }

            return .success(data)
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return .networkError(error)
        }
    }
}
