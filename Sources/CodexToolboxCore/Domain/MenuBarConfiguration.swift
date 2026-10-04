import Foundation

public enum MenuBarContent: String, Codable, CaseIterable, Identifiable, Sendable {
    case overall, iq, cost, duration, todayTokens, todayAPICost, accountQuota

    public func resolved(localCostEstimatesEnabled: Bool) -> Self {
        self == .todayAPICost && !localCostEstimatesEnabled ? .todayTokens : self
    }

    public static func availableContents(localCostEstimatesEnabled: Bool) -> [Self] {
        allCases.filter { localCostEstimatesEnabled || $0 != .todayAPICost }
    }
    public var id: String { rawValue }
    public var rankingMetric: RankingMetric? { RankingMetric(rawValue: rawValue) }
    public var module: ToolboxModule {
        switch self {
        case .overall, .iq, .cost, .duration: .modelRadar
        case .todayTokens, .todayAPICost: .tokenUsage
        case .accountQuota: .resetCredits
        }
    }
    public var displayName: String {
        switch self {
        case .overall: "综合榜单"
        case .iq: "智商榜单"
        case .cost: "费用榜单"
        case .duration: "耗时榜单"
        case .todayTokens: "今日 Token"
        case .todayAPICost: "今日 API 等值成本"
        case .accountQuota: "账户剩余额度"
        }
    }
    public var systemImage: String {
        rankingMetric?.systemImage ?? (self == .accountQuota ? "gauge.with.dots.needle.50percent" : self == .todayAPICost ? "dollarsign.circle" : "chart.bar.xaxis")
    }
}

public struct MenuBarItemConfiguration: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var content: MenuBarContent
    public var isEnabled: Bool
    public init(id: UUID = UUID(), content: MenuBarContent = .iq, isEnabled: Bool = true) {
        self.id = id; self.content = content; self.isEnabled = isEnabled
    }
}

public struct MenuBarConfiguration: Codable, Hashable, Sendable {
    public private(set) var items: [MenuBarItemConfiguration]
    public var enabledItems: [MenuBarItemConfiguration] { items.filter(\.isEnabled) }
    public static let defaultContents: [MenuBarContent] = [.overall, .todayTokens, .accountQuota]
    public init(items: [MenuBarItemConfiguration] = []) {
        var seen = Set<UUID>()
        self.items = Array(items.filter { seen.insert($0.id).inserted }.prefix(3))
        while self.items.count < 3 {
            self.items.append(MenuBarItemConfiguration(content: Self.defaultContents[self.items.count], isEnabled: false))
        }
        if !self.items.contains(where: \.isEnabled) { self.items[0].isEnabled = true }
    }
    private enum CodingKeys: CodingKey { case items }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(items: try container.decode([MenuBarItemConfiguration].self, forKey: .items))
    }
    public mutating func update(_ id: UUID, content: MenuBarContent? = nil, isEnabled: Bool? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let content { items[index].content = content }
        if let isEnabled {
            guard isEnabled || !items[index].isEnabled || enabledItems.count > 1 else { return }
            items[index].isEnabled = isEnabled
        }
    }
}

public enum MenuBarNumberFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case full, abbreviated
    public var id: String { rawValue }
    public var displayName: String { self == .full ? "完整数字" : "缩写（K / M / B）" }
}
public struct TokenMenuBarOptions: Codable, Hashable, Sendable {
    public var showsIcon: Bool
    public var numberFormat: MenuBarNumberFormat
    public init(showsIcon: Bool = true, numberFormat: MenuBarNumberFormat = .abbreviated) {
        self.showsIcon = showsIcon; self.numberFormat = numberFormat
    }
}
public enum QuotaIndicatorStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case bar, ring, none
    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .bar: "进度条"; case .ring: "圆圈"; case .none: "关闭" }
    }
}
public struct QuotaDisplayOptions: Codable, Hashable, Sendable {
    public var indicator: QuotaIndicatorStyle
    public var percentage: Bool
    public var showsIcon: Bool
    public var usesColor: Bool
    public init(indicator: QuotaIndicatorStyle = .bar, percentage: Bool = true, showsIcon: Bool = true, usesColor: Bool = false) {
        self.indicator = indicator; self.percentage = percentage; self.showsIcon = showsIcon; self.usesColor = usesColor
    }
    public static let dashboard = Self(usesColor: true)
    private enum CodingKeys: String, CodingKey { case indicator, percentage, showsIcon, usesColor }
    public static func migratingLegacy(_ data: Data?, showsIcon: Bool) -> Self {
        struct Legacy: Decodable { let bar: Bool; let ring: Bool; let percentage: Bool }
        let legacy = data.flatMap { try? JSONDecoder().decode(Legacy.self, from: $0) }
        return Self(indicator: legacy.map { $0.bar ? .bar : $0.ring ? .ring : .none } ?? .bar,
                    percentage: legacy?.percentage ?? true, showsIcon: showsIcon, usesColor: true)
    }
}

public enum AccountPlan {
    public static func displayName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "套餐未提供" }
        return ["free": "Free", "go": "Go", "plus": "Plus", "prolite": "Pro 100",
                "pro": "Pro 200", "promax": "Pro 500", "team": "Team", "business": "Business",
                "self_serve_business_prolite": "Business Pro Lite", "self_serve_business_usage_based": "Business",
                "enterprise": "Enterprise", "ent26": "Enterprise", "enterprise_cbp_automation": "Enterprise",
                "enterprise_cbp_usage_based": "Enterprise", "edu": "Edu", "edu_plus": "Edu Plus", "edu_pro": "Edu Pro"][raw]
            ?? "未知套餐（\(raw.prefix(64))）"
    }
}
