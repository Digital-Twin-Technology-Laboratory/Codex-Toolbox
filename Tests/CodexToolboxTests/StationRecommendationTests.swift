import Foundation
import XCTest
@testable import CodexToolboxCore

final class StationRecommendationTests: XCTestCase {
    func testDecodesKnownScenariosInStableOrderAndLimitsItems() throws {
        let payload = #"""
        {
          "schema": 1,
          "mode": "rolling_weighted_per_task",
          "generated_at": "2026-08-11T00:00:00Z",
          "source_updated_at": "2026-08-10T23:52:00Z",
          "recommendations": [
            {"key":"hard_problems","title":"困难任务","rule":"优先质量","items":[
              {"model":"gpt-5.6-sol","effort":"ultra","iq":104.6,"average_cost_usd":21.73,"average_duration_minutes":53},
              {"model":"gpt-5.6-sol","effort":"xhigh","iq":103.9,"average_cost_usd":6.28,"average_duration_minutes":26},
              {"model":"ignored","effort":"high","iq":1}
            ]},
            {"key":"daily_development","title":"日常开发","rule":"平衡质量与成本","items":[
              {"model":"gpt-5.6-sol","effort":"medium","iq":92.9,"average_cost_usd":3.58,"average_duration_minutes":17}
            ]},
            {"key":"lobster_tasks","title":"龙虾类任务","items":[
              {"model":"gpt-5.6-luna","effort":"high","iq":73.9,"average_cost_usd":0.20,"average_duration_minutes":17}
            ]},
            {"key":"background_automation","title":"后台自动化","items":[
              {"model":"gpt-5.6-luna","effort":"xhigh","iq":86.8,"average_cost_usd":0.31,"average_duration_minutes":24}
            ]},
            {"key":"future_scenario","title":"未来","items":[]}
          ]
        }
        """#

        let response = try JSONDecoder().decode(
            StationRecommendationResponse.self,
            from: Data(payload.utf8)
        )
        let snapshot = StationRecommendationSnapshot(
            schema: response.schema,
            mode: response.mode,
            generatedAt: response.generatedAt,
            sourceUpdatedAt: response.sourceUpdatedAt,
            fetchedAt: Date(timeIntervalSince1970: 1),
            scenarios: response.scenarios,
            validators: CacheValidators()
        )

        XCTAssertEqual(snapshot.scenarios.map(\.key), StationRecommendationScenarioKey.allCases)
        XCTAssertEqual(snapshot.scenario(for: .hardProblems)?.items.count, 2)
        XCTAssertEqual(snapshot.scenario(for: .hardProblems)?.items.first?.averageCostUSD, 21.73)
        XCTAssertEqual(
            StationRecommendationScenarioKey.allCases.map(\.shortTitle),
            ["日常", "困难", "后台", "龙虾"]
        )
    }

    func testSanitizesInvalidMetricsWithoutDroppingRecommendation() throws {
        let payload = #"{"schema":1,"mode":"test","recommendations":[{"key":"daily_development","title":"","items":[{"model":"gpt-5.6-luna","effort":"low","iq":null,"average_cost_usd":-1,"average_duration_minutes":-2}]}]}"#
        let response = try JSONDecoder().decode(
            StationRecommendationResponse.self,
            from: Data(payload.utf8)
        )
        let scenario = try XCTUnwrap(response.scenarios.first)

        XCTAssertEqual(scenario.title, "日常开发")
        XCTAssertNil(scenario.items.first?.averageCostUSD)
        XCTAssertNil(scenario.items.first?.averageDurationMinutes)
    }

    func testFailurePreservesLastSuccessfulRecommendationAndMarksItStale() async throws {
        let snapshot = sampleSnapshot()
        let store = StationStoreStub(snapshot: snapshot)
        let client = StationClientStub(behavior: .failure)
        let repository = StationRecommendationRepository(client: client, store: store)

        let cached = await repository.loadCached()
        let failed = await repository.refresh()

        XCTAssertEqual(cached.snapshot, snapshot)
        XCTAssertEqual(failed.snapshot, snapshot)
        XCTAssertTrue(failed.isStale)
        XCTAssertNotNil(failed.errorMessage)
        let requestCount = await client.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testOldCacheIsMarkedStaleWithoutStartingANetworkRequest() async {
        let snapshot = sampleSnapshot()
        let store = StationStoreStub(snapshot: snapshot)
        let client = StationClientStub(behavior: .failure)
        let repository = StationRecommendationRepository(
            client: client,
            store: store,
            now: { Date(timeIntervalSince1970: 2 * 24 * 60 * 60) }
        )

        let cached = await repository.loadCached()

        XCTAssertEqual(cached.snapshot, snapshot)
        XCTAssertTrue(cached.isStale)
        let requestCount = await client.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    private func sampleSnapshot() -> StationRecommendationSnapshot {
        StationRecommendationSnapshot(
            schema: 1,
            mode: "test",
            generatedAt: "2026-08-11T00:00:00Z",
            sourceUpdatedAt: "2026-08-11T00:00:00Z",
            fetchedAt: Date(timeIntervalSince1970: 1),
            scenarios: [
                StationRecommendationScenario(
                    key: .dailyDevelopment,
                    title: "日常开发",
                    rule: "平衡",
                    items: [
                        StationRecommendationItem(
                            model: "gpt-5.6-sol",
                            effort: "medium",
                            iq: 92,
                            averageCostUSD: 3,
                            averageDurationMinutes: 17,
                            rule: nil
                        )
                    ]
                )
            ],
            validators: CacheValidators(etag: "etag")
        )
    }
}

private actor StationStoreStub: StationRecommendationStoring {
    private var snapshot: StationRecommendationSnapshot?

    init(snapshot: StationRecommendationSnapshot?) {
        self.snapshot = snapshot
    }

    func load() async throws -> StationRecommendationSnapshot? { snapshot }
    func save(_ snapshot: StationRecommendationSnapshot) async throws { self.snapshot = snapshot }
}

private actor StationClientStub: StationRecommendationReading {
    enum Behavior: Sendable { case failure }
    private let behavior: Behavior
    private var requests = 0

    init(behavior: Behavior) { self.behavior = behavior }

    func fetch(cacheValidators: CacheValidators?) async throws -> StationRecommendationFetchResult {
        requests += 1
        switch behavior {
        case .failure:
            throw StationRecommendationClientError.httpStatus(503)
        }
    }

    func requestCount() -> Int { requests }
}
