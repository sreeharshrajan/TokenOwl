import Foundation
import Testing
@testable import TokenOwlCore

struct DateFormattingTests {

    private let now = Date(timeIntervalSince1970: 1_791_675_455)

    // MARK: Parsing

    @Test func parsesISO8601ResetTime() {
        let date = DateParser.parse("2026-10-11T18:17:35Z")
        let expected = ISO8601DateFormatter().date(from: "2026-10-11T18:17:35Z")

        #expect(date == expected)
    }

    @Test func parsesFractionalSeconds() {
        let date = DateParser.parse("2026-10-11T18:17:35.123Z")

        #expect(date != nil)
    }

    @Test func parsesEpochSeconds() {
        let date = DateParser.parse("1791675455")

        #expect(date == Date(timeIntervalSince1970: 1_791_675_455))
    }

    @Test func rejectsUnparseableValues() {
        #expect(DateParser.parse("") == nil)
        #expect(DateParser.parse("tomorrow") == nil)
    }

    // MARK: Countdowns

    @Test func countdownForHoursAndMinutes() {
        let resetAt = now.addingTimeInterval(4 * 3600 + 58 * 60)

        #expect(ResetCountdown.text(resetAt: resetAt, now: now) == "Resets in 4h 58m")
    }

    @Test func countdownForDaysAndHours() {
        let resetAt = now.addingTimeInterval(3 * 86_400 + 6 * 3600)

        #expect(ResetCountdown.text(resetAt: resetAt, now: now) == "Resets in 3d 6h")
    }

    @Test func countdownForSixDaysAndHours() {
        let resetAt = now.addingTimeInterval(6 * 86_400 + 23 * 3600)

        #expect(ResetCountdown.text(resetAt: resetAt, now: now) == "Resets in 6d 23h")
    }

    @Test func countdownForMinutesOnly() {
        let resetAt = now.addingTimeInterval(42 * 60)

        #expect(ResetCountdown.text(resetAt: resetAt, now: now) == "Resets in 42m")
    }

    @Test func exactHoursOmitZeroMinutes() {
        let resetAt = now.addingTimeInterval(2 * 3600)

        #expect(ResetCountdown.text(resetAt: resetAt, now: now) == "Resets in 2h")
    }

    @Test func resettingNowWhenResetIsDue() {
        #expect(ResetCountdown.text(resetAt: now.addingTimeInterval(-1), now: now) == "Resetting now")
        #expect(ResetCountdown.text(resetAt: now, now: now) == "Resetting now")
        #expect(ResetCountdown.text(resetAt: now.addingTimeInterval(30), now: now) == "Resetting now")
    }

    @Test func missingResetDateRendersNothing() {
        #expect(ResetCountdown.text(resetAt: nil, now: now) == "")
    }

    // MARK: Updated labels

    @Test func updatedJustNowWithinAMinute() {
        #expect(UpdatedText.text(updatedAt: now.addingTimeInterval(-10), now: now) == "Updated just now")
    }

    @Test func updatedMinutesAndHoursAgo() {
        #expect(UpdatedText.text(updatedAt: now.addingTimeInterval(-5 * 60), now: now) == "Updated 5m ago")
        #expect(UpdatedText.text(updatedAt: now.addingTimeInterval(-3 * 3600), now: now) == "Updated 3h ago")
    }

    @Test func neverUpdatedText() {
        #expect(UpdatedText.text(updatedAt: nil, now: now) == "Not updated yet")
    }

    // MARK: Clock strings

    @Test func clockStringIsLocalizedAndShort() {
        let formatted = TimeFormatting.clockString(for: now)

        #expect(!formatted.isEmpty)
        #expect(!formatted.contains("2026"))
    }
}
