import Foundation

public enum RankingMetric: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case iq
    case cost
    case duration
    case overall

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .iq: "智商"
        case .cost: "费用"
        case .duration: "耗时"
        case .overall: "综合"
        }
    }

    public var systemImage: String {
        switch self {
        case .iq: "brain.head.profile"
        case .cost: "dollarsign.circle"
        case .duration: "clock"
        case .overall: "trophy"
        }
    }
}

public struct RankingWeights: Codable, Hashable, Sendable {
    public var iq: Int
    public var cost: Int
    public var duration: Int

    public static let `default` = RankingWeights(iq: 50, cost: 25, duration: 25)

    public init(iq: Int, cost: Int, duration: Int) {
        self.iq = iq
        self.cost = cost
        self.duration = duration
    }

    public var total: Int { iq + cost + duration }

    public var isValid: Bool {
        (0...100).contains(iq)
            && (0...100).contains(cost)
            && (0...100).contains(duration)
            && total == 100
    }
}
