import Foundation

/// Owned wire contract. Upstream schemas never cross this boundary.
public struct ManagedRadarMetadata: Codable, Hashable, Sendable {
    public struct Dataset: Codable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let scoreLabel: String
        public let semanticsKey: String
    }
    public struct Source: Codable, Hashable, Sendable {
        public let name: String
        public let url: String
    }
    public let schemaVersion: String
    public let revision: Int
    public let generation: Int
    public let publishedAt: String
    public let checkedAt: String
    public let lastSuccessAt: String?
    public let sourceUpdatedAt: String?
    public let status: String
    public let change: String
    public let dataset: Dataset
    public let sources: [Source]

    public var isStale: Bool { status != "current" }
    public var statusLabel: String {
        switch status {
        case "historical": "历史数据"
        case "upstream_error": "同步异常 · 历史数据"
        case "no_data": "暂无成绩"
        default: "已同步"
        }
    }
}

public struct ManagedRadarFeed: Decodable, Sendable {
    public static let schema = "codex-toolbox.radar.v1"
    public let metadata: ManagedRadarMetadata
    public let models: [ModelBenchmark]

    private enum CodingKeys: String, CodingKey { case models }

    public init(from decoder: Decoder) throws {
        metadata = try ManagedRadarMetadata(from: decoder)
        models = try decoder.container(keyedBy: CodingKeys.self).decode([ModelBenchmark].self, forKey: .models)
    }

    public func snapshot(fetchedAt: Date, validators: CacheValidators) throws -> RadarSnapshot {
        func require(_ valid: Bool, _ message: String) throws {
            if !valid { throw RadarClientError.invalidPayload(message) }
        }
        try require(metadata.schemaVersion == Self.schema, "不支持的榜单接口版本。")
        try require(metadata.revision > 0 && metadata.generation > 0, "无效的发布版本。")
        try require(["current", "historical", "upstream_error", "no_data"].contains(metadata.status), "未知的数据状态。")
        try require(["sync", "status", "activation", "rollback"].contains(metadata.change), "未知的发布类型。")
        for value in [metadata.dataset.id, metadata.dataset.name, metadata.dataset.scoreLabel, metadata.dataset.semanticsKey] {
            try require(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 512, "无效的评分基准。")
        }
        for value in [metadata.publishedAt, metadata.checkedAt] + [metadata.sourceUpdatedAt, metadata.lastSuccessAt].compactMap({ $0 }) {
            try require(MetricFormatter.sourceDate(value) != nil, "无效的数据日期。")
        }
        try require(models.count <= 1000 && (!models.isEmpty || metadata.status == "no_data"), "榜单没有可用的模型数据。")
        try require(metadata.status != "no_data" || models.isEmpty, "空数据状态与成绩不一致。")
        var ids = Set<String>()
        var identities = Set<String>()
        for model in models {
            for value in [model.id, model.model, model.reasoningEffort, model.label] {
                try require(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 512, "缺少模型标识。")
            }
            try require(ids.insert(model.id).inserted && identities.insert(model.model + "|" + model.reasoningEffort).inserted, "重复的模型档位。")
            try require(model.latest?.score?.isFinite == true, "缺少有效评分。")
            try require(model.recentDays.count <= 90, "历史记录过多。")
            try require(model.recentDays.allSatisfy { !$0.date.isEmpty }, "历史成绩缺少日期。")
            for record in [model.latest].compactMap({ $0 }) + model.recentDays {
                try require(record.date.isEmpty || MetricFormatter.sourceDate(record.date) != nil, "无效的成绩日期。")
                if let source = metadata.sourceUpdatedAt.flatMap(MetricFormatter.sourceDate),
                   let grade = MetricFormatter.sourceDate(record.date) {
                    try require(grade <= source, "成绩日期晚于源数据日期。")
                }
                for count in [record.passed, record.tasks, record.priceSamples, record.durationSamples].compactMap({ $0 }) {
                    try require(count >= 0, "无效的样本数量。")
                }
                for value in [record.score, record.costUSD, record.wallSeconds, record.combinedCostIndex].compactMap({ $0 }) {
                    try require(value.isFinite, "无效的指标数值。")
                }
                for value in [record.costUSD, record.wallSeconds, record.combinedCostIndex].compactMap({ $0 }) {
                    try require(value >= 0, "指标数值不能为负。")
                }
            }
        }
        for source in metadata.sources {
            try require(URL(string: source.url)?.scheme == "https" && !source.name.isEmpty, "无效的数据来源。")
        }
        return RadarSnapshot(schemaVersion: Self.schema, sourceMonitoredAt: metadata.sourceUpdatedAt,
                             fetchedAt: fetchedAt, benchmarks: models, validators: validators,
                             benchmarkID: metadata.dataset.id, managed: metadata)
    }
}
