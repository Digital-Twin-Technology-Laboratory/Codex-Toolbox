import Foundation

/// A single plotted observation. `recordedAt` remains the source timestamp for
/// detail presentation, while `day` is the device-calendar day used by Charts.
public struct TrendPoint: Identifiable, Hashable, Sendable {
    public let modelID: String
    public let modelLabel: String
    public let dateKey: String
    public let sequence: Int
    public let value: Double
    public let recordedAt: Date?
    public let day: Date?

    public var id: String { "\(modelID)|\(dateKey)" }

    public init(
        modelID: String,
        modelLabel: String,
        dateKey: String,
        sequence: Int,
        value: Double,
        recordedAt: Date? = nil,
        day: Date? = nil
    ) {
        self.modelID = modelID
        self.modelLabel = modelLabel
        self.dateKey = dateKey
        self.sequence = sequence
        self.value = value
        self.recordedAt = recordedAt
        self.day = day
    }
}

public enum ModelTrendSeriesConfiguration {
    public static let defaultCount = 3
    public static let maximumCount = 5
}

/// Metric/range data that is expensive to derive but independent of the user's
/// current curve selection. Keeping this value alive lets changing one color
/// slot filter existing points instead of reparsing the source history.
public struct TrendSeriesSourceData: Hashable, Sendable {
    public let metric: RankingMetric
    public let automaticModelIDs: [String]
    public let selectableGroups: [ModelCatalogFamilyGroup]

    private let pointsByModelID: [String: [TrendPoint]]
    private let drawableModelIDs: Set<String>

    fileprivate init(
        metric: RankingMetric,
        pointsByModelID: [String: [TrendPoint]],
        automaticModelIDs: [String],
        selectableGroups: [ModelCatalogFamilyGroup],
        drawableModelIDs: Set<String>
    ) {
        self.metric = metric
        self.pointsByModelID = pointsByModelID
        self.automaticModelIDs = automaticModelIDs
        self.selectableGroups = selectableGroups
        self.drawableModelIDs = drawableModelIDs
    }

    public func selecting(savedModelIDs: [String]) -> TrendSeriesData {
        var seen = Set<String>()
        var explicitModelIDs: [String] = []
        for modelID in savedModelIDs
        where drawableModelIDs.contains(modelID) && seen.insert(modelID).inserted {
            explicitModelIDs.append(modelID)
            if explicitModelIDs.count == ModelTrendSeriesConfiguration.maximumCount { break }
        }
        let selectedModelIDs = explicitModelIDs.isEmpty
            ? automaticModelIDs
            : explicitModelIDs
        let chartPoints = selectedModelIDs.flatMap { modelID in
            pointsByModelID[modelID] ?? []
        }
        let chartDays = Array(Set(chartPoints.compactMap(\.day))).sorted()
        let datedPoints = chartPoints.compactMap { point in
            point.day.map { (day: $0, point: point) }
        }
        let pointsByDay = Dictionary(grouping: datedPoints, by: \.day)
            .mapValues { $0.map(\.point) }

        return TrendSeriesData(
            metric: metric,
            chartPoints: chartPoints,
            chartDays: chartDays,
            axisDays: TrendPointBuilder.axisDays(chartDays, maximumCount: 4),
            pointsByDay: pointsByDay,
            automaticModelIDs: automaticModelIDs,
            selectedModelIDs: selectedModelIDs,
            selectableGroups: selectableGroups,
            hasCustomSelection: !savedModelIDs.isEmpty,
            hasDrawableSeries: selectedModelIDs.contains {
                pointsByModelID[$0, default: []].count >= 2
            }
        )
    }
}

/// Immutable data prepared for one metric/range/selection combination.
///
/// SwiftUI containers such as `Menu` can evaluate their content more than once.
/// Keeping every derived collection in one value prevents those evaluations from
/// reparsing the complete source history for each label, submenu, and chart mark.
public struct TrendSeriesData: Hashable, Sendable {
    public let metric: RankingMetric
    public let chartPoints: [TrendPoint]
    public let chartDays: [Date]
    public let axisDays: [Date]
    public let pointsByDay: [Date: [TrendPoint]]
    public let automaticModelIDs: [String]
    public let selectedModelIDs: [String]
    public let selectableGroups: [ModelCatalogFamilyGroup]
    public let hasCustomSelection: Bool
    public let hasDrawableSeries: Bool

