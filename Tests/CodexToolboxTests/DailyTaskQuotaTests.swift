import Foundation
import XCTest
@testable import CodexToolboxCore

final class DailyTaskQuotaTests: XCTestCase, @unchecked Sendable {
    private let base = MetricFormatter.sourceDate("2026-10-03T16:00:00Z")!
    private func row(_ weekly: Double?, _ five: Double? = nil, status: String = "available") -> NativeTaskUsageRow {
        NativeTaskUsageRow(id: "root", status: status, usageSource: "included_plan", fiveHourPercent: five, weeklyPercent: weekly, groups: [])
    }
    private func sample(_ minutes: Double, _ weekly: Double?, _ five: Double? = nil, birth: Double = -1440,
                        asOf: Double? = nil, account: String = "a", plan: String = "pro", continuity: String = "run",
                        children: [String] = [], earliest: Double? = nil, status: String = "available") -> NativeTaskQuotaSnapshot {
        NativeTaskQuotaSnapshot(accountKey: account,
            thread: NativeThread(id: "root", title: "Task", createdAt: base.addingTimeInterval(birth * 60).ISO8601Format(),
                descendantIDs: children, earliestCreatedAt: earliest.map { base.addingTimeInterval($0 * 60).ISO8601Format() }),
            row: row(weekly, five, status: status), collectedAt: base.addingTimeInterval(minutes * 60),
            dataAsOf: asOf.map { base.addingTimeInterval($0 * 60) }, planType: plan,
            timezoneIdentifier: "Asia/Shanghai", continuityID: continuity)
    }
    private func local(_ minutes: Double, _ tokens: Int64, account: String? = nil, api: Bool = false) -> LocalQuotaUsageObservation {
        LocalQuotaUsageObservation(timestamp: base.addingTimeInterval(minutes * 60), rootTaskID: "root", tokenIncrement: tokens,
            accountKey: account, executionContext: UsageExecutionContext(modelID: "model", reasoningEffort: "high", serviceTier: "default", authenticationMode: api ? .api : .chatGPT), windows: [])
    }
    private func history(_ rows: [LocalQuotaUsageObservation] = [], days: [String] = ["2026-10-04"]) -> UsageHistory {
        let tasks = days.map { day in
            let tokens = rows.filter { ($0.timestamp >= base) == (day == "2026-10-04") }.reduce(Int64(0)) { $0 + $1.tokenIncrement }
            return DailyUsageSummary(dateKey: day, totalTokens: tokens,
                tasks: [DailyTaskUsage(dateKey: day, rootTaskID: "root", title: "Task", tokens: tokens, descendantCount: 0)], isComplete: true)
        }
        return UsageHistory(generatedAt: base.addingTimeInterval(400 * 60), timezoneIdentifier: "Asia/Shanghai", days: tasks, quotaObservations: rows)
    }
    private func analyze(_ samples: [NativeTaskQuotaSnapshot], rows: [LocalQuotaUsageObservation] = [], now: Double = 400,
                         days: [String] = ["2026-10-04"]) -> [Int: [String: DailyTaskQuotaValue]] {
        DailyTaskQuotaAnalyzer.values(history: history(rows, days: days), snapshots: samples, accountKey: "a", now: base.addingTimeInterval(now * 60))
    }
    func testNewSameDayTaskUsesExactNativeValuesAboveOneHundred() throws {
        let values = analyze([sample(10, 125, 230, birth: 2)])
        XCTAssertEqual(values[10080]?["2026-10-04|root"]?.percent, 125)
        XCTAssertEqual(values[300]?["2026-10-04|root"]?.comparison, "=")
    }
    func testFirstOldTaskSampleIsBaselineNotTodayUsageOrZero() {
        XCTAssertTrue(analyze([sample(10, 70)]).isEmpty)
    }
    func testPartialOrdinaryDeltaAndIndependentMetricAvailability() throws {
        let value = try XCTUnwrap(analyze([sample(10, 70), sample(15, 73)])[10080]?["2026-10-04|root"])
        XCTAssertEqual(value.percent, 3); XCTAssertFalse(value.isExact)
        XCTAssertNil(analyze([sample(10, 70), sample(15, 73)])[300])
    }
    func testBoundaryCoveredDifferenceUsesEqualsWithoutTokenCostDependency() throws {
        let value = try XCTUnwrap(analyze([sample(0, 70, asOf: 0), sample(5, 73, asOf: 5)], now: 5)[10080]?["2026-10-04|root"])
        XCTAssertEqual(value.percent, 3); XCTAssertTrue(value.isExact)
    }
    func testLateCrossDayDeltaIsNotAssignedEntirelyToToday() {
        XCTAssertTrue(analyze([sample(-5, 70, asOf: -5), sample(5, 80, asOf: 5)]).isEmpty)
        let lagged = analyze([sample(5, 70, birth: -2880, asOf: -10), sample(10, 80, birth: -2880, asOf: -5)], days: ["2026-10-03", "2026-10-04"])
        XCTAssertNil(lagged[10080]?["2026-10-04|root"])
        XCTAssertEqual(lagged[10080]?["2026-10-03|root"]?.percent, 10)
    }
    func testCorrectionsPlanChangesScopeChangesAndSleepRebase() {
        for samples in [
            [sample(10, 70), sample(15, 60)],
            [sample(10, 70), sample(15, 80, plan: "plus")],
            [sample(10, 70), sample(15, 80, continuity: "wake")],
            [sample(10, 70), sample(15, 80, children: ["child"])],
            [sample(10, 70), sample(40, 80)],
            [sample(10, 70, asOf: 10), sample(15, 80, asOf: 5)]
        ] { XCTAssertTrue(analyze(samples).isEmpty) }
        let rebased = analyze([sample(10, 70), sample(15, 60), sample(20, 62)])
        XCTAssertEqual(rebased[10080]?["2026-10-04|root"]?.percent, 2)
    }
    func testRebaseDoesNotReuseDeltasFromBeforeCorrectionOrPlanChange() {
        let before = [sample(0, 70), sample(5, 73)]
        XCTAssertTrue(analyze(before + [sample(10, 60)]).isEmpty)
        XCTAssertEqual(analyze(before + [sample(10, 60), sample(15, 62)])[10080]?["2026-10-04|root"]?.percent, 2)
        XCTAssertEqual(analyze(before + [sample(10, 60, plan: "plus"), sample(15, 62, plan: "plus")])[10080]?["2026-10-04|root"]?.percent, 2)
    }
    func testOldDescendantAndPartialNativeStatusPreventExactValue() {
        XCTAssertTrue(analyze([sample(10, 10, birth: 2, children: ["child"], earliest: -10)]).isEmpty)
        XCTAssertTrue(analyze([sample(10, 10, birth: 2, status: "partial")]).isEmpty)
    }
    func testHistoricalDayRemainsAvailableAfterQuotaReset() {
        let result = analyze([sample(0, 70), sample(5, 72)], now: 3000)
        XCTAssertEqual(result[10080]?["2026-10-04|root"]?.percent, 2)
    }
    func testNativeStepsCalibrateUncoveredLocalDayWithoutBackfillingIdentity() throws {
        let rows = [local(2, 100), local(10, 100)]
        let result = analyze([sample(0, 50), sample(5, 51)], rows: rows)
        let value = try XCTUnwrap(result[10080]?["2026-10-04|root"])
        XCTAssertEqual(value.percent, 2); XCTAssertFalse(value.isExact)
        XCTAssertTrue(rows.allSatisfy { $0.accountKey == nil })
        let apiMixed = analyze([sample(0, 50), sample(5, 51)], rows: [local(2, 100), local(10, 100, api: true)])
        XCTAssertEqual(apiMixed[10080]?["2026-10-04|root"]?.percent, 1)
    }
    func testAnotherAccountCannotSupplySnapshotOrCalibration() {
        XCTAssertTrue(analyze([sample(1, 10, birth: 0, account: "b")]).isEmpty)
        XCTAssertTrue(analyze([sample(0, 50, account: "b"), sample(5, 51, account: "b")], rows: [local(2, 100)]).isEmpty)
    }
    func testUnavailableRefreshRetainsSameAccountNativeRecordAsOfItsTimestamp() {
        let result = analyze([sample(5, 10, birth: 1), sample(10, nil, birth: 1, status: "unavailable")])
        XCTAssertEqual(result[10080]?["2026-10-04|root"]?.percent, 10)
        XCTAssertEqual(result[10080]?["2026-10-04|root"]?.updatedAt, base.addingTimeInterval(300))
    }
    func testRemainderRequiresEveryTaskAndCombinesPrecisionConservatively() {
        let exact = DailyTaskQuotaValue(percent: 3, isExact: true, updatedAt: base, help: "source")
        let inferred = DailyTaskQuotaValue(percent: 2, isExact: false, updatedAt: base, help: "estimate")
        XCTAssertNil(DailyTaskQuotaValue.combined([exact, nil]))
        XCTAssertEqual(DailyTaskQuotaValue.combined([exact, inferred])?.percent, 5)
        XCTAssertEqual(DailyTaskQuotaValue.combined([exact, inferred])?.comparison, "≈")
    }
    func testJournalSeparatesAccountsAndDeduplicatesIdenticalSamples() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("quota.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = NativeTaskQuotaStore(fileURL: url)
        let a = sample(5, 10), b = sample(5, 20, account: "b")
        try await store.append([a, a, b], now: base.addingTimeInterval(3600))
        let storedA = try await store.snapshots(accountKey: "a"), storedB = try await store.snapshots(accountKey: "b")
        XCTAssertEqual(storedA, [a]); XCTAssertEqual(storedB, [b])
        let fractional = sample(5.123456, 12, asOf: 4.987654)
        try await store.append([fractional], now: base.addingTimeInterval(3600))
        try await store.append([fractional], now: base.addingTimeInterval(3600))
        let roundTrip = try await store.snapshots(accountKey: "a")
        XCTAssertEqual(roundTrip, [a, fractional])
    }
    func testDailyLegacyCalibrationUsesRawTokensAndDoesNotCapToCurrentUsage() throws {
        let reset = base.addingTimeInterval(7 * 86400)
        func observation(_ minute: Double, _ tokens: Int64, _ used: Double, priced: Bool) -> LocalQuotaUsageObservation {
            LocalQuotaUsageObservation(timestamp: base.addingTimeInterval(minute * 60), rootTaskID: "root",
                tokenIncrement: tokens, accountKey: "a", quotaUsageWeight: priced ? 999 : nil,
                executionContext: UsageExecutionContext(modelID: "model", reasoningEffort: "high", serviceTier: nil, authenticationMode: .chatGPT, planType: "pro"),
                creditEstimate: priced ? TokenCreditEstimate(credits: 1, precision: .exact, rateCardVersion: "price", modelRateID: "model") : nil,
                windows: [AccountQuotaWindow(durationMinutes: 10080, usedPercent: used, resetsAt: reset)])
        }
        func result(_ priced: Bool, now: Date) -> Double? {
            let rows = [observation(0, 0, 0, priced: priced), observation(5, 100, 1, priced: priced), observation(10, 10000, 1, priced: priced)]
            return TaskQuotaEstimator.dailyEstimates(history: history(rows), accountKey: "a", now: now)[10080]?["2026-10-04|root"]
        }
        let now = base.addingTimeInterval(1200)
        XCTAssertEqual(try XCTUnwrap(result(false, now: now)), 101, accuracy: 0.001)
        XCTAssertEqual(result(true, now: now), result(false, now: now))
        XCTAssertEqual(result(false, now: base.addingTimeInterval(8 * 86400)), result(false, now: now))
    }
    private func legacyRows(plan: String = "prolite", account: String? = nil, api: Bool = false,
                            resetOffset: TimeInterval = 0) -> [LocalQuotaUsageObservation] {
        let reset = base.addingTimeInterval(7 * 86400 + resetOffset)
        return [(0.0, Int64(0), 25.0), (5.0, Int64(100), 26.0), (10.0, Int64(10000), 26.0)].map { minute, tokens, percent in
            LocalQuotaUsageObservation(timestamp: base.addingTimeInterval(minute * 60), rootTaskID: "root",
                tokenIncrement: tokens, accountKey: account,
                executionContext: UsageExecutionContext(modelID: "gpt-6.1-sol", reasoningEffort: nil, serviceTier: nil, modelProviderID: "custom",
                    authenticationMode: api ? .api : nil, planType: plan, hasAccountRateLimits: true),
                windows: [AccountQuotaWindow(durationMinutes: 10080, usedPercent: percent, resetsAt: reset)])
        }
    }
    private func verifiedQuota(at minutes: Double = 20, plan: String = "prolite", fiveHour: Bool = false) -> ResetCreditsSnapshot {
        var windows = [AccountQuotaWindow(durationMinutes: 10080, usedPercent: 26, resetsAt: base.addingTimeInterval(7 * 86400))]
        if fiveHour { windows.append(AccountQuotaWindow(durationMinutes: 300, usedPercent: 10, resetsAt: base.addingTimeInterval(300 * 60))) }
        return ResetCreditsSnapshot(availableCount: 2, credits: [], quotaWindows: windows, planType: plan,
                                    fetchedAt: base.addingTimeInterval(minutes * 60))
    }
    func testActualAccountWindowsControlSupportedMetricsEvenAfterReset() {
        XCTAssertEqual(TaskQuotaMetric.supported(by: verifiedQuota().quotaWindows), [.weekly])
        XCTAssertEqual(TaskQuotaMetric.supported(by: verifiedQuota(fiveHour: true).quotaWindows), [.weekly, .fiveHour])
        XCTAssertEqual(TaskQuotaMetric.supported(by: []), [])
        XCTAssertEqual(TaskQuotaMetric.supported(by: verifiedQuota(at: 8 * 1440).quotaWindows), [.weekly])
    }
    func testUnattributedLegacyContextRestoresWeeklyFallbackWithoutBackfillingAccount() throws {
        let rows = legacyRows()
        let result = TaskQuotaEstimator.dailyEstimates(history: history(rows), accountKey: "a",
            now: base.addingTimeInterval(1200), accountSnapshot: verifiedQuota())
        XCTAssertEqual(try XCTUnwrap(result[10080]?["2026-10-04|root"]), 101, accuracy: 0.001)
        XCTAssertNil(result[300])
        XCTAssertTrue(rows.allSatisfy { $0.accountKey == nil && $0.executionContext?.authenticationMode == nil })
    }
    func testDelayedOrUnavailableNativeReportDoesNotBlockLegacyFallback() throws {
        let rows = legacyRows()
        let snapshots = [sample(10, 4, asOf: -1500), sample(15, nil, status: "unavailable")]
        XCTAssertNil(analyze(snapshots, rows: rows)[10080]?["2026-10-04|root"])
        let fallback = TaskQuotaEstimator.dailyEstimates(history: history(rows), accountKey: "a",
            now: base.addingTimeInterval(1200), accountSnapshot: verifiedQuota())
        let percent = try XCTUnwrap(fallback[10080]?["2026-10-04|root"])
        XCTAssertEqual(DailyTaskQuotaValue(percent: percent, isExact: false, updatedAt: base, help: "legacy").comparison, "≈")
    }
    func testLegacyFallbackRejectsOtherAccountAPIWrongPlanAndWrongWindow() {
        for rows in [legacyRows(account: "b"), legacyRows(api: true), legacyRows(plan: "plus"), legacyRows(resetOffset: 3600)] {
            XCTAssertTrue(TaskQuotaEstimator.dailyEstimates(history: history(rows), accountKey: "a",
                now: base.addingTimeInterval(1200), accountSnapshot: verifiedQuota()).isEmpty)
        }
        XCTAssertTrue(TaskQuotaEstimator.dailyEstimates(history: history(legacyRows()), accountKey: "a",
            now: base.addingTimeInterval(1200)).isEmpty)
    }
    func testLegacyFallbackExcludesUnknownObservationsAroundRecordedAccountSwitches() {
        var h = history(legacyRows())
        for (minute, key) in [(-5.0, "a"), (6.0, "b"), (20.0, "a")] {
            let snapshot = verifiedQuota(at: minute)
            h = h.appendingAccountSnapshot(timestamp: snapshot.fetchedAt, planType: snapshot.planType,
                                          windows: snapshot.quotaWindows, accountKey: key)
        }
        XCTAssertTrue(TaskQuotaEstimator.dailyEstimates(history: h, accountKey: "a",
            now: base.addingTimeInterval(1800), accountSnapshot: verifiedQuota(at: 30)).isEmpty)
        XCTAssertTrue(TaskQuotaEstimator.dailyEstimates(history: history(legacyRows()), accountKey: "a",
            now: base.addingTimeInterval(1200), accountSnapshot: verifiedQuota(),
            unattributedSince: base.addingTimeInterval(15 * 60)).isEmpty)
    }
    func testAccountSessionOnlyBoundsUnknownQuotaHistoryAfterRealIdentityTransitions() {
        var session = AccountSession()
        session.observe(.chatGPT(accountKey: "a"), at: base)
        XCTAssertNil(session.unattributedQuotaSince)
        session.observe(.unknown, at: base.addingTimeInterval(1))
        session.observe(.chatGPT(accountKey: "a"), at: base.addingTimeInterval(2))
        XCTAssertNil(session.unattributedQuotaSince)
        let oldTicket = session.ticket!
        session.observe(.chatGPT(accountKey: "b"), at: base.addingTimeInterval(3))
        session.observe(.chatGPT(accountKey: "a"), at: base.addingTimeInterval(4))
        XCTAssertEqual(session.unattributedQuotaSince, base.addingTimeInterval(4))
        XCTAssertFalse(session.accepts(oldTicket))
        session.observe(.api, at: base.addingTimeInterval(5))
        XCTAssertEqual(session.unattributedQuotaSince, base.addingTimeInterval(5))
    }
    func testLegacyFallbackRetainsHistoricalDayAfterWindowReset() throws {
        let afterReset = base.addingTimeInterval(8 * 86400)
        let result = TaskQuotaEstimator.dailyEstimates(history: history(legacyRows()), accountKey: "a",
            now: afterReset, accountSnapshot: verifiedQuota(at: 8 * 1440))
        XCTAssertEqual(try XCTUnwrap(result[10080]?["2026-10-04|root"]), 101, accuracy: 0.001)
    }
    func testBatchBoundsRootCountAndTotalDescendantCount() {
        let roots = (0..<201).map { NativeThread(id: "\($0)", title: "", createdAt: nil, descendantIDs: []) }
        XCTAssertEqual(DailyTaskQuotaAnalyzer.batches(roots).map(\.count), [100, 100, 1])
        let big = NativeThread(id: "big", title: "", createdAt: nil, descendantIDs: (0..<999).map(String.init))
        XCTAssertEqual(DailyTaskQuotaAnalyzer.batches([big, roots[0]]).map(\.count), [1, 1])
    }
    func testReportRejectsInvalidSchemaNegativePercentAndFutureWatermark() throws {
        func data(_ percent: Double = 10, asOf: String? = nil, schema: Int = 3) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["schemaVersion":schema,"accountKey":String(repeating:"a",count:64),
                "collectedAt":"2026-10-04T01:00:00Z","dataAsOf":asOf as Any? ?? NSNull(),
                "threads":[["id":"root","status":"available","usageSource":"included_plan","weeklyPercent":percent,"groups":[]]]])
        }
        XCTAssertEqual(try NativeTaskUsageReport.decode(data()).threads.first?.weeklyPercent, 10)
        XCTAssertThrowsError(try NativeTaskUsageReport.decode(data(-1)))
        XCTAssertThrowsError(try NativeTaskUsageReport.decode(data(asOf:"2026-10-05T01:00:00Z")))
        XCTAssertThrowsError(try NativeTaskUsageReport.decode(data(schema:2)))
    }
}
