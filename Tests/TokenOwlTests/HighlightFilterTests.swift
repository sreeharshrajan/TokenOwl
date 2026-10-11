import Foundation
import Testing
@testable import TokenOwlCore

struct HighlightFilterTests {

    private var sampleSummary: AntigravityQuotaSummary {
        Fixtures.quotaSummary
    }

    @Test func geminiModelWithWeeklyPeriod() {
        let bucket = HighlightFilter.resolveBucket(
            in: sampleSummary,
            model: .gemini,
            period: .weekly
        )

        #expect(bucket?.remainingPercent == 81)
        #expect(bucket?.bucketId == "gemini-weekly")
    }

    @Test func geminiModelWithFiveHoursPeriod() {
        let bucket = HighlightFilter.resolveBucket(
            in: sampleSummary,
            model: .gemini,
            period: .fiveHours
        )

        #expect(bucket?.bucketId == "gemini-5h")
        #expect(bucket?.remainingPercent == 100)
    }

    @Test func claudeModelWithWeeklyPeriod() {
        let bucket = HighlightFilter.resolveBucket(
            in: sampleSummary,
            model: .claudeAndGPT,
            period: .weekly
        )

        #expect(bucket?.bucketId == "claude-gpt-weekly")
        #expect(bucket?.remainingPercent == 100)
    }

    @Test func labelsFormatAccurately() {
        #expect(HighlightFilter.label(model: .gemini, period: .fiveHours) == "Gemini • 5 Hours")
        #expect(HighlightFilter.label(model: .claudeAndGPT, period: .weekly) == "Claude & GPT • Weekly")
    }

    @Test func nilSummaryReturnsNil() {
        let bucket = HighlightFilter.resolveBucket(
            in: nil,
            model: .gemini,
            period: .weekly
        )

        #expect(bucket == nil)
    }
}

struct CodexHighlightSelectionTests {
    @Test func selectsQuotaGroupAndPeriodWithoutFallback() {
        let snapshot = ProviderSnapshot(
            editor: .codex, fetchedAt: Date(), accountEmail: nil,
            tierDisplayName: nil, credentialSourceDisplayName: nil,
            metrics: [
                ProviderMetric(id: "codex.primary", label: "5 hours", remainingPercent: 70, resetAt: nil),
                ProviderMetric(id: "codex.secondary", label: "Weekly", remainingPercent: 40, resetAt: nil),
                ProviderMetric(id: "special.primary", label: "5 hours", remainingPercent: 20, resetAt: nil)
            ], headlineRemainingPercent: 20
        )
        #expect(snapshot.metric(for: .fiveHours)?.remainingPercent == 20)
        #expect(snapshot.metric(for: .fiveHours, codexLimitGroup: "codex")?.remainingPercent == 70)
        #expect(snapshot.metric(for: .weekly, codexLimitGroup: "codex")?.remainingPercent == 40)
        #expect(snapshot.metric(for: .weekly, codexLimitGroup: "special") == nil)
        #expect(snapshot.metric(for: .fiveHours, codexLimitGroup: "missing") == nil)
    }
}
