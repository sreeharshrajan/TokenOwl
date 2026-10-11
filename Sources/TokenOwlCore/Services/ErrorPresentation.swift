import Foundation

/// Turns internal errors into short, safe, user-facing copy.
///
/// Never surfaces raw HTTP bodies, response payloads, tokens, headers, or
/// stack traces into the UI.
public enum ErrorPresentation {

    public static let genericTitle = "Unable to refresh quota"

    public static func message(for error: Error) -> String {
        switch error {

        case let error as CredentialError:
            switch error {
            case .notFound:
                return "Antigravity credential was not found in the Keychain."
            case .keychain:
                return "Keychain access was denied for the Antigravity credential."
            case .invalidEncoding:
                return "The stored Antigravity credential could not be read."
            }

        case let error as CredentialDecodingError:
            switch error {
            case .invalidBase64, .invalidJSON, .missingToken:
                return "The stored Antigravity credential could not be read."
            }

        case let error as OAuthError:
            switch error {
            case .missingClientConfiguration:
                return "Open or reinstall Antigravity IDE so TokenOwl can read its Google sign-in configuration."
            case .missingRefreshToken:
                return "No refresh token is available for this credential."
            case .missingAccessToken, .invalidResponse:
                return "Google authentication needs attention."
            case .credentialExpired:
                return "The IDE session token expired and could not be refreshed."
            case .httpError(let status):
                return (status == 400 || status == 401 || status == 403)
                    ? "Google authentication needs attention."
                    : "Google authentication could not be completed."
            }

        case let error as IDETokenStateError:
            switch error {
            case .databaseNotFound:
                return "The Antigravity IDE session was not found."
            case .databaseUnreadable:
                return "The Antigravity IDE session could not be read."
            case .rowNotFound:
                return "No session token was found in the Antigravity IDE state."
            case .emptyToken:
                return "The Antigravity IDE session token is empty."
            case .tokenNotRecognized:
                return "The Antigravity IDE session token could not be read."
            }

        case let error as QuotaClientError:
            switch error {
            case .httpError(401):
                return "Google authentication needs attention."
            case .httpError(429):
                return "Google is rate-limiting quota requests. Try again shortly."
            case .rateLimited:
                return "Google is rate-limiting quota requests. Try again shortly."
            case .httpError:
                return "Google could not serve the quota request."
            case .invalidJSON, .decodingFailure:
                return "The quota response could not be read."
            case .invalidResponse, .responseTooLarge:
                return "Google returned an unexpected quota response."
            }

        case let error as CodexError:
            return error.localizedDescription

        case is URLError:
            return "Network unavailable. Check your connection and try again."

        default:
            // Deliberately does not forward arbitrary `localizedDescription`
            // values: unknown errors may carry response bodies or URLs.
            return "Something went wrong while refreshing the quota."
        }
    }
}
