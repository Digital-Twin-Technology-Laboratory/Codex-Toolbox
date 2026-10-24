import Foundation

public enum TaskQuotaMetric: Int, Codable, CaseIterable, Sendable {
    case weekly = 10080, fiveHour = 300
    public var displayName: String { self == .weekly ? "周" : "5小时" }
    public static func supported(by windows: [AccountQuotaWindow]) -> [Self] {
        let durations = Set(windows.map(\.durationMinutes))
        return allCases.filter { durations.contains($0.rawValue) }
    }
}

public struct NativeTaskUsageRow: Codable, Equatable, Sendable {
    public let id: String
    public let status: String
    public let usageSource: String
    public let fiveHourPercent: Double?
    public let weeklyPercent: Double?
    public let groups: [Group]
    public struct Group: Codable, Equatable, Sendable {
        public let product: String?
        public let model: String?
        public let effort: String?
        public let speed: String?
        public let fiveHourPercent: Double?
        public let weeklyPercent: Double?
    }
    public func percent(_ metric: TaskQuotaMetric) -> Double? {
        metric == .weekly ? weeklyPercent : fiveHourPercent
    }
}

public struct NativeTaskUsageReport: Decodable, Sendable {
    public let schemaVersion: Int
    public let accountKey: String
    public let planType: String?
    public let collectedAt: String
    public let dataAsOf: String?
    public let threads: [NativeTaskUsageRow]
    public static func decode(_ data: Data) throws -> Self {
        let report = try JSONDecoder().decode(Self.self, from: data)
        let values = report.threads.flatMap { row in
            [row.fiveHourPercent, row.weeklyPercent] + row.groups.flatMap { [$0.fiveHourPercent, $0.weeklyPercent] }
        }.compactMap { $0 }
        guard report.schemaVersion == 3, report.accountKey.count == 64, report.accountKey.allSatisfy(\.isHexDigit),
              let collected = MetricFormatter.sourceDate(report.collectedAt), collected <= Date().addingTimeInterval(300),
              report.dataAsOf == nil || report.dataAsOf.flatMap(MetricFormatter.sourceDate).map({ $0 <= collected }) == true,
              report.threads.count <= 100, Set(report.threads.map(\.id)).count == report.threads.count,
              report.threads.allSatisfy({ ["available", "partial", "unavailable"].contains($0.status) }),
              values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw NativeAnalyticsError.invalidResponse }
        return report
    }
}

public struct NativeTaskQuotaSnapshot: Codable, Equatable, Sendable {
    public let accountKey: String
    public let thread: NativeThread
    public let row: NativeTaskUsageRow
    public let collectedAt: Date
    public let dataAsOf: Date?
    public let planType: String?
    public let timezoneIdentifier: String
    public let continuityID: String
    public init(accountKey: String, thread: NativeThread, row: NativeTaskUsageRow, collectedAt: Date, dataAsOf: Date?, planType: String?, timezoneIdentifier: String, continuityID: String) {
        self.accountKey = accountKey; self.thread = thread; self.row = row; self.collectedAt = collectedAt
        self.dataAsOf = dataAsOf; self.planType = planType; self.timezoneIdentifier = timezoneIdentifier; self.continuityID = continuityID
    }
    public var effectiveAt: Date { dataAsOf ?? collectedAt }
    public var epoch: String { "\(planType ?? "unknown")|\(row.usageSource)|\(thread.scopeKey)|\(continuityID)" }
}

public struct DailyTaskQuotaValue: Codable, Equatable, Sendable {
    public let percent: Double
    public let isExact: Bool
    public let updatedAt: Date
    public let help: String
    public init(percent: Double, isExact: Bool, updatedAt: Date, help: String) {
        self.percent = percent; self.isExact = isExact; self.updatedAt = updatedAt; self.help = help
    }
    public var comparison: String { isExact ? "=" : "≈" }
    public static func combined(_ values: [Self?]) -> Self? {
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        let known = values.compactMap { $0 }
        return Self(percent: known.reduce(0) { $0 + $1.percent }, isExact: known.allSatisfy(\.isExact),
                    updatedAt: known.map(\.updatedAt).min()!, help: known.map(\.help).joined(separator: "；"))
    }
}

