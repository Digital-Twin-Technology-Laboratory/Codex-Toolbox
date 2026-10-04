import Foundation
import XCTest
@testable import CodexToolboxCore

final class NativeAnalyticsTests: XCTestCase, @unchecked Sendable {
    func testAuthenticationModesAndInvalidProtocolCannotReuseAnAccount() throws {
        func decode(_ mode: String, key: String? = nil) throws -> AccountAuthentication {
            try AccountAuthentication.decode(JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "authMode": mode, "accountKey": key as Any? ?? NSNull()]))
        }
        let key = String(repeating: "a", count: 64)
        XCTAssertEqual(try decode("chatGPT", key: key), .chatGPT(accountKey: key))
        XCTAssertEqual(try decode("api"), .api)
        XCTAssertEqual(try decode("signedOut"), .signedOut)
        XCTAssertEqual(try decode("unknown"), .unknown)
        XCTAssertThrowsError(try decode("api", key: key))
        XCTAssertThrowsError(try decode("chatGPT", key: "invalid"))
        XCTAssertThrowsError(try decode("new-mode"))
        XCTAssertThrowsError(try AccountAuthentication.decode(Data(#"{"schemaVersion":1,"accountKey":"a"}"#.utf8)))
    }
    func testAccountGenerationRejectsABAAndAPIAndLogoutResults() throws {
        var session = AccountSession()
        session.observe(.chatGPT(accountKey: "a"))
        let first = try XCTUnwrap(session.ticket)
        XCTAssertTrue(session.accepts(first))
        XCTAssertFalse(session.observe(.chatGPT(accountKey: "a")))
        session.observe(.chatGPT(accountKey: "b"))
        XCTAssertFalse(session.accepts(first))
        session.observe(.chatGPT(accountKey: "a"))
        XCTAssertFalse(session.accepts(first))
        for authentication in [AccountAuthentication.api, .signedOut, .unknown] {
            session.observe(authentication)
            XCTAssertNil(session.ticket)
            XCTAssertFalse(session.accepts(first))
        }
    }
    func testQuotaCalibrationRequiresWholeTaskDayAccountAttribution() throws {
        let start = try XCTUnwrap(MetricFormatter.sourceDate("2026-10-03T16:01:00Z"))
        let reset = start.addingTimeInterval(3600)
        let window = AccountQuotaWindow(durationMinutes: 10080, usedPercent: 3, resetsAt: reset)
        func row(_ offset: Double, _ tokens: Int64, _ percent: Double, _ key: String?) -> LocalQuotaUsageObservation {
            LocalQuotaUsageObservation(timestamp: start.addingTimeInterval(offset), rootTaskID: "shared", tokenIncrement: tokens,
                accountKey: key, windows: [AccountQuotaWindow(durationMinutes: 10080, usedPercent: percent, resetsAt: reset)])
        }
        let known = [row(0, 0, 0, "a"), row(10, 100, 1, "a"), row(20, 100, 2, "a")]
        func estimate(_ rows: [LocalQuotaUsageObservation]) -> [String: TaskQuotaEstimate] {
            let history = UsageHistory(generatedAt: start, timezoneIdentifier: "Asia/Shanghai", days: [], quotaObservations: rows)
            return TaskQuotaEstimator.estimates(history: history, window: window, now: start.addingTimeInterval(60), accountKey: "a")
        }
        XCTAssertNotNil(estimate(known)["2026-10-04|shared"])
        XCTAssertTrue(estimate(known + [row(30, 100, 3, "b")]).isEmpty)
        XCTAssertTrue(estimate(known + [row(30, 100, 3, nil)]).isEmpty)
    }

    func testQuotaCacheCannotLoadUnboundOrOtherAccount() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = ResetCreditsCacheStore(fileURL: url)
        let value = ResetCreditsSnapshot(availableCount: 1, credits: [], fetchedAt: Date())
        try await cache.save(value)
        let legacy = try await cache.load(accountKey: "a"); XCTAssertNil(legacy)
        try await cache.save(value, accountKey: "a")
        let same = try await cache.load(accountKey: "a"); XCTAssertNotNil(same)
        let other = try await cache.load(accountKey: "b"); XCTAssertNil(other)
    }
    func testAccountObservationsDoNotReplaceAnotherAccountsSameMinuteOrDailyTotals() throws {
        let now = Date()
        let window = AccountQuotaWindow(durationMinutes: 10080, usedPercent: 10, resetsAt: now.addingTimeInterval(100))
        let history = UsageHistory(generatedAt: now, timezoneIdentifier: "Asia/Shanghai", days: [], warnings: [])
            .appendingAccountSnapshot(timestamp: now, planType: "pro", windows: [window], accountKey: "a")
            .appendingAccountSnapshot(timestamp: now, planType: "pro", windows: [window], accountKey: "b")
        XCTAssertEqual(history.quotaObservations.count, 2)
        XCTAssertEqual(history.days, [])
        XCTAssertTrue(TaskQuotaEstimator.estimates(history: history, window: window, now: now, accountKey: "a").isEmpty)
    }
}
