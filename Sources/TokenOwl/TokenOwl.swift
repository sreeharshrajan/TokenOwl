import Foundation
import TokenOwlCore

@main
struct TokenOwl {

    static func main() async {
        if CommandLine.arguments.contains("--codex") {
            do {
                let snapshot = try await CodexQuotaProvider().fetchSnapshot()
                print("Codex connection verified")
                for metric in snapshot.metrics { print("\(metric.label): \(metric.remainingPercent)% remaining") }
            } catch {
                print("Codex verification failed: \(ErrorPresentation.message(for: error))")
                exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--editors") {
            await printEditorDiscovery()
            return
        }

        print("🦉 TokenOwl CLI")
        print("────────────────────────────")
        print("Fetching Antigravity quota...")

        let service = AntigravityService()

        do {
            let snapshot = try await service.fetchSnapshot()

            print("")
            print("✓ Credential source: \(snapshot.credentialSource.displayName)")
            print("✓ Quota received")

            print("")
            print("🦉 TokenOwl")
            print("────────────────────────────")
            print("Source:  \(snapshot.credentialSource.displayName)")

            if let email = snapshot.account.email {
                print("Account: \(email)")
            }
            if let tier = snapshot.account.tierDisplayName {
                print("Application: \(tier)")
            }

            if let change = snapshot.accountChange {
                print("")
                print("⚠ Account changed: \(change.fromEmail) → \(change.toEmail) (\(change.toSource.displayName))")
            }

            if snapshot.accountIdentityUnavailable {
                print("")
                print("⚠ Account identity could not be verified; the quota above is still current.")
            }

            let now = Date()

            for group in snapshot.quota.groups {
                print("")
                print(group.displayName)

                for bucket in group.buckets {
                    print("  \(bucket.displayName)")
                    if bucket.disabled {
                        print("    Not applicable")
                        if let description = bucket.description { print("    \(description)") }
                        continue
                    }
                    print("    \(bucket.remainingPercent)% remaining")

                    if let window = bucket.window {
                        print("    Window: \(window)")
                    }

                    let countdown = ResetTimeFormatting.text(resetAt: bucket.resetAt, now: now)
                    if !countdown.isEmpty {
                        print("    \(countdown)")
                    }
                }
            }

            print("")
            print("────────────────────────────")

            if let mostConstrained = snapshot.quota.mostConstrainedPercent,
               let bucket = snapshot.quota.mostConstrainedBucket {
                print("Most constrained: \(mostConstrained)% remaining (\(bucket.displayName))")
            } else {
                print("No quota buckets reported.")
            }

            print("Updated: \(TimeFormatting.clockString(for: snapshot.fetchedAt))")

        } catch {
            print("")
            print("✗ \(ErrorPresentation.message(for: error))")
            exit(1)
        }
    }

    /// Read-only editor discovery: reports which supported AI editors are
    /// installed and whether a verified quota adapter exists for each.
    /// Executes no binaries, reads no credentials, contacts no network.
    private static func printEditorDiscovery() async {
        print("🦉 TokenOwl — AI editor discovery")
        print("────────────────────────────")
        print("Installation detection only: no binaries executed, no credentials read.")
        print("")

        let installations = await MainActor.run {
            EditorDiscoveryService().discoverInstallations()
        }
        let registry = QuotaProviderRegistry()

        for editor in AIEditor.allCases {
            let installation = installations[editor] ?? .notInstalled
            switch installation {
            case .notInstalled:
                print("  \(editor.displayName): not installed")
            case .installed(let location):
                print("  \(editor.displayName): installed")
                print("      location:   \(location)")
                print("      quota:      \(registry.hasAdapter(for: editor) ? "adapter available" : "not configured yet")")
                print("      credentials: \(editor.readsCredentials ? "reads this editor's credential" : "never read by TokenOwl")")
            case .error(let message):
                print("  \(editor.displayName): discovery error — \(message)")
            }
        }

        print("")
        print("────────────────────────────")
    }
}
