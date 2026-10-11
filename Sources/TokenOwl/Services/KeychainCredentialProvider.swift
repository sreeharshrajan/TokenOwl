import Foundation

struct KeychainCredentialProvider: AntigravityCredentialProvider {
    let source: CredentialSource = .cliKeychain

    func resolveCredential() async throws -> ResolvedCredential {
        let rawCredential = try AntigravityCredentialReader().readRawCredential()
        let credential = try AntigravityCredentialDecoder().decode(rawCredential)

        guard let refreshToken = credential.token.refreshToken, !refreshToken.isEmpty else {
            throw OAuthError.missingRefreshToken
        }

        return ResolvedCredential(
            source: source,
            refreshToken: refreshToken
        )
    }
}
