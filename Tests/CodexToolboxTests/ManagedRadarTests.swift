import Foundation
import XCTest
@testable import CodexToolboxCore

final class ManagedRadarTests: XCTestCase {
    private func payload(_ name: String = "managed-radar-v1.json", edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        #else
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: nil)!
        #endif
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func snapshot(_ data: Data) throws -> RadarSnapshot {
        try JSONDecoder().decode(ManagedRadarFeed.self, from: data).snapshot(
            fetchedAt: Date(timeIntervalSince1970: 100), validators: CacheValidators(etag: "owned"))
    }

    func testBothServerAdaptersWorkWithSameDecoderAndRanking() throws {
        let old = try snapshot(payload())
        let new = try snapshot(payload("managed-radar-bench-v1.json"))
        XCTAssertEqual(RankingEngine.rank(old.benchmarks, by: .iq).first?.value, 100)
        XCTAssertEqual(RankingEngine.rank(old.benchmarks, by: .cost).first?.value, 2)
        XCTAssertEqual(RankingEngine.rank(old.benchmarks, by: .duration).first?.value, 120)
        XCTAssertEqual(RankingEngine.rank(new.benchmarks, by: .iq).first?.value, 80)
        XCTAssertEqual(new.managed?.dataset.scoreLabel, "Radar Bench 分数")
        XCTAssertNil(new.sourceMonitoredAt)
        XCTAssertEqual(new.benchmarks.first?.latest?.date, "")
        for metric in [RankingMetric.cost, .duration, .overall] {
            XCTAssertTrue(RankingEngine.rank(new.benchmarks, by: metric).isEmpty)
        }
        XCTAssertTrue(RankingEngine.rank(new.benchmarks, by: .overall, overallMode: .radarCostEfficiency).isEmpty)
        XCTAssertTrue(CostHistoryBuilder.merging([], benchmarks: new.benchmarks, recordedAt: Date()).isEmpty)
    }

    func testUnknownOptionalFieldsAreCompatible() throws {
        let result = try snapshot(payload { $0["futureField"] = ["new": true] })
        XCTAssertEqual(result.benchmarks.count, 1)
    }

    func testInvalidContractAndDuplicateModelsAreRejected() throws {
        for field in ["schemaVersion", "status", "change", "checkedAt"] {
            XCTAssertThrowsError(try snapshot(payload { $0[field] = "invalid" }))
        }
        XCTAssertThrowsError(try snapshot(payload { $0["revision"] = 0 }))
        XCTAssertThrowsError(try snapshot(payload {
            let rows = $0["models"] as! [[String: Any]]; $0["models"] = rows + rows
        }))
        XCTAssertThrowsError(try snapshot(payload { $0["models"] = [] }))
        XCTAssertThrowsError(try snapshot(payload {
            var rows = $0["models"] as! [[String: Any]]
            var record = rows[0]["latest"] as! [String: Any]; record["cost_usd"] = -1
            rows[0]["latest"] = record; $0["models"] = rows
        }))
    }

    func testNoDataIsAValidColdStartStateButCannotReplaceScores() async throws {
        let empty = try snapshot(payload { $0["status"] = "no_data"; $0["models"] = []; $0["revision"] = 2 })
        let fresh = RadarRepository(client: ManagedQueueClient([.modified(empty)]), store: ManagedMemoryStore())
        let cold = await fresh.refresh()
        XCTAssertEqual(cold.snapshot?.managed?.status, "no_data")
        XCTAssertNil(cold.errorMessage)
        let old = try snapshot(payload())
        let warm = RadarRepository(client: ManagedQueueClient([.modified(empty)]), store: ManagedMemoryStore(old))
        _ = await warm.loadCached()
        let result = await warm.refresh()
        XCTAssertEqual(result.snapshot, old)
        XCTAssertTrue(result.refreshFailed)
    }

    func testRevisionRegressionAndSameRevisionMutationRejected() async throws {
        let old = try snapshot(payload { $0["revision"] = 3 })
        for bad in [try snapshot(payload()), try snapshot(payload { $0["revision"] = 3; $0["status"] = "current" })] {
            let repository = RadarRepository(client: ManagedQueueClient([.modified(bad)]), store: ManagedMemoryStore(old))
            _ = await repository.loadCached()
            let result = await repository.refresh()
            XCTAssertEqual(result.snapshot, old)
            XCTAssertTrue(result.refreshFailed)
        }
    }

    func testSwitchRequiresNewGenerationAndDropsCostHistory() async throws {
        let old = try snapshot(payload())
        let history = CostHistoryPoint(modelID: old.benchmarks[0].id, dateKey: "2026-10-01", costUSD: 5, recordedAt: Date())
        let unapproved = try snapshot(payload("managed-radar-bench-v1.json") { $0["revision"] = 2 })
        let approved = try snapshot(payload("managed-radar-bench-v1.json") {
            $0["revision"] = 3; $0["generation"] = 2; $0["change"] = "activation"
        })
        let repository = RadarRepository(client: ManagedQueueClient([.modified(unapproved), .modified(approved)]),
                                         store: ManagedMemoryStore(old, history: [history]))
        _ = await repository.loadCached()
        let rejected = await repository.refresh()
        XCTAssertEqual(rejected.snapshot, old)
        let accepted = await repository.refresh()
        XCTAssertEqual(accepted.snapshot, approved)
        XCTAssertTrue(accepted.costHistory.isEmpty)
    }

