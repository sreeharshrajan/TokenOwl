import Foundation

/// Everything the application layer is allowed to see about one quota fetch.
///
/// Deliberately contains no credential or token material of any kind.
public struct AntigravitySnapshot: Sendable {
    public let account: AntigravityAccount
    public let quota: AntigravityQuotaSummary
    public let fetchedAt: Date
    public let credentialSource: CredentialSource

    public init(
        account: AntigravityAccount,
        quota: AntigravityQuotaSummary,
        fetchedAt: Date,
        credentialSource: CredentialSource
    ) {
        self.account = account
        self.quota = quota
        self.fetchedAt = fetchedAt
        self.credentialSource = credentialSource
    }
}
