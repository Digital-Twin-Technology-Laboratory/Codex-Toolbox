import Foundation
import XCTest
@testable import CodexToolboxCore

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsAndWeightValidation() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.menuBarMetric, .iq)
        XCTAssertEqual(settings.dashboardModuleOrder, ToolboxModule.allCases)
        XCTAssertTrue(settings.hiddenDashboardModules.isEmpty)
        XCTAssertTrue(settings.collapsedDashboardModules.isEmpty)
        XCTAssertEqual(settings.usageRefreshInterval, .fiveMinutes)
        XCTAssertEqual(settings.usageTrendRange, .sevenDays)
        XCTAssertFalse(settings.anonymizesTaskTitles)
        XCTAssertEqual(settings.resetCreditsRefreshInterval, .thirtyMinutes)
        XCTAssertEqual(settings.resetExpiryWarning, .threeDays)
        XCTAssertTrue(settings.showsResetCreditDescriptions)
        XCTAssertEqual(settings.menuBarRankStyle, .hidden)
        XCTAssertTrue(settings.showsMenuBarIcon)
        XCTAssertFalse(settings.showsMenuBarDetails)
        XCTAssertTrue(settings.menuBarModelAliases.isEmpty)
        XCTAssertTrue(settings.showsTrendChart)
        XCTAssertTrue(settings.showsDetailedBenchmarkTime)
        XCTAssertTrue(settings.automaticRefreshEnabled)
        XCTAssertEqual(settings.refreshInterval, .thirtyMinutes)
        XCTAssertEqual(settings.rankingWeights, .default)
        XCTAssertFalse(settings.apply(weights: RankingWeights(iq: 70, cost: 20, duration: 20)))
        XCTAssertEqual(settings.rankingWeights, .default)
        XCTAssertTrue(settings.apply(weights: RankingWeights(iq: 70, cost: 20, duration: 10)))
    }

    func testDashboardAndFeaturePreferencesPersist() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.moveDashboardModule(.resetCredits, to: 0)
        settings.setDashboardModule(.tokenUsage, isVisible: false)
        settings.setDashboardModule(.modelRadar, isCollapsed: true)
        settings.usageRefreshInterval = .oneMinute
        settings.usageTrendRange = .ninetyDays
        settings.anonymizesTaskTitles = true
        settings.resetCreditsRefreshInterval = .twoHours
        settings.resetExpiryWarning = .sevenDays
        settings.showsResetCreditDescriptions = false

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.dashboardModuleOrder, [.resetCredits, .modelRadar, .tokenUsage])
        XCTAssertEqual(restored.dashboardConfiguration.visibleModules, [.resetCredits, .modelRadar])
        XCTAssertTrue(restored.dashboardConfiguration.collapsedModules.contains(.modelRadar))
        XCTAssertEqual(restored.usageRefreshInterval, .oneMinute)
        XCTAssertEqual(restored.usageTrendRange, .ninetyDays)
        XCTAssertTrue(restored.anonymizesTaskTitles)
        XCTAssertEqual(restored.resetCreditsRefreshInterval, .twoHours)
        XCTAssertEqual(restored.resetExpiryWarning, .sevenDays)
        XCTAssertFalse(restored.showsResetCreditDescriptions)

        restored.resetDashboardConfiguration()
        XCTAssertEqual(restored.dashboardModuleOrder, ToolboxModule.allCases)
        XCTAssertTrue(restored.hiddenDashboardModules.isEmpty)
        XCTAssertTrue(restored.collapsedDashboardModules.isEmpty)
    }

    func testMenuBarDisplayPreferencesPersist() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.menuBarRankStyle = .ideographicComma
        settings.showsMenuBarIcon = false
        settings.showsMenuBarDetails = true
        settings.showsTrendChart = false
        settings.showsDetailedBenchmarkTime = false
        settings.setMenuBarModelAlias("  Sol xh  ", for: "gpt_56_sol_xhigh")

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.menuBarRankStyle, .ideographicComma)
        XCTAssertFalse(restored.showsMenuBarIcon)
        XCTAssertTrue(restored.showsMenuBarDetails)
        XCTAssertFalse(restored.showsTrendChart)
        XCTAssertFalse(restored.showsDetailedBenchmarkTime)
        XCTAssertEqual(restored.menuBarRankStyle.prefix(for: 2), "2、")
        XCTAssertEqual(restored.menuBarModelAlias(for: "gpt_56_sol_xhigh"), "Sol xh")
        XCTAssertEqual(
            restored.menuBarModelName(
                modelID: "gpt_56_sol_xhigh",
                fullName: "GPT-5.6 Sol xhigh"
            ),
            "Sol xh"
        )

        restored.setMenuBarModelAlias(" \n ", for: "gpt_56_sol_xhigh")
        XCTAssertEqual(restored.menuBarModelAlias(for: "gpt_56_sol_xhigh"), "")
        XCTAssertEqual(
            restored.menuBarModelName(
                modelID: "gpt_56_sol_xhigh",
                fullName: "GPT-5.6 Sol xhigh"
            ),
            "5.6 Sol xh"
        )
    }

    func testInvalidStoredValuesMigrateToDefaults() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: "menuBarMetric")
        defaults.set("unknown", forKey: "menuBarRankStyle")
        defaults.set(7, forKey: "refreshIntervalMinutes")
        defaults.set(90, forKey: "rankingWeightIQ")
        defaults.set(90, forKey: "rankingWeightCost")
        defaults.set(90, forKey: "rankingWeightDuration")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.menuBarMetric, .iq)
        XCTAssertEqual(settings.menuBarRankStyle, .hidden)
        XCTAssertEqual(settings.refreshInterval, .thirtyMinutes)
        XCTAssertEqual(settings.rankingWeights, .default)
    }
}
