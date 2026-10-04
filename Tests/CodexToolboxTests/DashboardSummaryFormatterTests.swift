import Foundation
import XCTest
@testable import CodexToolboxCore

final class DashboardSummaryFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_158_400)

    private func window(_ minutes: Int, used: Double = 30, expiresIn: TimeInterval = 600) -> AccountQuotaWindow {
        AccountQuotaWindow(durationMinutes: minutes, usedPercent: used, resetsAt: now.addingTimeInterval(expiresIn))
    }

    private func account(_ windows: [AccountQuotaWindow], cards: Int = 2, stale: Bool = false) -> String {
        DashboardSummaryFormatter.account(
            ResetCreditsSnapshot(availableCount: cards, credits: [], quotaWindows: windows, planType: "prolite", fetchedAt: now),
            isLoading: false, isStale: stale, now: now
        )
    }

    private func usage(tokens: Int64, complete: Bool = true, cost: Decimal? = nil, showsCost: Bool = false) -> String {
        DashboardSummaryFormatter.usage(
            DailyUsageSummary(dateKey: "2026-10-05", totalTokens: tokens, totalCostUSD: cost, tasks: [], isComplete: complete),
            isLoading: false, showsCost: showsCost
        )
    }

    func testNoDailyRecordIsDistinctFromRecordedZeroAndLoading() {
        XCTAssertEqual(DashboardSummaryFormatter.usage(nil, isLoading: false, showsCost: true), "今日暂无数据")
        XCTAssertEqual(DashboardSummaryFormatter.usage(nil, isLoading: true, showsCost: false), "正在读取…")
        XCTAssertEqual(usage(tokens: 0), "今日 0")
    }

    func testDailyUsagePreservesIncompleteAndOptionalCost() {
        XCTAssertEqual(usage(tokens: 42), "今日 42")
        XCTAssertEqual(usage(tokens: 42, complete: false), "今日 42 · 不完整")
        XCTAssertEqual(usage(tokens: 42, cost: 2, showsCost: false), "今日 42")
        XCTAssertEqual(usage(tokens: 42, complete: false, cost: 2, showsCost: true), "今日 42 · $2.00 · 不完整")
        XCTAssertEqual(usage(tokens: 42, showsCost: true), "今日 42")
    }

    func testWeeklyWindowWinsOverFiveHourAndOtherWindows() {
        XCTAssertEqual(account([window(10_080)]), "周70% · 重置卡 2 张")
        XCTAssertEqual(account([window(300, used: 80), window(10_080)]), "周70% · 重置卡 2 张")
        XCTAssertEqual(account([window(60, used: 90), window(10_080), window(300)]), "周70% · 重置卡 2 张")
    }

    func testFiveHourThenActualOtherWindowFallback() {
        XCTAssertEqual(account([window(300)]), "5小时70% · 重置卡 2 张")
        XCTAssertEqual(account([window(60, used: 90), window(300)]), "5小时70% · 重置卡 2 张")
        XCTAssertEqual(account([window(1_440)]), "1天70% · 重置卡 2 张")
    }

    func testExpiredPreferredWindowNeverShowsOldPercentageOrAnotherWindow() {
        XCTAssertEqual(account([window(10_080, expiresIn: -1)]), "额度待更新 · 重置卡 2 张")
        XCTAssertEqual(account([window(10_080, expiresIn: 0), window(300)]), "额度待更新 · 重置卡 2 张")
    }

    func testMissingWindowCacheAndLoadingRemainExplicit() {
        XCTAssertEqual(account([]), "额度暂无数据 · 重置卡 2 张")
        XCTAssertEqual(account([window(10_080)], stale: true), "周70% · 重置卡 2 张 · 缓存")
        XCTAssertEqual(account([window(10_080, expiresIn: -1)], stale: true), "额度待更新 · 重置卡 2 张 · 缓存")
        XCTAssertEqual(DashboardSummaryFormatter.account(nil, isLoading: false, isStale: false, now: now), "暂无数据")
        XCTAssertEqual(DashboardSummaryFormatter.account(nil, isLoading: true, isStale: false, now: now), "正在读取…")
    }

    func testRemainingPercentBoundariesAndZeroCards() {
        XCTAssertEqual(account([window(10_080, used: 100)], cards: 0), "周0% · 重置卡 0 张")
        XCTAssertEqual(account([window(10_080, used: 0)]), "周100% · 重置卡 2 张")
        let percent = DashboardSummaryFormatter.remainingPercent(69.26)
        XCTAssertEqual(percent, 69.3.formatted(.number.precision(.fractionLength(0...1))) + "%")
        XCTAssertEqual(account([window(10_080, used: 30.74)]), "周\(percent) · 重置卡 2 张")
    }
}
