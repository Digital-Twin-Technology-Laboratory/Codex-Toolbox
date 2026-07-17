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
}
