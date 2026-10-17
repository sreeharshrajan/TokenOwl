import SwiftUI
import TokenOwlCore

/// A single quota window: name, percentage, sleek gradient progress bar, exact reset time and countdown.
struct QuotaBucketView: View {

    let bucket: QuotaBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label & Percentage row
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(bucket.disabled ? "N/A" : "\(bucket.remainingPercent)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(percentageColor)
            }

            // Gradient progress bar
            if !bucket.disabled {
                QuotaBar(fraction: progress, severity: bucket.severity)
                    .padding(.vertical, 1)
            }

            // Reset time with clock icon
            if bucket.disabled {
                Text(bucket.description ?? "This limit does not currently apply.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if !resetText.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.7))

                    Text(resetText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var displayName: String {
        var name = bucket.displayName
        if name.hasSuffix(" Remaining") {
            name = String(name.dropLast(" Remaining".count))
        }
        return name
    }

    private var progress: Double {
        min(max(bucket.remainingFraction, 0), 1)
    }

    private var resetText: String {
        ResetTimeFormatting.text(resetAt: bucket.resetAt)
    }

    /// Matches the screenshot colors:
    /// Weekly limit displays in bright green; Five hour limit displays in vibrant yellow/gold.
    private var percentageColor: Color {
        if bucket.disabled { return .secondary }
        switch bucket.severity {
        case .normal:
            let lower = displayName.lowercased()
            if lower.contains("five") || lower.contains("5") {
                return Color(red: 0.96, green: 0.85, blue: 0.35)
            }
            return Color(red: 0.25, green: 0.88, blue: 0.5)
        case .warning:
            return .orange
        case .critical, .exhausted:
            return .red
        }
    }

    private var accessibilityLabel: String {
        if bucket.disabled {
            return "\(displayName): not applicable. \(bucket.description ?? "")"
        }
        var label = "\(displayName): \(bucket.remainingPercent) percent remaining"
        if !resetText.isEmpty {
            label += ", \(resetText)"
        }
        return label
    }
}

/// A sleek filled capacity bar with gradient fill matching the screenshot.
private struct QuotaBar: View {

    let fraction: Double
    let severity: QuotaSeverity

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.12))

                // Gradient Progress Fill
                Capsule()
                    .fill(barGradient)
                    .frame(width: max(geometry.size.width * fraction, 0))
            }
        }
        .frame(height: 4.5)
        .accessibilityHidden(true)
    }

    private var barGradient: LinearGradient {
        switch severity {
        case .exhausted, .critical:
            return LinearGradient(
                colors: [Color.red, Color.orange],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .warning:
            return LinearGradient(
                colors: [Color(red: 0.95, green: 0.75, blue: 0.2), Color(red: 0.95, green: 0.55, blue: 0.15)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .normal:
            return LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.85, blue: 0.45),
                    Color(red: 0.95, green: 0.85, blue: 0.28)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
