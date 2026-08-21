import Foundation
@testable import CodexToolboxCore
import XCTest

final class RateCardRepositoryTests: XCTestCase {
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
