import Foundation

@main
struct TokenOwl {

  static func main() async {

    print("🦉 TokenOwl POC")
    print("────────────────────────────")

    do {
      // MARK: Keychain

      print("Checking Antigravity credentials...")

      let rawCredential =
        try AntigravityCredentialReader()
        .readRawCredential()

      print("✓ Antigravity credential found")

      // MARK: Decode

      let credential =
        try AntigravityCredentialDecoder()
        .decode(rawCredential)

      print("✓ Credential decoded")

      guard
        let refreshToken = credential.token.refreshToken,
        !refreshToken.isEmpty
      else {
        throw OAuthError.missingRefreshToken
      }

      print("✓ Refresh token available")

      // MARK: OAuth

      print("")
      print("Refreshing Google access token...")

      let oauth = GoogleOAuthClient()

      let refreshed =
        try await oauth.refreshAccessToken(
          refreshToken: refreshToken
        )

      print("✓ Google OAuth refresh successful")
      print("✓ New access token received")

      print("")
      print("Fetching Antigravity quota and account info...")

      let quotaClient = AntigravityQuotaClient()

      async let quotaTask = quotaClient.fetchQuota(
        accessToken: refreshed.accessToken
      )
      async let accountTask = quotaClient.fetchAccount(
        accessToken: refreshed.accessToken
      )

      let (quota, account) = try await (quotaTask, accountTask)

      let snapshot = AntigravitySnapshot(
        account: account,
        quota: quota,
        fetchedAt: Date()
      )

      print("✓ Quota & account received")
      print("")
      print("🦉 TokenOwl")
      print("────────────────────────────")
      if let email = snapshot.account.email {
        print("Account: \(email)")
      }
      if let tierName = snapshot.account.tierName {
        print("Plan:    \(tierName)")
      }
      print("────────────────────────────")

      var lowestRemaining = 100

      for group in snapshot.quota.groups {
        print("")
        print(group.displayName)

        for bucket in group.buckets {
          let percent = bucket.remainingPercent
          lowestRemaining = min(
            lowestRemaining,
            percent
          )

          print("  \(bucket.displayName)")
          print("    \(percent)% remaining")

          if let window = bucket.window {
            print("    Window: \(window)")
          }

          if let resetTime = bucket.resetTime {
            print("    Resets: \(resetTime)")
          }
        }
      }

      print("")
      print("────────────────────────────")
      print("Most constrained: \(lowestRemaining)% remaining")

    } catch {
      print("")
      print("✗ \(error.localizedDescription)")
    }
  }
}
