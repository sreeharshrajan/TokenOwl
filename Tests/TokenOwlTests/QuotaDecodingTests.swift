import Foundation
import Testing
@testable import TokenOwlCore

struct QuotaDecodingTests {

    @Test func routesConsumerAndGCPTiersLikeIDE() {
        #expect(AntigravityQuotaClient.quotaURL(accountDetails: [
            "paidTier": ["usesGcpTos": false]
        ]).host == "daily-cloudcode-pa.googleapis.com")
        #expect(AntigravityQuotaClient.quotaURL(accountDetails: [
            "paidTier": ["usesGcpTos": true]
        ]).host == "cloudcode-pa.googleapis.com")
        // The IDE treats an absent paid tier/flag as consumer terms after loadCodeAssist.
        #expect(AntigravityQuotaClient.quotaURL(accountDetails: [:]).host == "daily-cloudcode-pa.googleapis.com")
    }

    @Test func disabledWindowIsPreservedButExcludedFromMetricsAndHighlights() throws {
        let summary = try AntigravityQuotaClient.summary(from: Data(#"""
        {"groups":[{"displayName":"Claude and GPT models","buckets":[
          {"bucketId":"3p-weekly","displayName":"Weekly Limit Remaining","window":"weekly","remainingFraction":0},
          {"bucketId":"3p-5h","displayName":"Five Hour Limit Remaining","window":"5h","remainingFraction":1,"disabled":true,"description":"The five-hour limit does not currently apply."}
        ]}]}
        """#.utf8))
        let disabled = summary.groups[0].buckets[1]
        #expect(disabled.disabled)
        #expect(disabled.description == "The five-hour limit does not currently apply.")
        #expect(summary.allBuckets.map(\.bucketId) == ["3p-weekly"])
        #expect(HighlightFilter.resolveBucket(in: summary, model: .claudeAndGPT,
            period: .fiveHours, requireMatchingPeriod: true) == nil)
        #expect(HighlightFilter.resolveBucket(in: summary, model: .claudeAndGPT,
            period: .fiveHours)?.bucketId == "3p-weekly")
    }

    @Test func existingResponsesDefaultToEnabled() {
        #expect(Fixtures.quotaSummary.allBuckets.allSatisfy { !$0.disabled })
    }

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
            window: nil,
            disabled: nil
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
            window: nil,
            disabled: nil
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

    // MARK: Retry-After parsing (HTTP 429)

    @Test func parsesRetryAfterDeltaSeconds() {
        let response = HTTPURLResponse(
            url: URL(string: "https://cloudcode-pa.googleapis.com")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": "7"]
        )!

        #expect(AntigravityQuotaClient.retryAfterSeconds(from: response) == 7)
    }

    @Test func parsesRetryAfterHTTPDate() {
        // 2023-11-14 22:13:20 UTC; header says 2023-11-15 00:00:00 GMT.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let response = HTTPURLResponse(
            url: URL(string: "https://cloudcode-pa.googleapis.com")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": "Wed, 15 Nov 2023 00:00:00 GMT"]
        )!

        #expect(
            AntigravityQuotaClient.retryAfterSeconds(from: response, now: now) == 6_400
        )
    }

    @Test func missingOrMalformedRetryAfterIsNil() {
        let missing = HTTPURLResponse(
            url: URL(string: "https://cloudcode-pa.googleapis.com")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        #expect(AntigravityQuotaClient.retryAfterSeconds(from: missing) == nil)

        let malformed = HTTPURLResponse(
            url: URL(string: "https://cloudcode-pa.googleapis.com")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": "soon"]
        )!
        #expect(AntigravityQuotaClient.retryAfterSeconds(from: malformed) == nil)
    }
}
