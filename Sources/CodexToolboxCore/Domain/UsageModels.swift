import Foundation

public struct DailyTaskUsage: Codable, Hashable, Identifiable, Sendable {
    public let dateKey: String
    public let rootTaskID: String
    public let title: String
    public let tokens: Int64
    public let descendantCount: Int

    public var id: String { "\(dateKey)|\(rootTaskID)" }

    public init(
        dateKey: String,
        rootTaskID: String,
        title: String,
        tokens: Int64,
        descendantCount: Int
    ) {
        self.dateKey = dateKey
        self.rootTaskID = rootTaskID
        self.title = title
        self.tokens = tokens
        self.descendantCount = descendantCount
    }
}

public struct DailyUsageSummary: Codable, Hashable, Identifiable, Sendable {
    public let dateKey: String
    public let totalTokens: Int64
    public let tasks: [DailyTaskUsage]
    public let isComplete: Bool

    public var id: String { dateKey }

    public init(
        dateKey: String,
        totalTokens: Int64,
        tasks: [DailyTaskUsage],
        isComplete: Bool
    ) {
        self.dateKey = dateKey
        self.totalTokens = totalTokens
        self.tasks = tasks.sorted {
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            return $0.rootTaskID < $1.rootTaskID
        }
        self.isComplete = isComplete
    }

    public func topTasks(limit: Int = 3) -> [DailyTaskUsage] {
        Array(tasks.prefix(max(0, limit)))
    }

    public func remainingTokens(afterTop limit: Int = 3) -> Int64 {
        max(0, totalTokens - topTasks(limit: limit).reduce(0) { $0 + $1.tokens })
    }
}

public struct LocalQuotaUsageObservation: Codable, Hashable, Sendable {
    public let timestamp: Date
    public let rootTaskID: String
    public let tokenIncrement: Int64
    public let windows: [AccountQuotaWindow]

    public init(
        timestamp: Date,
        rootTaskID: String,
        tokenIncrement: Int64,
        windows: [AccountQuotaWindow]
    ) {
        self.timestamp = timestamp
        self.rootTaskID = rootTaskID
        self.tokenIncrement = max(0, tokenIncrement)
        self.windows = windows.sorted { $0.durationMinutes < $1.durationMinutes }
    }
}

public enum QuotaEstimateConfidence: String, Codable, Hashable, Sendable {
    case low
    case medium

    public var displayName: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        }
    }
}

public struct TaskQuotaEstimate: Codable, Hashable, Sendable {
    public let window: AccountQuotaWindow
    public let percent: Double
    public let confidence: QuotaEstimateConfidence
    public let observedStepCount: Int
    public let observedTokenCoverage: Double

    public init(
        window: AccountQuotaWindow,
        percent: Double,
        confidence: QuotaEstimateConfidence,
        observedStepCount: Int,
        observedTokenCoverage: Double
    ) {
        self.window = window
        self.percent = max(0, percent)
        self.confidence = confidence
        self.observedStepCount = max(0, observedStepCount)
        self.observedTokenCoverage = min(1, max(0, observedTokenCoverage))
    }
}

public struct UsageHistory: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let timezoneIdentifier: String
    public let days: [DailyUsageSummary]
    public let warnings: [String]
    public let quotaObservations: [LocalQuotaUsageObservation]

    public init(
        generatedAt: Date,
        timezoneIdentifier: String,
        days: [DailyUsageSummary],
        warnings: [String] = [],
        quotaObservations: [LocalQuotaUsageObservation] = []
    ) {
        self.generatedAt = generatedAt
        self.timezoneIdentifier = timezoneIdentifier
        self.days = days.sorted { $0.dateKey < $1.dateKey }
        self.warnings = warnings
        self.quotaObservations = quotaObservations.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.rootTaskID < $1.rootTaskID
        }
    }

    public func summary(for dateKey: String) -> DailyUsageSummary? {
        days.first { $0.dateKey == dateKey }
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case timezoneIdentifier
        case days
        case warnings
        case quotaObservations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            timezoneIdentifier: try container.decode(String.self, forKey: .timezoneIdentifier),
            days: try container.decode([DailyUsageSummary].self, forKey: .days),
            warnings: try container.decodeIfPresent([String].self, forKey: .warnings) ?? [],
            quotaObservations: try container.decodeIfPresent(
                [LocalQuotaUsageObservation].self,
                forKey: .quotaObservations
            ) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encode(days, forKey: .days)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(quotaObservations, forKey: .quotaObservations)
    }
}