    /// A truthful, local scale for line charts. Ranking values often cluster
    /// tightly around the same score; including zero makes distinct curves
    /// look identical even when their underlying values differ.
    public var adaptiveYDomain: ClosedRange<Double> {
        let values = chartPoints.map(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        let spread = maximum - minimum
        let magnitude = max(abs(minimum), abs(maximum))
        let minimumSpan: Double
        switch metric {
        case .iq:
            minimumSpan = max(6, magnitude * 0.04)
        case .cost:
            minimumSpan = max(0.02, magnitude * 0.12)
        case .duration:
            minimumSpan = max(60, magnitude * 0.08)
        case .overall:
            minimumSpan = max(5, magnitude * 0.05)
        }

        let targetSpan = max(spread * 1.28, minimumSpan)
        let padding = max(0, (targetSpan - spread) / 2)
        let lower = max(0, minimum - padding)
        let upper = max(maximum + padding, lower + targetSpan)
        return lower...upper
    }

    public init(
        metric: RankingMetric,
        chartPoints: [TrendPoint],
        chartDays: [Date],
        axisDays: [Date],
        pointsByDay: [Date: [TrendPoint]],
        automaticModelIDs: [String],
        selectedModelIDs: [String],
        selectableGroups: [ModelCatalogFamilyGroup],
        hasCustomSelection: Bool,
        hasDrawableSeries: Bool
    ) {
        self.metric = metric
        self.chartPoints = chartPoints
        self.chartDays = chartDays
        self.axisDays = axisDays
        self.pointsByDay = pointsByDay
        self.automaticModelIDs = automaticModelIDs
        self.selectedModelIDs = selectedModelIDs
        self.selectableGroups = selectableGroups
        self.hasCustomSelection = hasCustomSelection
        self.hasDrawableSeries = hasDrawableSeries
    }
}

public enum TrendSeriesBuilder {
    /// Parses and aggregates every source observation once for a metric/range.
    public static func prepare(
        benchmarks: [ModelBenchmark],
        costHistory: [CostHistoryPoint],
        rankedModelIDs: [String],
        metric: RankingMetric,
        days: Int,
        now: Date,
        calendar: Calendar
    ) -> TrendSeriesSourceData {
        let allRecentPoints = TrendPointBuilder.recentPoints(
            TrendPointBuilder.points(
                benchmarks: benchmarks,
                costHistory: costHistory,
                metric: metric,
                modelIDs: benchmarks.map(\.id),
                calendar: calendar
            ),
            days: days,
            now: now,
            calendar: calendar
        )
        let pointsByModelID = Dictionary(grouping: allRecentPoints, by: \.modelID)
        let drawableModelIDs = Set(
            pointsByModelID
                .compactMap { modelID, points in
                    points.count >= 2 ? modelID : nil
                }
        )
        let automaticModelIDs = Array(
            rankedModelIDs.lazy
                .filter(drawableModelIDs.contains)
                .prefix(ModelTrendSeriesConfiguration.defaultCount)
        )
        let selectableGroups = ModelCatalog.grouped(
            benchmarks.filter { drawableModelIDs.contains($0.id) }
        )

        return TrendSeriesSourceData(
            metric: metric,
            pointsByModelID: pointsByModelID,
            automaticModelIDs: automaticModelIDs,
            selectableGroups: selectableGroups,
            drawableModelIDs: drawableModelIDs
        )
    }

    /// Convenience API for non-interactive callers and tests.
    public static func build(
        benchmarks: [ModelBenchmark],
        costHistory: [CostHistoryPoint],
        rankedModelIDs: [String],
        metric: RankingMetric,
        savedModelIDs: [String],
        days: Int,
        now: Date,
        calendar: Calendar
    ) -> TrendSeriesData {
        prepare(
            benchmarks: benchmarks,
            costHistory: costHistory,
            rankedModelIDs: rankedModelIDs,
            metric: metric,
            days: days,
            now: now,
            calendar: calendar
        )
        .selecting(savedModelIDs: savedModelIDs)
    }
}

public enum TrendPointBuilder {
    /// Builds chart-ready points by retaining the latest valid source snapshot
    /// for each model and device-calendar day.
    public static func points(
        benchmarks: [ModelBenchmark],
        costHistory: [CostHistoryPoint],
        metric: RankingMetric,
        modelIDs: [String],
        calendar: Calendar = .current
    ) -> [TrendPoint] {
        guard metric != .overall else { return [] }

        let selected = Set(modelIDs)
        let dateParser = SourceDateParser(calendar: calendar)
        return benchmarks
            .filter { selected.contains($0.id) }
            .flatMap { benchmark in
                let remotePoints = remotePoints(
                    for: benchmark,
                    metric: metric,
                    calendar: calendar,
                    dateParser: dateParser
                )
                guard metric == .cost, remotePoints.isEmpty else { return remotePoints }
                return localCostPoints(for: benchmark, costHistory: costHistory, calendar: calendar)
            }
            .sorted(by: pointOrdering)
    }

