import Foundation

public struct CacheValidators: Codable, Hashable, Sendable {
    public var etag: String?
    public var lastModified: String?

    public init(etag: String? = nil, lastModified: String? = nil) {
        self.etag = etag
        self.lastModified = lastModified
    }
}

public struct RadarSnapshot: Codable, Hashable, Sendable {
    public let schemaVersion: String
    public let sourceMonitoredAt: String?
    public let fetchedAt: Date
    public let benchmarks: [ModelBenchmark]
    public let validators: CacheValidators

    public init(
        schemaVersion: String,
        sourceMonitoredAt: String?,
        fetchedAt: Date,
        benchmarks: [ModelBenchmark],
        validators: CacheValidators
    ) {
        self.schemaVersion = schemaVersion
        self.sourceMonitoredAt = sourceMonitoredAt
        self.fetchedAt = fetchedAt
        self.benchmarks = benchmarks
        self.validators = validators
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
            "无法读取 CodexRadar 数据：\(message)"
        case .notModifiedWithoutCache:
            "服务端未返回新数据，但本地缓存不存在。"
        }
    }
}