    func testExplicitRollbackAllowsOlderDataAndClearsFutureHistory() async throws {
        let old = try snapshot(payload())
        let restored = try snapshot(payload {
            $0["revision"] = 2; $0["generation"] = 2; $0["change"] = "rollback"
            $0["sourceUpdatedAt"] = "2026-10-01T00:00:00Z"
            var rows = $0["models"] as! [[String: Any]]
            var record = rows[0]["latest"] as! [String: Any]; record["date"] = "2026-10-01T00:00:00Z"
            rows[0]["latest"] = record; $0["models"] = rows
        })
        let history = CostHistoryPoint(modelID: old.benchmarks[0].id, dateKey: "2026-10-06", costUSD: 5, recordedAt: Date())
        let repository = RadarRepository(client: ManagedQueueClient([.modified(restored)]), store: ManagedMemoryStore(old, history: [history]))
        _ = await repository.loadCached()
        let result = await repository.refresh()
        XCTAssertEqual(result.snapshot, restored)
        XCTAssertEqual(result.costHistory.map(\.dateKey), ["2026-10-01T00:00:00Z"])
    }

    func testUpgradeKeepsLegacyCacheButSendsNoLegacyValidators() async throws {
        let legacy = RadarSnapshot(schemaVersion: "intelligence-efficiency/3", sourceMonitoredAt: "2026-10-06T08:00:00Z",
                                   fetchedAt: Date(), benchmarks: try snapshot(payload()).benchmarks,
                                   validators: CacheValidators(etag: "old-upstream"), benchmarkID: "deep-swe",
                                   aggregationMode: "equal_latest_3", scoringMode: "binary-majority", priceRollingWindow: 3)
        let owned = try snapshot(payload())
        let client = ManagedQueueClient([.modified(owned), .notModified(CacheValidators(etag: "owned"))])
        let repository = RadarRepository(client: client, store: ManagedMemoryStore(legacy))
        let cached = await repository.loadCached(); XCTAssertEqual(cached.snapshot, legacy)
        _ = await repository.refresh()
        let checked = await repository.refresh()
        let validators = await client.received()
        XCTAssertNil(validators[0]); XCTAssertEqual(validators[1]?.etag, "owned")
        XCTAssertEqual(checked.snapshot?.sourceMonitoredAt, owned.sourceMonitoredAt)
        XCTAssertEqual(checked.snapshot?.managed, owned.managed)
        XCTAssertFalse(checked.refreshFailed)
        XCTAssertTrue(checked.isStale) // 304 never changes historical to current.
    }

    func testManagedCachePersistsMetadataAcrossRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("snapshot.json")
        let original = try snapshot(payload())
        try await SnapshotStore(fileURL: url).save(StoredRadarState(snapshot: original, costHistory: []))
        let result = try await SnapshotStore(fileURL: url).load()
        XCTAssertEqual(result?.snapshot, original)
    }

    func testHTTPManagedFeedUsesOnlyOneEndpointAndClearsMissing200Validators() async throws {
        let bytes = try payload()
        ManagedURLProtocol.handler = { request in
            XCTAssertEqual(request.url, AppMetadata.radarJSONURL)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!, bytes)
        }
        defer { ManagedURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ManagedURLProtocol.self]
        let client = URLSessionRadarClient(session: URLSession(configuration: config))
        guard case let .modified(result) = try await client.fetch(cacheValidators: CacheValidators(etag: "old", lastModified: "old")) else {
            return XCTFail("expected modified feed")
        }
        XCTAssertNotNil(result.managed)
        XCTAssertNil(result.validators.etag); XCTAssertNil(result.validators.lastModified)
    }

    func testHTTP304WithoutCacheFailsSafely() async {
        let repository = RadarRepository(client: ManagedQueueClient([.notModified(CacheValidators())]), store: ManagedMemoryStore())
        let result = await repository.refresh()
        XCTAssertNil(result.snapshot)
        XCTAssertTrue(result.refreshFailed)
    }

    func testServiceFailurePreservesManagedCacheAndMarksConnectionFailure() async throws {
        let old = try snapshot(payload())
        let repository = RadarRepository(client: ManagedFailingClient(), store: ManagedMemoryStore(old))
        _ = await repository.loadCached()
        let result = await repository.refresh()
        XCTAssertEqual(result.snapshot, old)
        XCTAssertTrue(result.refreshFailed)
        XCTAssertTrue(result.isStale)
    }
}

private actor ManagedMemoryStore: SnapshotStoring {
    var state: StoredRadarState?
    init(_ snapshot: RadarSnapshot? = nil, history: [CostHistoryPoint] = []) {
        state = snapshot.map { StoredRadarState(snapshot: $0, costHistory: history) }
    }
    func load() async throws -> StoredRadarState? { state }
    func save(_ state: StoredRadarState) async throws { self.state = state }
}

private actor ManagedQueueClient: RadarClient {
    var results: [RadarFetchResult]
    var validators: [CacheValidators?] = []
    init(_ results: [RadarFetchResult]) { self.results = results }
    func fetch(cacheValidators: CacheValidators?) async throws -> RadarFetchResult {
        validators.append(cacheValidators)
        return results.removeFirst()
    }
    func received() -> [CacheValidators?] { validators }
}

private struct ManagedFailingClient: RadarClient {
    func fetch(cacheValidators: CacheValidators?) async throws -> RadarFetchResult { throw URLError(.notConnectedToInternet) }
}

private final class ManagedURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
