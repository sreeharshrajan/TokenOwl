import Foundation
import Testing
@testable import TokenOwlCore

struct AntigravityServiceTests {

    private let now = Date(timeIntervalSince1970: 1_791_675_455)

    private func makeService(
        quotaClient: MockQuotaClient,
        oauthClient: MockOAuthClient,
        accessToken: String? = nil
    ) -> AntigravityService {
        AntigravityService(
            providers: [
                StubCredentialProvider(
                    credential: ResolvedCredential(
                        source: .keychain,
                        refreshToken: "fixture-refresh-token",
                        accessToken: accessToken,
                        accessTokenExpiresAt: accessToken == nil ? nil : now.addingTimeInterval(3600)
                    )
                )
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: oauthClient, clock: { [now] in now })
        )
    }

    @Test func snapshotCarriesAccountQuotaAndSource() async throws {
        let quotaClient = MockQuotaClient()
        let service = makeService(quotaClient: quotaClient, oauthClient: MockOAuthClient())

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot.account.email == "fixture@example.com")
        #expect(snapshot.account.tierDisplayName == "Antigravity Free")
        #expect(snapshot.quota.mostConstrainedPercent == 81)
        #expect(snapshot.credentialSource == .keychain)
        #expect(abs(snapshot.fetchedAt.timeIntervalSinceNow) < 60)
    }

    @Test func reusesOAuthTokenAcrossSnapshotFetches() async throws {
        let quotaClient = MockQuotaClient()
        let oauthClient = MockOAuthClient()
        let service = makeService(quotaClient: quotaClient, oauthClient: oauthClient)

        _ = try await service.fetchSnapshot()
        _ = try await service.fetchSnapshot()

        #expect(await oauthClient.refreshCount == 1)
        #expect(await quotaClient.tokensUsed == ["access-1", "access-1"])
    }

    @Test func credentialAccessTokenIsUsedWithoutRefreshing() async throws {
        let quotaClient = MockQuotaClient()
        let oauthClient = MockOAuthClient()
        let service = makeService(
            quotaClient: quotaClient,
            oauthClient: oauthClient,
            accessToken: "credential-access-token"
        )

        _ = try await service.fetchSnapshot()

        #expect(await oauthClient.refreshCount == 0)
        #expect(await quotaClient.tokensUsed == ["credential-access-token"])
    }

    @Test func refreshesOnceAndRetriesAfterUnauthorized() async throws {
        let quotaClient = MockQuotaClient(unauthorizedRequests: 1)
        let oauthClient = MockOAuthClient()
        let service = makeService(quotaClient: quotaClient, oauthClient: oauthClient)

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot.quota.mostConstrainedPercent == 81)
        #expect(await oauthClient.refreshCount == 2)
        #expect(await quotaClient.tokensUsed == ["access-1", "access-2"])
    }

    @Test func persistentUnauthorizedFailsAfterSingleRetry() async {
        let quotaClient = MockQuotaClient(unauthorizedRequests: .max)
        let oauthClient = MockOAuthClient()
        let service = makeService(quotaClient: quotaClient, oauthClient: oauthClient)

        await #expect(throws: QuotaClientError.httpError(401)) {
            _ = try await service.fetchSnapshot()
        }

        // Initial refresh + exactly one controlled retry.
        #expect(await oauthClient.refreshCount == 2)
        #expect(await quotaClient.tokensUsed == ["access-1", "access-2"])
    }

    @Test func concurrentFetchesShareOneRequest() async throws {
        let quotaClient = MockQuotaClient(delay: .milliseconds(50))
        let oauthClient = MockOAuthClient()
        let service = makeService(quotaClient: quotaClient, oauthClient: oauthClient)

        let snapshots = try await withThrowingTaskGroup(of: AntigravitySnapshot.self) { group in
            for _ in 0..<5 {
                group.addTask { try await service.fetchSnapshot() }
            }

            var results: [AntigravitySnapshot] = []
            for try await snapshot in group {
                results.append(snapshot)
            }
            return results
        }

        #expect(snapshots.count == 5)
        #expect(await quotaClient.requestCount == 1)
        #expect(await oauthClient.refreshCount == 1)
    }

    @Test func credentialFailurePropagatesWithoutTouchingQuota() async {
        let quotaClient = MockQuotaClient()
        let service = AntigravityService(
            providers: [ThrowingCredentialProvider(error: CredentialError.notFound)],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now })
        )

        await #expect(throws: CredentialError.notFound) {
            _ = try await service.fetchSnapshot()
        }

        #expect(await quotaClient.requestCount == 0)
    }

    // MARK: Credential-source priority and fallback

    @Test func ideSourceIsUsedWhenItWorks() async throws {
        let quotaClient = MockQuotaClient()
        let keychain = CountingCredentialProvider(
            credential: ResolvedCredential(source: .keychain, refreshToken: "fixture-refresh-token")
        )

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(source: .ide, accessToken: Fixtures.ideSessionToken)
                ),
                keychain
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now })
        )

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot.credentialSource == .ide)
        #expect(await quotaClient.tokensUsed == [Fixtures.ideSessionToken])
        #expect(await keychain.resolveCount == 0)
    }

    @Test func fallsBackToKeychainWhenIDETokenIsRejected() async throws {
        // The IDE token gets a single 401: it cannot be refreshed, so the
        // service hands the fetch to the Keychain credential instead of
        // failing.
        let quotaClient = MockQuotaClient(unauthorizedRequests: 1)
        let oauthClient = MockOAuthClient()

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(source: .ide, accessToken: Fixtures.ideSessionToken)
                ),
                StubCredentialProvider(
                    credential: ResolvedCredential(source: .keychain, refreshToken: "fixture-refresh-token")
                )
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: oauthClient, clock: { [now] in now })
        )

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot.credentialSource == .keychain)
        #expect(snapshot.quota.mostConstrainedPercent == 81)
        #expect(await quotaClient.tokensUsed == [Fixtures.ideSessionToken, "access-1"])
        #expect(await oauthClient.refreshCount == 1)
    }

    @Test func fallsBackWhenIDEReadFails() async throws {
        let quotaClient = MockQuotaClient()
        let keychain = CountingCredentialProvider(
            credential: ResolvedCredential(source: .keychain, refreshToken: "fixture-refresh-token")
        )

        let service = AntigravityService(
            providers: [
                ThrowingCredentialProvider(source: .ide, error: IDETokenStateError.rowNotFound),
                keychain
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now })
        )

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot.credentialSource == .keychain)
        #expect(await keychain.resolveCount == 1)
    }

    @Test func networkFailureDoesNotTryTheNextSource() async {
        // Every source would hit the same network error, so falling back
        // would only double the requests.
        let quotaClient = MockQuotaClient(error: URLError(.notConnectedToInternet))
        let keychain = CountingCredentialProvider(
            credential: ResolvedCredential(source: .keychain, refreshToken: "fixture-refresh-token")
        )

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(source: .ide, accessToken: Fixtures.ideSessionToken)
                ),
                keychain
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now })
        )

        await #expect(throws: URLError.self) {
            _ = try await service.fetchSnapshot()
        }

        #expect(await keychain.resolveCount == 0)
    }

    @Test func lastSourceFailureIsPropagated() async {
        let quotaClient = MockQuotaClient(unauthorizedRequests: .max)

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(source: .ide, accessToken: Fixtures.ideSessionToken)
                ),
                StubCredentialProvider(
                    credential: ResolvedCredential(source: .keychain, refreshToken: "fixture-refresh-token")
                )
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now })
        )

        await #expect(throws: QuotaClientError.httpError(401)) {
            _ = try await service.fetchSnapshot()
        }
    }

    @Test func failedSourceIsSkippedDuringCooldown() async throws {
        let clock = TestClock(now)
        let quotaClient = MockQuotaClient(
            unauthorizedTokens: [Fixtures.ideSessionToken]
        )
        let oauthClient = MockOAuthClient()

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(source: .ide, accessToken: Fixtures.ideSessionToken)
                ),
                StubCredentialProvider(
                    credential: ResolvedCredential(source: .keychain, refreshToken: "fixture-refresh-token")
                )
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: oauthClient, clock: { [now] in now }),
            sourceCooldown: 900,
            clock: { clock.now }
        )

        _ = try await service.fetchSnapshot()
        _ = try await service.fetchSnapshot()

        // The second refresh does not pay for another rejected IDE request.
        #expect(
            await quotaClient.tokensUsed
                == [Fixtures.ideSessionToken, "access-1", "access-1"]
        )
        #expect(await oauthClient.refreshCount == 1)
    }

    @Test func cooldownExpiresAndSourceIsTriedAgain() async throws {
        let clock = TestClock(now)
        let quotaClient = MockQuotaClient(
            unauthorizedTokens: [Fixtures.ideSessionToken]
        )
        let oauthClient = MockOAuthClient()

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(source: .ide, accessToken: Fixtures.ideSessionToken)
                ),
                StubCredentialProvider(
                    credential: ResolvedCredential(source: .keychain, refreshToken: "fixture-refresh-token")
                )
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: oauthClient, clock: { [now] in now }),
            sourceCooldown: 900,
            clock: { clock.now }
        )

        _ = try await service.fetchSnapshot()

        clock.advance(by: 901)

        _ = try await service.fetchSnapshot()

        // Past the cooldown, the IDE source is tried again (it fails again and
        // falls through; "access-2" just reflects the mocked access token
        // also expiring across the same clock jump).
        #expect(
            await quotaClient.tokensUsed
                == [
                    Fixtures.ideSessionToken, "access-1",
                    Fixtures.ideSessionToken, "access-2"
                ]
        )
        #expect(await oauthClient.refreshCount == 2)
    }

    @Test func ideSourceRefreshesAStaleSessionToken() async throws {
        // The envelope's access token is stale: the IDE source must renew it
        // with the envelope's refresh token and still win over Keychain.
        let quotaClient = MockQuotaClient(
            unauthorizedTokens: [Fixtures.ideAccessToken]
        )
        let oauthClient = MockOAuthClient()

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(
                        source: .ide,
                        refreshToken: Fixtures.ideRefreshToken,
                        accessToken: Fixtures.ideAccessToken
                    )
                ),
                StubCredentialProvider(
                    credential: ResolvedCredential(
                        source: .keychain,
                        refreshToken: "fixture-refresh-token"
                    )
                )
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: oauthClient, clock: { [now] in now })
        )

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot.credentialSource == .ide)
        #expect(
            await quotaClient.tokensUsed == [Fixtures.ideAccessToken, "access-1"]
        )
        #expect(await oauthClient.refreshCount == 1)
    }

    @Test func rejectedIDERefreshTokenFallsBackToKeychain() async throws {
        // Google refuses to refresh the IDE's refresh token (revoked, wrong
        // audience): that is a credential failure, so Keychain takes over.
        let quotaClient = MockQuotaClient(
            unauthorizedTokens: [Fixtures.ideAccessToken]
        )
        let oauthClient = MockOAuthClient(
            rejectRefreshToken: Fixtures.ideRefreshToken
        )

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(
                        source: .ide,
                        refreshToken: Fixtures.ideRefreshToken,
                        accessToken: Fixtures.ideAccessToken
                    )
                ),
                StubCredentialProvider(
                    credential: ResolvedCredential(
                        source: .keychain,
                        refreshToken: "fixture-refresh-token"
                    )
                )
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: oauthClient, clock: { [now] in now })
        )

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot.credentialSource == .keychain)
        #expect(await quotaClient.tokensUsed == [Fixtures.ideAccessToken, "access-2"])
        #expect(await oauthClient.refreshCount == 2)
    }

    // MARK: Default provider ordering

    @Test func defaultProviderChainIsKeychainFirstThenIDE() {
        #expect(
            AntigravityService.defaultProviders.map(\.source) == [.keychain, .ide]
        )
    }

    // MARK: Account-identity guard

    @Test func accountChangeIsReportedWhenFetchBelongsToADifferentAccount() async throws {
        let quotaClient = MockQuotaClient(
            accountEmails: ["first@example.com", "second@example.com"]
        )
        let service = makeService(quotaClient: quotaClient, oauthClient: MockOAuthClient())

        let first = try await service.fetchSnapshot()
        #expect(first.accountChange == nil)

        let second = try await service.fetchSnapshot()
        #expect(
            second.accountChange == AccountChangeNotice(
                fromEmail: "first@example.com",
                toEmail: "second@example.com",
                toSource: .keychain
            )
        )

        // The notice persists while fetches keep belonging to the other
        // account — the switch cannot be missed on a later refresh.
        let third = try await service.fetchSnapshot()
        #expect(third.accountChange == second.accountChange)
    }

    @Test func noAccountChangeIsReportedForTheSameAccount() async throws {
        let service = makeService(
            quotaClient: MockQuotaClient(),
            oauthClient: MockOAuthClient()
        )

        _ = try await service.fetchSnapshot()
        let second = try await service.fetchSnapshot()

        #expect(second.accountChange == nil)
        #expect(second.account.email == "fixture@example.com")
    }

    @Test func accountChangeClearsWhenTheOriginalAccountReturns() async throws {
        let quotaClient = MockQuotaClient(
            accountEmails: [
                "a@example.com",
                "b@example.com",
                "a@example.com"
            ]
        )
        let service = makeService(quotaClient: quotaClient, oauthClient: MockOAuthClient())

        _ = try await service.fetchSnapshot()
        let changed = try await service.fetchSnapshot()
        #expect(changed.accountChange != nil)

        let restored = try await service.fetchSnapshot()
        #expect(restored.accountChange == nil)
        #expect(restored.account.email == "a@example.com")
    }

    // MARK: Observable identity failures

    @Test func identityFailureIsFlaggedWhileQuotaStillSucceeds() async throws {
        let quotaClient = MockQuotaClient(accountError: URLError(.badServerResponse))
        let service = makeService(quotaClient: quotaClient, oauthClient: MockOAuthClient())

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot.accountIdentityUnavailable)
        #expect(snapshot.account.email == nil)
        #expect(snapshot.quota.mostConstrainedPercent == 81)
        #expect(snapshot.accountChange == nil)
    }

    // MARK: Rate limiting (HTTP 429)

    @Test func rateLimitBacksOffOnceAndSucceedsWithoutSwitchingProviders() async throws {
        let recorder = SleepRecorder()
        let quotaClient = MockQuotaClient(
            rateLimitedRequests: 1,
            rateLimitedRetryAfter: 1.5
        )
        let keychain = CountingCredentialProvider(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token"
            )
        )

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(
                        source: .ide,
                        accessToken: Fixtures.ideSessionToken
                    )
                ),
                keychain
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now }),
            sleep: { seconds in recorder.record(seconds) }
        )

        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot.credentialSource == .ide)
        #expect(recorder.slept == [1.5])
        #expect(await quotaClient.requestCount == 2)
        #expect(await keychain.resolveCount == 0)
    }

    @Test func persistentRateLimitSurfacesAfterOneBoundedBackoff() async {
        let recorder = SleepRecorder()
        let quotaClient = MockQuotaClient(rateLimitedRequests: .max)
        let keychain = CountingCredentialProvider(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token"
            )
        )

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(
                        source: .ide,
                        accessToken: Fixtures.ideSessionToken
                    )
                ),
                keychain
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now }),
            sleep: { seconds in recorder.record(seconds) }
        )

        await #expect(throws: QuotaClientError.rateLimited(retryAfter: nil)) {
            _ = try await service.fetchSnapshot()
        }

        // Exactly one bounded backoff, and never a credential-source switch.
        #expect(recorder.slept == [AntigravityService.defaultRateLimitDelay])
        #expect(await keychain.resolveCount == 0)
    }

    @Test func rateLimitBackoffIsCappedAtTheMaximum() async throws {
        let recorder = SleepRecorder()
        let quotaClient = MockQuotaClient(
            rateLimitedRequests: 1,
            rateLimitedRetryAfter: 10_000
        )

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    credential: ResolvedCredential(
                        source: .keychain,
                        refreshToken: "fixture-refresh-token"
                    )
                )
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now }),
            sleep: { seconds in recorder.record(seconds) }
        )

        _ = try await service.fetchSnapshot()

        #expect(recorder.slept == [AntigravityService.maximumRateLimitDelay])
    }

    // MARK: Non-persistence

    @Test func credentialsNeverReachUserDefaults() async throws {
        let quotaClient = MockQuotaClient()
        let oauthClient = MockOAuthClient()

        let service = AntigravityService(
            providers: [
                StubCredentialProvider(
                    source: .ide,
                    credential: ResolvedCredential(
                        source: .ide,
                        refreshToken: Fixtures.ideRefreshToken,
                        accessToken: Fixtures.ideAccessToken
                    )
                ),
                StubCredentialProvider(
                    credential: ResolvedCredential(
                        source: .keychain,
                        refreshToken: "fixture-refresh-token"
                    )
                )
            ],
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: oauthClient, clock: { [now] in now })
        )

        // Exercise install, refresh, and two snapshot fetches end to end.
        _ = try await service.fetchSnapshot()
        _ = try await service.fetchSnapshot()

        let dump = UserDefaults.standard.dictionaryRepresentation()
            .values
            .map { String(describing: $0) }
            .joined(separator: " ")

        #expect(!dump.contains(Fixtures.ideRefreshToken))
        #expect(!dump.contains(Fixtures.ideAccessToken))
        #expect(!dump.contains(Fixtures.ideSessionToken))
        #expect(!dump.contains("fixture-refresh-token"))
        #expect(!dump.contains("access-1"))
        #expect(!dump.contains("ya29."))
    }
}