public enum TaskQuotaEstimator {
    private static let inactivityThreshold: TimeInterval = 15 * 60
    private static let resetTolerance: TimeInterval = 5 * 60
    private static let maximumCleanStep = 3.0
    private static let percentEpsilon = 0.000_001

    private struct Sample: Sendable {
        let timestamp: Date
        let rootTaskID: String
        let tokens: Int64
        let percent: Double
    }

    private struct Attribution {
        var totalTokensByTask: [String: Int64] = [:]
        var coveredTokensByTask: [String: Int64] = [:]
        var observedPercentByTask: [String: Double] = [:]
        var observedStepsByTask: [String: Int] = [:]
        var ratesByTask: [String: [Double]] = [:]
        var globalRates: [Double] = []
        var observedPercentagePoints = 0.0
    }

    private struct WindowKey: Hashable {
        let durationMinutes: Int
        let resetBucket: Int64
    }

    public static func estimates(
        history: UsageHistory,
        window: AccountQuotaWindow,
        now: Date
    ) -> [String: TaskQuotaEstimate] {
        guard now < window.resetsAt else { return [:] }
        let currentSamples = samples(
            observations: history.quotaObservations,
            matching: window,
            now: now
        )
        guard !currentSamples.isEmpty else { return [:] }

        let current = attribute(currentSamples)
        let historicalRates = calibrationRates(
            observations: history.quotaObservations,
            durationMinutes: window.durationMinutes,
            now: now
        )
        let currentGlobalRate = median(current.globalRates)
        let historicalRate = median(historicalRates)

        var raw: [String: TaskQuotaEstimate] = [:]
        for (taskID, totalTokens) in current.totalTokensByTask where totalTokens > 0 {
            let coveredTokens = min(totalTokens, current.coveredTokensByTask[taskID] ?? 0)
            let uncoveredTokens = max(0, totalTokens - coveredTokens)
            let taskRate = median(current.ratesByTask[taskID] ?? [])
            guard let rate = taskRate ?? currentGlobalRate ?? historicalRate,
                  rate > 0,
                  rate.isFinite else { continue }

            let observedPercent = current.observedPercentByTask[taskID] ?? 0
            let inferredPercent = Double(uncoveredTokens) / rate
            let estimate = observedPercent + inferredPercent
            guard estimate.isFinite else { continue }

            let coverage = Double(coveredTokens) / Double(totalTokens)
            let stepCount = current.observedStepsByTask[taskID] ?? 0
            let confidence: QuotaEstimateConfidence
            if current.observedPercentagePoints >= 10,
               stepCount >= 2,
               coverage >= 0.5 {
                confidence = .medium
            } else if !current.globalRates.isEmpty || historicalRate != nil {
                confidence = .low
            } else {
                continue
            }
            raw[taskID] = TaskQuotaEstimate(
                window: window,
                percent: estimate,
                confidence: confidence,
                observedStepCount: stepCount,
                observedTokenCoverage: coverage
            )
        }

        let totalRaw = raw.values.reduce(0) { $0 + $1.percent }
        let scale = totalRaw > window.usedPercent && totalRaw > 0
            ? window.usedPercent / totalRaw
            : 1
        return raw.mapValues { estimate in
            TaskQuotaEstimate(
                window: estimate.window,
                percent: estimate.percent * scale,
                confidence: estimate.confidence,
                observedStepCount: estimate.observedStepCount,
                observedTokenCoverage: estimate.observedTokenCoverage
            )
        }
    }