    /// Projects arbitrary source observations to one latest valid observation
    /// per model/calendar day. Invalid or undated observations cannot be drawn.
    public static func dailyPoints(
        _ points: [TrendPoint],
        calendar: Calendar = .current
    ) -> [TrendPoint] {
        var latestByDay: [DailyKey: TrendPoint] = [:]

        for point in points where point.value.isFinite {
            guard let recordedAt = point.recordedAt ?? point.day else { continue }
            let day = calendar.startOfDay(for: recordedAt)
            let normalized = TrendPoint(
                modelID: point.modelID,
                modelLabel: point.modelLabel,
                dateKey: point.dateKey,
                sequence: point.sequence,
                value: point.value,
                recordedAt: point.recordedAt,
                day: day
            )
            let key = DailyKey(modelID: point.modelID, day: day)

            guard let existing = latestByDay[key] else {
                latestByDay[key] = normalized
                continue
            }

            if isLater(normalized, than: existing) {
                latestByDay[key] = normalized
            }
        }

        return latestByDay.values.sorted(by: pointOrdering)
    }

    public static func hasDrawableSeries(
        _ points: [TrendPoint],
        calendar: Calendar = .current
    ) -> Bool {
        Dictionary(grouping: dailyPoints(points, calendar: calendar), by: \.modelID)
            .values
            .contains { $0.count >= 2 }
    }

    /// Filters after daily aggregation so a range never contains several
    /// snapshots for a single chart day.
    public static func recentPoints(
        _ points: [TrendPoint],
        days: Int,
        now: Date,
        calendar: Calendar
    ) -> [TrendPoint] {
        guard days > 0,
              let cutoff = calendar.date(
                  byAdding: .day,
                  value: -(days - 1),
                  to: calendar.startOfDay(for: now)
              ) else { return [] }

        let today = calendar.startOfDay(for: now)
        return dailyPoints(points, calendar: calendar).filter { point in
            guard let day = point.day else { return false }
            return day >= cutoff && day <= today
        }
    }

    /// Returns no more than `maximumCount` evenly-spaced device-calendar days
    /// for a readable date axis.
    public static func axisDays(
        _ points: [TrendPoint],
        maximumCount: Int = 4,
        calendar: Calendar = .current
    ) -> [Date] {
        let days = Array(Set(dailyPoints(points, calendar: calendar).compactMap(\.day))).sorted()
        return axisDays(days, maximumCount: maximumCount)
    }

    /// Selects readable axis values from chart days that have already been
    /// normalized, deduplicated, and sorted during series preparation.
    public static func axisDays(
        _ sortedDays: [Date],
        maximumCount: Int = 4
    ) -> [Date] {
        guard maximumCount > 0 else { return [] }
        let days = sortedDays
        guard days.count > maximumCount, maximumCount > 1 else {
            return Array(days.prefix(maximumCount))
        }

        let lastIndex = days.count - 1
        let denominator = maximumCount - 1
        return (0..<maximumCount).map { index in
            let scaledIndex = Double(index) * Double(lastIndex) / Double(denominator)
            return days[Int(scaledIndex.rounded())]
        }
    }

    /// Finds the existing chart day nearest to an interaction location. Ties
    /// choose the earlier day, which keeps hover behavior deterministic.
    public static func nearestDay(
        to date: Date,
        in points: [TrendPoint],
        calendar: Calendar = .current
    ) -> Date? {
        nearestDay(
            to: date,
            inSortedDays: axisCandidates(points, calendar: calendar)
        )
    }

