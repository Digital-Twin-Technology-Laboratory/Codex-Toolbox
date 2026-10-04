import Foundation
import XCTest
@testable import CodexToolboxCore

@MainActor
final class MenuBarConfigurationTests: XCTestCase {
    private func withSettings(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "MenuMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
    func testNewInstallationHasThreeStableSlotsAndOnlyFirstEnabled() {
        withSettings { defaults in
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(settings.menuBarConfiguration.items.map(\.content), [.overall, .todayTokens, .accountQuota])
            XCTAssertEqual(settings.menuBarConfiguration.items.map(\.isEnabled), [true, false, false])
            XCTAssertFalse(settings.quotaDisplayOptions.usesColor)
            XCTAssertEqual(AppSettings(defaults: defaults).menuBarConfiguration, settings.menuBarConfiguration)
        }
    }
    func testLocalCostExperimentDefaultsOffOnUpgradeAndPreservesCostSlot() {
        withSettings { defaults in
            defaults.set(true, forKey: "showsAPICostEstimates")
            let settings = AppSettings(defaults: defaults)
            let id = settings.menuBarConfiguration.items[0].id
            settings.menuBarConfiguration.update(id, content: .todayAPICost)
            XCTAssertFalse(settings.experimentalLocalCostEstimatesEnabled)
            XCTAssertFalse(settings.showsLocalCostEstimates)
            XCTAssertEqual(settings.menuBarConfiguration.items[0].content.resolved(localCostEstimatesEnabled: false), .todayTokens)
            XCTAssertFalse(MenuBarContent.availableContents(localCostEstimatesEnabled: false).contains(.todayAPICost))
            settings.experimentalLocalCostEstimatesEnabled = true
            XCTAssertTrue(settings.showsLocalCostEstimates)
            XCTAssertEqual(settings.menuBarConfiguration.items[0].content.resolved(localCostEstimatesEnabled: true), .todayAPICost)
            XCTAssertEqual(AppSettings(defaults: defaults).menuBarConfiguration.items[0].id, id)
            XCTAssertTrue(AppSettings(defaults: defaults).experimentalLocalCostEstimatesEnabled)
        }
    }
    func testLegacyUpgradePreservesMetricAndIndependentStyles() {
        withSettings { defaults in
            defaults.set("cost", forKey: "menuBarMetric")
            defaults.set(false, forKey: "showsMenuBarIcon")
            defaults.set(true, forKey: "showsMenuBarDetails")
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(settings.menuBarConfiguration.items.map(\.content), [.cost, .todayTokens, .accountQuota])
            XCTAssertFalse(settings.tokenMenuBarOptions.showsIcon)
            XCTAssertFalse(settings.quotaDisplayOptions.showsIcon)
            XCTAssertTrue(settings.showsMenuBarDetails)
            settings.tokenMenuBarOptions.showsIcon = true
            XCTAssertFalse(settings.showsMenuBarIcon)
            XCTAssertFalse(settings.quotaDisplayOptions.showsIcon)
        }
    }
    func testBuild52MigrationPreservesIDsDuplicatesAndEnabledStateOnlyOnce() throws {
        try withSettings { defaults in
            let items = [MenuBarItemConfiguration(content: .cost, isEnabled: false), MenuBarItemConfiguration(content: .cost)]
            defaults.set(try JSONEncoder().encode(["items": items]), forKey: "menuBarConfigurationV1")
            defaults.set(Data(#"{"bar":true,"ring":true,"percentage":false}"#.utf8), forKey: "quotaDisplayOptionsV1")
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(Array(settings.menuBarConfiguration.items.prefix(2)), items)
            XCTAssertEqual(settings.menuBarConfiguration.items[2].content, .accountQuota)
            XCTAssertFalse(settings.menuBarConfiguration.items[2].isEnabled)
            XCTAssertEqual(settings.quotaDisplayOptions.indicator, .bar)
            XCTAssertFalse(settings.quotaDisplayOptions.percentage)
            XCTAssertTrue(settings.quotaDisplayOptions.usesColor)
            settings.quotaDisplayOptions.indicator = .ring
            settings.quotaDisplayOptions.usesColor = false
            XCTAssertEqual(AppSettings(defaults: defaults).quotaDisplayOptions, settings.quotaDisplayOptions)
        }
    }
    func testLastEnabledItemAndMalformedDuplicateIDsAreRepaired() throws {
        var config = MenuBarConfiguration()
        config.update(config.items[0].id, isEnabled: false)
        XCTAssertEqual(config.enabledItems.count, 1)
        config.update(config.items[1].id, content: .overall, isEnabled: true)
        config.update(config.items[0].id, isEnabled: false)
        XCTAssertEqual(config.enabledItems.first?.id, config.items[1].id)
        let disabled = MenuBarItemConfiguration(isEnabled: false)
        let repaired = try JSONDecoder().decode(MenuBarConfiguration.self, from: JSONEncoder().encode(["items": [disabled, disabled]]))
        XCTAssertEqual(repaired.items.count, 3)
        XCTAssertEqual(Set(repaired.items.map(\.id)).count, 3)
        XCTAssertEqual(repaired.enabledItems.count, 1)
    }
    func testNumberFormatsDateLocaleAndDistinctIcons() throws {
        XCTAssertEqual(MetricFormatter.menuBarTokens(5_000_000, format: .full), "5,000,000")
        XCTAssertEqual(MetricFormatter.menuBarTokens(5_000_000, format: .abbreviated), "5M")
        XCTAssertEqual(MetricFormatter.menuBarTokens(950_000, format: .abbreviated), "950K")
        XCTAssertEqual(MetricFormatter.menuBarTokens(999_999, format: .abbreviated), "1M")
        XCTAssertEqual(MetricFormatter.menuBarTokens(0, format: .abbreviated), "0")
        XCTAssertEqual(MetricFormatter.menuBarAPICost(nil, precision: nil, format: .full), "—")
        XCTAssertEqual(MetricFormatter.menuBarAPICost(Decimal(string: "0.0012"), precision: .approximate, format: .abbreviated), "≈$0.0012")
        XCTAssertEqual(MetricFormatter.menuBarAPICost(5000000, precision: .lowerBound, format: .abbreviated), "≥$5M")
        let date = try XCTUnwrap(MetricFormatter.sourceDate("2026-10-10T08:39:00Z"))
        XCTAssertEqual(MetricFormatter.chineseAccountDate(date), "2026年10月10日 星期六 16:39")
        XCTAssertNotEqual(MenuBarContent.todayTokens.systemImage, MenuBarContent.todayAPICost.systemImage)
    }
    func testVerifiedPlanLabelsAndUnknownType() {
        XCTAssertEqual(AccountPlan.displayName("prolite"), "Pro 100")
        XCTAssertEqual(AccountPlan.displayName("pro"), "Pro 200")
        XCTAssertEqual(AccountPlan.displayName("promax"), "Pro 500")
        XCTAssertTrue(AccountPlan.displayName("future").contains("未知套餐"))
    }
}
