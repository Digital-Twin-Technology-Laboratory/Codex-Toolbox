import Foundation

public struct RadarResponse: Decodable, Sendable {
    public let schemaVersion: String
    public let monitoredAt: String?
    public let modelIQ: ModelIQPayload

    public var benchmarks: [ModelBenchmark] {
        modelIQ.comparisons
            .map { id, comparison in comparison.benchmark(id: id) }
            .sorted { $0.id < $1.id }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case monitoredAt = "monitored_at"
        case modelIQ = "model_iq"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "unknown"
        monitoredAt = try container.decodeIfPresent(String.self, forKey: .monitoredAt)
        modelIQ = try container.decodeIfPresent(ModelIQPayload.self, forKey: .modelIQ) ?? ModelIQPayload()
    }
}

public struct ModelIQPayload: Decodable, Sendable {
    public let comparisons: [String: ModelComparison]

    private enum CodingKeys: String, CodingKey {
        case comparisons
    }

    public init(comparisons: [String: ModelComparison] = [:]) {
        self.comparisons = comparisons
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comparisons = try container.decodeIfPresent([String: ModelComparison].self, forKey: .comparisons) ?? [:]
    }
}

public struct ModelComparison: Decodable, Sendable {
    public let label: String?
    public let model: String?
    public let reasoningEffort: String?
    public let latest: BenchmarkRecord?
    public let recentDays: [BenchmarkRecord]

    private enum CodingKeys: String, CodingKey {
        case label
        case model
        case reasoningEffort = "reasoning_effort"
        case latest
        case recentDays = "recent_days"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        latest = try container.decodeIfPresent(BenchmarkRecord.self, forKey: .latest)
        recentDays = try container.decodeIfPresent([BenchmarkRecord].self, forKey: .recentDays) ?? []
    }

    fileprivate func benchmark(id: String) -> ModelBenchmark {
        ModelBenchmark(
            id: id,
            label: label ?? id,
            model: model ?? id,
            reasoningEffort: reasoningEffort ?? "unknown",
            latest: latest,
            recentDays: recentDays
        )
    }
}
