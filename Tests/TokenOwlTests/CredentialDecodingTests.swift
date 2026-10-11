import Foundation
import Testing
@testable import TokenOwlCore

struct CredentialDecodingTests {

    @Test func decodesRawJSONCredential() throws {
        let credential = try AntigravityCredentialDecoder().decode(Fixtures.rawCredentialJSON)

        #expect(credential.token.refreshToken == "fixture-refresh-token")
        #expect(credential.token.accessToken == "fixture-access-token")
        #expect(credential.token.expiry == "2026-10-11T18:17:35Z")
    }

    @Test func decodesGoKeyringBase64Credential() throws {
        let credential = try AntigravityCredentialDecoder().decode(Fixtures.goKeyringCredential)

        #expect(credential.token.refreshToken == "fixture-refresh-token")
        #expect(credential.token.accessToken == "fixture-access-token")
    }

    @Test func rejectsMalformedCredential() {
        #expect(throws: CredentialDecodingError.invalidJSON) {
            try AntigravityCredentialDecoder().decode(Fixtures.malformedCredential)
        }
    }

    @Test func rejectsMalformedBase64Credential() {
        #expect(throws: CredentialDecodingError.invalidBase64) {
            try AntigravityCredentialDecoder().decode(Fixtures.malformedBase64Credential)
        }
    }

    @Test func reportsMissingTokenBlock() {
        #expect(throws: CredentialDecodingError.missingToken) {
            try AntigravityCredentialDecoder().decode(Fixtures.credentialWithoutToken)
        }
    }

    @Test func credentialWithoutExpiryStillResolves() async throws {
        let provider = KeychainCredentialProvider(
            reader: StubRawCredentialReader(raw: #"{"token":{"refresh_token":"fixture-refresh-token"}}"#),
            decoder: AntigravityCredentialDecoder()
        )

        let credential = try await provider.resolveCredential()

        #expect(credential.source == .keychain)
        #expect(credential.refreshToken == "fixture-refresh-token")
        #expect(credential.accessToken == nil)
        #expect(credential.accessTokenExpiresAt == nil)
    }

    @Test func emptyRefreshTokenIsRejected() async {
        let provider = KeychainCredentialProvider(
            reader: StubRawCredentialReader(raw: #"{"token":{"refresh_token":""}}"#),
            decoder: AntigravityCredentialDecoder()
        )

        await #expect(throws: OAuthError.missingRefreshToken) {
            _ = try await provider.resolveCredential()
        }
    }

    @Test func parsesCredentialExpiryIntoDate() async throws {
        let provider = KeychainCredentialProvider(
            reader: StubRawCredentialReader(raw: Fixtures.rawCredentialJSON),
            decoder: AntigravityCredentialDecoder()
        )

        let credential = try await provider.resolveCredential()
        let expected = ISO8601DateFormatter().date(from: "2026-10-11T18:17:35Z")

        #expect(credential.accessTokenExpiresAt == expected)
    }
}

/// Replaces the Keychain reader so credential-provider logic is testable
/// without touching the real Keychain.
private struct StubRawCredentialReader: AntigravityCredentialReading {
    let raw: String
    func readRawCredential() throws -> String { raw }
}
