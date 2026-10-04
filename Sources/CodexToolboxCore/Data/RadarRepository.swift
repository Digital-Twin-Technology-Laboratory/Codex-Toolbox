import Foundation

public struct RadarRepositoryState: Sendable, Equatable {
    public let snapshot: RadarSnapshot?
    public let costHistory: [CostHistoryPoint]
    public let isStale: Bool
    public let errorMessage: String?
    public let checkedAt: Date?

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
        errorMessage: String?,
        checkedAt: Date? = nil
    ) {
        self.snapshot = snapshot
        self.costHistory = costHistory
        self.isStale = isStale
        self.errorMessage = errorMessage
        self.checkedAt = checkedAt
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
                let result = try await client.fetch(cacheValidators: previous.snapshot?.schemaVersion == "intelligence-efficiency/3" && previous.snapshot?.aggregationMode != nil ? previous.snapshot?.validators : nil)
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
                        validators: validators,
                        benchmarkID: cached.benchmarkID, aggregationMode: cached.aggregationMode, scoringMode: cached.scoringMode, priceRollingWindow: cached.priceRollingWindow
                    )
                }

                if let previousDate = previous.snapshot?.sourceMonitoredAt.flatMap(MetricFormatter.sourceDate),
                   let newDate = snapshot.sourceMonitoredAt.flatMap(MetricFormatter.sourceDate), newDate < previousDate {
                    throw RadarClientError.invalidPayload("上游快照时间倒退，保留较新的有效缓存。")
                }
                let oldPrices = Dictionary(uniqueKeysWithValues: (previous.snapshot?.benchmarks ?? []).map { ($0.id, $0.latest?.priceAggregation) })
                let newPrices = Dictionary(uniqueKeysWithValues: snapshot.benchmarks.map { ($0.id, $0.latest?.priceAggregation) })
                let compatibleHistory = previous.snapshot?.schemaVersion == snapshot.schemaVersion && previous.snapshot?.semanticsKey == snapshot.semanticsKey
                    ? previous.costHistory.filter { oldPrices[$0.modelID] == newPrices[$0.modelID] } : []
                let history = CostHistoryBuilder.merging(
                    compatibleHistory,
                    benchmarks: snapshot.benchmarks,
                    recordedAt: snapshot.fetchedAt
                )
                let stored = StoredRadarState(snapshot: snapshot, costHistory: history)
                try await store.save(stored)
                return RadarRepositoryState(
                    snapshot: snapshot,
                    costHistory: history,
                    isStale: false,
                    errorMessage: nil,
                    checkedAt: now()
                )
            } catch {
                let hasCache = previous.snapshot != nil
                let isTransient = NetworkRecoveryPolicy.failure(in: error) != nil
                return RadarRepositoryState(
                    snapshot: previous.snapshot,
                    costHistory: previous.costHistory,
                    isStale: hasCache,
                    errorMessage: isTransient && hasCache
                        ? nil
                        : isTransient
                            ? "网络暂不可用，恢复连接后请重试。"
                            : error.localizedDescription,
                    checkedAt: now()
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
