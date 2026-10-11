import SwiftUI
import TokenOwlCore

/// One quota group rendered inside a dark rounded card matching the screenshot,
/// e.g. "GEMINI MODELS" or "CLAUDE AND GPT MODELS".
struct QuotaGroupView: View {

    let group: QuotaGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Group Header with icon and uppercase title
            HStack(spacing: 6) {
                Image(systemName: groupIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(group.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }

            // Buckets stack
            VStack(alignment: .leading, spacing: 12) {
                ForEach(group.buckets.indices, id: \.self) { index in
                    QuotaBucketView(bucket: group.buckets[index])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.displayName)
    }

    private var groupIcon: String {
        let lower = group.displayName.lowercased()
        if lower.contains("gemini") {
            return "sparkles"
        } else if lower.contains("claude") || lower.contains("gpt") || lower.contains("codex") {
            return "cpu"
        } else {
            return "square.stack.3d.up"
        }
    }
}
