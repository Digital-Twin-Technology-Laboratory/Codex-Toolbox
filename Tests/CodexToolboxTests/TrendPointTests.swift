import Foundation
import XCTest
@testable import CodexToolboxCore

final class TrendPointTests: XCTestCase {
    func testRemoteTrendPreservesSourceOrderAndDeduplicatesDates() {
        let model = ModelBenchmark(
            id: "model",
            label: "Model",
            model: "model",
            reasoningEffort: "high",
            latest: nil,
            recentDays: [
                record("2026-07-12-pm", score: 90, duration: 200),
                record("2026-07-13-am", score: 105, duration: 180),
                record("2026-07-13-am", score: 120, duration: 170)
            ]
        )

        let points = TrendPointBuilder.points(
            benchmarks: [model],
            costHistory: [],
            metric: .iq,
            modelIDs: ["model"]
        )

        XCTAssertEqual(points.map(\.dateKey), ["2026-07-12-pm", "2026-07-13-am"])
        XCTAssertEqual(points.last?.value, 120)
    }

    func testCostTrendUsesOnlyLocallyRecordedPoints() {
        let model = ModelBenchmark(
            id: "model",
            label: "Model",
            model: "model",
            reasoningEffort: "high",
            latest: nil,
            recentDays: [record("remote", score: 100, duration: 200)]
        )
        let history = [
            CostHistoryPoint(modelID: "model", dateKey: "day-1", costUSD: 2, recordedAt: .distantPast),
            CostHistoryPoint(modelID: "model", dateKey: "day-2", costUSD: 3, recordedAt: Date())
        ]

        let points = TrendPointBuilder.points(
            benchmarks: [model],
            costHistory: history,
            metric: .cost,
            modelIDs: ["model"]
        )

        XCTAssertEqual(points.map(\.value), [2, 3])
        XCTAssertTrue(TrendPointBuilder.hasDrawableSeries(points))
    }

    func testSinglePointIsNotDrawable() {
        XCTAssertFalse(TrendPointBuilder.hasDrawableSeries([
            TrendPoint(modelID: "one", modelLabel: "One", dateKey: "day", sequence: 0, value: 1)
        ]))
    }

    private func record(_ date: String, score: Double, duration: Double) -> BenchmarkRecord {
        BenchmarkRecord(
            date: date,
            score: score,
            status: nil,
            passed: nil,
            tasks: nil,
            wallSeconds: duration,
            costUSD: nil
        )
    }
}
