import CodexToolboxCore
import SwiftUI

extension RankingMetric {
    var tint: Color {
        switch self {
        case .iq: .blue
        case .cost: .green
        case .duration: .orange
        case .overall: .purple
        }
    }

    var rankingTitle: String {
        switch self {
        case .iq: "智商最高"
        case .cost: "费用最低"
        case .duration: "耗时最低"
        case .overall: "综合最佳"
        }
    }
}
