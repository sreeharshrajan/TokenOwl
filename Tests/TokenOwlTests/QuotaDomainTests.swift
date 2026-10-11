import Foundation
import Testing
@testable import TokenOwlCore

struct QuotaDomainTests {

    @Test func remainingPercentMatchesFraction() {
        let bucket = QuotaBucket(
            bucketId: "b",
            displayName: "Weekly",
            description: nil,
            remainingFraction: 0.81,
            resetAt: nil,
            window: nil
        )

        #expect(bucket.remainingPercent == 81)
    }

    @Test func menuReports81ForRealWorldShape() {
        let summary = Fixtures.summary(grouped: [[81, 100], [100, 100]])

        #expect(summary.mostConstrainedPercent == 81)
        #expect(summary.mostConstrainedBucket?.displayName == "Bucket 0")
        #expect(summary.groups.count == 2)
    }

    @Test func mostConstrainedIsZeroWhenAnyBucketIsExhausted() {
        let summary = Fixtures.summary(grouped: [[6, 99], [0, 100]])

        #expect(summary.mostConstrainedPercent == 0)
        #expect(summary.mostConstrainedBucket?.remainingPercent == 0)
    }

    @Test func bucketsAreNeverAveraged() {
        // (81 + 100 + 100 + 100) / 4 = 95.25 — the average must never win.
        let summary = Fixtures.summary(grouped: [[81, 100], [100, 100]])

        #expect(summary.mostConstrainedPercent == 81)
        #expect(summary.mostConstrainedPercent != 95)
    }

    @Test func flatQuotaReports100() {
        let summary = Fixtures.summary(percentages: [100, 100, 100, 100])

        #expect(summary.mostConstrainedPercent == 100)
    }

    @Test func emptySummaryHasNoMostConstrainedBucket() {
        let summary = AntigravityQuotaSummary(description: nil, groups: [])

        #expect(summary.mostConstrainedBucket == nil)
        #expect(summary.mostConstrainedPercent == nil)
        #expect(summary.allBuckets.isEmpty)
    }

    @Test func severityThresholds() {
        #expect(QuotaSeverity(percent: 100) == .normal)
        #expect(QuotaSeverity(percent: 51) == .normal)
        #expect(QuotaSeverity(percent: 50) == .warning)
        #expect(QuotaSeverity(percent: 20) == .warning)
        #expect(QuotaSeverity(percent: 19) == .critical)
        #expect(QuotaSeverity(percent: 1) == .critical)
        #expect(QuotaSeverity(percent: 0) == .exhausted)
    }

    @Test func snapshotExposesCredentialSourceWithoutCredentials() {
        let snapshot = AntigravitySnapshot(
            account: AntigravityAccount(
                email: "fixture@example.com",
                tierID: "free-tier",
                tierName: "Antigravity Free",
                upgradePrompt: nil
            ),
            quota: Fixtures.summary(percentages: [81]),
            fetchedAt: Date(),
            credentialSource: .keychain
        )

        #expect(snapshot.credentialSource.displayName == "Keychain credential")
        #expect(snapshot.account.tierDisplayName == "Antigravity Free")
        #expect(snapshot.account.email == "fixture@example.com")
    }
}
