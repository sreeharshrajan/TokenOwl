import Foundation
import Testing
@testable import TokenOwlCore

@Suite("Codex response decoding")
struct CodexDecodingTests {

    @Test func decodesTwoWindowsFromRateLimitsByLimitId() throws {
        let json = """
        {
          "rateLimitsByLimitId": {
            "five_hour": {
              "usedPercent": 42,
              "windowDurationMins": 300,
              "resetsAt": "2026-10-12T18:00:00Z"
            },
            "weekly": {
              "usedPercent": 78,
              "windowDurationMins": 10080,
              "resetsAt": "2026-10-19T18:00:00Z"
            }
          }
        }
        """

        let response = try JSONDecoder().decode(
            CodexRateLimitResponse.self,
            from: Data(json.utf8)
        )
        let summary = CodexQuotaSummary(response: response)

        #expect(summary.windows.count == 2)

        let fiveHour = summary.windows.first { $0.limitId == "five_hour" }
        #expect(fiveHour != nil)
        #expect(fiveHour?.usedPercent == 42)
        #expect(fiveHour?.remainingPercent == 58)
        #expect(fiveHour?.windowDurationMins == 300)
        #expect(fiveHour?.label == "5 hours")
        #expect(fiveHour?.resetsAt != nil)

        let weekly = summary.windows.first { $0.limitId == "weekly" }
        #expect(weekly != nil)
        #expect(weekly?.usedPercent == 78)
        #expect(weekly?.remainingPercent == 22)
        #expect(weekly?.windowDurationMins == 10080)
        #expect(weekly?.label == "Weekly")
    }

    @Test func decodesFromRateLimitsByNameFallback() throws {
        let json = """
        {
          "rate_limits_by_name": {
            "5 hour": {
              "usedPercent": 10,
              "windowDurationMins": 300,
              "resetsAt": "2026-10-12T18:00:00Z"
            }
          }
        }
        """

        let response = try JSONDecoder().decode(
            CodexRateLimitResponse.self,
            from: Data(json.utf8)
        )
        let summary = CodexQuotaSummary(response: response)

        #expect(summary.windows.count == 1)
        #expect(summary.windows[0].limitId == "5 hour")
        #expect(summary.windows[0].remainingPercent == 90)
    }

    @Test func emptyResponseProducesNoWindows() throws {
        let json = """
        {
          "rateLimitsByLimitId": {}
        }
        """

        let response = try JSONDecoder().decode(
            CodexRateLimitResponse.self,
            from: Data(json.utf8)
        )
        let summary = CodexQuotaSummary(response: response)

        #expect(summary.windows.isEmpty)
        #expect(summary.primaryWindow == nil)
        #expect(summary.mostConstrainedPercent == nil)
    }

    @Test func missingResetsAtProducesNilDate() throws {
        let json = """
        {
          "rateLimitsByLimitId": {
            "five_hour": {
              "usedPercent": 50,
              "windowDurationMins": 300
            }
          }
        }
        """

        let response = try JSONDecoder().decode(
            CodexRateLimitResponse.self,
            from: Data(json.utf8)
        )
        let summary = CodexQuotaSummary(response: response)

        #expect(summary.windows.count == 1)
        #expect(summary.windows[0].resetsAt == nil)
        #expect(summary.windows[0].remainingPercent == 50)
    }

    @Test func unparseableResetsAtBecomesNil() throws {
        let json = """
        {
          "rateLimitsByLimitId": {
            "five_hour": {
              "usedPercent": 50,
              "windowDurationMins": 300,
              "resetsAt": "not-a-date"
            }
          }
        }
        """

        let response = try JSONDecoder().decode(
            CodexRateLimitResponse.self,
            from: Data(json.utf8)
        )
        let summary = CodexQuotaSummary(response: response)

        #expect(summary.windows[0].resetsAt == nil)
    }

    @Test func mostConstrainedWindowIsLowestRemaining() throws {
        let json = """
        {
          "rateLimitsByLimitId": {
            "five_hour": {
              "usedPercent": 90,
              "windowDurationMins": 300,
              "resetsAt": "2026-10-12T18:00:00Z"
            },
            "weekly": {
              "usedPercent": 30,
              "windowDurationMins": 10080,
              "resetsAt": "2026-10-19T18:00:00Z"
            }
          }
        }
        """

        let response = try JSONDecoder().decode(
            CodexRateLimitResponse.self,
            from: Data(json.utf8)
        )
        let summary = CodexQuotaSummary(response: response)

        #expect(summary.mostConstrainedPercent == 10)
        #expect(summary.mostConstrainedWindow?.limitId == "five_hour")
    }

    @Test func severityThresholdsApplyToCodexWindows() throws {
        let json = """
        {
          "rateLimitsByLimitId": {
            "five_hour": {
              "usedPercent": 95,
              "windowDurationMins": 300,
              "resetsAt": "2026-10-12T18:00:00Z"
            }
          }
        }
        """

        let response = try JSONDecoder().decode(
            CodexRateLimitResponse.self,
            from: Data(json.utf8)
        )
        let summary = CodexQuotaSummary(response: response)

        #expect(summary.windows[0].remainingPercent == 5)
        #expect(summary.windows[0].severity == .critical)
    }

    @Test func usedPercentIsClamped() throws {
        let json = """
        {
          "rateLimitsByLimitId": {
            "five_hour": {
              "usedPercent": 150,
              "windowDurationMins": 300,
              "resetsAt": "2026-10-12T18:00:00Z"
            }
          }
        }
        """

        let response = try JSONDecoder().decode(
            CodexRateLimitResponse.self,
            from: Data(json.utf8)
        )
        let summary = CodexQuotaSummary(response: response)

        #expect(summary.windows[0].remainingPercent == 0)
        #expect(summary.windows[0].severity == .exhausted)
    }

    @Test func unknownLimitIdIsPreservedNotFiltered() throws {
        let json = """
        {
          "rateLimitsByLimitId": {
            "custom_limit_v2": {
              "usedPercent": 25,
              "windowDurationMins": 60,
              "resetsAt": "2026-10-12T18:00:00Z"
            }
          }
        }
        """

        let response = try JSONDecoder().decode(
            CodexRateLimitResponse.self,
            from: Data(json.utf8)
        )
        let summary = CodexQuotaSummary(response: response)

        #expect(summary.windows.count == 1)
        #expect(summary.windows[0].limitId == "custom_limit_v2")
        #expect(summary.windows[0].remainingPercent == 75)
    }
}
