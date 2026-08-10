import Foundation

public enum StationRecommendationPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
    case aboveRankings
    case belowRankings

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aboveRankings: "四宫格上方"
        case .belowRankings: "四宫格下方"
        }
    }
}

public enum OverallRankingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case localWeighted
    case radarCostEfficiency

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .localWeighted: "本地综合"
        case .radarCostEfficiency: "雷达成本效率"
        }
    }
}

public enum RateCardMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case tokenBased
    case legacy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "自动"
        case .tokenBased: "Token-based"
        case .legacy: "Legacy"
        }
    }
}
