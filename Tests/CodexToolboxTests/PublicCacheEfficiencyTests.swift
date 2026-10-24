import Foundation
import XCTest
@testable import CodexToolboxCore

final class PublicCacheEfficiencyTests: XCTestCase, @unchecked Sendable {
    private let before = Date(timeIntervalSince1970: 1_800_000_000)
    private let after = Date(timeIntervalSince1970: 1_800_000_060)
    private let validators = CacheValidators(etag: "checked-v2", lastModified: "checked", sourceURL: "https://example.invalid/feed")

    func testRateAndPrice304KeepPayloadBytesAndRestoreCheckTimeAfterRestart() async throws {
        try await verifyRateAndPriceChecks(modified: false)
    }

    func testIdenticalRateAndPrice200KeepPayloadAndRestoreFreshness() async throws {
        try await verifyRateAndPriceChecks(modified: true)
    }

    private func verifyRateAndPriceChecks(modified: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rate: RateCardManifest = try resource("codex-rate-card-v1.json")
        let price: APIPriceManifest = try resource("api-price-card-v1.json")
        let rateURL = directory.appendingPathComponent("rate.json")
        let rateStore = RateCardStore(fileURL: rateURL)
        try await rateStore.save(StoredRateCard(manifest: rate, validators: .init(), fetchedAt: before))
        let rateBody = try Data(contentsOf: rateURL)
        let rateFileIdentity = try fileIdentity(rateURL)
        let rateRepository = RateCardRepository(bundledManifest: rate, client: UnchangedRate(validators: validators, manifest: modified ? rate : nil), store: rateStore, now: { self.after })
        _ = await rateRepository.loadCached()
        _ = await rateRepository.refresh()
        let rateReloaded = try await RateCardStore(fileURL: rateURL).load()
        XCTAssertEqual(rateReloaded?.fetchedAt, after)
        XCTAssertEqual(rateReloaded?.validators, validators)
        XCTAssertEqual(try Data(contentsOf: rateURL), rateBody)
        XCTAssertEqual(try fileIdentity(rateURL), rateFileIdentity)

        let priceURL = directory.appendingPathComponent("price.json")
        let priceStore = APIPriceCardStore(fileURL: priceURL)
        try await priceStore.save(StoredAPIPriceCard(manifest: price, validators: .init(), fetchedAt: before))
        let priceBody = try Data(contentsOf: priceURL)
        let priceFileIdentity = try fileIdentity(priceURL)
        let priceRepository = APIPriceCardRepository(bundledManifest: price, client: UnchangedPrice(validators: validators, manifest: modified ? price : nil), store: priceStore, now: { self.after })
        _ = await priceRepository.loadCached()
        _ = await priceRepository.refresh()
        let priceReloaded = try await APIPriceCardStore(fileURL: priceURL).load()
        XCTAssertEqual(priceReloaded?.fetchedAt, after)
        XCTAssertEqual(priceReloaded?.validators, validators)
        XCTAssertEqual(try Data(contentsOf: priceURL), priceBody)
        XCTAssertEqual(try fileIdentity(priceURL), priceFileIdentity)
    }

    func testRadar304KeepsPayloadAndCostHistoryWhileRestoringFreshness() async throws {
        try await verifyRadarChecks(modified: false)
    }

    func testIdenticalRadar200KeepsPayloadAndCostHistoryWhileRestoringFreshness() async throws {
        try await verifyRadarChecks(modified: true)
    }

    private func verifyRadarChecks(modified: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("radar.json")
        #if SWIFT_PACKAGE
        let fixture = Bundle.module.url(forResource: "managed-radar-v1", withExtension: "json", subdirectory: "Fixtures")!
        #else
        let fixture = Bundle(for: Self.self).url(forResource: "managed-radar-v1", withExtension: "json")!
        #endif
        let snapshot = try JSONDecoder().decode(ManagedRadarFeed.self, from: Data(contentsOf: fixture)).snapshot(fetchedAt: before, validators: .init())
        let history = [CostHistoryPoint(modelID: "test", dateKey: "2026-10-23", costUSD: 1, recordedAt: before)]
        let store = SnapshotStore(fileURL: url)
        try await store.save(StoredRadarState(snapshot: snapshot, costHistory: history))
        let body = try Data(contentsOf: url)
        let identity = try fileIdentity(url)
        let repository = RadarRepository(client: UnchangedRadar(validators: validators, snapshot: modified ? snapshot.withCheck(.init(payloadDigest: "", fetchedAt: after, validators: validators)) : nil), store: store, now: { self.after })
        _ = await repository.loadCached()
        let result = await repository.refresh()
        XCTAssertEqual(result.costHistory, history)
        let restarted = try await SnapshotStore(fileURL: url).load()
        XCTAssertEqual(restarted?.snapshot.fetchedAt, after)
        XCTAssertEqual(restarted?.snapshot.validators, validators)
        XCTAssertEqual(restarted?.costHistory, history)
        XCTAssertEqual(try Data(contentsOf: url), body)
        XCTAssertEqual(try fileIdentity(url), identity)
        XCTAssertLessThan(try Data(contentsOf: url.appendingPathExtension("check.json")).count, 1024)
    }

    func testRecommendation304AndInterruptedPayloadReplacementNeverMixMetadata() async throws {
        try await verifyRecommendationChecks(modified: false)
    }

