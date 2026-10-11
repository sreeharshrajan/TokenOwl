import Foundation

// MARK: - Wire format

public struct CodexRateLimitResponse: Decodable, Sendable {
    let rateLimitsByLimitId: [String: CodexRateLimitBucket]?
    let rateLimitsByName: [String: CodexRateLimitBucket]?

    enum CodingKeys: String, CodingKey {
        case rateLimitsByLimitId = "rateLimitsByLimitId"
        case rateLimitsByName = "rate_limits_by_name"
        case rateLimits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? container.decode([String: CodexNestedLimit].self, forKey: .rateLimitsByLimitId), nested.values.contains(where: { $0.primary != nil || $0.secondary != nil }) {
            rateLimitsByLimitId = Self.flatten(nested)
        } else if let single = try? container.decode(CodexNestedLimit.self, forKey: .rateLimits) {
            rateLimitsByLimitId = Self.flatten(["codex": single])
        } else {
            rateLimitsByLimitId = try container.decodeIfPresent([String: CodexRateLimitBucket].self, forKey: .rateLimitsByLimitId)
        }
        rateLimitsByName = try container.decodeIfPresent(
            [String: CodexRateLimitBucket].self,
            forKey: .rateLimitsByName
        )
    }

    private static func flatten(_ limits: [String: CodexNestedLimit]) -> [String: CodexRateLimitBucket] {
        var result: [String: CodexRateLimitBucket] = [:]
        for (id, limit) in limits {
            if let primary = limit.primary { result[id + ".primary"] = primary }
            if let secondary = limit.secondary { result[id + ".secondary"] = secondary }
        }
        return result
    }

    init(rateLimitsByLimitId: [String: CodexRateLimitBucket]?, rateLimitsByName: [String: CodexRateLimitBucket]?) {
        self.rateLimitsByLimitId = rateLimitsByLimitId
        self.rateLimitsByName = rateLimitsByName
    }
}

private struct CodexNestedLimit: Decodable {
    let primary: CodexRateLimitBucket?
    let secondary: CodexRateLimitBucket?
}

public struct CodexRateLimitBucket: Decodable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMins
        case resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = max(0, min(100, try container.decode(Double.self, forKey: .usedPercent)))
        windowDurationMins = try container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
        if let timestamp = try? container.decode(Double.self, forKey: .resetsAt) {
            resetsAt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
        } else {
            resetsAt = try container.decodeIfPresent(String.self, forKey: .resetsAt)
        }
    }

    init(usedPercent: Double, windowDurationMins: Int?, resetsAt: String?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

// MARK: - Domain

public struct CodexQuotaWindow: Sendable, Equatable {
    public let limitId: String
    public let label: String
    public let usedPercent: Int
    public let windowDurationMins: Int?
    public let resetsAt: Date?

    public var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }

    public var severity: QuotaSeverity {
        QuotaSeverity(percent: remainingPercent)
    }

    public init(limitId: String, label: String, usedPercent: Int, windowDurationMins: Int?, resetsAt: Date?) {
        self.limitId = limitId
        self.label = label
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct CodexQuotaSummary: Sendable {
    public let windows: [CodexQuotaWindow]
    public let planType: String?

    public init(windows: [CodexQuotaWindow], planType: String?) {
        self.windows = windows
        self.planType = planType
    }

    public var primaryWindow: CodexQuotaWindow? {
        windows.first
    }

    public var mostConstrainedWindow: CodexQuotaWindow? {
        windows.min { lhs, rhs in
            if lhs.remainingPercent != rhs.remainingPercent {
                return lhs.remainingPercent < rhs.remainingPercent
            }
            return lhs.limitId < rhs.limitId
        }
    }

    public var mostConstrainedPercent: Int? {
        mostConstrainedWindow?.remainingPercent
    }
}

// MARK: - Decoding

extension CodexQuotaSummary {
    public init(response: CodexRateLimitResponse) {
        var windows: [CodexQuotaWindow] = []

        if let byId = response.rateLimitsByLimitId {
            for (limitId, bucket) in byId {
                windows.append(
                    CodexQuotaWindow(
                        limitId: limitId,
                        label: Self.label(forLimitId: limitId, durationMins: bucket.windowDurationMins),
                        usedPercent: Int(bucket.usedPercent.rounded()),
                        windowDurationMins: bucket.windowDurationMins,
                        resetsAt: bucket.resetsAt.flatMap(DateParser.parse)
                    )
                )
            }
        } else if let byName = response.rateLimitsByName {
            for (name, bucket) in byName {
                windows.append(
                    CodexQuotaWindow(
                        limitId: name,
                        label: Self.label(forLimitId: name, durationMins: bucket.windowDurationMins),
                        usedPercent: Int(bucket.usedPercent.rounded()),
                        windowDurationMins: bucket.windowDurationMins,
                        resetsAt: bucket.resetsAt.flatMap(DateParser.parse)
                    )
                )
            }
        }

        windows.sort { lhs, rhs in
            let lhsIsPrimary = lhs.windowDurationMins == 300 || lhs.limitId.lowercased().contains("5")
            let rhsIsPrimary = rhs.windowDurationMins == 300 || rhs.limitId.lowercased().contains("5")
            if lhsIsPrimary != rhsIsPrimary {
                return lhsIsPrimary
            }
            return lhs.limitId < rhs.limitId
        }

        self.init(windows: windows, planType: nil)
    }

    static func label(forLimitId limitId: String, durationMins: Int?) -> String {
        if let mins = durationMins {
            if mins == 300 { return "5 hours" }
            if mins == 10080 { return "Weekly" }
            if mins < 60 { return "\(mins)m" }
            let hours = mins / 60
            if hours < 24 { return "\(hours)h" }
            let days = hours / 24
            return "\(days)d"
        }
        if limitId.lowercased().contains("5h") || limitId.lowercased().contains("five") {
            return "5 hours"
        }
        if limitId.lowercased().contains("week") || limitId.lowercased().contains("7d") {
            return "Weekly"
        }
        return limitId
    }
}
