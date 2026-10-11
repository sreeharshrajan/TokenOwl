import SwiftUI
import TokenOwlCore

/// Preferences view shown in the standalone Settings window.
struct PreferencesView: View {

    @Environment(QuotaStore.self) private var store
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Highlight settings section
            VStack(alignment: .leading, spacing: 10) {
                Text("MENU BAR HIGHLIGHT")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                // Full-width Model Dropdown
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Menu {
                        ForEach(HighlightFilter.ModelSelection.allCases, id: \.self) { model in
                            Button {
                                store.selectedModel = model
                            } label: {
                                if store.selectedModel == model {
                                    Label(model.title, systemImage: "checkmark")
                                } else {
                                    Text(model.title)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(store.selectedModel.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: .infinity)
                }

                // Full-width Time Period Dropdown
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time Period")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Menu {
                        ForEach(HighlightFilter.PeriodSelection.allCases, id: \.self) { period in
                            Button {
                                store.selectedPeriod = period
                            } label: {
                                if store.selectedPeriod == period {
                                    Label(period.title, systemImage: "checkmark")
                                } else {
                                    Text(period.title)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(store.selectedPeriod.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: .infinity)
                }

                Text("Controls the percentage shown in the menu bar and the popover hero number.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Account & info section
            VStack(alignment: .leading, spacing: 6) {
                Text("ACCOUNT & CREDENTIALS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                if let email = store.snapshot?.account.email {
                    HStack {
                        Text("Account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(email)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if let source = store.snapshot?.credentialSource {
                    HStack {
                        Text("Source")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(source.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let tier = store.snapshot?.account.tierDisplayName, !tier.isEmpty {
                    HStack {
                        Text("Application")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(tier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Quit TokenOwl") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
