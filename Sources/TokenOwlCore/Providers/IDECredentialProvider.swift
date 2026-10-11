import Foundation

/// Produces a credential from a session the Antigravity IDE stored in its
/// state database.
///
/// The IDE stores this session as plaintext inside a base64 envelope (see
/// `IDETokenStateReader`), so no Safe Storage decryption is involved. The
/// envelope carries both an access token and a refresh token, which means
/// TokenOwl can renew it itself — the renewed access token stays in memory
/// only and is never persisted.
///
/// Caution: this envelope is **not** guaranteed to be the account the IDE is
/// currently signed into — it can retain a previously signed-in account whose
/// refresh token still works. The Keychain credential tracks the live login
/// and is therefore tried first (see `AntigravityService`); this provider is
/// the fallback. When Google rejects the credential anyway, the service falls
/// back again rather than failing the whole fetch.
///
/// Read-only: nothing in the IDE's state is written or modified.
public struct IDECredentialProvider: AntigravityCredentialProvider {
    public let source: CredentialSource = .ide

    private let reader: any IDETokenStateReading

    public init(reader: any IDETokenStateReading = IDETokenStateReader()) {
        self.reader = reader
    }

    public func resolveCredential() async throws -> ResolvedCredential {
        let session = try reader.readSession()
        guard session.accessToken != nil || session.refreshToken != nil else {
            throw IDETokenStateError.emptyToken
        }

        // Deliberately logs neither the tokens nor their lengths.
        RedactedLogger.log("IDE session read from the IDE state database")

        return ResolvedCredential(
            source: source,
            refreshToken: session.refreshToken,
            accessToken: session.accessToken,
            accessTokenExpiresAt: nil
        )
    }
}
