import Foundation
import Observation

public struct RadarRepositoryState: Sendable, Equatable {
    public let snapshot: RadarSnapshot?
    public let costHistory: [CostHistoryPoint]
    public let isStale: Bool
    public let errorMessage: String?
    public let checkedAt: Date?
    public let refreshFailed: Bool

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
        checkedAt: Date? = nil,
        refreshFailed: Bool = false
    ) {
        self.snapshot = snapshot
        self.costHistory = costHistory
        self.isStale = isStale
        self.errorMessage = errorMessage
        self.checkedAt = checkedAt
        self.refreshFailed = refreshFailed
    }
}

public enum RadarRefreshResult: Sendable, Equatable {
    case updated, unchanged, failed

    public var message: String {
        switch self {
        case .updated: "刷新成功"
        case .unchanged: "已是最新"
        case .failed: "刷新失败"
        }
    }

    public static func comparing(previous: RadarSnapshot?, current: RadarRepositoryState) -> Self {
        guard !current.refreshFailed, let snapshot = current.snapshot,
              !snapshot.benchmarks.isEmpty, snapshot.managed?.status != "no_data" else { return .failed }
        guard let previous else { return .updated }
        func models(_ snapshot: RadarSnapshot) -> [ModelBenchmark] {
            snapshot.benchmarks.sorted { $0.id < $1.id }.map {
                ModelBenchmark(id: $0.id, label: $0.label, model: $0.model, reasoningEffort: $0.reasoningEffort,
                               latest: $0.latest, recentDays: $0.recentDays.sorted { $0.date < $1.date })
            }
        }
        return previous.sourceMonitoredAt == snapshot.sourceMonitoredAt
            && previous.managed?.dataset == snapshot.managed?.dataset
            && previous.semanticsKey == snapshot.semanticsKey
            && models(previous) == models(snapshot) ? .unchanged : .updated
    }
}

@MainActor @Observable
public final class RadarRefreshFeedback {
    public private(set) var result: RadarRefreshResult?
    private var requestID: UUID?
    private var dismissal: Task<Void, Never>?
    private let duration: Duration

    public init(duration: Duration = .seconds(3)) { self.duration = duration }

    public func begin(manual: Bool) -> UUID? {
        clear()
        requestID = manual ? UUID() : nil
        return requestID
    }

    public func finish(_ id: UUID?, result: RadarRefreshResult) {
        guard let id, id == requestID else { return }
        dismissal?.cancel()
        self.result = result
        dismissal = Task { [weak self, duration] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.requestID == id else { return }
            self.clear()
        }
    }

    public func clear() {
        dismissal?.cancel()
        dismissal = nil
        requestID = nil
        result = nil
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
                isStale: cached.snapshot.managed?.isStale ?? false,
                errorMessage: nil
            )
        } catch {
            PublicDataDiagnostics.record(error, feed: "radar-cache")
            state = RadarRepositoryState(
                snapshot: nil,
                costHistory: [],
                isStale: true,
                errorMessage: "暂时无法获取榜单数据，请稍后重试。"
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
                // HTTP validators belong to the owned endpoint, never the 1.4.0 upstream.
                let result = try await client.fetch(cacheValidators: previous.snapshot?.managed != nil ? previous.snapshot?.validators : nil)
                let snapshot: RadarSnapshot
                switch result {
                case let .modified(newSnapshot):
                    snapshot = newSnapshot
                case let .notModified(validators):
                    guard let cached = previous.snapshot, cached.managed != nil else {
                        throw RadarClientError.notModifiedWithoutCache
                    }
                    snapshot = RadarSnapshot(
                        schemaVersion: cached.schemaVersion,
                        sourceMonitoredAt: cached.sourceMonitoredAt,
                        fetchedAt: now(),
                        benchmarks: cached.benchmarks,
                        validators: validators,
                        benchmarkID: cached.benchmarkID, aggregationMode: cached.aggregationMode, scoringMode: cached.scoringMode, priceRollingWindow: cached.priceRollingWindow, managed: cached.managed
                    )
                }

                if let old = previous.snapshot?.managed, let new = snapshot.managed {
                    guard new.revision >= old.revision, new.generation >= old.generation else {
                        throw RadarClientError.invalidPayload("发布版本倒退，保留有效缓存。")
                    }
                    if new.revision == old.revision && (new != old || snapshot.benchmarks != previous.snapshot?.benchmarks) {
                        throw RadarClientError.invalidPayload("同一发布版本的数据发生变化。")
                    }
                    if new.dataset.semanticsKey != old.dataset.semanticsKey && new.generation == old.generation {
                        throw RadarClientError.invalidPayload("评分基准变化未经显式发布。")
                    }
                }
                let changedGeneration = snapshot.managed.map { new in
                    previous.snapshot?.managed.map { new.generation > $0.generation } ?? false
                } ?? false
                if snapshot.benchmarks.isEmpty, previous.snapshot?.benchmarks.isEmpty == false {
                    throw RadarClientError.invalidPayload("服务端暂无成绩，保留有效缓存。")
                }
                if !changedGeneration, previous.snapshot?.semanticsKey == snapshot.semanticsKey,
                   let previousDate = previous.snapshot?.sourceMonitoredAt.flatMap(MetricFormatter.sourceDate),
                   let newDate = snapshot.sourceMonitoredAt.flatMap(MetricFormatter.sourceDate), newDate < previousDate {
                    throw RadarClientError.invalidPayload("上游快照时间倒退，保留较新的有效缓存。")
                }
                let oldPrices = Dictionary(uniqueKeysWithValues: (previous.snapshot?.benchmarks ?? []).map { ($0.id, $0.latest?.priceAggregation) })
                let newPrices = Dictionary(uniqueKeysWithValues: snapshot.benchmarks.map { ($0.id, $0.latest?.priceAggregation) })
                let compatibleHistory = !changedGeneration && previous.snapshot?.semanticsKey == snapshot.semanticsKey
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
                    isStale: snapshot.managed?.isStale ?? false,
                    errorMessage: nil,
                    checkedAt: now()
                )
            } catch {
                PublicDataDiagnostics.record(error, feed: "radar")
                let hasCache = previous.snapshot?.benchmarks.isEmpty == false
                let isTransient = NetworkRecoveryPolicy.failure(in: error) != nil
                return RadarRepositoryState(
                    snapshot: previous.snapshot,
                    costHistory: previous.costHistory,
                    isStale: previous.snapshot != nil,
                    errorMessage: hasCache
                        ? nil
                        : isTransient
                            ? "网络暂不可用，恢复连接后请重试。"
                            : "暂时无法获取榜单数据，请稍后重试。",
                    checkedAt: now(),
                    refreshFailed: true
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
