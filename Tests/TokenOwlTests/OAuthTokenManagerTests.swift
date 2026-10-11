import Foundation
import Testing
@testable import TokenOwlCore

struct OAuthTokenManagerTests {

    private let now = Date(timeIntervalSince1970: 1_791_675_455)

    @Test func validCachedTokenIsReused() async throws {
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token",
                accessToken: "seed-access-token",
                accessTokenExpiresAt: now.addingTimeInterval(3600)
            )
        )

        let token = try await manager.accessToken()

        #expect(token == "seed-access-token")
        #expect(await client.refreshCount == 0)
    }

    @Test func expiredTokenIsRefreshed() async throws {
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token",
                accessToken: "stale-access-token",
                accessTokenExpiresAt: now.addingTimeInterval(-60)
            )
        )

        let token = try await manager.accessToken()

        #expect(token == "access-1")
        #expect(await client.refreshCount == 1)
    }

    @Test func nearExpiryTokenIsRefreshedEarly() async throws {
        // Inside the 5 minute safety margin: refreshed before it can expire.
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token",
                accessToken: "nearly-expired-token",
                accessTokenExpiresAt: now.addingTimeInterval(120)
            )
        )

        let token = try await manager.accessToken()

        #expect(token == "access-1")
        #expect(await client.refreshCount == 1)
    }

    @Test func invalidationForcesRefresh() async throws {
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token",
                accessToken: "seed-access-token",
                accessTokenExpiresAt: now.addingTimeInterval(3600)
            )
        )

        #expect(try await manager.accessToken() == "seed-access-token")
        #expect(await client.refreshCount == 0)

        await manager.invalidate()

        #expect(try await manager.accessToken() == "access-1")
        #expect(await client.refreshCount == 1)
    }

    @Test func refreshedTokenIsReusedOnLaterCalls() async throws {
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token"
            )
        )

        #expect(try await manager.accessToken() == "access-1")
        #expect(try await manager.accessToken() == "access-1")
        #expect(await client.refreshCount == 1)
    }

    @Test func concurrentCallersDoNotDuplicateRefresh() async throws {
        let client = MockOAuthClient(delay: .milliseconds(50))
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token"
            )
        )

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 {
                group.addTask { try await manager.accessToken() }
            }

            var results: [String] = []
            for try await token in group {
                results.append(token)
            }
            return results
        }

        #expect(tokens.count == 8)
        #expect(Set(tokens) == ["access-1"])
        #expect(await client.refreshCount == 1)
    }

    @Test func refreshFailureAllowsLaterRetry() async throws {
        let client = MockOAuthClient(failuresRemaining: 1)
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token"
            )
        )

        await #expect(throws: OAuthError.httpError(500)) {
            _ = try await manager.accessToken()
        }

        #expect(try await manager.accessToken() == "access-2")
        #expect(await client.refreshCount == 2)
    }

    @Test func missingCredentialThrows() async {
        let manager = OAuthTokenManager(client: MockOAuthClient(), clock: { [now] in now })

        await #expect(throws: OAuthError.missingRefreshToken) {
            _ = try await manager.accessToken()
        }
    }

    @Test func changedRefreshTokenInvalidatesCache() async throws {
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "fixture-refresh-token",
                accessToken: "seed-access-token",
                accessTokenExpiresAt: now.addingTimeInterval(3600)
            )
        )
        #expect(try await manager.accessToken() == "seed-access-token")

        await manager.install(
            credential: ResolvedCredential(
                source: .keychain,
                refreshToken: "different-refresh-token"
            )
        )

        #expect(try await manager.accessToken() == "access-1")
        #expect(await client.refreshCount == 1)
    }

    // MARK: Access-token-only credentials (IDE session)

    @Test func accessOnlyCredentialIsUsedWithoutRefreshing() async throws {
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .ide,
                refreshToken: nil,
                accessToken: Fixtures.ideSessionToken,
                accessTokenExpiresAt: nil
            )
        )

        #expect(try await manager.accessToken() == Fixtures.ideSessionToken)
        #expect(await client.refreshCount == 0)
    }

    @Test func accessOnlyCredentialFailsInsteadOfRefreshing() async {
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(
                source: .ide,
                refreshToken: nil,
                accessToken: "expired-ide-token",
                accessTokenExpiresAt: now.addingTimeInterval(-60)
            )
        )

        await #expect(throws: OAuthError.credentialExpired) {
            _ = try await manager.accessToken()
        }

        // Nothing was sent to Google: this credential cannot be refreshed.
        #expect(await client.refreshCount == 0)
    }

    @Test func newerAccessOnlyCredentialReplacesCachedToken() async throws {
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(source: .ide, accessToken: "ide-token-a")
        )
        #expect(try await manager.accessToken() == "ide-token-a")

        // The IDE rotates its token; the newest read wins.
        await manager.install(
            credential: ResolvedCredential(source: .ide, accessToken: "ide-token-b")
        )

        #expect(try await manager.accessToken() == "ide-token-b")
        #expect(await client.refreshCount == 0)
    }

    @Test func refreshableCredentialReplacesAccessOnlyCredential() async throws {
        let client = MockOAuthClient()
        let manager = OAuthTokenManager(client: client, clock: { [now] in now })

        await manager.install(
            credential: ResolvedCredential(source: .ide, accessToken: Fixtures.ideSessionToken)
        )
        #expect(try await manager.accessToken() == Fixtures.ideSessionToken)

        await manager.install(
            credential: ResolvedCredential(source: .keychain, refreshToken: "fixture-refresh-token")
        )

        #expect(try await manager.accessToken() == "access-1")
        #expect(await client.refreshCount == 1)
    }
}

// MARK: - Doubles

private actor MockOAuthClient: AccessTokenRefreshing {
    private let expiresIn: Int
    private let delay: Duration
    private var failuresRemaining: Int

    private(set) var refreshCount = 0

    init(
        expiresIn: Int = 3600,
        delay: Duration = .zero,
        failuresRemaining: Int = 0
    ) {
        self.expiresIn = expiresIn
        self.delay = delay
        self.failuresRemaining = failuresRemaining
    }

    func refreshAccessToken(refreshToken: String) async throws -> GoogleOAuthClient.RefreshResponse {
        refreshCount += 1

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw OAuthError.httpError(500)
        }

        return GoogleOAuthClient.RefreshResponse(
            accessToken: "access-\(refreshCount)",
            expiresIn: expiresIn,
            tokenType: "Bearer"
        )
    }
}
