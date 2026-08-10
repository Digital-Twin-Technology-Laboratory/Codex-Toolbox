import Foundation

public struct DailyTaskUsage: Codable, Hashable, Identifiable, Sendable {
    public let dateKey: String
    public let rootTaskID: String
    public let title: String
    public let tokens: Int64
    public let credits: Double?
    public let creditPrecision: CreditEstimatePrecision?
    public let descendantCount: Int

    public var id: String { "\(dateKey)|\(rootTaskID)" }

    public init(
        dateKey: String,
        rootTaskID: String,
        title: String,
        tokens: Int64,
        credits: Double? = nil,
        creditPrecision: CreditEstimatePrecision? = nil,
        descendantCount: Int
    ) {
        self.dateKey = dateKey
        self.rootTaskID = rootTaskID
        self.title = title
        self.tokens = tokens
        self.credits = credits.flatMap { $0.isFinite ? max(0, $0) : nil }
        self.creditPrecision = creditPrecision
        self.descendantCount = descendantCount
    }
}

public struct DailyUsageSummary: Codable, Hashable, Identifiable, Sendable {
    public let dateKey: String
    public let totalTokens: Int64
    public let totalCredits: Double?
    public let creditPrecision: CreditEstimatePrecision?
    public let tasks: [DailyTaskUsage]
    public let isComplete: Bool

    public var id: String { dateKey }

    public init(
        dateKey: String,
        totalTokens: Int64,
        totalCredits: Double? = nil,
        creditPrecision: CreditEstimatePrecision? = nil,
        tasks: [DailyTaskUsage],
        isComplete: Bool
    ) {
        self.dateKey = dateKey
        self.totalTokens = totalTokens
        self.totalCredits = totalCredits.flatMap { $0.isFinite ? max(0, $0) : nil }
        self.creditPrecision = creditPrecision
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
    public let quotaUsageWeight: Double?
    public let tokenBreakdown: UsageTokenBreakdown?
    public let executionContext: UsageExecutionContext?
    public let creditEstimate: TokenCreditEstimate?
    public let isAccountSnapshot: Bool
    public let windows: [AccountQuotaWindow]

    public init(
        timestamp: Date,
        rootTaskID: String,
        tokenIncrement: Int64,
        quotaUsageWeight: Double? = nil,
        tokenBreakdown: UsageTokenBreakdown? = nil,
        executionContext: UsageExecutionContext? = nil,
        creditEstimate: TokenCreditEstimate? = nil,
        isAccountSnapshot: Bool = false,
        windows: [AccountQuotaWindow]
    ) {
        self.timestamp = timestamp
        self.rootTaskID = rootTaskID
        self.tokenIncrement = max(0, tokenIncrement)
        self.quotaUsageWeight = quotaUsageWeight.flatMap {
            $0.isFinite ? max(0, $0) : nil
        }
        self.tokenBreakdown = tokenBreakdown
        self.executionContext = executionContext
        self.creditEstimate = creditEstimate
        self.isAccountSnapshot = isAccountSnapshot
        self.windows = windows.sorted { $0.durationMinutes < $1.durationMinutes }
    }

    public var calibrationWeight: Double {
        creditEstimate?.credits ?? quotaUsageWeight ?? Double(tokenIncrement)
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case rootTaskID
        case tokenIncrement
        case quotaUsageWeight
        case tokenBreakdown
        case executionContext
        case creditEstimate
        case isAccountSnapshot
        case windows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            rootTaskID: try container.decode(String.self, forKey: .rootTaskID),
            tokenIncrement: try container.decode(Int64.self, forKey: .tokenIncrement),
            quotaUsageWeight: try container.decodeIfPresent(Double.self, forKey: .quotaUsageWeight),
            tokenBreakdown: try container.decodeIfPresent(UsageTokenBreakdown.self, forKey: .tokenBreakdown),
            executionContext: try container.decodeIfPresent(UsageExecutionContext.self, forKey: .executionContext),
            creditEstimate: try container.decodeIfPresent(TokenCreditEstimate.self, forKey: .creditEstimate),
            isAccountSnapshot: try container.decodeIfPresent(Bool.self, forKey: .isAccountSnapshot) ?? false,
            windows: try container.decode([AccountQuotaWindow].self, forKey: .windows)
        )
    }
}

