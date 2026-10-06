import Foundation
import OSLog

public struct CacheValidators: Codable, Hashable, Sendable {
    public var etag: String?
    public var lastModified: String?

    public var sourceURL: String?

    public init(etag: String? = nil, lastModified: String? = nil, sourceURL: String? = nil) {
        self.etag = etag
        self.lastModified = lastModified
        self.sourceURL = sourceURL
    }
}

public struct RadarSnapshot: Codable, Hashable, Sendable {
    public let schemaVersion: String
    public let sourceMonitoredAt: String?
    public let fetchedAt: Date
    public let benchmarks: [ModelBenchmark]
    public let validators: CacheValidators
    public let benchmarkID: String?
    public let aggregationMode: String?
    public let scoringMode: String?
    public let priceRollingWindow: Int?
    public let managed: ManagedRadarMetadata?
    public var semanticsKey: String { managed?.dataset.semanticsKey ?? [benchmarkID ?? "legacy", aggregationMode ?? "legacy", scoringMode ?? "legacy", priceRollingWindow.map(String.init) ?? "legacy"].joined(separator: "|") }

    public init(
        schemaVersion: String,
        sourceMonitoredAt: String?,
        fetchedAt: Date,
        benchmarks: [ModelBenchmark],
        validators: CacheValidators,
        benchmarkID: String? = nil, aggregationMode: String? = nil, scoringMode: String? = nil, priceRollingWindow: Int? = nil,
        managed: ManagedRadarMetadata? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sourceMonitoredAt = sourceMonitoredAt
        self.fetchedAt = fetchedAt
        self.benchmarks = benchmarks
        self.validators = validators
        self.benchmarkID = benchmarkID; self.aggregationMode = aggregationMode; self.scoringMode = scoringMode; self.priceRollingWindow = priceRollingWindow
        self.managed = managed
    }
}

public enum RadarFetchResult: Sendable {
    case modified(RadarSnapshot)
    case notModified(CacheValidators)
}

public protocol RadarClient: Sendable {
    func fetch(cacheValidators: CacheValidators?) async throws -> RadarFetchResult
}

public enum RadarClientError: Error, LocalizedError, Sendable, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload(String)
    case notModifiedWithoutCache

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "数据服务返回了无效响应。"
        case let .httpStatus(code):
            "数据服务暂时不可用（HTTP \(code)）。"
        case let .invalidPayload(message):
            "无法读取榜单数据：\(message)"
        case .notModifiedWithoutCache:
            "服务端未返回新数据，但本地缓存不存在。"
        }
    }
}

enum PublicDataDiagnostics {
    private static let payloadReasons: Set<String> = [
        "上游快照时间倒退，保留较新的有效缓存。",
        "不支持的榜单接口版本。",
        "刷新失败",
        "刷新成功",
        "历史成绩缺少日期。",
        "历史数据",
        "历史记录过多。",
        "发布版本倒退，保留有效缓存。",
        "同一发布版本的数据发生变化。",
        "同步异常 · 历史数据",
        "已同步",
        "已是最新",
        "成绩日期晚于源数据日期。",
        "指标数值不能为负。",
        "无效的发布版本。",
        "无效的成绩日期。",
        "无效的指标数值。",
        "无效的数据日期。",
        "无效的数据来源。",
        "无效的样本数量。",
        "无效的评分基准。",
        "暂无成绩",
        "暂时无法获取榜单数据，请稍后重试。",
        "服务端暂无成绩，保留有效缓存。",
        "未知的发布类型。",
        "未知的数据状态。",
        "榜单没有可用的模型数据。",
        "源数据日期倒退，保留有效缓存。",
        "空数据状态与成绩不一致。",
        "缺少有效评分。",
        "缺少模型标识。",
        "网络暂不可用，恢复连接后请重试。",
        "评分基准变化未经显式发布。",
        "重复的模型档位。",
    ]

    static func summary(_ error: any Error) -> String {
        switch error {
        case let RadarClientError.httpStatus(code), let StationRecommendationClientError.httpStatus(code),
             let RateCardClientError.httpStatus(code), let APIPriceCardClientError.httpStatus(code):
            return "HTTP \(code)"
        case let RadarClientError.invalidPayload(reason), let StationRecommendationClientError.invalidPayload(reason):
            return payloadReasons.contains(reason) ? reason : "payload validation failed"
        case let error as RateCardValidationError: return error.localizedDescription
        case let error as APIPriceValidationError: return error.localizedDescription
        default: return "\(String(reflecting: type(of: error))) (\((error as NSError).code))"
        }
    }

    static func record(_ error: any Error, feed: String) {
        let logger = Logger(subsystem: "io.github.zzzzzzjw.CodexToolbox", category: "PublicData")
        logger.error("\(feed, privacy: .public): \(summary(error), privacy: .public)")
    }
}
