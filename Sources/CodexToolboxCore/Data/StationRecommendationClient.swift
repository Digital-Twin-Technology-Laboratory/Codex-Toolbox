import Foundation

public enum StationRecommendationFetchResult: Sendable {
    case modified(StationRecommendationSnapshot)
    case notModified(CacheValidators)
}

public protocol StationRecommendationReading: Sendable {
    func fetch(cacheValidators: CacheValidators?) async throws -> StationRecommendationFetchResult
}

public enum StationRecommendationClientError: Error, LocalizedError, Sendable, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload(String)
    case notModifiedWithoutCache

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "站长推荐服务返回了无效响应。"
        case let .httpStatus(code):
            "站长推荐暂时不可用（HTTP \(code)）。"
        case let .invalidPayload(message):
            "无法读取站长推荐：\(message)"
        case .notModifiedWithoutCache:
            "站长推荐未返回新数据，但本地缓存不存在。"
        }
    }
}

public final class URLSessionStationRecommendationClient: StationRecommendationReading, @unchecked Sendable {
    private let session: URLSession
    private let endpoint: URL
    private let now: @Sendable () -> Date

    public convenience init(endpoint: URL = AppMetadata.stationRecommendationsURL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.init(session: URLSession(configuration: configuration), endpoint: endpoint)
    }

    public init(
        session: URLSession,
        endpoint: URL = AppMetadata.stationRecommendationsURL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.endpoint = endpoint
        self.now = now
    }

    public func fetch(cacheValidators: CacheValidators?) async throws -> StationRecommendationFetchResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "CodexToolbox/\(AppMetadata.version) (+\(AppMetadata.repositoryURL.absoluteString))",
            forHTTPHeaderField: "User-Agent"
        )
        if let etag = cacheValidators?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = cacheValidators?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StationRecommendationClientError.invalidResponse
        }
        let validators = CacheValidators(
            etag: http.value(forHTTPHeaderField: "ETag") ?? cacheValidators?.etag,
            lastModified: http.value(forHTTPHeaderField: "Last-Modified") ?? cacheValidators?.lastModified
        )
        if http.statusCode == 304 { return .notModified(validators) }
        guard (200...299).contains(http.statusCode) else {
            throw StationRecommendationClientError.httpStatus(http.statusCode)
        }

        do {
            let payload = try JSONDecoder().decode(StationRecommendationResponse.self, from: data)
            guard payload.schema == 1 else {
                throw StationRecommendationClientError.invalidPayload(
                    "不支持的数据版本：\(payload.schema)"
                )
            }
            let scenarios = payload.scenarios
            guard !scenarios.isEmpty else {
                throw StationRecommendationClientError.invalidPayload("没有可用场景。")
            }
            return .modified(
                StationRecommendationSnapshot(
                    schema: payload.schema,
                    mode: payload.mode,
                    generatedAt: payload.generatedAt,
                    sourceUpdatedAt: payload.sourceUpdatedAt,
                    fetchedAt: now(),
                    scenarios: scenarios,
                    validators: validators
                )
            )
        } catch let error as StationRecommendationClientError {
            throw error
        } catch {
            throw StationRecommendationClientError.invalidPayload(error.localizedDescription)
        }
    }
}