public enum QuotaEstimateConfidence: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high

    public var displayName: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

public struct TaskQuotaEstimate: Codable, Hashable, Sendable {
    public let window: AccountQuotaWindow
    public let percent: Double
    public let confidence: QuotaEstimateConfidence
    public let observedStepCount: Int
    public let observedTokenCoverage: Double
    public let hasConcurrentInterference: Bool

    public init(
        window: AccountQuotaWindow,
        percent: Double,
        confidence: QuotaEstimateConfidence,
        observedStepCount: Int,
        observedTokenCoverage: Double,
        hasConcurrentInterference: Bool = false
    ) {
        self.window = window
        self.percent = max(0, percent)
        self.confidence = confidence
        self.observedStepCount = max(0, observedStepCount)
        self.observedTokenCoverage = min(1, max(0, observedTokenCoverage))
        self.hasConcurrentInterference = hasConcurrentInterference
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

    public var lastLocalActivityAt: Date? {
        quotaObservations
            .filter { !$0.isAccountSnapshot && $0.tokenIncrement > 0 }
            .map(\.timestamp)
            .max()
    }

    public func appendingAccountSnapshot(
        timestamp: Date,
        planType: String?,
        windows: [AccountQuotaWindow]
    ) -> UsageHistory {
        guard !windows.isEmpty else { return self }
        let observation = LocalQuotaUsageObservation(
            timestamp: timestamp,
            rootTaskID: "__account__",
            tokenIncrement: 0,
            executionContext: UsageExecutionContext(
                modelID: nil,
                reasoningEffort: nil,
                serviceTier: nil,
                planType: planType,
                hasAccountRateLimits: true
            ),
            isAccountSnapshot: true,
            windows: windows
        )
        let minute = Int64(timestamp.timeIntervalSince1970 / 60)
        let retained = quotaObservations.filter {
            !$0.isAccountSnapshot
                || Int64($0.timestamp.timeIntervalSince1970 / 60) != minute
        }
        return UsageHistory(
            generatedAt: generatedAt,
            timezoneIdentifier: timezoneIdentifier,
            days: days,
            warnings: warnings,
            quotaObservations: retained + [observation]
        )
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
    private static let minimumBucketsForOutlierFiltering = 5
    private static let maximumRateDeviationFactor = 4.0
    private static let percentEpsilon = 0.000_001

    private struct Sample: Sendable {
        let timestamp: Date
        let dailyTaskID: String
        let usageWeight: Double
        let percent: Double
        let isAccountSnapshot: Bool
        let calibrationKey: String
        let hasCompleteCreditEvidence: Bool
    }

    private struct Attribution {
        var totalUsageByTask: [String: Double] = [:]
        var coveredUsageByTask: [String: Double] = [:]
        var observedPercentByTask: [String: Double] = [:]
        var observedStepsByTask: [String: Int] = [:]
        var globalRates: [Double] = []
        var observedPercentagePoints = 0.0
        var hasConcurrentInterference = false
        var hasIncompleteCreditEvidence = false
    }

    private struct Bucket: Sendable {
        let percentDelta: Double
        let usageByTask: [String: Double]

        var totalUsage: Double {
            usageByTask.values.reduce(0, +)
        }

        var rate: Double {
            totalUsage / percentDelta
        }
    }

    private struct WindowKey: Hashable {
        let durationMinutes: Int
        let resetBucket: Int64
        let calibrationKey: String
    }

    public static func estimates(
        history: UsageHistory,
        window: AccountQuotaWindow,
        now: Date
    ) -> [String: TaskQuotaEstimate] {
        guard now < window.resetsAt else { return [:] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: history.timezoneIdentifier) ?? .current
        let currentSamples = samples(
            observations: history.quotaObservations,
            matching: window,
            now: now,
            calendar: calendar
        )
        guard !currentSamples.isEmpty else { return [:] }

        let current = attribute(currentSamples)
        let historicalRates = calibrationRates(
            observations: history.quotaObservations,
            durationMinutes: window.durationMinutes,
            now: now,
            calendar: calendar
        )
        let currentGlobalRate = median(current.globalRates)
        let historicalRate = median(historicalRates)

        var raw: [String: TaskQuotaEstimate] = [:]
        for (taskID, totalUsage) in current.totalUsageByTask where totalUsage > 0 {
            let coveredUsage = min(totalUsage, current.coveredUsageByTask[taskID] ?? 0)
            let uncoveredUsage = max(0, totalUsage - coveredUsage)
            guard let rate = currentGlobalRate ?? historicalRate,
                  rate > 0,
                  rate.isFinite else { continue }

            let observedPercent = current.observedPercentByTask[taskID] ?? 0
            let inferredPercent = uncoveredUsage / rate
            let estimate = observedPercent + inferredPercent
            guard estimate.isFinite else { continue }

            let coverage = coveredUsage / totalUsage
            let stepCount = current.observedStepsByTask[taskID] ?? 0
            let confidence: QuotaEstimateConfidence
            if current.hasIncompleteCreditEvidence {
                confidence = .low
            } else if stepCount >= 5,
               coverage >= 0.8,
               !current.hasConcurrentInterference {
                confidence = .high
            } else if stepCount >= 2,
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
                observedTokenCoverage: coverage,
                hasConcurrentInterference: current.hasConcurrentInterference
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
                observedTokenCoverage: estimate.observedTokenCoverage,
                hasConcurrentInterference: estimate.hasConcurrentInterference
            )
        }
    }

    private static func samples(
        observations: [LocalQuotaUsageObservation],
        matching window: AccountQuotaWindow,
        now: Date,
        calendar: Calendar
    ) -> [Sample] {
        let windowStart = window.resetsAt.addingTimeInterval(
            -TimeInterval(window.durationMinutes * 60)
        )
        let eligible = observations.compactMap { observation -> (LocalQuotaUsageObservation, AccountQuotaWindow)? in
            guard observation.timestamp >= windowStart,
                  observation.timestamp <= now,
                  observation.timestamp < window.resetsAt,
                  let observedWindow = observation.windows.first(where: {
                      $0.durationMinutes == window.durationMinutes
                          && abs($0.resetsAt.timeIntervalSince(window.resetsAt)) <= resetTolerance
                  }) else { return nil }
            return (observation, observedWindow)
        }.sorted {
            if $0.0.timestamp != $1.0.timestamp { return $0.0.timestamp < $1.0.timestamp }
            return $0.0.rootTaskID < $1.0.rootTaskID
        }
        var nextLocalKeys = Array<String?>(repeating: nil, count: eligible.count)
        var nextLocalKey: String?
        for index in eligible.indices.reversed() {
            let observation = eligible[index].0
            if !observation.isAccountSnapshot {
                nextLocalKey = calibrationKey(for: observation)
            }
            nextLocalKeys[index] = nextLocalKey
        }
        var lastLocalKey: String?
        return eligible.enumerated().map { index, pair in
            let observation = pair.0
            let observedWindow = pair.1
            let dateKey = dayKey(observation.timestamp, calendar: calendar)
            let key: String
            if observation.isAccountSnapshot {
                key = lastLocalKey ?? nextLocalKeys[index] ?? "unknown|unknown"
            } else {
                key = calibrationKey(for: observation)
                lastLocalKey = key
            }
            return Sample(
                timestamp: observation.timestamp,
                dailyTaskID: "\(dateKey)|\(observation.rootTaskID)",
                usageWeight: observation.calibrationWeight,
                percent: observedWindow.usedPercent,
                isAccountSnapshot: observation.isAccountSnapshot,
                calibrationKey: key,
                hasCompleteCreditEvidence: observation.executionContext == nil
                    || observation.creditEstimate?.precision == .exact
            )
        }
    }

    private static func attribute(_ samples: [Sample]) -> Attribution {
        var result = Attribution()
        var previous: Sample?
        var bucketUsageByTask: [String: Double] = [:]
        var buckets: [Bucket] = []

        for sample in samples {
            if !sample.isAccountSnapshot {
                result.totalUsageByTask[sample.dailyTaskID, default: 0] += sample.usageWeight
                if !sample.hasCompleteCreditEvidence, sample.usageWeight > 0 {
                    result.hasIncompleteCreditEvidence = true
                }
            }
            guard let last = previous else {
                previous = sample
                continue
            }

            let gap = sample.timestamp.timeIntervalSince(last.timestamp)
            let percentDelta = sample.percent - last.percent
            guard gap >= 0,
                  gap <= inactivityThreshold,
                  sample.calibrationKey == last.calibrationKey,
                  percentDelta >= -percentEpsilon else {
                bucketUsageByTask.removeAll(keepingCapacity: true)
                previous = sample
                continue
            }

            if !sample.isAccountSnapshot, sample.usageWeight > 0 {
                bucketUsageByTask[sample.dailyTaskID, default: 0] += sample.usageWeight
            }
            if percentDelta > percentEpsilon {
                let bucket = Bucket(
                    percentDelta: percentDelta,
                    usageByTask: bucketUsageByTask
                )
                if bucket.totalUsage == 0 || percentDelta > maximumCleanStep {
                    result.hasConcurrentInterference = true
                } else if percentDelta <= maximumCleanStep,
                   bucket.totalUsage > 0,
                   bucket.rate.isFinite,
                   bucket.rate > 0 {
                    buckets.append(bucket)
                }
                bucketUsageByTask.removeAll(keepingCapacity: true)
            }
            previous = sample
        }

        let candidateMedian = median(buckets.map(\.rate))
        for bucket in buckets where isReliable(bucket, medianRate: candidateMedian, count: buckets.count) {
            result.globalRates.append(bucket.rate)
            result.observedPercentagePoints += bucket.percentDelta
            for (taskID, usage) in bucket.usageByTask where usage > 0 {
                let share = usage / bucket.totalUsage
                result.coveredUsageByTask[taskID, default: 0] += usage
                result.observedPercentByTask[taskID, default: 0] += bucket.percentDelta * share
                result.observedStepsByTask[taskID, default: 0] += 1
            }
        }
        return result
    }

    private static func isReliable(
        _ bucket: Bucket,
        medianRate: Double?,
        count: Int
    ) -> Bool {
        guard count >= minimumBucketsForOutlierFiltering,
              let medianRate,
              medianRate > 0 else { return true }
        let lowerBound = medianRate / maximumRateDeviationFactor
        let upperBound = medianRate * maximumRateDeviationFactor
        return bucket.rate >= lowerBound && bucket.rate <= upperBound
    }

    private static func calibrationRates(
        observations: [LocalQuotaUsageObservation],
        durationMinutes: Int,
        now: Date,
        calendar: Calendar
    ) -> [Double] {
        var windows: [WindowKey: AccountQuotaWindow] = [:]
        for observation in observations where observation.timestamp <= now {
            for window in observation.windows where window.durationMinutes == durationMinutes {
                let key = WindowKey(
                    durationMinutes: durationMinutes,
                    resetBucket: Int64(window.resetsAt.timeIntervalSince1970 / resetTolerance),
                    calibrationKey: "segmented"
                )
                windows[key] = window
            }
        }
        return windows.values.flatMap { window in
            attribute(
                samples(
                    observations: observations,
                    matching: window,
                    now: now,
                    calendar: calendar
                )
            ).globalRates
        }
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

    private static func calibrationKey(for observation: LocalQuotaUsageObservation) -> String {
        let plan = observation.executionContext?.planType ?? "unknown"
        let rate = observation.creditEstimate?.rateCardVersion ?? "unknown"
        return "\(plan)|\(rate)"
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

public protocol CodexUsageReading: Sendable {
    func readUsage(
        now: Date,
        calendar: Calendar,
        rateCard: RateCardManifest?,
        rateCardMode: RateCardMode
    ) async throws -> UsageHistory
}

public extension CodexUsageReading {
    func readUsage(
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> UsageHistory {
        try await readUsage(
            now: now,
            calendar: calendar,
            rateCard: nil,
            rateCardMode: .automatic
        )
    }
}

public protocol UsageHistoryClearing: Sendable {
    func clearHistory() async throws
}

public protocol AccountQuotaSnapshotRecording: Sendable {
    func recordAccountQuotaSnapshot(
        windows: [AccountQuotaWindow],
        planType: String?,
        timestamp: Date
    ) async throws
}

public protocol UsageHistoryStoring: Sendable {
    func load() async throws -> UsageHistory?
    func save(_ history: UsageHistory) async throws
    func clear() async throws
}
