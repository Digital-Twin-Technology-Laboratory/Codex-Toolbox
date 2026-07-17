import Foundation

public struct ResetCreditSummary: Codable, Hashable, Identifiable, Sendable {
    public let resetType: String?
    public let status: String
    public let grantedAt: Date?
    public let expiresAt: Date?
    public let title: String?
    public let description: String?

    public var id: String {
        [resetType, status, grantedAt?.ISO8601Format(), expiresAt?.ISO8601Format(), title]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    public var isAvailable: Bool { status.caseInsensitiveCompare("available") == .orderedSame }

    public init(
        resetType: String?,
        status: String,
        grantedAt: Date?,
        expiresAt: Date?,
        title: String?,
        description: String?
    ) {
        self.resetType = resetType
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.title = title
        self.description = description
    }
}

public struct ResetCreditsSnapshot: Codable, Hashable, Sendable {
    public let availableCount: Int
    public let credits: [ResetCreditSummary]
    public let fetchedAt: Date

    public init(availableCount: Int, credits: [ResetCreditSummary], fetchedAt: Date) {
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
        self.fetchedAt = fetchedAt
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
