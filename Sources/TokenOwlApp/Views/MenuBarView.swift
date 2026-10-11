import SwiftUI
import TokenOwlCore

/// Native popover dashboard for the menu-bar item with compact width matching macOS standards.
struct MenuBarView: View {

    @Environment(QuotaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingActionsMenu = false
    @State private var dismissedIdentityChange: AccountChangeNotice?

    var body: some View {
        dashboardContent
            .frame(width: 300)
    }

    private var dashboardContent: some View {
        ZStack(alignment: .bottomTrailing) {
            // Dismiss area when actions menu is open
            if showingActionsMenu {
                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showingActionsMenu = false
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 10) {
                AccountHeaderView()
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 2)

                if store.selectedEditor == .antigravity {
                    if let change = store.snapshot?.accountChange,
                       change != dismissedIdentityChange {
                        identityChangeBanner(change)
                            .padding(.horizontal, 12)
                    }

                    if let snapshot = store.snapshot {
                        if store.isStale {
                            staleBanner
                                .padding(.horizontal, 12)
                        }
                        quotaContent(snapshot)
                            .padding(.horizontal, 12)
                    } else if store.hasFailed {
                        errorCard
                            .padding(.horizontal, 12)
                    } else {
                        loadingCard
                            .padding(.horizontal, 12)
                    }
                }
                else {
                    if let snapshot = store.selectedProviderSnapshot {
                        providerQuotaContent(snapshot)
                            .padding(.horizontal, 12)
                        if store.isStale { staleBanner.padding(.horizontal, 12) }
                    } else if store.hasFailed {
                        errorCard.padding(.horizontal, 12)
                    } else {
                        loadingCard.padding(.horizontal, 12)
                    }
                }

                footer
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
            }

            // Floating "Actions & Support" popover panel anchored above footer gear button
            if showingActionsMenu {
                actionsMenuOverlay
                    .padding(.trailing, 12)
                    .padding(.bottom, 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
            }
        }
    }

    // MARK: - Quota Content

    private func quotaContent(_ snapshot: AntigravitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.quota.groups.indices, id: \.self) { index in
                QuotaGroupView(group: snapshot.quota.groups[index])
            }
        }
    }

    private func providerQuotaContent(_ snapshot: ProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(store.selectedEditor == .codex ? "CODEX QUOTA" : "\(store.selectedEditor.displayName.uppercased()) QUOTA")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }

            VStack(alignment: .leading, spacing: 12) {
                if store.selectedEditor == .codex {
                    let hasFiveHour = snapshot.metrics.contains { $0.label.lowercased().contains("5") || $0.id.lowercased().contains("5") }
                    let hasWeekly = snapshot.metrics.contains { $0.label.lowercased().contains("week") || $0.id.lowercased().contains("week") }

                    ForEach(snapshot.metrics, id: \.id) { metric in
                        let name = metric.label == "5 hours" ? "Five Hour Limit" : metric.label == "Weekly" ? "Weekly Limit" : metric.label
                        QuotaBucketView(bucket: QuotaBucket(
                            bucketId: metric.id,
                            displayName: name,
                            description: nil,
                            remainingFraction: Double(metric.remainingPercent) / 100,
                            resetAt: metric.resetAt,
                            window: nil
                        ))
                    }

                    if !hasFiveHour {
                        unreportedRow(label: "Five Hour Limit")
                    }
                    if !hasWeekly {
                        unreportedRow(label: "Weekly Limit")
                    }
                } else {
                    ForEach(snapshot.metrics, id: \.id) { metric in
                        QuotaBucketView(bucket: QuotaBucket(
                            bucketId: metric.id,
                            displayName: metric.label,
                            description: nil,
                            remainingFraction: Double(metric.remainingPercent) / 100,
                            resetAt: metric.resetAt,
                            window: nil
                        ))
                    }
                    if snapshot.metrics.isEmpty {
                        Text("Connected. Quota limits are unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
    }

    private func unreportedRow(label: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Not reported")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Errors & Notices

    private func identityChangeBanner(_ change: AccountChangeNotice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                "Google account changed",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.orange)

            Text("Was \(change.fromEmail), now \(change.toEmail) via \(change.toSource.displayName).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Dismiss") {
                    dismissedIdentityChange = change
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
    }

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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private var lastUpdatedLine: some View {
        if let clock = store.lastSuccessfulClockText {
            Text("Last successful update: \(clock)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(
                    UpdatedText.text(
                        updatedAt: store.lastSuccessfulRefresh,
                        now: context.date
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Refresh button (first)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: store.isRefreshing
                    )
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .accessibilityLabel(
                store.isRefreshing ? "Refreshing quota" : "Refresh quota"
            )

            // Settings / Gear action button (then settings)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingActionsMenu.toggle()
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(showingActionsMenu ? .primary : .secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Actions & Support")
        }
    }

    // MARK: - Actions & Support Menu Overlay

    private var actionsMenuOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Actions & Support")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.bottom, 4)

            // Copy Stats in Markdown format — Antigravity's numbers only
            // appear while Antigravity is the selected editor.
            if store.selectedEditor == .antigravity {
                ActionsMenuItem(
                    title: "Copy Stats",
                    systemImage: "doc.on.doc"
                ) {
                    copyStatsToClipboard()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showingActionsMenu = false
                    }
                }
            }

            // Settings modal window
            ActionsMenuItem(
                title: "Settings...",
                systemImage: "gearshape"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingActionsMenu = false
                }
                dismiss()
                WindowManager.shared.openSettings(store: store)
            }

            // About TokenOwl modal window
            ActionsMenuItem(
                title: "About TokenOwl",
                systemImage: "info.circle"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingActionsMenu = false
                }
                dismiss()
                WindowManager.shared.openAbout(store: store)
            }

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // Exit / Quit TokenOwl
            ActionsMenuItem(
                title: "Quit TokenOwl",
                systemImage: "power",
                isDestructive: true
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.bottom, 6)
        .frame(width: 195)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.13, green: 0.14, blue: 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 14, x: 0, y: 6)
    }

    private func copyStatsToClipboard() {
        guard let snapshot = store.snapshot else { return }
        var markdown = "### 🦉 TokenOwl Quota Summary\n\n"
        if let email = snapshot.account.email, !email.isEmpty {
            markdown += "**Account:** `\(email)`\n"
        }
        if let source = snapshot.credentialSource.displayName as String?, !source.isEmpty {
            markdown += "**Credential Source:** \(source)\n"
        }
        markdown += "\n"

        for group in snapshot.quota.groups {
            markdown += "#### \(group.displayName.uppercased())\n"
            for bucket in group.buckets {
                var line = "- **\(bucket.displayName):** \(bucket.remainingPercent)%"
                let reset = ResetTimeFormatting.text(resetAt: bucket.resetAt)
                if !reset.isEmpty {
                    line += " (\(reset))"
                }
                markdown += line + "\n"
            }
            markdown += "\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
    }
}

/// Interactive menu item for the Actions & Support popup with trailing SF Symbol.
private struct ActionsMenuItem: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isDestructive ? Color.red.opacity(0.9) : .primary)

                Spacer()

                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(isDestructive ? Color.red.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isHovered ? (isDestructive ? Color.red.opacity(0.12) : Color.white.opacity(0.08)) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
