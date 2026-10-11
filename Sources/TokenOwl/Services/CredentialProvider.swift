import Foundation

enum CredentialSource: String, Sendable {
    case cliKeychain = "Keychain (CLI / Antigravity)"
    case environment = "Environment Override"
    case ide = "Antigravity IDE"
}

struct ResolvedCredential: Sendable {
    let source: CredentialSource
    let refreshToken: String
}

protocol AntigravityCredentialProvider: Sendable {
    var source: CredentialSource { get }
    func resolveCredential() async throws -> ResolvedCredential
}
