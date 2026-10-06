import CodexToolboxCore
import SwiftUI

private struct RadarScoreLabelKey: EnvironmentKey {
    static let defaultValue = "Radar IQ"
}

extension EnvironmentValues {
    var radarScoreLabel: String {
        get { self[RadarScoreLabelKey.self] }
        set { self[RadarScoreLabelKey.self] = newValue }
    }
}

extension RankingMetric {
    func displayName(scoreLabel: String, overallMode: OverallRankingMode = .localWeighted) -> String {
        self == .iq ? scoreLabel : displayName(overallMode: overallMode)
    }
}
