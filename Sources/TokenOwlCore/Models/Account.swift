import Foundation

/// Identity of the account the quota belongs to. No credential material.
public struct AntigravityAccount: Sendable {
    public let email: String?
    public let tierID: String?
    public let tierName: String?
    public let upgradePrompt: String?

    public init(
        email: String?,
        tierID: String?,
        tierName: String?,
        upgradePrompt: String?
    ) {
        self.email = email
        self.tierID = tierID
        self.tierName = tierName
        self.upgradePrompt = upgradePrompt
    }

    /// Best human readable plan/tier name available.
    public var tierDisplayName: String? {
        if let tierName, !tierName.isEmpty { return tierName }
        if let tierID, !tierID.isEmpty { return tierID }
        return nil
    }
}
