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
            return "Keychain credential"
        case .environment:
            return "Environment override"
        case .ide:
            return "Antigravity IDE"
        }
    }
}

/// Long-lived credential material plus, when the credential already carries
/// one, a short-lived access token TokenOwl may reuse instead of refreshing.
///
/// Never logged, never persisted, never put in UI state.
public struct ResolvedCredential: Sendable {
    public let source: CredentialSource
    public let refreshToken: String
    public let accessToken: String?
    public let accessTokenExpiresAt: Date?

    public init(
        source: CredentialSource,
        refreshToken: String,
        accessToken: String? = nil,
        accessTokenExpiresAt: Date? = nil
    ) {
        self.source = source
        self.refreshToken = refreshToken
        self.accessToken = (accessToken?.isEmpty ?? true) ? nil : accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }
}

public protocol AntigravityCredentialProvider: Sendable {
    var source: CredentialSource { get }
    func resolveCredential() async throws -> ResolvedCredential
}
