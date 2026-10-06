import Foundation

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
