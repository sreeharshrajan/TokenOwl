import Foundation

/// Facade between the UI and the credential / OAuth / quota layers.
///
/// Pipeline:
/// ```
/// CredentialProvider -> OAuthTokenManager -> Account Identity -> QuotaClient
///                                                             -> AntigravitySnapshot
/// ```
///
/// The UI never talks to providers, the OAuth client, or the HTTP client
/// directly. Concurrent `fetchSnapshot()` callers share one in-flight request.
public actor AntigravityService {

    /// Credential sources in priority order.
    ///
    /// The Keychain credential is the IDE's *current* login: the IDE keeps
    /// its active session there (verified — its quota matches the IDE's own
    /// usage panel). The state-database envelope is tried second: it can
    /// hold a **previously** signed-in account whose refresh token still
    /// works, so it must not outrank the live credential.
    public static let defaultProviders: [any AntigravityCredentialProvider] = [
        KeychainCredentialProvider(),
        IDECredentialProvider()
    ]

    private let providers: [any AntigravityCredentialProvider]
    private let quotaClient: any AntigravityQuotaFetching
    private let tokenManager: OAuthTokenManager

    /// How long a source is skipped after it fails in a way that handed the
    /// fetch to the next source. Without this, a stale IDE token would cost
    /// one rejected request on every refresh cycle.
    private let sourceCooldown: TimeInterval
    private let clock: @Sendable () -> Date

    /// Backoff sleeper for HTTP 429, injectable so tests never really wait.
    private let sleep: @Sendable (TimeInterval) async -> Void

    private var cooldownUntil: [Int: Date] = [:]

    /// The first Google account this service ever saw. Later fetches for a
    /// different account are flagged instead of silently replacing it.
    private var identityBaselineEmail: String?

    private var inFlight: InFlightFetch?
    private var nextFetchID: UInt = 0

    private struct InFlightFetch {
        let id: UInt
        let task: Task<AntigravitySnapshot, Error>
    }

    /// Backoff when Google sends HTTP 429 without a `Retry-After` header,
    /// and the hard cap on any single backoff.
    public static let defaultRateLimitDelay: TimeInterval = 2
    public static let maximumRateLimitDelay: TimeInterval = 30

    public init(
        providers: [any AntigravityCredentialProvider]? = nil,
        quotaClient: any AntigravityQuotaFetching = AntigravityQuotaClient(),
        tokenManager: OAuthTokenManager = OAuthTokenManager(),
        sourceCooldown: TimeInterval = 15 * 60,
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.providers = providers ?? Self.defaultProviders
        self.quotaClient = quotaClient
        self.tokenManager = tokenManager
        self.sourceCooldown = sourceCooldown
        self.clock = clock
        self.sleep = sleep
    }

    // MARK: Public API

    public func fetchSnapshot() async throws -> AntigravitySnapshot {
        if let inFlight {
            return try await inFlight.task.value
        }

        nextFetchID &+= 1
        let attempt = InFlightFetch(
            id: nextFetchID,
            task: Task { try await self.performFetch() }
        )
        inFlight = attempt

        do {
            let snapshot = try await attempt.task.value
            clearInFlight(ifIDIs: attempt.id)
            return snapshot
        } catch {
            clearInFlight(ifIDIs: attempt.id)
            throw error
        }
    }

    // MARK: Internals

    private func performFetch() async throws -> AntigravitySnapshot {
        guard !providers.isEmpty else {
            throw OAuthError.missingRefreshToken
        }

        var lastFallbackError: Error?

        for (index, provider) in providers.enumerated() {
            let isLastSource = index == providers.count - 1

            // A source that recently handed off a fetch is skipped until the
            // cooldown expires. The last source is never skipped, so there is
            // always something to try.
            if !isLastSource, let until = cooldownUntil[index], until > clock() {
                RedactedLogger.log(
                    "Skipping \(provider.source.displayName) credential source (cooling down)"
                )
                continue
            }

            do {
                return try await performFetch(using: provider)
            } catch {
                guard !isLastSource, Self.shouldTryNextProvider(after: error) else {
                    throw error
                }

                RedactedLogger.log(
                    "Credential source \(provider.source.displayName) failed; trying the next source"
                )
                cooldownUntil[index] = clock().addingTimeInterval(sourceCooldown)
                lastFallbackError = error
            }
        }

        throw lastFallbackError ?? OAuthError.missingRefreshToken
    }

    private func performFetch(
        using provider: any AntigravityCredentialProvider
    ) async throws -> AntigravitySnapshot {
        let credential = try await provider.resolveCredential()
        await tokenManager.install(credential: credential)

        RedactedLogger.log("Fetching Antigravity snapshot (source: \(credential.source.displayName))")

        let accessToken = try await tokenManager.accessToken()

        let result = try await loadWithBoundedRetries(accessToken: accessToken)

        // Identity guard: the first account seen becomes the baseline; any
        // later fetch belonging to a different account carries a persistent
        // notice, so a credential-source fallback can never switch the
        // displayed Google account silently.
        if identityBaselineEmail == nil, let email = result.account.email {
            identityBaselineEmail = email
        }

        let accountChange: AccountChangeNotice?
        if let baseline = identityBaselineEmail,
           let current = result.account.email,
           current != baseline {
            accountChange = AccountChangeNotice(
                fromEmail: baseline,
                toEmail: current,
                toSource: credential.source
            )
        } else {
            accountChange = nil
        }

        return AntigravitySnapshot(
            account: result.account,
            quota: result.quota,
            fetchedAt: Date(),
            credentialSource: credential.source,
            accountChange: accountChange,
            accountIdentityUnavailable: result.identityUnavailable
        )
    }

    /// One account/quota load with two bounded, independent retries: a
    /// single credential refresh on 401 (never a loop) and a single backoff
    /// on 429 (rate limits are not credential failures, never switch
    /// providers, and are capped at `maximumRateLimitDelay` seconds).
    private func loadWithBoundedRetries(
        accessToken: String
    ) async throws -> (quota: AntigravityQuotaSummary, account: AntigravityAccount, identityUnavailable: Bool) {
        var token = accessToken
        var didRefreshOnUnauthorized = false
        var didBackOffOnRateLimit = false

        while true {
            do {
                return try await load(accessToken: token)
            } catch QuotaClientError.httpError(let status)
                where status == 401 && !didRefreshOnUnauthorized {
                // One controlled refresh and one retry, never a loop. For a
                // credential that cannot refresh this throws
                // `credentialExpired`, which hands the fetch to the next
                // credential source.
                didRefreshOnUnauthorized = true
                await tokenManager.invalidate()
                RedactedLogger.log("Quota request returned 401; refreshing access token once")
                token = try await tokenManager.accessToken()
            } catch QuotaClientError.rateLimited(let retryAfter)
                where !didBackOffOnRateLimit {
                didBackOffOnRateLimit = true
                let delay = max(
                    0,
                    min(retryAfter ?? Self.defaultRateLimitDelay, Self.maximumRateLimitDelay)
                )
                RedactedLogger.log(
                    "Rate limited; backing off \(Int(delay))s before one retry"
                )
                await sleep(delay)
            }
        }
    }

    /// Failures that mean "this credential source cannot serve the request",
    /// as opposed to failures every source would hit the same way (no
    /// network, a 5xx from Google, an oversized response).
    private static func shouldTryNextProvider(after error: Error) -> Bool {
        switch error {
        case is CredentialError, is CredentialDecodingError, is IDETokenStateError:
            return true
        case OAuthError.credentialExpired,
             OAuthError.missingAccessToken,
             OAuthError.missingRefreshToken:
            return true
        case OAuthError.httpError(let status) where status == 400 || status == 401:
            // A refresh this source failed to authorize (for example a
            // revoked IDE refresh token): the next source may still work.
            return true
        case QuotaClientError.rateLimited:
            // A rate limit would hit every source the same way, and the
            // bounded backoff already ran above. Never a fallback trigger.
            return false
        case QuotaClientError.httpError(let status) where status == 401 || status == 403:
            return true
        default:
            return false
        }
    }

    private func load(
        accessToken: String
    ) async throws -> (quota: AntigravityQuotaSummary, account: AntigravityAccount, identityUnavailable: Bool) {
        async let quota = quotaClient.fetchQuota(accessToken: accessToken)

        let account: AntigravityAccount
        let identityUnavailable: Bool

        do {
            account = try await quotaClient.fetchAccount(accessToken: accessToken)
            identityUnavailable = false
        } catch {
            // The quota below is still served; the identity failure is
            // logged and surfaced on the snapshot instead of swallowed.
            RedactedLogger.log("Account identity fetch failed (\(type(of: error)))")
            account = AntigravityAccount(
                email: nil,
                tierID: nil,
                tierName: nil,
                upgradePrompt: nil
            )
            identityUnavailable = true
        }

        return (try await quota, account, identityUnavailable)
    }

    private func clearInFlight(ifIDIs id: UInt) {
        guard inFlight?.id == id else { return }
        inFlight = nil
    }
}
