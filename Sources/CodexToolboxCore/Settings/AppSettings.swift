import Foundation
import Observation

public enum RefreshInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .fifteenMinutes: "15 分钟"
        case .thirtyMinutes: "30 分钟"
        case .oneHour: "1 小时"
        case .twoHours: "2 小时"
        case .fourHours: "4 小时"
        }
    }
}

public enum MenuBarRankStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case hidden
    case hash
    case period
    case ideographicComma

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hidden: "不显示"
        case .hash: "#1"
        case .period: "1."
        case .ideographicComma: "1、"
        }
    }

    public func prefix(for position: Int) -> String {
        switch self {
        case .hidden: ""
        case .hash: "#\(position) "
        case .period: "\(position). "
        case .ideographicComma: "\(position)、"
        }
    }
}

public enum UsageRefreshInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    public var id: Int { rawValue }
    public var displayName: String { "\(rawValue) 分钟" }
}

public enum UsageTrendRange: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90

    public var id: Int { rawValue }
    public var displayName: String { "\(rawValue) 天" }
}

public enum UsageExpandedTaskLimit: Int, Codable, CaseIterable, Identifiable, Sendable {
    case topFive = 5
    case topTen = 10

    public var id: Int { rawValue }
    public var displayName: String { "Top \(rawValue)" }
}

public enum ModelTrendRange: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90

    public var id: Int { rawValue }
    public var displayName: String { "\(rawValue) 天" }
}

public enum ResetCreditsRefreshInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .fifteenMinutes: "15 分钟"
        case .thirtyMinutes: "30 分钟"
        case .oneHour: "1 小时"
        case .twoHours: "2 小时"
        }
    }
}

public enum ResetExpiryWarning: Int, Codable, CaseIterable, Identifiable, Sendable {
    case disabled = 0
    case oneDay = 1
    case threeDays = 3
    case sevenDays = 7

    public var id: Int { rawValue }
    public var displayName: String { self == .disabled ? "关闭" : "\(rawValue) 天内" }
}

@MainActor
@Observable
public final class AppSettings {
    public private(set) var dashboardModuleOrder: [ToolboxModule] {
        didSet { defaults.set(dashboardModuleOrder.map(\.rawValue), forKey: Keys.dashboardModuleOrder) }
    }

    public private(set) var hiddenDashboardModules: Set<ToolboxModule> {
        didSet { defaults.set(hiddenDashboardModules.map(\.rawValue).sorted(), forKey: Keys.hiddenDashboardModules) }
    }

    public private(set) var collapsedDashboardModules: Set<ToolboxModule> {
        didSet { defaults.set(collapsedDashboardModules.map(\.rawValue).sorted(), forKey: Keys.collapsedDashboardModules) }
    }

    public var usageRefreshInterval: UsageRefreshInterval {
        didSet { defaults.set(usageRefreshInterval.rawValue, forKey: Keys.usageRefreshInterval) }
    }

    public var usageTrendRange: UsageTrendRange {
        didSet { defaults.set(usageTrendRange.rawValue, forKey: Keys.usageTrendRange) }
    }

    public var usageExpandedTaskLimit: UsageExpandedTaskLimit {
        didSet { defaults.set(usageExpandedTaskLimit.rawValue, forKey: Keys.usageExpandedTaskLimit) }
    }

    public var anonymizesTaskTitles: Bool {
        didSet { defaults.set(anonymizesTaskTitles, forKey: Keys.anonymizesTaskTitles) }
    }

    public var resetCreditsRefreshInterval: ResetCreditsRefreshInterval {
        didSet { defaults.set(resetCreditsRefreshInterval.rawValue, forKey: Keys.resetCreditsRefreshInterval) }
    }

    public var resetExpiryWarning: ResetExpiryWarning {
        didSet { defaults.set(resetExpiryWarning.rawValue, forKey: Keys.resetExpiryWarning) }
    }

    public var menuBarMetric: RankingMetric {
        didSet { defaults.set(menuBarMetric.rawValue, forKey: Keys.menuBarMetric) }
    }

    public var automaticRefreshEnabled: Bool {
        didSet { defaults.set(automaticRefreshEnabled, forKey: Keys.automaticRefreshEnabled) }
    }

    public var menuBarRankStyle: MenuBarRankStyle {
        didSet { defaults.set(menuBarRankStyle.rawValue, forKey: Keys.menuBarRankStyle) }
    }

