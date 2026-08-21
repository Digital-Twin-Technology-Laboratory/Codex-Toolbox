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

        XCTAssertFalse(settings.showsExperimentalFeaturesEntry)
        XCTAssertFalse(settings.experimentalDashboardThemesEnabled)
        XCTAssertEqual(settings.dashboardTheme, .colorfulGlass)
        XCTAssertEqual(settings.effectiveDashboardTheme, .colorfulGlass)
        XCTAssertEqual(settings.menuBarMetric, .iq)
        XCTAssertEqual(settings.dashboardModuleOrder, ToolboxModule.allCases)
        XCTAssertTrue(settings.hiddenDashboardModules.isEmpty)
        XCTAssertEqual(settings.collapsedDashboardModules, [.tokenUsage, .resetCredits])
        XCTAssertEqual(settings.usageRefreshInterval, .fiveMinutes)
        XCTAssertEqual(settings.usageTrendRange, .sevenDays)
        XCTAssertEqual(settings.usageExpandedTaskLimit, .topFive)
        XCTAssertFalse(settings.showsAPICostEstimatesInMenuBar)
        XCTAssertTrue(settings.automaticRateCardUpdatesEnabled)
        XCTAssertEqual(settings.rateCardMode, .automatic)
        XCTAssertFalse(settings.anonymizesTaskTitles)
        XCTAssertEqual(settings.resetCreditsRefreshInterval, .thirtyMinutes)
        XCTAssertEqual(settings.resetExpiryWarning, .threeDays)
        XCTAssertTrue(settings.automaticUpdateChecksEnabled)
        XCTAssertEqual(settings.menuBarRankStyle, .hidden)
        XCTAssertTrue(settings.showsMenuBarIcon)
        XCTAssertFalse(settings.showsMenuBarDetails)
        XCTAssertTrue(settings.menuBarModelAliases.isEmpty)
        XCTAssertTrue(settings.modelFamilyAliases.isEmpty)
        XCTAssertEqual(settings.modelVisibilityDefaultMode, .gptOnly)
        XCTAssertTrue(settings.modelProviderVisibilityOverrides.isEmpty)
        XCTAssertTrue(settings.modelFamilyVisibilityOverrides.isEmpty)
        XCTAssertFalse(settings.showsTrendChart)
        XCTAssertFalse(settings.expandsTrendChartByDefault)
        XCTAssertEqual(settings.modelTrendRange, .sevenDays)
        XCTAssertTrue(settings.modelTrendSelections.isEmpty)
        XCTAssertTrue(settings.showsDetailedBenchmarkTime)
        XCTAssertTrue(settings.showsExpandedRankingMetrics)
        XCTAssertFalse(settings.showsStationRecommendations)
        XCTAssertEqual(settings.stationRecommendationPlacement, .aboveRankings)
        XCTAssertEqual(settings.selectedStationRecommendationScenario, .dailyDevelopment)
        XCTAssertEqual(settings.overallRankingMode, .localWeighted)
        XCTAssertTrue(settings.automaticRefreshEnabled)
        XCTAssertEqual(settings.refreshInterval, .thirtyMinutes)
        XCTAssertEqual(settings.rankingWeights, .default)
        XCTAssertFalse(settings.apply(weights: RankingWeights(iq: 70, cost: 20, duration: 20)))
        XCTAssertEqual(settings.rankingWeights, .default)
        XCTAssertTrue(settings.apply(weights: RankingWeights(iq: 70, cost: 20, duration: 10)))
    }

    func testDashboardThemeRawValuesAndPersistence() {
        XCTAssertEqual(DashboardTheme.colorfulGlass.rawValue, "colorfulGlass")
        XCTAssertEqual(DashboardTheme.clearGlass.rawValue, "clearGlass")
        XCTAssertEqual(DashboardTheme.flatNeutral.rawValue, "flatNeutral")
        XCTAssertEqual(
            DashboardTheme.allCases.map(\.displayName),
            ["彩色玻璃", "纯净玻璃", "简约平面"]
        )

        for theme in DashboardTheme.allCases {
            let suite = "AppSettingsTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }

            let settings = AppSettings(defaults: defaults)
            settings.dashboardTheme = theme

            XCTAssertEqual(AppSettings(defaults: defaults).dashboardTheme, theme)
        }
    }

    func testExperimentalDashboardThemesRequireOptInAndPersist() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.dashboardTheme = .flatNeutral

        XCTAssertFalse(settings.experimentalDashboardThemesEnabled)
        XCTAssertEqual(settings.dashboardTheme, .flatNeutral)
        XCTAssertEqual(settings.effectiveDashboardTheme, .colorfulGlass)

        settings.experimentalDashboardThemesEnabled = true
        XCTAssertEqual(settings.effectiveDashboardTheme, .flatNeutral)

        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.experimentalDashboardThemesEnabled)
        XCTAssertEqual(restored.dashboardTheme, .flatNeutral)
        XCTAssertEqual(restored.effectiveDashboardTheme, .flatNeutral)

        restored.experimentalDashboardThemesEnabled = false
        XCTAssertEqual(restored.effectiveDashboardTheme, .colorfulGlass)
        XCTAssertEqual(restored.dashboardTheme, .flatNeutral)
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
        settings.usageExpandedTaskLimit = .topTen
        settings.showsAPICostEstimatesInMenuBar = true
        settings.automaticRateCardUpdatesEnabled = false
        settings.rateCardMode = .legacy
        settings.anonymizesTaskTitles = true
        settings.resetCreditsRefreshInterval = .twoHours
        settings.resetExpiryWarning = .sevenDays
        settings.automaticUpdateChecksEnabled = false
        settings.modelTrendRange = .ninetyDays
        settings.showsStationRecommendations = true
        settings.stationRecommendationPlacement = .belowRankings
        settings.selectedStationRecommendationScenario = .backgroundAutomation
        settings.overallRankingMode = .radarCostEfficiency

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.dashboardModuleOrder, [.resetCredits, .modelRadar, .tokenUsage])
        XCTAssertEqual(restored.dashboardConfiguration.visibleModules, [.resetCredits, .modelRadar])
        XCTAssertTrue(restored.dashboardConfiguration.collapsedModules.contains(.modelRadar))
        XCTAssertEqual(restored.usageRefreshInterval, .oneMinute)
        XCTAssertEqual(restored.usageTrendRange, .ninetyDays)
        XCTAssertEqual(restored.usageExpandedTaskLimit, .topTen)
        XCTAssertTrue(restored.showsAPICostEstimatesInMenuBar)
        XCTAssertFalse(restored.automaticRateCardUpdatesEnabled)
        XCTAssertEqual(restored.rateCardMode, .legacy)
        XCTAssertTrue(restored.anonymizesTaskTitles)
        XCTAssertEqual(restored.resetCreditsRefreshInterval, .twoHours)
        XCTAssertEqual(restored.resetExpiryWarning, .sevenDays)
        XCTAssertFalse(restored.automaticUpdateChecksEnabled)
        XCTAssertEqual(restored.modelTrendRange, .ninetyDays)
        XCTAssertTrue(restored.showsStationRecommendations)
        XCTAssertEqual(restored.stationRecommendationPlacement, .belowRankings)
        XCTAssertEqual(restored.selectedStationRecommendationScenario, .backgroundAutomation)
        XCTAssertEqual(restored.overallRankingMode, .radarCostEfficiency)

        restored.resetDashboardConfiguration()
        XCTAssertEqual(restored.dashboardModuleOrder, ToolboxModule.allCases)
        XCTAssertTrue(restored.hiddenDashboardModules.isEmpty)
        XCTAssertEqual(restored.collapsedDashboardModules, [.tokenUsage, .resetCredits])
    }

    func testAPICostEstimateMenuBarVisibilityDefaultsOffAndPersists() {
        let existingSuite = "AppSettingsTests.\(UUID().uuidString)"
        let existingDefaults = UserDefaults(suiteName: existingSuite)!
        defer { existingDefaults.removePersistentDomain(forName: existingSuite) }
        existingDefaults.set(true, forKey: "showsAPICostEstimates")

        var settings = AppSettings(defaults: existingDefaults)
        XCTAssertTrue(settings.showsAPICostEstimatesInMenuBar)

        settings.showsAPICostEstimatesInMenuBar = false
        settings = AppSettings(defaults: existingDefaults)
        XCTAssertFalse(settings.showsAPICostEstimatesInMenuBar)

        let freshSuite = "AppSettingsTests.\(UUID().uuidString)"
        let freshDefaults = UserDefaults(suiteName: freshSuite)!
        defer { freshDefaults.removePersistentDomain(forName: freshSuite) }

        let fresh = AppSettings(defaults: freshDefaults)
        XCTAssertFalse(fresh.showsAPICostEstimatesInMenuBar)
        fresh.automaticRefreshEnabled = false
        XCTAssertFalse(AppSettings(defaults: freshDefaults).showsAPICostEstimatesInMenuBar)
    }

    func testMenuBarDisplayPreferencesPersist() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.menuBarRankStyle = .ideographicComma
        settings.showsMenuBarIcon = false
        settings.showsMenuBarDetails = true
        settings.showsTrendChart = true
        settings.expandsTrendChartByDefault = true
        settings.modelTrendRange = .fourteenDays
        settings.showsDetailedBenchmarkTime = false
        settings.showsExpandedRankingMetrics = false
        settings.setMenuBarModelAlias("  Sol xh  ", for: "gpt_56_sol_xhigh")

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.menuBarRankStyle, .ideographicComma)
        XCTAssertFalse(restored.showsMenuBarIcon)
        XCTAssertTrue(restored.showsMenuBarDetails)
        XCTAssertTrue(restored.showsTrendChart)
        XCTAssertTrue(restored.expandsTrendChartByDefault)
        XCTAssertEqual(restored.modelTrendRange, .fourteenDays)
        XCTAssertFalse(restored.showsDetailedBenchmarkTime)
        XCTAssertFalse(restored.showsExpandedRankingMetrics)
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

    func testModelTrendSelectionsPersistDeduplicateFiveCurveLimitAndReset() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.setModelTrendSelection(
            [
                "sol-ultra", "  sol-ultra  ", "terra-ultra", "luna-max",
                "5.5-xhigh", "deepseek-high", "ignored-sixth"
            ],
            for: .iq
        )
        settings.setModelTrendSelection(["luna-low"], for: .cost)
        settings.setModelTrendSelection(["luna-low", "terra-low"], for: .duration)
        settings.setModelTrendSelection(["ignored"], for: .overall)

        XCTAssertEqual(
            settings.modelTrendSelection(for: .iq),
            ["sol-ultra", "terra-ultra", "luna-max", "5.5-xhigh", "deepseek-high"]
        )
        XCTAssertEqual(settings.modelTrendSelection(for: .cost), ["luna-low"])
        XCTAssertEqual(settings.modelTrendSelection(for: .duration), ["luna-low", "terra-low"])
        XCTAssertEqual(settings.modelTrendSelection(for: .overall), [])

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(
            restored.modelTrendSelection(for: .iq),
            ["sol-ultra", "terra-ultra", "luna-max", "5.5-xhigh", "deepseek-high"]
        )
        XCTAssertEqual(restored.modelTrendSelection(for: .cost), ["luna-low"])
        XCTAssertEqual(restored.modelTrendSelection(for: .duration), ["luna-low", "terra-low"])

        restored.resetModelTrendSelection(for: .iq)
        restored.setModelTrendSelection([], for: .cost)
        XCTAssertEqual(restored.modelTrendSelection(for: .iq), [])
        XCTAssertEqual(restored.modelTrendSelection(for: .cost), [])
        XCTAssertEqual(restored.modelTrendSelection(for: .duration), ["luna-low", "terra-low"])
    }

    func testInvalidStoredValuesMigrateToDefaults() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: "menuBarMetric")
        defaults.set("unknown", forKey: "menuBarRankStyle")
        defaults.set("unknown", forKey: "dashboardTheme")
        defaults.set(7, forKey: "refreshIntervalMinutes")
        defaults.set(90, forKey: "rankingWeightIQ")
        defaults.set(90, forKey: "rankingWeightCost")
        defaults.set(90, forKey: "rankingWeightDuration")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.menuBarMetric, .iq)
        XCTAssertEqual(settings.menuBarRankStyle, .hidden)
        XCTAssertEqual(settings.dashboardTheme, .colorfulGlass)
        XCTAssertEqual(settings.refreshInterval, .thirtyMinutes)
        XCTAssertEqual(settings.rankingWeights, .default)
    }

    func testExperimentalEntryVisibilityPersistsWithoutDisablingTheme() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.experimentalDashboardThemesEnabled = true
        settings.dashboardTheme = .flatNeutral
        settings.showsExperimentalFeaturesEntry = true

        var restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.showsExperimentalFeaturesEntry)
        XCTAssertEqual(restored.effectiveDashboardTheme, .flatNeutral)

        restored.showsExperimentalFeaturesEntry = false
        restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.showsExperimentalFeaturesEntry)
        XCTAssertTrue(restored.experimentalDashboardThemesEnabled)
        XCTAssertEqual(restored.effectiveDashboardTheme, .flatNeutral)
    }

    func testModelVisibilityDefaultsToOnlyGPTForFreshAndExistingUsers() {
        for isExistingUser in [false, true] {
            let suite = "AppSettingsTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            if isExistingUser {
                defaults.set(true, forKey: "automaticRefreshEnabled")
            }
            let settings = AppSettings(defaults: defaults)

            XCTAssertTrue(settings.isModelVisible(benchmark(id: "sol", model: "gpt-5.6-sol")))
            XCTAssertFalse(settings.isModelVisible(benchmark(id: "grok", model: "grok-4.6")))
            XCTAssertFalse(settings.isModelVisible(benchmark(id: "kimi", model: "k3")))
            XCTAssertFalse(settings.isModelVisible(benchmark(id: "unknown", model: "future-model")))
        }
    }

    func testProviderVisibilityInheritsFutureFamiliesAndFamilyOverrideWins() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let current = benchmark(id: "grok46", model: "grok-4.6")
        let future = benchmark(id: "grok50", model: "grok-5.0")

        settings.setModelProvider(
            "xai",
            isVisible: true,
            knownFamilyIDs: [current.catalogEntry.familyID]
        )
        XCTAssertTrue(settings.isModelVisible(current))
        XCTAssertTrue(settings.isModelVisible(future))

        settings.setModelFamily(current.catalogEntry.familyID, isVisible: false)
        XCTAssertFalse(settings.isModelVisible(current))
        XCTAssertTrue(settings.isModelVisible(future))

        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.isModelVisible(current))
        XCTAssertTrue(restored.isModelVisible(future))
    }

    func testVisibilityCanHideEverythingAndRestoresModesWithoutLosingTrendSelection() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let models = [
            benchmark(id: "sol", model: "gpt-5.6-sol"),
            benchmark(id: "grok", model: "grok-4.6")
        ]
        settings.setModelTrendSelection(["grok"], for: .iq)
        settings.setModelProvider(
            "openai",
            isVisible: false,
            knownFamilyIDs: [models[0].catalogEntry.familyID]
        )
        settings.setModelProvider(
            "xai",
            isVisible: false,
            knownFamilyIDs: [models[1].catalogEntry.familyID]
        )

        XCTAssertTrue(models.allSatisfy { !settings.isModelVisible($0) })
        XCTAssertEqual(settings.modelTrendSelection(for: .iq), ["grok"])

        settings.showAllModels()
        XCTAssertTrue(models.allSatisfy(settings.isModelVisible))
        XCTAssertEqual(settings.modelTrendSelection(for: .iq), ["grok"])
        settings.resetModelVisibilityToGPTOnly()
        XCTAssertTrue(settings.isModelVisible(models[0]))
        XCTAssertFalse(settings.isModelVisible(models[1]))
    }

    func testFamilyAliasPreservesInternalSpacesEnforcesLimitAndOverridesAllEfforts() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let low = benchmark(id: "sol-low", model: "gpt-5.6-sol", effort: "low")
        let high = benchmark(id: "sol-high", model: "gpt-5.6-sol", effort: "high")

        XCTAssertTrue(settings.setModelFamilyAlias("  Sol Vision  ", for: low.catalogEntry.familyID))
        XCTAssertEqual(settings.modelFamilyAlias(for: low.catalogEntry.familyID), "Sol Vision")
        XCTAssertEqual(settings.compactModelName(for: low), "Sol Vision low")
        XCTAssertEqual(settings.compactModelName(for: high), "Sol Vision high")
        XCTAssertFalse(
            settings.setModelFamilyAlias("12345678901234567", for: low.catalogEntry.familyID)
        )
        XCTAssertEqual(settings.modelFamilyAlias(for: low.catalogEntry.familyID), "Sol Vision")
    }

    func testLegacyAliasesMigrateOnlyWhenFamilyIsUnambiguousAndRemainAsFallback() {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let solLow = benchmark(id: "sol-low", model: "gpt-5.6-sol", effort: "low")
        let solHigh = benchmark(id: "sol-high", model: "gpt-5.6-sol", effort: "high")
        let terraLow = benchmark(id: "terra-low", model: "gpt-5.6-terra", effort: "low")
        let terraHigh = benchmark(id: "terra-high", model: "gpt-5.6-terra", effort: "high")
        settings.setMenuBarModelAlias("Nova low", for: solLow.id)
        settings.setMenuBarModelAlias("Nova high", for: solHigh.id)
        settings.setMenuBarModelAlias("Earth", for: terraLow.id)
        settings.setMenuBarModelAlias("Ground", for: terraHigh.id)

        settings.migrateLegacyModelAliases(using: [solLow, solHigh, terraLow, terraHigh])

        XCTAssertEqual(settings.modelFamilyAlias(for: solLow.catalogEntry.familyID), "Nova")
        XCTAssertEqual(settings.compactModelName(for: solHigh), "Nova high")
        XCTAssertEqual(settings.modelFamilyAlias(for: terraLow.catalogEntry.familyID), "")
        XCTAssertEqual(settings.compactModelName(for: terraLow), "Earth")
        XCTAssertEqual(settings.compactModelName(for: terraHigh), "Ground")

        XCTAssertTrue(settings.setModelFamilyAlias("Terra", for: terraLow.catalogEntry.familyID))
        XCTAssertEqual(settings.compactModelName(for: terraLow), "Terra low")
        XCTAssertEqual(settings.compactModelName(for: terraHigh), "Terra high")
        XCTAssertEqual(settings.menuBarModelAlias(for: terraLow.id), "Earth")
    }

    private func benchmark(
        id: String,
        model: String,
        effort: String = "high"
    ) -> ModelBenchmark {
        ModelBenchmark(
            id: id,
            label: "source label",
            model: model,
            reasoningEffort: effort,
            latest: nil,
            recentDays: []
        )
    }
}
