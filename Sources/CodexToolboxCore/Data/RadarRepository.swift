import Foundation

public struct RadarRepositoryState: Sendable, Equatable {
    public let snapshot: RadarSnapshot?
    public let costHistory: [CostHistoryPoint]
    public let isStale: Bool
    public let errorMessage: String?

    public static let empty = RadarRepositoryState(
        snapshot: nil,
        costHistory: [],
        isStale: false,
        errorMessage: nil
    )

    public init(
        snapshot: RadarSnapshot?,
        costHistory: [CostHistoryPoint],
        isStale: Bool,
        errorMessage: String?
    ) {
        self.snapshot = snapshot
        self.costHistory = costHistory
        self.isStale = isStale
        self.errorMessage = errorMessage
    }
}

public actor RadarRepository {
    private let client: any RadarClient
    private let store: any SnapshotStoring
    private let now: @Sendable () -> Date
    private var state: RadarRepositoryState = .empty
    private var refreshTask: Task<RadarRepositoryState, Never>?

    public init(
        client: any RadarClient,
        store: any SnapshotStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.store = store
        self.now = now
    }

    @discardableResult
    public func loadCached() async -> RadarRepositoryState {
        do {
            guard let cached = try await store.load() else {
                state = .empty
                return state
            }
            state = RadarRepositoryState(
                snapshot: cached.snapshot,
                costHistory: cached.costHistory,
                isStale: false,
                errorMessage: nil
            )
        } catch {
            state = RadarRepositoryState(
                snapshot: nil,
                costHistory: [],
                isStale: true,
                errorMessage: "本地缓存无法读取：\(error.localizedDescription)"
            )
        }
        return state
    }

    public func currentState() -> RadarRepositoryState {
        state
    }

    @discardableResult
    public func refresh() async -> RadarRepositoryState {
        if let refreshTask {
            return await refreshTask.value
        }

        let previous = state
        let client = client
        let store = store
        let now = now
        let task = Task<RadarRepositoryState, Never> {
            do {
                let result = try await client.fetch(cacheValidators: previous.snapshot?.validators)
                let snapshot: RadarSnapshot
                switch result {
                case let .modified(newSnapshot):
                    snapshot = newSnapshot
                case let .notModified(validators):
                    guard let cached = previous.snapshot else {
                        throw RadarClientError.notModifiedWithoutCache
                    }
                    snapshot = RadarSnapshot(
                        schemaVersion: cached.schemaVersion,
                        sourceMonitoredAt: cached.sourceMonitoredAt,
                        fetchedAt: now(),
                        benchmarks: cached.benchmarks,
                        validators: validators
                    )
                }

                let history = CostHistoryBuilder.merging(
                    previous.costHistory,
                    benchmarks: snapshot.benchmarks,
                    recordedAt: snapshot.fetchedAt
                )
                let stored = StoredRadarState(snapshot: snapshot, costHistory: history)
                try await store.save(stored)
                return RadarRepositoryState(
                    snapshot: snapshot,
                    costHistory: history,
                    isStale: false,
                    errorMessage: nil
                )
            } catch {
                return RadarRepositoryState(
                    snapshot: previous.snapshot,
                    costHistory: previous.costHistory,
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
