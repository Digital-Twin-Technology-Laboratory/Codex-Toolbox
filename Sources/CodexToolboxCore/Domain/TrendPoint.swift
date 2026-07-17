import Foundation

public struct TrendPoint: Identifiable, Hashable, Sendable {
    public let modelID: String
    public let modelLabel: String
    public let dateKey: String
    public let sequence: Int
    public let value: Double

    public var id: String { "\(modelID)|\(dateKey)" }

    public init(modelID: String, modelLabel: String, dateKey: String, sequence: Int, value: Double) {
        self.modelID = modelID
        self.modelLabel = modelLabel
        self.dateKey = dateKey
        self.sequence = sequence
        self.value = value
    }
}

public enum TrendPointBuilder {
    public static func points(
        benchmarks: [ModelBenchmark],
        costHistory: [CostHistoryPoint],
        metric: RankingMetric,
        modelIDs: [String]
    ) -> [TrendPoint] {
        let selected = Set(modelIDs)
        switch metric {
        case .iq, .duration:
            return benchmarks
                .filter { selected.contains($0.id) }
                .flatMap { benchmark -> [TrendPoint] in
                    var byDate: [String: TrendPoint] = [:]
                    for (index, record) in benchmark.recentDays.enumerated() {
                        let value = metric == .iq ? record.score : record.wallSeconds
                        guard let value, value.isFinite else { continue }
                        byDate[record.date] = TrendPoint(
                            modelID: benchmark.id,
                            modelLabel: benchmark.label,
                            dateKey: record.date,
                            sequence: index,
                            value: value
                        )
                    }
                    return byDate.values.sorted {
                        if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                        return $0.dateKey < $1.dateKey
                    }
                }
                .sorted(by: pointOrdering)
        case .cost:
            let labels = Dictionary(uniqueKeysWithValues: benchmarks.map { ($0.id, $0.label) })
            return Dictionary(grouping: costHistory.filter { selected.contains($0.modelID) }, by: \.modelID)
                .flatMap { modelID, points in
                    points.sorted {
                        if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
                        return $0.dateKey < $1.dateKey
                    }
                    .enumerated()
                    .map { index, point in
                        TrendPoint(
                            modelID: modelID,
                            modelLabel: labels[modelID] ?? modelID,
                            dateKey: point.dateKey,
                            sequence: index,
                            value: point.costUSD
                        )
                    }
                }
                .sorted(by: pointOrdering)
        case .overall:
            return []
        }
    }

    public static func hasDrawableSeries(_ points: [TrendPoint]) -> Bool {
        Dictionary(grouping: points, by: \.modelID).values.contains { $0.count >= 2 }
    }

    public static func shortDateLabel(_ dateKey: String) -> String {
        let base = dateKey.split(separator: "_").first.map(String.init) ?? dateKey
        let components = base.split(separator: "-")
        guard components.count >= 4 else { return dateKey }
        let month = components[1]
        let day = components[2]
        let session = components[3].uppercased()
        return "\(month)/\(day) \(session)"
    }

    private static func pointOrdering(_ lhs: TrendPoint, _ rhs: TrendPoint) -> Bool {
        if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
        if lhs.dateKey != rhs.dateKey { return lhs.dateKey < rhs.dateKey }
        return lhs.modelID < rhs.modelID
    }
}
