import Foundation

/// Reads the Antigravity credential from the macOS Keychain and hands the
/// domain a `ResolvedCredential`.
///
/// Read-only: this provider never writes to the Keychain.
public struct KeychainCredentialProvider: AntigravityCredentialProvider {
    public let source: CredentialSource = .keychain

    private let reader: any AntigravityCredentialReading
    private let decoder: AntigravityCredentialDecoder

    public init(
        reader: any AntigravityCredentialReading = AntigravityCredentialReader(),
        decoder: AntigravityCredentialDecoder = AntigravityCredentialDecoder()
    ) {
        self.reader = reader
        self.decoder = decoder
    }

    public func resolveCredential() async throws -> ResolvedCredential {
        let rawCredential = try reader.readRawCredential()
        let credential = try decoder.decode(rawCredential)

        guard let refreshToken = credential.token.refreshToken, !refreshToken.isEmpty else {
            throw OAuthError.missingRefreshToken
        }

        return ResolvedCredential(
            source: source,
            refreshToken: refreshToken,
            accessToken: credential.token.accessToken,
            accessTokenExpiresAt: credential.token.expiry.flatMap(DateParser.parse)
        )
    }
}
