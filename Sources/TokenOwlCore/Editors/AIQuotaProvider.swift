import Foundation

// MARK: - Schema-neutral snapshots

/// One flat quota metric from any provider.
///
/// Deliberately not Antigravity's group/bucket shape: other editors may
/// report a single number, a per-model list, or something else entirely.
public struct ProviderMetric: Sendable, Equatable {
    public let id: String
    public let label: String
    public let remainingPercent: Int
    public let resetAt: Date?

    public init(id: String, label: String, remainingPercent: Int, resetAt: Date?) {
        self.id = id
        self.label = label
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
    }
}

/// What the application layer may see from any quota provider.
///
/// Display state only: the type has no credential field and no provider may
/// add one. `editor` records whose data this is, so it can never be
/// presented under a different editor.
public struct ProviderSnapshot: Sendable, Equatable {
    public let editor: AIEditor
    public let fetchedAt: Date
    public let accountEmail: String?
    public let tierDisplayName: String?
    public let credentialSourceDisplayName: String?
    public let metrics: [ProviderMetric]
    public let headlineRemainingPercent: Int?

    public init(
        editor: AIEditor,
        fetchedAt: Date,
        accountEmail: String?,
        tierDisplayName: String?,
        credentialSourceDisplayName: String?,
        metrics: [ProviderMetric],
        headlineRemainingPercent: Int?
    ) {
        self.editor = editor
        self.fetchedAt = fetchedAt
        self.accountEmail = accountEmail
        self.tierDisplayName = tierDisplayName
        self.credentialSourceDisplayName = credentialSourceDisplayName
        self.metrics = metrics
        self.headlineRemainingPercent = headlineRemainingPercent
    }
}

// MARK: - Provider protocol

/// How an AI editor plugs into TokenOwl's quota display.
///
/// Implementations fetch with their own credentials, for their own account,
/// and must never surface data belonging to a different editor.
public protocol AIQuotaProvider: Sendable {
    var editor: AIEditor { get }
    func fetchSnapshot() async throws -> ProviderSnapshot
}

// MARK: - Antigravity adapter

/// Adapts the existing Antigravity service to `AIQuotaProvider`.
///
/// The service remains the single implementation of Antigravity fetching
/// (credentials, retry, identity guard) — this adapter only reshapes the
/// result into the schema-neutral model, so no fetch logic is duplicated.
public struct AntigravityQuotaProvider: AIQuotaProvider {
    public let editor: AIEditor = .antigravity

    private let service: AntigravityService

    public init(service: AntigravityService) {
        self.service = service
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        ProviderSnapshot(editor: .antigravity, antigravitySnapshot: try await service.fetchSnapshot())
    }
}

extension ProviderSnapshot {
    /// Flattens Antigravity's group/bucket hierarchy into the neutral model.
    public init(editor: AIEditor, antigravitySnapshot: AntigravitySnapshot) {
        var metrics: [ProviderMetric] = []
        for group in antigravitySnapshot.quota.groups {
            for bucket in group.buckets where !bucket.disabled {
                metrics.append(
                    ProviderMetric(
                        id: bucket.bucketId,
                        label: "\(group.displayName) · \(bucket.displayName)" + (bucket.window.map { " · \($0)" } ?? ""),
                        remainingPercent: bucket.remainingPercent,
                        resetAt: bucket.resetAt
                    )
                )
            }
        }

        self.init(
            editor: editor,
            fetchedAt: antigravitySnapshot.fetchedAt,
            accountEmail: antigravitySnapshot.account.email,
            tierDisplayName: antigravitySnapshot.account.tierDisplayName,
            credentialSourceDisplayName: antigravitySnapshot.credentialSource.displayName,
            metrics: metrics,
            headlineRemainingPercent: antigravitySnapshot.quota.mostConstrainedPercent
        )
    }
}

// MARK: - Registry

/// Maps editors to their verified quota adapters.
///
/// An editor without a verified adapter resolves to `nil`, which is what
/// lets the UI state "quota integration not configured" instead of ever
/// borrowing another editor's numbers.
public struct QuotaProviderRegistry: Sendable {
    private let providers: [AIEditor: any AIQuotaProvider]

    public init(
        providers: [any AIQuotaProvider] = [AntigravityQuotaProvider(service: AntigravityService()), CodexQuotaProvider()]
    ) {
        var map: [AIEditor: any AIQuotaProvider] = [:]
        for provider in providers {
            map[provider.editor] = provider
        }
        self.providers = map
    }

    public func provider(for editor: AIEditor) -> (any AIQuotaProvider)? {
        providers[editor]
    }

    public func hasAdapter(for editor: AIEditor) -> Bool {
        providers[editor] != nil
    }

    /// Capabilities as seen through this registry: quota-adapter availability
    /// comes from the registry itself, credential access from the editor.
    public func capabilities(for editor: AIEditor) -> EditorCapabilities {
        EditorCapabilities(
            hasQuotaAdapter: hasAdapter(for: editor),
            readsCredentials: editor.readsCredentials
        )
    }
}

public extension ProviderSnapshot {
    /// An unreported selected period stays unavailable rather than displaying
    /// another period's limit.
    func metric(for period: HighlightFilter.PeriodSelection, codexLimitGroup: String? = nil) -> ProviderMetric? {
        metrics.filter { metric in
            guard codexLimitGroup == nil || metric.codexLimitGroup == codexLimitGroup else { return false }
            switch period {
            case .fiveHours: return metric.label == "5 hours"
            case .weekly: return metric.label == "Weekly"
            }
        }.min { $0.remainingPercent < $1.remainingPercent }
    }
}

public extension ProviderMetric {
    /// Codex identifies a shared quota group with primary and secondary windows.
    var codexLimitGroup: String {
        for suffix in [".primary", ".secondary"] where id.hasSuffix(suffix) {
            return String(id.dropLast(suffix.count))
        }
        return id
    }
}
