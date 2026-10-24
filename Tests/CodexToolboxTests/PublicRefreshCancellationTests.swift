import Foundation
import XCTest
@testable import CodexToolboxCore

final class PublicRefreshCancellationTests: XCTestCase, @unchecked Sendable {
    func testCancellingOwnerRejectsLateRecommendationWithoutSaving() async throws {
        let client = GatedRecommendationClient(), store = CancellationRecommendationStore()
        let repository = StationRecommendationRepository(client: client, store: store)
        let operation = Task { await repository.refresh() }
        await client.waitForCalls(1)
        operation.cancel()
        await client.completeFirst(mode: "late")
        _ = await operation.value
        let state = await repository.currentState(), saved = await store.saved
        XCTAssertNil(state.snapshot)
        XCTAssertEqual(saved, [])
    }

    func testOldSleepCancellationCannotCancelWakeAndLateOldResultCannotRollbackIt() async throws {
        let client = GatedRecommendationClient(), store = CancellationRecommendationStore()
        let repository = StationRecommendationRepository(client: client, store: store)
        let sleeping = Task { await repository.refresh(generation: 1) }
        await client.waitForCalls(1)
        let joinedOld = Task { await repository.refresh(generation: 1) }
        try await Task.sleep(for: .milliseconds(20))
        await repository.cancelRefresh(generation: 2)
        let waking = Task { await repository.refresh(generation: 3) }
        await client.waitForCalls(2)
        await repository.cancelRefresh(generation: 2)
        await client.complete(at: 1, mode: "fresh")
        let fresh = await waking.value
        await client.completeFirst(mode: "obsolete")
        let late = await sleeping.value
        let joinedLate = await joinedOld.value
        let state = await repository.currentState(), saved = await store.saved
        XCTAssertEqual(fresh.snapshot?.mode, "fresh")
        XCTAssertEqual(late, fresh)
        XCTAssertEqual(joinedLate, fresh)
        XCTAssertEqual(state, fresh)
        XCTAssertEqual(saved, ["fresh"])
        let rejected = await repository.refresh(generation: 1)
        XCTAssertEqual(rejected, fresh)
    }

    func testCancellingJoinedCallerKeepsManualOwnerFreshness() async throws {
        let client = GatedRecommendationClient(), store = CancellationRecommendationStore()
        let repository = StationRecommendationRepository(client: client, store: store)
        let manual = Task { await repository.refresh(generation: 1) }
        await client.waitForCalls(1)
        let joined = Task { await repository.refresh(generation: 1) }
        try await Task.sleep(for: .milliseconds(20))
        joined.cancel()
        await client.completeFirst(mode: "fresh")
        let manualResult = await manual.value, joinedResult = await joined.value
        let state = await repository.currentState(), saved = await store.saved
        XCTAssertEqual(manualResult.snapshot?.mode, "fresh")
        XCTAssertEqual(joinedResult.snapshot?.mode, "fresh")
        XCTAssertEqual(state, manualResult)
        XCTAssertEqual(saved, ["fresh"])
    }

    func testExplicitCancellationStopsUnderlyingRadarURLRequest() async throws {
        let started = expectation(description: "URL request started")
        let stopped = expectation(description: "URLProtocol.stopLoading called")
        CancelledRequestProtocol.started = started
        CancelledRequestProtocol.stopped = stopped
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancelledRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = CancellationRadarStore()
        let repository = RadarRepository(client: URLSessionRadarClient(session: session,
            endpoint: URL(string: "https://example.invalid/radar")!), store: store)
        let operation = Task { await repository.refresh(generation: 1) }
        await fulfillment(of: [started], timeout: 2)
        await repository.cancelRefresh(generation: 2)
        await fulfillment(of: [stopped], timeout: 2)
        _ = await operation.value
        let saved = await store.saved
        let state = await repository.currentState()
        XCTAssertEqual(saved, 0)
        XCTAssertEqual(state, .empty)
    }

}

private actor GatedRecommendationClient: StationRecommendationReading {
    private var calls = 0
    private var pending: [CheckedContinuation<StationRecommendationFetchResult, Error>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func fetch(cacheValidators: CacheValidators?) async throws -> StationRecommendationFetchResult {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            let ready = waiters.filter { $0.0 <= calls }; waiters.removeAll { $0.0 <= calls }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForCalls(_ count: Int) async {
        guard calls < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func completeFirst(mode: String) { complete(at: 0, mode: mode) }
    func complete(at index: Int, mode: String) {
        pending.remove(at: index).resume(returning: .modified(StationRecommendationSnapshot(schema: 1, mode: mode,
            generatedAt: nil, sourceUpdatedAt: nil, fetchedAt: Date(), scenarios: [], validators: .init())))
    }
}

private actor CancellationRecommendationStore: StationRecommendationStoring {
    private(set) var saved: [String] = []
    func load() async throws -> StationRecommendationSnapshot? { nil }
    func save(_ snapshot: StationRecommendationSnapshot) async throws { saved.append(snapshot.mode) }
}

private actor CancellationRadarStore: SnapshotStoring {
    private(set) var saved = 0
    func load() async throws -> StoredRadarState? { nil }
    func save(_ state: StoredRadarState) async throws { saved += 1 }
}

private final class CancelledRequestProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var started: XCTestExpectation?
    nonisolated(unsafe) static var stopped: XCTestExpectation?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.started?.fulfill() }
    override func stopLoading() { Self.stopped?.fulfill() }
}
