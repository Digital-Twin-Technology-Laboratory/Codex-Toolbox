import XCTest
@testable import CodexToolboxCore

final class RankingEngineTests: XCTestCase {
    func testSingleMetricRankingsUseCorrectDirection() {
        let models = [
            benchmark("quality", iq: 150, cost: 30, duration: 2000),
            benchmark("balanced", iq: 120, cost: 10, duration: 1000),
            benchmark("cheap", iq: 90, cost: 2, duration: 1500)
        ]

        XCTAssertEqual(RankingEngine.rank(models, by: .iq).map(\.id), ["quality", "balanced", "cheap"])
        XCTAssertEqual(RankingEngine.rank(models, by: .cost).map(\.id), ["cheap", "balanced", "quality"])
        XCTAssertEqual(RankingEngine.rank(models, by: .duration).map(\.id), ["balanced", "cheap", "quality"])
    }

    func testCustomWeightsChangeOverallRanking() {
        let models = [
            benchmark("quality", iq: 150, cost: 30, duration: 2000),
            benchmark("balanced", iq: 120, cost: 10, duration: 1000),
            benchmark("cheap", iq: 90, cost: 2, duration: 1500)
        ]

        let qualityFirst = RankingEngine.rank(
            models,
            by: .overall,
            weights: RankingWeights(iq: 100, cost: 0, duration: 0)
        )
        let costFirst = RankingEngine.rank(
            models,
            by: .overall,
            weights: RankingWeights(iq: 0, cost: 100, duration: 0)
        )

        XCTAssertEqual(qualityFirst.first?.id, "quality")
        XCTAssertEqual(costFirst.first?.id, "cheap")
    }

    func testTiesSharePercentileButOrderingIsStable() {
        let models = [
            benchmark("zeta", iq: 120, cost: 10, duration: 1000),
            benchmark("alpha", iq: 120, cost: 10, duration: 1000),
            benchmark("lower", iq: 90, cost: 20, duration: 2000)
        ]

        let iq = RankingEngine.rank(models, by: .iq)

        XCTAssertEqual(iq.map(\.id), ["alpha", "zeta", "lower"])
        XCTAssertEqual(iq[0].percentileScore, iq[1].percentileScore)
    }

    func testMissingCoreMetricIsExcludedOnlyWhereRequired() {
        let incomplete = benchmark("incomplete", iq: 150, cost: nil, duration: 800)
        let complete = benchmark("complete", iq: 120, cost: 5, duration: 1000)

        XCTAssertEqual(RankingEngine.rank([incomplete, complete], by: .iq).count, 2)
        XCTAssertEqual(RankingEngine.rank([incomplete, complete], by: .overall).map(\.id), ["complete"])
    }

    func testSingleCandidateReceivesFullPercentile() {
        let model = benchmark("only", iq: 100, cost: 10, duration: 1000)

        XCTAssertEqual(RankingEngine.rank([model], by: .overall).first?.percentileScore, 100)
    }

    private func benchmark(
        _ id: String,
        iq: Double?,
        cost: Double?,
        duration: Double?
    ) -> ModelBenchmark {
        ModelBenchmark(
            id: id,
            label: id,
            model: id,
            reasoningEffort: "high",
            latest: BenchmarkRecord(
                date: "2026-07-13-pm",
                score: iq,
                status: nil,
                passed: nil,
                tasks: nil,
                wallSeconds: duration,
                costUSD: cost
            ),
            recentDays: []
        )
    }
}
