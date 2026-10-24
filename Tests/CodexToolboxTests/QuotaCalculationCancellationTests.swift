import Foundation
import XCTest
@testable import CodexToolboxCore

final class QuotaCalculationCancellationTests: XCTestCase, @unchecked Sendable {
    private let base = Date(timeIntervalSince1970: 1_791_043_200)

    private func history() -> UsageHistory {
        let reset = base.addingTimeInterval(3600)
        let rows = (0..<3).map { index in
            LocalQuotaUsageObservation(timestamp: base.addingTimeInterval(Double(index * 60)), rootTaskID: "root",
                tokenIncrement: index == 0 ? 0 : 100, accountKey: "a",
                windows: [AccountQuotaWindow(durationMinutes: 300, usedPercent: Double(index), resetsAt: reset)])
        }
        return UsageHistory(generatedAt: base, timezoneIdentifier: "UTC", days: [], quotaObservations: rows)
    }

    func testCancelledHistoricalCalculationStopsWithoutPublishingPartialResults() async {
        let history = history(), now = base.addingTimeInterval(180)
        XCTAssertFalse(TaskQuotaEstimator.dailyEstimates(history: history, accountKey: "a", now: now).isEmpty)
        let task = Task.detached {
            try? await Task.sleep(for: .seconds(60))
            return TaskQuotaEstimator.dailyEstimates(history: history, accountKey: "a", now: now)
        }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.isEmpty)
    }

    func testAppendingAccountObservationPreservesOrderAndLocalActivity() {
        let history = history()
        let window = AccountQuotaWindow(durationMinutes: 300, usedPercent: 2, resetsAt: base.addingTimeInterval(3600))
        let updated = history.appendingAccountSnapshot(timestamp: base.addingTimeInterval(61), planType: "pro", windows: [window], accountKey: "a")
            .appendingAccountSnapshot(timestamp: base.addingTimeInterval(62), planType: "pro", windows: [window], accountKey: "a")
        XCTAssertEqual(updated.quotaObservations.count, 4)
        XCTAssertEqual(updated.quotaObservations.map(\.timestamp), [base, base.addingTimeInterval(60), base.addingTimeInterval(62), base.addingTimeInterval(120)])
        XCTAssertEqual(updated.lastLocalActivityAt, base.addingTimeInterval(120))
        XCTAssertEqual(history.quotaObservations.count, 3)
    }
}
