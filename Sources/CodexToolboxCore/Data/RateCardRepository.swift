import Foundation

public enum RateCardFetchResult: Sendable {
    case modified(RateCardManifest, CacheValidators)
    case notModified(CacheValidators)
}

public protocol RateCardReading: Sendable {
    func fetch(cacheValidators: CacheValidators?) async throws -> RateCardFetchResult
}

public enum RateCardClientError: Error, LocalizedError, Sendable, Equatable {
    case transport(String)
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case let .transport(message):
            "在线 Codex 费率清单连接失败：\(message)；继续使用本地费率。"
        case .invalidResponse:
            "在线 Codex 费率清单返回了无效响应；继续使用本地费率。"
        case let .httpStatus(code):
            "在线 Codex 费率清单检查失败（HTTP \(code)）；继续使用本地费率。"
        case let .invalidPayload(message):
            "在线 Codex 费率清单无法读取：\(message)；继续使用本地费率。"
        }
    }
}

public final class URLSessionRateCardClient: RateCardReading, @unchecked Sendable {
    private let session: URLSession
    private let endpoint: URL

    public convenience init(endpoint: URL = AppMetadata.rateCardManifestURL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.init(session: URLSession(configuration: configuration), endpoint: endpoint)
    }

    public init(session: URLSession, endpoint: URL = AppMetadata.rateCardManifestURL) {
        self.session = session
        self.endpoint = endpoint
    }

    public func fetch(cacheValidators: CacheValidators?) async throws -> RateCardFetchResult {
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
            throw RateCardClientError.invalidResponse
        } catch let error as CancellationError {
            throw error
        } catch {
            PublicDataDiagnostics.record(error, feed: "codex-rate-card-network")
            throw RateCardClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RateCardClientError.invalidResponse
        }
        let validators = CacheValidators(
            etag: http.value(forHTTPHeaderField: "ETag") ?? (http.statusCode == 304 ? cacheValidators?.etag : nil),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified") ?? (http.statusCode == 304 ? cacheValidators?.lastModified : nil),
            sourceURL: endpoint.absoluteString
        )
        if http.statusCode == 304 {
            guard cacheValidators != nil else { throw RateCardClientError.invalidResponse }
            return .notModified(validators)
        }
        guard (200...299).contains(http.statusCode) else {
            throw RateCardClientError.httpStatus(http.statusCode)
        }
        do {
            let manifest = try JSONDecoder().decode(RateCardManifest.self, from: data).validated()
            return .modified(manifest, validators)
        } catch {
            throw RateCardClientError.invalidPayload(error.localizedDescription)
        }
    }
}

public struct StoredRateCard: Codable, Hashable, Sendable {
    public let manifest: RateCardManifest
    public let validators: CacheValidators
    public let fetchedAt: Date

    public init(manifest: RateCardManifest, validators: CacheValidators, fetchedAt: Date) {
        self.manifest = manifest
        self.validators = validators
        self.fetchedAt = fetchedAt
    }
}

public protocol RateCardStoring: Sendable {
    func load() async throws -> StoredRateCard?
    func save(_ card: StoredRateCard) async throws
    func saveCheck(_ card: StoredRateCard) async throws
}

public extension RateCardStoring {
    func saveCheck(_ card: StoredRateCard) async throws { try await save(card) }
}

