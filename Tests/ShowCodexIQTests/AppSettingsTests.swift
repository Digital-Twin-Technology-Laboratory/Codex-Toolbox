import Foundation
import XCTest
@testable import ShowCodexIQCore

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsAndWeightValidation() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.menuBarMetric, .iq)
        XCTAssertEqual(settings.menuBarRankStyle, .hidden)
        XCTAssertFalse(settings.showsMenuBarDetails)
        XCTAssertTrue(settings.automaticRefreshEnabled)
        XCTAssertEqual(settings.refreshInterval, .thirtyMinutes)
        XCTAssertEqual(settings.rankingWeights, .default)
        XCTAssertFalse(settings.apply(weights: RankingWeights(iq: 70, cost: 20, duration: 20)))
        XCTAssertEqual(settings.rankingWeights, .default)
        XCTAssertTrue(settings.apply(weights: RankingWeights(iq: 70, cost: 20, duration: 10)))
    }

    func testMenuBarDisplayPreferencesPersist() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.menuBarRankStyle = .ideographicComma
        settings.showsMenuBarDetails = true

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.menuBarRankStyle, .ideographicComma)
        XCTAssertTrue(restored.showsMenuBarDetails)
        XCTAssertEqual(restored.menuBarRankStyle.prefix(for: 2), "2、")
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
