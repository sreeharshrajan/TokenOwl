import Foundation

/// Where TokenOwl obtained its credential from. Displayed in the UI, so
/// account transparency stays honest about what was actually used.
public enum CredentialSource: String, Sendable, Equatable {
    case keychain
    case environment
    case ide

    public var displayName: String {
        switch self {
        case .keychain:
            return "CLI Keychain credential"
        case .environment:
            return "Environment override"
        case .ide:
            return "Antigravity IDE session"
        }
    }
}

/// Long-lived credential material plus, when the credential already carries
/// one, a short-lived access token TokenOwl may reuse instead of refreshing.
///
/// A credential with no refresh token (the IDE session token) can still be
/// used — it just cannot be renewed by TokenOwl: when its access token stops
/// working, the next provider in the priority list is tried instead.
///
/// Never logged, never persisted, never put in UI state.
public struct ResolvedCredential: Sendable {
    public let source: CredentialSource
    /// Long-lived material used to mint new access tokens. `nil` when the
    /// source only produced a short-lived access token.
    public let refreshToken: String?
    public let accessToken: String?
    public let accessTokenExpiresAt: Date?

    public init(
        source: CredentialSource,
        refreshToken: String? = nil,
        accessToken: String? = nil,
        accessTokenExpiresAt: Date? = nil
    ) {
        self.source = source
        self.refreshToken = (refreshToken?.isEmpty ?? true) ? nil : refreshToken
        self.accessToken = (accessToken?.isEmpty ?? true) ? nil : accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }

    /// Whether TokenOwl can mint a fresh access token from this credential.
    public var canRefresh: Bool {
        refreshToken != nil
    }
}

public protocol AntigravityCredentialProvider: Sendable {
    var source: CredentialSource { get }
    func resolveCredential() async throws -> ResolvedCredential
}
