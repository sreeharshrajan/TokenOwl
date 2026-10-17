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


    /// Match the IDE: consumer tiers use the daily service, GCP terms use
    /// the standard service. Both may return 200 with different quota values.
    static func quotaURL(accountDetails: [String: Any]) -> URL {
        let tier = accountDetails["paidTier"] as? [String: Any]
        let usesGCPTerms = tier?["usesGcpTos"] as? Bool ?? false
        let host = usesGCPTerms ? "cloudcode-pa.googleapis.com" : "daily-cloudcode-pa.googleapis.com"
        return URL(string: "https://\(host)/v1internal:retrieveUserQuotaSummary")!
    }

    private func quotaURL(accessToken: String) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let details = try await Self.accountDetails(accessToken: accessToken, session: session)
        return Self.quotaURL(accountDetails: details)
    }

    /// The service gates available model groups on the client version.
    static var userAgent: String {
        var version = "2.5.5"
        if case .installed(let path) = EditorDiscoveryService().discoverInstallation(of: .antigravity),
           let data = FileManager.default.contents(atPath: path + "/Contents/Resources/app/product.json"),
           let product = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let installedVersion = product["ideVersion"] as? String,
           !installedVersion.isEmpty {
            version = installedVersion
        }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x64"
        #endif
        return "antigravity/\(version) darwin/\(architecture)"
    }

    private let maximumResponseSize = 4 * 1024 * 1024

    func inspectQuota(
        accessToken: String
    ) async throws -> QuotaInspectionResult {

        var request = URLRequest(url: try await quotaURL(accessToken: accessToken))
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
            Self.userAgent,
            forHTTPHeaderField: "User-Agent"
        )

        request.httpBody = Data("{}".utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await HTTPRetry.data(for: request, session: session)

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

        var request = URLRequest(url: try await quotaURL(accessToken: accessToken))
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
            Self.userAgent,
            forHTTPHeaderField: "User-Agent"
        )

        request.httpBody = Data("{}".utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

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
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

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
        let json = try await accountDetails(accessToken: accessToken, session: session)
        let tier = (json["paidTier"] as? [String: Any])
            ?? (json["currentTier"] as? [String: Any])
            ?? (json["userTier"] as? [String: Any])
        return (tier?["id"] as? String, tier?["name"] as? String,
                json["upgradeSubscriptionText"] as? String)
    }

    private static func accountDetails(
        accessToken: String,
        session: URLSession
    ) async throws -> [String: Any] {
        let url = URL(
            string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
        )!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await HTTPRetry.data(for: request, session: session)

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

        return json
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

        let (data, response) = try await HTTPRetry.data(for: request, session: session)

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
