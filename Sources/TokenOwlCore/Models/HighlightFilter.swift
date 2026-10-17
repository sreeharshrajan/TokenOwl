import Foundation

/// Filter configuration for which model and time period should be highlighted
/// in the menu bar and the popover hero header.
public struct HighlightFilter: Equatable, Sendable {

    public enum ModelSelection: String, CaseIterable, Sendable {
        case gemini = "gemini"
        case claudeAndGPT = "claude"

        public var title: String {
            switch self {
            case .gemini: return "Gemini"
            case .claudeAndGPT: return "Claude & GPT"
            }
        }
    }

    public enum PeriodSelection: String, CaseIterable, Sendable {
        case fiveHours = "5h"
        case weekly = "weekly"

        public var title: String {
            switch self {
            case .fiveHours: return "5 Hours"
            case .weekly: return "Weekly"
            }
        }
    }

    /// Resolves the bucket matching the user's selected model and time period.
    /// Falls back gracefully to the most constrained bucket if no specific bucket matches.
    public static func resolveBucket(
        in summary: AntigravityQuotaSummary?,
        model: ModelSelection,
        period: PeriodSelection,
        requireMatchingPeriod: Bool = false
    ) -> QuotaBucket? {
        guard let summary else { return nil }

        // Step 1: Filter groups by model selection
        let candidateGroups: [QuotaGroup]
        switch model {
        case .gemini:
            let filtered = summary.groups.filter {
                $0.displayName.localizedCaseInsensitiveContains("gemini")
            }
            candidateGroups = filtered.isEmpty ? summary.groups : filtered
        case .claudeAndGPT:
            let filtered = summary.groups.filter {
                $0.displayName.localizedCaseInsensitiveContains("claude") ||
                $0.displayName.localizedCaseInsensitiveContains("gpt")
            }
            candidateGroups = filtered.isEmpty ? summary.groups : filtered
        }

        // Step 2: Filter candidate buckets by period selection
        let allCandidates = candidateGroups.flatMap(\.buckets).filter { !$0.disabled }
        let candidateBuckets: [QuotaBucket]
        switch period {
        case .fiveHours:
            let filtered = allCandidates.filter {
                ($0.window?.contains("5") == true) ||
                $0.displayName.localizedCaseInsensitiveContains("5") ||
                $0.displayName.localizedCaseInsensitiveContains("five") ||
                $0.bucketId.localizedCaseInsensitiveContains("5h")
            }
            candidateBuckets = filtered.isEmpty && !requireMatchingPeriod ? allCandidates : filtered
        case .weekly:
            let filtered = allCandidates.filter {
                ($0.window?.contains("7") == true) ||
                $0.displayName.localizedCaseInsensitiveContains("week") ||
                $0.bucketId.localizedCaseInsensitiveContains("weekly")
            }
            candidateBuckets = filtered.isEmpty && !requireMatchingPeriod ? allCandidates : filtered
        }

        // Step 3: Pick the lowest remaining percentage among matching candidates
        return candidateBuckets.min { lhs, rhs in
            if lhs.remainingPercent != rhs.remainingPercent {
                return lhs.remainingPercent < rhs.remainingPercent
            }
            return lhs.bucketId < rhs.bucketId
        } ?? (requireMatchingPeriod ? nil : summary.mostConstrainedBucket)
    }

    /// Prefer the short window until it is exhausted; absent data does not
    /// imply exhaustion.
    public static func automaticPeriod(fiveHourRemainingPercent: Int?) -> PeriodSelection {
        if let fiveHourRemainingPercent, fiveHourRemainingPercent <= 0 { return .weekly }
        return .fiveHours
    }

    /// Short label describing the active highlight criteria.
    public static func label(model: ModelSelection, period: PeriodSelection) -> String {
        "\(model.title) • \(period.title)"
    }
}