    /// Finds a hover target with a binary search over prepared chart days.
    /// Ties choose the earlier day for deterministic pointer behavior.
    public static func nearestDay(
        to date: Date,
        inSortedDays days: [Date]
    ) -> Date? {
        guard !days.isEmpty else { return nil }

        var lowerBound = 0
        var upperBound = days.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if days[middle] < date {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        guard lowerBound > 0 else { return days[0] }
        guard lowerBound < days.count else { return days[days.count - 1] }

        let earlier = days[lowerBound - 1]
        let later = days[lowerBound]
        let earlierDistance = date.timeIntervalSince(earlier)
        let laterDistance = later.timeIntervalSince(date)
        return earlierDistance <= laterDistance ? earlier : later
    }

    public static func shortDateLabel(_ dateKey: String) -> String {
        let trimmed = dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 16 {
            let dateEnd = trimmed.index(trimmed.startIndex, offsetBy: 10)
            let separator = trimmed[dateEnd]
            if separator == "T" || separator == "t" || separator == " " {
                let date = trimmed[..<dateEnd].split(separator: "-")
                let timeStart = trimmed.index(after: dateEnd)
                let timeEnd = trimmed.index(timeStart, offsetBy: 5, limitedBy: trimmed.endIndex)
                if date.count == 3, let timeEnd {
                    return "\(date[1])/\(date[2]) \(trimmed[timeStart..<timeEnd])"
                }
            }
        }
        let base = dateKey.split(separator: "_").first.map(String.init) ?? dateKey
        let components = base.split(separator: "-")
        guard components.count >= 4 else { return dateKey }
        let month = components[1]
        let day = components[2]
        let session = components[3].uppercased()
        return "\(month)/\(day) \(session)"
    }

    private static func remotePoints(
        for benchmark: ModelBenchmark,
        metric: RankingMetric,
        calendar: Calendar,
        dateParser: SourceDateParser
    ) -> [TrendPoint] {
        let observations = benchmark.recentDays.enumerated().compactMap { index, record -> TrendPoint? in
            guard let value = value(in: record, for: metric), value.isFinite,
                  let recordedAt = dateParser.date(from: record.date) else { return nil }
            return TrendPoint(
                modelID: benchmark.id,
                modelLabel: benchmark.label,
                dateKey: record.date,
                sequence: index,
                value: value,
                recordedAt: recordedAt,
                day: calendar.startOfDay(for: recordedAt)
            )
        }
        return dailyPoints(observations, calendar: calendar)
    }

    private static func localCostPoints(
        for benchmark: ModelBenchmark,
        costHistory: [CostHistoryPoint],
        calendar: Calendar
    ) -> [TrendPoint] {
        let observations = costHistory
            .filter { $0.modelID == benchmark.id && $0.costUSD.isFinite }
            .sorted {
                if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
                return $0.dateKey < $1.dateKey
            }
            .enumerated()
            .map { index, point in
                TrendPoint(
                    modelID: benchmark.id,
                    modelLabel: benchmark.label,
                    dateKey: point.dateKey,
                    sequence: index,
                    value: point.costUSD,
                    recordedAt: point.recordedAt,
                    day: calendar.startOfDay(for: point.recordedAt)
                )
            }
        return dailyPoints(observations, calendar: calendar)
    }

    private static func value(in record: BenchmarkRecord, for metric: RankingMetric) -> Double? {
        switch metric {
        case .iq:
            record.score
        case .cost:
            record.costUSD
        case .duration:
            record.wallSeconds
        case .overall:
            nil
        }
    }

    private static func axisCandidates(_ points: [TrendPoint], calendar: Calendar) -> [Date] {
        Array(Set(dailyPoints(points, calendar: calendar).compactMap(\.day))).sorted()
    }

    private static func isLater(_ lhs: TrendPoint, than rhs: TrendPoint) -> Bool {
        switch (lhs.recordedAt, rhs.recordedAt) {
        case let (left?, right?) where left != right:
            return left > right
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            break
        }
        if lhs.sequence != rhs.sequence { return lhs.sequence > rhs.sequence }
        return lhs.dateKey > rhs.dateKey
    }

    private static func pointOrdering(_ lhs: TrendPoint, _ rhs: TrendPoint) -> Bool {
        if lhs.modelID != rhs.modelID { return lhs.modelID < rhs.modelID }
        if lhs.day != rhs.day {
            switch (lhs.day, rhs.day) {
            case let (left?, right?):
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }
        }
        switch (lhs.recordedAt, rhs.recordedAt) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }
        if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
        return lhs.dateKey < rhs.dateKey
    }

    private struct DailyKey: Hashable {
        let modelID: String
        let day: Date
    }

    /// `ISO8601DateFormatter` is reference-typed and not Sendable, so it stays
    /// confined to the synchronous build invocation instead of becoming a
    /// shared static formatter. One pair is reused for the whole snapshot.
    private final class SourceDateParser {
        private let calendar: Calendar
        private let fractionalFormatter: ISO8601DateFormatter
        private let standardFormatter: ISO8601DateFormatter

        init(calendar: Calendar) {
            self.calendar = calendar
            fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]
        }

        func date(from dateKey: String) -> Date? {
            let trimmed = dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let date = fractionalFormatter.date(from: trimmed)
                ?? standardFormatter.date(from: trimmed) {
                return date
            }

            guard trimmed.count >= 10 else { return nil }
            let dateEnd = trimmed.index(trimmed.startIndex, offsetBy: 10)
            let components = trimmed[..<dateEnd].split(separator: "-")
            guard components.count == 3,
                  let year = Int(components[0]),
                  let month = Int(components[1]),
                  let day = Int(components[2]) else { return nil }

            let lowercased = trimmed.lowercased()
            let hour = lowercased.contains("-pm") || lowercased.contains("_pm") ? 12 : 0
            return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
        }
    }
}