    func testIdenticalRecommendation200KeepsPayloadAndRestoresFreshness() async throws {
        try await verifyRecommendationChecks(modified: true)
    }

    private func verifyRecommendationChecks(modified: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recommendations.json")
        let snapshot = StationRecommendationSnapshot(schema: 1, mode: "test", generatedAt: nil,
            sourceUpdatedAt: nil, fetchedAt: before, scenarios: [], validators: .init())
        let store = StationRecommendationStore(fileURL: url)
        try await store.save(snapshot)
        let body = try Data(contentsOf: url)
        let identity = try fileIdentity(url)
        let repository = StationRecommendationRepository(client: UnchangedRecommendation(validators: validators, snapshot: modified ? snapshot.withCheck(.init(payloadDigest: "", fetchedAt: after, validators: validators)) : nil), store: store, now: { self.after })
        _ = await repository.loadCached()
        _ = await repository.refresh()
        let restarted = try await StationRecommendationStore(fileURL: url).load()
        XCTAssertEqual(restarted?.fetchedAt, after)
        XCTAssertEqual(restarted?.validators, validators)
        XCTAssertEqual(try Data(contentsOf: url), body)
        XCTAssertEqual(try fileIdentity(url), identity)
        let metadataURL = url.appendingPathExtension("check.json")
        let oldMetadata = try Data(contentsOf: metadataURL)
        let replacement = StationRecommendationSnapshot(schema: 1, mode: "replacement", generatedAt: nil,
            sourceUpdatedAt: nil, fetchedAt: before, scenarios: [], validators: .init())
        try await store.save(replacement)
        try oldMetadata.write(to: metadataURL)
        let recovered = try await StationRecommendationStore(fileURL: url).load()
        XCTAssertEqual(recovered?.mode, "replacement")
        XCTAssertEqual(recovered?.fetchedAt, before)
        XCTAssertEqual(recovered?.validators, CacheValidators())
    }

    func testCancelledQueuedSnapshotWritesCannotReplaceFreshPayloadOrMetadata() async throws {
        for checkOnly in [false, true] {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("queued.json")
            let store = SnapshotStore(fileURL: url)
            let fresh = RadarSnapshot(schemaVersion: "test", sourceMonitoredAt: nil, fetchedAt: after,
                benchmarks: [], validators: validators)
            let obsolete = RadarSnapshot(schemaVersion: "obsolete", sourceMonitoredAt: nil, fetchedAt: before,
                benchmarks: [], validators: .init())
            try await store.save(StoredRadarState(snapshot: fresh, costHistory: []))
            let body = try Data(contentsOf: url), identity = try fileIdentity(url)
            let entered = expectation(description: "Store actor is occupied")
            let queued = expectation(description: "Write is about to enter occupied actor")
            let release = DispatchSemaphore(value: 0)
            let blocker = Task.detached { await store.holdForCancellationTest(entered: entered, release: release) }
            await fulfillment(of: [entered], timeout: 2)
            let write = Task {
                queued.fulfill()
                let state = StoredRadarState(snapshot: obsolete, costHistory: [])
                if checkOnly { try await store.saveCheck(state) }
                else { try await store.save(state) }
            }
            await fulfillment(of: [queued], timeout: 2)
            write.cancel()
            release.signal()
            await blocker.value
            do { try await write.value; XCTFail("Cancelled queued store work must throw") }
            catch is CancellationError {}
            let restored = try await store.load()
            XCTAssertEqual(restored?.snapshot, fresh)
            XCTAssertEqual(try Data(contentsOf: url), body)
            XCTAssertEqual(try fileIdentity(url), identity)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("check.json").path))
        }
    }

    private func fileIdentity(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber).uint64Value
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func resource<T: Decodable>(_ name: String) throws -> T {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: root.appendingPathComponent("Sources/CodexToolbox/Resources/" + name)))
    }
}

private struct UnchangedRate: RateCardReading {
    let validators: CacheValidators
    let manifest: RateCardManifest?
    func fetch(cacheValidators: CacheValidators?) async throws -> RateCardFetchResult {
        manifest.map { .modified($0, validators) } ?? .notModified(validators)
    }
}
private struct UnchangedPrice: APIPriceCardReading {
    let validators: CacheValidators
    let manifest: APIPriceManifest?
    func fetch(cacheValidators: CacheValidators?) async throws -> APIPriceCardFetchResult {
        manifest.map { .modified($0, validators) } ?? .notModified(validators)
    }
}
private struct UnchangedRadar: RadarClient {
    let validators: CacheValidators
    let snapshot: RadarSnapshot?
    func fetch(cacheValidators: CacheValidators?) async throws -> RadarFetchResult {
        snapshot.map { .modified($0) } ?? .notModified(validators)
    }
}
private struct UnchangedRecommendation: StationRecommendationReading {
    let validators: CacheValidators
    let snapshot: StationRecommendationSnapshot?
    func fetch(cacheValidators: CacheValidators?) async throws -> StationRecommendationFetchResult {
        snapshot.map { .modified($0) } ?? .notModified(validators)
    }
}

private extension SnapshotStore {
    func holdForCancellationTest(entered: XCTestExpectation, release: DispatchSemaphore) {
        entered.fulfill()
        _ = release.wait(timeout: .now() + 5)
    }
}
