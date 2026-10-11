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

    // MARK: Reset Time Formatting

    @Test func resetTimeFormattingForSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US_POSIX")

        let testNow = Date(timeIntervalSince1970: 1_791_675_455) // Sun, 11 Oct 2026 23:37:35 GMT
        // Reset 1 hour before midnight on same day
        let morning = calendar.startOfDay(for: testNow).addingTimeInterval(10 * 3600) // 10:00 AM
        let resetToday = morning.addingTimeInterval(4 * 3600 + 30 * 60) // 2:30 PM

        let formatted = ResetTimeFormatting.text(
            resetAt: resetToday,
            now: morning,
            calendar: calendar,
            locale: locale
        ).replacingOccurrences(of: "\u{202F}", with: " ")

        #expect(formatted == "Resets at 2:30 PM (in 4h 30m)")
    }

    @Test func resetTimeFormattingForTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US_POSIX")

        let testNow = Date(timeIntervalSince1970: 1_791_675_455) // Sun, 11 Oct 2026 23:37:35 GMT
        let resetTomorrow = testNow.addingTimeInterval(18 * 3600 + 35 * 60) // Mon 12 Oct 18:12:35 GMT

        let formatted = ResetTimeFormatting.text(
            resetAt: resetTomorrow,
            now: testNow,
            calendar: calendar,
            locale: locale
        ).replacingOccurrences(of: "\u{202F}", with: " ")

        #expect(formatted == "Resets tomorrow at 6:12 PM (in 18h 35m)")
    }

    @Test func resetTimeFormattingForFutureWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US_POSIX")

        let testNow = Date(timeIntervalSince1970: 1_791_675_455) // Sun, 11 Oct 2026 23:37:35 GMT
        let resetWed = testNow.addingTimeInterval(3 * 86_400) // Wed 14 Oct

        let formatted = ResetTimeFormatting.text(
            resetAt: resetWed,
            now: testNow,
            calendar: calendar,
            locale: locale
        )

        #expect(formatted.contains("Resets Tue at"))
        #expect(formatted.contains("3d"))
    }

    @Test func resetTimeFormattingResettingNow() {
        #expect(ResetTimeFormatting.text(resetAt: now.addingTimeInterval(10), now: now) == "Resetting now")
        #expect(ResetTimeFormatting.text(resetAt: nil, now: now) == "")
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
