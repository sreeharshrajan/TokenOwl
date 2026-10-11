import Foundation

public enum OAuthError: LocalizedError, Equatable {
  case missingClientConfiguration
  case missingRefreshToken
  case invalidResponse
  case httpError(Int)
  case missingAccessToken

  public var errorDescription: String? {
    switch self {
    case .missingClientConfiguration:
      return "Set GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET before refreshing Google authentication."
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

/// The single capability `OAuthTokenManager` needs. Conforming
/// `GoogleOAuthClient` keeps the token manager testable without a network.
public protocol AccessTokenRefreshing: Sendable {
    func refreshAccessToken(refreshToken: String) async throws -> GoogleOAuthClient.RefreshResponse
}

public struct GoogleOAuthClient: AccessTokenRefreshing {

  public init() {}

  // OAuth client credentials must be provided through the environment.
  private var clientID: String {
    if let env = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"], !env.isEmpty {
      return env
    }
    return ""
  }

  private var clientSecret: String {
    if let env = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_SECRET"], !env.isEmpty {
      return env
    }
    return ""
  }

  private let tokenURL =
    URL(string: "https://oauth2.googleapis.com/token")!

  public struct RefreshResponse: Decodable, Sendable {
    public let accessToken: String
    public let expiresIn: Int?
    public let tokenType: String?

    public init(accessToken: String, expiresIn: Int?, tokenType: String?) {
      self.accessToken = accessToken
      self.expiresIn = expiresIn
      self.tokenType = tokenType
    }

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case expiresIn = "expires_in"
      case tokenType = "token_type"
    }
  }

  public func refreshAccessToken(
    refreshToken: String
  ) async throws -> RefreshResponse {

    guard !clientID.isEmpty, !clientSecret.isEmpty else {
      throw OAuthError.missingClientConfiguration
    }

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
