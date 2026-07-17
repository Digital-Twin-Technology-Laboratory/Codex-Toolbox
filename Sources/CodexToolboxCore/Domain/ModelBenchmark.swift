import Foundation

public struct BenchmarkRecord: Codable, Hashable, Sendable {
    public let date: String
    public let score: Double?
    public let status: String?
    public let passed: Int?
    public let tasks: Int?
    public let wallSeconds: Double?
    public let costUSD: Double?

    private enum CodingKeys: String, CodingKey {
        case date
        case score
        case status
        case passed
        case tasks
        case wallSeconds = "wall_seconds"
        case costUSD = "cost_usd"
    }

    public init(
        date: String,
        score: Double?,
        status: String?,
        passed: Int?,
        tasks: Int?,
        wallSeconds: Double?,
        costUSD: Double?
    ) {
        self.date = date
        self.score = score
        self.status = status
        self.passed = passed
        self.tasks = tasks
        self.wallSeconds = wallSeconds
        self.costUSD = costUSD
    }
}

public struct ModelBenchmark: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let model: String
    public let reasoningEffort: String
    public let latest: BenchmarkRecord?
    public let recentDays: [BenchmarkRecord]

    public init(
        id: String,
        label: String,
        model: String,
        reasoningEffort: String,
        latest: BenchmarkRecord?,
        recentDays: [BenchmarkRecord]
    ) {
        self.id = id
        self.label = label
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.latest = latest
        self.recentDays = recentDays
    }

    public func value(for metric: RankingMetric) -> Double? {
        switch metric {
        case .iq:
            latest?.score
        case .cost:
            latest?.costUSD
        case .duration:
            latest?.wallSeconds
        case .overall:
            nil
        }
    }
}
