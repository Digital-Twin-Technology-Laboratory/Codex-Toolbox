import Foundation
import XCTest
@testable import CodexToolboxCore

final class TrendPointTests: XCTestCase {
    func testSameDaySnapshotsKeepLatestValidISOTimestampIndependentOfInputOrder() {
        let model = ModelBenchmark(
            id: "model",
            label: "Model",
            model: "model",
            reasoningEffort: "high",
            latest: nil,
            recentDays: [
                record("2026-07-12T21:00:00+08:00", score: 120, duration: 170),
                record("2026-07-12T09:00:00+08:00", score: 90, duration: 200),
                record("2026-07-12T13:00:00+08:00", score: .infinity, duration: 180)
            ]
        )

        let points = TrendPointBuilder.points(
            benchmarks: [model],
            costHistory: [],
            metric: .iq,
            modelIDs: ["model"],
            calendar: utcCalendar
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.dateKey, "2026-07-12T21:00:00+08:00")
        XCTAssertEqual(points.first?.value, 120)
        XCTAssertEqual(points.first?.recordedAt, date(2026, 7, 12, hour: 13))
        XCTAssertNotNil(points.first?.day)
    }

    func testProjectedDatesAreChronologicalRegardlessOfSourceOrder() {
        let model = ModelBenchmark(
            id: "model",
            label: "Model",
            model: "model",
            reasoningEffort: "high",
            latest: nil,
            recentDays: [
                record("2026-07-14T09:00:00Z", score: 114, duration: 170),
                record("2026-07-12T09:00:00Z", score: 112, duration: 180),
                record("2026-07-13T09:00:00Z", score: 113, duration: 175)
            ]
        )

        let points = TrendPointBuilder.points(
            benchmarks: [model],
            costHistory: [],
            metric: .iq,
            modelIDs: ["model"],
            calendar: utcCalendar
        )

        XCTAssertEqual(points.map(\.dateKey), [
            "2026-07-12T09:00:00Z",
            "2026-07-13T09:00:00Z",
            "2026-07-14T09:00:00Z"
        ])
    }

    func testLegacyAMPMRecordsShareADayAndKeepPMObservation() {
        let model = ModelBenchmark(
            id: "model",
            label: "Model",
            model: "model",
            reasoningEffort: "high",
            latest: nil,
            recentDays: [
                record("2026-07-12-pm", score: 120, duration: 170),
                record("2026-07-12-am", score: 90, duration: 200)
            ]
        )

        let points = TrendPointBuilder.points(
            benchmarks: [model],
            costHistory: [],
            metric: .iq,
            modelIDs: ["model"],
            calendar: utcCalendar
        )

        XCTAssertEqual(points.map(\.dateKey), ["2026-07-12-pm"])
        XCTAssertEqual(points.first?.value, 120)
    }

    func testCostTrendPrefersPublishedAverageHistory() {
        let model = ModelBenchmark(
            id: "model",
            label: "Model",
            model: "model",
            reasoningEffort: "high",
            latest: nil,
            recentDays: [
                record("2026-08-01T13:23:26+08:00", score: 100, duration: 200, cost: 1.25),
                record("2026-08-02T13:23:26+08:00", score: 110, duration: 180, cost: 1.50)
            ]
        )
        let history = [
            CostHistoryPoint(modelID: "model", dateKey: "local", costUSD: 999, recordedAt: Date())
        ]

        let points = TrendPointBuilder.points(
            benchmarks: [model],
            costHistory: history,
            metric: .cost,
            modelIDs: ["model"],
            calendar: utcCalendar
        )

        XCTAssertEqual(points.map(\.value), [1.25, 1.50])
        XCTAssertEqual(points.map(\.dateKey), [
            "2026-08-01T13:23:26+08:00",
            "2026-08-02T13:23:26+08:00"
        ])
        XCTAssertTrue(TrendPointBuilder.hasDrawableSeries(points, calendar: utcCalendar))
    }

