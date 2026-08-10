import Foundation

public enum RateCardFetchResult: Sendable {
    case modified(RateCardManifest, CacheValidators)
    case notModified(CacheValidators)
}

public protocol RateCardReading: Sendable {
    func fetch(cacheValidators: CacheValidators?) async throws -> RateCardFetchResult
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
        if http.statusCode == 304 { return .notModified(validators) }
        guard (200...299).contains(http.statusCode) else {
            throw RadarClientError.httpStatus(http.statusCode)
        }
        do {
            let manifest = try JSONDecoder().decode(RateCardManifest.self, from: data).validated()
            return .modified(manifest, validators)
        } catch {
            throw RadarClientError.invalidPayload(error.localizedDescription)
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
}

public actor RateCardStore: RateCardStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? ApplicationSupportLayout(fileManager: fileManager).rateCardCacheURL
    }

    public func load() async throws -> StoredRateCard? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let stored = try Self.decoder.decode(StoredRateCard.self, from: Data(contentsOf: fileURL))
        _ = try stored.manifest.validated()
        return stored
    }

    public func save(_ card: StoredRateCard) async throws {
        _ = try card.manifest.validated()
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder.encode(card).write(to: fileURL, options: .atomic)
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
            state = RateCardRepositoryState(
                manifest: bundledManifest,
                source: .bundled,
                fetchedAt: nil,
                validators: CacheValidators(),
                errorMessage: "官方费率缓存无法读取：\(error.localizedDescription)"
            )
        }
        return state
    }

    public func currentState() -> RateCardRepositoryState { state }

    @discardableResult
    public func refresh() async -> RateCardRepositoryState {
        if let refreshTask { return await refreshTask.value }
        let previous = state
        let client = client
        let store = store
        let now = now
        let task = Task<RateCardRepositoryState, Never> {
            do {
                let result = try await client.fetch(cacheValidators: previous.validators)
                let manifest: RateCardManifest
                let validators: CacheValidators
                switch result {
                case let .modified(value, newValidators):
                    guard value.isHistoryPreservingSuccessor(of: previous.manifest) else {
                        throw RateCardValidationError.invalidVersions
                    }
                    manifest = value
                    validators = newValidators
                case let .notModified(newValidators):
                    manifest = previous.manifest
                    validators = newValidators
                }
                let fetchedAt = now()
                let stored = StoredRateCard(
                    manifest: manifest,
                    validators: validators,
                    fetchedAt: fetchedAt
                )
                try await store.save(stored)
                return RateCardRepositoryState(
                    manifest: manifest,
                    source: .remote,
                    fetchedAt: fetchedAt,
                    validators: validators,
                    errorMessage: nil
                )
            } catch {
                return RateCardRepositoryState(
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
