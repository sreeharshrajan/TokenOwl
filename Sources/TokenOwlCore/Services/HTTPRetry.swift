import Foundation

/// Retries only rate limits. Long Retry-After values fail immediately rather
/// than retrying before the server's requested deadline.
enum HTTPRetry {
    static func delay(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval? {
        guard attempt < 2 else { return nil }
        if let retryAfter {
            guard retryAfter.isFinite, retryAfter <= 30 else { return nil }
            return max(0, retryAfter)
        }
        return pow(2, Double(attempt + 1))
    }
    static func data(for request: URLRequest, session: URLSession,
                     sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) async throws -> (Data, URLResponse) {
        for attempt in 0...2 {
            try Task.checkCancellation()
            let result = try await session.data(for: request)
            guard let response = result.1 as? HTTPURLResponse, response.statusCode == 429, attempt < 2 else { return result }
            let hint = AntigravityQuotaClient.retryAfterSeconds(from: response)
            guard let delay = delay(attempt: attempt, retryAfter: hint) else { return result }
            try await sleep(delay)
        }
        throw URLError(.badServerResponse)
    }
}
