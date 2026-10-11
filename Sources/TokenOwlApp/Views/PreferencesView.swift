import SwiftUI
import TokenOwlCore

/// Preferences view shown in the standalone Settings window.
struct PreferencesView: View {

    @Environment(QuotaStore.self) private var store
    let onDismiss: () -> Void

    private var hasAlertProvider: Bool {
        store.alertPreferences.antigravityEnabled || store.alertPreferences.codexEnabled
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Automatically switch between editors", isOn: $store.followsActiveApplication)
                    Text("Switch to Antigravity to show its quota, or to VS Code, VS Code Insiders, or the Codex app to show Codex quota. Other apps keep the current selection. Turn this off to choose the editor yourself.")
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Antigravity model", selection: $store.selectedModel) {
                        ForEach(HighlightFilter.ModelSelection.allCases, id: \.self) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    Picker("Antigravity time period", selection: $store.selectedPeriod) {
                        ForEach(HighlightFilter.PeriodSelection.allCases, id: \.self) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    Picker("Codex model / quota group", selection: $store.codexHighlightModel) {
                        Text("All models").tag("all")
                        ForEach(store.codexHighlightModels, id: \.self) { model in
                            Text(model == "codex" ? "Codex (shared quota)" : model).tag(model)
                        }
                        if store.codexHighlightModel != "all", !store.codexHighlightModels.contains(store.codexHighlightModel) {
                            Text("\(store.codexHighlightModel) (not reported)").tag(store.codexHighlightModel)
                        }
                    }
                    Picker("Codex time period", selection: $store.codexHighlightPeriod) {
                        ForEach(HighlightFilter.PeriodSelection.allCases, id: \.self) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    Text("Each editor keeps its own highlight settings. Codex model options come from its reported quota groups; some models share a single quota.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Controls the popover highlight. The menu bar shows 5h until exhausted, then Weekly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Menu bar highlight", systemImage: "menubar.rectangle")
                }

                Section {
                    Toggle("Enable quota notifications", isOn: $store.alertPreferences.enabled)
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Antigravity alerts", isOn: $store.alertPreferences.antigravityEnabled)
                        Toggle("Codex alerts", isOn: $store.alertPreferences.codexEnabled)
                        Picker("Warn when remaining", selection: Binding(
                            get: { store.alertPreferences.thresholds.intersection([50, 25, 10, 5]).min() ?? 10 },
                            set: { store.alertPreferences.thresholds = [$0] }
                        )) {
                            ForEach([50, 25, 10, 5], id: \.self) { threshold in
                                Text("\(threshold)%").tag(threshold)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(!hasAlertProvider)
                        Text("Alerts fire when quota crosses this threshold, once per reset period.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .disabled(!store.alertPreferences.enabled)
                    HStack {
                        Text(store.notifications.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if store.notifications.canRequest {
                            Button("Allow Notifications") {
                                Task { await store.notifications.requestPermission() }
                            }
                            .disabled(!store.alertPreferences.enabled)
                        }
                    }
                } header: {
                    Label("Notifications", systemImage: "bell")
                }

                Section {
                    Toggle("Monitor Antigravity", isOn: $store.alertPreferences.backgroundAntigravity)
                        .disabled(!store.alertPreferences.allows(.antigravity))
                    Toggle("Monitor Codex", isOn: $store.alertPreferences.backgroundCodex)
                        .disabled(!store.alertPreferences.allows(.codex))
                    Text("Refreshes an unselected editor every five minutes. Requires quota notifications and that editor’s alerts to be enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Background monitoring", systemImage: "arrow.clockwise")
                }

                Section {
                    Toggle("Launch at login", isOn: Binding(
                        get: { store.notifications.loginEnabled },
                        set: { store.notifications.setLoginEnabled($0) }
                    ))
                    if let message = store.notifications.loginError {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    } else if !store.notifications.loginStatus.isEmpty {
                        Text(store.notifications.loginStatus).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Label("General", systemImage: "gearshape")
                }

            // Account & info section
            Section("Account & credentials") {
                if let email = store.selectedProviderSnapshot?.accountEmail {
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

                if let source = store.selectedProviderSnapshot?.credentialSourceDisplayName {
                    HStack {
                        Text("Source")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let tier = store.selectedProviderSnapshot?.tierDisplayName, !tier.isEmpty {
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

            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .controlSize(.small)

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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 520, idealHeight: 640)
        .task { await store.notifications.updatePermission() }
    }
}
