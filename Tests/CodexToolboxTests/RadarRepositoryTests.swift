import Foundation
import XCTest
@testable import CodexToolboxCore

final class RadarRepositoryTests: XCTestCase {
    func testOlderSourceCannotReplaceNewerCacheAndCheckTimeIsSeparate() async {
        let fresh = RadarSnapshot(schemaVersion: "intelligence-efficiency/3", sourceMonitoredAt: "2026-10-03T12:00:00Z", fetchedAt: Date(timeIntervalSince1970: 1), benchmarks: [], validators: CacheValidators())
        let old = RadarSnapshot(schemaVersion: "intelligence-efficiency/3", sourceMonitoredAt: "2026-10-02T12:00:00Z", fetchedAt: Date(timeIntervalSince1970: 2), benchmarks: [], validators: CacheValidators())
        let check = Date(timeIntervalSince1970: 100)
        let repository = RadarRepository(client: QueueRadarClient(results: [.success(.modified(old))]), store: MemorySnapshotStore(state: StoredRadarState(snapshot: fresh, costHistory: [])), now: { check })
        _ = await repository.loadCached()
        let result = await repository.refresh()
        XCTAssertEqual(result.snapshot, fresh)
        XCTAssertEqual(result.checkedAt, check)
        XCTAssertTrue(result.isStale)
    }

    func testDifferentPriceAggregationDoesNotJoinOldCostHistory() async {
        let record = BenchmarkRecord(date: "2026-10-03T12:00:00Z", score: 100, status: nil, passed: 2, tasks: 3, wallSeconds: 60, costUSD: 2, priceAggregation: "median")
        let benchmark = ModelBenchmark(id: "model", label: "Model", model: "gpt-6-sol", reasoningEffort: "high", latest: record, recentDays: [])
        let oldRecord = BenchmarkRecord(date: "2026-10-01T12:00:00Z", score: 100, status: nil, passed: 2, tasks: 3, wallSeconds: 60, costUSD: 9, priceAggregation: "mean")
        let oldModel = ModelBenchmark(id: "model", label: "Model", model: "gpt-6-sol", reasoningEffort: "high", latest: oldRecord, recentDays: [])
        let old = RadarSnapshot(schemaVersion: "intelligence-efficiency/3", sourceMonitoredAt: oldRecord.date, fetchedAt: Date(timeIntervalSince1970: 1), benchmarks: [oldModel], validators: CacheValidators())
        let current = RadarSnapshot(schemaVersion: "intelligence-efficiency/3", sourceMonitoredAt: record.date, fetchedAt: Date(timeIntervalSince1970: 2), benchmarks: [benchmark], validators: CacheValidators())
        let history = CostHistoryPoint(modelID: "model", dateKey: oldRecord.date, costUSD: 9, recordedAt: old.fetchedAt)
        let repository = RadarRepository(client: QueueRadarClient(results: [.success(.modified(current))]), store: MemorySnapshotStore(state: StoredRadarState(snapshot: old, costHistory: [history])))
        _ = await repository.loadCached()
        let result = await repository.refresh()
        XCTAssertEqual(result.costHistory.count, 1)
        XCTAssertEqual(result.costHistory.first?.costUSD, 2)
    }

    func testFailurePreservesCachedSnapshot() async throws {
        let cached = StoredRadarState(snapshot: snapshot(), costHistory: [])
        let store = MemorySnapshotStore(state: cached)
        let client = QueueRadarClient(results: [.failure(.httpStatus(503))])
        let repository = RadarRepository(client: client, store: store)

        _ = await repository.loadCached()
        let failed = await repository.refresh()

        XCTAssertEqual(failed.snapshot, cached.snapshot)
        XCTAssertTrue(failed.isStale)
        XCTAssertNil(failed.errorMessage)
    }

    func testTransientFailureWithCacheUsesStaleDataWithoutBanner() async throws {
        let cached = StoredRadarState(snapshot: snapshot(), costHistory: [])
        let repository = RadarRepository(
            client: TransientFailureRadarClient(),
            store: MemorySnapshotStore(state: cached)
        )

        _ = await repository.loadCached()
        let failed = await repository.refresh()

        XCTAssertEqual(failed.snapshot, cached.snapshot)
        XCTAssertTrue(failed.isStale)
        XCTAssertNil(failed.errorMessage)
    }

    func testTransientFailureWithoutCacheUsesLocalizedMessage() async {
        let repository = RadarRepository(
            client: TransientFailureRadarClient(),
            store: MemorySnapshotStore()
        )

        let failed = await repository.refresh()

        XCTAssertNil(failed.snapshot)
        XCTAssertFalse(failed.isStale)
        XCTAssertEqual(failed.errorMessage, "网络暂不可用，恢复连接后请重试。")
    }

    func testConcurrentRefreshesUseOneRequest() async {
        let fresh = snapshot()
        let client = QueueRadarClient(results: [.success(.modified(fresh))], delay: .milliseconds(30))
        let repository = RadarRepository(client: client, store: MemorySnapshotStore())

        async let first = repository.refresh()
        async let second = repository.refresh()
        let results = await [first, second]
        let callCount = await client.callCount()

        XCTAssertTrue(results.allSatisfy { $0.snapshot == fresh })
        XCTAssertEqual(callCount, 1)
    }

    func testInitialFailureDoesNotExposeAnIncompatibleSnapshot() async {
        let repository = RadarRepository(
            client: QueueRadarClient(results: [.failure(.httpStatus(503))]),
            store: MemorySnapshotStore()
        )

        _ = await repository.loadCached()
        let failed = await repository.refresh()

        XCTAssertNil(failed.snapshot)
        XCTAssertFalse(failed.isStale)
        XCTAssertNotNil(failed.errorMessage)
    }

    private func snapshot() -> RadarSnapshot {
        RadarSnapshot(
            schemaVersion: "2.0",
            sourceMonitoredAt: "2026-07-13T16:30:00+08:00",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            benchmarks: [ModelBenchmark(id: "model", label: "Model", model: "gpt-6-sol", reasoningEffort: "high",
                latest: BenchmarkRecord(date: "2026-07-13T16:30:00+08:00", score: 100, status: nil,
                                        passed: 1, tasks: 1, wallSeconds: 60, costUSD: 1), recentDays: [])],
            validators: CacheValidators(etag: "etag")
        )
    }
}

private struct TransientFailureRadarClient: RadarClient {
    func fetch(cacheValidators: CacheValidators?) async throws -> RadarFetchResult {
        throw URLError(.notConnectedToInternet)
    }
}

private actor MemorySnapshotStore: SnapshotStoring {
    private var state: StoredRadarState?

    init(state: StoredRadarState? = nil) {
        self.state = state
    }

    func load() async throws -> StoredRadarState? { state }
    func save(_ state: StoredRadarState) async throws { self.state = state }
}

private actor QueueRadarClient: RadarClient {
    enum StubResult: Sendable {
        case success(RadarFetchResult)
        case failure(RadarClientError)
    }

    private var results: [StubResult]
    private let delay: Duration
    private var calls = 0

    init(results: [StubResult], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func fetch(cacheValidators: CacheValidators?) async throws -> RadarFetchResult {
        calls += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        let result = results.removeFirst()
        switch result {
        case let .success(value): return value
        case let .failure(error): throw error
        }
    }

    func callCount() -> Int { calls }
}
