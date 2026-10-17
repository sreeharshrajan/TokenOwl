import Foundation

// MARK: - Wire format
//
// Kept separate from the domain model so that API quirks (strings where we
// want `Date`, raw fractions where we want percentages) never leak into the
// application layer.

struct QuotaSummaryPayload: Decodable, Sendable {
    let description: String?
    let groups: [QuotaGroupPayload]
}

struct QuotaGroupPayload: Decodable, Sendable {
    let displayName: String
    let description: String?
    let buckets: [QuotaBucketPayload]
}

struct QuotaBucketPayload: Decodable, Sendable {
    let bucketId: String
    let displayName: String
    let description: String?
    let remainingFraction: Double
    let resetTime: String?
    let window: String?
    let disabled: Bool?
}

// MARK: - Domain

public struct AntigravityQuotaSummary: Sendable {
    public let description: String?
    public let groups: [QuotaGroup]

    public init(description: String?, groups: [QuotaGroup]) {
        self.description = description
        self.groups = groups
    }

    init(payload: QuotaSummaryPayload) {
        self.init(
            description: payload.description,
            groups: payload.groups.map(QuotaGroup.init(payload:))
        )
    }
}

public struct QuotaGroup: Sendable {
    public let displayName: String
    public let description: String?
    public let buckets: [QuotaBucket]

    public init(displayName: String, description: String?, buckets: [QuotaBucket]) {
        self.displayName = displayName
        self.description = description
        self.buckets = buckets
    }

    init(payload: QuotaGroupPayload) {
        self.init(
            displayName: payload.displayName,
            description: payload.description,
            buckets: payload.buckets.map(QuotaBucket.init(payload:))
        )
    }
}

public struct QuotaBucket: Sendable {
    public let bucketId: String
    public let displayName: String
    public let description: String?
    public let remainingFraction: Double
    /// Normalized from the API's `resetTime` string. `nil` when the API sent
    /// something we could not parse.
    public let resetAt: Date?
    public let window: String?
    /// Disabled windows do not constrain usage and must not advertise capacity.
    public let disabled: Bool

    public var remainingPercent: Int {
        Int((remainingFraction * 100).rounded())
    }

    /// Never used for arithmetic across buckets, only for presentation.
    public var severity: QuotaSeverity {
        QuotaSeverity(percent: remainingPercent)
    }

    public init(
        bucketId: String,
        displayName: String,
        description: String?,
        remainingFraction: Double,
        resetAt: Date?,
        window: String?,
        disabled: Bool = false
    ) {
        self.bucketId = bucketId
        self.displayName = displayName
        self.description = description
        self.remainingFraction = remainingFraction
        self.resetAt = resetAt
        self.window = window
        self.disabled = disabled
    }

    init(payload: QuotaBucketPayload) {
        self.init(
            bucketId: payload.bucketId,
            displayName: payload.displayName,
            description: payload.description,
            remainingFraction: payload.remainingFraction,
            resetAt: payload.resetTime.flatMap(DateParser.parse),
            window: payload.window,
            disabled: payload.disabled ?? false
        )
    }
}

// MARK: - Domain helpers

extension AntigravityQuotaSummary {
    /// Enabled buckets that currently constrain usage.
    public var allBuckets: [QuotaBucket] {
        groups.flatMap(\.buckets).filter { !$0.disabled }
    }

    /// The single tightest bucket. Buckets are never averaged or combined:
    /// a weekly limit and a 5-hour limit are independent constraints.
    public var mostConstrainedBucket: QuotaBucket? {
        allBuckets.min { lhs, rhs in
            if lhs.remainingPercent != rhs.remainingPercent {
                return lhs.remainingPercent < rhs.remainingPercent
            }
            return lhs.bucketId < rhs.bucketId
        }
    }

    /// The number the menu bar shows: the lowest remaining percentage among
    /// active quota buckets. `nil` when there is nothing to report.
    public var mostConstrainedPercent: Int? {
        mostConstrainedBucket?.remainingPercent
    }
}

/// Presentation-only severity of a single bucket.
///
/// `> 50%` normal, `20...50%` warning, `1...19%` critical, `0%` exhausted.
public enum QuotaSeverity: Sendable, Equatable {
    case normal
    case warning
    case critical
    case exhausted

    public init(percent: Int) {
        switch percent {
        case ..<1:
            self = .exhausted
        case 1..<20:
            self = .critical
        case 20...50:
            self = .warning
        default:
            self = .normal
        }
    }
}
