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
        let cacheValidators = cacheValidators?.sourceURL == endpoint.absoluteString ? cacheValidators : nil
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
            (data, response) = try await BoundedHTTPResponse.data(for: request, session: session, maximumBytes: 8 * 1024 * 1024)
        } catch is BoundedHTTPResponse.Failure {
            throw APIPriceCardClientError.invalidResponse
        } catch let error as CancellationError {
            throw error
        } catch {
            PublicDataDiagnostics.record(error, feed: "api-price-card-network")
            throw APIPriceCardClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIPriceCardClientError.invalidResponse
        }
        let validators = CacheValidators(
            etag: http.value(forHTTPHeaderField: "ETag") ?? (http.statusCode == 304 ? cacheValidators?.etag : nil),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified") ?? (http.statusCode == 304 ? cacheValidators?.lastModified : nil),
            sourceURL: endpoint.absoluteString
        )
        if http.statusCode == 304 {
            guard cacheValidators != nil else { throw APIPriceCardClientError.invalidResponse }
            return .notModified(validators)
        }
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
    func saveCheck(_ card: StoredAPIPriceCard) async throws
}

public extension APIPriceCardStoring {
    func saveCheck(_ card: StoredAPIPriceCard) async throws { try await save(card) }
}

public actor APIPriceCardStore: APIPriceCardStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private var persistence: PublicCachePersistence

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL
            ?? ApplicationSupportLayout(fileManager: fileManager).apiPriceCardCacheURL
        persistence = PublicCachePersistence(fileURL: self.fileURL)
    }

    public func load() async throws -> StoredAPIPriceCard? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL)
        let stored = try decoder.decode(StoredAPIPriceCard.self, from: data)
        _ = try stored.manifest.validated()
        guard let check = persistence.didLoad(data) else { return stored }
        return StoredAPIPriceCard(manifest: stored.manifest, validators: check.validators, fetchedAt: check.fetchedAt)
    }

    public func save(_ card: StoredAPIPriceCard) async throws {
        try Task.checkCancellation()
        _ = try card.manifest.validated()
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try persistence.save(encoder.encode(card))
    }
    public func saveCheck(_ card: StoredAPIPriceCard) async throws {
        try Task.checkCancellation()
        if try !persistence.saveCheck(fetchedAt: card.fetchedAt, validators: card.validators) {
            try await save(card)
        }
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
    private var refreshID: UUID?
    private var lifecycleGeneration: UInt64 = 0

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
            PublicDataDiagnostics.record(error, feed: "api-price-card-cache")
            state = APIPriceCardRepositoryState(
                manifest: bundledManifest,
                source: .bundled,
                fetchedAt: nil,
                validators: CacheValidators(),
                errorMessage: "价格更新失败，继续使用本地价格。"
            )
        }
        return state
    }


    public func cancelRefresh(generation: UInt64? = nil) {
        guard advanceGeneration(to: generation) else { return }
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
    }

    private func advanceGeneration(to generation: UInt64?) -> Bool {
        guard let generation else { return true }
        guard generation >= lifecycleGeneration else { return false }
        if generation > lifecycleGeneration {
            lifecycleGeneration = generation
            refreshTask?.cancel()
            refreshTask = nil
            refreshID = nil
        }
        return true
    }

    public func refresh(generation: UInt64? = nil) async -> APIPriceCardRepositoryState {
        guard advanceGeneration(to: generation), !Task.isCancelled else { return state }
        if let refreshTask {
            let joinedID = refreshID
            let joined = await refreshTask.value
            return refreshID == joinedID ? joined : state
        }
        let id = UUID()
        let previous = state
        let client = client
        let store = store
        let now = now
        let task = Task<APIPriceCardRepositoryState, Never> {
            do {
                try Task.checkCancellation()
                let result = try await client.fetch(cacheValidators: previous.validators)
                try Task.checkCancellation()
                let manifest: APIPriceManifest
                let unchanged: Bool
                let validators: CacheValidators
                switch result {
                case let .modified(value, nextValidators):
                    guard value.isHistoryPreservingSuccessor(of: previous.manifest) else {
                        throw APIPriceValidationError.invalidManifest
                    }
                    manifest = value
                    unchanged = value == previous.manifest
                    validators = nextValidators
                case let .notModified(nextValidators):
                    manifest = previous.manifest
                    unchanged = true
                    validators = nextValidators
                }
                let fetchedAt = now()
                let stored = StoredAPIPriceCard(manifest: manifest, validators: validators, fetchedAt: fetchedAt)
                try Task.checkCancellation()
                if unchanged { try await store.saveCheck(stored) }
                else { try await store.save(stored) }
                try Task.checkCancellation()
                return APIPriceCardRepositoryState(
                    manifest: manifest,
                    source: .remote,
                    fetchedAt: fetchedAt,
                    validators: validators,
                    errorMessage: nil
                )
            } catch where Task.isCancelled {
                return previous
            } catch {
                PublicDataDiagnostics.record(error, feed: "api-price-card")
                return APIPriceCardRepositoryState(
                    manifest: previous.manifest,
                    source: previous.source,
                    fetchedAt: previous.fetchedAt,
                    validators: previous.validators,
                    errorMessage: "价格更新失败，继续使用本地价格。"
                )
            }
        }
        refreshTask = task
        refreshID = id
        let refreshed = await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
        guard refreshID == id else { return state }
        refreshTask = nil
        refreshID = nil
        guard !task.isCancelled else { return state }
        state = refreshed
        return refreshed
    }
}
