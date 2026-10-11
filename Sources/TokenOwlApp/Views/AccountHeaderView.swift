import SwiftUI
import TokenOwlCore

/// Always-on account transparency: which account, which plan, and which
/// credential source produced the quota on screen.
struct AccountHeaderView: View {

    @Environment(QuotaStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Antigravity")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(accountLine)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)

            if let tier = snapshot?.account.tierDisplayName {
                Text(tier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let source = snapshot?.credentialSource {
                Text(source.displayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var snapshot: AntigravitySnapshot? {
        store.snapshot
    }

    private var accountLine: String {
        if let email = snapshot?.account.email, !email.isEmpty {
            return email
        }
        if store.snapshot == nil && !store.hasFailed {
            return "Waiting for first refresh…"
        }
        return "Account unavailable"
    }
}
