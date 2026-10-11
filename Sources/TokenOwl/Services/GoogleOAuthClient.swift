import Foundation

enum OAuthError: LocalizedError {
  case missingRefreshToken
  case invalidResponse
  case httpError(Int)
  case missingAccessToken

  var errorDescription: String? {
    switch self {
    case .missingRefreshToken:
      return "Refresh token is unavailable."
    case .invalidResponse:
      return "Google OAuth returned an invalid response."
    case .httpError(let status):
      return "Google OAuth refresh failed with HTTP \(status)."
    case .missingAccessToken:
      return "Google OAuth response did not contain an access token."
    }
  }
}

struct GoogleOAuthClient {

  // Public installed-app OAuth credentials used by Antigravity.
  // These are read from the environment or configured at runtime so push protection is satisfied.
  private var clientID: String {
    ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"] ?? ""
  }

  private var clientSecret: String {
    ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_SECRET"] ?? ""
  }

  private let tokenURL =
    URL(string: "https://oauth2.googleapis.com/token")!

  struct RefreshResponse: Decodable {
    let accessToken: String
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case expiresIn = "expires_in"
      case tokenType = "token_type"
    }
  }

  func refreshAccessToken(
    refreshToken: String
  ) async throws -> RefreshResponse {

    var request = URLRequest(url: tokenURL)
    request.httpMethod = "POST"

    request.setValue(
      "application/x-www-form-urlencoded",
      forHTTPHeaderField: "Content-Type"
    )

    let parameters = [
      "client_id": clientID,
      "client_secret": clientSecret,
      "refresh_token": refreshToken,
      "grant_type": "refresh_token",
    ]

    request.httpBody = formEncode(parameters)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20

    let session = URLSession(configuration: configuration)

    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw OAuthError.invalidResponse
    }

    guard (200...299).contains(http.statusCode) else {
      // Deliberately do not print Google's response body:
      // OAuth errors can contain sensitive context.
      throw OAuthError.httpError(http.statusCode)
    }

    let decoded = try JSONDecoder().decode(
      RefreshResponse.self,
      from: data
    )

    guard !decoded.accessToken.isEmpty else {
      throw OAuthError.missingAccessToken
    }

    return decoded
  }

  private func formEncode(
    _ parameters: [String: String]
  ) -> Data {

    let allowed = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-._~")
    )

    let body =
      parameters
      .sorted { $0.key < $1.key }
      .map { key, value in
        let encodedKey =
          key.addingPercentEncoding(
            withAllowedCharacters: allowed
          ) ?? key

        let encodedValue =
          value.addingPercentEncoding(
            withAllowedCharacters: allowed
          ) ?? value

        return "\(encodedKey)=\(encodedValue)"
      }
      .joined(separator: "&")

    return Data(body.utf8)
  }
}
