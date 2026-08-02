import Foundation

public final class URLSessionRadarClient: RadarClient, @unchecked Sendable {
    private let session: URLSession
    private let endpoint: URL
    private let now: @Sendable () -> Date

    public convenience init(endpoint: URL = AppMetadata.radarJSONURL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.init(session: URLSession(configuration: configuration), endpoint: endpoint)
    }

    public init(
        session: URLSession,
        endpoint: URL = AppMetadata.radarJSONURL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.endpoint = endpoint
        self.now = now
    }

    public func fetch(cacheValidators: CacheValidators?) async throws -> RadarFetchResult {
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
            throw RadarClientError.invalidResponse
        }
        let validators = CacheValidators(
            etag: http.value(forHTTPHeaderField: "ETag") ?? cacheValidators?.etag,
            lastModified: http.value(forHTTPHeaderField: "Last-Modified") ?? cacheValidators?.lastModified
        )

        if http.statusCode == 304 {
            return .notModified(validators)
        }
        guard (200...299).contains(http.statusCode) else {
            throw RadarClientError.httpStatus(http.statusCode)
        }

        do {
            let response = try JSONDecoder().decode(IntelligenceEfficiencyResponse.self, from: data)
            guard response.schema == 2 else {
                throw RadarClientError.invalidPayload("不支持的数据版本：\(response.schema)")
            }
            guard let sourceUpdatedAt = response.normalizedSourceUpdatedAt else {
                throw RadarClientError.invalidPayload("聚合快照缺少 source_updated_at。")
            }
            let benchmarks = response.benchmarks
            guard !benchmarks.isEmpty else {
                throw RadarClientError.invalidPayload("聚合快照没有可用的模型数据。")
            }
            return .modified(
                RadarSnapshot(
                    schemaVersion: "intelligence-efficiency/\(response.schema)",
                    sourceMonitoredAt: sourceUpdatedAt,
                    fetchedAt: now(),
                    benchmarks: benchmarks,
                    validators: validators
                )
            )
        } catch let error as RadarClientError {
            throw error
        } catch {
            throw RadarClientError.invalidPayload(error.localizedDescription)
        }
    }
}
