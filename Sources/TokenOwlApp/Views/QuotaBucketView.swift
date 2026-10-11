import SwiftUI
import TokenOwlCore

/// A single quota window: name, percentage, progress bar, reset countdown.
struct QuotaBucketView: View {

    let bucket: QuotaBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bucket.displayName)
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text("\(bucket.remainingPercent)%")
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.medium)
            }

            QuotaBar(fraction: progress, color: severityColor)

            if !countdown.isEmpty {
                Text(countdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var progress: Double {
        min(max(bucket.remainingFraction, 0), 1)
    }

    private var countdown: String {
        ResetCountdown.text(resetAt: bucket.resetAt)
    }

    /// System colors only, so Light/Dark Mode is handled by the system and
    /// the numeric percentage always stays visible next to the bar.
    private var severityColor: Color {
        switch bucket.severity {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical, .exhausted:
            return .red
        }
    }

    private var accessibilityLabel: String {
        var label = "\(bucket.displayName): \(bucket.remainingPercent) percent remaining"
        if !countdown.isEmpty {
            label += ", \(countdown)"
        }
        return label
    }
}

/// A filled capacity bar built from plain SwiftUI shapes.
///
/// `ProgressView` is avoided deliberately: offscreen rendering of
/// `NSProgressIndicator`-backed controls is unreliable, and the numeric
/// percentage is always shown next to the bar, so the bar itself carries no
/// information that is not repeated in text or the accessibility label.
private struct QuotaBar: View {

    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
