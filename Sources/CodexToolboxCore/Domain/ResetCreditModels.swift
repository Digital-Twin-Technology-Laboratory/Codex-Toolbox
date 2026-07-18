import Foundation

public struct AccountQuotaWindow: Codable, Hashable, Identifiable, Sendable {
    public let durationMinutes: Int
    public let usedPercent: Double
    public let resetsAt: Date

    public var id: String {
        "quota-window-\(durationMinutes)-\(Int(resetsAt.timeIntervalSince1970))"
    }

    public var displayName: String {
        switch durationMinutes {
        case 300:
            "5小时"
        case 10_080:
            "周"
        case let minutes where minutes.isMultiple(of: 1_440):
            "\(minutes / 1_440)天"
        case let minutes where minutes.isMultiple(of: 60):
            "\(minutes / 60)小时"
        default:
            "\(durationMinutes)分钟"
        }
    }

    public init(durationMinutes: Int, usedPercent: Double, resetsAt: Date) {
        self.durationMinutes = max(1, durationMinutes)
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }
}

public struct ResetCreditSummary: Codable, Hashable, Identifiable, Sendable {
    public let sequence: Int
    public let status: String
    public let grantedAt: Date?
    public let expiresAt: Date?

    public var id: String { "reset-credit-\(sequence)" }

    public var isAvailable: Bool { status.caseInsensitiveCompare("available") == .orderedSame }

    public init(
        sequence: Int,
        status: String,
        grantedAt: Date?,
        expiresAt: Date?
    ) {
        self.sequence = sequence
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
    }
}

public struct ResetCreditsSnapshot: Codable, Hashable, Sendable {
    public let availableCount: Int
    public let credits: [ResetCreditSummary]
    public let quotaWindows: [AccountQuotaWindow]
    public let fetchedAt: Date

    public init(
        availableCount: Int,
        credits: [ResetCreditSummary],
        quotaWindows: [AccountQuotaWindow] = [],
        fetchedAt: Date
    ) {
        self.availableCount = max(0, availableCount)
        self.credits = credits.sorted {
            if $0.isAvailable != $1.isAvailable { return $0.isAvailable }
            switch ($0.expiresAt, $1.expiresAt) {
            case let (lhs?, rhs?) where lhs != rhs: return lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.id < $1.id
            }
        }
        self.quotaWindows = quotaWindows.sorted {
            if $0.durationMinutes != $1.durationMinutes {
                return $0.durationMinutes < $1.durationMinutes
            }
            return $0.resetsAt < $1.resetsAt
        }
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey {
        case availableCount
        case credits
        case quotaWindows
        case fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            availableCount: try container.decode(Int.self, forKey: .availableCount),
            credits: try container.decode([ResetCreditSummary].self, forKey: .credits),
            quotaWindows: try container.decodeIfPresent([AccountQuotaWindow].self, forKey: .quotaWindows) ?? [],
            fetchedAt: try container.decode(Date.self, forKey: .fetchedAt)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(availableCount, forKey: .availableCount)
        try container.encode(credits, forKey: .credits)
        try container.encode(quotaWindows, forKey: .quotaWindows)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }

    public var availableCredits: [ResetCreditSummary] {
        credits.filter(\.isAvailable)
    }

    public var nearestExpiration: Date? {
        availableCredits.compactMap(\.expiresAt).min()
    }
}

public protocol AccountRateLimitsReading: Sendable {
    func readResetCredits() async throws -> ResetCreditsSnapshot
}
