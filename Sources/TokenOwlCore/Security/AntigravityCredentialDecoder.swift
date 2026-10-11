import Foundation

enum CredentialDecodingError: LocalizedError, Equatable {
    case invalidBase64
    case invalidJSON
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidBase64:
            return "Antigravity credential contains invalid Base64 data."
        case .invalidJSON:
            return "Antigravity credential is not in the expected JSON format."
        case .missingToken:
            return "Antigravity credential does not contain token information."
        }
    }
}

public struct AntigravityCredentialDecoder: Sendable {

    private let prefix = "go-keyring-base64:"

    public init() {}

    func decode(_ rawCredential: String) throws -> AntigravityCredential {
        let data: Data

        if rawCredential.hasPrefix(prefix) {
            let encoded = String(rawCredential.dropFirst(prefix.count))

            guard let decoded = Data(base64Encoded: encoded) else {
                throw CredentialDecodingError.invalidBase64
            }

            data = decoded
        } else {
            guard let rawData = rawCredential.data(using: .utf8) else {
                throw CredentialDecodingError.invalidJSON
            }

            data = rawData
        }

        do {
            return try JSONDecoder().decode(
                AntigravityCredential.self,
                from: data
            )
        } catch let error as DecodingError {
            if case .keyNotFound = error {
                throw CredentialDecodingError.missingToken
            }
            throw CredentialDecodingError.invalidJSON
        } catch {
            throw CredentialDecodingError.invalidJSON
        }
    }
}
