import Combine
import CodexToolboxCore

@MainActor
final class WeightDraft: ObservableObject {
    @Published private(set) var firstBoundary: Int
    @Published private(set) var secondBoundary: Int

    init(weights: RankingWeights) {
        let partition = RankingWeights(
            firstBoundary: weights.firstBoundary,
            secondBoundary: weights.secondBoundary
        )
        firstBoundary = partition.firstBoundary
        secondBoundary = partition.secondBoundary
    }

    var weights: RankingWeights {
        RankingWeights(firstBoundary: firstBoundary, secondBoundary: secondBoundary)
    }

    func updateFirstBoundary(to value: Int) {
        firstBoundary = min(max(value, 0), secondBoundary)
    }

    func updateSecondBoundary(to value: Int) {
        secondBoundary = min(max(value, firstBoundary), 100)
    }

    func reset() {
        firstBoundary = RankingWeights.default.firstBoundary
        secondBoundary = RankingWeights.default.secondBoundary
    }
}