    public var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Keys.showsMenuBarIcon) }
    }

    public var showsMenuBarDetails: Bool {
        didSet { defaults.set(showsMenuBarDetails, forKey: Keys.showsMenuBarDetails) }
    }

    public private(set) var menuBarModelAliases: [String: String] {
        didSet { defaults.set(menuBarModelAliases, forKey: Keys.menuBarModelAliases) }
    }

    public var showsTrendChart: Bool {
        didSet { defaults.set(showsTrendChart, forKey: Keys.showsTrendChart) }
    }

    public var modelTrendRange: ModelTrendRange {
        didSet { defaults.set(modelTrendRange.rawValue, forKey: Keys.modelTrendRange) }
    }

    public var showsDetailedBenchmarkTime: Bool {
        didSet {
            defaults.set(showsDetailedBenchmarkTime, forKey: Keys.showsDetailedBenchmarkTime)
        }
    }

    public var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }

    public private(set) var rankingWeights: RankingWeights

    public var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }

    public var automaticUpdateChecksEnabled: Bool {
        didSet { defaults.set(automaticUpdateChecksEnabled, forKey: Keys.automaticUpdateChecksEnabled) }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dashboardModuleOrder = Self.normalizedModuleOrder(
            defaults.stringArray(forKey: Keys.dashboardModuleOrder) ?? []
        )
        hiddenDashboardModules = Self.moduleSet(
            defaults.stringArray(forKey: Keys.hiddenDashboardModules) ?? []
        )
        collapsedDashboardModules = Self.moduleSet(
            defaults.stringArray(forKey: Keys.collapsedDashboardModules)
                ?? DashboardConfiguration.default.collapsedModules.map(\.rawValue)
        )
        usageRefreshInterval = UsageRefreshInterval(
            rawValue: defaults.integer(forKey: Keys.usageRefreshInterval)
        ) ?? .fiveMinutes
        usageTrendRange = UsageTrendRange(
            rawValue: defaults.integer(forKey: Keys.usageTrendRange)
        ) ?? .sevenDays
        usageExpandedTaskLimit = UsageExpandedTaskLimit(
            rawValue: defaults.integer(forKey: Keys.usageExpandedTaskLimit)
        ) ?? .topFive
        anonymizesTaskTitles = defaults.bool(forKey: Keys.anonymizesTaskTitles)
        resetCreditsRefreshInterval = ResetCreditsRefreshInterval(
            rawValue: defaults.integer(forKey: Keys.resetCreditsRefreshInterval)
        ) ?? .thirtyMinutes
        if defaults.object(forKey: Keys.resetExpiryWarning) == nil {
            resetExpiryWarning = .threeDays
        } else {
            resetExpiryWarning = ResetExpiryWarning(
                rawValue: defaults.integer(forKey: Keys.resetExpiryWarning)
            ) ?? .threeDays
        }
        menuBarMetric = RankingMetric(rawValue: defaults.string(forKey: Keys.menuBarMetric) ?? "") ?? .iq
        menuBarRankStyle = MenuBarRankStyle(
            rawValue: defaults.string(forKey: Keys.menuBarRankStyle) ?? ""
        ) ?? .hidden

        if defaults.object(forKey: Keys.showsMenuBarIcon) == nil {
            showsMenuBarIcon = true
        } else {
            showsMenuBarIcon = defaults.bool(forKey: Keys.showsMenuBarIcon)
        }

        showsMenuBarDetails = defaults.bool(forKey: Keys.showsMenuBarDetails)
        let storedAliases = defaults.dictionary(forKey: Keys.menuBarModelAliases)?
            .compactMapValues { $0 as? String } ?? [:]
        menuBarModelAliases = Self.sanitizedAliases(
            storedAliases
        )

        if defaults.object(forKey: Keys.showsTrendChart) == nil {
            showsTrendChart = false
        } else {
            showsTrendChart = defaults.bool(forKey: Keys.showsTrendChart)
        }
        modelTrendRange = ModelTrendRange(
            rawValue: defaults.integer(forKey: Keys.modelTrendRange)
        ) ?? .sevenDays

        if defaults.object(forKey: Keys.showsDetailedBenchmarkTime) == nil {
            showsDetailedBenchmarkTime = true
        } else {
            showsDetailedBenchmarkTime = defaults.bool(forKey: Keys.showsDetailedBenchmarkTime)
        }

        if defaults.object(forKey: Keys.automaticRefreshEnabled) == nil {
            automaticRefreshEnabled = true
        } else {
            automaticRefreshEnabled = defaults.bool(forKey: Keys.automaticRefreshEnabled)
        }

        refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: Keys.refreshInterval)) ?? .thirtyMinutes

        let storedWeights = RankingWeights(
            iq: defaults.object(forKey: Keys.iqWeight) as? Int ?? RankingWeights.default.iq,
            cost: defaults.object(forKey: Keys.costWeight) as? Int ?? RankingWeights.default.cost,
            duration: defaults.object(forKey: Keys.durationWeight) as? Int ?? RankingWeights.default.duration
        )
        rankingWeights = storedWeights.isValid ? storedWeights : .default
        launchAtLoginEnabled = defaults.bool(forKey: Keys.launchAtLoginEnabled)
        if defaults.object(forKey: Keys.automaticUpdateChecksEnabled) == nil {
            automaticUpdateChecksEnabled = true
        } else {
            automaticUpdateChecksEnabled = defaults.bool(forKey: Keys.automaticUpdateChecksEnabled)
        }
    }

    @discardableResult
    public func apply(weights: RankingWeights) -> Bool {
        guard weights.isValid else { return false }
        rankingWeights = weights
        defaults.set(weights.iq, forKey: Keys.iqWeight)
        defaults.set(weights.cost, forKey: Keys.costWeight)
        defaults.set(weights.duration, forKey: Keys.durationWeight)
        return true
    }

    public func resetWeights() {
        _ = apply(weights: .default)
    }

    public var dashboardConfiguration: DashboardConfiguration {
        DashboardConfiguration(
            orderedModules: dashboardModuleOrder,
            hiddenModules: hiddenDashboardModules,
            collapsedModules: collapsedDashboardModules
        )
    }

    public func setDashboardModule(_ module: ToolboxModule, isVisible: Bool) {
        if isVisible {
            hiddenDashboardModules.remove(module)
        } else {
            hiddenDashboardModules.insert(module)
        }
    }

    public func setDashboardModule(_ module: ToolboxModule, isCollapsed: Bool) {
        if isCollapsed {
            collapsedDashboardModules.insert(module)
        } else {
            collapsedDashboardModules.remove(module)
        }
    }

    public func moveDashboardModule(_ module: ToolboxModule, to destination: Int) {
        guard let source = dashboardModuleOrder.firstIndex(of: module) else { return }
        var updated = dashboardModuleOrder
        updated.remove(at: source)
        updated.insert(module, at: min(max(0, destination), updated.count))
        dashboardModuleOrder = updated
    }

    public func moveDashboardModuleUp(_ module: ToolboxModule) {
        guard let index = dashboardModuleOrder.firstIndex(of: module), index > 0 else { return }
        moveDashboardModule(module, to: index - 1)
    }

    public func moveDashboardModuleDown(_ module: ToolboxModule) {
        guard let index = dashboardModuleOrder.firstIndex(of: module), index + 1 < dashboardModuleOrder.count else { return }
        moveDashboardModule(module, to: index + 1)
    }

    public func resetDashboardConfiguration() {
        dashboardModuleOrder = ToolboxModule.allCases
        hiddenDashboardModules = []
        collapsedDashboardModules = DashboardConfiguration.default.collapsedModules
    }

    public func menuBarModelAlias(for modelID: String) -> String {
        menuBarModelAliases[modelID] ?? ""
    }

    public func setMenuBarModelAlias(_ alias: String, for modelID: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedAliases = menuBarModelAliases
        if trimmed.isEmpty {
            updatedAliases.removeValue(forKey: modelID)
        } else {
            updatedAliases[modelID] = alias
        }
        menuBarModelAliases = updatedAliases
    }

    public func menuBarModelName(modelID: String, fullName: String) -> String {
        menuBarModelAliases[modelID]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? MetricFormatter.compactModelName(fullName)
    }

    private static func sanitizedAliases(_ aliases: [String: String]) -> [String: String] {
        aliases.reduce(into: [:]) { result, entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result[entry.key] = trimmed
            }
        }
    }

    private static func normalizedModuleOrder(_ rawValues: [String]) -> [ToolboxModule] {
        DashboardConfiguration(
            orderedModules: rawValues.compactMap(ToolboxModule.init(rawValue:)),
            hiddenModules: [],
            collapsedModules: []
        ).orderedModules
    }

    private static func moduleSet(_ rawValues: [String]) -> Set<ToolboxModule> {
        Set(rawValues.compactMap(ToolboxModule.init(rawValue:)))
    }

    private enum Keys {
        static let dashboardModuleOrder = "dashboardModuleOrder"
        static let hiddenDashboardModules = "hiddenDashboardModules"
        static let collapsedDashboardModules = "collapsedDashboardModules"
        static let usageRefreshInterval = "usageRefreshIntervalMinutes"
        static let usageTrendRange = "usageTrendRangeDays"
        static let usageExpandedTaskLimit = "usageExpandedTaskLimit"
        static let anonymizesTaskTitles = "anonymizesTaskTitles"
        static let resetCreditsRefreshInterval = "resetCreditsRefreshIntervalMinutes"
        static let resetExpiryWarning = "resetExpiryWarningDays"
        static let menuBarMetric = "menuBarMetric"
        static let menuBarRankStyle = "menuBarRankStyle"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let showsMenuBarDetails = "showsMenuBarDetails"
        static let menuBarModelAliases = "menuBarModelAliases"
        static let showsTrendChart = "showsTrendChart"
        static let modelTrendRange = "modelTrendRangeDays"
        static let showsDetailedBenchmarkTime = "showsDetailedBenchmarkTime"
        static let automaticRefreshEnabled = "automaticRefreshEnabled"
        static let refreshInterval = "refreshIntervalMinutes"
        static let iqWeight = "rankingWeightIQ"
        static let costWeight = "rankingWeightCost"
        static let durationWeight = "rankingWeightDuration"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let automaticUpdateChecksEnabled = "automaticUpdateChecksEnabled"
    }
}
