import Foundation
@testable import CodexToolboxCore
import XCTest

final class RateCardRepositoryTests: XCTestCase {
    func testDisablingExperimentCancelsRateRefreshWithoutSavingResponse() async throws {
        let gate = CostRefreshTestGate(), store = RateStoreStub(stored: nil)
        let repository = RateCardRepository(bundledManifest: manifest(inputRate: 100), client: SuspendedRateClient(gate: gate), store: store)
        let request = Task { await repository.refresh() }
        await gate.waitUntilRequested()
        await repository.cancelRefresh()
        await gate.release()
        let state = await request.value, cached = try await store.load()
        XCTAssertNil(cached)
        XCTAssertEqual(state.source, .bundled)
        XCTAssertNil(state.errorMessage)
    }
    func testOnlineRateErrorsIdentifyLocalFallback() {
        XCTAssertEqual(
            RateCardClientError.httpStatus(503).localizedDescription,
            "在线 Codex 费率清单检查失败（HTTP 503）；继续使用本地费率。"
        )
        XCTAssertEqual(
            RateCardClientError.transport("网络离线").localizedDescription,
            "在线 Codex 费率清单连接失败：网络离线；继续使用本地费率。"
        )
    }

    func testRemoteCannotRewritePublishedHistory() async {
        let bundled = manifest(inputRate: 100)
        let rewritten = manifest(inputRate: 999)
        let client = RateClientStub(result: .modified(rewritten, CacheValidators(etag: "bad")))
        let repository = RateCardRepository(
            bundledManifest: bundled,
            client: client,
            store: RateStoreStub(stored: nil)
        )

        let state = await repository.refresh()

        XCTAssertEqual(state.manifest, bundled)
        XCTAssertNotNil(state.errorMessage)
    }

    func testBundledGenerationDateControlsSevenDayStaleStatus() {
        let state = RateCardRepositoryState(
            manifest: manifest(inputRate: 100),
            source: .bundled,
            fetchedAt: nil,
            validators: CacheValidators(),
            errorMessage: nil
        )
        XCTAssertFalse(state.isStale(now: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertTrue(
            state.isStale(
                now: Date(timeIntervalSince1970: 1_800_000_000 + 8 * 86_400)
            )
        )
    }

    private func manifest(inputRate: Double) -> RateCardManifest {
        let generated = Date(timeIntervalSince1970: 1_800_000_000)
            .formatted(.iso8601)
        return RateCardManifest(
            schema: 1,
            currentVersion: "v1",
            generatedAt: generated,
            sources: ["official"],
            versions: [
                RateCardVersion(
                    id: "v1",
                    effectiveAt: generated,
                    models: [
                        ModelTokenRate(
                            id: "model",
                            aliases: ["model"],
                            inputCreditsPerMillion: inputRate,
                            cachedInputCreditsPerMillion: 1,
                            outputCreditsPerMillion: 2
                        )
                    ],
                    fastMultipliers: [],
                    legacyModels: []
                )
            ]
        )
    }
}

actor CostRefreshTestGate {
    private var requested = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var response: CheckedContinuation<Void, Never>?
    func block() async {
        requested = true
        waiters.forEach { $0.resume() }; waiters = []
        await withCheckedContinuation { response = $0 }
    }
    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { response?.resume(); response = nil }
}
private struct SuspendedRateClient: RateCardReading {
    let gate: CostRefreshTestGate
    func fetch(cacheValidators: CacheValidators?) async throws -> RateCardFetchResult {
        await gate.block()
        return .notModified(CacheValidators())
    }
}

private actor RateClientStub: RateCardReading {
    let result: RateCardFetchResult
    init(result: RateCardFetchResult) { self.result = result }
    func fetch(cacheValidators: CacheValidators?) async throws -> RateCardFetchResult { result }
}

private actor RateStoreStub: RateCardStoring {
    private var stored: StoredRateCard?
    init(stored: StoredRateCard?) { self.stored = stored }
    func load() async throws -> StoredRateCard? { stored }
    func save(_ card: StoredRateCard) async throws { stored = card }
}