// MARK: - Doubles

private struct StubCredentialProvider: AntigravityCredentialProvider {
    var source: CredentialSource = .keychain
    let credential: ResolvedCredential

    func resolveCredential() async throws -> ResolvedCredential {
        credential
    }
}

private struct ThrowingCredentialProvider: AntigravityCredentialProvider {
    var source: CredentialSource = .keychain
    let error: Error

    func resolveCredential() async throws -> ResolvedCredential {
        throw error
    }
}

/// Counts how often a source was consulted, so priority and fallback are
/// observable without inspecting tokens.
private actor CountingCredentialProvider: AntigravityCredentialProvider {
    let source: CredentialSource
    private let credential: ResolvedCredential

    private(set) var resolveCount = 0

    init(credential: ResolvedCredential) {
        self.source = credential.source
        self.credential = credential
    }

    func resolveCredential() async throws -> ResolvedCredential {
        resolveCount += 1
        return credential
    }
}

private actor MockQuotaClient: AntigravityQuotaFetching {
    private let unauthorizedRequests: Int
    private let unauthorizedTokens: Set<String>
    private let rateLimitedRequests: Int
    private let rateLimitedRetryAfter: TimeInterval?
    private let accountError: Error?
    private let accountEmails: [String]
    private let delay: Duration
    private let error: Error?

    private(set) var requestCount = 0
    private(set) var tokensUsed: [String] = []
    private(set) var accountFetchCount = 0

    init(
        unauthorizedRequests: Int = 0,
        unauthorizedTokens: Set<String> = [],
        rateLimitedRequests: Int = 0,
        rateLimitedRetryAfter: TimeInterval? = nil,
        accountError: Error? = nil,
        accountEmails: [String] = ["fixture@example.com"],
        delay: Duration = .zero,
        error: Error? = nil
    ) {
        self.unauthorizedRequests = unauthorizedRequests
        self.unauthorizedTokens = unauthorizedTokens
        self.rateLimitedRequests = rateLimitedRequests
        self.rateLimitedRetryAfter = rateLimitedRetryAfter
        self.accountError = accountError
        self.accountEmails = accountEmails.isEmpty
            ? ["fixture@example.com"]
            : accountEmails
        self.delay = delay
        self.error = error
    }

    func fetchQuota(accessToken: String) async throws -> AntigravityQuotaSummary {
        requestCount += 1
        tokensUsed.append(accessToken)

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        if let error {
            throw error
        }

        if unauthorizedTokens.contains(accessToken) {
            throw QuotaClientError.httpError(401)
        }

        if requestCount <= rateLimitedRequests {
            throw QuotaClientError.rateLimited(retryAfter: rateLimitedRetryAfter)
        }

        if requestCount <= unauthorizedRequests {
            throw QuotaClientError.httpError(401)
        }

        return Fixtures.quotaSummary
    }

    func fetchAccount(accessToken: String) async throws -> AntigravityAccount {
        accountFetchCount += 1

        if let accountError {
            throw accountError
        }

        let index = min(accountFetchCount - 1, accountEmails.count - 1)
        return AntigravityAccount(
            email: accountEmails[index],
            tierID: "free-tier",
            tierName: "Antigravity Free",
            upgradePrompt: nil
        )
    }
}

/// A clock the tests can move forward, so cooldown expiry is observable.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ now: Date) {
        self.current = now
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

/// Records rate-limit backoffs instead of actually sleeping.
private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []

    func record(_ seconds: TimeInterval) {
        lock.withLock { values.append(seconds) }
    }

    var slept: [TimeInterval] {
        lock.withLock { values }
    }
}

private actor MockOAuthClient: AccessTokenRefreshing {
    private let expiresIn: Int
    private let rejectRefreshToken: String?

    private(set) var refreshCount = 0

    init(expiresIn: Int = 3600, rejectRefreshToken: String? = nil) {
        self.expiresIn = expiresIn
        self.rejectRefreshToken = rejectRefreshToken
    }

    func refreshAccessToken(refreshToken: String) async throws -> GoogleOAuthClient.RefreshResponse {
        refreshCount += 1

        if let rejectRefreshToken, refreshToken == rejectRefreshToken {
            // What Google answers for a refresh token it will not honor.
            throw OAuthError.httpError(400)
        }

        return GoogleOAuthClient.RefreshResponse(
            accessToken: "access-\(refreshCount)",
            expiresIn: expiresIn,
            tokenType: "Bearer"
        )
    }
}
