import Foundation
import XCTest
@testable import CodexToolboxCore

final class RadarRepositoryTests: XCTestCase {
    func testFailurePreservesCachedSnapshot() async throws {
        let cached = StoredRadarState(snapshot: snapshot(), costHistory: [])
        let store = MemorySnapshotStore(state: cached)
        let client = QueueRadarClient(results: [.failure(.httpStatus(503))])
        let repository = RadarRepository(client: client, store: store)

        _ = await repository.loadCached()
        let failed = await repository.refresh()

        XCTAssertEqual(failed.snapshot, cached.snapshot)
        XCTAssertTrue(failed.isStale)
        XCTAssertNotNil(failed.errorMessage)
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

    private func snapshot() -> RadarSnapshot {
        RadarSnapshot(
            schemaVersion: "2.0",
            sourceMonitoredAt: "2026-07-13T16:30:00+08:00",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            benchmarks: [],
            validators: CacheValidators(etag: "etag")
        )
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
