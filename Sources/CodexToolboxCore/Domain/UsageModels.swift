import Foundation

public struct DailyTaskUsage: Codable, Hashable, Identifiable, Sendable {
    public let dateKey: String
    public let rootTaskID: String
    public let title: String
    public let tokens: Int64
    public let descendantCount: Int

    public var id: String { "\(dateKey)|\(rootTaskID)" }

    public init(
        dateKey: String,
        rootTaskID: String,
        title: String,
        tokens: Int64,
        descendantCount: Int
    ) {
        self.dateKey = dateKey
        self.rootTaskID = rootTaskID
        self.title = title
        self.tokens = tokens
        self.descendantCount = descendantCount
    }
}

public struct DailyUsageSummary: Codable, Hashable, Identifiable, Sendable {
    public let dateKey: String
    public let totalTokens: Int64
    public let tasks: [DailyTaskUsage]
    public let isComplete: Bool

    public var id: String { dateKey }

    public init(
        dateKey: String,
        totalTokens: Int64,
        tasks: [DailyTaskUsage],
        isComplete: Bool
    ) {
        self.dateKey = dateKey
        self.totalTokens = totalTokens
        self.tasks = tasks.sorted {
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            return $0.rootTaskID < $1.rootTaskID
        }
        self.isComplete = isComplete
    }

    public func topTasks(limit: Int = 3) -> [DailyTaskUsage] {
        Array(tasks.prefix(max(0, limit)))
    }

    public func remainingTokens(afterTop limit: Int = 3) -> Int64 {
        max(0, totalTokens - topTasks(limit: limit).reduce(0) { $0 + $1.tokens })
    }
}

public struct UsageHistory: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let timezoneIdentifier: String
    public let days: [DailyUsageSummary]
    public let warnings: [String]

    public init(
        generatedAt: Date,
        timezoneIdentifier: String,
        days: [DailyUsageSummary],
        warnings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.timezoneIdentifier = timezoneIdentifier
        self.days = days.sorted { $0.dateKey < $1.dateKey }
        self.warnings = warnings
    }

    public func summary(for dateKey: String) -> DailyUsageSummary? {
        days.first { $0.dateKey == dateKey }
    }
}

public protocol CodexUsageReading: Sendable {
    func readUsage(now: Date, calendar: Calendar) async throws -> UsageHistory
}

public protocol UsageHistoryClearing: Sendable {
    func clearHistory() async throws
}

public protocol UsageHistoryStoring: Sendable {
    func load() async throws -> UsageHistory?
    func save(_ history: UsageHistory) async throws
    func clear() async throws
}