    private static func samples(
        observations: [LocalQuotaUsageObservation],
        matching window: AccountQuotaWindow,
        now: Date
    ) -> [Sample] {
        let windowStart = window.resetsAt.addingTimeInterval(
            -TimeInterval(window.durationMinutes * 60)
        )
        return observations.compactMap { observation in
            guard observation.timestamp >= windowStart,
                  observation.timestamp <= now,
                  observation.timestamp < window.resetsAt,
                  let observedWindow = observation.windows.first(where: {
                      $0.durationMinutes == window.durationMinutes
                          && abs($0.resetsAt.timeIntervalSince(window.resetsAt)) <= resetTolerance
                  }) else { return nil }
            return Sample(
                timestamp: observation.timestamp,
                rootTaskID: observation.rootTaskID,
                tokens: observation.tokenIncrement,
                percent: observedWindow.usedPercent
            )
        }.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.rootTaskID < $1.rootTaskID
        }
    }

    private static func attribute(_ samples: [Sample]) -> Attribution {
        var result = Attribution()
        var previous: Sample?
        var bucketTokensByTask: [String: Int64] = [:]

        for sample in samples {
            result.totalTokensByTask[sample.rootTaskID, default: 0] += sample.tokens
            guard let last = previous else {
                previous = sample
                continue
            }

            let gap = sample.timestamp.timeIntervalSince(last.timestamp)
            let percentDelta = sample.percent - last.percent
            guard gap >= 0,
                  gap <= inactivityThreshold,
                  percentDelta >= -percentEpsilon else {
                bucketTokensByTask.removeAll(keepingCapacity: true)
                previous = sample
                continue
            }

            bucketTokensByTask[sample.rootTaskID, default: 0] += sample.tokens
            if percentDelta > percentEpsilon {
                let bucketTotal = bucketTokensByTask.values.reduce(Int64(0), +)
                if percentDelta <= maximumCleanStep, bucketTotal > 0 {
                    let rate = Double(bucketTotal) / percentDelta
                    if rate.isFinite, rate > 0 {
                        result.globalRates.append(rate)
                        result.observedPercentagePoints += percentDelta
                        for (taskID, tokens) in bucketTokensByTask where tokens > 0 {
                            let share = Double(tokens) / Double(bucketTotal)
                            result.coveredTokensByTask[taskID, default: 0] += tokens
                            result.observedPercentByTask[taskID, default: 0] += percentDelta * share
                            result.observedStepsByTask[taskID, default: 0] += 1
                            result.ratesByTask[taskID, default: []].append(rate)
                        }
                    }
                }
                bucketTokensByTask.removeAll(keepingCapacity: true)
            }
            previous = sample
        }
        return result
    }

    private static func calibrationRates(
        observations: [LocalQuotaUsageObservation],
        durationMinutes: Int,
        now: Date
    ) -> [Double] {
        var grouped: [WindowKey: [Sample]] = [:]
        for observation in observations where observation.timestamp <= now {
            for window in observation.windows where window.durationMinutes == durationMinutes {
                let key = WindowKey(
                    durationMinutes: durationMinutes,
                    resetBucket: Int64(window.resetsAt.timeIntervalSince1970 / resetTolerance)
                )
                grouped[key, default: []].append(
                    Sample(
                        timestamp: observation.timestamp,
                        rootTaskID: observation.rootTaskID,
                        tokens: observation.tokenIncrement,
                        percent: window.usedPercent
                    )
                )
            }
        }
        return grouped.values.flatMap { attribute($0.sorted { $0.timestamp < $1.timestamp }).globalRates }
    }

    private static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

public protocol CodexUsageReading: Sendable {
    func readUsage(now: Date, calendar: Calendar) async throws -> UsageHistory
}

public protocol UsageHistoryClearing: Sendable {
    func clearHistory() async throws
}

public protocol UsageHistoryStoring: Sendable {
    func load() async throws -> UsageHistory?
    func save(_ history: UsageHistory) async throws
    func clear() async throws
}
