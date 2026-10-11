import Foundation

enum QuotaClientError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case responseTooLarge
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Antigravity quota API returned an invalid response."
        case .httpError(let status):
            return "Antigravity quota request failed with HTTP \(status)."
        case .responseTooLarge:
            return "Antigravity quota response exceeded the safety limit."
        case .invalidJSON:
            return "Antigravity quota response was not valid JSON."
        }
    }
}

struct QuotaInspectionResult {
    let statusCode: Int
    let byteCount: Int
    let topLevelKeys: [String]
    let structure: String
}

struct AntigravityQuotaClient {

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

    func fetchQuota(
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
            throw QuotaClientError.httpError(http.statusCode)
        }

        guard data.count <= maximumResponseSize else {
            throw QuotaClientError.responseTooLarge
        }

        do {
            return try JSONDecoder().decode(
                AntigravityQuotaSummary.self,
                from: data
            )
        } catch {
            throw QuotaClientError.invalidJSON
        }
    }

    func fetchAccount(
        accessToken: String
    ) async -> AntigravityAccount {
        let loadCodeAssistURL = URL(
            string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
        )!

        var request = URLRequest(url: loadCodeAssistURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity/1.11.3 macOS/arm64", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("{}".utf8)

        var email: String?
        var tierID: String?
        var tierName: String?
        var upgradePrompt: String?

        // Fetch Tier details
        let session = URLSession(configuration: .ephemeral)
        if let (data, response) = try? await session.data(for: request),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let currentTier = json["currentTier"] as? [String: Any] {
                tierID = currentTier["id"] as? String
                tierName = currentTier["name"] as? String
            }
            if let userTier = json["userTier"] as? [String: Any] {
                if tierID == nil { tierID = userTier["id"] as? String }
                if tierName == nil { tierName = userTier["name"] as? String }
            }
            upgradePrompt = json["upgradeSubscriptionText"] as? String
        }

        // Fetch User Identity (Email)
        if let userinfoURL = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") {
            var userinfoReq = URLRequest(url: userinfoURL)
            userinfoReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            if let (userData, userResponse) = try? await session.data(for: userinfoReq),
               let userHttp = userResponse as? HTTPURLResponse, (200...299).contains(userHttp.statusCode),
               let userJson = try? JSONSerialization.jsonObject(with: userData) as? [String: Any] {
                email = userJson["email"] as? String
            }
        }

        return AntigravityAccount(
            email: email,
            tierID: tierID,
            tierName: tierName,
            upgradePrompt: upgradePrompt
        )
    }
}