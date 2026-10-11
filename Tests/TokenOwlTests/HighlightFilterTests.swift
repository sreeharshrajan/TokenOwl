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
