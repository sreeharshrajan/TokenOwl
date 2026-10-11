import Foundation

/// Raw credential blob as stored in the macOS Keychain by Antigravity.
///
/// This type is only ever decoded in memory and is never written back,
/// logged, or persisted by TokenOwl.
struct AntigravityCredential: Decodable, Sendable {
    let token: OAuthToken

    struct OAuthToken: Decodable, Sendable {
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
