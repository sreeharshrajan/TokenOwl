import Foundation

/// Codex CLI and its VS Code extension share the Codex login managed by app-server.
public struct CodexQuotaProvider: AIQuotaProvider {
    public let editor: AIEditor
    private let client: (any CodexProcessClient)?

    public init(editor: AIEditor = .codex, client: (any CodexProcessClient)? = nil) {
        precondition(editor == .codex)
        self.editor = editor
        self.client = client
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let resolved: any CodexProcessClient
        if let client { resolved = client }
        else {
            guard let path = CodexBinaryResolver().resolve() else { throw CodexError.codexNotInstalled }
            resolved = CodexProcessClientLive(binaryPath: path)
        }
        let result = try await resolved.fetchRateLimits()
        let summary = CodexQuotaSummary(response: result.response)
        guard !summary.windows.isEmpty else { throw CodexError.rateLimitsUnavailable }
        return ProviderSnapshot(
            editor: editor, fetchedAt: Date(), accountEmail: result.accountEmail,
            tierDisplayName: summary.planType,
            credentialSourceDisplayName: "Codex login",
            metrics: summary.windows.map {
                ProviderMetric(id: $0.limitId, label: $0.label, remainingPercent: $0.remainingPercent, resetAt: $0.resetsAt)
            }, headlineRemainingPercent: summary.mostConstrainedPercent
        )
    }
}

