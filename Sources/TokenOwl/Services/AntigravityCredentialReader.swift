import Foundation
import Security

enum CredentialError: LocalizedError {
  case notFound
  case keychain(OSStatus)
  case invalidEncoding

  var errorDescription: String? {
    switch self {
    case .notFound:
      return "Antigravity credentials were not found in Keychain."

    case .keychain(let status):
      return "Keychain access failed with status \(status)."

    case .invalidEncoding:
      return "Antigravity credential contains invalid UTF-8 data."
    }
  }
}

struct AntigravityCredentialReader {

  private let service = "gemini"
  private let account = "antigravity"

  func readRawCredential() throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?

    let status = SecItemCopyMatching(
      query as CFDictionary,
      &result
    )

    guard status != errSecItemNotFound else {
      throw CredentialError.notFound
    }

    guard status == errSecSuccess else {
      throw CredentialError.keychain(status)
    }

    guard
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      throw CredentialError.invalidEncoding
    }

    return value
  }
}
