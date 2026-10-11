import SwiftUI
import TokenOwlCore

/// One quota group, e.g. "Gemini Models" with its weekly and 5-hour buckets.
struct QuotaGroupView: View {

    let group: QuotaGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(group.buckets.indices, id: \.self) { index in
                    QuotaBucketView(bucket: group.buckets[index])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.displayName)
    }
}
