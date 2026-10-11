import Foundation

public enum CodexError: Error, Equatable, LocalizedError {
    case codexNotInstalled
    case unsupportedVersion(found: String)
    case accountChanged
    case notLoggedIn
    case apiKeyAuthUnsupported
    case timeout
    case processFailed(exitCode: Int32)
    case malformedResponse
    case rateLimitsUnavailable
    case binaryResolutionFailed

    public var errorDescription: String? {
        switch self {
        case .codexNotInstalled:
            return "Codex CLI was not found on this Mac."
        case .unsupportedVersion(let found):
            return "Codex version \(found) is not supported."
        case .accountChanged:
            return "Codex account changed. Restart TokenOwl to monitor the newly signed-in account."
        case .notLoggedIn:
            return "Codex is not logged in. Run `codex login`, then refresh."
        case .apiKeyAuthUnsupported:
            return "API-key authentication is not supported. Please use ChatGPT login."
        case .timeout:
            return "Codex did not respond in time."
        case .processFailed(let exitCode):
            return "Codex process exited with code \(exitCode)."
        case .malformedResponse:
            return "Codex returned an unexpected response."
        case .rateLimitsUnavailable:
            return "Codex did not report any rate limits."
        case .binaryResolutionFailed:
            return "Could not locate the Codex binary."
        }
    }
}
