import Foundation
import Testing
@testable import TokenOwlCore

struct RedactedLoggerTests {

    @Test func redactsAuthorizationHeaders() {
        let input = "Authorization: Bearer ya29.a0AfB_byDemoToken"
        let output = RedactedLogger.redact(input)

        #expect(!output.contains("ya29.a0AfB_byDemoToken"))
        #expect(output.lowercased().contains("authorization"))
    }

    @Test func redactsFormEncodedTokens() {
        let input = "client_id=demo&refresh_token=super-secret&grant_type=refresh_token"
        let output = RedactedLogger.redact(input)

        #expect(!output.contains("super-secret"))
        #expect(output.contains("grant_type=refresh_token"))
    }

    @Test func redactsJSONTokenFields() {
        let input = #"{"access_token":"json-secret","expires_in":3600}"#
        let output = RedactedLogger.redact(input)

        #expect(!output.contains("json-secret"))
        #expect(output.contains("expires_in"))
    }

    @Test func redactsGoogleAccessTokenPrefixes() {
        let input = "token is ya29.a0AfH something else"
        let output = RedactedLogger.redact(input)

        #expect(!output.contains("a0AfH"))
    }

    @Test func leavesOrdinaryMessagesIntact() {
        let input = "Quota refresh succeeded in 412 ms (source: Keychain credential)"

        #expect(RedactedLogger.redact(input) == input)
    }

    @Test func loggingIsOptIn() {
        #expect(RedactedLogger.isEnabled == (ProcessInfo.processInfo.environment["TOKENOWL_DEBUG"] == "1"))
    }
}

struct ErrorPresentationTests {

    @Test func mapsAuthenticationFailures() {
        #expect(
            ErrorPresentation.message(for: OAuthError.httpError(401))
                == "Google authentication needs attention."
        )
        #expect(
            ErrorPresentation.message(for: QuotaClientError.httpError(401))
                == "Google authentication needs attention."
        )
        #expect(
            ErrorPresentation.message(for: OAuthError.missingRefreshToken)
                == "No refresh token is available for this credential."
        )
    }

    @Test func mapsRateLimitAndNetworkFailures() {
        #expect(
            ErrorPresentation.message(for: QuotaClientError.httpError(429))
                == "Google is rate-limiting quota requests. Try again shortly."
        )
        #expect(
            ErrorPresentation.message(for: URLError(.notConnectedToInternet))
                == "Network unavailable. Check your connection and try again."
        )
    }

    @Test func mapsCredentialFailures() {
        #expect(
            ErrorPresentation.message(for: CredentialError.notFound)
                == "Antigravity credential was not found in the Keychain."
        )
        #expect(
            ErrorPresentation.message(for: CredentialDecodingError.invalidJSON)
                == "The stored Antigravity credential could not be read."
        )
    }

    @Test func neverSurfacesUnknownErrorPayloads() {
        struct SneakyError: LocalizedError {
            var errorDescription: String? {
                #"{"access_token":"leaked-secret"}"#
            }
        }

        let message = ErrorPresentation.message(for: SneakyError())

        #expect(!message.contains("leaked-secret"))
        #expect(!message.contains("{"))
    }

    @Test func neverSurfacesHTTPStatusBodies() {
        let message = ErrorPresentation.message(for: QuotaClientError.httpError(500))

        #expect(!message.contains("{"))
        #expect(message == "Google could not serve the quota request.")
    }
}
