import Foundation

/// Owns the Google OAuth access token for the lifetime of the process.
///
/// Responsibilities:
/// - accepts credential material from an `AntigravityCredentialProvider`;
/// - reuses an already-valid access token (from the credential or from a
///   previous refresh) instead of refreshing on every quota request;
/// - refreshes through `AccessTokenRefreshing` only when necessary;
/// - keeps the refreshed access token **in memory only**;
/// - tracks expiration as a `Date` and refreshes a few minutes early;
/// - serializes concurrent callers so simultaneous quota requests share one
///   refresh instead of racing into a refresh storm.
///
/// Invariants: no access token or refresh token is ever logged or persisted.
public actor OAuthTokenManager {

    /// A memory-only access token. Never written to disk, UserDefaults, the
    /// Keychain, or crash reports.
    private struct CachedToken: Sendable {
        let value: String
        /// `nil` when the source of the token did not tell us when it expires.
        let expiresAt: Date?
    }

    private struct InFlightRefresh {
        let id: UInt
        let task: Task<String, Error>
    }

    private let client: any AccessTokenRefreshing
    private let refreshMargin: TimeInterval
    private let clock: @Sendable () -> Date

    private var credential: ResolvedCredential?
    private var cachedToken: CachedToken?
    private var inFlight: InFlightRefresh?
    private var nextRefreshID: UInt = 0

    public init(
        client: any AccessTokenRefreshing = GoogleOAuthClient(),
        refreshMargin: TimeInterval = 5 * 60,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.refreshMargin = refreshMargin
        self.clock = clock
    }

    // MARK: Credential intake

    /// Accepts credential material resolved by a credential provider.
    ///
    /// A different refresh token invalidates everything we hold. The same
    /// refresh token only seeds the cache when we do not have a token yet, so
    /// an already-refreshed token is never downgraded by a stale credential.
    public func install(credential: ResolvedCredential) {
        if credential.refreshToken != self.credential?.refreshToken {
            cachedToken = nil
        }

        if cachedToken == nil, let accessToken = credential.accessToken {
            cachedToken = CachedToken(
                value: accessToken,
                expiresAt: credential.accessTokenExpiresAt
            )
        }

        self.credential = credential
    }

    // MARK: Token access

    /// Returns a usable access token, refreshing only when necessary.
    public func accessToken() async throws -> String {
        if let cachedToken, isUsable(cachedToken) {
            return cachedToken.value
        }

        // Another caller is already refreshing: share its result.
        if let inFlight {
            return try await inFlight.task.value
        }

        guard credential != nil else {
            throw OAuthError.missingRefreshToken
        }

        nextRefreshID &+= 1
        let attempt = InFlightRefresh(
            id: nextRefreshID,
            task: Task { try await self.performRefresh() }
        )
        inFlight = attempt

        do {
            let token = try await attempt.task.value
            clearInFlight(ifIDIs: attempt.id)
            return token
        } catch {
            clearInFlight(ifIDIs: attempt.id)
            throw error
        }
    }

    /// Drops the cached access token, forcing the next call to refresh.
    public func invalidate() {
        cachedToken = nil
    }

    // MARK: Internals

    private func isUsable(_ token: CachedToken) -> Bool {
        guard let expiresAt = token.expiresAt else {
            // No expiry information: try it and let the 401 path decide.
            return true
        }

        return expiresAt.timeIntervalSince(clock()) > refreshMargin
    }

    private func performRefresh() async throws -> String {
        guard let credential else {
            throw OAuthError.missingRefreshToken
        }

        RedactedLogger.log("Refreshing Google access token")

        let response = try await client.refreshAccessToken(
            refreshToken: credential.refreshToken
        )

        guard !response.accessToken.isEmpty else {
            throw OAuthError.missingAccessToken
        }

        cachedToken = CachedToken(
            value: response.accessToken,
            expiresAt: response.expiresIn.map {
                clock().addingTimeInterval(TimeInterval($0))
            }
        )

        RedactedLogger.log("Google access token refreshed")

        return response.accessToken
    }

    private func clearInFlight(ifIDIs id: UInt) {
        guard inFlight?.id == id else { return }
        inFlight = nil
    }
}
