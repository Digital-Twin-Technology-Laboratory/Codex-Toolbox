import Foundation

public protocol StationRecommendationStoring: Sendable {
    func load() async throws -> StationRecommendationSnapshot?
    func save(_ snapshot: StationRecommendationSnapshot) async throws
}

public actor StationRecommendationStore: StationRecommendationStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? ApplicationSupportLayout(fileManager: fileManager)
            .stationRecommendationsStateURL
    }

    public func load() async throws -> StationRecommendationSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try Self.decoder.decode(
            StationRecommendationSnapshot.self,
            from: Data(contentsOf: fileURL)
        )
    }

    public func save(_ snapshot: StationRecommendationSnapshot) async throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
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

public struct StationRecommendationRepositoryState: Sendable, Equatable {
    public let snapshot: StationRecommendationSnapshot?
    public let isStale: Bool
    public let errorMessage: String?

    public static let empty = StationRecommendationRepositoryState(
        snapshot: nil,
        isStale: false,
        errorMessage: nil
    )
}

public actor StationRecommendationRepository {
    private static let staleThreshold: TimeInterval = 24 * 60 * 60

    private let client: any StationRecommendationReading
    private let store: any StationRecommendationStoring
    private let now: @Sendable () -> Date
    private var state: StationRecommendationRepositoryState = .empty
    private var refreshTask: Task<StationRecommendationRepositoryState, Never>?

    public init(
        client: any StationRecommendationReading = URLSessionStationRecommendationClient(),
        store: any StationRecommendationStoring = StationRecommendationStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.store = store
        self.now = now
    }

    @discardableResult
    public func loadCached() async -> StationRecommendationRepositoryState {
        do {
            let snapshot = try await store.load()
            state = StationRecommendationRepositoryState(
                snapshot: snapshot,
                isStale: snapshot.map {
                    now().timeIntervalSince($0.fetchedAt) > Self.staleThreshold || ($0.managed.map { $0.status != "current" } ?? false)
                } ?? false,
                errorMessage: nil
            )
        } catch {
            PublicDataDiagnostics.record(error, feed: "recommendations-cache")
            state = StationRecommendationRepositoryState(
                snapshot: nil,
                isStale: true,
                errorMessage: "站长推荐缓存无法读取：\(error.localizedDescription)"
            )
        }
        return state
    }

    public func currentState() -> StationRecommendationRepositoryState { state }

    @discardableResult
    public func refresh() async -> StationRecommendationRepositoryState {
        if let refreshTask { return await refreshTask.value }
        let previous = state
        let client = client
        let store = store
        let now = now
        let task = Task<StationRecommendationRepositoryState, Never> {
            do {
                let result = try await client.fetch(cacheValidators: previous.snapshot?.validators)
                let snapshot: StationRecommendationSnapshot
                switch result {
                case let .modified(value):
                    if let oldSnapshot = previous.snapshot, let old = oldSnapshot.managed {
                        guard let new = value.managed, new.revision >= old.revision, new.generation >= old.generation else {
                            throw StationRecommendationClientError.invalidPayload("发布版本倒退，保留有效缓存。")
                        }
                        if new.revision == old.revision && (new != old || value.schema != oldSnapshot.schema
                            || value.mode != oldSnapshot.mode || value.generatedAt != oldSnapshot.generatedAt
                            || value.sourceUpdatedAt != oldSnapshot.sourceUpdatedAt || value.scenarios != oldSnapshot.scenarios) {
                            throw StationRecommendationClientError.invalidPayload("同一发布版本的数据发生变化。")
                        }
                    }
                    if let old = previous.snapshot, old.managed?.generation == value.managed?.generation,
                       let oldDate = old.sourceUpdatedAt.flatMap(MetricFormatter.sourceDate),
                       let newDate = value.sourceUpdatedAt.flatMap(MetricFormatter.sourceDate), newDate < oldDate {
                        throw StationRecommendationClientError.invalidPayload("源数据日期倒退，保留有效缓存。")
                    }
                    snapshot = value
                case let .notModified(validators):
                    guard let cached = previous.snapshot else {
                        throw StationRecommendationClientError.notModifiedWithoutCache
                    }
                    snapshot = StationRecommendationSnapshot(
                        schema: cached.schema,
                        mode: cached.mode,
                        generatedAt: cached.generatedAt,
                        sourceUpdatedAt: cached.sourceUpdatedAt,
                        fetchedAt: now(),
                        scenarios: cached.scenarios,
                        validators: validators,
                        managed: cached.managed
                    )
                }
                try await store.save(snapshot)
                return StationRecommendationRepositoryState(
                    snapshot: snapshot,
                    isStale: snapshot.managed.map { $0.status != "current" } ?? false,
                    errorMessage: nil
                )
            } catch {
                PublicDataDiagnostics.record(error, feed: "recommendations")
                return StationRecommendationRepositoryState(
                    snapshot: previous.snapshot,
                    isStale: previous.snapshot != nil,
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
