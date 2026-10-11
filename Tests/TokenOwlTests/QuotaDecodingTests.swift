import Foundation
import Testing
@testable import TokenOwlCore

struct QuotaDecodingTests {

    @Test func decodesTwoGroups() throws {
        let summary = Fixtures.quotaSummary

        #expect(summary.groups.count == 2)
        #expect(summary.groups[0].displayName == "Gemini Models")
        #expect(summary.groups[1].displayName == "Claude and GPT models")
        #expect(summary.description == "Sanitized quota summary fixture")
    }

    @Test func decodesBuckets() throws {
        let buckets = Fixtures.quotaSummary.allBuckets

        #expect(buckets.count == 4)

        let weekly = buckets[0]
        #expect(weekly.bucketId == "gemini-weekly")
        #expect(weekly.displayName == "Weekly")
        #expect(weekly.remainingFraction == 0.81)
        #expect(weekly.remainingPercent == 81)
        #expect(weekly.window == "7 days")
        #expect(weekly.description == "Rolling 7 day window")
    }

    @Test func decodesResetTimeAsDate() throws {
        let weekly = Fixtures.quotaSummary.allBuckets[0]
        let expected = ISO8601DateFormatter().date(from: "2026-10-14T18:17:35Z")

        #expect(expected != nil)
        #expect(weekly.resetAt == expected)
    }

    @Test func decodesWindow() throws {
        let windows = Fixtures.quotaSummary.allBuckets.map(\.window)

        #expect(windows == ["7 days", "5 hours", "7 days", "5 hours"])
    }

    @Test func unparseableResetTimeBecomesNil() {
        let payload = QuotaBucketPayload(
            bucketId: "broken",
            displayName: "Weekly",
            description: nil,
            remainingFraction: 0.5,
            resetTime: "not-a-date",
            window: nil
        )

        #expect(QuotaBucket(payload: payload).resetAt == nil)
    }

    @Test func missingResetTimeBecomesNil() {
        let payload = QuotaBucketPayload(
            bucketId: "no-reset",
            displayName: "Weekly",
            description: nil,
            remainingFraction: 0.5,
            resetTime: nil,
            window: nil
        )

        #expect(QuotaBucket(payload: payload).resetAt == nil)
    }

    @Test func malformedJSONThrowsInvalidJSON() {
        #expect(throws: QuotaClientError.invalidJSON) {
            try AntigravityQuotaClient.summary(from: Data("this is not json".utf8))
        }
    }

    @Test func schemaMismatchThrowsDecodingFailure() {
        #expect(throws: QuotaClientError.decodingFailure) {
            try AntigravityQuotaClient.summary(from: Data(#"{"groups":"nope"}"#.utf8))
        }
    }

    @Test func missingRequiredBlockThrowsDecodingFailure() {
        #expect(throws: QuotaClientError.decodingFailure) {
            try AntigravityQuotaClient.summary(from: Data("{}".utf8))
        }
    }

    @Test func fixtureRoundTripsThroughClientDecoder() throws {
        let summary = try AntigravityQuotaClient.summary(from: Data(Fixtures.quotaJSON.utf8))

        #expect(summary.groups.count == 2)
        #expect(summary.allBuckets.count == 4)
    }
}
