import Foundation
@testable import TokenOwlCore

/// Sanitized, synthetic fixtures. Never contains a real OAuth credential.
enum Fixtures {

    // MARK: Credentials

    static let rawCredentialJSON = """
    {
      "token": {
        "access_token": "fixture-access-token",
        "refresh_token": "fixture-refresh-token",
        "expiry": "2026-10-11T18:17:35Z"
      }
    }
    """

    static let goKeyringCredential =
        "go-keyring-base64:" + Data(rawCredentialJSON.utf8).base64EncodedString()

    static let malformedCredential = "not-a-credential"

    static let malformedBase64Credential = "go-keyring-base64:%%%not-base64%%%"

    static let credentialWithoutToken = #"{"unrelated":true}"#

    /// Synthetic stand-in for the IDE session access token. Never a real one.
    static let ideSessionToken = "fixture-ide-session-token"

    /// Synthetic Google-shaped access token (`ya29.` prefix required by the
    /// reader's extraction pattern). Never a real one.
    static let ideAccessToken =
        "ya29.a0AfFixtureAccessToken_0123456789abcdefghijklm"

    /// Synthetic Google-shaped refresh token (`1//` prefix, opaque tail).
    /// Never a real one.
    static let ideRefreshToken =
        "1//0cFixtureRefreshToken_0123456789abcdefghijklmno"

    /// Synthetic stand-in for the IDE's stored value: base64 of a JSON state
    /// that carries the sentinel key followed by a base64 session blob
    /// holding both tokens — the same nesting the real database uses.
    static let ideSessionEnvelope: String = {
        let blob = "session-blob-begin "
            + ideAccessToken + " " + ideRefreshToken
            + " session-blob-end"
        let nested = Data(blob.utf8).base64EncodedString()
        let outer = #"{"context":"fixture","state":"oauthTokenInfoSentinelKey:\#(nested)"}"#
        return Data(outer.utf8).base64EncodedString()
    }()

    /// An envelope whose session blob carries only an access token.
    static let ideSessionEnvelopeAccessOnly: String = {
        let blob = "session-blob-begin " + ideAccessToken + " session-blob-end"
        let nested = Data(blob.utf8).base64EncodedString()
        let outer = #"{"context":"fixture","state":"oauthTokenInfoSentinelKey:\#(nested)"}"#
        return Data(outer.utf8).base64EncodedString()
    }()

    // MARK: Quota

    static let quotaJSON = """
    {
      "description": "Sanitized quota summary fixture",
      "groups": [
        {
          "displayName": "Gemini Models",
          "description": "Gemini models",
          "buckets": [
            {
              "bucketId": "gemini-weekly",
              "displayName": "Weekly",
              "description": "Rolling 7 day window",
              "remainingFraction": 0.81,
              "resetTime": "2026-10-14T18:17:35Z",
              "window": "7 days"
            },
            {
              "bucketId": "gemini-5h",
              "displayName": "5 hours",
              "description": "Rolling 5 hour window",
              "remainingFraction": 1.0,
              "resetTime": "2026-10-11T23:17:35Z",
              "window": "5 hours"
            }
          ]
        },
        {
          "displayName": "Claude and GPT models",
          "description": "Claude and GPT models",
          "buckets": [
            {
              "bucketId": "claude-gpt-weekly",
              "displayName": "Weekly",
              "description": "Rolling 7 day window",
              "remainingFraction": 1.0,
              "resetTime": "2026-10-18T18:17:35Z",
              "window": "7 days"
            },
            {
              "bucketId": "claude-gpt-5h",
              "displayName": "5 hours",
              "description": "Rolling 5 hour window",
              "remainingFraction": 1.0,
              "resetTime": "2026-10-11T23:17:35Z",
              "window": "5 hours"
            }
          ]
        }
      ]
    }
    """

    static var quotaSummary: AntigravityQuotaSummary {
        let payload = try! JSONDecoder().decode(
            QuotaSummaryPayload.self,
            from: Data(quotaJSON.utf8)
        )
        return AntigravityQuotaSummary(payload: payload)
    }

    // MARK: Helpers

    static func summary(percentages: [Int]) -> AntigravityQuotaSummary {
        let buckets = percentages.enumerated().map { index, percent in
            QuotaBucket(
                bucketId: "bucket-\(index)",
                displayName: "Bucket \(index)",
                description: nil,
                remainingFraction: Double(percent) / 100,
                resetAt: nil,
                window: nil
            )
        }

        return AntigravityQuotaSummary(
            description: nil,
            groups: [QuotaGroup(displayName: "Test group", description: nil, buckets: buckets)]
        )
    }

    static func summary(grouped: [[Int]]) -> AntigravityQuotaSummary {
        let groups = grouped.enumerated().map { index, percentages in
            QuotaGroup(
                displayName: "Group \(index)",
                description: nil,
                buckets: percentages.enumerated().map { bucketIndex, percent in
                    QuotaBucket(
                        bucketId: "g\(index)-b\(bucketIndex)",
                        displayName: "Bucket \(bucketIndex)",
                        description: nil,
                        remainingFraction: Double(percent) / 100,
                        resetAt: nil,
                        window: nil
                    )
                }
            )
        }

        return AntigravityQuotaSummary(description: nil, groups: groups)
    }
}
