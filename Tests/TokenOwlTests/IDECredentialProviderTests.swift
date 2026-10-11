import Foundation
import Testing
@testable import TokenOwlCore

struct IDECredentialProviderTests {

    private struct StubReader: IDETokenStateReading {
        private let session: IDESessionState?
        private let error: IDETokenStateError?

        init(
            accessToken: String? = nil,
            refreshToken: String? = nil,
            error: IDETokenStateError? = nil
        ) {
            if accessToken == nil && refreshToken == nil && error == nil {
                self.session = nil
            } else {
                self.session = IDESessionState(
                    accessToken: accessToken,
                    refreshToken: refreshToken
                )
            }
            self.error = error
        }

        func readSession() throws -> IDESessionState {
            if let error { throw error }
            guard let session else { throw IDETokenStateError.emptyToken }
            return session
        }
    }

    @Test func resolvesARefreshableIDECredential() async throws {
        let provider = IDECredentialProvider(
            reader: StubReader(
                accessToken: Fixtures.ideAccessToken,
                refreshToken: Fixtures.ideRefreshToken
            )
        )

        let credential = try await provider.resolveCredential()

        #expect(credential.source == .ide)
        #expect(credential.source.displayName == "Antigravity IDE session")
        #expect(credential.accessToken == Fixtures.ideAccessToken)
        #expect(credential.refreshToken == Fixtures.ideRefreshToken)
        #expect(credential.canRefresh == true)
        // The envelope carries no expiry, so the 401 path decides.
        #expect(credential.accessTokenExpiresAt == nil)
    }

    @Test func resolvesAnAccessOnlyIDECredential() async throws {
        let provider = IDECredentialProvider(
            reader: StubReader(accessToken: Fixtures.ideAccessToken)
        )

        let credential = try await provider.resolveCredential()

        #expect(credential.source == .ide)
        #expect(credential.accessToken == Fixtures.ideAccessToken)
        #expect(credential.refreshToken == nil)
        #expect(credential.canRefresh == false)
    }

    @Test func resolvesWhenOnlyARefreshTokenIsPresent() async throws {
        let provider = IDECredentialProvider(
            reader: StubReader(refreshToken: Fixtures.ideRefreshToken)
        )

        let credential = try await provider.resolveCredential()

        #expect(credential.accessToken == nil)
        #expect(credential.refreshToken == Fixtures.ideRefreshToken)
        #expect(credential.canRefresh == true)
    }

    @Test func readerFailurePropagates() async {
        let provider = IDECredentialProvider(
            reader: StubReader(error: IDETokenStateError.rowNotFound)
        )

        await #expect(throws: IDETokenStateError.rowNotFound) {
            _ = try await provider.resolveCredential()
        }
    }

    @Test func emptySessionProducesNoCredential() async {
        // A reader that yields neither token must fail, not produce an
        // empty bearer.
        let provider = IDECredentialProvider(reader: StubReader())

        await #expect(throws: IDETokenStateError.emptyToken) {
            _ = try await provider.resolveCredential()
        }
    }
}
