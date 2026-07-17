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
            let response = try JSONDecoder().decode(RadarResponse.self, from: data)
            return .modified(
                RadarSnapshot(
                    schemaVersion: response.schemaVersion,
                    sourceMonitoredAt: response.monitoredAt,
                    fetchedAt: now(),
                    benchmarks: response.benchmarks,
                    validators: validators
                )
            )
        } catch {
            throw RadarClientError.invalidPayload(error.localizedDescription)
        }
    }
}
