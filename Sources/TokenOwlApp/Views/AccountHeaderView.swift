import SwiftUI
import TokenOwlCore

/// Circular progress ring matching the hero quota gauge in the header.
struct CircularProgressArc: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 2.8)
            Circle()
                .trim(from: 0, to: max(0.01, min(fraction, 1.0)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 2.8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.8), radius: 3)
        }
        .frame(width: 24, height: 24)
    }
}

/// Header for the compact dashboard:
/// - Top row: App title (🦉 TokenOwl) on the left, native AI Editor
///   selector on the right.
/// - Shared quota hero with percentage, reset time, and available account identity.
struct AccountHeaderView: View {

    @Environment(QuotaStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            // Top row: App title + (AI Editor selector only if > 1 editor)
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Text("🦉")
                        .font(.system(size: 15))
                    Text("TokenOwl")
                        .font(.system(size: 15, weight: .bold))
                }

                Spacer(minLength: 8)

                if store.hasMultipleEditors {
                    editorPicker
                }
            }

            heroRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - AI Editor selector (dynamic when > 1 editor)

    private var editorPicker: some View {
        Picker(selection: editorSelection) {
            ForEach(store.installedEditors) { editor in
                Text(editor.displayName)
                    .tag(editor)
            }
        } label: {
            Text("AI Editor")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("AI Editor")
    }

    private var editorSelection: Binding<AIEditor> {
        Binding(
            get: { store.selectedEditor },
            set: { store.selectedEditor = $0 }
        )
    }

    // MARK: - Shared quota hero

    private var heroRow: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 7) {
                Text(headlineNumber)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(headlineColor)
                    .monospacedDigit()

                CircularProgressArc(
                    fraction: headlineFraction,
                    color: headlineColor
                )
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(highlightTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isLowest {
                        Text("(Lowest)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let reset = resetDescription {
                    Text(reset)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                if !accountLine.isEmpty {
                    Text(accountLine)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Model Computations

    private var snapshot: AntigravitySnapshot? {
        store.selectedEditor == .antigravity ? store.snapshot : nil
    }

    private var highlightedBucket: QuotaBucket? {
        guard store.selectedEditor == .antigravity else { return nil }
        return store.highlightBucket ?? snapshot?.quota.mostConstrainedBucket
    }

    private var highlightedMetric: ProviderMetric? {
        store.selectedProviderSnapshot?.metrics.min {
            if $0.remainingPercent != $1.remainingPercent { return $0.remainingPercent < $1.remainingPercent }
            return $0.id < $1.id
        }
    }

    private var headlinePercent: Int? {
        highlightedBucket?.remainingPercent ?? store.headlinePercent
    }

    private var headlineNumber: String {
        headlinePercent.map { "\($0)%" } ?? "—"
    }

    private var headlineFraction: Double {
        if let fraction = highlightedBucket?.remainingFraction {
            return min(max(fraction, 0), 1)
        }
        if let percent = headlinePercent {
            return Double(percent) / 100.0
        }
        return 0
    }

    private var headlineColor: Color {
        guard let percent = headlinePercent else { return .secondary }
        switch QuotaSeverity(percent: percent) {
        case .normal:
            return Color(red: 0.22, green: 0.88, blue: 0.45)
        case .warning:
            return Color(red: 0.95, green: 0.75, blue: 0.2)
        case .critical, .exhausted:
            return .red
        }
    }

    private var isLowest: Bool {
        guard let highlightedBucket, let most = snapshot?.quota.mostConstrainedBucket else { return false }
        return highlightedBucket.bucketId == most.bucketId || highlightedBucket.remainingPercent == most.remainingPercent
    }

    private var highlightTitle: String {
        if store.selectedEditor == .codex {
            return "Codex • " + (highlightedMetric?.label ?? "Quota")
        }
        if let bucket = highlightedBucket {
            var name = bucket.displayName
            if name.hasSuffix(" Remaining") {
                name = String(name.dropLast(" Remaining".count))
            }
            if name.hasSuffix(" Limit") {
                name = String(name.dropLast(" Limit".count))
            }
            return "\(store.selectedModel.title) • \(name)"
        }
        return store.highlightLabel
    }

    private var resetDescription: String? {
        let resetAt = store.selectedEditor == .antigravity ? highlightedBucket?.resetAt : highlightedMetric?.resetAt
        let text = ResetTimeFormatting.text(resetAt: resetAt)
        return text.isEmpty ? nil : text
    }

    private var accountLine: String {
        if store.selectedEditor == .codex { return store.selectedProviderSnapshot?.accountEmail ?? "" }
        if let email = snapshot?.account.email, !email.isEmpty {
            return email
        }
        if store.snapshot == nil && !store.hasFailed {
            return "Loading…"
        }
        if snapshot?.accountIdentityUnavailable == true {
            return "Identity unavailable"
        }
        return "Account unavailable"
    }

    private var accessibilitySummary: String {
        "TokenOwl, AI Editor \(store.selectedEditor.displayName), \(accountLine), \(headlineNumber) \(highlightTitle)"
    }
}