public actor RateCardStore: RateCardStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private var persistence: PublicCachePersistence

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? ApplicationSupportLayout(fileManager: fileManager).rateCardCacheURL
        persistence = PublicCachePersistence(fileURL: self.fileURL)
    }

    public func load() async throws -> StoredRateCard? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let stored = try Self.decoder.decode(StoredRateCard.self, from: data)
        _ = try stored.manifest.validated()
        guard let check = persistence.didLoad(data) else { return stored }
        return StoredRateCard(manifest: stored.manifest, validators: check.validators, fetchedAt: check.fetchedAt)
    }

    public func save(_ card: StoredRateCard) async throws {
        try Task.checkCancellation()
        _ = try card.manifest.validated()
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try persistence.save(Self.encoder.encode(card))
    }

    public func saveCheck(_ card: StoredRateCard) async throws {
        try Task.checkCancellation()
        if try !persistence.saveCheck(fetchedAt: card.fetchedAt, validators: card.validators) {
            try await save(card)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum RateCardSource: String, Codable, Hashable, Sendable {
    case bundled
    case cached
    case remote
}

public struct RateCardRepositoryState: Sendable, Equatable {
    public let manifest: RateCardManifest
    public let source: RateCardSource
    public let fetchedAt: Date?
    public let validators: CacheValidators
    public let errorMessage: String?

    public init(
        manifest: RateCardManifest,
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

    public func isStale(now: Date, threshold: TimeInterval = 7 * 24 * 60 * 60) -> Bool {
        let reference = fetchedAt
            ?? (try? Date(manifest.generatedAt, strategy: .iso8601))
        guard let reference else { return true }
        return now.timeIntervalSince(reference) > threshold
    }
}

public actor RateCardRepository {
    private let bundledManifest: RateCardManifest
    private let client: any RateCardReading
    private let store: any RateCardStoring
    private let now: @Sendable () -> Date
    private var state: RateCardRepositoryState
    private var refreshTask: Task<RateCardRepositoryState, Never>?
    private var refreshID: UUID?
    private var lifecycleGeneration: UInt64 = 0

    public init(
        bundledManifest: RateCardManifest,
        client: any RateCardReading = URLSessionRateCardClient(),
        store: any RateCardStoring = RateCardStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.bundledManifest = bundledManifest
        self.client = client
        self.store = store
        self.now = now
        state = RateCardRepositoryState(
            manifest: bundledManifest,
            source: .bundled,
            fetchedAt: nil,
            validators: CacheValidators(),
            errorMessage: nil
        )
    }

    @discardableResult
    public func loadCached() async -> RateCardRepositoryState {
        do {
            guard let cached = try await store.load() else { return state }
            guard cached.manifest.isHistoryPreservingSuccessor(of: bundledManifest) else {
                return state
            }
            state = RateCardRepositoryState(
                manifest: cached.manifest,
                source: .cached,
                fetchedAt: cached.fetchedAt,
                validators: cached.validators,
                errorMessage: nil
            )
        } catch {
            PublicDataDiagnostics.record(error, feed: "codex-rate-card-cache")
            state = RateCardRepositoryState(
                manifest: bundledManifest,
                source: .bundled,
                fetchedAt: nil,
                validators: CacheValidators(),
                errorMessage: "费率更新失败，继续使用本地费率。"
            )
        }
        return state
    }

    public func currentState() -> RateCardRepositoryState { state }


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

    @discardableResult
    public func refresh(generation: UInt64? = nil) async -> RateCardRepositoryState {
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
        let task = Task<RateCardRepositoryState, Never> {
            do {
                try Task.checkCancellation()
                let result = try await client.fetch(cacheValidators: previous.validators)
                try Task.checkCancellation()
                let manifest: RateCardManifest
                let unchanged: Bool
                let validators: CacheValidators
                switch result {
                case let .modified(value, newValidators):
                    guard value.isHistoryPreservingSuccessor(of: previous.manifest) else {
                        throw RateCardValidationError.invalidVersions
                    }
                    manifest = value
                    unchanged = value == previous.manifest
                    validators = newValidators
                case let .notModified(newValidators):
                    manifest = previous.manifest
                    unchanged = true
                    validators = newValidators
                }
                let fetchedAt = now()
                let stored = StoredRateCard(
                    manifest: manifest,
                    validators: validators,
                    fetchedAt: fetchedAt
                )
                try Task.checkCancellation()
                if unchanged { try await store.saveCheck(stored) }
                else { try await store.save(stored) }
                try Task.checkCancellation()
                return RateCardRepositoryState(
                    manifest: manifest,
                    source: .remote,
                    fetchedAt: fetchedAt,
                    validators: validators,
                    errorMessage: nil
                )
            } catch where Task.isCancelled {
                return previous
            } catch {
                PublicDataDiagnostics.record(error, feed: "codex-rate-card")
                return RateCardRepositoryState(
                    manifest: previous.manifest,
                    source: previous.source,
                    fetchedAt: previous.fetchedAt,
                    validators: previous.validators,
                    errorMessage: "费率更新失败，继续使用本地费率。"
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
