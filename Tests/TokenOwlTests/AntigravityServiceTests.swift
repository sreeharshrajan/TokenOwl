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
            provider: StubCredentialProvider(
                credential: ResolvedCredential(
                    source: .keychain,
                    refreshToken: "fixture-refresh-token",
                    accessToken: accessToken,
                    accessTokenExpiresAt: accessToken == nil ? nil : now.addingTimeInterval(3600)
                )
            ),
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
            provider: ThrowingCredentialProvider(error: CredentialError.notFound),
            quotaClient: quotaClient,
            tokenManager: OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now })
        )

        await #expect(throws: CredentialError.notFound) {
            _ = try await service.fetchSnapshot()
        }

        #expect(await quotaClient.requestCount == 0)
    }
}

// MARK: - Doubles

private struct StubCredentialProvider: AntigravityCredentialProvider {
    let source: CredentialSource = .keychain
    let credential: ResolvedCredential

    func resolveCredential() async throws -> ResolvedCredential {
        credential
    }
}

private struct ThrowingCredentialProvider: AntigravityCredentialProvider {
    let source: CredentialSource = .keychain
    let error: CredentialError

    func resolveCredential() async throws -> ResolvedCredential {
        throw error
    }
}

private actor MockQuotaClient: AntigravityQuotaFetching {
    private let unauthorizedRequests: Int
    private let delay: Duration

    private(set) var requestCount = 0
    private(set) var tokensUsed: [String] = []

    init(unauthorizedRequests: Int = 0, delay: Duration = .zero) {
        self.unauthorizedRequests = unauthorizedRequests
        self.delay = delay
    }

    func fetchQuota(accessToken: String) async throws -> AntigravityQuotaSummary {
        requestCount += 1
        tokensUsed.append(accessToken)

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        if requestCount <= unauthorizedRequests {
            throw QuotaClientError.httpError(401)
        }

        return Fixtures.quotaSummary
    }

    func fetchAccount(accessToken: String) async -> AntigravityAccount {
        AntigravityAccount(
            email: "fixture@example.com",
            tierID: "free-tier",
            tierName: "Antigravity Free",
            upgradePrompt: nil
        )
    }
}

private actor MockOAuthClient: AccessTokenRefreshing {
    private let expiresIn: Int

    private(set) var refreshCount = 0

    init(expiresIn: Int = 3600) {
        self.expiresIn = expiresIn
    }

    func refreshAccessToken(refreshToken: String) async throws -> GoogleOAuthClient.RefreshResponse {
        refreshCount += 1
        return GoogleOAuthClient.RefreshResponse(
            accessToken: "access-\(refreshCount)",
            expiresIn: expiresIn,
            tokenType: "Bearer"
        )
    }
}
