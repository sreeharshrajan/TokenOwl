import Foundation

/// A detected change of the Google account behind the displayed quota.
///
/// Carries no credential material — only the two identities already shown
/// in the UI and the source that produced the new one.
public struct AccountChangeNotice: Sendable, Equatable {
    /// The account TokenOwl established as its baseline (first seen).
    public let fromEmail: String
    /// The account the most recent fetch actually belongs to.
    public let toEmail: String
    /// The credential source that produced `toEmail`.
    public let toSource: CredentialSource

    public init(fromEmail: String, toEmail: String, toSource: CredentialSource) {
        self.fromEmail = fromEmail
        self.toEmail = toEmail
        self.toSource = toSource
    }
}

/// Everything the application layer is allowed to see about one quota fetch.
///
/// Deliberately contains no credential or token material of any kind.
public struct AntigravitySnapshot: Sendable {
    public let account: AntigravityAccount
    public let quota: AntigravityQuotaSummary
    public let fetchedAt: Date
    public let credentialSource: CredentialSource

    /// Non-nil when this fetch belongs to a different Google account than
    /// the one TokenOwl first saw, so a credential-source fallback can never
    /// switch accounts silently.
    public let accountChange: AccountChangeNotice?

    /// True when the account-identity call failed and `account` is a
    /// degraded placeholder (no email/tier) — the quota itself is current.
    public let accountIdentityUnavailable: Bool

    public init(
        account: AntigravityAccount,
        quota: AntigravityQuotaSummary,
        fetchedAt: Date,
        credentialSource: CredentialSource,
        accountChange: AccountChangeNotice? = nil,
        accountIdentityUnavailable: Bool = false
    ) {
        self.account = account
        self.quota = quota
        self.fetchedAt = fetchedAt
        self.credentialSource = credentialSource
        self.accountChange = accountChange
        self.accountIdentityUnavailable = accountIdentityUnavailable
    }
}