    func testCostTrendFallsBackToLocalHistoryOnlyWhenRemoteCostIsAbsent() {
        let model = ModelBenchmark(
            id: "model",
            label: "Model",
            model: "model",
            reasoningEffort: "high",
            latest: nil,
            recentDays: [record("2026-08-02T13:23:26+08:00", score: 100, duration: 200)]
        )
        let history = [
            CostHistoryPoint(
                modelID: "model",
                dateKey: "day-1",
                costUSD: 2,
                recordedAt: date(2026, 8, 1, hour: 8)
            ),
            CostHistoryPoint(
                modelID: "model",
                dateKey: "day-1-late",
                costUSD: 2.5,
                recordedAt: date(2026, 8, 1, hour: 20)
            ),
            CostHistoryPoint(
                modelID: "model",
                dateKey: "day-2",
                costUSD: 3,
                recordedAt: date(2026, 8, 2, hour: 12)
            )
        ]

        let points = TrendPointBuilder.points(
            benchmarks: [model],
            costHistory: history,
            metric: .cost,
            modelIDs: ["model"],
            calendar: utcCalendar
        )

        XCTAssertEqual(points.map(\.value), [2.5, 3])
        XCTAssertEqual(points.map(\.dateKey), ["day-1-late", "day-2"])
    }

    func testRecentRangeAggregatesFirstAndKeepsSevenCalendarDays() {
        let points = (0..<8).flatMap { dayOffset -> [TrendPoint] in
            let day = date(2026, 7, 11 + dayOffset, hour: 9)
            return [
                TrendPoint(
                    modelID: "model",
                    modelLabel: "Model",
                    dateKey: "early-\(dayOffset)",
                    sequence: dayOffset * 2,
                    value: Double(dayOffset),
                    recordedAt: day
                ),
                TrendPoint(
                    modelID: "model",
                    modelLabel: "Model",
                    dateKey: "late-\(dayOffset)",
                    sequence: dayOffset * 2 + 1,
                    value: Double(dayOffset) + 0.5,
                    recordedAt: date(2026, 7, 11 + dayOffset, hour: 20)
                )
            ]
        }

        let recent = TrendPointBuilder.recentPoints(
            points,
            days: 7,
            now: date(2026, 7, 18, hour: 12),
            calendar: utcCalendar
        )

        XCTAssertEqual(recent.count, 7)
        XCTAssertEqual(recent.map(\.dateKey), [
            "late-1", "late-2", "late-3", "late-4", "late-5", "late-6", "late-7"
        ])
        XCTAssertEqual(recent.first?.day, date(2026, 7, 12))
        XCTAssertEqual(recent.last?.day, date(2026, 7, 18))
    }

    func testAxisDaysAndNearestDayUseDailyDateValues() {
        let points = (0..<7).map { offset in
            TrendPoint(
                modelID: "model",
                modelLabel: "Model",
                dateKey: "day-\(offset)",
                sequence: offset,
                value: Double(offset),
                recordedAt: date(2026, 7, 12 + offset, hour: 12)
            )
        }

        let axis = TrendPointBuilder.axisDays(points, maximumCount: 4, calendar: utcCalendar)

        XCTAssertEqual(axis.count, 4)
        XCTAssertEqual(axis.first, date(2026, 7, 12))
        XCTAssertEqual(axis.last, date(2026, 7, 18))
        XCTAssertEqual(
            TrendPointBuilder.nearestDay(
                to: date(2026, 7, 16, hour: 18),
                in: points,
                calendar: utcCalendar
            ),
            date(2026, 7, 17)
        )
    }

    func testSingleOrUndatedPointIsNotDrawable() {
        XCTAssertFalse(TrendPointBuilder.hasDrawableSeries([
            TrendPoint(modelID: "one", modelLabel: "One", dateKey: "day", sequence: 0, value: 1)
        ], calendar: utcCalendar))
    }

    func testOverallMetricDoesNotCreateTrendPoints() {
        let model = ModelBenchmark(
            id: "model",
            label: "Model",
            model: "model",
            reasoningEffort: "high",
            latest: nil,
            recentDays: [record("2026-07-12T09:00:00Z", score: 100, duration: 180)]
        )

        XCTAssertTrue(
            TrendPointBuilder.points(
                benchmarks: [model],
                costHistory: [],
                metric: .overall,
                modelIDs: ["model"],
                calendar: utcCalendar
            ).isEmpty
        )
    }

    func testShortDateLabelFormatsPublishedISOTimestamp() {
        XCTAssertEqual(
            TrendPointBuilder.shortDateLabel("2026-08-02T13:23:26+08:00"),
            "08/02 13:23"
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func record(
        _ date: String,
        score: Double,
        duration: Double,
        cost: Double? = nil
    ) -> BenchmarkRecord {
        BenchmarkRecord(
            date: date,
            score: score,
            status: nil,
            passed: nil,
            tasks: nil,
            wallSeconds: duration,
            costUSD: cost
        )
    }
}
