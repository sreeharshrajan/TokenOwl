import Foundation

struct AntigravityCredential: Decodable {
  let token: OAuthToken

  struct OAuthToken: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiry: String?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case expiry
    }
  }
}

struct AntigravityQuotaSummary: Decodable {
  let description: String?
  let groups: [QuotaGroup]
}

struct QuotaGroup: Decodable {
  let displayName: String
  let description: String?
  let buckets: [QuotaBucket]
}

struct QuotaBucket: Decodable {
  let bucketId: String
  let displayName: String
  let description: String?
  let remainingFraction: Double
  let resetTime: String?
  let window: String?

  var remainingPercent: Int {
    Int((remainingFraction * 100).rounded())
  }

  enum CodingKeys: String, CodingKey {
    case bucketId
    case displayName
    case description
    case remainingFraction
    case resetTime
    case window
  }
}

struct AntigravityAccount {
  let email: String?
  let tierID: String?
  let tierName: String?
  let upgradePrompt: String?
}

struct AntigravitySnapshot {
  let account: AntigravityAccount
  let quota: AntigravityQuotaSummary
  let fetchedAt: Date
}
