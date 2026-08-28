import Foundation
import XCTest
@testable import CodexToolboxCore

final class RefreshSchedulerTests: XCTestCase {
    func testMissingRefreshIsImmediatelyDue() {
        XCTAssertTrue(RefreshPolicy.isRefreshDue(
            lastSuccessfulRefresh: nil,
            now: Date(),
            interval: .thirtyMinutes
        ))
    }

    func testRefreshBecomesDueAtSelectedInterval() {
        let last = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(RefreshPolicy.isRefreshDue(
            lastSuccessfulRefresh: last,
            now: last.addingTimeInterval(1_799),
            interval: .thirtyMinutes
        ))
        XCTAssertTrue(RefreshPolicy.isRefreshDue(
            lastSuccessfulRefresh: last,
            now: last.addingTimeInterval(1_800),
            interval: .thirtyMinutes
        ))
    }

    func testStopCancelsPendingWorkAndConfigureRestartsIt() async throws {
        let scheduler = RefreshScheduler()
        let counter = RefreshCounter()

        await scheduler.configure(enabled: true, every: .milliseconds(40)) {
            await counter.increment()
        }
        await scheduler.stop()
        try await Task.sleep(for: .milliseconds(70))
        let stoppedCount = await counter.value()
        XCTAssertEqual(stoppedCount, 0)

        await scheduler.configure(enabled: true, every: .milliseconds(10)) {
            await counter.increment()
        }
        try await Task.sleep(for: .milliseconds(35))
        await scheduler.stop()
        let restartedCount = await counter.value()
        XCTAssertGreaterThanOrEqual(restartedCount, 1)
    }
}

private actor RefreshCounter {
    private var count = 0

    func increment() { count += 1 }
    func value() -> Int { count }
}
