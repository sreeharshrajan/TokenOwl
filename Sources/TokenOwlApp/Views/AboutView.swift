import SwiftUI
import TokenOwlCore

/// About view showing app details, developer information, version, and links.
struct AboutView: View {

    @Environment(QuotaStore.self) private var store: QuotaStore?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // App Identity Hero
            VStack(spacing: 8) {
                Text("🦉")
                    .font(.system(size: 44))
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    )

                Text("TokenOwl")
                    .font(.title2.weight(.bold))

                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            .padding(.vertical, 4)

            // Info Card
            VStack(alignment: .leading, spacing: 8) {
                Text("Menu bar companion for tracking Antigravity and Codex quota in real-time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)

                Divider()
                    .opacity(0.5)

                HStack {
                    Text("Developed by")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Sreeharsh Rajan")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }

                HStack {
                    Text("Website")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("sreeharsh.vercel.app", destination: URL(string: "https://sreeharsh.vercel.app/")!)
                        .font(.caption)
                }

                if let appName = store?.snapshot?.account.tierDisplayName, !appName.isEmpty {
                    HStack {
                        Text("Application")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(appName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                }

                if let email = store?.snapshot?.account.email, !email.isEmpty {
                    HStack {
                        Text("Account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                HStack {
                    Text("Support & Updates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("GitHub", destination: URL(string: "https://github.com/sreeharshrajan/TokenOwl")!)
                        .font(.caption)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )

            Spacer(minLength: 8)

            Button("Done") {
                onDismiss()
            }
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 300)
    }
}
