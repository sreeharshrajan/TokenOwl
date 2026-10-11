import Foundation

/// Foundation-only date helpers. No manual timezone arithmetic anywhere:
/// everything is `Date` subtraction plus Foundation formatters.
public enum DateParser {

    /// Parses the shapes TokenOwl may encounter:
    /// - `2026-10-11T18:17:35Z` (API reset times)
    /// - `2026-10-11T18:17:35.123Z` (fractional seconds)
    /// - epoch seconds (`"1791675455"`)
    public static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: trimmed) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) {
            return date
        }

        if let epoch = TimeInterval(trimmed) {
            return Date(timeIntervalSince1970: epoch)
        }

        return nil
    }
}

/// Human readable quota reset countdowns, e.g. `Resets in 4h 58m`.
public enum ResetCountdown {

    public static func duration(resetAt: Date?, now: Date = Date()) -> String? {
        guard let resetAt else { return nil }

        let remaining = resetAt.timeIntervalSince(now)

        // Already resetting (or within the same minute).
        guard remaining >= 60 else { return nil }

        let totalSeconds = Int(remaining.rounded())

        if totalSeconds < 3600 {
            return "\(totalSeconds / 60)m"
        }

        if totalSeconds < 86_400 {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            return minutes == 0
                ? "\(hours)h"
                : "\(hours)h \(minutes)m"
        }

        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3600
        return hours == 0
            ? "\(days)d"
            : "\(days)d \(hours)h"
    }

    /// - Parameters:
    ///   - resetAt: the normalized reset instant
    ///   - now: injectable clock, used by tests
    public static func text(resetAt: Date?, now: Date = Date()) -> String {
        guard let resetAt else { return "" }
        guard let dur = duration(resetAt: resetAt, now: now) else {
            return "Resetting now"
        }
        return "Resets in \(dur)"
    }
}

/// Human readable quota reset times showing exact clock time and countdown,
/// e.g. `Resets at 11:06 PM (in 4h 59m)` or `Resets tomorrow at 12:42 PM (in 18h 35m)`.
public enum ResetTimeFormatting {

    public static func text(
        resetAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard let resetAt else { return "" }
        guard let dur = ResetCountdown.duration(resetAt: resetAt, now: now) else {
            return "Resetting now"
        }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timeString = timeFormatter.string(from: resetAt)

        let startOfNow = calendar.startOfDay(for: now)
        let startOfReset = calendar.startOfDay(for: resetAt)
        let days = calendar.dateComponents([.day], from: startOfNow, to: startOfReset).day ?? 0

        let dayPrefix: String
        if days <= 0 {
            dayPrefix = "at \(timeString)"
        } else if days == 1 {
            dayPrefix = "tomorrow at \(timeString)"
        } else if days < 7 {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.locale = locale
            weekdayFormatter.timeZone = calendar.timeZone
            weekdayFormatter.dateFormat = "EEE"
            let weekday = weekdayFormatter.string(from: resetAt)
            dayPrefix = "\(weekday) at \(timeString)"
        } else {
            let monthDayFormatter = DateFormatter()
            monthDayFormatter.locale = locale
            monthDayFormatter.timeZone = calendar.timeZone
            monthDayFormatter.dateFormat = "MMM d"
            let monthDay = monthDayFormatter.string(from: resetAt)
            dayPrefix = "\(monthDay) at \(timeString)"
        }

        return "Resets \(dayPrefix) (in \(dur))"
    }
}

/// "Updated just now" style labels.
public enum UpdatedText {
    public static func text(updatedAt: Date?, now: Date = Date()) -> String {
        guard let updatedAt else { return "Not updated yet" }

        let elapsed = max(0, Int(now.timeIntervalSince(updatedAt).rounded()))

        if elapsed < 60 { return "Updated just now" }
        if elapsed < 3600 { return "Updated \(elapsed / 60)m ago" }
        if elapsed < 86_400 { return "Updated \(elapsed / 3600)h ago" }
        return "Updated \(elapsed / 86_400)d ago"
    }
}

public enum TimeFormatting {
    /// Short localized clock string, e.g. `6:42 PM`.
    public static func clockString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
