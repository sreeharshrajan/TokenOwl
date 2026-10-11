import SwiftUI
import TokenOwlCore

/// Compact native popover content for the menu-bar item.
struct MenuBarView: View {

    @Environment(QuotaStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            Divider()

            AccountHeaderView()

            if let snapshot = store.snapshot {
                if store.isStale {
                    Divider()
                    staleBanner
                }
                Divider()
                quotaContent(snapshot)
            } else if store.hasFailed {
                Divider()
                errorCard
            } else {
                Divider()
                loadingCard
            }

            Divider()
            footer
        }
        .frame(width: 300)
    }

    // MARK: Header

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("TokenOwl")
                .font(.headline)
            Spacer()
            Text(headlineNumber)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TokenOwl, \(headlineAccessibility)")
    }

    private var headlineNumber: String {
        store.headlinePercent.map { "\($0)%" } ?? "—"
    }

    private var headlineAccessibility: String {
        guard let percent = store.headlinePercent else {
            return "quota unavailable"
        }
        return "\(percent) percent remaining"
    }

    // MARK: Quota

    private func quotaContent(_ snapshot: AntigravitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(snapshot.quota.groups.indices, id: \.self) { index in
                QuotaGroupView(group: snapshot.quota.groups[index])
                if index < snapshot.quota.groups.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolEffect(.pulse, options: .repeating)
                .foregroundStyle(.secondary)
            Text("Loading quota…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Errors

    private var staleBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                ErrorPresentation.genericTitle,
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.orange)

            if let message = store.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            lastUpdatedLine

            Button("Retry") {
                Task { await store.refresh() }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ErrorPresentation.genericTitle)
                .font(.subheadline.weight(.medium))

            if let message = store.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            lastUpdatedLine

            Button("Retry") {
                Task { await store.refresh() }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private var lastUpdatedLine: some View {
        if let clock = store.lastSuccessfulClockText {
            Text("Last successful update: \(clock)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(
                    UpdatedText.text(
                        updatedAt: store.lastSuccessfulRefresh,
                        now: context.date
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: store.isRefreshing
                    )
            }
            .controlSize(.small)
            .disabled(store.isRefreshing)
            .accessibilityLabel(
                store.isRefreshing ? "Refreshing quota" : "Refresh quota"
            )

            settingsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var settingsMenu: some View {
        Menu {
            Button("Refresh Now") {
                Task { await store.refresh() }
            }
            .disabled(store.isRefreshing)

            Divider()

            Button("Quit TokenOwl") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Settings")
    }
}
