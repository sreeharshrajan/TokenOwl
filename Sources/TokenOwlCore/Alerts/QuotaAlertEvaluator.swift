import Foundation

public struct QuotaAlertPreferences: Codable, Equatable, Sendable {
    public var enabled = true
    public var antigravityEnabled = true
    public var codexEnabled = true
    public var backgroundAntigravity = false
    public var backgroundCodex = false
    public var thresholds: Set<Int> = [10]
    public init() {}
    public func allows(_ editor: AIEditor) -> Bool {
        enabled && (editor == .antigravity ? antigravityEnabled : editor == .codex && codexEnabled)
    }
    public func monitors(_ editor: AIEditor, selected: AIEditor) -> Bool {
        editor == selected || (allows(editor) && (editor == .antigravity ? backgroundAntigravity : editor == .codex && backgroundCodex))
    }
}

public struct QuotaAlert: Equatable, Sendable {
    public let editor: AIEditor
    public let metric: ProviderMetric
    public let threshold: Int
    public var identifier: String {
        "tokenowl.\(editor.rawValue).\(metric.id).\(metric.resetAt?.timeIntervalSince1970.description ?? "unknown").\(threshold)"
    }
}

/// Process-local baselines deliberately suppress historical alerts after launch.
/// State is isolated by editor/bucket and retained only for the current reset window.
public struct QuotaAlertEvaluator: Sendable {
    private struct Key: Hashable, Sendable { let editor: AIEditor; let bucket: String }
    private struct State: Sendable {
        var percent: Int
        var reset: Date?
        var fired: Set<Int>
        var fetchedAt: Date
        var account: String?
    }
    private var states: [Key: State] = [:]
    public init() {}
    public mutating func evaluate(_ snapshot: ProviderSnapshot, preferences: QuotaAlertPreferences,
                                  verified: Bool = true, stale: Bool = false,
                                  permissionGranted: Bool = true) -> [QuotaAlert] {
        guard verified, !stale else { return [] }
        var alerts: [QuotaAlert] = []
        for metric in snapshot.metrics where (0...100).contains(metric.remainingPercent) {
            let key = Key(editor: snapshot.editor, bucket: metric.id)
            let previous = states[key]
            guard previous == nil || snapshot.fetchedAt > previous!.fetchedAt else { continue }
            var state = State(percent: metric.remainingPercent, reset: metric.resetAt, fired: [],
                              fetchedAt: snapshot.fetchedAt, account: snapshot.accountEmail)
            if let previous, previous.reset == metric.resetAt, previous.account == snapshot.accountEmail {
                state.fired = previous.fired
                let crossed = preferences.thresholds.intersection([50, 25, 10, 5]).filter {
                    previous.percent > $0 && metric.remainingPercent <= $0 && !state.fired.contains($0)
                }
                if let threshold = crossed.min(), preferences.allows(snapshot.editor), permissionGranted {
                    // Consume every crossed threshold: only the most severe one is delivered.
                    state.fired.formUnion(crossed)
                    alerts.append(QuotaAlert(editor: snapshot.editor, metric: metric, threshold: threshold))
                }
            }
            states[key] = state
        }
        return alerts
    }
}
