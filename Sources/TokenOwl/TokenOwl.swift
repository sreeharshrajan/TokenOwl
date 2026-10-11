import Foundation
import TokenOwlCore

@main
struct TokenOwl {

    static func main() async {
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
                print("Plan:    \(tier)")
            }

            let now = Date()

            for group in snapshot.quota.groups {
                print("")
                print(group.displayName)

                for bucket in group.buckets {
                    print("  \(bucket.displayName)")
                    print("    \(bucket.remainingPercent)% remaining")

                    if let window = bucket.window {
                        print("    Window: \(window)")
                    }

                    let countdown = ResetCountdown.text(resetAt: bucket.resetAt, now: now)
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
}
