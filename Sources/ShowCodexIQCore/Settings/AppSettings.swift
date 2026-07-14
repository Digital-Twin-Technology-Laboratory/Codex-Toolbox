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

@MainActor
@Observable
public final class AppSettings {
    public var menuBarMetric: RankingMetric {
        didSet { defaults.set(menuBarMetric.rawValue, forKey: Keys.menuBarMetric) }
    }

    public var automaticRefreshEnabled: Bool {
        didSet { defaults.set(automaticRefreshEnabled, forKey: Keys.automaticRefreshEnabled) }
    }

    public var menuBarRankStyle: MenuBarRankStyle {
        didSet { defaults.set(menuBarRankStyle.rawValue, forKey: Keys.menuBarRankStyle) }
    }

    public var showsMenuBarDetails: Bool {
        didSet { defaults.set(showsMenuBarDetails, forKey: Keys.showsMenuBarDetails) }
    }

    public var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }

    public private(set) var rankingWeights: RankingWeights

    public var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarMetric = RankingMetric(rawValue: defaults.string(forKey: Keys.menuBarMetric) ?? "") ?? .iq
        menuBarRankStyle = MenuBarRankStyle(
            rawValue: defaults.string(forKey: Keys.menuBarRankStyle) ?? ""
        ) ?? .hidden
        showsMenuBarDetails = defaults.bool(forKey: Keys.showsMenuBarDetails)

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

    private enum Keys {
        static let menuBarMetric = "menuBarMetric"
        static let menuBarRankStyle = "menuBarRankStyle"
        static let showsMenuBarDetails = "showsMenuBarDetails"
        static let automaticRefreshEnabled = "automaticRefreshEnabled"
        static let refreshInterval = "refreshIntervalMinutes"
        static let iqWeight = "rankingWeightIQ"
        static let costWeight = "rankingWeightCost"
        static let durationWeight = "rankingWeightDuration"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
    }
}
