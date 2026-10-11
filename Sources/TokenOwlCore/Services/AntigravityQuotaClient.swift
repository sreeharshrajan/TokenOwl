import Foundation

enum QuotaClientError: LocalizedError, Equatable {
    case invalidResponse
    case httpError(Int)
    /// HTTP 429 with, when Google sent one, the `Retry-After` hint in
    /// seconds. Rate limits are not credential failures: they never hand
    /// the request to a different credential source.
    case rateLimited(retryAfter: TimeInterval?)
    case responseTooLarge
    case invalidJSON
    case decodingFailure

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Antigravity quota API returned an invalid response."
        case .httpError(let status):
            return "Antigravity quota request failed with HTTP \(status)."
        case .rateLimited:
            return "Antigravity quota API is rate-limiting requests (HTTP 429)."
        case .responseTooLarge:
            return "Antigravity quota response exceeded the safety limit."
        case .invalidJSON:
            return "Antigravity quota response was not valid JSON."
        case .decodingFailure:
            return "Antigravity quota response could not be read."
        }
    }
}

struct QuotaInspectionResult {
    let statusCode: Int
    let byteCount: Int
    let topLevelKeys: [String]
    let structure: String
}

/// The quota/account capability `AntigravityService` depends on, so the
/// service can be tested without a network.
public protocol AntigravityQuotaFetching: Sendable {
    func fetchQuota(accessToken: String) async throws -> AntigravityQuotaSummary
    func fetchAccount(accessToken: String) async throws -> AntigravityAccount
}

public struct AntigravityQuotaClient: AntigravityQuotaFetching {

    public init() {}


    private let quotaURL = URL(
        string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
    )!

    private let maximumResponseSize = 4 * 1024 * 1024

    func inspectQuota(
        accessToken: String
    ) async throws -> QuotaInspectionResult {

        var request = URLRequest(url: quotaURL)
        request.httpMethod = "POST"

        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.setValue(
            "antigravity/1.11.3 macOS/arm64",
            forHTTPHeaderField: "User-Agent"
        )

        request.httpBody = Data("{}".utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20

        let session = URLSession(configuration: configuration)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw QuotaClientError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw QuotaClientError.httpError(http.statusCode)
        }

        guard data.count <= maximumResponseSize else {
            throw QuotaClientError.responseTooLarge
        }

        let object: Any

        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw QuotaClientError.invalidJSON
        }

        let keys: [String]

        if let dictionary = object as? [String: Any] {
            keys = dictionary.keys.sorted()
        } else {
            keys = []
        }

        return QuotaInspectionResult(
            statusCode: http.statusCode,
            byteCount: data.count,
            topLevelKeys: keys,
            structure: describeStructure(object)
        )
    }

    private func describeStructure(
        _ value: Any,
        depth: Int = 0
    ) -> String {

        // Prevent unexpectedly deep API responses from producing
        // enormous diagnostic output.
        guard depth < 8 else {
            return "…"
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.keys
                .sorted()
                .map { key in
                    let child = dictionary[key]!

                    return "\(key): \(describeStructure(child, depth: depth + 1))"
                }
                .joined(separator: "\n")
        }

        if let array = value as? [Any] {
            guard let first = array.first else {
                return "[empty]"
            }

            return "[\(array.count) items]\n"
                + describeStructure(first, depth: depth + 1)
        }

        if value is String {
            return "<string>"
        }

        if value is NSNumber {
            return "<number>"
        }

        if value is NSNull {
            return "<null>"
        }

        return "<unknown>"
    }

    public func fetchQuota(
        accessToken: String
    ) async throws -> AntigravityQuotaSummary {

        var request = URLRequest(url: quotaURL)
        request.httpMethod = "POST"

        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.setValue(
            "antigravity/1.11.3 macOS/arm64",
            forHTTPHeaderField: "User-Agent"
        )

        request.httpBody = Data("{}".utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20

        let session = URLSession(configuration: configuration)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw QuotaClientError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw QuotaClientError.rateLimited(
                    retryAfter: Self.retryAfterSeconds(from: http)
                )
            }
            throw QuotaClientError.httpError(http.statusCode)
        }

        guard data.count <= maximumResponseSize else {
            throw QuotaClientError.responseTooLarge
        }

        // Wire format is converted into the normalized domain model here, so
        // callers only ever see `Date` reset times, never raw API strings.
        return try Self.summary(from: data)
    }

    /// Parses a `Retry-After` header: either delta-seconds (`"30"`) or an
    /// HTTP-date (`"Wed, 21 Oct 2026 07:28:00 GMT"`), as sent by Google.
    static func retryAfterSeconds(
        from response: HTTPURLResponse,
        now: Date = Date()
    ) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces),
              !raw.isEmpty
        else { return nil }

        if let seconds = TimeInterval(raw), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        if let date = formatter.date(from: raw) {
            return max(0, date.timeIntervalSince(now))
        }

        return nil
    }

    /// Decodes and normalizes a quota response body.
    static func summary(from data: Data) throws -> AntigravityQuotaSummary {
        let payload: QuotaSummaryPayload

        do {
            payload = try JSONDecoder().decode(
                QuotaSummaryPayload.self,
                from: data
            )
        } catch DecodingError.dataCorrupted {
            throw QuotaClientError.invalidJSON
        } catch {
            throw QuotaClientError.decodingFailure
        }

        return AntigravityQuotaSummary(payload: payload)
    }

    public func fetchAccount(
        accessToken: String
    ) async throws -> AntigravityAccount {
        let session = URLSession(configuration: .ephemeral)

        // The email is the load-bearing identity field: if it cannot be
        // fetched the whole call throws, so the service can surface an
        // identity failure instead of silently displaying no account.
        async let email = Self.emailAddress(accessToken: accessToken, session: session)

        // Tier details are best-effort: a failure degrades the plan label
        // but is logged rather than swallowed without a trace.
        var tierID: String?
        var tierName: String?
        var upgradePrompt: String?
        do {
            let tier = try await Self.tierDetails(accessToken: accessToken, session: session)
            tierID = tier.id
            tierName = tier.name
            upgradePrompt = tier.upgrade
        } catch {
            RedactedLogger.log("Tier lookup failed (\(type(of: error)))")
        }

        return AntigravityAccount(
            email: try await email,
            tierID: tierID,
            tierName: tierName,
            upgradePrompt: upgradePrompt
        )
    }

    private static func tierDetails(
        accessToken: String,
        session: URLSession
    ) async throws -> (id: String?, name: String?, upgrade: String?) {
        let url = URL(
            string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
        )!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity/1.11.3 macOS/arm64", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw QuotaClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw QuotaClientError.rateLimited(retryAfter: retryAfterSeconds(from: http))
            }
            throw QuotaClientError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaClientError.invalidJSON
        }

        var id: String?
        var name: String?

        if let currentTier = json["currentTier"] as? [String: Any] {
            id = currentTier["id"] as? String
            name = currentTier["name"] as? String
        }
        if let userTier = json["userTier"] as? [String: Any] {
            if id == nil { id = userTier["id"] as? String }
            if name == nil { name = userTier["name"] as? String }
        }

        return (id, name, json["upgradeSubscriptionText"] as? String)
    }

    private static func emailAddress(
        accessToken: String,
        session: URLSession
    ) async throws -> String {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else {
            throw QuotaClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw QuotaClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw QuotaClientError.rateLimited(retryAfter: retryAfterSeconds(from: http))
            }
            throw QuotaClientError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String,
              !email.isEmpty
        else {
            throw QuotaClientError.invalidJSON
        }

        return email
    }
}