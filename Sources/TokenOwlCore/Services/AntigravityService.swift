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

    private let provider: any AntigravityCredentialProvider
    private let quotaClient: any AntigravityQuotaFetching
    private let tokenManager: OAuthTokenManager

    private var inFlight: InFlightFetch?
    private var nextFetchID: UInt = 0

    private struct InFlightFetch {
        let id: UInt
        let task: Task<AntigravitySnapshot, Error>
    }

    public init(
        provider: any AntigravityCredentialProvider = KeychainCredentialProvider(),
        quotaClient: any AntigravityQuotaFetching = AntigravityQuotaClient(),
        tokenManager: OAuthTokenManager = OAuthTokenManager()
    ) {
        self.provider = provider
        self.quotaClient = quotaClient
        self.tokenManager = tokenManager
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
        let credential = try await provider.resolveCredential()
        await tokenManager.install(credential: credential)

        RedactedLogger.log("Fetching Antigravity snapshot (source: \(credential.source.displayName))")

        let accessToken = try await tokenManager.accessToken()

        let result: (quota: AntigravityQuotaSummary, account: AntigravityAccount)

        do {
            result = try await load(accessToken: accessToken)
        } catch QuotaClientError.httpError(let status) where status == 401 {
            // One controlled refresh and one retry, never a loop.
            await tokenManager.invalidate()
            RedactedLogger.log("Quota request returned 401; refreshing access token once")
            let refreshed = try await tokenManager.accessToken()
            result = try await load(accessToken: refreshed)
        }

        return AntigravitySnapshot(
            account: result.account,
            quota: result.quota,
            fetchedAt: Date(),
            credentialSource: credential.source
        )
    }

    private func load(
        accessToken: String
    ) async throws -> (quota: AntigravityQuotaSummary, account: AntigravityAccount) {
        async let quota = quotaClient.fetchQuota(accessToken: accessToken)
        async let account = quotaClient.fetchAccount(accessToken: accessToken)
        return try await (quota, account)
    }

    private func clearInFlight(ifIDIs id: UInt) {
        guard inFlight?.id == id else { return }
        inFlight = nil
    }
}
