import Foundation

public enum APIPriceCardFetchResult: Sendable {
    case modified(APIPriceManifest, CacheValidators)
    case notModified(CacheValidators)
}

public protocol APIPriceCardReading: Sendable {
    func fetch(cacheValidators: CacheValidators?) async throws -> APIPriceCardFetchResult
}

public enum APIPriceCardClientError: Error, LocalizedError, Sendable, Equatable {
    case transport(String)
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case let .transport(message):
            "在线 API 价格清单连接失败：\(message)；继续使用本地价格。"
        case .invalidResponse:
            "在线 API 价格清单返回了无效响应；继续使用本地价格。"
        case let .httpStatus(code):
            "在线 API 价格清单检查失败（HTTP \(code)）；继续使用本地价格。"
        case let .invalidPayload(message):
            "在线 API 价格清单无法读取：\(message)；继续使用本地价格。"
        }
    }
}

public final class URLSessionAPIPriceCardClient: APIPriceCardReading, @unchecked Sendable {
    private let session: URLSession
    private let endpoint: URL

    public convenience init(endpoint: URL = AppMetadata.apiPriceManifestURL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.init(session: URLSession(configuration: configuration), endpoint: endpoint)
    }

    public init(session: URLSession, endpoint: URL = AppMetadata.apiPriceManifestURL) {
        self.session = session
        self.endpoint = endpoint
    }

    public func fetch(cacheValidators: CacheValidators?) async throws -> APIPriceCardFetchResult {
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw APIPriceCardClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIPriceCardClientError.invalidResponse
        }
        let validators = CacheValidators(
            etag: http.value(forHTTPHeaderField: "ETag") ?? cacheValidators?.etag,
            lastModified: http.value(forHTTPHeaderField: "Last-Modified") ?? cacheValidators?.lastModified
        )
        if http.statusCode == 304 { return .notModified(validators) }
        guard (200...299).contains(http.statusCode) else {
            throw APIPriceCardClientError.httpStatus(http.statusCode)
        }
        do {
            let manifest = try JSONDecoder().decode(APIPriceManifest.self, from: data).validated()
            return .modified(manifest, validators)
        } catch {
            throw APIPriceCardClientError.invalidPayload(error.localizedDescription)
        }
    }
}

public struct StoredAPIPriceCard: Codable, Hashable, Sendable {
    public let manifest: APIPriceManifest
    public let validators: CacheValidators
    public let fetchedAt: Date
}

public protocol APIPriceCardStoring: Sendable {
    func load() async throws -> StoredAPIPriceCard?
    func save(_ card: StoredAPIPriceCard) async throws
}

public actor APIPriceCardStore: APIPriceCardStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL
            ?? ApplicationSupportLayout(fileManager: fileManager).apiPriceCardCacheURL
    }

    public func load() async throws -> StoredAPIPriceCard? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = try decoder.decode(StoredAPIPriceCard.self, from: Data(contentsOf: fileURL))
        _ = try stored.manifest.validated()
        return stored
    }

    public func save(_ card: StoredAPIPriceCard) async throws {
        _ = try card.manifest.validated()
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(card).write(to: fileURL, options: .atomic)
    }
}

public struct APIPriceCardRepositoryState: Sendable, Equatable {
    public let manifest: APIPriceManifest
    public let source: RateCardSource
    public let fetchedAt: Date?
    public let validators: CacheValidators
    public let errorMessage: String?

    public init(
        manifest: APIPriceManifest,
        source: RateCardSource,
        fetchedAt: Date?,
        validators: CacheValidators,
        errorMessage: String?
    ) {
        self.manifest = manifest
        self.source = source
        self.fetchedAt = fetchedAt
        self.validators = validators
        self.errorMessage = errorMessage
    }

    public func isStale(now: Date, threshold: TimeInterval = 14 * 24 * 60 * 60) -> Bool {
        let reference = fetchedAt ?? (try? Date(manifest.generatedAt, strategy: .iso8601))
        guard let reference else { return true }
        return now.timeIntervalSince(reference) > threshold
    }
}

public actor APIPriceCardRepository {
    private let bundledManifest: APIPriceManifest
    private let client: any APIPriceCardReading
    private let store: any APIPriceCardStoring
    private let now: @Sendable () -> Date
    private var state: APIPriceCardRepositoryState
    private var refreshTask: Task<APIPriceCardRepositoryState, Never>?

    public init(
        bundledManifest: APIPriceManifest,
        client: any APIPriceCardReading = URLSessionAPIPriceCardClient(),
        store: any APIPriceCardStoring = APIPriceCardStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.bundledManifest = bundledManifest
        self.client = client
        self.store = store
        self.now = now
        state = APIPriceCardRepositoryState(
            manifest: bundledManifest,
            source: .bundled,
            fetchedAt: nil,
            validators: CacheValidators(),
            errorMessage: nil
        )
    }

    public func loadCached() async -> APIPriceCardRepositoryState {
        do {
            guard let cached = try await store.load(),
                  cached.manifest.isHistoryPreservingSuccessor(of: bundledManifest) else {
                return state
            }
            state = APIPriceCardRepositoryState(
                manifest: cached.manifest,
                source: .cached,
                fetchedAt: cached.fetchedAt,
                validators: cached.validators,
                errorMessage: nil
            )
        } catch {
            state = APIPriceCardRepositoryState(
                manifest: bundledManifest,
                source: .bundled,
                fetchedAt: nil,
                validators: CacheValidators(),
                errorMessage: "API 价格缓存无法读取：\(error.localizedDescription)"
            )
        }
        return state
    }

    public func refresh() async -> APIPriceCardRepositoryState {
        if let refreshTask { return await refreshTask.value }
        let previous = state
        let client = client
        let store = store
        let now = now
        let task = Task<APIPriceCardRepositoryState, Never> {
            do {
                let result = try await client.fetch(cacheValidators: previous.validators)
                let manifest: APIPriceManifest
                let validators: CacheValidators
                switch result {
                case let .modified(value, nextValidators):
                    guard value.isHistoryPreservingSuccessor(of: previous.manifest) else {
                        throw APIPriceValidationError.invalidManifest
                    }
                    manifest = value
                    validators = nextValidators
                case let .notModified(nextValidators):
                    manifest = previous.manifest
                    validators = nextValidators
                }
                let fetchedAt = now()
                try await store.save(
                    StoredAPIPriceCard(
                        manifest: manifest,
                        validators: validators,
                        fetchedAt: fetchedAt
                    )
                )
                return APIPriceCardRepositoryState(
                    manifest: manifest,
                    source: .remote,
                    fetchedAt: fetchedAt,
                    validators: validators,
                    errorMessage: nil
                )
            } catch {
                return APIPriceCardRepositoryState(
                    manifest: previous.manifest,
                    source: previous.source,
                    fetchedAt: previous.fetchedAt,
                    validators: previous.validators,
                    errorMessage: error.localizedDescription
                )
            }
        }
        refreshTask = task
        let refreshed = await task.value
        state = refreshed
        refreshTask = nil
        return refreshed
    }
}