public enum DailyTaskQuotaAnalyzer {
    private struct Interval {
        let start: NativeTaskQuotaSnapshot
        let end: NativeTaskQuotaSnapshot
        let percent: Double
        let observations: [LocalQuotaUsageObservation]
        let baselineAt: Date
        let weight: Double
        init(start: NativeTaskQuotaSnapshot, end: NativeTaskQuotaSnapshot, percent: Double,
             observations: [LocalQuotaUsageObservation], baselineAt: Date) {
            self.start = start; self.end = end; self.percent = percent
            self.observations = observations; self.baselineAt = baselineAt
            self.weight = observations.reduce(0) { $0 + Double($1.tokenIncrement) }
        }
    }
    public static func values(history: UsageHistory, snapshots: [NativeTaskQuotaSnapshot], accountKey: String, now: Date) -> [Int: [String: DailyTaskQuotaValue]] {
        guard !Task.isCancelled else { return [:] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: history.timezoneIdentifier) ?? .current
        let scoped = snapshots.filter { $0.accountKey == accountKey && $0.timezoneIdentifier == history.timezoneIdentifier && $0.collectedAt <= now }
        let byRoot = Dictionary(grouping: scoped, by: { $0.thread.id }).mapValues {
            $0.sorted { $0.collectedAt < $1.collectedAt }
        }
        let local = Dictionary(grouping: history.quotaObservations.filter { !$0.isAccountSnapshot && $0.tokenIncrement > 0 }, by: \.rootTaskID)
        let dayBounds = history.days.compactMap { day -> (DailyUsageSummary, Date, Date)? in
            guard let start = date(day.dateKey, calendar: calendar),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return (day, start, end)
        }
        var result: [Int: [String: DailyTaskQuotaValue]] = [:]
        for metric in TaskQuotaMetric.allCases {
            guard !Task.isCancelled else { return [:] }
            var intervals: [String: [Interval]] = [:]
            var baselines: [String: [Date: Date]] = [:]
            for (root, sorted) in byRoot {
                guard !Task.isCancelled else { return [:] }
                guard let first = sorted.first else { continue }
                var baselineAt = first.collectedAt
                baselines[root, default: [:]][first.collectedAt] = baselineAt
                // Corrections and backwards watermarks create a baseline, never a negative usage day.
                for (a, b) in zip(sorted, sorted.dropFirst()) {
                    guard !Task.isCancelled else { return [:] }
                    let unchanged = a.epoch == b.epoch && a.row.status == "available" && b.row.status == "available"
                        && a.effectiveAt == b.effectiveAt && a.row.percent(metric) == b.row.percent(metric)
                    guard a.epoch == b.epoch, a.row.status == "available", b.row.status == "available",
                          b.effectiveAt > a.effectiveAt, b.collectedAt.timeIntervalSince(a.collectedAt) <= 15 * 60,
                          let first = a.row.percent(metric), let last = b.row.percent(metric), last >= first else {
                        if !unchanged { baselineAt = b.collectedAt }
                        baselines[root, default: [:]][b.collectedAt] = baselineAt
                        continue
                    }
                    baselines[root, default: [:]][b.collectedAt] = baselineAt
                    let source = local[root] ?? []
                    let lower = SortedSearch.firstIndex(in: source) { $0.timestamp > a.effectiveAt }
                    let upper = SortedSearch.firstIndex(in: source) { $0.timestamp > b.effectiveAt }
                    let rows = source[lower..<upper].filter {
                        $0.timestamp > a.effectiveAt && $0.timestamp <= b.effectiveAt
                            && $0.executionContext?.authenticationMode == .chatGPT
                            && ($0.accountKey == nil || $0.accountKey == accountKey)
                    }
                    intervals[root, default: []].append(Interval(start: a, end: b, percent: last - first, observations: rows, baselineAt: baselineAt))
                }
            }
            let rates = calibrationRates(intervals: intervals)
            for (day, start, end) in dayBounds {
                guard !Task.isCancelled else { return [:] }
                for task in day.tasks {
                    guard !Task.isCancelled else { return [:] }
                    guard let samples = byRoot[task.rootTaskID],
                          let latest = samples.last(where: { $0.row.status != "unavailable" }) else { continue }
                    let through = min(now, end)
                    let dayScope = samples.last(where: { $0.row.status != "unavailable" && $0.effectiveAt <= through }) ?? latest
                    let daySamples = samples.filter { $0.row.status != "unavailable" && $0.effectiveAt >= start && $0.effectiveAt < end }
                    if let native = daySamples.last, native.row.status == "available", let percent = native.row.percent(metric),
                       let birth = native.thread.earliestCreatedAt.flatMap(MetricFormatter.sourceDate), birth >= start, birth <= native.effectiveAt {
                        result[metric.rawValue, default: [:]][task.id] = DailyTaskQuotaValue(percent: percent, isExact: true,
                            updatedAt: native.collectedAt, help: "当前账户；同日新建任务的完整原生记录，包含子代理。数据截至 \(MetricFormatter.chineseAccountDate(native.effectiveAt))。")
                        continue
                    }
                    let observed = (intervals[task.rootTaskID] ?? []).filter {
                        $0.start.effectiveAt >= start && $0.end.effectiveAt <= through
                            && $0.baselineAt == baselines[task.rootTaskID]?[dayScope.collectedAt]
                    }
                    let measured = observed.reduce(0) { $0 + $1.percent }
                    let exactBoundary = observed.first.map { $0.start.effectiveAt == start } == true
                        && observed.last.map { $0.end.effectiveAt == through } == true
                        && observed.allSatisfy { $0.start.dataAsOf != nil && $0.end.dataAsOf != nil && $0.start.planType != nil }
                        && zip(observed, observed.dropFirst()).allSatisfy { pair in
                            pair.0.end.effectiveAt == pair.1.start.effectiveAt && pair.0.end.epoch == pair.1.start.epoch
                                && pair.0.end.row.percent(metric) == pair.1.start.row.percent(metric)
                        }
                    if exactBoundary, let last = observed.last {
                        result[metric.rawValue, default: [:]][task.id] = DailyTaskQuotaValue(percent: measured, isExact: true,
                            updatedAt: last.end.collectedAt, help: "当前账户；完整覆盖当日边界的原生快照差值。")
                        continue
                    }
                    // Retain the old calibrated-rate approach, using account-scoped native steps.
                    // No historical rollout record receives the currently logged-in account ID.
                    let source = local[task.rootTaskID] ?? []
                    let lower = SortedSearch.firstIndex(in: source) { $0.timestamp >= start }
                    let upper = SortedSearch.firstIndex(in: source) { $0.timestamp >= through }
                    let rows = lower < upper ? Array(source[lower..<upper]) : []
                    let canInfer = !rows.isEmpty && rows.allSatisfy {
                        $0.executionContext?.authenticationMode == .chatGPT && ($0.accountKey == nil || $0.accountKey == accountKey)
                    } && tokenTotal(rows) == task.tokens
                    if canInfer, let inferred = calibratedPercent(rows: rows, rates: rates, scope: dayScope) {
                        result[metric.rawValue, default: [:]][task.id] = DailyTaskQuotaValue(percent: max(measured, inferred), isExact: false,
                            updatedAt: latest.collectedAt, help: "当前账户原生差值校准本机逐轮 Token 的当日估算；账户归属未知的历史未被回填。并发、其他设备及模型变化可能影响精度。")
                    } else if let last = observed.last {
                        result[metric.rawValue, default: [:]][task.id] = DailyTaskQuotaValue(percent: measured, isExact: false,
                            updatedAt: last.end.collectedAt, help: "当前账户；当日已采样区间的增量，未完整覆盖全天。首次基线、缺测或延迟会影响精度。")
                    }
                }
            }
        }
        return Task.isCancelled ? [:] : result
    }
    private static func contextKey(_ row: LocalQuotaUsageObservation) -> String {
        let c = row.executionContext
        return "\(c?.modelID ?? "unknown")|\(c?.reasoningEffort ?? "unknown")|\(c?.serviceTier ?? "unknown")"
    }
    private struct CalibrationScope: Hashable {
        let plan: String
        let source: String
    }
    private static func calibrationRates(intervals: [String: [Interval]]) -> [CalibrationScope: [String: Double]] {
        var grouped: [CalibrationScope: [String: [Double]]] = [:]
        for group in intervals.values {
            guard !Task.isCancelled else { return [:] }
            for interval in group where interval.percent > 0 && interval.weight > 0 {
                guard let plan = interval.end.planType else { continue }
                let keys = Set(interval.observations.map(contextKey))
                let rate = interval.weight / interval.percent
                guard keys.count == 1, let key = keys.first, rate.isFinite && rate > 0 else { continue }
                grouped[CalibrationScope(plan: plan, source: interval.end.row.usageSource), default: [:]][key, default: []].append(rate)
            }
        }
        return grouped.mapValues { contexts in
            contexts.mapValues { values in
                let ordered = values.sorted()
                let median = ordered[ordered.count / 2]
                let clean = ordered.count >= 5 ? ordered.filter { $0 >= median / 4 && $0 <= median * 4 } : ordered
                return clean[clean.count / 2]
            }
        }
    }
    private static func tokenTotal(_ rows: [LocalQuotaUsageObservation]) -> Int64? {
        var total: Int64 = 0
        for row in rows {
            let (next, overflow) = total.addingReportingOverflow(row.tokenIncrement)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
    private static func calibratedPercent(rows: [LocalQuotaUsageObservation], rates: [CalibrationScope: [String: Double]], scope: NativeTaskQuotaSnapshot) -> Double? {
        guard let plan = scope.planType, let rates = rates[CalibrationScope(plan: plan, source: scope.row.usageSource)] else { return nil }
        var total = 0.0
        for (key, group) in Dictionary(grouping: rows, by: contextKey) {
            guard !Task.isCancelled, let rate = rates[key] else { return nil }
            total += group.reduce(0) { $0 + Double($1.tokenIncrement) } / rate
        }
        return total.isFinite ? total : nil
    }
    private static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    public static func batches(_ threads: [NativeThread]) -> [[NativeThread]] {
        var batches: [[NativeThread]] = []; var batch: [NativeThread] = []; var count = 0
        for thread in threads {
            let size = 1 + thread.descendantIDs.count
            guard size <= 1000 else { continue }
            if batch.count == 100 || count + size > 1000 { batches.append(batch); batch = []; count = 0 }
            batch.append(thread); count += size
        }
        if !batch.isEmpty { batches.append(batch) }
        return batches
    }
}
