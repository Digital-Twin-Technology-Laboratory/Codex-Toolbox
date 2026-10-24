import Foundation
import XCTest
@testable import CodexToolboxCore

final class UsagePresentationTests: XCTestCase {
    func testProjectionKeepsDayAmountsAndEmptyChartSlotsAcrossMonthBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9)))
        let history = UsageHistory(generatedAt: now, timezoneIdentifier: calendar.timeZone.identifier,
            days: [DailyUsageSummary(dateKey: "2026-09-30", totalTokens: 123, totalCostUSD: Decimal(string: "1.25"),
                costPrecision: .lowerBound, tasks: [], isComplete: false),
                   DailyUsageSummary(dateKey: "2026-10-02", totalTokens: 456, tasks: [], isComplete: true)])
        let result = try UsagePresentation.prepare(history: history, now: now, calendar: calendar)
        XCTAssertEqual(result.trendPoints.count, 90)
        XCTAssertEqual(result.trendPoints.suffix(3).map(\.dateKey), ["2026-09-30", "2026-10-01", "2026-10-02"])
        XCTAssertEqual(result.trendPoints.suffix(3).map(\.tokens), [123, 0, 456])
        XCTAssertEqual(result.trendPoints.suffix(3).first?.costUSD, 1.25)
        XCTAssertEqual(result.trendPoints.suffix(3).first?.costPrecision, .lowerBound)
        XCTAssertNil(result.summariesByDay["2026-10-01"])
        XCTAssertEqual(result.summariesByDay["2026-09-30"]?.isComplete, false)
        XCTAssertEqual(result.timezoneIdentifier, "Asia/Shanghai")
    }
}
