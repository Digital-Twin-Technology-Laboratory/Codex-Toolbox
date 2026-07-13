import Foundation

public struct RankedModel: Identifiable, Hashable, Sendable {
    public let benchmark: ModelBenchmark
    public let metric: RankingMetric
    public let position: Int
    public let value: Double
    public let percentileScore: Double

    public var id: String { benchmark.id }

    public init(
        benchmark: ModelBenchmark,
        metric: RankingMetric,
        position: Int,
        value: Double,
        percentileScore: Double
    ) {
        self.benchmark = benchmark
        self.metric = metric
        self.position = position
        self.value = value
        self.percentileScore = percentileScore
    }
}

public enum RankingEngine {
    public static func rank(
        _ benchmarks: [ModelBenchmark],
        by metric: RankingMetric,
        weights: RankingWeights = .default
    ) -> [RankedModel] {
        if metric == .overall {
            return overallRanking(benchmarks, weights: weights)
        }

        let candidates = benchmarks.compactMap { benchmark -> Candidate? in
            guard let value = benchmark.value(for: metric), value.isFinite else { return nil }
            return Candidate(benchmark: benchmark, value: value)
        }
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return metric == .iq ? lhs.value > rhs.value : lhs.value < rhs.value
            }
            return lhs.benchmark.id < rhs.benchmark.id
        }
        let percentileByID = percentileScores(sorted)

        return sorted.enumerated().map { index, candidate in
            RankedModel(
                benchmark: candidate.benchmark,
                metric: metric,
                position: index + 1,
                value: candidate.value,
                percentileScore: percentileByID[candidate.benchmark.id] ?? 0
            )
        }
    }

    private static func overallRanking(
        _ benchmarks: [ModelBenchmark],
        weights: RankingWeights
    ) -> [RankedModel] {
        guard weights.isValid else { return [] }

        let complete = benchmarks.filter { benchmark in
            guard
                let iq = benchmark.latest?.score,
                let cost = benchmark.latest?.costUSD,
                let duration = benchmark.latest?.wallSeconds
            else { return false }
            return iq.isFinite && cost.isFinite && duration.isFinite
        }
        guard !complete.isEmpty else { return [] }

        let iqScores = percentileMap(complete, metric: .iq)
        let costScores = percentileMap(complete, metric: .cost)
        let durationScores = percentileMap(complete, metric: .duration)

        let iqWeight = Double(weights.iq)
        let costWeight = Double(weights.cost)
        let durationWeight = Double(weights.duration)
        var weighted: [OverallCandidate] = []
        weighted.reserveCapacity(complete.count)

        for benchmark in complete {
            let iq = iqScores[benchmark.id] ?? 0
            let cost = costScores[benchmark.id] ?? 0
            let duration = durationScores[benchmark.id] ?? 0
            let iqComponent = iq * iqWeight
            let costComponent = cost * costWeight
            let durationComponent = duration * durationWeight
            let score = (iqComponent + costComponent + durationComponent) / 100
            weighted.append(OverallCandidate(benchmark: benchmark, score: score))
        }

        let sorted = weighted.sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.000_001 {
                return lhs.score > rhs.score
            }
            if lhs.benchmark.latest?.score != rhs.benchmark.latest?.score {
                return (lhs.benchmark.latest?.score ?? -.infinity) > (rhs.benchmark.latest?.score ?? -.infinity)
            }
            if lhs.benchmark.latest?.costUSD != rhs.benchmark.latest?.costUSD {
                return (lhs.benchmark.latest?.costUSD ?? .infinity) < (rhs.benchmark.latest?.costUSD ?? .infinity)
            }
            if lhs.benchmark.latest?.wallSeconds != rhs.benchmark.latest?.wallSeconds {
                return (lhs.benchmark.latest?.wallSeconds ?? .infinity) < (rhs.benchmark.latest?.wallSeconds ?? .infinity)
            }
            return lhs.benchmark.id < rhs.benchmark.id
        }

        return sorted.enumerated().map { index, candidate in
            RankedModel(
                benchmark: candidate.benchmark,
                metric: .overall,
                position: index + 1,
                value: candidate.score,
                percentileScore: candidate.score
            )
        }
    }

    private static func percentileMap(
        _ benchmarks: [ModelBenchmark],
        metric: RankingMetric
    ) -> [String: Double] {
        let candidates = benchmarks.compactMap { benchmark -> Candidate? in
            guard let value = benchmark.value(for: metric) else { return nil }
            return Candidate(benchmark: benchmark, value: value)
        }
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return metric == .iq ? lhs.value > rhs.value : lhs.value < rhs.value
            }
            return lhs.benchmark.id < rhs.benchmark.id
        }
        return percentileScores(sorted)
    }

    private static func percentileScores(_ sorted: [Candidate]) -> [String: Double] {
        guard !sorted.isEmpty else { return [:] }
        guard sorted.count > 1 else { return [sorted[0].benchmark.id: 100] }

        var result: [String: Double] = [:]
        var start = 0
        while start < sorted.count {
            var end = start + 1
            while end < sorted.count, sorted[end].value == sorted[start].value {
                end += 1
            }

            let firstRank = Double(start + 1)
            let lastRank = Double(end)
            let averageRank = (firstRank + lastRank) / 2
            let percentile = 100 * (Double(sorted.count) - averageRank) / Double(sorted.count - 1)
            for index in start..<end {
                result[sorted[index].benchmark.id] = percentile
            }
            start = end
        }
        return result
    }

    private struct Candidate {
        let benchmark: ModelBenchmark
        let value: Double
    }

    private struct OverallCandidate {
        let benchmark: ModelBenchmark
        let score: Double
    }
}
